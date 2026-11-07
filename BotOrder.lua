-- TortoiseBotsManager/BotOrder.lua
-- Guild orders: give a claimed guild bot a farm / buy / craft order from the
-- Guild tab and watch its progress live.
--
-- The server advertises "guild-orders" in TBM:CAPS. No capability: no Order
-- buttons, no window, no sends. Every CAPS line replaces the set, so the
-- gate is re-checked on each one (as BotLoot.lua does).
--
-- Contract (TortoiseBots#1525 "Guild orders: who-can-make, materials I bring"):
-- the guild-wide pick-a-bot mode, per-enchant search, and the bring= ticks.
-- Sends (byte-exact, all gated on the guild-orders capability like above):
--   "order search <craft|enchant> <text>"             -> guild-wide matches
--     (no bot: a first argument of farm|buy|craft|enchant means no bot)
--   "order search <Bot> enchant <text>"               -> that bot's enchants
--   "order <bot> preview <craft> <itemId> <n> [bring=<id>,<id>]"
--     (craft only: unticked reagents ride no field; old servers answering
--     invalid shed the bring field first, then the pending-give tail)
--   "order <bot> <farm|buy|craft> <itemId> <n> [hours|inf] [keep] [gold=<copper>] [bring=<id>,<id>]"
--     (same order as today, bring last; give retry sheds bring first)
-- Inbound:
--   TBM:ORDER_WHO_BEGIN|<kind>|<n>, then per match
--   TBM:ORDER_WHO|<kind>|<id>|<name>|<quality>|<slot>|<reqSkill>|<bots>,
--   then TBM:ORDER_WHO_END. <kind> craft|enchant; <bots> is
--   "name:skill:have:need:busy;..." online bots only, skill high to low,
--   busy 1 while that bot runs an order ("-" or empty = none). At most 30.
--   TBM:ORDER_ENCHANTS_BEGIN|<n>, then per match
--   TBM:ORDER_ENCHANT|<spellId>|<name>|<slot>|<reqSkill>|<verdict>|<reagents>,
--   then TBM:ORDER_ENCHANTS_END. <verdict> ok or a reason token;
--   <reagents> is "itemId:need:have;..." per reagent ("-" or empty = none).
--   TBM:ORDER_PREVIEW| and TBM:ORDER| each carry ONE new trailing <bring>
--   field: ticked itemIds joined by ",", or "-" (missing on old servers
--   means nothing ticked).
-- A who or enchants pair for another bot (or the other kind) never touches
-- the shown rows; an empty pair is a real answer.
-- Contract (TortoiseBots#1384 "Guild orders: guild bank as the crafting store"):
-- the player sees live who does what and can step in from the addon.
-- Sends (byte-exact):
--   "order list"                                   -> full snapshot (orders
--     plus TBM:ORDER_ACCESS first inside the pair)
--   "order search <bot> <farm|buy|craft> [cat=<category>] <text>"
--   "order search <bot> enchant <text>"
--   "order <bot> <farm|buy|craft> <itemId> <n> [hours|inf] [keep] [gold=<copper>]"
--   "order <bot> enchant <spellId>"
--   "order <bot> meet" (walk to the giver for the enchant trade)
--     (gold omitted with no cap; an old server answering invalid sheds the
--     newest trailing field first: gold, then keep, then a refused inf
--     retries once as 24, then bare)
--   "order rank <rankIndex>"                        -> bots' guild rank (ACK
--     or ERR, then TBM:ORDER_ACCESS)
--   "order access"                                  -> TBM:ORDER_ACCESS now
--   "order reassign <subOrderBot> <newBot>"         -> hand a sub-order over
--   "order <bot> cancel"                            -> on a parent cancels
--     the whole branch
--   "order <bot> steps"                             -> TBM:ORDER_STEPS_* for
--     that bot's order (capability "guild-order-steps", memory only)
-- Inbound:
--   TBM:ORDER_BEGIN|<n>
--   TBM:ORDER|<bot>|<type>|<itemId>|<item>|<have>|<want>|<state>|<reason>|<zone>|<difficulty>|<hours>|<keep>|<parent>|<goldCap>|<step>|<need>|<carry>
--   TBM:ORDER_END
--   TBM:ORDER_STEPS_BEGIN|<bot>|<n>|<dropped>   (the answer to "order <bot>
--   TBM:ORDER_STEP|<bot>|<ageSec>|<state>|<reason>|<step>|<itemId>   steps":
--   TBM:ORDER_STEPS_END|<bot>                   oldest first, "TBM:ORDER" tokens)
--   TBM:ORDER_ACCESS|<rankIndex>|<rankName>|<tabsOk>|<tabsDenied>|<gold 0/1>|<canSetRank 0/1>
--   TBM:ORDER_ITEMS_BEGIN|<n>
--   TBM:ORDER_ITEM|<itemId>|<item>|<quality>|<sources>|<minLevel>|<skill>|<verdict>|<zone>|<chance>|<difficulty>|<category>
--   TBM:ORDER_ITEMS_END
--   TBM:ORDER_ENCHANTS_BEGIN|<n>, TBM:ORDER_ENCHANT|<spellId>|<name>|<slot>|<reqSkill>|<verdict>|<reagents>,
--   TBM:ORDER_ENCHANTS_END (the answer to "order search <bot> enchant <text>"; <reagents> is
--   itemId:need:have per reagent, ";" between rows, "-" when none)
--   TBM:ACTION_ACK|order|bot:<Bot>|1|<farm|buy|craft|enchant|cancel|rank|reassign>
--   TBM:ACTION_ACK|order|bot:<Bot>|1|meet coming|meet later|meet gathering (plus
--   the same words as plain system text, which paints the status line)
--   TBM:ACTION_ERR|order|<notcapital|noorder|busy|cooldown|nothingtobring>|<message>
--   (the message shows as-is on screen and in the window; a cooldown refusal
--   ("... Try again in N min.") greys the bot's Meet button for N minutes;
--   the row repaints from the live TBM:ORDER line)
-- A TBM:ORDER line inside BEGIN/END is the full list (replace the whole
-- set); outside a pair it is a live update for one bot (update that row
-- only). The search pair is its own stream, so an empty result is a real
-- answer. Unknown state / reason / step tokens are shown raw, never crash.
-- The step pair is its own stream too: the addon asks on hover of a guild row
-- (one request per bot per 15 s, cap token "guild-order-steps") and shows the
-- newest entries at the end of the order tooltip. The server keeps at most 16
-- entries in memory (it resets on restart, a new order or a reassign) and
-- <dropped> counts the older ones it no longer keeps.
-- <reason> "-" means none; <zone> "-" means none; <chance> is percent.
-- <difficulty> is easy / medium / hard ("-" or a missing field on old
-- servers means none); <reason> and <verdict> may be "elite", "timeout",
-- "noprogress", "needitems", "nobanker", "bankdenied", "noauctioneer" or
-- "nolisting" (the last four ride state "working"). <keep> is keep or "-" (missing on old servers means not
-- keep); a keep order that delivered sits in state "stocked" until the bank
-- runs low. <hours> is whole hours or "inf" for no limit (missing on
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
-- trade them, mail them or put them in the guild bank; a working row may also
-- carry a non-empty need list.
-- <have> counts delivered only (bank deposit or the mail hand-over to the
-- guild master); <carry> is what the bot holds in its bags plus its mailbox,
-- not yet delivered ("-" or a missing field on old servers means none). A
-- `working` row with carry > 0 shows "(+N carrying)" after the progress.
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

-- Order window picks. Declared up here: the order builders and parsers
-- above the window code read them (they were globals by accident).
local orderHours = 1
local selectedItemId = nil
local function now() return (GetTime and GetTime()) or 0 end

-- ── capability gate + permission ─────────────────────────────────────────
function TB.HasOrderCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

-- Player Buy orders are refused while the server sends guild-order-nobuy.
-- Servers without the token keep today's behaviour (Buy allowed).
function TB.PlayerBuyAllowed()
    if not TB.HasServerCapability then return true end
    return not TB.HasServerCapability("guild-order-nobuy")
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
local TYPE_LABEL = { farm = "Farm", buy = "Buy", craft = "Craft", enchant = "Enchant" }
local STATE_LABEL = {
    working = "Working", waiting = "Waiting", delivering = "Delivering",
    done = "Done", stocked = "Stocked", mailed = "Mailed", noskill = "No skill", cant = "Can't",
    ready = "Ready", coming = "Coming", enchanting = "Enchanting",
}
local STATE_COLOR = {
    working = "|cff4ecb5a", waiting = "|cffffd200", delivering = "|cffffd200",
    done = "|cff4ecb5a", stocked = "|cff4ecb5a", mailed = "|cffffd200", noskill = "|cffff5050", cant = "|cffff5050",
    ready = "|cff4ecb5a", coming = "|cffffd200", enchanting = "|cffffd200",
}
local REASON_LABEL = {
    grouped = "in a group", noskill = "missing profession", lowskill = "skill too low",
    lowlevel = "bot under level 10", norange = "nothing in level range",
    nosource = "no source", norecipe = "unknown recipe", elite = "only from elite creatures",
    timeout = "farm time ran out", noprogress = "no progress - the bot found nothing to farm",
    stuck = "stuck, gave up", bagsfull = "bags full", nobank = "no bank deposit",
    needitems = "needs items from you",
    nobanker = "no banker in reach", bankdenied = "bank refused withdrawal",
    noauctioneer = "no auctioneer in reach", nolisting = "nothing fitting on the AH",
    enchant = "enchants cannot be ordered yet", bound = "soulbound when made",
    needsprofession = "needs a profession to use", cooldown = "long recipe cooldown",
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
-- The capital an enchant order meets in, by the player's faction: Stormwind
-- for the Alliance, Orgrimmar for the Horde. UnitFactionGroup is missing in
-- the harness and on some clients, so anything but Horde reads Alliance.
function TB.OrderCapital()
    if UnitFactionGroup then
        local faction = UnitFactionGroup("player")
        if faction and string.lower(faction) == "horde" then return "Orgrimmar" end
    end
    return "Stormwind"
end
-- The player's current zone: GetRealZoneText names the minimap zone, falling
-- back to GetZoneText. Missing APIs (or an empty zone) mean unknown.
function TB.OrderPlayerZone()
    local zone = nil
    if GetRealZoneText then zone = GetRealZoneText() end
    if (not zone or zone == "") and GetZoneText then zone = GetZoneText() end
    zone = trim(zone or "")
    if zone == "" then return nil end
    return zone
end
-- Meet waits for the capital the order names: Stormwind or Orgrimmar by the
-- player's faction. Zone text compares literally; unknown zone never counts
-- as the capital.
function TB.OrderInCapital()
    local zone = TB.OrderPlayerZone()
    if not zone then return false end
    return zone == TB.OrderCapital()
end
-- Unfinished enchant orders are the ones that still need Meet: anything but
-- done (and cant/noskill, which end the order the same way). Unknown states
-- show the button too, never hide it on a new token.
function TB.OrderNeedsMeet(order)
    if not order or string.lower(trim(order.type or "")) ~= "enchant" then return false end
    local state = string.lower(trim(order.state or ""))
    return state ~= "done" and state ~= "cant" and state ~= "noskill"
end
-- Meet cooldowns, per bot: the server refuses a Meet it just refused with
-- "cooldown ... N min", and the button stays greyed with the countdown until
-- the stored time passes. Cleared when the order leaves that bot.
local meetCooldownUntil = {}
local MEET_COOLDOWN_CAP = 60 * 60
function TB.SetOrderMeetCooldown(bot, seconds)
    bot = norm(bot)
    seconds = math.floor(tonumber(seconds) or 0)
    if not bot then return nil end
    if seconds <= 0 then
        meetCooldownUntil[bot] = nil
        return nil
    end
    if seconds > MEET_COOLDOWN_CAP then seconds = MEET_COOLDOWN_CAP end
    meetCooldownUntil[bot] = now() + seconds
    return meetCooldownUntil[bot]
end
function TB.GetOrderMeetCooldown(bot)
    bot = norm(bot)
    if not bot then return nil end
    local untilAt = meetCooldownUntil[bot]
    if not untilAt then return nil end
    local left = untilAt - now()
    if left <= 0 then
        meetCooldownUntil[bot] = nil
        return nil
    end
    return left
end
function TB.ClearOrderMeetCooldown(bot)
    bot = norm(bot)
    if bot then meetCooldownUntil[bot] = nil end
end
-- Meet button state for one guild row: enabled plus the greyed-out reason.
-- Gathering (working) never meets; waiting+needitems meets only when the
-- bags hold something from the need list; a known zone outside the capital
-- and a remembered cooldown keep the button waiting (unknown zone cannot
-- tell, so it stays enabled). Returns true when the click may go out, else
-- false and the tooltip reason.
function TB.OrderMeetState(order)
    if not order then return false, nil end
    if not TB.OrderNeedsMeet(order) then return false, nil end
    local state = string.lower(trim(order.state or ""))
    if state == "working" then
        return false, "Still gathering materials"
    end
    if state == "waiting" and string.lower(trim(order.reason or "")) == "needitems" then
        local held = false
        for _, entry in ipairs(order.need or {}) do
            if TB.OrderBagCount(entry.id) > 0 then held = true break end
        end
        if not held then
            local names = {}
            for _, entry in ipairs(order.need or {}) do
                local label = nil
                if GetItemInfo then label = GetItemInfo(entry.id) end
                table.insert(names, label or ("item #" .. tostring(entry.id)))
            end
            if table.getn(names) == 0 then
                return false, "You carry none of the missing materials"
            end
            return false, "You carry none of the missing materials: " .. table.concat(names, ", ")
        end
    end
    local left = TB.GetOrderMeetCooldown(order.bot)
    if left then
        local mins = math.floor((left + 59) / 60)
        if mins < 1 then mins = 1 end
        return false, "Try again in " .. mins .. " min"
    end
    local zone = TB.OrderPlayerZone()
    local capital = TB.OrderCapital()
    if zone and zone ~= capital and zone ~= capital .. " City" then
        return false, "Go to " .. capital
    end
    return true, nil
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

-- ── send missing items (mailbox) ─────────────────────────────────────────
-- The button never mails anything on its own: it fills the Send Mail form
-- for the bot that needs items and attaches one stack from the bags. The
-- player presses Send (items and postage are irreversible).
local MAIL_BAGS = 5 -- bags 0..4 (backpack plus equipped bags)

local function orderHasNeed(order)
    return order and order.need and table.getn(order.need) > 0
end

-- First bot in the window's tree (root, then children depth-first) whose
-- order needs items. Returns bot, order, or nil.
function TB.OrderNeedTarget(rootBot)
    rootBot = norm(rootBot)
    if not rootBot then return nil end
    local rootOrder = TB.GetBotOrder(rootBot)
    if not rootOrder then return nil end
    if orderHasNeed(rootOrder) then return rootBot, rootOrder end
    local function visit(parentBot)
        for _, child in ipairs(TB.OrderChildren(parentBot)) do
            if orderHasNeed(child) then return child.bot, child end
            local bot, order = visit(child.bot)
            if bot then return bot, order end
        end
        return nil
    end
    return visit(rootBot)
end

-- The mail the button would fill: recipient, subject, need body. nil when
-- the order needs nothing.
function TB.OrderMailDraft(bot, order)
    if not orderHasNeed(order) then return nil end
    return {
        to = bot,
        subject = "Order: " .. (order.item or "item"),
        body = TB.OrderNeedText(order),
    }
end

-- One bag stack for the first need entry that is in bags 0..4. Sparse
-- stacks are skipped; locked stacks are skipped. split is the need count
-- when the stack is larger (a partial attach), else nil (whole stack).
function TB.FindOrderNeedStack(order)
    if not orderHasNeed(order) then return nil end
    if not (GetContainerNumSlots and GetContainerItemLink and GetContainerItemInfo) then return nil end
    for _, entry in ipairs(order.need) do
        local needCount = entry.count or 0
        if needCount > 0 then
            for bag = 0, MAIL_BAGS - 1 do
                local slots = GetContainerNumSlots(bag) or 0
                for slot = 1, slots do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        local _, _, idText = string.find(link, "item:(%d+)")
                        if tonumber(idText) == entry.id then
                            local _, count, locked = GetContainerItemInfo(bag, slot)
                            if not locked and count and count > 0 then
                                local split = nil
                                if count > needCount then split = needCount end
                                return { bag = bag, slot = slot, id = entry.id, count = count, split = split }
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- The item in the Send Mail attachment slot: 1.12 GetSendMailItem() returns
-- itemName, itemTexture, stackCount, quality (MailFrame.lua, build 5803).
-- Both nil when the slot is empty.
local function sendMailItem()
    if not GetSendMailItem then return nil, nil end
    local name, _, count = GetSendMailItem()
    if name == "" then name = nil end
    return name, tonumber(count)
end

-- The globals the attach needs, by name: the pickup call for this path
-- (split or whole stack), the attach click, the cursor probe and the
-- read-back. Names, so the message can say which one is missing.
local function missingMailApis(split)
    local missing = {}
    if split then
        if not SplitContainerItem then table.insert(missing, "SplitContainerItem") end
    elseif not PickupContainerItem then
        table.insert(missing, "PickupContainerItem")
    end
    if not ClickSendMailItemButton then table.insert(missing, "ClickSendMailItemButton") end
    if not CursorHasItem then table.insert(missing, "CursorHasItem") end
    if not GetSendMailItem then table.insert(missing, "GetSendMailItem") end
    return missing
end

-- The button is live only at an open mailbox with a bot that needs items.
function TB.CanSendOrderItems(rootBot)
    if not (MailFrame and MailFrame.IsVisible and MailFrame:IsVisible()) then
        return false, "Open a mailbox first"
    end
    if not TB.OrderNeedTarget(rootBot) then
        return false, "No order needs items"
    end
    return true, nil
end

-- Fill the form and attach one stack. Never sends. Returns true when the
-- form was filled (with or without an attachment). A busy cursor or a filled
-- attachment slot stops the attach: the pickup would swap one of the two
-- items into the mail, which is worse than attaching nothing.
function TB.SendOrderMissingItems(rootBot)
    local bot, order = TB.OrderNeedTarget(rootBot)
    if not bot then return false end
    local draft = TB.OrderMailDraft(bot, order)
    if not draft then return false end
    -- A draft the player is already composing is left alone: with an item on
    -- the cursor or in the attachment slot, re-addressing the form would send
    -- that item to the bot. Check before any field changes.
    if CursorHasItem and CursorHasItem() then
        TB.SetOrderFeedback("Nothing changed: your cursor holds an item - drop or place it first", "error")
        return false
    end
    local busyName = sendMailItem()
    if busyName then
        TB.SetOrderFeedback("Nothing changed: the mail already holds " .. busyName .. " - send or clear it first", "error")
        return false
    end
    -- A text-only draft is the player's too: never overwrite it.
    local function boxText(box) return box and box.GetText and box:GetText() or "" end
    if boxText(SendMailNameEditBox) ~= "" or boxText(SendMailSubjectEditBox) ~= ""
        or boxText(SendMailBodyEditBox) ~= "" then
        TB.SetOrderFeedback("Nothing changed: the mail form already has text - clear it first", "error")
        return false
    end
    -- D4: open the Send tab and fill the boxes (guard every global).
    if MailFrameTab_OnClick then MailFrameTab_OnClick(2) end
    if SendMailNameEditBox and SendMailNameEditBox.SetText then SendMailNameEditBox:SetText(draft.to) end
    if SendMailSubjectEditBox and SendMailSubjectEditBox.SetText then SendMailSubjectEditBox:SetText(draft.subject) end
    if SendMailBodyEditBox and SendMailBodyEditBox.SetText then SendMailBodyEditBox:SetText(draft.body) end
    local stack = TB.FindOrderNeedStack(order)
    if not stack then
        TB.SetOrderFeedback("None of the needed items are in your bags", "error")
        return true
    end
    local attached = stack.split or stack.count
    local itemName = needName(stack.id)
    -- No half-blind attach: without the pickup call, the attach click, the
    -- cursor probe and the read-back, nothing is moved at all.
    local missing = missingMailApis(stack.split)
    if table.getn(missing) > 0 then
        TB.SetOrderFeedback("Nothing attached: this client has no "
            .. table.concat(missing, ", "), "error")
        return true
    end
    -- The cursor and the attachment slot were checked empty before the form
    -- was touched (top of this function), so the pickup cannot swap anything.
    if stack.split then
        SplitContainerItem(stack.bag, stack.slot, stack.split)
    else
        PickupContainerItem(stack.bag, stack.slot)
    end
    ClickSendMailItemButton()
    -- The client is the only witness: a wrong item, a wrong count or an
    -- item left on the cursor is an error, never "attached".
    local sentName, sentCount = sendMailItem()
    if CursorHasItem() or sentName ~= itemName or sentCount ~= attached then
        if ClearCursor then ClearCursor() end
        -- The wrong item may now sit in the attachment slot: clear the
        -- recipient so a Send cannot mail it to the bot.
        if SendMailNameEditBox and SendMailNameEditBox.SetText then SendMailNameEditBox:SetText("") end
        local shown = sentName and (sentName .. " x" .. tostring(sentCount)) or "no item"
        TB.SetOrderFeedback("Check the mail: it shows " .. shown .. " instead of " .. itemName
            .. " x" .. tostring(attached) .. " - recipient cleared", "error")
        return true
    end
    TB.SetOrderFeedback(itemName .. " x" .. tostring(attached) .. " attached - press Send", "ok")
    return true
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
--   difficulty, hours, keep, parent, goldCap, step, need, carry }
-- hours is a number, "inf" for no limit, or nil when the server sent none.
-- parent is the parent order's bot, or nil for a top-level order; goldCap is
-- guild gold in copper or nil for no cap; need is { {id, count} } of items
-- the player must bring, or nil; carry is bags plus mail not yet delivered
-- (nil on old servers without the field, treated as 0 in the display).
local orders = {}

-- Per-order step history, memory only: orderSteps[bot] = { entries, dropped,
-- receivedAt, type, itemId, parent }. entries hold the server's entries
-- oldest first; type + itemId (+ parent when the row has one) is the order
-- identity the list belongs to. stepsReceiving buffers one bot's list
-- between BEGIN and END; stepsAskedAt is the per-bot request throttle (one
-- ".bot order <bot> steps" per 15 s); stepsPending keeps the order identity
-- seen when the request went out, so a reply that lands after the bot moved
-- to a new order is dropped instead of stamped onto it.
local orderSteps = {}
local stepsReceiving = nil
local stepsAskedAt = {}
local stepsPending = {}

-- The order a step list belongs to. A new order on the same bot must not
-- show the old order's steps, so every cached list carries its order's
-- identity and the cache is dropped whenever the bot's current order
-- identity differs from it.
local function orderIdentity(order)
    if not order then return nil end
    local parent = order.parent
    if parent ~= nil then parent = string.lower(trim(parent or "")) end
    if parent == "" then parent = nil end
    return {
        type = string.lower(trim(order.type or "")),
        itemId = order.itemId,
        parent = parent,
    }
end

local function sameOrderIdentity(a, b)
    if not a or not b then return false end
    return a.type == b.type and a.itemId == b.itemId and a.parent == b.parent
end

-- Tooltip-side view of one order-step record's identity: the same lowered
-- key as orderIdentity, so a mixed-kind order ("Farm" vs "farm") still
-- matches the row it belongs to.
function TB.OrderStepIdentity(record)
    if not record then return nil end
    local parent = record.parent
    if parent ~= nil then parent = string.lower(trim(parent or "")) end
    if parent == "" then parent = nil end
    return {
        type = record.type and string.lower(trim(record.type or "")) or nil,
        itemId = record.itemId,
        parent = parent,
    }
end

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
-- tooltip (RefreshGuildView + the row tooltip in UI.lua). The live step
-- ("taking from guild bank", "farming in Elwynn" ...) joins working and
-- waiting rows (except needitems, whose rows name the need instead).
function TB.OrderRowText(order)
    if not order then return "" end
    local item = order.item or ("item #" .. tostring(order.itemId or "?"))
    local progress = tostring(order.have or 0) .. "/" .. tostring(order.want or 0)
    local carryCount = math.floor(tonumber(order.carry) or 0)
    if carryCount > 0 then progress = progress .. " (+" .. carryCount .. " carrying)" end
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
    elseif state == "ready" then
        text = item .. " · " .. word("Ready") .. " - come to " .. TB.OrderCapital() .. " and press Meet"
    elseif state == "coming" then
        text = item .. " · " .. word("On the way to you")
    elseif state == "enchanting" then
        text = item .. " · " .. word("Trade open - put your item in Will not be traded")
    else
        text = item .. " " .. progress .. " · " .. trim(order.state or "")
    end
    if (state == "working" or (state == "waiting" and string.lower(trim(order.reason or "")) ~= "needitems"))
        and order.need and table.getn(order.need) > 0
        and not string.find(text, "needs items from you", 1, true) then -- a "need" step label already says it
        text = text .. " · " .. "|cffffd200needs items from you|r"
    end
    if order.keep and state ~= "stocked" then text = text .. " · " .. word("Keep") end
    if order.hours == "inf" then text = text .. " · " .. word("No limit") end
    local diff = TB.OrderDifficultyLabel(order.difficulty)
    if diff then text = text .. " · " .. diff end
    return text
end

-- One order-window tree line: always names the bot, indented under its
-- parent ("  Silver: item 1/5 · ..."). A sub-order whose parent row is
-- missing or late shows as a root (no indent) until the parent arrives,
-- then re-indents; the name never drops.
function TB.OrderTreeRowText(order, depth)
    if not order then return "" end
    depth = tonumber(depth) or TB.OrderDepth(order)
    if depth < 0 then depth = 0 end
    return string.rep("  ", depth) .. (order.bot or "?") .. ": " .. TB.OrderRowText(order)
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
    local carryTip = math.floor(tonumber(order.carry) or 0)
    if carryTip > 0 then
        table.insert(lines, "Carrying " .. carryTip .. " (in bags and mail, not yet delivered).")
    elseif order.carry == nil and string.lower(trim(order.state or "")) == "working"
        and (order.want or 0) > 0 and (order.have or 0) >= order.want then
        table.insert(lines, "Not deliverable yet: part of the count is not in the bot's bags (usually still in its mail). It delivers once all are in its bags.")
    end
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
    -- The step timeline rides at the end: newest steps with their age, fetched
    -- on hover (nothing on servers without the guild-order-steps token).
    for _, stepLineText in ipairs(TB.OrderStepsTooltipLines(order.bot)) do
        table.insert(lines, stepLineText)
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
-- Ticked "I bring it" reagent ids for the craft preview. Resets on pick,
-- bot switch and preview commit; auto-ticks fill from the player's bags.
-- Declared here (before ParseOrderMessage) so the preview commit can seed
-- the ticks; the window setters below reuse the same locals.
local resetOrderBring
local orderBring = {}
function TB.GetOrderBring()
    local out = {}
    for _, id in ipairs(orderBring or {}) do table.insert(out, id) end
    return out
end
function TB.SetOrderBring(ids)
    local seen, out = {}, {}
    for _, id in ipairs(ids or {}) do
        id = math.floor(tonumber(id) or 0)
        if id > 0 and not seen[id] then seen[id] = true table.insert(out, id) end
    end
    table.sort(out)
    orderBring = out
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return TB.GetOrderBring()
end
function TB.ToggleOrderBring(itemId)
    itemId = math.floor(tonumber(itemId) or 0)
    if itemId <= 0 then return TB.GetOrderBring() end
    local out = {}
    local found = false
    for _, id in ipairs(orderBring or {}) do
        if id == itemId then found = true
        else table.insert(out, id) end
    end
    if not found then table.insert(out, itemId) end
    return TB.SetOrderBring(out)
end
resetOrderBring = function(reagents)
    local out = {}
    for _, row in ipairs(reagents or {}) do
        if TB.OrderBringAutoTicked(row) then table.insert(out, row.itemId) end
    end
    orderBring = {}
    return TB.SetOrderBring(out)
end

-- ── step history ──────────────────────────────────────────────────────────
-- One bot's step timeline: ".bot order <bot> steps" is answered with
-- TBM:ORDER_STEPS_BEGIN|<bot>|<n>|<dropped>, n TBM:ORDER_STEP lines (oldest
-- first) and TBM:ORDER_STEPS_END|<bot>. The server keeps at most 16 entries in
-- memory and counts the dropped older ones; the addon shows the newest ones in
-- the order tooltip. Tokens are the TBM:ORDER ones ("-" = none, itemId 0 =
-- none); errors ride the existing order action-error codes (no-bot, not-guild).
local STEP_SHOWN = 8
local STEPS_THROTTLE = 15
-- One steps reply on the wire at a time: a resting hover on another bot waits
-- until the current END lands (or 5 s pass), so a sweep never floods the send
-- queue. The in-flight bot and its send time; empty means idle.
local stepsFlightAt = nil
local STEPS_FLIGHT_TIMEOUT = 5
-- The most entries one reply may carry (the server's memory cap). A BEGIN
-- count above it is refused; a reply whose valid entries fall short of its
-- BEGIN count is discarded. stepsMissed[bot] = { identity } marks a bot whose
-- last reply was discarded: its tooltip says so while it still shows that order.
local STEPS_PROTOCOL_MAX = 16
local stepsMissed = {}

-- Drop a reply that cannot be trusted: free the buffer and the bot's throttle
-- so the next hover asks again, flag the tooltip for the order the bot holds
-- now, and repaint. The cached list stays as it was.
local function discardSteps(bot)
    stepsReceiving = nil
    stepsPending[bot] = nil
    stepsAskedAt[bot] = nil
    if next(stepsPending) == nil then stepsFlightAt = nil end
    stepsMissed[bot] = { identity = orderIdentity(orders[bot]) }
    if TB.RepaintGuildRowTooltip then TB.RepaintGuildRowTooltip(bot) end
end

-- TBM:ORDER_STEP|<bot>|<ageSec>|<state>|<reason>|<step>|<itemId>: exactly six
-- fields, bot non-empty, age and itemId whole numbers >= 0.
function TB.ParseOrderStepLine(msg)
    if string.sub(msg or "", 1, 15) ~= "TBM:ORDER_STEP|" then return nil end
    local fields = splitProtocol(string.sub(msg, 16))
    if table.getn(fields) ~= 6 then return nil end
    local bot = norm(trim(fields[1]))
    if not bot or bot == "" then return nil end
    local age = tonumber(trim(fields[2]))
    local state = trim(fields[3])
    local itemId = tonumber(trim(fields[6]))
    if not age or not itemId or age < 0 or itemId < 0 or state == "" then return nil end
    return {
        bot = bot, age = math.floor(age), state = state,
        reason = noneDash(fields[4]), step = noneDash(fields[5]),
        itemId = math.floor(itemId),
    }
end

-- The cached list of one bot (entries oldest first, dropped, receivedAt), or
-- nil when none arrived yet.
function TB.GetOrderSteps(bot)
    bot = norm(bot)
    return bot and orderSteps[bot] or nil
end

-- Both gates: the order feature and the step-history token. Old servers are
-- never asked and their tooltips stay unchanged.
local function stepsCapable()
    return TB.HasOrderCapability() and TB.HasServerCapability("guild-order-steps")
end

-- Ask for one bot's step list; at most one request per bot per 15 s, and
-- only one steps request in flight at a time (a new one waits until the
-- current END arrives or 5 s pass). A live TBM:ORDER line that changes
-- state, reason or step clears the throttle so the next hover refetches
-- at once.
function TB.RequestOrderSteps(bot)
    if not stepsCapable() then return false end
    bot = norm(bot)
    if not bot then return false end
    if now() - (stepsAskedAt[bot] or -1000) < STEPS_THROTTLE then return false end
    if stepsFlightAt and now() - stepsFlightAt < STEPS_FLIGHT_TIMEOUT then
        local other = false
        for pending in pairs(stepsPending) do
            if pending ~= bot then other = true break end
        end
        if other then return false end
    end
    stepsAskedAt[bot] = now()
    stepsPending[bot] = orderIdentity(orders[bot])
    stepsFlightAt = now()
    return TB.SendBotCommand("order " .. bot .. " steps")
end

-- "just now", "5m ago", "2h ago", "2h 1m ago", "3d ago".
function TB.OrderStepAgeText(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    if sec < 60 then return "just now" end
    if sec < 3600 then return math.floor(sec / 60) .. "m ago" end
    if sec < 86400 then
        local h = math.floor(sec / 3600)
        local m = math.floor(math.mod(sec, 3600) / 60)
        if m == 0 then return h .. "h ago" end
        return h .. "h " .. m .. "m ago"
    end
    return math.floor(sec / 86400) .. "d ago"
end

-- One entry: what the bot did (the live step while working, else the state
-- word), which item the leg is for, and the reason in brackets.
function TB.OrderStepText(entry)
    if not entry then return nil end
    local base = nil
    if string.lower(trim(entry.state or "")) == "working" then
        base = TB.OrderStepLabel({ step = entry.step })
    end
    if not base then base = TB.OrderStateLabel(entry.state) end
    if (tonumber(entry.itemId) or 0) > 0 then
        base = base .. ": " .. needName(entry.itemId)
    end
    local reason = TB.OrderReasonLabel(entry.reason)
    if reason then base = base .. " (" .. reason .. ")" end
    return base
end

-- The tooltip block: the newest entries first (at most 8), then one line with
-- how many older steps are no longer kept. {} without a cache or with an
-- empty list.
local function stepsBlockLines(bot)
    if not stepsCapable() then return {} end
    local record = TB.GetOrderSteps(bot)
    if not record or not record.entries or table.getn(record.entries) == 0 then return {} end
    -- The cache belongs to one order: while the bot holds a different order,
    -- show nothing until that order's own reply lands. With no current order
    -- there is no tooltip anyway, so the stranded list still reads.
    local current = orders[norm(bot)]
    if current and not sameOrderIdentity(TB.OrderStepIdentity(record), TB.OrderStepIdentity(current)) then return {} end
    local lines = { "Steps (newest first):" }
    local entries = record.entries
    local count = table.getn(entries)
    local shown = 0
    local drift = now() - (record.receivedAt or now())
    for i = count, 1, -1 do
        if shown >= STEP_SHOWN then break end
        local age = (tonumber(entries[i].age) or 0) + drift
        table.insert(lines, "  " .. TB.OrderStepAgeText(age) .. " · " .. TB.OrderStepText(entries[i]))
        shown = shown + 1
    end
    local earlier = (count - shown) + (record.dropped or 0)
    if earlier > 0 then
        table.insert(lines, "  ... " .. earlier .. " earlier steps")
    end
    return lines
end

-- The step lines for a bot's tooltip: the "history incomplete, retrying" flag
-- while its last reply was discarded for the order it holds now, then the
-- step block. {} without the capability.
function TB.OrderStepsTooltipLines(bot)
    if not stepsCapable() then return {} end
    local key = norm(bot)
    local lines = {}
    local missed = key and stepsMissed[key]
    local current = key and orders[key]
    if missed and (not current or sameOrderIdentity(missed.identity, orderIdentity(current))) then
        table.insert(lines, "Steps: history incomplete, retrying")
    end
    for _, line in ipairs(stepsBlockLines(bot)) do
        table.insert(lines, line)
    end
    return lines
end

function TB.ParseOrderLine(msg)
    if string.sub(msg or "", 1, 10) ~= "TBM:ORDER|" then return nil end
    local fields = splitProtocol(string.sub(msg, 11))
    local count = table.getn(fields)
    if count < 9 then return nil end
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
        if not need then return nil end
    end
    local bring = {}
    if count >= 18 then
        bring = TB.ParseOrderBring(fields[18])
        if not bring then return nil end
    end
    local carry = nil
    if count >= 17 and trim(fields[17]) ~= "-" then
        local n = tonumber(trim(fields[17]))
        if n and n >= 0 then carry = math.floor(n) end
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
        need = need, carry = carry, bring = bring,
    }
end
-- ── materials I bring ─────────────────────────────────────────────────────
-- Ticks for the craft preview: ticked ids joined by "," or "-" when none.
-- Missing GetContainer* APIs mean no bags, never a crash.
function TB.OrderBagCount(itemId)
    itemId = math.floor(tonumber(itemId) or 0)
    if itemId <= 0 then return 0 end
    if not (GetContainerNumSlots and GetContainerItemLink and GetContainerItemInfo) then
        return 0
    end
    local total = 0
    for bag = 0, MAIL_BAGS - 1 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, idText = string.find(link, "item:(%d+)")
                if tonumber(idText) == itemId then
                    local _, count, locked = GetContainerItemInfo(bag, slot)
                    if not locked and count and count > 0 then
                        total = total + math.floor(count)
                    end
                end
            end
        end
    end
    return total
end
-- Auto-tick when the player's own bags hold the full need count of a
-- reagent: with only part of it the bot still sources the rest, so the
-- row stays unticked.
function TB.OrderBringAutoTicked(reagent)
    if not reagent then return false end
    local need = tonumber(reagent.need) or 0
    if need <= 0 then return false end
    return TB.OrderBagCount(reagent.itemId) >= need
end
function TB.OrderBringTicked(bring, itemId)
    itemId = math.floor(tonumber(itemId) or 0)
    for _, id in ipairs(bring or {}) do
        if id == itemId then return true end
    end
    return false
end
function TB.OrderBringText(bring)
    if not bring or table.getn(bring) == 0 then return "-" end
    local parts = {}
    for _, id in ipairs(bring) do table.insert(parts, tostring(id)) end
    return table.concat(parts, ",")
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
-- real bank and a denied tab shows red; gold 0 alone is normal below officer
-- (bots buy with their own gold) and stays plain. "-" rank (server leaves
-- ranks alone) and no-bank-yet stay grey.
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
    if orderAccess.tabsDenied then
        return { text = head .. " · " .. tail .. " (tabs "
            .. TB.OrderTabList(orderAccess.tabsDenied) .. " denied)", bad = true }
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
-- ── guild-wide search (who-can-make) ──────────────────────────────────────
-- TBM:ORDER_WHO|<kind>|<id>|<name>|<quality>|<slot>|<reqSkill>|<bots>:
-- seven fields after the prefix; bots is "name:skill:have:need:busy;...",
-- "-" when no bot knows it. Enchant matches sort by reqSkill up on the
-- server; craft keeps today's server order.
function TB.ParseOrderWhoBots(text)
    text = trim(text or "")
    if text == "" or text == "-" then return {} end
    local out = {}
    for token in string.gfind(text, "[^;]+") do
        local _, _, name, skillText, haveText, needText, busyText =
            string.find(trim(token), "^([^:]+):(%d+):(%d+):(%d+):(%d+)$")
        local bot = norm(name)
        local skill, have, need, busy = tonumber(skillText), tonumber(haveText),
            tonumber(needText), tonumber(busyText)
        if not bot or bot == "" or not skill or not have or not need or not busy then
            return nil
        end
        if busy ~= 0 and busy ~= 1 then return nil end
        table.insert(out, { bot = bot, skill = math.floor(skill),
            have = math.floor(have), need = math.floor(need), busy = busy == 1 })
    end
    if table.getn(out) == 0 then return nil end
    return out
end
function TB.ParseOrderWhoLine(msg)
    if string.sub(msg or "", 1, 14) ~= "TBM:ORDER_WHO|" then return nil end
    local fields = splitProtocol(string.sub(msg, 15))
    if table.getn(fields) ~= 7 then return nil end
    local kind = string.lower(trim(fields[1]))
    if kind ~= "craft" and kind ~= "enchant" then return nil end
    local id = tonumber(trim(fields[2]))
    local name = trim(fields[3])
    if not id or id <= 0 or name == "" then return nil end
    local quality = nil
    if trim(fields[4]) ~= "-" then
        quality = tonumber(trim(fields[4]))
        if not quality then return nil end
        quality = math.floor(quality)
    end
    local slot = noneDash(fields[5])
    local reqSkill = tonumber(trim(fields[6]))
    if not reqSkill or reqSkill < 0 then return nil end
    local bots = TB.ParseOrderWhoBots(fields[7])
    if not bots then return nil end
    return { kind = kind, id = math.floor(id), item = name, quality = quality,
        slot = slot, reqSkill = math.floor(reqSkill), bots = bots }
end
-- TBM:ORDER_ENCHANT|<spellId>|<name>|<slot>|<reqSkill>|<verdict>|<reagents>:
-- six fields after the prefix; reagents is "itemId:need:have;...". Rows keep
-- the per-bot catalogue shape: the spell id rides as itemId.
function TB.ParseOrderEnchantReagents(text)
    text = trim(text or "")
    if text == "" or text == "-" then return {} end
    local out = {}
    for token in string.gfind(text, "[^;]+") do
        local _, _, idText, needText, haveText = string.find(trim(token), "^(%d+):(%d+):(%d+)$")
        local id, need, have = tonumber(idText), tonumber(needText), tonumber(haveText)
        if not id or not need or not have or id <= 0 or need <= 0 or have < 0 then
            return nil
        end
        table.insert(out, { itemId = math.floor(id), need = math.floor(need), have = math.floor(have) })
    end
    if table.getn(out) == 0 then return nil end
    return out
end
function TB.ParseOrderEnchantLine(msg)
    if string.sub(msg or "", 1, 18) ~= "TBM:ORDER_ENCHANT|" then return nil end
    local fields = splitProtocol(string.sub(msg, 19))
    if table.getn(fields) ~= 6 then return nil end
    local spellId = tonumber(trim(fields[1]))
    local name = trim(fields[2])
    local verdict = trim(fields[5])
    if not spellId or spellId <= 0 or name == "" or verdict == "" then return nil end
    local reagents = TB.ParseOrderEnchantReagents(fields[6])
    if not reagents then return nil end
    return {
        itemId = math.floor(spellId), item = name,
        slot = noneDash(fields[3]), skill = noneDash(fields[4]),
        verdict = verdict, reagents = reagents,
    }
end
-- Last guild-wide search: { kind, text, rows }. Rows arrive in server order,
-- capped at 30.
local WHO_MAX = 30
local lastWhoSearch = { kind = "craft", text = "", rows = {} }
local whoReceiving, whoKind, whoText = nil, nil, nil
function TB.GetOrderWhoSearch()
    return { kind = lastWhoSearch.kind, text = lastWhoSearch.text, rows = lastWhoSearch.rows or {} }
end
-- One who-can-make row for the pick-a-bot list: name (+ slot and required
-- skill for enchant), then each bot "name skill have/need" with a busy mark.
function TB.OrderWhoBotText(entry)
    if not entry then return nil end
    local parts = {}
    for _, bot in ipairs(entry.bots or {}) do
        local text = bot.bot .. " " .. tostring(bot.skill or 0)
            .. " " .. tostring(bot.have or 0) .. "/" .. tostring(bot.need or 0)
        if bot.busy then text = text .. " (busy)" end
        table.insert(parts, text)
    end
    return table.concat(parts, ", ")
end
function TB.OrderWhoRowText(entry)
    if not entry then return "" end
    local head = entry.item or ("item #" .. tostring(entry.id or "?"))
    if entry.kind == "enchant" then
        head = head .. " (" .. (entry.slot or "?") .. " " .. tostring(entry.reqSkill or 0) .. ")"
    end
    local bots = TB.OrderWhoBotText(entry)
    if not bots or bots == "" then return head .. " - no guild bot knows it" end
    return head .. " - " .. bots
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

-- ── order preview ─────────────────────────────────────────────────────────
-- TBM:ORDER_PREVIEW|<bot>|<type>|<itemId>|<item>|<want>|<missing>|<difficulty>|<zone>|<reagents>|<minutes>|<goldCap>
-- <reagents> is "itemId:need:bags:mail:bank:farm:zone:ah:vendor:sub:player;..."
-- or "-" (zone "-" means none; names come from the server, no client map).
-- <goldCap> is copper or "-" for no cap. A refusal rides the existing order
-- ACTION_ERR codes (buy-disabled, norecipe, ...), never a preview line.
-- A trailing <bring> field ("id,id" or "-", missing on old servers) names
-- the reagents the player ticks as "I bring it".
local orderPreview = nil
local previewPending = nil
-- A re-ask after the amount changes, fired once typing pauses.
local previewDueAt = nil

-- One reagent row: exactly eleven colon fields, ids and counts whole >= 0.
function TB.ParseOrderPreviewReagent(text)
    local fields = {}
    local start = 1
    while true do
        local at = string.find(text or "", ":", start, true)
        if at then
            table.insert(fields, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(fields, string.sub(text or "", start))
            break
        end
    end
    if table.getn(fields) ~= 11 then return nil end
    local itemId = tonumber(trim(fields[1]))
    local need = tonumber(trim(fields[2]))
    local bags = tonumber(trim(fields[3]))
    local mail = tonumber(trim(fields[4]))
    local bank = tonumber(trim(fields[5]))
    local farm = tonumber(trim(fields[6]))
    local zone = trim(fields[7])
    local ah = tonumber(trim(fields[8]))
    local vendor = tonumber(trim(fields[9]))
    local sub = tonumber(trim(fields[10]))
    local player = tonumber(trim(fields[11]))
    if not itemId or not need or not bags or not mail or not bank or not farm
        or zone == "" or not ah or not vendor or not sub or not player then return nil end
    if itemId <= 0 or need <= 0 then return nil end
    if bags < 0 or mail < 0 or bank < 0 or farm < 0 then return nil end
    if ah < 0 or vendor < 0 or sub < 0 or player < 0 then return nil end
    if zone == "-" then zone = nil end
    return {
        itemId = math.floor(itemId), need = math.floor(need),
        bags = math.floor(bags), mail = math.floor(mail), bank = math.floor(bank),
        farm = math.floor(farm), zone = zone,
        ah = math.floor(ah), vendor = math.floor(vendor), sub = math.floor(sub),
        player = math.floor(player),
    }
end

function TB.ParseOrderPreviewReagents(text)
    text = trim(text or "")
    if text == "" or text == "-" then return {} end
    local out = {}
    for token in string.gfind(text, "[^;]+") do
        local row = TB.ParseOrderPreviewReagent(trim(token))
        if not row then return nil end
        table.insert(out, row)
    end
    if table.getn(out) == 0 then return nil end
    return out
end

-- TBM:ORDER_PREVIEW| plus its eleven fields and the trailing <bring> tick
-- list ("id,id", "-" or missing on old servers).
function TB.ParseOrderBring(text)
    text = trim(text or "")
    if text == "" or text == "-" then return {} end
    local out = {}
    for token in string.gfind(text, "[^,]+") do
        local id = tonumber(trim(token))
        if not id or id <= 0 then return nil end
        table.insert(out, math.floor(id))
    end
    if table.getn(out) == 0 then return nil end
    return out
end
function TB.ParseOrderPreviewLine(msg)
    if string.sub(msg or "", 1, 18) ~= "TBM:ORDER_PREVIEW|" then return nil end
    local fields = splitProtocol(string.sub(msg, 19))
    local count = table.getn(fields)
    if count ~= 11 and count ~= 12 then return nil end
    local bot = norm(trim(fields[1]))
    local kind = trim(fields[2])
    local itemId = tonumber(trim(fields[3]))
    local item = trim(fields[4])
    local want = tonumber(trim(fields[5]))
    local missing = tonumber(trim(fields[6]))
    if not bot or bot == "" or kind == "" then return nil end
    if not itemId or item == "" or not want or not missing then return nil end
    if itemId <= 0 or want <= 0 or want > 200 or missing < 0 then return nil end
    local difficulty = trim(fields[7] or "")
    if difficulty == "" or difficulty == "-" then difficulty = nil end
    local zone = trim(fields[8] or "")
    if zone == "" or zone == "-" then zone = nil end
    local reagents = TB.ParseOrderPreviewReagents(fields[9])
    if not reagents then return nil end
    local minutes = tonumber(trim(fields[10]))
    if not minutes or minutes < 0 then return nil end
    local goldCap = nil
    if trim(fields[11]) ~= "-" then
        goldCap = tonumber(trim(fields[11]))
        if not goldCap or goldCap < 0 then return nil end
        goldCap = math.floor(goldCap)
    end
    local bring = {}
    if count == 12 then
        bring = TB.ParseOrderBring(fields[12])
        if not bring then return nil end
    end
    return {
        bot = bot, kind = kind, itemId = math.floor(itemId), item = item,
        want = math.floor(want), missing = math.floor(missing),
        difficulty = difficulty, zone = zone, reagents = reagents,
        minutes = math.floor(minutes), goldCap = goldCap, bring = bring,
    }
end

function TB.GetOrderPreview()
    return orderPreview
end

-- Drop the shown and pending preview (pick changed, bot switched, Buy lost
-- its token): the panel hides until the next request answers.
function TB.ClearOrderPreview()
    orderPreview = nil
    previewPending = nil
    previewDueAt = nil
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
end

-- Plain-words preview for the panel above Send: what the bot makes, has,
-- farms, buys, asks for and needs from the player, plus time and gold cap.
function TB.OrderPreviewText(preview)
    if not preview then return nil end
    local verb = "gets"
    if string.lower(trim(preview.kind or "")) == "craft" then verb = "makes" end
    local lines = {}
    table.insert(lines, (preview.bot or "?") .. " " .. verb .. " " .. tostring(preview.want or 0)
        .. " " .. (preview.item or "?") .. ".")
    local has, farm, ah, sub, player = {}, {}, {}, {}, {}
    for _, row in ipairs(preview.reagents or {}) do
        local name = needName(row.itemId)
        local held = (row.bags or 0) + (row.mail or 0) + (row.bank or 0)
        if held > 0 then table.insert(has, held .. " " .. name) end
        if (row.farm or 0) > 0 then
            table.insert(farm, row.farm .. " " .. name
                .. (row.zone and (" (" .. row.zone .. ")") or ""))
        end
        if (row.ah or 0) > 0 then table.insert(ah, row.ah .. " " .. name) end
        if (row.vendor or 0) > 0 then table.insert(ah, row.vendor .. " " .. name .. " (shop)") end
        if (row.sub or 0) > 0 then table.insert(sub, row.sub .. " " .. name) end
        if (row.player or 0) > 0 then table.insert(player, row.player .. " " .. name) end
    end
    if table.getn(has) > 0 then table.insert(lines, "Has: " .. table.concat(has, ", ") .. ".") end
    if table.getn(farm) > 0 then table.insert(lines, "Will farm: " .. table.concat(farm, ", ") .. ".") end
    if table.getn(ah) > 0 then table.insert(lines, "May buy: " .. table.concat(ah, ", ") .. ".") end
    if table.getn(sub) > 0 then table.insert(lines, "Asks guild bots: " .. table.concat(sub, ", ") .. ".") end
    if table.getn(player) > 0 then
        table.insert(lines, "You need to send: " .. table.concat(player, ", ") .. ".")
    else
        table.insert(lines, "You need to send: nothing.")
    end
    if (preview.minutes or 0) > 0 then
        table.insert(lines, "Rough time: about " .. tostring(preview.minutes) .. " min.")
    end
    if preview.goldCap then
        table.insert(lines, "Spends at most: " .. TB.OrderGoldText(preview.goldCap) .. ".")
    end
    return table.concat(lines, " ")
end
-- Last completed search: { bot, kind, text, cat, items }.
local lastSearch = { bot = nil, kind = "farm", text = "", cat = nil, items = {} }
local searchBot, searchKind, searchText, searchCat = nil, "farm", "", nil
local orderReceiving, itemsReceiving = nil, nil

function TB.GetOrderSearch()
    return { bot = lastSearch.bot, kind = lastSearch.kind, text = lastSearch.text,
        cat = lastSearch.cat, items = lastSearch.items or {} }
end

-- Orders already announced as ready, by bot: one on-screen message and one
-- sound per order. Cleared when the order leaves ready (or is replaced), so
-- a later ready on a new order announces again; a login replay of an
-- already-ready order stays silent because the announce happened before.
local readyAnnounced = {}

local function commitOrderList(rows)
    for key in pairs(orders) do orders[key] = nil end
    for _, order in ipairs(rows) do orders[order.bot] = order end
    -- A full list replaces identities: ready notices announced for an old
    -- order stay announced only while the same order is still there.
    for bot in pairs(readyAnnounced) do
        if not orders[bot] or string.lower(trim(orders[bot].state or "")) ~= "ready"
            or string.lower(trim(orders[bot].type or "")) ~= "enchant" then
            readyAnnounced[bot] = nil
        end
    end
end

-- Step-history lines (TBM:ORDER_STEPS_*). Kept out of TB.ParseOrderMessage
-- so neither function needs more than the 1.12 client's 32 upvalues.
-- Returns true when the line was a step-history line.
local function parseOrderStepsMessage(msg)
    -- Step history of one bot: BEGIN opens a buffer, the ORDER_STEP lines fill
    -- it (only for the bot the buffer belongs to), END commits it and redraws
    -- the tooltip of the row under the cursor. The buffer carries the order
    -- identity seen when the request went out; a reply that lands after the
    -- bot moved to a new order is dropped at BEGIN (never buffered) and at
    -- END (never cached), freeing the throttle so the next hover asks again.
    -- A line for another bot, or an END without its BEGIN, is ignored; a
    -- BEGIN replaces an open buffer. Without a pending request there is
    -- nothing to compare against, so the reply commits as before.
    -- The BEGIN count is the entry count the reply promises: a count above
    -- STEPS_PROTOCOL_MAX is refused at once, and an END whose valid entries
    -- fall short of it is discarded (discardSteps), never committed.
    local _, _, stepBot, stepCount, stepDropped = string.find(msg, "^TBM:ORDER_STEPS_BEGIN|([^|]+)|(%d+)|(%d+)$")
    if stepBot then
        local bot = norm(stepBot)
        local expected = stepsPending[bot]
        local count = tonumber(stepCount)
        if expected and not sameOrderIdentity(expected, orderIdentity(orders[bot])) then
            stepsReceiving = nil
        elseif count > STEPS_PROTOCOL_MAX then
            discardSteps(bot)
        else
            stepsReceiving = { bot = bot, entries = {}, count = count, dropped = tonumber(stepDropped), expected = expected }
        end
        return true
    end
    if string.sub(msg, 1, 15) == "TBM:ORDER_STEP|" then
        local entry = TB.ParseOrderStepLine(msg)
        if stepsReceiving and entry and entry.bot == stepsReceiving.bot then
            table.insert(stepsReceiving.entries, entry)
        end
        return true
    end
    local _, _, stepEndBot = string.find(msg, "^TBM:ORDER_STEPS_END|([^|]+)$")
    if stepEndBot then
        local bot = norm(stepEndBot)
        if stepsReceiving and stepsReceiving.bot == bot then
            local expected = stepsReceiving.expected
            if expected and not sameOrderIdentity(expected, orderIdentity(orders[bot])) then
                stepsReceiving = nil
                stepsPending[bot] = nil
                stepsAskedAt[bot] = nil
                if next(stepsPending) == nil then stepsFlightAt = nil end
            elseif table.getn(stepsReceiving.entries) ~= stepsReceiving.count then
                -- Short of the BEGIN count: entries were lost, so nothing commits.
                discardSteps(bot)
            else
                -- Stamp the commit with its order's identity; a missing row means
                -- no identity, which never matches a live order.
                local identity = orderIdentity(orders[bot])
                orderSteps[bot] = { entries = stepsReceiving.entries, dropped = stepsReceiving.dropped,
                    receivedAt = now(),
                    type = identity and identity.type or nil,
                    itemId = identity and identity.itemId or nil,
                    parent = identity and identity.parent or nil }
                stepsMissed[bot] = nil
                stepsReceiving = nil
                stepsPending[bot] = nil
                if next(stepsPending) == nil then stepsFlightAt = nil end
                if TB.RepaintGuildRowTooltip then TB.RepaintGuildRowTooltip(bot) end
            end
        elseif stepsPending[bot] then
            -- The BEGIN was refused above (or the buffer was replaced), so the
            -- tail ends nothing: a stale tail still frees the throttle so the
            -- next hover asks again, a fresh one just clears the pending mark.
            if not sameOrderIdentity(stepsPending[bot], orderIdentity(orders[bot])) then
                stepsPending[bot] = nil
                stepsAskedAt[bot] = nil
            else
                stepsPending[bot] = nil
            end
            if next(stepsPending) == nil then stepsFlightAt = nil end
        end
        return true
    end
    return false
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
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    if string.sub(msg, 1, 10) == "TBM:ORDER|" then
        local order = TB.ParseOrderLine(msg)
        if orderReceiving then
            if order then table.insert(orderReceiving.rows, order) end
        elseif order then
            local previous = orders[order.bot]
            local wasState = previous and string.lower(trim(previous.state or "")) or nil
            local nowState = string.lower(trim(order.state or ""))
            local sameOrder = previous and sameOrderIdentity(previous, order)
            if previous and (not sameOrder or wasState ~= nowState) then
                if readyAnnounced then readyAnnounced[order.bot] = nil end
            end
            -- The step list belongs to its order's identity. A new order on
            -- the same bot drops the old list at once: hide via the identity
            -- check by keeping only a list that matches the incoming row. A
            -- new or changed state/reason/step also clears the throttle so
            -- the next hover refetches.
            if not previous
                or not sameOrderIdentity(previous, order)
                or string.lower(trim(previous.state or "")) ~= string.lower(trim(order.state or ""))
                or string.lower(trim(previous.reason or "")) ~= string.lower(trim(order.reason or ""))
                or string.lower(trim(previous.step or "")) ~= string.lower(trim(order.step or "")) then
                stepsAskedAt[order.bot] = nil
            end
            if orderSteps[order.bot]
                and not sameOrderIdentity(orderSteps[order.bot], orderIdentity(order)) then
                orderSteps[order.bot] = nil
            end
            orders[order.bot] = order
            if nowState == "ready" and string.lower(trim(order.type or "")) == "enchant"
                and (not sameOrder or wasState ~= "ready") then
                TB.AnnounceOrderReady(order.bot)
            end
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
            -- A full list drops the step lists whose order is gone or whose
            -- identity changed (a new order reuses the bot). A list with no
            -- current row is stranded, not stale, so it stays readable.
            for bot in pairs(orderSteps) do
                local current = orders[bot]
                if current and not sameOrderIdentity(orderSteps[bot], orderIdentity(current)) then
                    orderSteps[bot] = nil
                end
            end
            if batch.access then orderAccess = batch.access end
            if TB.SetStatus then
                TB.SetStatus("Orders updated · " .. table.getn(batch.rows), "ok")
            end
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    local _, _, enchantCount = string.find(msg, "^TBM:ORDER_ENCHANTS_BEGIN|(%d+)$")
    if enchantCount then
        itemsReceiving = { expected = tonumber(enchantCount), rows = {}, enchant = true }
        return true
    end
    if string.sub(msg, 1, 18) == "TBM:ORDER_ENCHANT|" then
        local row = TB.ParseOrderEnchantLine(msg)
        if itemsReceiving and itemsReceiving.enchant and row then
            table.insert(itemsReceiving.rows, row)
        end
        return true
    end
    if msg == "TBM:ORDER_ENCHANTS_END" then
        local batch = itemsReceiving
        itemsReceiving = nil
        if batch and batch.enchant then
            lastSearch = { bot = searchBot, kind = searchKind, text = searchText,
                cat = searchCat, items = batch.rows }
            if TB.SetStatus then
                if table.getn(batch.rows) == 0 then
                    TB.SetStatus("No matching enchants.", "muted")
                else
                    TB.SetStatus("Order search · " .. table.getn(batch.rows) .. " enchants", "ok")
                end
            end
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
        if itemsReceiving and not itemsReceiving.enchant and item then
            table.insert(itemsReceiving.rows, item)
        end
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
    -- Who-can-make rows: BEGIN opens a buffer for a (kind, text) search, the
    -- WHO lines fill it, END commits or drops the answer (over-cap answers
    -- drop whole). A pair for another kind answers the other pick list, so
    -- the shown rows only move for the current pick-a-bot search.
    local _, _, whoBeginKind, whoBeginCount = string.find(msg, "^TBM:ORDER_WHO_BEGIN|([^|]+)|(%d+)$")
    if whoBeginKind then
        whoReceiving = { kind = string.lower(trim(whoBeginKind)),
            expected = tonumber(whoBeginCount), rows = {} }
        return true
    end
    if string.sub(msg, 1, 14) == "TBM:ORDER_WHO|" then
        local entry = TB.ParseOrderWhoLine(msg)
        if whoReceiving and entry and entry.kind == whoReceiving.kind then
            if table.getn(whoReceiving.rows) < WHO_MAX then
                table.insert(whoReceiving.rows, entry)
            end
        end
        return true
    end
    if msg == "TBM:ORDER_WHO_END" then
        local batch = whoReceiving
        whoReceiving = nil
        if batch then
            if batch.expected and table.getn(batch.rows) > batch.expected then
                batch.rows = {}
            end
            -- The shown rows follow the BEGIN kind, not the last request: a
            -- late pair for the other kind replaces the rows with its own
            -- answer (never stale rows under a new pill).
            lastWhoSearch = { kind = batch.kind, text = whoText, rows = batch.rows }
            if TB.SetStatus then
                if table.getn(batch.rows) == 0 then
                    TB.SetStatus("No matching recipes.", "muted")
                else
                    TB.SetStatus("Order search · " .. table.getn(batch.rows) .. " recipes", "ok")
                end
            end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        end
        return true
    end
    -- (The W12 per-bot enchant pair above commits into lastSearch; there is
    -- no second enchant cache.)
    -- Order preview: one line per request, committed only while it answers
    -- the pending pick (bot, kind, item, amount). Anything else is ignored.
    -- The commit seeds the bring ticks: the server's list first, else
    -- auto-tick what the bags hold in full.
    if string.sub(msg, 1, 15) == "TBM:ORDER_STEPS" or string.sub(msg, 1, 15) == "TBM:ORDER_STEP|" then
        return parseOrderStepsMessage(msg)
    end
    if string.sub(msg, 1, 18) == "TBM:ORDER_PREVIEW|" then
        local preview = TB.ParseOrderPreviewLine(msg)
        -- A reply for another bot leaves the pending pick alone; a reply
        -- for its bot answers it (committing only on a full match).
        if preview and previewPending and preview.bot == previewPending.bot then
            if string.lower(trim(preview.kind or "")) == previewPending.kind
                and preview.itemId == previewPending.itemId
                and preview.want == previewPending.amount then
                orderPreview = preview
                if preview.bring and table.getn(preview.bring) > 0 then
                    orderBring = {}
                    TB.SetOrderBring(preview.bring)
                else
                    resetOrderBring(preview.reagents)
                end
            end
            previewPending = nil
        end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return true
    end
    return false
end

-- One-time ready notice for the player's own enchant order: highlight is
-- the row repaint above; the message and sound fire once per order, never on
-- every list refresh. UIErrorsFrame is the addon's notice frame (Core shows
-- status text beside it); ReadyCheck is a stock 1.12 sound.
function TB.AnnounceOrderReady(bot)
    bot = norm(bot)
    if not bot then return false end
    readyAnnounced = readyAnnounced or {}
    if readyAnnounced[bot] then return false end
    readyAnnounced[bot] = true
    local order = orders[bot]
    local name = (order and order.item) or "enchant"
    local capital = TB.OrderCapital()
    local text = bot .. ": " .. name .. " is ready - come to " .. capital .. " and press Meet"
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
    elseif RaidWarningFrame and RaidWarningFrame.AddMessage then
        RaidWarningFrame:AddMessage(text, 1, 0.82, 0)
    end
    if PlaySound then PlaySound("ReadyCheck") end
    if TB.SetStatus then TB.SetStatus(text, "ok") end
    if TB.RefreshGuildView then TB.RefreshGuildView() end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return true
end

function TB.OrderReadyAnnounced(bot)
    bot = norm(bot)
    return bot and readyAnnounced and readyAnnounced[bot] or false
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

-- (The per-bot enchant catalogue shares TB.ParseOrderEnchantReagents and
-- TB.ParseOrderEnchantLine with the WHO rows above; rows keep the W12 shape
-- with the spell id as itemId.)

function TB.SendOrderSearch(bot, kind, text, cat)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    text = trim(text or "")
    cat = string.lower(trim(cat or ""))
    if cat == "all" or cat == "" then cat = nil end
    if cat and not ORDER_CAT_LABEL[cat] then return false end
    -- Enchant searches carry no cat filter and need no 3-letter gate: even
    -- empty text lists the bot's enchants.
    if kind == "enchant" then
        searchBot, searchKind, searchText, searchCat = bot, kind, text, nil
        local line = "order search " .. bot .. " " .. kind
        if text ~= "" then line = line .. " " .. text end
        return TB.SendBotCommand(line)
    end
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
-- Guild-wide search (no bot): ".bot order search <craft|enchant> <text>".
-- The reply rides TBM:ORDER_WHO_BEGIN/WHO/END for the current pick-a-bot
-- kind only. Enchant needs no minimum text on the wire here; the window
-- keeps its 3-letter gate, matching today's farm/craft searches.
function TB.SendOrderWhoSearch(kind, text)
    if not TB.HasOrderCapability() then return false end
    kind = string.lower(trim(kind or ""))
    if kind ~= "craft" and kind ~= "enchant" then return false end
    text = trim(text or "")
    if string.len(text) < SEARCH_MIN then return false end
    whoKind, whoText = kind, text
    return TB.SendBotCommand("order search " .. kind .. " " .. text)
end
-- Per-bot enchant search alias: ".bot order search <Bot> enchant <text>".
-- One implementation under it (TB.SendOrderSearch); kept so the guild-wide
-- and per-bot search helpers read the same at the call site.
function TB.SendOrderEnchantSearch(bot, text)
    if not TB.HasOrderCapability() then return false end
    if not norm(bot) then return false end
    return TB.SendOrderSearch(bot, "enchant", text)
end

-- Ask what the bot would do for one pick: farm and craft only, one request
-- per pick change (never on a timer). Buy previews would promise finished
-- goods the server refuses, so they never go out.
function TB.RequestOrderPreview(bot, kind, itemId, amount, bring)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    itemId = math.floor(tonumber(itemId) or 0)
    amount = TB.ClampOrderAmount(amount)
    if not bot or (kind ~= "farm" and kind ~= "craft") then return false end
    if itemId <= 0 then return false end
    local bringText = TB.OrderBringText(bring)
    if bringText == "-" then bringText = nil end
    -- One request per pick: a repeat while the answer is still missing
    -- (double click, refresh race) reuses the pending one, never queues two.
    if previewPending and previewPending.bot == bot and previewPending.kind == kind
        and previewPending.itemId == itemId and previewPending.amount == amount
        and (previewPending.bring or nil) == bringText then
        return true
    end
    previewPending = { bot = bot, kind = kind, itemId = itemId, amount = amount,
        bring = bringText }
    local line = "order " .. bot .. " preview " .. kind .. " " .. itemId .. " " .. amount
    if bringText then line = line .. " bring=" .. bringText end
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

-- Guild gold cap for one give, in copper: nil means no cap (empty box) and
-- rides no trailing field; 0 is a real cap (no guild gold at all) and rides
-- gold=0. Rounds down whole copper, plain digits only.
function TB.ClampOrderGold(copper)
    if copper == nil or copper == "" then return nil end
    copper = tonumber(copper)
    if not copper or copper < 0 then return nil end
    return math.floor(copper)
end

function TB.SendOrderGive(bot, kind, itemId, amount, hours, keep, gold, bring)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    itemId = math.floor(tonumber(itemId) or 0)
    if not bot or (kind ~= "farm" and kind ~= "buy" and kind ~= "craft" and kind ~= "enchant") then return false end
    if kind == "buy" and not TB.PlayerBuyAllowed() then return false end
    if itemId <= 0 then return false end
    if kind == "enchant" then
        return TB.SendBotCommand("order " .. bot .. " enchant " .. itemId)
    end
    amount = TB.ClampOrderAmount(amount)
    gold = TB.ClampOrderGold(gold)
    local bringText = TB.OrderBringText(bring)
    if bringText == "-" then bringText = nil end
    local text = "order " .. bot .. " " .. kind .. " " .. itemId .. " " .. amount
    if hours ~= nil then
        if isInf(hours) then text = text .. " inf"
        else text = text .. " " .. TB.ClampOrderHours(hours) end
    end
    if keep then
        if hours == nil then text = text .. " " .. TB.ClampOrderHours(orderHours) end
        text = text .. " keep"
    end
    if gold ~= nil then text = text .. " gold=" .. gold end
    if bringText then text = text .. " bring=" .. bringText end
    if hours ~= nil or keep or gold ~= nil or bringText then
        pendingGive = { bot = bot, kind = kind, itemId = itemId, amount = amount,
            hours = hours, keep = keep and true or false, gold = gold, bring = bringText }
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
            -- The whole branch goes at any depth: sweep until no row
            -- still names a removed bot as its parent.
            local gone = {}
            gone[bot] = true
            orders[bot] = nil
            orderSteps[bot] = nil
            local swept = true
            while swept do
                swept = false
                for child, order in pairs(orders) do
                    if order.parent and gone[order.parent] then
                        gone[child] = true
                        orders[child] = nil
                        orderSteps[child] = nil
                        swept = true
                    end
                end
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
            local _, _, want = string.find(packet.scope or "", "^rank:(.+)$")
            TB.SetStatus("Bots' rank changed to " .. tostring(want or packet.scope) .. ".", "ok")
        end
        TB.RequestOrderAccess()
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return true
    end
    if string.sub(packet.executor or "", 1, 5) == "meet " then
        local detail = string.sub(packet.executor, 6)
        if detail == "coming" or detail == "later" or detail == "gathering" then
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
            return true
        end
        return false
    end
    if packet.executor == "enchant" then
        if TB.SetStatus then
            local text = "Enchant order accepted"
            if bot then text = bot .. ": " .. text end
            TB.SetStatus(text .. ".", "ok")
        end
        if bot and TB.GetOrderWindowBot and TB.GetOrderWindowBot() == bot then
            if TB.CloseOrderWindow then TB.CloseOrderWindow() end
        end
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        return true
    end
    if TB.SetStatus then
        local text = TB.OrderTypeLabel(packet.executor) .. " order accepted"
        if bot then text = bot .. ": " .. text end
        TB.SetStatus(text .. ".", "ok")
    end
    if bot and TB.GetOrderWindowBot and TB.GetOrderWindowBot() == bot then
        if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    end
    if TB.RefreshGuildView then TB.RefreshGuildView() end
    return true
end

-- ERR routing: the window keeps its own feedback line, the generic status
-- text below still reports the code and message.
local lastMeetBot = nil
function TB.OnOrderError(packet)
    if not packet or packet.intent ~= "order" then return false end
    -- An old server rejects the trailing bring / gold / keep / hours
    -- arguments or cat= as invalid: resend without them, bring first
    -- (newest), then gold, then keep, then hours (a refused inf retries
    -- once as 24). The rest settles both.
    if packet.code == "invalid" and pendingGive then
        local give = pendingGive
        if give.bring ~= nil then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = give.hours, keep = give.keep, gold = give.gold }
            TB.SetOrderFeedback("Old server: retrying without the materials you bring...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, give.hours, give.keep, give.gold)
            return false
        end
        if give.gold ~= nil then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = give.hours, keep = give.keep, gold = nil, bring = give.bring }
            TB.SetOrderFeedback("Old server: retrying without the guild gold cap...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, give.hours, give.keep, nil, give.bring)
            return false
        end
        if give.keep then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = give.hours, keep = false, bring = give.bring }
            TB.SetOrderFeedback("Old server: retrying without keep in stock...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, give.hours, false, nil, give.bring)
            return false
        end
        if isInf(give.hours) then
            pendingGive = { bot = give.bot, kind = give.kind, itemId = give.itemId,
                amount = give.amount, hours = HOURS_MAX, keep = false, bring = give.bring }
            TB.SetOrderFeedback("Old server: no time limit refused, retrying with 24 hours...", "pending")
            TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, HOURS_MAX, false, nil, give.bring)
            return false
        end
        pendingGive = nil
        TB.SetOrderFeedback("Old server: retrying without farm time...", "pending")
        TB.SendOrderGive(give.bot, give.kind, give.itemId, give.amount, nil, false, nil, give.bring)
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
    -- Meet refusals also reach the player on screen (the same frame the
    -- ready notice uses) and repaint the row: a cooldown refusal starts the
    -- button's countdown, parsed from the server's "N min" text.
    if packet.code == "cooldown" or packet.code == "nothingtobring"
        or packet.code == "notcapital" or packet.code == "noorder"
        or packet.code == "busy" then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(message, 1, 0.34, 0.28)
        end
        if TB.SetStatus then TB.SetStatus(message, "warn") end
        if packet.code == "cooldown" and lastMeetBot then
            -- The error carries no bot, so the last bot asked to meet owns
            -- the countdown, parsed from the server's "N min" text.
            local _, _, mins = string.find(message, "(%d+)%s*min")
            if mins then TB.SetOrderMeetCooldown(lastMeetBot, tonumber(mins) * 60) end
        end
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    end
    return false
end
-- One enchant order's Meet: the bot leaves the capital inn and walks over.
-- Sent from the guild row's Meet button the same way as the other commands.
-- The last bot asked owns a later cooldown refusal (the error names no bot).
function TB.SendOrderMeet(bot)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    if not bot then return false end
    lastMeetBot = bot
    return TB.SendBotCommand("order " .. bot .. " meet")
end

-- The capability can disappear mid-session (a restart with the feature
-- off): close the window and drop the model so no stale state lingers.
function TB.NoteOrderCaps()
    if TB.HasOrderCapability() then
        -- The server can lose the step history mid-session (a restart with
        -- the token off, a session change): its memory resets, so the whole
        -- cache goes rather than show one order's steps on another.
        if not TB.HasServerCapability("guild-order-steps") then
            for bot in pairs(orderSteps) do orderSteps[bot] = nil end
            stepsReceiving = nil
            for bot in pairs(stepsPending) do stepsPending[bot] = nil end
            for bot in pairs(stepsAskedAt) do stepsAskedAt[bot] = nil end
            stepsFlightAt = nil
        end
        -- The server can refuse player Buy orders mid-session (a restart
        -- with the flag off): leave Buy and show Farm instead, so no Buy
        -- give or preview goes out after the token lands.
        if not TB.PlayerBuyAllowed() and TB.GetOrderKind and TB.GetOrderKind() == "buy" then
            TB.SetOrderKind("farm")
            if TB.ClearOrderPreview then TB.ClearOrderPreview() end
        end
        if TB.RefreshGuildView then TB.RefreshGuildView() end
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return
    end
    for key in pairs(orders) do orders[key] = nil end
    for bot in pairs(readyAnnounced) do readyAnnounced[bot] = nil end
    orderAccess = nil
    for bot in pairs(orderSteps) do orderSteps[bot] = nil end
    lastSearch = { bot = nil, kind = "farm", text = "", cat = nil, items = {} }
    lastWhoSearch = { kind = "craft", text = "", rows = {} }
    orderReceiving, itemsReceiving = nil, nil
    whoReceiving = nil
    whoKind, whoText = nil, nil
    stepsReceiving = nil
    for bot in pairs(stepsPending) do stepsPending[bot] = nil end
    for bot in pairs(stepsAskedAt) do stepsAskedAt[bot] = nil end
    stepsFlightAt = nil
    searchBot, searchCat = nil, nil
    pendingSearchCat = nil
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if TB.RefreshGuildView then TB.RefreshGuildView() end
end

-- "order access" goes out when the window opens and has no snapshot yet, or
-- right after a rank change; the list batch already carries it. The tick
-- also repaints the guild rows while a cooldown runs so its countdown ticks
-- down without a new server line (at most once a second).
local lastMeetRepaintAt = 0
local function meetRepaintTick()
    if not TB.guildFrame or not TB.guildFrame:IsVisible() then return end
    if not TB.RefreshGuildView then return end
    if now() - lastMeetRepaintAt < 1 then return end
    lastMeetRepaintAt = now()
    TB.RefreshGuildView()
end
function TB.OrderPollTick()
    if not TB.HasOrderCapability() then return false end
    if not (TB.guildFrame and TB.guildFrame:IsVisible()) then return false end
    if now() - (TB._lastOrderListAt or 0) < LIST_INTERVAL then return false end
    return TB.RequestOrderList()
end

local pollFrame
local function ensurePollFrame()
    if pollFrame then return end
    pollFrame = CreateFrame("Frame", "TortoiseBotsManagerOrderPoll")
    pollFrame:SetScript("OnUpdate", function()
        TB.OrderPollTick()
        meetRepaintTick()
    end)
    -- The Send-missing-items button follows the mailbox: refresh when it
    -- opens or closes so the button enables/disables itself (D2).
    pollFrame:RegisterEvent("MAIL_SHOW")
    pollFrame:RegisterEvent("MAIL_CLOSED")
    pollFrame:SetScript("OnEvent", function()
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    end)
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
-- Pick-a-bot (guild-wide) mode: no windowBot, type Craft/Enchant, WHO rows
-- with a per-row bot click.
local orderGuild = false
function TB.IsOrderGuildMode()
    return (win and win:IsVisible() and orderGuild) and true or false
end
-- Window-scoped bring edits: the early SetOrderBring only stores; these
-- also re-ask the preview so the panel follows the tick.
local function resendBringPreview()
    if win and windowBot and selectedItemId
        and (orderKind == "farm" or orderKind == "craft")
        and (orderPreview or previewPending) then
        orderPreview = nil
        previewPending = nil
        previewDueAt = now() + SEARCH_DEBOUNCE
    end
end
-- Manual bring edits from the checkboxes: store, then re-ask the preview so
-- the panel follows the tick. Defined after win/preview locals exist.
function TB.SetOrderBringNow(ids)
    local kept = TB.SetOrderBring(ids)
    resendBringPreview()
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return kept
end
function TB.ToggleOrderBringNow(itemId)
    local kept = TB.ToggleOrderBring(itemId)
    resendBringPreview()
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return kept
end

function TB.GetOrderWindowBot()
    return (win and win:IsVisible()) and windowBot or nil
end

function TB.GetOrderKind()
    return orderKind
end

local ORDER_KINDS = { farm = true, buy = true, craft = true, enchant = true }

function TB.SetOrderKind(kind)
    kind = string.lower(trim(kind or ""))
    if not ORDER_KINDS[kind] then return false end
    if kind == orderKind then return true end
    orderKind = kind
    selectedItemId = nil
    orderPreview = nil
    previewPending = nil
    lastSearch = { bot = windowBot, kind = kind, text = "", cat = orderCat, items = {} }
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    -- A new kind re-runs a valid search at once: verdicts differ per kind
    -- (a craft search refuses unknown recipes, a farm search does not).
    -- Small kinds may browse with empty text; big kinds need 3+ letters.
    -- Enchant searches carry no cat filter.
    orderCat = nil
    if win and windowBot and win.searchBox then
        local text = trim(win.searchBox:GetText() or "")
        if orderKind == "enchant" then
            searchPendingAt = nil
            TB.SendOrderSearch(windowBot, orderKind, text)
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
    orderPreview = nil
    previewPending = nil
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
    -- The estimate follows the amount: a shown preview re-asks once typing
    -- pauses (same 0.6 s pause as the search), never per keystroke or timer.
    if selectedItemId and (orderPreview or previewPending) then
        orderPreview = nil
        previewPending = nil
        previewDueAt = now() + SEARCH_DEBOUNCE
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

-- Max guild gold for the give, in copper: nil means no cap (empty box);
-- 0 is a real cap (no guild gold at all) and shows "0".
function TB.GetOrderGold()
    return orderGold
end

function TB.SetOrderGold(copper)
    orderGold = TB.ClampOrderGold(copper)
    local shown = orderGold ~= nil and tostring(orderGold) or ""
    if win and win.goldBox and win.goldBox:GetText() ~= shown then
        win.goldBox:SetText(shown)
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
    -- A fresh pick asks at once: farm and craft only, Buy and Enchant have no preview.
    orderPreview = nil
    previewPending = nil
    previewDueAt = nil
    if selectedItemId and windowBot
        and (orderKind == "farm" or orderKind == "craft") then
        TB.RequestOrderPreview(windowBot, orderKind, selectedItemId, orderAmount, orderBring)
    end
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

-- Second line of an enchant result: name, slot, required skill, verdict,
-- reagents with have/need. Keep to the shared ORDER_ENCHANT shape: rows
-- carry spellId as itemId, the verdict token, and itemId:need:have rows.
function TB.OrderEnchantDetail(row)
    if not row then return "" end
    if string.lower(trim(row.verdict or "")) ~= "ok" then
        local reason = TB.OrderReasonLabel(row.verdict)
        return "Can't: " .. (reason or row.verdict)
    end
    local parts = {}
    if row.slot then table.insert(parts, row.slot) end
    local skill = TB.OrderSkillLabel(row.skill)
    if skill then table.insert(parts, skill) end
    local reagents = {}
    for _, reagent in ipairs(row.reagents or {}) do
        local name = nil
        if GetItemInfo then name = GetItemInfo(reagent.itemId) end
        name = name or ("item #" .. tostring(reagent.itemId))
        table.insert(reagents, name .. " " .. tostring(reagent.have or 0) .. "/" .. tostring(reagent.need or 0))
    end
    if table.getn(reagents) > 0 then table.insert(parts, table.concat(reagents, ", ")) end
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
    if not (win and win.searchBox) then return end
    local text = trim(win.searchBox:GetText() or "")
    if orderGuild then
        if string.len(text) < SEARCH_MIN then
            lastWhoSearch = { kind = lastWhoSearch.kind, text = text, rows = {} }
            TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
            if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
            return
        end
        TB.SendOrderWhoSearch(lastWhoSearch.kind, text)
        return
    end
    if not windowBot then return end
    if orderKind == "enchant" then
        TB.SendOrderSearch(windowBot, orderKind, text)
        return
    end
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
-- The preview re-ask goes out after the same pause, once per amount change.
local function firePendingPreview()
    if not previewDueAt or now() < previewDueAt then return end
    previewDueAt = nil
    if not (win and windowBot and selectedItemId) then return end
    if orderKind ~= "farm" and orderKind ~= "craft" then return end
    TB.RequestOrderPreview(windowBot, orderKind, selectedItemId, orderAmount, orderBring)
end

-- Dropdown menus (rank list, reassign targets): the 1.12 FrameXML set is
-- UIDropDownMenu_Initialize / UIDropDownMenu_AddButton / ToggleDropDownMenu
-- on a UIDropDownMenuTemplate frame anchored to the cursor. Each menu row
-- picks, asks one confirm, then sends; the builders below stay testable
-- without the global DropDownList frames.
-- The order window's timer: typing-pause searches, previews, and a redraw
-- once uncached items arrive. Kept out of createWindow (32-upvalue limit).
local function onOrderWindowUpdate()
    firePendingSearch()
    firePendingPreview()
    -- Uncached items re-render once the client has them.
    if uncachedAt and now() - uncachedAt > 1 then
        uncachedAt = nil
        TB.RefreshOrderWindow()
    end
end

-- The amount, farm time, keep-in-stock and gold limit controls of the order
-- window. Built apart from createWindow so neither function needs more than
-- the 1.12 client's 32 upvalues. Returns the y base the Send row uses.
local function createOrderLimits()
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
    TB.SetTextColor(amountLabel, color("title"))

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
    TB.StyleEditBox(amountBox, nil)
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
    TB.SetTextColor(hoursLabel, color("title"))

    local hoursBox = CreateFrame("EditBox", "TortoiseBotsManagerOrderHours", win, "InputBoxTemplate")
    TB.StyleEditBox(hoursBox, nil)
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
    TB.StyleCheckButton(keepBox)
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
    TB.SetTextColor(goldLabel, color("title"))
    win.goldLabel = goldLabel

    local goldBox = CreateFrame("EditBox", "TortoiseBotsManagerOrderGold", win, "InputBoxTemplate")
    TB.StyleEditBox(goldBox, nil)
    goldBox:SetWidth(100); goldBox:SetHeight(20)
    goldBox:SetPoint("TOPLEFT", win, "TOPLEFT", 168, -(base + 44))
    goldBox:SetAutoFocus(false)
    goldBox:SetScript("OnEscapePressed", function()
        this:SetText(orderGold ~= nil and tostring(orderGold) or "")
        this:ClearFocus()
    end)
    goldBox:SetScript("OnEnterPressed", function()
        local text = trim(this:GetText() or "")
        if text == "" then TB.SetOrderGold(nil)
        else TB.SetOrderGold(tonumber(text)) end
        this:ClearFocus()
    end)
    goldBox:SetScript("OnTextChanged", function()
        local text = trim(this:GetText() or "")
        if text == "" then
            if orderGold ~= nil then TB.SetOrderGold(nil) end
        else
            local g = tonumber(text)
            if g ~= nil and TB.ClampOrderGold(g) ~= orderGold then TB.SetOrderGold(g) end
        end
    end)
    goldBox:SetScript("OnEditFocusLost", function()
        this:SetText(orderGold ~= nil and tostring(orderGold) or "")
    end)
    win.goldBox = goldBox
    setTooltip(goldBox, "Max guild gold",
        { "Most the order may spend from the guild bank, in copper. Empty means no cap." })
    local noLimitBox = CreateFrame("CheckButton", "TortoiseBotsManagerOrderNoLimit", win, "UICheckButtonTemplate")
    TB.StyleCheckButton(noLimitBox)
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
    return base
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerOrderWindow", TB.frame or UIParent)
    win:SetWidth(OW); win:SetHeight(510 + 178)
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
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -9)
    win.title:SetWidth(OW - 50); win.title:SetJustifyH("LEFT")
    TB.StyleTitle(win.title, 14)
    TB.SetTextColor(win.title, color("title"))

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseOrderWindow() end)

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    head:SetWidth(OW - 24); head:SetJustifyH("LEFT")
    head:SetText("Pick a real item, how to get it, and how many.")
    TB.SetTextColor(head, color("muted"))

    local search = CreateFrame("EditBox", "TortoiseBotsManagerOrderSearch", win, "InputBoxTemplate")
    TB.StyleEditBox(search, "Search items")
    search:SetWidth(OW - 24); search:SetHeight(20)
    search:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -56)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function()
        searchPendingAt = nil
        this:ClearFocus()
        local text = trim(this:GetText() or "")
        if orderGuild then
            if string.len(text) >= SEARCH_MIN then
                TB.SendOrderWhoSearch(lastWhoSearch.kind, text)
            else
                TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
            end
            return
        end
        if win and windowBot then
            if orderKind == "enchant" then
                TB.SendOrderSearch(windowBot, orderKind, text)
            elseif string.len(text) >= SEARCH_MIN
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

    local kinds = { { "Farm", "farm" }, { "Buy", "buy" }, { "Craft", "craft" }, { "Enchant", "enchant" } }
    win.kindPills = {}
    local kindWidths = { 76, 56, 76, 96 }
    local kindX = 12
    for i, entry in ipairs(kinds) do
        local pill = TB.UI.CreateTogglePill(win, entry[1], kindWidths[i], 22, {
            tipTitle = entry[1],
            tip = entry[2] == "farm" and "Gather or kill for the items."
                or (entry[2] == "buy" and "Buy on the auction house first, farm the rest."
                    or (entry[2] == "craft" and "Craft from materials, farming what is missing."
                        or "Search this bot's enchants and order one (spell id).")),
        })
        pill:SetPoint("TOPLEFT", win, "TOPLEFT", kindX, -80)
        kindX = kindX + kindWidths[i] + 4
        local kind = entry[2]
        pill:SetScript("OnClick", function()
            if orderGuild and (kind == "craft" or kind == "enchant") then
                TB.SetGuildOrderKind(kind)
            else
                TB.SetOrderKind(kind)
            end
        end)
        win.kindPills[kind] = pill
    end
-- Guild-mode type switch: the Craft/Enchant pills pick the WHO stream, not
-- today's per-bot kind. Farm/Buy stay per-bot only and leave guild mode.
function TB.SetGuildOrderKind(kind)
    kind = string.lower(trim(kind or ""))
    if kind ~= "craft" and kind ~= "enchant" then return false end
    lastWhoSearch.kind = kind
    selectedItemId = nil
    -- The search goes out on Enter or after the typing pause, never on the
    -- pill click: the box still holds the other kind's text at click time.
    if win and win.searchBox then
        lastWhoSearch = { kind = kind, text = trim(win.searchBox:GetText() or ""), rows = {} }
    else
        lastWhoSearch = { kind = kind, text = "", rows = {} }
    end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return true
end
function TB.GetGuildOrderKind()
    return lastWhoSearch.kind
end

    win.catPills = {}
    for i, cat in ipairs(ORDER_CATS) do
        local pill = TB.UI.CreateTogglePill(win, ORDER_CAT_LABEL[cat], 74, 18, {
            tipTitle = ORDER_CAT_LABEL[cat],
            tip = "Only show this kind of item.",
        })
        pill:SetPoint("TOPLEFT", win, "TOPLEFT", 12 + math.mod(i - 1, 4) * 80,
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
        TB.ApplySurface(row, "row")
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
    -- Pick-a-bot clicks: one small button per knowing bot lives inside the
    -- row, laid out after RefreshOrderWindow names them. Buttons are reused
    -- across rows (at most three drawn per row for space); extras fold into
    -- the row detail line ("+N more").
    win.botBtns = {}
    for i = 1, RESULT_ROW_N * 3 do
        local b = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
        b:SetWidth(52); b:SetHeight(14)
        b:SetText("")
        b:SetScript("OnClick", function()
            local entry, bot = this.whoEntry, this.whoBot
            if entry and bot then TB.PickGuildOrderBot(entry, bot) end
        end)
        b:Hide()
        win.botBtns[i] = b
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
    -- The heading gets its own line; the order lines start under it.
    treeLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 18))
    treeLabel:SetText("ORDERS")
    treeLabel:SetWidth(200); treeLabel:SetJustifyH("LEFT")
    TB.SetTextColor(treeLabel, color("title"))

    win.treeLines = {}
    for i = 1, 4 do
        local line = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(152 + RESULT_ROW_N * RESULT_ROW_H + 4 + 30 + (i - 1) * 11))
        line:SetWidth(OW - 24 - 68); line:SetJustifyH("LEFT")
        TB.SetTextColor(line, color("muted"))
        win.treeLines[i] = line
    end

    local base = createOrderLimits()

    -- What the bot would do for the current pick, asked on selection (never
    -- on a timer). Two lines above Send; hidden until a pick has a preview.
    local previewLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 68))
    previewLine:SetWidth(OW - 24); previewLine:SetJustifyH("LEFT")
    TB.SetTextColor(previewLine, color("muted"))
    win.previewLine = previewLine
    -- "I bring it" ticks: one checkbox per craft reagent above the preview
    -- line. The row names the reagent and its need count; auto-tick when
    -- the player's bags hold the full need, manual toggle otherwise.
    -- At most four rows fit; extras fold into the preview text.
    win.bringRows = {}
    for i = 1, 4 do
        local box = CreateFrame("CheckButton", "TortoiseBotsManagerOrderBring" .. i, win, "UICheckButtonTemplate")
        TB.StyleCheckButton(box)
        box:SetWidth(16); box:SetHeight(16)
        box:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 68 + (i - 1) * 15))
        box:SetScript("OnClick", function()
            local id = this.bringId
            if id then TB.ToggleOrderBringNow(id) end
        end)
        box:Hide()
        local label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        label:SetWidth(OW - 24 - 22); label:SetJustifyH("LEFT")
        TB.SetTextColor(label, color("muted"))
        label:Hide()
        box.bringLabel = label
        win.bringRows[i] = box
    end

    win.sendBtn = smallButton(win, "Send", 76, 194, -(base + 96),
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
            if orderKind == "enchant" then
                if selectedItemId and windowBot then
                    TB.SetOrderFeedback(TB.OrderTypeLabel(orderKind) .. " " .. item.item
                        .. " sent, waiting for the server...", "pending")
                    TB.SendOrderGive(windowBot, "enchant", selectedItemId)
                end
                return
            end
            local timeText = orderNoLimit and "no limit" or (orderHours .. "h")
            local goldText = orderGold and (" " .. TB.OrderGoldText(orderGold)) or ""
            TB.SetOrderFeedback(TB.OrderTypeLabel(orderKind) .. " " .. item.item
                .. " x" .. orderAmount .. " (" .. timeText .. (orderKeep and ", keep" or "")
                .. goldText .. ") sent, waiting for the server...", "pending")
            TB.SendOrderGive(windowBot, orderKind, item.itemId, orderAmount,
                orderNoLimit and "inf" or orderHours, orderKeep, orderGold, orderBring)
        end)

    win.cancelBtn = smallButton(win, "Cancel", 62, 274, -(base + 96),
        "Cancel order", "Remove this bot's current order. Cancelling also ends keep-in-stock and no-limit orders.",
        function()
            if windowBot then TB.ConfirmOrderCancel(windowBot) end
        end)

    -- Fills the Send Mail form for the bot that needs items; the player
    -- presses Send. Enabled only at an open mailbox with a need (D2/D3).
    win.sendItemsBtn = smallButton(win, "Send missing items", 176, 12, -(base + 96),
        "Send missing items", "Fill the mail form for the bot that needs items.",
        function()
            TB.SendOrderMissingItems(TB.GetOrderWindowBot())
        end)

    win.statusLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.statusLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 122))
    win.statusLine:SetWidth(OW - 24); win.statusLine:SetJustifyH("LEFT")
    TB.SetTextColor(win.statusLine, color("muted"))

    win.feedbackLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.feedbackLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 138))
    win.feedbackLine:SetWidth(OW - 24); win.feedbackLine:SetJustifyH("LEFT")

    win:SetScript("OnUpdate", onOrderWindowUpdate)

    win:Hide()
    TB.orderWindow = win
end

function TB.RefreshOrderWindow()
    if not win or not win:IsVisible() then return end
    if orderGuild then
        win.title:SetText("Order for the guild: pick a bot")
    else
        win.title:SetText("Order for " .. (windowBot or "?"))
    end
    for kind, pill in pairs(win.kindPills or {}) do
        if orderGuild then
            -- Craft/Enchant pick the WHO stream; Farm and Buy stay per-bot.
            if kind == "craft" or kind == "enchant" then
                if pill.SetActive then pill:SetActive(kind == lastWhoSearch.kind) end
                pill:Show()
            else
                pill:Hide()
            end
        else
            if pill.SetActive then pill:SetActive(kind == orderKind) end
            -- No Buy option while the server refuses player Buy orders. Older
            -- servers without the cap keep today's pills.
            if kind == "buy" then
                if TB.PlayerBuyAllowed() then pill:Show() else pill:Hide() end
            end
        end
    end
    for cat, pill in pairs(win.catPills or {}) do
        if orderGuild then
            pill:Hide()
        else
            if pill.SetActive then pill:SetActive(cat == (orderCat or "all")) end
            pill:Show()
        end
    end
    if orderGuild then
        TB.RefreshGuildOrderRows()
    else
        TB.RefreshPerBotOrderRows()
    end
end
-- WHO rows for pick-a-bot mode: name (+ slot and reqSkill on enchant),
-- bots "name skill have/need" with a busy marker, clickable per bot.
function TB.RefreshGuildOrderRows()
    local search = TB.GetOrderWhoSearch()
    local rows = {}
    if search.kind == lastWhoSearch.kind then rows = search.rows or {} end
    local total = table.getn(rows)
    FauxScrollFrame_Update(win.results, total, RESULT_ROW_N, RESULT_ROW_H)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(win.results)) or 0
    local used = 0
    for i = 1, RESULT_ROW_N do
        local row = win.resultRows[i]
        local entry = rows[offset + i]
        if entry then
            row.whoEntry = entry
            row.item = nil
            local head = entry.item or ("item #" .. tostring(entry.id or "?"))
            if entry.kind == "enchant" then
                head = head .. " (" .. (entry.slot or "?") .. " " .. tostring(entry.reqSkill or 0) .. ")"
            elseif entry.reqSkill and entry.reqSkill > 0 then
                head = head .. " (" .. tostring(entry.reqSkill) .. ")"
            end
            row.name:SetText(head)
            row.name:SetTextColor(1, 1, 1)
            local bots = entry.bots or {}
            local extra = 0
            if table.getn(bots) > 3 then extra = table.getn(bots) - 3 end
            if table.getn(bots) == 0 then
                row.detail:SetText("no guild bot knows it")
            else
                local line = TB.OrderWhoBotText({ bots = bots })
                if extra > 0 then line = line .. " (+" .. extra .. " more)" end
                row.detail:SetText(line)
            end
            row.detail:SetTextColor(0.85, 0.85, 0.85)
            row.icon:SetTexture(itemTexture(entry.id))
            row.sel:Hide()
            row:Show()
            for j = 1, 3 do
                used = used + 1
                local b = win.botBtns and win.botBtns[used] or nil
                local bot = bots[j]
                if b and bot then
                    b.whoEntry, b.whoBot = entry, bot.bot
                    b:SetText(bot.bot)
                    b:SetPoint("TOPLEFT", row, "TOPLEFT", 38 + (j - 1) * 58, -18)
                    if TB.CanGiveOrders() then b:Enable() else b:Disable() end
                    b:Show()
                elseif b then
                    b.whoEntry, b.whoBot = nil, nil
                    b:Hide()
                end
            end
        else
            row.whoEntry = nil
            row.item = nil
            row:Hide()
        end
    end
    if win.botBtns then
        for i = used + 1, table.getn(win.botBtns) do win.botBtns[i]:Hide() end
    end
    if win.emptyMsg then
        if total == 0 then
            local text = trim(win.searchBox:GetText() or "")
            if string.len(text) < SEARCH_MIN then
                win.emptyMsg:SetText("Type at least 3 letters to search.")
            elseif search.kind == lastWhoSearch.kind then
                win.emptyMsg:SetText("No matching recipes.")
            else
                win.emptyMsg:SetText("Searching...")
            end
            win.emptyMsg:Show()
        else
            win.emptyMsg:Hide()
        end
    end
    TB.RefreshOrderChrome(nil)
    TB.RefreshOrderBringRows()
end
-- Today's per-bot rows, split out so guild mode can share the chrome.
function TB.RefreshPerBotOrderRows()
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
            row.whoEntry = nil
            row.item = item
            if item.itemId == selectedItemId then foundSelected = true end
            local cant = string.lower(trim(item.verdict or "")) ~= "ok"
            if orderKind == "enchant" then
                row.icon:SetTexture("Interface\Icons\INV_Misc_QuestionMark")
            else
                row.icon:SetTexture(itemTexture(item.itemId))
            end
            -- No quality escape when greyed: inline |cff codes override
            -- SetTextColor in the 1.12 client.
            if cant then row.name:SetText(item.item)
            elseif orderKind == "enchant" then row.name:SetText(item.item)
            else row.name:SetText(qualityHex(item.quality) .. item.item .. "|r") end
            if cant then row.name:SetTextColor(0.45, 0.45, 0.45) else row.name:SetTextColor(1, 1, 1) end
            if orderKind == "enchant" then
                row.detail:SetText(TB.OrderEnchantDetail(item))
            else
                row.detail:SetText(TB.OrderItemDetail(item, orderKind, orderAmount, level))
            end
            if cant then row.detail:SetTextColor(0.45, 0.45, 0.45)
            else row.detail:SetTextColor(0.85, 0.85, 0.85) end
            if item.itemId == selectedItemId then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.whoEntry = nil
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
                if orderKind == "enchant" then win.emptyMsg:SetText("No matching enchants.")
                else win.emptyMsg:SetText("No matching items.") end
            else
                win.emptyMsg:SetText("Searching...")
            end
            win.emptyMsg:Show()
        else
            win.emptyMsg:Hide()
        end
    end
    if win.botBtns then
        for _, b in ipairs(win.botBtns) do b:Hide() end
    end
    local order = windowBot and TB.GetBotOrder(windowBot) or nil
    TB.RefreshOrderChrome(order)
    TB.RefreshOrderBringRows()
end
-- Shared chrome below the rows: access, rank, tree, boxes, preview, bring.
function TB.RefreshOrderChrome(order)
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
                line:SetText(TB.OrderTreeRowText(entry.order, entry.depth))
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
        if orderGuild then
            win.statusLine:SetText("Pick a bot to open its order flow.")
        elseif order then
            win.statusLine:SetText("Current: " .. TB.OrderRowText(order))
        else
            win.statusLine:SetText("No order on this bot.")
        end
    end
    if win.cancelBtn then
        if order and TB.CanGiveOrders() then win.cancelBtn:Enable() else win.cancelBtn:Disable() end
    end
    if win.sendBtn then
        if orderGuild then win.sendBtn:Disable()
        elseif TB.CanGiveOrders() then win.sendBtn:Enable() else win.sendBtn:Disable() end
    end
    if win.sendItemsBtn then
        local canSend, mailReason = TB.CanSendOrderItems(windowBot)
        if canSend and not orderGuild then win.sendItemsBtn:Enable() else win.sendItemsBtn:Disable() end
        -- The tooltip names the bot and its need, or why the button is dead.
        win.sendItemsBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Send missing items")
            if canSend then
                local bot, needOrder = TB.OrderNeedTarget(windowBot)
                local need = needOrder and TB.OrderNeedText(needOrder)
                if bot and need then GameTooltip:AddLine(bot .. ": " .. need, 0.9, 0.9, 0.9, 1) end
            elseif mailReason then
                GameTooltip:AddLine(mailReason, 0.9, 0.9, 0.9, 1)
            end
            GameTooltip:Show()
        end)
        win.sendItemsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local isEnchantKind = orderKind == "enchant"
    if win.amountBox then
        if isEnchantKind then win.amountBox:EnableMouse(false) else win.amountBox:EnableMouse(true) end
    end
    if win.amountMinus then
        if isEnchantKind then win.amountMinus:Disable() else win.amountMinus:Enable() end
    end
    if win.amountPlus then
        if isEnchantKind then win.amountPlus:Disable() else win.amountPlus:Enable() end
    end
    if win.hoursBox then
        if isEnchantKind then
            win.hoursBox:ClearFocus()
            win.hoursBox:EnableMouse(false)
            win.hoursBox:SetTextColor(0.5, 0.5, 0.5)
        elseif orderNoLimit then
            win.hoursBox:ClearFocus()
            win.hoursBox:EnableMouse(false)
            win.hoursBox:SetTextColor(0.5, 0.5, 0.5)
        else
            win.hoursBox:EnableMouse(true)
            win.hoursBox:SetTextColor(1, 1, 1)
        end
    end
    if win.keepBox and win.keepBox.SetChecked then
        win.keepBox:SetChecked(orderKeep and true or false)
        if isEnchantKind then win.keepBox:Disable()
        elseif TB.CanGiveOrders() then win.keepBox:Enable() else win.keepBox:Disable() end
    end
    if win.noLimitBox and win.noLimitBox.SetChecked then
        win.noLimitBox:SetChecked(orderNoLimit and true or false)
        if isEnchantKind then win.noLimitBox:Disable()
        elseif TB.CanGiveOrders() then win.noLimitBox:Enable() else win.noLimitBox:Disable() end
    end
    if win.goldBox then
        if isEnchantKind then win.goldBox:EnableMouse(false)
        elseif TB.CanGiveOrders() then win.goldBox:EnableMouse(true) end
    end
    if win.keepLabel then
        if isEnchantKind then win.keepLabel:SetTextColor(0.5, 0.5, 0.5)
        else TB.SetTextColor(win.keepLabel, color("muted")) end
    end
    if win.noLimitLabel then
        if isEnchantKind then win.noLimitLabel:SetTextColor(0.5, 0.5, 0.5)
        else TB.SetTextColor(win.noLimitLabel, color("muted")) end
    end
    if win.goldLabel then
        if isEnchantKind then win.goldLabel:SetTextColor(0.5, 0.5, 0.5)
        else TB.SetTextColor(win.goldLabel, color("title")) end
    end
    if win.farmNote then
        if isEnchantKind then win.farmNote:SetText("Meet the bot in Stormwind or Orgrimmar to trade the enchant.")
        else win.farmNote:SetText("Bots farm like players: large amounts or rare drops can take very long or fail.") end
    end
    if win.previewLine then
        local previewText = nil
        if isEnchantKind then previewText = nil
        elseif orderPreview and orderPreview.bot == windowBot
            and string.lower(trim(orderPreview.kind or "")) == string.lower(trim(orderKind or ""))
            and orderPreview.itemId == selectedItemId
            and orderPreview.want == orderAmount then
            previewText = TB.OrderPreviewText(orderPreview)
        elseif previewPending then
            previewText = "Preview: asking the server..."
        end
        if previewText then
            win.previewLine:SetText(previewText)
            win.previewLine:Show()
        else
            win.previewLine:Hide()
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
    TB.RefreshOrderBringRows()
end
-- Bring checkboxes: one row per craft reagent of the shown preview, hidden
-- otherwise. The tick follows the preview's <bring> list; a new preview
-- auto-ticks what the bags hold in full.
function TB.RefreshOrderBringRows()
    local reagents = nil
    if win and not orderGuild and orderKind == "craft" and orderPreview
        and orderPreview.bot == windowBot
        and string.lower(trim(orderPreview.kind or "")) == "craft"
        and orderPreview.itemId == selectedItemId
        and orderPreview.want == orderAmount then
        reagents = orderPreview.reagents or {}
    end
    for i, box in ipairs(win and win.bringRows or {}) do
        local row = reagents and reagents[i] or nil
        if row then
            local name = needName(row.itemId)
            box.bringId = row.itemId
            box.bringLabel:SetText("I bring it: " .. name .. " x" .. tostring(row.need or 0))
            if box.SetChecked then box:SetChecked(TB.OrderBringTicked(orderBring, row.itemId)) end
            if box.bringLabel then box.bringLabel:Show() end
            if TB.CanGiveOrders() then box:Enable() else box:Disable() end
            box:Show()
        else
            box.bringId = nil
            if box.bringLabel then box.bringLabel:Hide() end
            box:Hide()
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
    local switched = windowBot ~= bot or orderGuild
    orderGuild = false
    windowBot = bot
    if switched then
        orderKind = "farm"
        orderAmount = 10
        orderHours = 1
        orderNoLimit = true
        orderKeep = false
        orderGold = nil
        orderCat = nil
        selectedItemId = nil
        feedback = nil
        searchPendingAt = nil
        orderPreview = nil
        previewPending = nil
        previewDueAt = nil
        searchTouched = false
        orderBring = {}
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
-- "Order" button above the Guild list: pick-a-bot mode, no bot pinned.
-- Craft/Enchant pills switch the WHO stream; a bot click opens the normal
-- per-bot flow for that bot and item.
function TB.OpenGuildOrderWindow()
    if not TB.HasOrderCapability() then return false end
    if not win then createWindow() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseBotPanel then TB.CloseBotPanel() end
    orderGuild = true
    windowBot = nil
    selectedItemId = nil
    orderPreview = nil
    previewPending = nil
    previewDueAt = nil
    searchPendingAt = nil
    searchTouched = false
    orderBring = {}
    if not TB.GetOrderAccess() then TB.RequestOrderAccess() end
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
-- A WHO bot click: craft previews that item for that bot; enchant opens the
-- per-bot enchant flow for that bot with the picked spell preselected.
function TB.PickGuildOrderBot(entry, bot)
    if not entry or not bot then return false end
    bot = norm(bot)
    if not bot then return false end
    if entry.kind == "enchant" then
        if not TB.OpenOrderWindow(bot) then return false end
        orderGuild = false
        windowBot = bot
        TB.SetOrderKind("enchant")
        local name = entry.item or ("spell #" .. tostring(entry.id or "?"))
        lastSearch = { bot = windowBot, kind = "enchant", text = name,
            cat = nil, items = { {
                itemId = entry.id, item = name,
                quality = nil, sources = {}, minLevel = 0,
                skill = entry.reqSkill and ("333:" .. tostring(entry.reqSkill)) or nil,
                verdict = "ok", zone = nil, chance = 0,
            } } }
        TB.SetOrderSelection(entry.id)
        return true
    end
    if not TB.OpenOrderWindow(bot) then return false end
    orderGuild = false
    windowBot = bot
    TB.SetOrderKind("craft")
    orderGuild = false
    windowBot = bot
    local name = entry.item or ("item #" .. tostring(entry.id or "?"))
    lastSearch = { bot = windowBot, kind = "craft", text = name,
        cat = orderCat, items = { {
            itemId = entry.id, item = name,
            quality = entry.quality, sources = { "craft" }, minLevel = 0,
            skill = nil, verdict = "ok", zone = nil, chance = 0,
        } } }
    TB.SetOrderSelection(entry.id)
    return true
end

function TB.CloseOrderWindow()
    searchPendingAt = nil
    if win then win:Hide() end
end

-- Professions view Craft button: opens the window with Craft picked and the
-- recipe's item already selected. The item lands in the search cache with
-- names the search verdicts as the source, so Send produces the normal
-- craft order message. Hidden or disabled unless the server verdict allows
-- it and the player may give orders.
function TB.PrefillCraftOrder(bot, recipe)
    bot = norm(bot)
    if not bot or not recipe then return false end
    local itemId = math.floor(tonumber(recipe.item) or 0)
    if itemId <= 0 then return false end
    if TB.ProfessionRecipeOrderable and not TB.ProfessionRecipeOrderable(recipe) then return false end
    if not TB.OpenOrderWindow(bot) then return false end
    TB.SetOrderKind("craft")
    local name = nil
    if GetItemInfo then name = GetItemInfo(itemId) end
    name = name or ("item #" .. tostring(itemId))
    lastSearch = { bot = windowBot, kind = "craft", text = name,
        cat = orderCat, items = { {
            itemId = itemId, item = name,
            quality = nil, sources = { "craft" }, minLevel = 0,
            skill = nil, verdict = "ok", zone = nil, chance = 0,
        } } }
    TB.SetOrderSelection(itemId)
    return true
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
        if option.current then
            addButton({ text = label, notCheckable = 1, disabled = 1 })
        else
            addButton({ text = label, notCheckable = 1,
                func = function() TB.ConfirmOrderRank(option.index, option.name) end })
        end
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
