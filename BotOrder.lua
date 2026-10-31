-- TortoiseBotsManager/BotOrder.lua
-- Guild orders: give a claimed guild bot a farm / buy / craft order from the
-- Guild tab and watch its progress live.
--
-- The server advertises "guild-orders" in TBM:CAPS. No capability: no Order
-- buttons, no window, no sends. Every CAPS line replaces the set, so the
-- gate is re-checked on each one (as BotLoot.lua does).
--
-- Contract (TortoiseBots#1384 "Guild orders: guild bank as the crafting store"):
-- the player sees live who does what and can step in from the addon.
-- Sends (byte-exact):
--   "order list"                                   -> full snapshot (orders
--     plus TBM:ORDER_ACCESS first inside the pair)
--   "order search <bot> <farm|buy|craft> [cat=<category>] <text>"
--   "order <bot> <farm|buy|craft> <itemId> <n> [hours|inf] [keep] [gold=<copper>]"
--     (gold omitted with no cap; an old server answering invalid sheds the
--     newest trailing field first: gold, then keep, then a refused inf
--     retries once as 24, then bare)
--   "order rank <rankIndex>"                        -> bots' guild rank (ACK
--     or ERR, then TBM:ORDER_ACCESS)
--   "order access"                                  -> TBM:ORDER_ACCESS now
--   "order reassign <subOrderBot> <newBot>"         -> hand a sub-order over
--   "order <bot> cancel"                            -> on a parent cancels
--     the whole branch
-- Inbound:
--   TBM:ORDER_BEGIN|<n>
--   TBM:ORDER|<bot>|<type>|<itemId>|<item>|<have>|<want>|<state>|<reason>|<zone>|<difficulty>|<hours>|<keep>|<parent>|<goldCap>|<step>|<need>
--   TBM:ORDER_END
--   TBM:ORDER_ACCESS|<rankIndex>|<rankName>|<tabsOk>|<tabsDenied>|<gold 0/1>|<canSetRank 0/1>
--   TBM:ORDER_ITEMS_BEGIN|<n>
--   TBM:ORDER_ITEM|<itemId>|<item>|<quality>|<sources>|<minLevel>|<skill>|<verdict>|<zone>|<chance>|<difficulty>|<category>
--   TBM:ORDER_ITEMS_END
--   TBM:ACTION_ACK|order|bot:<Bot>|1|<farm|buy|craft|cancel|rank|reassign>
--   TBM:ACTION_ERR|order|<code>|<message>
-- A TBM:ORDER line inside BEGIN/END is the full list (replace the whole
-- set); outside a pair it is a live update for one bot (update that row
-- only). The search pair is its own stream, so an empty result is a real
-- answer. Unknown state / reason / step tokens are shown raw, never crash.
-- <reason> "-" means none; <zone> "-" means none; <chance> is percent.
-- <difficulty> is easy / medium / hard ("-" or a missing field on old
-- servers means none); <reason> and <verdict> may be "elite", "timeout",
-- "noprogress" or "needitems". <keep> is keep or "-" (missing on old servers
-- means not keep); a keep order that delivered sits in state "stocked" until
-- the bank runs low. <hours> is whole hours or "inf" for no limit (missing on
-- old servers means none); an inf order never times out, only cancel ends it.
-- <category> is herb / ore / leather / fish / cloth / drop / other
-- ("-" or missing on old servers means none).
-- <parent> is the parent order's bot, or "-" for a top-level order (missing
-- on old servers means top-level); sub-order rows go live to the root
-- order's giver and show indented under their parent by bot name.
-- <goldCap> is the guild gold cap in copper, or "-" for no cap. <step> is
-- what the bot does now: bags, bank, ah, farm, craft, sub, need, deliver or
-- "-" (missing on old servers means none). <need> lists items the player must
-- bring as "itemId:count;..." or "-" (names come from the client item cache);
-- new reason needitems (state waiting) means the order waits for those items:
-- trade them, mail them or put them in the guild bank.
-- TBM:ORDER_ACCESS rides first inside ORDER_BEGIN/END and again after a rank
-- change; tab lists are comma-separated 1-based tabs or "-". Rank "-" (as in
-- "-|-|-|-|0|0") means the server leaves bot ranks alone: grey line, no rank
-- control. Tabs "-" and "-" with a numeric rank means no unlocked guild bank
-- yet: grey "No guild bank yet". Red is a real bank with a denied tab or
-- gold 0.
--
-- Permission: the giver's guild rank must be allowed to edit officer notes
-- (CanEditOfficerNote). Without it the Order and Cancel buttons are greyed
-- out instead of waiting for a "forbidden" reply.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local CAP = "guild-orders"
local SEARCH_MIN = 3
local SEARCH_DEBOUNCE = 0.6
local LIST_INTERVAL = 30
local AMOUNT_MIN, AMOUNT_MAX = 1, 200
local HOURS_MIN, HOURS_MAX = 1, 24

local function trim(text) local s = TB.Trim(text or "") return s end

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── capability gate + permission ─────────────────────────────────────────
function TB.HasOrderCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

-- The 1.12 client reports officer-note rights per rank; the server checks
-- the same right. A missing API (or no guild) means no orders.
function TB.CanGiveOrders()
    if CanEditOfficerNote then
        return CanEditOfficerNote() and true or false
    end
    return false
end

-- ── labels ────────────────────────────────────────────────────────────────
local TYPE_LABEL = { farm = "Farm", buy = "Buy", craft = "Craft" }
local STATE_LABEL = {
    working = "Working", waiting = "Waiting", delivering = "Delivering",
    done = "Done", stocked = "Stocked", mailed = "Mailed", noskill = "No skill", cant = "Can't",
}
local STATE_COLOR = {
    working = "|cff4ecb5a", waiting = "|cffffd200", delivering = "|cffffd200",
    done = "|cff4ecb5a", stocked = "|cff4ecb5a", mailed = "|cffffd200", noskill = "|cffff5050", cant = "|cffff5050",
}
local REASON_LABEL = {
    grouped = "in a group", noskill = "missing profession", lowskill = "skill too low",
    lowlevel = "bot under level 10", norange = "nothing in level range",
    nosource = "no source", norecipe = "unknown recipe", elite = "only from elite creatures",
    timeout = "farm time ran out", noprogress = "no progress - the bot found nothing to farm",
    stuck = "stuck, gave up", bagsfull = "bags full", nobank = "no bank deposit",
    needitems = "needs items from you",
}
local SOURCE_LABEL = { drop = "drop", skin = "skin", herb = "herb", ore = "ore", fish = "fish", craft = "craft", ah = "AH" }
local SKILL_NAMES = {
    ["129"] = "First Aid", ["164"] = "Blacksmithing", ["165"] = "Leatherworking",
    ["171"] = "Alchemy", ["182"] = "Herbalism", ["185"] = "Cooking",
    ["186"] = "Mining", ["197"] = "Tailoring", ["202"] = "Engineering",
    ["333"] = "Enchanting", ["356"] = "Fishing", ["393"] = "Skinning",
}

function TB.OrderTypeLabel(kind)
    kind = trim(kind)
    return TYPE_LABEL[string.lower(kind)] or kind
end

function TB.OrderStateLabel(state)
    state = trim(state)
    return STATE_LABEL[string.lower(state)] or state
end

function TB.OrderReasonLabel(reason)
    reason = trim(reason or "")
    if reason == "" or reason == "-" then return nil end
    return REASON_LABEL[string.lower(reason)] or reason
end
-- What the bot does now: bags (own bags and mail), bank (guild bank),
-- ah (auction house), farm in <zone>, craft, sub (waiting for a sub-order),
-- need (needs items from you), deliver. "-" or a missing field on old
-- servers means none; unknown steps show raw, never crash.
local STEP_LABEL = {
    bags = "checking bags and mail", bank = "taking from guild bank",
    ah = "buying on AH", farm = "farming", craft = "crafting",
    sub = "waiting for sub-order", need = "needs items from you",
    deliver = "delivering",
}

function TB.OrderStepLabel(order)
    if not order then return nil end
    local step = string.lower(trim(order.step or ""))
    if step == "" or step == "-" then return nil end
    if step == "farm" and order.zone then return "farming in " .. order.zone end
    return STEP_LABEL[step] or trim(order.step)
end
-- Money in plain coin words: 1g 20s 5c. Used for the guild gold cap; the
-- guild-log style colours of BotPanel would add noise in narrow rows.
function TB.OrderGoldText(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 or table.getn(parts) == 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end

-- Item names for a need list come from the client item cache (GetItemInfo),
-- like the search icons: unknown ids show as "item #<id>".
local function needName(id)
    if GetItemInfo then
        local name = GetItemInfo(id)
        if name then return name end
    end
    return "item #" .. tostring(id)
end

-- One hint for the whole need list: "trade, mail or put in guild bank".
function TB.OrderNeedText(order)
    if not order or not order.need or table.getn(order.need) == 0 then return nil end
    local parts = {}
    for _, entry in ipairs(order.need) do
        table.insert(parts, needName(entry.id) .. " x" .. tostring(entry.count or 0))
    end
    return "Needs: " .. table.concat(parts, ", ")
        .. " (trade, mail or put in guild bank)"
end

-- Difficulty estimate from the server: easy / medium / hard in plain words
-- with a subtle colour, nothing for "-" or old lines without the field.
local DIFFICULTY_LABEL = { easy = "Easy", medium = "Medium", hard = "Hard" }
local DIFFICULTY_COLOR = { easy = "|cff4ecb5a", medium = "|cffffd200", hard = "|cffff5050" }

function TB.OrderDifficultyLabel(difficulty)
    difficulty = trim(difficulty or "")
    if difficulty == "" or difficulty == "-" then return nil end
    local key = string.lower(difficulty)
    if not DIFFICULTY_LABEL[key] then return nil end
    return (DIFFICULTY_COLOR[key] or "") .. DIFFICULTY_LABEL[key] .. "|r"
end

function TB.OrderSourcesLabel(sources)
    local parts = {}
    for _, token in ipairs(sources or {}) do
        token = trim(token)
        if token ~= "" then
            table.insert(parts, SOURCE_LABEL[string.lower(token)] or token)
        end
    end
    return table.concat(parts, ", ")
end

-- "<skillId>:<value>" or "-". Unknown ids stay readable ("Skill 999 12").
function TB.OrderSkillLabel(skill)
    skill = trim(skill or "")
    if skill == "" or skill == "-" then return nil end
    local _, _, id, value = string.find(skill, "^(%d+):(%d+)$")
    if not id then return skill end
    return (SKILL_NAMES[id] or ("Skill " .. id)) .. " " .. value
end

local function skillName(skill)
    local _, _, id = string.find(trim(skill or ""), "^(%d+):%d+$")
    if not id then return nil end
    return SKILL_NAMES[id]
end

-- Farm estimate from the chance percent: amount ÷ chance. Herb and ore
-- count nodes, fish counts casts, everything else kills. Buy and craft show no estimate.
function TB.OrderEstimate(kind, sources, chance, amount)
    if string.lower(trim(kind or "")) ~= "farm" then return nil end
    chance = tonumber(chance) or 0
    amount = tonumber(amount) or 0
    if chance <= 0 or amount <= 0 then return nil end
    local count = math.floor((amount * 100 + chance - 1) / chance)
    local unit = "kills"
    for _, token in ipairs(sources or {}) do
        token = string.lower(trim(token))
        if token == "herb" or token == "ore" then unit = "nodes" break end
        if token == "fish" then unit = "casts" break end
    end
    if count == 1 then unit = string.sub(unit, 1, string.len(unit) - 1) end
    return "about " .. count .. " " .. unit
end

-- Drop rate next to the estimate: the server's whole-number chance, shown
-- plainly for farm kills ("12% drop"). Herb and ore nodes sit at 100 and
-- say nothing; a zero chance (no usable source) says nothing either.
function TB.OrderDropRate(kind, sources, chance)
    if string.lower(trim(kind or "")) ~= "farm" then return nil end
    chance = tonumber(chance) or 0
    if chance <= 0 then return nil end
    for _, token in ipairs(sources or {}) do
        token = string.lower(trim(token))
        if (token == "herb" or token == "ore") and chance >= 100 then return nil end
    end
    return chance .. "% drop"
end

-- ── model ─────────────────────────────────────────────────────────────────
-- orders[bot] = { bot, type, itemId, item, have, want, state, reason, zone,
--   difficulty, hours, keep, parent, goldCap, step, need }
-- hours is a number, "inf" for no limit, or nil when the server sent none.
-- parent is the parent order's bot, or nil for a top-level order; goldCap is
-- guild gold in copper or nil for no cap; need is { {id, count} } of items
-- the player must bring, or nil.
local orders = {}

function TB.GetBotOrder(bot)
    bot = norm(bot)
    return bot and orders[bot] or nil
end

-- Depth in the sub-order tree: top-level is 0, each parent adds one. Missing
-- parents (a live line ahead of the list) count as top-level, never a loop.
function TB.OrderDepth(order)
    local depth = 0
    local seen = {}
    local parent = order and order.parent or nil
    while parent and not seen[parent] and depth < 8 do
        seen[parent] = true
        local row = orders[parent]
        if not row then break end
        depth = depth + 1
        parent = row.parent
    end
    return depth
end

-- Child bots of one order, sorted for a stable tree.
function TB.OrderChildren(bot)
    bot = norm(bot)
    local out = {}
    if not bot then return out end
    for _, order in pairs(orders) do
        if order.parent == bot then table.insert(out, order) end
    end
    table.sort(out, function(a, b) return (a.bot or "") < (b.bot or "") end)
    return out
end

-- Every row with its depth: roots first (sorted), then each branch. Sorted
-- by name so the tree reads the same from any list order.
function TB.GetOrderTree()
    local roots = {}
    for _, order in pairs(orders) do
        if not order.parent or not orders[order.parent] then
            table.insert(roots, order)
        end
    end
    table.sort(roots, function(a, b) return (a.bot or "") < (b.bot or "") end)
    local out = {}
    local function visit(row, depth)
        table.insert(out, { order = row, depth = depth })
        for _, child in ipairs(TB.OrderChildren(row.bot)) do
            visit(child, depth + 1)
        end
    end
    for _, root in ipairs(roots) do visit(root, 0) end
    return out
end

function TB.GetOrders()
    local out = {}
    for _, order in pairs(orders) do table.insert(out, order) end
    table.sort(out, function(a, b) return (a.bot or "") < (b.bot or "") end)
    return out
end

-- One guild-row line: item, progress, state. The reason stays in the
-- tooltip (RefreshGuildView + the row tooltip in UI.lua). Sub-order rows
-- indent under their parent ("  Silver: item 1/5 · ..."); the live step
-- ("taking from guild bank", "farming in Elwynn" ...) joins waiting rows.
function TB.OrderRowText(order)
    if not order then return "" end
    local item = order.item or ("item #" .. tostring(order.itemId or "?"))
    local progress = tostring(order.have or 0) .. "/" .. tostring(order.want or 0)
    local state = string.lower(trim(order.state or ""))
    local paint = STATE_COLOR[state]
    local function word(text)
        if paint then return paint .. text .. "|r" end
        return text
    end
    local text
    if state == "working" then
        text = item .. " " .. progress
        local step = TB.OrderStepLabel(order)
        if step then text = text .. " · " .. step
        elseif order.zone then text = text .. " (" .. order.zone .. ")" end
    elseif state == "waiting" then
        text = item .. " " .. progress .. " · " .. word("Waiting")
        if string.lower(trim(order.reason or "")) ~= "needitems" then
            local step = TB.OrderStepLabel(order)
            if step then text = text .. " · " .. step end
        end
    elseif state == "delivering" then
        text = word("Delivering") .. " " .. item
    elseif state == "done" then
        text = item .. " · " .. word("Done")
    elseif state == "stocked" then
        text = item .. " · " .. word("Stocked")
    elseif state == "mailed" then
        text = item .. " · " .. word("Mailed to GM")
    elseif state == "noskill" then
        text = item .. " · " .. word("No skill")
    elseif state == "cant" then
        text = item .. " · " .. word("Can't")
    else
        text = item .. " " .. progress .. " · " .. trim(order.state or "")
    end
    if order.keep and state ~= "stocked" then text = text .. " · " .. word("Keep") end
    if order.hours == "inf" then text = text .. " · " .. word("No limit") end
    local diff = TB.OrderDifficultyLabel(order.difficulty)
    if diff then text = text .. " · " .. diff end
    if order.parent and orders[order.parent] then
        local indent = TB.OrderDepth(order)
        if indent > 0 then text = string.rep("  ", indent) .. order.bot .. ": " .. text end
    end
    return text
end
-- Tooltip body for a bot's order: type, progress, state, reason, zone, step,
-- need list, difficulty. Need items show item links like other rows, with a
-- short hint ("trade, mail or put in guild bank"); names come from the
-- client item cache, unknown ids show as "item #<id>".
function TB.OrderTooltipText(order)
    if not order then return nil end
    local lines = { "Order: " .. TB.OrderTypeLabel(order.type) .. " " .. (order.item or "?")
        .. " " .. tostring(order.have or 0) .. "/" .. tostring(order.want or 0) }
    local state = "State: " .. TB.OrderStateLabel(order.state)
    local reason = TB.OrderReasonLabel(order.reason)
    if reason then state = state .. " (" .. reason .. ")" end
    table.insert(lines, state)
    if order.zone then table.insert(lines, "Zone: " .. order.zone) end
    local step = TB.OrderStepLabel(order)
    if step then table.insert(lines, "Now: " .. step) end
    if order.hours == "inf" then
        table.insert(lines, "Farm time: no limit")
    elseif order.hours and order.hours > 0 then
        table.insert(lines, "Farm time: " .. math.floor(order.hours) .. " h")
    end
    if order.goldCap then
        table.insert(lines, "Max guild gold: " .. TB.OrderGoldText(order.goldCap))
    end
    local diff = TB.OrderDifficultyLabel(order.difficulty)
    if diff then
        table.insert(lines, "Difficulty: " .. diff
            .. " (Rough effort for this bot: how many kills, gathers or casts it needs)")
    end
    local need = TB.OrderNeedText(order)
    if need then table.insert(lines, need) end
    if order.keep and string.lower(trim(order.state or "")) ~= "stocked" then
        table.insert(lines, "Keep in stock: the bot refills when the bank drops below "
            .. tostring(order.want or 0))
    end
    if string.lower(trim(order.state or "")) == "stocked" then
        table.insert(lines, "Stocked: " .. tostring(order.want or 0) .. " in the bank, the bot refills when it drops below "
            .. tostring(order.want or 0))
    end
    return table.concat(lines, "\n")
end
-- ── parsing ───────────────────────────────────────────────────────────────
local function splitProtocol(text)
    local fields = {}
    local start = 1
    while true do
        local at = string.find(text, "|", start, true)
        if at then
            table.insert(fields, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(fields, string.sub(text, start))
            break
        end
    end
    return fields
end

local function splitSources(text)
    local out = {}
    for token in string.gfind(text or "", "[^,]+") do
        token = trim(token)
        if token ~= "" then table.insert(out, token) end
    end
    return out
end

local function noneDash(text)
    text = trim(text or "")
    if text == "" or text == "-" then return nil end
    return text
end

function TB.ParseOrderNeed(text)
    text = trim(text or "")
    if text == "" or text == "-" then return nil end
    local out = {}
    for pair in string.gfind(text, "[^;]+") do
        local _, _, idText, countText = string.find(trim(pair), "^(%d+):(%d+)$")
        local id = tonumber(idText)
        local count = tonumber(countText)
        if not id or not count or id <= 0 or count <= 0 then return nil end
        table.insert(out, { id = math.floor(id), count = math.floor(count) })
    end
    if table.getn(out) == 0 then return nil end
    return out
end

function TB.ParseOrderLine(msg)
    if string.sub(msg or "", 1, 10) ~= "TBM:ORDER|" then return nil end
    local fields = splitProtocol(string.sub(msg, 11))
    local count = table.getn(fields)
    if count < 9 or count > 16 then return nil end
    local bot = norm(trim(fields[1]))
    if not bot or bot == "" then return nil end
    local kind = trim(fields[2])
    if kind == "" then return nil end
    local itemId = tonumber(trim(fields[3]))
    local item = trim(fields[4])
    local have = tonumber(trim(fields[5]))
    local want = tonumber(trim(fields[6]))
    local state = trim(fields[7])
    if not itemId or item == "" or not have or not want or state == "" then return nil end
    local hours = nil
    if count >= 11 then
        local hoursField = trim(fields[11])
        if string.lower(hoursField) == "inf" then hours = "inf"
        else hours = tonumber(hoursField) end
    end
    local goldCap = nil
    if count >= 14 and trim(fields[14]) ~= "-" then
        local cap = tonumber(trim(fields[14]))
        if cap and cap >= 0 then goldCap = math.floor(cap) end
    end
    local need = nil
    if count >= 16 and trim(fields[16]) ~= "-" then
        need = TB.ParseOrderNeed(fields[16])
    end
    local parent = nil
    if count >= 13 then
        local raw = trim(fields[13])
        if raw ~= "" and raw ~= "-" then parent = norm(raw) end
    end
    if parent == bot then return nil end
    return {
        bot = bot, type = kind, itemId = math.floor(itemId), item = item,
        have = math.floor(have), want = math.floor(want), state = state,
        reason = noneDash(fields[8]), zone = noneDash(fields[9]),
        difficulty = count >= 10 and noneDash(fields[10]) or nil,
        hours = hours,
        keep = count >= 12 and string.lower(trim(fields[12])) == "keep" or false,
        parent = parent, goldCap = goldCap,
        step = count >= 15 and noneDash(fields[15]) or nil,
        need = need,
    }
end

-- TBM:ORDER_ACCESS|<rankIndex>|<rankName>|<tabsOk>|<tabsDenied>|<gold 0/1>|<canSetRank 0/1>.
-- Rank "-" means the server leaves bot ranks alone (grey line, no control);
-- tabs "-" and "-" with a numeric rank means no unlocked guild bank yet (grey
-- "No guild bank yet"). Red is a real bank with a denied tab or gold 0.
function TB.ParseOrderAccess(msg)
    if string.sub(msg or "", 1, 17) ~= "TBM:ORDER_ACCESS|" then return nil end
    local fields = splitProtocol(string.sub(msg, 18))
    if table.getn(fields) ~= 6 then return nil end
    local rankIndex = trim(fields[1])
    if rankIndex == "" then return nil end
    local rankNum = tonumber(rankIndex)
    if rankIndex ~= "-" and (not rankNum or rankNum < 0) then return nil end
    local rankName = trim(fields[2])
    if rankName == "" then return nil end
    local function tabs(text)
        text = trim(text or "")
        if text == "-" then return nil end
        local out = {}
        for token in string.gfind(text, "[^,]+") do
            local n = tonumber(trim(token))
            if not n or n < 1 then return nil end
            table.insert(out, math.floor(n))
        end
        if table.getn(out) == 0 then return nil end
        return out
    end
    local ok, denied = tabs(fields[3]), tabs(fields[4])
    if fields[3] ~= "-" and not ok then return nil end
    if fields[4] ~= "-" and not denied then return nil end
    if trim(fields[5]) ~= "0" and trim(fields[5]) ~= "1" then return nil end
    if trim(fields[6]) ~= "0" and trim(fields[6]) ~= "1" then return nil end
    local out = {
        tabsOk = ok, tabsDenied = denied,
        gold = trim(fields[5]) == "1" and true or false,
        canSetRank = trim(fields[6]) == "1" and true or false,
    }
    if rankIndex ~= "-" then out.rankIndex = math.floor(rankNum) end
    if rankName ~= "-" then out.rankName = rankName end
    return out
end

local orderAccess = nil

function TB.GetOrderAccess()
    return orderAccess
end

-- Header line for the order window: rank, bank tabs, gold. Numeric with a
-- real bank and a gap (a denied tab or gold 0) shows red; "-" rank (server
-- leaves ranks alone) and no-bank-yet stay grey; the rest stays plain.
function TB.OrderAccessText()
    if not orderAccess then return nil end
    if not orderAccess.rankIndex then
        return { text = "Bots: server does not manage the bots' rank;"
            .. " their bank access depends on each bot's own rank", bad = false }
    end
    local head = "Bots: rank " .. (orderAccess.rankName or ("#" .. orderAccess.rankIndex))
    if not orderAccess.tabsOk and not orderAccess.tabsDenied then
        return { text = head .. " · No guild bank yet", bad = false }
    end
    local tail = "bank tabs " .. TB.OrderTabList(orderAccess.tabsOk)
        .. ", gold " .. (orderAccess.gold and "yes" or "no")
    local bad = (orderAccess.tabsDenied and true or false) or not orderAccess.gold
    if bad then
        local why = {}
        if orderAccess.tabsDenied then
            table.insert(why, "tabs " .. TB.OrderTabList(orderAccess.tabsDenied) .. " denied")
        end
        if not orderAccess.gold then table.insert(why, "no gold access") end
        return { text = head .. " · " .. tail .. " (" .. table.concat(why, ", ") .. ")", bad = true }
    end
    return { text = head .. " · " .. tail, bad = false }
end

function TB.OrderTabList(tabs)
    if not tabs or table.getn(tabs) == 0 then return "-" end
    local parts = {}
    for _, n in ipairs(tabs) do table.insert(parts, tostring(n)) end
    return table.concat(parts, ",")
end

-- Guild ranks for the rank dropdown: index 0 is the guild master (skipped:
-- setting bots to GM is never offered), the rest by name from the client
-- guild API when present, else "Rank <idx>". The server's rankIndex is the
-- same 0-based index (GetGuildRosterInfo rankIndex; 1-based GuildControl
-- names minus one). The current bot rank is marked, not offered.
function TB.GetOrderRankOptions()
    local access = TB.GetOrderAccess()
    if not access or not access.canSetRank then return {} end
    local names = {}
    if GuildControlGetNumRanks and GuildControlGetRankName then
        local count = GuildControlGetNumRanks() or 0
        for i = 2, math.min(count, 10) do
            local name = GuildControlGetRankName(i)
            if name and trim(name) ~= "" then names[i - 1] = name end
        end
    end
    if table.getn(names) == 0 then
        for idx = 1, 9 do names[idx] = "Rank " .. idx end
    end
    local out = {}
    for idx = 1, 9 do
        if names[idx] then
            table.insert(out, { index = idx, name = names[idx],
                current = access.rankIndex == idx })
        end
    end
    return out
end

-- Reassign candidates: the guild bots the addon knows (claimed roster first,
-- then any other ordered bot), excluding the worker holding the sub-order.
-- Sorted so the menu reads the same from any list order.
function TB.GetOrderReassignCandidates(subBot)
    subBot = norm(subBot)
    local seen = {}
    local out = {}
    local function add(name)
        name = norm(name)
        if not name or name == subBot or seen[name] then return end
        seen[name] = true
        table.insert(out, name)
    end
    if TB.GetClaimedBots then
        for _, entry in ipairs(TB.GetClaimedBots() or {}) do add(entry.name) end
    end
    for _, order in pairs(orders) do add(order.bot) end
    table.sort(out)
    return out
end

function TB.ParseOrderItemLine(msg)
    if string.sub(msg or "", 1, 15) ~= "TBM:ORDER_ITEM|" then return nil end
    local fields = splitProtocol(string.sub(msg, 16))
    local count = table.getn(fields)
    if count ~= 9 and count ~= 10 and count ~= 11 then return nil end
    local itemId = tonumber(trim(fields[1]))
    local item = trim(fields[2])
    local quality = tonumber(trim(fields[3]))
    local minLevel = tonumber(trim(fields[5]))
    local verdict = trim(fields[7])
    local chance = tonumber(trim(fields[9]))
    if not itemId or item == "" or quality == nil or not minLevel
        or verdict == "" or chance == nil then return nil end
    if quality < 0 or quality > 6 then quality = nil end
    return {
        itemId = math.floor(itemId), item = item,
        quality = quality and math.floor(quality) or nil,
        sources = splitSources(fields[4]), minLevel = math.floor(minLevel),
        skill = noneDash(fields[6]), verdict = verdict,
        zone = noneDash(fields[8]), chance = math.floor(chance),
        difficulty = count >= 10 and noneDash(fields[10]) or nil,
        category = count == 11 and noneDash(fields[11]) or nil,
    }
end

-- Last completed search: { bot, kind, text, cat, items }.
local lastSearch = { bot = nil, kind = "farm", text = "", cat = nil, items = {} }
local searchBot, searchKind, searchText, searchCat = nil, "farm", "", nil
local orderReceiving, itemsReceiving = nil, nil

function TB.GetOrderSearch()
    return { bot = lastSearch.bot, kind = lastSearch.kind, text = lastSearch.text,
        cat = lastSearch.cat, items = lastSearch.items or {} }
end

local function commitOrderList(rows)
    for key in pairs(orders) do orders[key] = nil end
    for _, order in ipairs(rows) do orders[order.bot] = order end
end

function TB.ParseOrderMessage(msg)
    if string.sub(msg or "", 1, 4) ~= "TBM:" then return false end
    local _, _, count = string.find(msg, "^TBM:ORDER_BEGIN|(%d+)$")
    if count then
        orderReceiving = { expected = tonumber(count), rows = {} }
        return true
    end
    if string.sub(msg, 1, 17) == "TBM:ORDER_ACCESS|" then
        local access = TB.ParseOrderAccess(msg)
        if orderReceiving then
            if access then orderReceiving.access = access end
        elseif access then
            orderAccess = access
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    if string.sub(msg, 1, 10) == "TBM:ORDER|" then
        local order = TB.ParseOrderLine(msg)
        if orderReceiving then
            if order then table.insert(orderReceiving.rows, order) end
        elseif order then
            orders[order.bot] = order
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    if msg == "TBM:ORDER_END" then
        local batch = orderReceiving
        orderReceiving = nil
        if batch then
            commitOrderList(batch.rows)
            if batch.access then orderAccess = batch.access end
            if TB.SetStatus then
                TB.SetStatus("Orders updated · " .. table.getn(batch.rows), "ok")
            end
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    local _, _, itemCount = string.find(msg, "^TBM:ORDER_ITEMS_BEGIN|(%d+)$")
    if itemCount then
        itemsReceiving = { expected = tonumber(itemCount), rows = {} }
        return true
    end
    if string.sub(msg, 1, 15) == "TBM:ORDER_ITEM|" then
        local item = TB.ParseOrderItemLine(msg)
        if itemsReceiving and item then table.insert(itemsReceiving.rows, item) end
        return true
    end
    if msg == "TBM:ORDER_ITEMS_END" then
        local batch = itemsReceiving
        itemsReceiving = nil
        if batch then
            lastSearch = { bot = searchBot, kind = searchKind, text = searchText,
                cat = searchCat, items = batch.rows }
            if TB.SetStatus then
                if table.getn(batch.rows) == 0 then
                    TB.SetStatus("No matching items.", "muted")
                else
                    TB.SetStatus("Order search · " .. table.getn(batch.rows) .. " items", "ok")
                end
            end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    return false
end

-- ── sends ─────────────────────────────────────────────────────────────────
function TB.RequestOrderList()
    if not TB.HasOrderCapability() then return false end
    TB._lastOrderListAt = now()
    return TB.SendBotCommand("order list")
end

-- Item kinds for the search filter; the server takes cat=<token> and the
-- text may be empty (browse the kind). Old servers reject cat= as invalid.
-- A cat= search waiting for the answer; an old server rejects it as invalid
-- and the search is retried once without the filter.
local pendingSearchCat = nil
local ORDER_CATS = { "all", "herb", "ore", "leather", "fish", "cloth", "drop", "other" }
local ORDER_CAT_LABEL = {
    all = "All", herb = "Herbs", ore = "Ore", leather = "Leather",
    fish = "Fish", cloth = "Cloth", drop = "Drops", other = "Other",
}

-- The server refuses an empty-text browse for the two big kinds (drop,
-- other): those need 3+ letters like a plain search. The small kinds
-- (herb, ore, leather, fish, cloth) may browse with empty text.
local ORDER_BROWSE_CATS = { herb = true, ore = true, leather = true, fish = true, cloth = true }

function TB.OrderCatBrowsable(cat)
    cat = string.lower(trim(cat or ""))
    if cat == "" or cat == "-" then return false end
    return ORDER_BROWSE_CATS[cat] and true or false
end

function TB.OrderCatLabel(cat)
    cat = string.lower(trim(cat or ""))
    if cat == "" or cat == "-" then return nil end
    return ORDER_CAT_LABEL[cat] or cat
end

function TB.SendOrderSearch(bot, kind, text, cat)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    text = trim(text or "")
    cat = string.lower(trim(cat or ""))
    if cat == "all" or cat == "" then cat = nil end
    if cat and not ORDER_CAT_LABEL[cat] then return false end
    if string.len(text) < SEARCH_MIN then
        -- Big kinds need text too; small kinds may browse empty.
        if not cat or not TB.OrderCatBrowsable(cat) then return false end
    end
    searchBot, searchKind, searchText, searchCat = bot, kind, text, cat
    local line = "order search " .. bot .. " " .. kind
    if cat then line = line .. " cat=" .. cat end
    if text ~= "" then line = line .. " " .. text end
    if cat then pendingSearchCat = { bot = bot, kind = kind, text = text } end
    return TB.SendBotCommand(line)
end

function TB.ClampOrderAmount(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < AMOUNT_MIN then amount = AMOUNT_MIN end
    if amount > AMOUNT_MAX then amount = AMOUNT_MAX end
    return amount
end

function TB.ClampOrderHours(hours)
    hours = math.floor(tonumber(hours) or 0)
    if hours < HOURS_MIN then hours = HOURS_MIN end
    if hours > HOURS_MAX then hours = HOURS_MAX end
    return hours
end

-- A trailing-hours-or-keep-or-gold give waiting for the server's answer; an
-- "invalid" reply means an old server that rejects the trailing argument.
local pendingGive = nil

-- The give's hours slot also takes "inf" (any case) for no time limit.
local function isInf(hours)
    return string.lower(tostring(hours or "")) == "inf"
end

-- Guild gold cap for one give, in copper: nil or <= 0 means no cap and rides
-- no trailing field. Rounds down whole copper, plain digits only.
function TB.ClampOrderGold(copper)
    copper = tonumber(copper)
    if not copper or copper <= 0 then return nil end
    return math.floor(copper)
end

function TB.SendOrderGive(bot, kind, itemId, amount, hours, keep, gold)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    itemId = math.floor(tonumber(itemId) or 0)
    if not bot or (kind ~= "farm" and kind ~= "buy" and kind ~= "craft") then return false end
    if itemId <= 0 then return false end
    amount = TB.ClampOrderAmount(amount)
    gold = TB.ClampOrderGold(gold)
    local text = "order " .. bot .. " " .. kind .. " " .. itemId .. " " .. amount
    if hours ~= nil then
        if isInf(hours) then text = text .. " inf"
        else text = text .. " " .. TB.ClampOrderHours(hours) end
    end
    if keep then
        if hours == nil then text = text .. " " .. TB.ClampOrderHours(orderHours) end
        text = text .. " keep"
    end
    if gold then text = text .. " gold=" .. gold end
    if hours ~= nil or keep or gold then
        pendingGive = { bot = bot, kind = kind, itemId = itemId, amount = amount,
            hours = hours, keep = keep and true or false, gold = gold }
    else
        pendingGive = nil
    end
    return TB.SendBotCommand(text)
end

function TB.SendOrderCancel(bot)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    if not bot then return false end
    return TB.SendBotCommand("order " .. bot .. " cancel")
end

-- Hand a sub-order to another guild bot: ".bot order reassign <subBot> <new>".
-- The moved row lands live; a rank ACK repaints.
function TB.SendOrderReassign(subBot, newBot)
    if not TB.HasOrderCapability() then return false end
    subBot = norm(subBot)
    newBot = norm(newBot)
    if not subBot or not newBot then return false end
    return TB.SendBotCommand("order reassign " .. subBot .. " " .. newBot)
end

-- Ask for the bank-access snapshot: the server answers TBM:ORDER_ACCESS.
function TB.RequestOrderAccess()
    if not TB.HasOrderCapability() then return false end
    return TB.SendBotCommand("order access")
end

-- Set the bots' guild rank: ".bot order rank <idx>". The server answers with
-- ACK or ERR, then a fresh TBM:ORDER_ACCESS.
function TB.SendOrderRank(rankIndex)
    if not TB.HasOrderCapability() then return false end
    rankIndex = math.floor(tonumber(rankIndex) or -1)
    if rankIndex < 0 then return false end
    return TB.SendBotCommand("order rank " .. rankIndex)
end

-- Cancel asks first: a StaticPopup names the bot and item (the BotPanel.lua
-- destroy pattern), and only Yes sends. A parent cancel cancels the whole
-- branch, so the dialog warns when the order has sub-orders. Cancel is the
-- only way to end a keep-in-stock or no-limit order, so the dialog says so.
function TB.ConfirmOrderCancel(bot)
    bot = norm(bot)
    if not bot then return false end
    local order = orders[bot]
    local text = "Cancel " .. bot .. "'s order?"
    if order and order.item then
        text = "Cancel " .. bot .. "'s order for " .. tostring(order.want or 0)
            .. "x " .. order.item .. "?"
    end
    if order and table.getn(TB.OrderChildren(bot)) > 0 then
        text = text .. "\n\nThis cancels the whole branch: the sub-orders under it go too."
    end
    text = text .. "\n\nCancelling also ends keep-in-stock and no-limit orders."
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"] = {
            text = text,
            button1 = "Yes",
            button2 = "No",
            OnAccept = function() TB.SendOrderCancel(bot) end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("TORTOISEBOTSMANAGER_CANCEL_ORDER")
    else
        TB.SendOrderCancel(bot)
    end
    return true
end

-- ACK routing from Comms.ParseActionMessage for the order intent. A cancel
-- ACK drops the row at once (no live line can follow a removed order); a
-- rank or reassign ACK just reports and repaints (the fresh TBM:ORDER_ACCESS
-- or moved row lands live); a give ACK closes the window, the live line
-- paints the progress.
function TB.OnOrderAck(packet)
    if not packet or packet.intent ~= "order" then return false end
    pendingGive = nil
    pendingSearchCat = nil
    local _, _, scopeBot = string.find(packet.scope or "", "^bot:(.+)$")
    local bot = norm(scopeBot)
    if packet.executor == "cancel" then
        if bot then
            orders[bot] = nil
            for child, order in pairs(orders) do
                if order.parent == bot then orders[child] = nil end
            end
        end
        if TB.SetStatus then
            TB.SetStatus((bot or "Order") .. ": order cancelled.", "ok")
        end
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return true
    end
    if packet.executor == "reassign" then
        if TB.SetStatus then
            TB.SetStatus((bot or "Order") .. ": sub-order handed over.", "ok")
        end
        TB.RequestOrderList()
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return true
    end
    if packet.executor == "rank" then
        if TB.SetStatus then
            local rank = tonumber(packet.scope) or packet.scope
            TB.SetStatus("Bots' rank changed to " .. tostring(rank) .. ".", "ok")
        end
        TB.RequestOrderAccess()
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return true
    end
    if TB.SetStatus then
        local text = TB.OrderTypeLabel(packet.executor) .. " order accepted"
        if bot then text = bot .. ": " .. text end
        TB.SetStatus(text .. ".", "ok")
    end
    if bot and TB.GetOrderWindowBot and TB.GetOrderWindowBot() == bot then
        TB.CloseOrderWindow()
    end
    if TB.RefreshGuildView then TB.RefreshGuildView() end
    return true
end

-- ERR routing: the window keeps its own feedback line, the generic status
-- text below still reports the code and message.
function TB.OnOrderError(packet)
    if not packet or packet.intent ~= "order" then return false end
    -- An old server rejects the trailing gold / keep / hours arguments or
    -- cat= as invalid: resend without them, gold first (newest), then keep,
    -- then hours (a refused inf retries once as 24). The rest settles both.
    if packet.code == "invalid" and pendingGive then
        local give = pendingGive
        if give.gold then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = give.hours, keep = give.keep, gold = nil }
            TB.SetOrderFeedback("Old server: retrying without the guild gold cap...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, give.hours, give.keep)
            return false
        end
        if give.keep then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = give.hours, keep = false }
            TB.SetOrderFeedback("Old server: retrying without keep in stock...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, give.hours)
            return false
        end
        if isInf(give.hours) then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = HOURS_MAX, keep = false }
            TB.SetOrderFeedback("Old server: no time limit refused, retrying with 24 hours...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, HOURS_MAX)
            return false
        end
        pendingGive = nil
        TB.SetOrderFeedback("Old server: retrying without farm time...", "pending")
        TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount)
        return false
    end
    if packet.code == "invalid" and pendingSearchCat then
        local search = pendingSearchCat
        pendingSearchCat = nil
        -- An empty browse hits the size limit, not an old server: the bare
        -- retry would fail the same way, so surface the hint instead.
        if string.len(trim(search.text or "")) < SEARCH_MIN then
            pendingGive = nil
            TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
            return false
        end
        TB.SetOrderFeedback("Old server: retrying without the kind filter...", "pending")
        TB.SendOrderSearch(search.bot, search.kind, search.text)
        return false
    end
    pendingGive = nil
    pendingSearchCat = nil
    local message = trim(packet.message)
    if message == "" then message = packet.code end
    TB.SetOrderFeedback("|cffff5050Order refused:|r " .. message, "err")
    return false
end

-- The capability can disappear mid-session (a restart with the feature
-- off): close the window and drop the model so no stale state lingers.
function TB.NoteOrderCaps()
    if TB.HasOrderCapability() then
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return
    end
    for key in pairs(orders) do orders[key] = nil end
    orderAccess = nil
    lastSearch = { bot = nil, kind = "farm", text = "", cat = nil, items = {} }
    orderReceiving, itemsReceiving = nil, nil
    searchBot, searchCat = nil, nil
    pendingSearchCat = nil
    TB.CloseOrderWindow()
    if TB.RefreshGuildView then TB.RefreshGuildView() end
end

-- "order access" rides along when the window opens and has no snapshot yet.
function TB.OrderPollTick()
    if not TB.HasOrderCapability() then return false end
    if not (TB.guildFrame and TB.guildFrame:IsVisible()) then return false end
    if now() - (TB._lastOrderListAt or 0) < LIST_INTERVAL then return false end
    local sentList = TB.RequestOrderList()
    TB.RequestOrderAccess()
    return sentList
end

local pollFrame
local function ensurePollFrame()
    if pollFrame then return end
    pollFrame = CreateFrame("Frame", "TortoiseBotsManagerOrderPoll")
    pollFrame:SetScript("OnUpdate", function() TB.OrderPollTick() end)
end
ensurePollFrame()

-- ── order window ──────────────────────────────────────────────────────────
local OW = 340
local RESULT_ROW_H = 34
local RESULT_ROW_N = 6

local win = nil
local windowBot = nil
local orderKind = "farm"
local orderCat = nil
local orderAmount = 10
local orderHours = 1
local orderNoLimit = true
local orderKeep = false
local orderGold = nil
local searchPendingAt = nil
-- A picked empty-text row clears once typing starts: the next run is a
-- plain text search again, not another browse.
local searchTouched = false
local feedback = nil
local uncachedAt = nil
local scanTip = nil

function TB.GetOrderWindowBot()
    return (win and win:IsVisible()) and windowBot or nil
end

function TB.GetOrderKind()
    return orderKind
end

function TB.SetOrderKind(kind)
    kind = string.lower(trim(kind or ""))
    if kind ~= "farm" and kind ~= "buy" and kind ~= "craft" then return false end
    if kind == orderKind then return true end
    orderKind = kind
    selectedItemId = nil
    lastSearch = { bot = windowBot, kind = kind, text = "", cat = orderCat, items = {} }
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    -- A new kind re-runs a valid search at once: verdicts differ per kind
    -- (a craft search refuses unknown recipes, a farm search does not).
    -- Small kinds may browse with empty text; big kinds need 3+ letters.
    if win and windowBot and win.searchBox then
        local text = trim(win.searchBox:GetText() or "")
        if orderCat and TB.OrderCatBrowsable(orderCat) then
            searchPendingAt = nil
            TB.SendOrderSearch(windowBot, orderKind, text, orderCat)
        elseif orderCat and string.len(text) >= SEARCH_MIN then
            searchPendingAt = nil
            TB.SendOrderSearch(windowBot, orderKind, text, orderCat)
        elseif string.len(text) >= SEARCH_MIN then
            TB.SendOrderSearch(windowBot, orderKind, text)
        end
    end
    return true
end

function TB.GetOrderCat()
    return orderCat
end

-- Item kind filter: nil (no filter) or a server category token. Picking one
-- runs the search at once (empty text browses the kind); clearing the
-- filter needs text again.
function TB.SetOrderCat(cat)
    cat = string.lower(trim(cat or ""))
    if cat == "" or cat == "all" then cat = nil end
    if cat and not ORDER_CAT_LABEL[cat] then return false end
    if cat == orderCat then return true end
    orderCat = cat
    selectedItemId = nil
    searchTouched = false
    if cat then
        searchPendingAt = nil
        if win and win.searchBox and windowBot then
            local browseText = trim(win.searchBox:GetText() or "")
            if string.len(browseText) < SEARCH_MIN and not TB.OrderCatBrowsable(cat) then
                TB.SetOrderFeedback("Type at least 3 letters to search "
                    .. string.lower(TB.OrderCatLabel(cat) or "items") .. ".", "muted")
            else
                TB.SendOrderSearch(windowBot, orderKind, browseText, orderCat)
            end
        end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    else
        lastSearch = { bot = windowBot, kind = orderKind, text = "", cat = nil, items = {} }
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    end
    return true
end
function TB.GetOrderAmount()
    return orderAmount
end

function TB.SetOrderAmount(amount)
    orderAmount = TB.ClampOrderAmount(amount)
    if win and win.amountBox and win.amountBox:GetText() ~= tostring(orderAmount) then
        win.amountBox:SetText(tostring(orderAmount))
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderAmount
end

function TB.GetOrderHours()
    return orderHours
end

function TB.SetOrderHours(hours)
    orderHours = TB.ClampOrderHours(hours)
    if win and win.hoursBox and win.hoursBox:GetText() ~= tostring(orderHours) then
        win.hoursBox:SetText(tostring(orderHours))
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderHours
end

function TB.GetOrderKeep()
    return orderKeep and true or false
end

function TB.SetOrderKeep(keep)
    orderKeep = keep and true or false
    if win and win.keepBox and win.keepBox.GetChecked
        and win.keepBox:GetChecked() ~= orderKeep then
        win.keepBox:SetChecked(orderKeep)
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderKeep
end

function TB.GetOrderNoLimit()
    return orderNoLimit and true or false
end

function TB.SetOrderNoLimit(noLimit)
    orderNoLimit = noLimit and true or false
    if win and win.noLimitBox and win.noLimitBox.GetChecked
        and win.noLimitBox:GetChecked() ~= orderNoLimit then
        win.noLimitBox:SetChecked(orderNoLimit)
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderNoLimit
end

-- Max guild gold for the give, in copper: nil means no cap (empty box).
function TB.GetOrderGold()
    return orderGold
end

function TB.SetOrderGold(copper)
    orderGold = TB.ClampOrderGold(copper)
    if win and win.goldBox and win.goldBox:GetText() ~= (orderGold and tostring(orderGold) or "") then
        win.goldBox:SetText(orderGold and tostring(orderGold) or "")
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderGold
end

function TB.GetOrderSelection()
    return selectedItemId
end

function TB.SetOrderSelection(itemId)
    itemId = tonumber(itemId)
    selectedItemId = itemId and math.floor(itemId) or nil
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
end

function TB.GetOrderFeedback()
    return feedback
end

function TB.SetOrderFeedback(text, kind)
    feedback = text and { text = text, kind = kind } or nil
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
end

local function botLevel()
    local entry = windowBot and TB.GetClaimedEntry and TB.GetClaimedEntry(windowBot) or nil
    return entry and entry.level or nil
end

local function qualityHex(quality)
    if quality and GetItemQualityColor then
        local _, _, _, hex = GetItemQualityColor(quality)
        if hex then return hex end
    end
    return "|cffffffff"
end

-- Ask the server for an uncached item (BotPanel.lua scan tip): a hidden
-- tooltip query caches it, and the window re-renders a moment later.
local function requestItem(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TortoiseBotsManagerOrderScanTip", UIParent, "GameTooltipTemplate")
    end
    if scanTip.SetOwner and scanTip.SetHyperlink then
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:SetHyperlink("item:" .. id .. ":0:0:0")
    end
    uncachedAt = uncachedAt or now()
end

local function itemTexture(id)
    if id and GetItemInfo then
        local _, _, _, _, _, _, _, _, texture = GetItemInfo(id)
        if texture then return texture end
        requestItem(id)
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Second line of a search result: why the bot cannot get it, or sources,
-- level, skill, zone, the farm estimate and drop rate for the current amount,
-- and difficulty. Unusable verdicts explain themselves instead.
function TB.OrderItemDetail(item, kind, amount, level)
    kind = string.lower(trim(kind or "farm"))
    if not item then return "" end
    if string.lower(trim(item.verdict or "")) ~= "ok" then
        local verdict = string.lower(trim(item.verdict or ""))
        if verdict == "noskill" then
            local name = skillName(item.skill)
            if name then return "needs " .. name end
        elseif verdict == "lowskill" then
            local label = TB.OrderSkillLabel(item.skill)
            if label then
                if item.zone then return "needs " .. label .. " (" .. item.zone .. ")" end
                return "needs " .. label
            end
        elseif verdict == "lowlevel" then
            return "needs level 10"
        elseif verdict == "norange" and level then
            return "no source near level " .. level
        end
        local reason = TB.OrderReasonLabel(item.verdict)
        return "Can't: " .. (reason or item.verdict)
    end
    local parts = {}
    local sources = TB.OrderSourcesLabel(item.sources)
    if sources ~= "" then table.insert(parts, sources) end
    local cat = TB.OrderCatLabel(item.category)
    if cat and string.lower(trim(item.category or "")) ~= "other" then table.insert(parts, cat) end
    if (item.minLevel or 0) > 0 then table.insert(parts, "lvl " .. item.minLevel .. "+") end
    local skill = TB.OrderSkillLabel(item.skill)
    if skill then table.insert(parts, skill) end
    if item.zone then table.insert(parts, item.zone) end
    local estimate = TB.OrderEstimate(kind, item.sources, item.chance, amount)
    if estimate then table.insert(parts, estimate) end
    local rate = TB.OrderDropRate(kind, item.sources, item.chance)
    if rate then table.insert(parts, rate) end
    local diff = TB.OrderDifficultyLabel(item.difficulty)
    if diff then table.insert(parts, diff) end
    return table.concat(parts, " · ")
end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function smallButton(parent, label, width, x, y, tipTitle, tip, onClick)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    setTooltip(b, tipTitle, { tip })
    return b
end

-- The search goes out after a short pause in typing, not on every key.
-- With a kind filter the text may stay empty (browse that kind).
local function armSearch()
    searchTouched = true
    searchPendingAt = now() + SEARCH_DEBOUNCE
end

local function firePendingSearch()
    if not searchPendingAt or now() < searchPendingAt then return end
    if not (win and windowBot and win.searchBox) then return end
    local text = trim(win.searchBox:GetText() or "")
    if string.len(text) < SEARCH_MIN and (not orderCat or not TB.OrderCatBrowsable(orderCat)) then
        lastSearch = { bot = windowBot, kind = orderKind, text = text, cat = nil, items = {} }
        selectedItemId = nil
        if orderCat then
            TB.SetOrderFeedback("Type at least 3 letters to search "
                .. string.lower(TB.OrderCatLabel(orderCat) or "items") .. ".", "muted")
        else
            TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
        end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return
    end
    TB.SendOrderSearch(windowBot, orderKind, text, orderCat)
end

-- Dropdown menus (rank list, reassign targets): the 1.12 FrameXML set is
-- UIDropDownMenu_Initialize / UIDropDownMenu_AddButton / ToggleDropDownMenu
-- on a UIDropDownMenuTemplate frame anchored to the cursor. Each menu row
-- picks, asks one confirm, then sends; the builders below stay testable
-- without the global DropDownList frames.
local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerOrderWindow", TB.frame or UIParent)
    win:SetWidth(OW); win:SetHeight(510 + 118)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function() win:StartMoving() end)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        -- 1.12-safe: re-anchor with GetLeft/GetTop, never GetPoint().
        local left, top = win:GetLeft(), win:GetTop()
        if left and top then
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerOrderWindow") end
    TB.ApplyBackdrop(win, 0.98, 1.0)

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -10)
    win.title:SetWidth(OW - 50); win.title:SetJustifyH("LEFT")
    TB.SetTextColor(win.title, color("gold"))

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseOrderWindow() end)

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    head:SetWidth(OW - 24); head:SetJustifyH("LEFT")
    head:SetText("Pick a real item, how to get it, and how many.")
    TB.SetTextColor(head, color("muted"))

    local search = CreateFrame("EditBox", "TortoiseBotsManagerOrderSearch", win, "InputBoxTemplate")
    search:SetWidth(OW - 24); search:SetHeight(20)
    search:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -56)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function()
        searchPendingAt = nil
        this:ClearFocus()
        if win and windowBot then
            local text = trim(this:GetText() or "")
            if string.len(text) >= SEARCH_MIN
                or (orderCat and TB.OrderCatBrowsable(orderCat)) then
                TB.SendOrderSearch(windowBot, orderKind, text, orderCat)
            elseif orderCat then
                TB.SetOrderFeedback("Type at least 3 letters to search "
                    .. string.lower(TB.OrderCatLabel(orderCat) or "items") .. ".", "muted")
            else
                TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
            end
        end
    end)
    search:SetScript("OnTextChanged", function() armSearch() end)
    win.searchBox = search

    local kinds = { { "Farm", "farm" }, { "Buy", "buy" }, { "Craft", "craft" } }
    win.kindPills = {}
    for i, entry in ipairs(kinds) do
        local pill = TB.UI.CreateTogglePill(win, entry[1], 100, 22, {
            tipTitle = entry[1],
            tip = entry[2] == "farm" and "Gather or kill for the items."
                or (entry[2] == "buy" and "Buy on the auction house first, farm the rest."
                    or "Craft from materials, farming what is missing."),
        })
        pill:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + (i - 1) * 106, -80)
        local kind = entry[2]
        pill:SetScript("OnClick", function() TB.SetOrderKind(kind) end)
        win.kindPills[kind] = pill
    end

    win.catPills = {}
    for i, cat in ipairs(ORDER_CATS) do
        local pill = TB.UI.CreateTogglePill(win, ORDER_CAT_LABEL[cat], 74, 18, {
            tipTitle = ORDER_CAT_LABEL[cat],
            tip = "Only show this kind of item.",
        })
        pill:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + ((i - 1) % 4) * 80,
            -106 - math.floor((i - 1) / 4) * 22)
        local token = cat
        pill:SetScript("OnClick", function() TB.SetOrderCat(token) end)
        win.catPills[cat] = pill
    end

    local results = CreateFrame("ScrollFrame", "TortoiseBotsManagerOrderResults", win, "FauxScrollFrameTemplate")
    results:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -152)
    results:SetWidth(OW - 24)
    results:SetHeight(RESULT_ROW_N * RESULT_ROW_H + 4)
    results:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(RESULT_ROW_H, TB.RefreshOrderWindow)
    end)
    win.results = results

    win.resultRows = {}
    for i = 1, RESULT_ROW_N do
        local row = CreateFrame("Button", nil, win)
        row:SetWidth(OW - 24 - 18)
        row:SetHeight(RESULT_ROW_H - 2)
        row:SetPoint("TOPLEFT", results, "TOPLEFT", 0, -(i - 1) * RESULT_ROW_H)
        TB.ApplyBackdrop(row, 0.62, 0.45)
        row:RegisterForClicks("LeftButtonUp")
        row.sel = row:CreateTexture(nil, "ARTWORK")
        row.sel:SetWidth(3)
        row.sel:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.sel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
        row.sel:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(24); row.icon:SetHeight(24)
        row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 38, 7)
        row.name:SetWidth(OW - 24 - 18 - 44)
        row.name:SetJustifyH("LEFT")
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.detail:SetPoint("LEFT", row, "LEFT", 38, -8)
        row.detail:SetWidth(OW - 24 - 18 - 44)
        row.detail:SetJustifyH("LEFT")
        row:SetScript("OnClick", function()
            local item = this.item
            if not item then return end
            if string.lower(trim(item.verdict or "")) ~= "ok" then
                TB.SetOrderFeedback("This bot can't get it: "
                    .. TB.OrderItemDetail(item, orderKind, orderAmount, botLevel()) .. ".", "warn")
                return
            end
            TB.SetOrderFeedback(nil)
            TB.SetOrderSelection(item.itemId)
        end)
        row:SetScript("OnEnter", function()
            local item = this.item
            if not item then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if GetItemInfo and GetItemInfo(item.itemId) and GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. item.itemId .. ":0:0:0")
            else
                GameTooltip:SetText(qualityHex(item.quality) .. item.item .. "|r")
                if item.zone then
                    GameTooltip:AddLine(item.zone, 0.9, 0.9, 0.9, 1)
                end
            end
            local diff = TB.OrderDifficultyLabel(item.difficulty)
            if diff then
                GameTooltip:AddLine("Difficulty: " .. diff, 0.9, 0.9, 0.9, 1)
                GameTooltip:AddLine("Rough effort for this bot: how many kills, gathers or casts it needs",
                    0.9, 0.9, 0.9, 1)
            end
            if TB.OrderDropRate(orderKind, item.sources, item.chance) then
                GameTooltip:AddLine("Rare drops can take many hours. Give reasonable orders.",
                    0.9, 0.9, 0.9, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(win.resultRows, row)
    end

    win.emptyMsg = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.emptyMsg:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -196)
    win.emptyMsg:SetWidth(OW - 24)
    win.emptyMsg:SetJustifyH("CENTER")
    TB.SetTextColor(win.emptyMsg, color("muted"))

    -- Guild bank access the bots can reach: rank, bank tabs, gold.
    local accessLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accessLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 4))
    accessLabel:SetWidth(OW - 24 - 68); accessLabel:SetJustifyH("LEFT")
    win.accessLabel = accessLabel

    win.rankBtn = smallButton(win, "Rank", 56, 260, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 2),
        "Change bots' rank", "Pick the guild rank bots get (needs rank rights).",
        function()
            TB.OpenOrderRankMenu(this)
        end)

    -- Live orders and sub-orders: every row names its bot and step, indented
    -- under its parent, updating as TBM:ORDER lines land.
    local treeLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    treeLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 20))
    treeLabel:SetText("ORDERS")
    treeLabel:SetWidth(OW - 24); treeLabel:SetJustifyH("LEFT")
    TB.SetTextColor(treeLabel, color("gold"))

    win.treeLines = {}
    for i = 1, 4 do
        local line = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 22 + (i - 1) * 12))
        line:SetWidth(OW - 24 - 68); line:SetJustifyH("LEFT")
        TB.SetTextColor(line, color("muted"))
        win.treeLines[i] = line
    end

    local base = 152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 76
    local farmNote = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    farmNote:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 2))
    farmNote:SetWidth(OW - 24); farmNote:SetJustifyH("LEFT")
    farmNote:SetText("Bots farm like players: large amounts or rare drops can take very long or fail.")
    TB.SetTextColor(farmNote, color("muted"))
    win.farmNote = farmNote
    base = 152 + RESULT_ROW_N * RESULT_ROW_H + 30 + 76
    local amountLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amountLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 4))
    amountLabel:SetText("AMOUNT")
    TB.SetTextColor(amountLabel, color("gold"))

    local minus = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    minus:SetWidth(24); minus:SetHeight(22)
    minus:SetPoint("TOPLEFT", win, "TOPLEFT", 70, -(base + 2))
    minus:SetText("-")
    minus:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            TB.SetOrderAmount(orderAmount - 10)
        else
            TB.SetOrderAmount(orderAmount - 1)
        end
    end)
    win.amountMinus = minus

    local amountBox = CreateFrame("EditBox", "TortoiseBotsManagerOrderAmount", win, "InputBoxTemplate")
    amountBox:SetWidth(52); amountBox:SetHeight(20)
    amountBox:SetPoint("TOPLEFT", win, "TOPLEFT", 98, -(base + 2))
    amountBox:SetAutoFocus(false)
    amountBox:SetScript("OnEscapePressed", function()
        this:SetText(tostring(orderAmount))
        this:ClearFocus()
    end)
    amountBox:SetScript("OnEnterPressed", function()
        TB.SetOrderAmount(tonumber(this:GetText()) or orderAmount)
        this:ClearFocus()
    end)
    -- Commit while typing and on focus loss, so Send always uses the
    -- shown number and the estimates follow without pressing Enter.
    -- Non-numeric text is left alone until Escape or a valid edit. The
    -- SetText below re-fires OnTextChanged, hence the differs guard.
    amountBox:SetScript("OnTextChanged", function()
        local n = tonumber(this:GetText() or "")
        if n and TB.ClampOrderAmount(n) ~= orderAmount then TB.SetOrderAmount(n) end
    end)
    amountBox:SetScript("OnEditFocusLost", function()
        this:SetText(tostring(orderAmount))
    end)
    win.amountBox = amountBox

    local plus = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    plus:SetWidth(24); plus:SetHeight(22)
    plus:SetPoint("TOPLEFT", win, "TOPLEFT", 154, -(base + 2))
    plus:SetText("+")
    plus:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            TB.SetOrderAmount(orderAmount + 10)
        else
            TB.SetOrderAmount(orderAmount + 1)
        end
    end)
    win.amountPlus = plus

    local hoursLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hoursLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 194, -(base + 4))
    hoursLabel:SetText("FARM TIME")
    TB.SetTextColor(hoursLabel, color("gold"))

    local hoursBox = CreateFrame("EditBox", "TortoiseBotsManagerOrderHours", win, "InputBoxTemplate")
    hoursBox:SetWidth(36); hoursBox:SetHeight(20)
    hoursBox:SetPoint("TOPLEFT", win, "TOPLEFT", 268, -(base + 2))
    hoursBox:SetAutoFocus(false)
    hoursBox:SetScript("OnEscapePressed", function()
        this:SetText(tostring(orderHours))
        this:ClearFocus()
    end)
    hoursBox:SetScript("OnEnterPressed", function()
        TB.SetOrderHours(tonumber(this:GetText()) or orderHours)
        this:ClearFocus()
    end)
    hoursBox:SetScript("OnTextChanged", function()
        local n = tonumber(this:GetText() or "")
        if n and TB.ClampOrderHours(n) ~= orderHours then TB.SetOrderHours(n) end
    end)
    hoursBox:SetScript("OnEditFocusLost", function()
        this:SetText(tostring(orderHours))
    end)
    win.hoursBox = hoursBox
    setTooltip(hoursBox, "Farm time",
        { "Whole hours this order may farm (1-24). The bot stops when the time runs out." })

    local keepBox = CreateFrame("CheckButton", "TortoiseBotsManagerOrderKeep", win, "UICheckButtonTemplate")
    keepBox:SetWidth(20); keepBox:SetHeight(20)
    keepBox:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 22))
    keepBox:SetScript("OnClick", function()
        TB.SetOrderKeep(this:GetChecked() and true or false)
    end)
    win.keepBox = keepBox
    setTooltip(keepBox, "Keep in stock",
        { "Delivered, the order stays: the bot watches the bank and refills when it drops below the amount." })
    local keepLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keepLabel:SetPoint("LEFT", keepBox, "RIGHT", 2, 0)
    keepLabel:SetWidth(120); keepLabel:SetJustifyH("LEFT")
    keepLabel:SetText("Keep in stock")
    TB.SetTextColor(keepLabel, color("muted"))
    win.keepLabel = keepLabel

    local goldLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 46))
    goldLabel:SetText("MAX GUILD GOLD")
    goldLabel:SetWidth(150); goldLabel:SetJustifyH("LEFT")
    TB.SetTextColor(goldLabel, color("gold"))
    win.goldLabel = goldLabel

    local goldBox = CreateFrame("EditBox", "TortoiseBotsManagerOrderGold", win, "InputBoxTemplate")
    goldBox:SetWidth(100); goldBox:SetHeight(20)
    goldBox:SetPoint("TOPLEFT", win, "TOPLEFT", 168, -(base + 44))
    goldBox:SetAutoFocus(false)
    goldBox:SetScript("OnEscapePressed", function()
        this:SetText(orderGold and tostring(orderGold) or "")
        this:ClearFocus()
    end)
    goldBox:SetScript("OnEnterPressed", function()
        local text = trim(this:GetText() or "")
        if text == "" then TB.SetOrderGold(nil)
        else TB.SetOrderGold(tonumber(text) or orderGold) end
        this:ClearFocus()
    end)
    goldBox:SetScript("OnTextChanged", function()
        local text = trim(this:GetText() or "")
        if text == "" then
            if orderGold ~= nil then TB.SetOrderGold(nil) end
        else
            local g = tonumber(text)
            if g and TB.ClampOrderGold(g) ~= orderGold then TB.SetOrderGold(g) end
        end
    end)
    goldBox:SetScript("OnEditFocusLost", function()
        this:SetText(orderGold and tostring(orderGold) or "")
    end)
    win.goldBox = goldBox
    setTooltip(goldLabel, "Max guild gold",
        { "Most the order may spend from the guild bank, in copper. Empty means no cap." })
    setTooltip(goldBox, "Max guild gold",
        { "Most the order may spend from the guild bank, in copper. Empty means no cap." })
    local noLimitBox = CreateFrame("CheckButton", "TortoiseBotsManagerOrderNoLimit", win, "UICheckButtonTemplate")
    noLimitBox:SetWidth(20); noLimitBox:SetHeight(20)
    noLimitBox:SetPoint("TOPLEFT", win, "TOPLEFT", 194, -(base + 22))
    noLimitBox:SetScript("OnClick", function()
        TB.SetOrderNoLimit(this:GetChecked() and true or false)
    end)
    win.noLimitBox = noLimitBox
    setTooltip(noLimitBox, "No time limit",
        { "The bot farms until it has the amount, however long it takes. Only Cancel stops it." })
    local noLimitLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noLimitLabel:SetPoint("LEFT", noLimitBox, "RIGHT", 2, 0)
    noLimitLabel:SetWidth(110); noLimitLabel:SetJustifyH("LEFT")
    noLimitLabel:SetText("No time limit")
    TB.SetTextColor(noLimitLabel, color("muted"))
    win.noLimitLabel = noLimitLabel

    win.sendBtn = smallButton(win, "Send", 76, 194, -(base + 66),
        "Send order", "Give this bot the order (replaces its old one).",
        function()
            -- The boxes commit on change, but read them anyway: a valid
            -- number must always win over a stale value.
            if win.amountBox then
                local n = tonumber(win.amountBox:GetText() or "")
                if n then TB.SetOrderAmount(n) end
            end
            if win.hoursBox and not orderNoLimit then
                local h = tonumber(win.hoursBox:GetText() or "")
                if h then TB.SetOrderHours(h) end
            end
            if win.goldBox then
                local text = trim(win.goldBox:GetText() or "")
                if text == "" then TB.SetOrderGold(nil)
                else
                    local g = tonumber(text)
                    if g then TB.SetOrderGold(g) end
                end
            end
            local item = nil
            for _, candidate in ipairs((TB.GetOrderSearch().items) or {}) do
                if candidate.itemId == selectedItemId then item = candidate break end
            end
            if not item then
                TB.SetOrderFeedback("Pick an item from the search first.", "warn")
                return
            end
            if string.lower(trim(item.verdict or "")) ~= "ok" then
                TB.SetOrderFeedback("This bot can't get it.", "warn")
                return
            end
            local timeText = orderNoLimit and "no limit" or (orderHours .. "h")
            local goldText = orderGold and (" " .. TB.OrderGoldText(orderGold)) or ""
            TB.SetOrderFeedback(TB.OrderTypeLabel(orderKind) .. " " .. item.item
                .. " x" .. orderAmount .. " (" .. timeText .. (orderKeep and ", keep" or "")
                .. goldText .. ") sent, waiting for the server...", "pending")
            TB.SendOrderGive(windowBot, orderKind, item.itemId, orderAmount,
                orderNoLimit and "inf" or orderHours, orderKeep, orderGold)
        end)

    win.cancelBtn = smallButton(win, "Cancel", 62, 274, -(base + 66),
        "Cancel order", "Remove this bot's current order. Cancelling also ends keep-in-stock and no-limit orders.",
        function()
            if windowBot then TB.ConfirmOrderCancel(windowBot) end
        end)

    win.statusLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.statusLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 92))
    win.statusLine:SetWidth(OW - 24); win.statusLine:SetJustifyH("LEFT")
    TB.SetTextColor(win.statusLine, color("muted"))

    win.feedbackLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.feedbackLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 108))
    win.feedbackLine:SetWidth(OW - 24); win.feedbackLine:SetJustifyH("LEFT")

    win:SetScript("OnUpdate", function()
        firePendingSearch()
        -- Uncached items re-render once the client has them.
        if uncachedAt and now() - uncachedAt > 1 then
            uncachedAt = nil
            TB.RefreshOrderWindow()
        end
    end)

    win:Hide()
    TB.orderWindow = win
end

function TB.RefreshOrderWindow()
    if not win or not win:IsVisible() then return end
    win.title:SetText("Order for " .. (windowBot or "?"))
    for kind, pill in pairs(win.kindPills or {}) do
        if pill.SetActive then pill:SetActive(kind == orderKind) end
    end
    for cat, pill in pairs(win.catPills or {}) do
        if pill.SetActive then pill:SetActive(cat == (orderCat or "all")) end
    end
    local search = TB.GetOrderSearch()
    local items = {}
    if search.bot == windowBot and search.kind == orderKind
        and (search.cat or nil) == (orderCat or nil) then
        items = search.items or {}
    end
    local total = table.getn(items)
    FauxScrollFrame_Update(win.results, total, RESULT_ROW_N, RESULT_ROW_H)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(win.results)) or 0
    local level = botLevel()
    local foundSelected = false
    for i = 1, RESULT_ROW_N do
        local row = win.resultRows[i]
        local item = items[offset + i]
        if item then
            row.item = item
            if item.itemId == selectedItemId then foundSelected = true end
            local cant = string.lower(trim(item.verdict or "")) ~= "ok"
            row.icon:SetTexture(itemTexture(item.itemId))
            -- No quality escape when greyed: inline |cff codes override
            -- SetTextColor in the 1.12 client.
            if cant then row.name:SetText(item.item) else row.name:SetText(qualityHex(item.quality) .. item.item .. "|r") end
            if cant then row.name:SetTextColor(0.45, 0.45, 0.45) else row.name:SetTextColor(1, 1, 1) end
            row.detail:SetText(TB.OrderItemDetail(item, orderKind, orderAmount, level))
            if cant then row.detail:SetTextColor(0.45, 0.45, 0.45)
            else row.detail:SetTextColor(0.85, 0.85, 0.85) end
            if item.itemId == selectedItemId then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.item = nil
            row:Hide()
        end
    end
    if selectedItemId and not foundSelected then
        -- The pick vanished from the list (a re-search replaced it).
        selectedItemId = nil
    end
    if win.emptyMsg then
        if total == 0 then
            local text = trim(win.searchBox:GetText() or "")
            if string.len(text) < SEARCH_MIN and not orderCat then
                win.emptyMsg:SetText("Type at least 3 letters to search.")
            elseif search.bot == windowBot and search.kind == orderKind
                and (search.cat or nil) == (orderCat or nil) then
                win.emptyMsg:SetText("No matching items.")
            else
                win.emptyMsg:SetText("Searching...")
            end
            win.emptyMsg:Show()
        else
            win.emptyMsg:Hide()
        end
    end
    -- The box commits on change and every amount change syncs the box, so
    -- a refresh never touches it: a typed number is never rewritten here.
    local order = windowBot and TB.GetBotOrder(windowBot) or nil
    local access = TB.GetOrderAccess()
    local accessText = access and TB.OrderAccessText() or nil
    if win.accessLabel then
        if accessText then
            win.accessLabel:SetText(accessText.text)
            if accessText.bad then win.accessLabel:SetTextColor(1, 0.34, 0.28)
            else win.accessLabel:SetTextColor(0.62, 0.60, 0.56) end
            win.accessLabel:Show()
        else
            win.accessLabel:SetText("Bank access: waiting for the server...")
            win.accessLabel:SetTextColor(0.62, 0.60, 0.56)
            win.accessLabel:Show()
        end
    end
    if win.rankBtn then
        if access and access.canSetRank and access.rankIndex and TB.CanGiveOrders() then
            win.rankBtn:Enable()
            win.rankBtn:Show()
        else
            win.rankBtn:Hide()
        end
    end
    if win.treeLines then
        local tree = TB.GetOrderTree()
        for i, line in ipairs(win.treeLines) do
            local entry = tree[i]
            if entry then
                line:SetText(TB.OrderRowText(entry.order))
                local paint = entry.order.bot == windowBot
                if paint then line:SetTextColor(0.95, 0.72, 0.28)
                else line:SetTextColor(0.85, 0.85, 0.85) end
                line:Show()
            else
                line:Hide()
            end
        end
    end
    if win.goldBox then
        if TB.CanGiveOrders() then
            win.goldBox:EnableMouse(true)
        else
            win.goldBox:ClearFocus()
        end
    end
    if win.statusLine then
        if order then
            win.statusLine:SetText("Current: " .. TB.OrderRowText(order))
        else
            win.statusLine:SetText("No order on this bot.")
        end
    end
    if win.cancelBtn then
        if order and TB.CanGiveOrders() then win.cancelBtn:Enable() else win.cancelBtn:Disable() end
    end
    if win.sendBtn then
        if TB.CanGiveOrders() then win.sendBtn:Enable() else win.sendBtn:Disable() end
    end
    if win.keepBox and win.keepBox.SetChecked then
        win.keepBox:SetChecked(orderKeep and true or false)
        if TB.CanGiveOrders() then win.keepBox:Enable() else win.keepBox:Disable() end
    end
    if win.noLimitBox and win.noLimitBox.SetChecked then
        win.noLimitBox:SetChecked(orderNoLimit and true or false)
        if TB.CanGiveOrders() then win.noLimitBox:Enable() else win.noLimitBox:Disable() end
    end
    -- No time limit greys the hours box: unfocused, unclickable, dimmed.
    -- The kept number returns when the box is ticked off.
    if win.hoursBox then
        if orderNoLimit then
            win.hoursBox:ClearFocus()
            win.hoursBox:EnableMouse(false)
            win.hoursBox:SetTextColor(0.5, 0.5, 0.5)
        else
            win.hoursBox:EnableMouse(true)
            win.hoursBox:SetTextColor(1, 1, 1)
        end
    end
    if win.feedbackLine then
        if feedback then
            win.feedbackLine:SetText(feedback.text)
            win.feedbackLine:Show()
        else
            win.feedbackLine:Hide()
        end
    end
end

function TB.OpenOrderWindow(bot)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    if not bot then return false end
    if not win then createWindow() end
    -- Same anchor as the other satellites: only one shows at a time.
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseBotPanel then TB.CloseBotPanel() end
    local switched = windowBot ~= bot
    windowBot = bot
    if switched then
        orderAmount = 10
        orderHours = 1
        orderNoLimit = true
        orderKeep = false
        orderGold = nil
        orderCat = nil
        selectedItemId = nil
        feedback = nil
        searchPendingAt = nil
        searchTouched = false
        lastSearch = { bot = bot, kind = orderKind, text = "", cat = nil, items = {} }
        if win.searchBox then win.searchBox:SetText("") end
        if win.amountBox then win.amountBox:SetText("10") end
        if win.hoursBox then win.hoursBox:SetText("1") end
        if win.goldBox then win.goldBox:SetText("") end
        if win.noLimitBox and win.noLimitBox.SetChecked then win.noLimitBox:SetChecked(true) end
        if win.keepBox and win.keepBox.SetChecked then win.keepBox:SetChecked(false) end
    end
    -- Bank access arrives with the list; ask for it now when the list
    -- did not carry it yet.
    if not TB.GetOrderAccess() then TB.RequestOrderAccess() end
    -- Anchor beside the main window, like the run window.
    win:ClearAllPoints()
    if TB.frame then
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + OW + 4) * scale > screen then
            win:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            win:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RefreshOrderWindow()
    return true
end

function TB.CloseOrderWindow()
    searchPendingAt = nil
    if win then win:Hide() end
end

-- Rank menu: a dropdown listing the guild's ranks by name (guild master
-- skipped, current bot rank marked). Picking one asks "Move all guild bots
-- to rank <name>?" and only Yes sends `.bot order rank <idx>` with the
-- server's 0-based rank index. The builders stay testable without the
-- global DropDownList frames; the openers need the 1.12 dropdown API.
function TB.BuildOrderRankMenu(addButton)
    local options = TB.GetOrderRankOptions()
    for _, option in ipairs(options) do
        local label = option.name
        if option.current then label = label .. " (current)" end
        addButton({ text = label, notCheckable = 1,
            func = function() TB.ConfirmOrderRank(option.index, option.name) end })
    end
    return table.getn(options)
end

function TB.OpenOrderRankMenu(owner)
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if table.getn(TB.GetOrderRankOptions()) == 0 then return false end
    if not TB._orderRankMenu then
        TB._orderRankMenu = CreateFrame("Frame", "TortoiseBotsManagerOrderRankMenu",
            UIParent, "UIDropDownMenuTemplate")
    end
    local menu = TB._orderRankMenu
    UIDropDownMenu_Initialize(menu, function()
        TB.BuildOrderRankMenu(UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, menu, "cursor")
    return true
end

-- Reassign menu: a dropdown on the sub-order row listing the guild's bots
-- the addon knows, excluding the worker holding the sub-order. Picking one
-- asks first, then sends `.bot order reassign <sub> <new>`. No candidates:
-- a short message instead of a menu.
function TB.BuildOrderReassignMenu(subBot, addButton)
    subBot = norm(subBot)
    if not subBot or not orders[subBot] or not orders[subBot].parent then return 0 end
    local names = TB.GetOrderReassignCandidates(subBot)
    for _, name in ipairs(names) do
        addButton({ text = name, notCheckable = 1,
            func = function() TB.ConfirmOrderReassign(subBot, name) end })
    end
    return table.getn(names)
end

function TB.OpenOrderReassignMenu(subBot, owner)
    subBot = norm(subBot)
    if not subBot then return false end
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if table.getn(TB.GetOrderReassignCandidates(subBot)) == 0 then
        TB.SetOrderFeedback("No other guild bots to hand it to.", "warn")
        return false
    end
    if not TB._orderReassignMenu then
        TB._orderReassignMenu = CreateFrame("Frame", "TortoiseBotsManagerOrderReassignMenu",
            UIParent, "UIDropDownMenuTemplate")
    end
    local menu = TB._orderReassignMenu
    UIDropDownMenu_Initialize(menu, function()
        TB.BuildOrderReassignMenu(subBot, UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, menu, "cursor")
    return true
end

function TB.ConfirmOrderRank(index, name)
    index = math.floor(tonumber(index) or -1)
    if index < 0 then return false end
    local text = "Move all guild bots to rank " .. (name or ("#" .. index)) .. "?"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"] = {
            text = text,
            button1 = "Yes",
            button2 = "No",
            OnAccept = function() TB.SendOrderRank(index) end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("TORTOISEBOTSMANAGER_ORDER_RANK")
    else
        TB.SendOrderRank(index)
    end
    return true
end

function TB.ConfirmOrderReassign(subBot, newBot)
    subBot = norm(subBot)
        newBot = norm(newBot)
    if not subBot or not newBot or subBot == newBot then return false end
    local text = "Hand " .. subBot .. "'s sub-order to " .. newBot .. "?"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"] = {
            text = text,
            button1 = "Yes",
            button2 = "No",
            OnAccept = function() TB.SendOrderReassign(subBot, newBot) end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("TORTOISEBOTSMANAGER_ORDER_REASSIGN")
    else
        TB.SendOrderReassign(subBot, newBot)
    end
    return true
end
