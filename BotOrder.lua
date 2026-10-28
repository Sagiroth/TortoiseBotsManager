-- TortoiseBotsManager/BotOrder.lua
-- Guild orders: give a claimed guild bot a farm / buy / craft order from the
-- Guild tab and watch its progress live.
--
-- The server advertises "guild-orders" in TBM:CAPS. No capability: no Order
-- buttons, no window, no sends. Every CAPS line replaces the set, so the
-- gate is re-checked on each one (as BotLoot.lua does).
--
-- Sends (byte-exact, contract: TortoiseBots#1297 "Addon contract"):
--   "order list"                                   -> full order snapshot
--   "order search <bot> <farm|buy|craft> <text>"   -> item search (>=3 chars)
--   "order <bot> <farm|buy|craft> <itemId> <n>"    -> give or replace (1-200)
--   "order <bot> cancel"                           -> remove the order
-- Inbound:
--   TBM:ORDER_BEGIN|<n>
--   TBM:ORDER|<bot>|<type>|<itemId>|<item>|<have>|<want>|<state>|<reason>|<zone>
--   TBM:ORDER_END
--   TBM:ORDER_ITEMS_BEGIN|<n>
--   TBM:ORDER_ITEM|<itemId>|<item>|<quality>|<sources>|<minLevel>|<skill>|<verdict>|<zone>|<chance>
--   TBM:ORDER_ITEMS_END
--   TBM:ACTION_ACK|order|bot:<Bot>|1|<farm|buy|craft|cancel>
--   TBM:ACTION_ERR|order|<code>|<message>
-- A TBM:ORDER line inside BEGIN/END is the full list (replace the whole
-- set); outside a pair it is a live update for one bot (update that row
-- only). The search pair is its own stream, so an empty result is a real
-- answer. Unknown state / reason tokens are shown raw, never crash.
-- <reason> "-" means none; <zone> "-" means none; <chance> is percent.
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
    done = "Done", mailed = "Mailed", noskill = "No skill", cant = "Can't",
}
local STATE_COLOR = {
    working = "|cff4ecb5a", waiting = "|cffffd200", delivering = "|cffffd200",
    done = "|cff4ecb5a", mailed = "|cffffd200", noskill = "|cffff5050", cant = "|cffff5050",
}
local REASON_LABEL = {
    grouped = "in a group", noskill = "missing profession", lowskill = "skill too low",
    lowlevel = "bot under level 10", norange = "nothing in level range",
    nosource = "no source", norecipe = "unknown recipe", stuck = "stuck, gave up",
    bagsfull = "bags full", nobank = "no bank deposit",
}
local SOURCE_LABEL = { drop = "drop", skin = "skin", herb = "herb", ore = "ore", craft = "craft", ah = "AH" }
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
-- count nodes, everything else kills. Buy and craft show no estimate.
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
    end
    if count == 1 then unit = string.sub(unit, 1, string.len(unit) - 1) end
    return "about " .. count .. " " .. unit
end

-- ── model ─────────────────────────────────────────────────────────────────
-- orders[bot] = { bot, type, itemId, item, have, want, state, reason, zone }
local orders = {}

function TB.GetBotOrder(bot)
    bot = norm(bot)
    return bot and orders[bot] or nil
end

function TB.GetOrders()
    local out = {}
    for _, order in pairs(orders) do table.insert(out, order) end
    table.sort(out, function(a, b) return (a.bot or "") < (b.bot or "") end)
    return out
end

-- One guild-row line: item, progress, state. The reason stays in the
-- tooltip (RefreshGuildView + the row tooltip in UI.lua).
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
    if state == "working" then
        local text = item .. " " .. progress
        if order.zone then text = text .. " (" .. order.zone .. ")" end
        return text
    elseif state == "waiting" then
        return item .. " " .. progress .. " · " .. word("Waiting")
    elseif state == "delivering" then
        return word("Delivering") .. " " .. item
    elseif state == "done" then
        return item .. " · " .. word("Done")
    elseif state == "mailed" then
        return item .. " · " .. word("Mailed to GM")
    elseif state == "noskill" then
        return item .. " · " .. word("No skill")
    elseif state == "cant" then
        return item .. " · " .. word("Can't")
    end
    return item .. " " .. progress .. " · " .. trim(order.state or "")
end

-- Tooltip body for a bot's order: type, progress, state, reason, zone.
function TB.OrderTooltipText(order)
    if not order then return nil end
    local lines = { "Order: " .. TB.OrderTypeLabel(order.type) .. " " .. (order.item or "?")
        .. " " .. tostring(order.have or 0) .. "/" .. tostring(order.want or 0) }
    local state = "State: " .. TB.OrderStateLabel(order.state)
    local reason = TB.OrderReasonLabel(order.reason)
    if reason then state = state .. " (" .. reason .. ")" end
    table.insert(lines, state)
    if order.zone then table.insert(lines, "Zone: " .. order.zone) end
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

function TB.ParseOrderLine(msg)
    if string.sub(msg or "", 1, 10) ~= "TBM:ORDER|" then return nil end
    local fields = splitProtocol(string.sub(msg, 11))
    if table.getn(fields) ~= 9 then return nil end
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
    return {
        bot = bot, type = kind, itemId = math.floor(itemId), item = item,
        have = math.floor(have), want = math.floor(want), state = state,
        reason = noneDash(fields[8]), zone = noneDash(fields[9]),
    }
end

function TB.ParseOrderItemLine(msg)
    if string.sub(msg or "", 1, 15) ~= "TBM:ORDER_ITEM|" then return nil end
    local fields = splitProtocol(string.sub(msg, 16))
    if table.getn(fields) ~= 9 then return nil end
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
    }
end

-- Last completed search: { bot, kind, text, items }.
local lastSearch = { bot = nil, kind = "farm", text = "", items = {} }
local searchBot, searchKind, searchText = nil, "farm", ""
local orderReceiving, itemsReceiving = nil, nil

function TB.GetOrderSearch()
    return { bot = lastSearch.bot, kind = lastSearch.kind, text = lastSearch.text,
        items = lastSearch.items or {} }
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
                items = batch.rows }
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

function TB.SendOrderSearch(bot, kind, text)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    text = trim(text or "")
    if not bot or (kind ~= "farm" and kind ~= "buy" and kind ~= "craft") then return false end
    if string.len(text) < SEARCH_MIN then return false end
    searchBot, searchKind, searchText = bot, kind, text
    return TB.SendBotCommand("order search " .. bot .. " " .. kind .. " " .. text)
end

function TB.ClampOrderAmount(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < AMOUNT_MIN then amount = AMOUNT_MIN end
    if amount > AMOUNT_MAX then amount = AMOUNT_MAX end
    return amount
end

function TB.SendOrderGive(bot, kind, itemId, amount)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    kind = string.lower(trim(kind or ""))
    itemId = math.floor(tonumber(itemId) or 0)
    if not bot or (kind ~= "farm" and kind ~= "buy" and kind ~= "craft") then return false end
    if itemId <= 0 then return false end
    return TB.SendBotCommand("order " .. bot .. " " .. kind .. " " .. itemId
        .. " " .. TB.ClampOrderAmount(amount))
end

function TB.SendOrderCancel(bot)
    if not TB.HasOrderCapability() then return false end
    bot = norm(bot)
    if not bot then return false end
    return TB.SendBotCommand("order " .. bot .. " cancel")
end

-- ACK routing from Comms.ParseActionMessage for the order intent. A cancel
-- ACK drops the row at once (no live line can follow a removed order); a
-- give ACK closes the window, the live line paints the progress.
function TB.OnOrderAck(packet)
    if not packet or packet.intent ~= "order" then return false end
    local _, _, scopeBot = string.find(packet.scope or "", "^bot:(.+)$")
    local bot = norm(scopeBot)
    if packet.executor == "cancel" then
        if bot then orders[bot] = nil end
        if TB.SetStatus then
            TB.SetStatus((bot or "Order") .. ": order cancelled.", "ok")
        end
        if TB.RefreshGuildView then TB.RefreshGuildView() end
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
    lastSearch = { bot = nil, kind = "farm", text = "", items = {} }
    orderReceiving, itemsReceiving = nil, nil
    searchBot = nil
    TB.CloseOrderWindow()
    if TB.RefreshGuildView then TB.RefreshGuildView() end
end

-- ── list refresh ──────────────────────────────────────────────────────────
-- "order list" goes out when the Guild tab opens (UI.lua) and every 30 s
-- while it stays open; live TBM:ORDER lines paint progress in between.
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
local orderAmount = 10
local selectedItemId = nil
local searchPendingAt = nil
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
    lastSearch = { bot = windowBot, kind = kind, text = "", items = {} }
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    -- A new kind re-runs a valid search at once: verdicts differ per kind
    -- (a craft search refuses unknown recipes, a farm search does not).
    if win and windowBot and win.searchBox then
        local text = trim(win.searchBox:GetText() or "")
        if string.len(text) >= SEARCH_MIN then
            TB.SendOrderSearch(windowBot, orderKind, text)
        end
    end
    return true
end

function TB.GetOrderAmount()
    return orderAmount
end

function TB.SetOrderAmount(amount)
    orderAmount = TB.ClampOrderAmount(amount)
    if win and win.amountBox then win.amountBox:SetText(tostring(orderAmount)) end
    if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
    return orderAmount
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
-- level, skill, zone and the farm estimate for the current amount.
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
            if label then return "needs " .. label end
        elseif verdict == "lowlevel" then
            return "needs level 10"
        elseif verdict == "norange" and level then
            return "no source near level " .. level
        end
        local label = TB.OrderReasonLabel(item.verdict)
        return "Can't: " .. (label or item.verdict)
    end
    local parts = {}
    local sources = TB.OrderSourcesLabel(item.sources)
    if sources ~= "" then table.insert(parts, sources) end
    if (item.minLevel or 0) > 0 then table.insert(parts, "lvl " .. item.minLevel .. "+") end
    local skill = TB.OrderSkillLabel(item.skill)
    if skill then table.insert(parts, skill) end
    if item.zone then table.insert(parts, item.zone) end
    local estimate = TB.OrderEstimate(kind, item.sources, item.chance, amount)
    if estimate then table.insert(parts, estimate) end
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
local function armSearch()
    searchPendingAt = now() + SEARCH_DEBOUNCE
end

local function firePendingSearch()
    if not searchPendingAt or now() < searchPendingAt then return end
    searchPendingAt = nil
    if not (win and windowBot and win.searchBox) then return end
    local text = trim(win.searchBox:GetText() or "")
    if string.len(text) < SEARCH_MIN then
        lastSearch = { bot = windowBot, kind = orderKind, text = text, items = {} }
        selectedItemId = nil
        TB.SetOrderFeedback("Type at least 3 letters to search.", "muted")
        if TB.RefreshOrderWindow then TB.RefreshOrderWindow() end
        return
    end
    TB.SendOrderSearch(windowBot, orderKind, text)
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerOrderWindow", TB.frame or UIParent)
    win:SetWidth(OW); win:SetHeight(396)
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
            if string.len(text) >= SEARCH_MIN then
                TB.SendOrderSearch(windowBot, orderKind, text)
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

    local results = CreateFrame("ScrollFrame", "TortoiseBotsManagerOrderResults", win, "FauxScrollFrameTemplate")
    results:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -106)
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
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(win.resultRows, row)
    end

    win.emptyMsg = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.emptyMsg:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -150)
    win.emptyMsg:SetWidth(OW - 24)
    win.emptyMsg:SetJustifyH("CENTER")
    TB.SetTextColor(win.emptyMsg, color("muted"))

    local base = 106 + RESULT_ROW_N * RESULT_ROW_H + 4
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

    win.sendBtn = smallButton(win, "Send", 76, 194, -(base + 2),
        "Send order", "Give this bot the order (replaces its old one).",
        function()
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
            TB.SetOrderFeedback(TB.OrderTypeLabel(orderKind) .. " " .. item.item
                .. " x" .. orderAmount .. " sent, waiting for the server...", "pending")
            TB.SendOrderGive(windowBot, orderKind, item.itemId, orderAmount)
        end)

    win.cancelBtn = smallButton(win, "Cancel", 62, 274, -(base + 2),
        "Cancel order", "Remove this bot's current order.",
        function()
            if windowBot then TB.SendOrderCancel(windowBot) end
        end)

    win.statusLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.statusLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 28))
    win.statusLine:SetWidth(OW - 24); win.statusLine:SetJustifyH("LEFT")
    TB.SetTextColor(win.statusLine, color("muted"))

    win.feedbackLine = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.feedbackLine:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(base + 44))
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
    local search = TB.GetOrderSearch()
    local items = {}
    if search.bot == windowBot and search.kind == orderKind then
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
            row.name:SetText(qualityHex(item.quality) .. item.item .. "|r")
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
            if string.len(text) < SEARCH_MIN then
                win.emptyMsg:SetText("Type at least 3 letters to search.")
            elseif search.bot == windowBot and search.kind == orderKind then
                win.emptyMsg:SetText("No matching items.")
            else
                win.emptyMsg:SetText("Searching...")
            end
            win.emptyMsg:Show()
        else
            win.emptyMsg:Hide()
        end
    end
    if win.amountBox and win.amountBox:GetText() ~= tostring(orderAmount) then
        -- A re-render while typing must not steal the half-typed number, so
        -- only fix the box when it drifted off the clamped amount.
        local shown = tonumber(win.amountBox:GetText() or "")
        if not shown or TB.ClampOrderAmount(shown) ~= shown or shown ~= orderAmount then
            win.amountBox:SetText(tostring(orderAmount))
        end
    end
    local order = windowBot and TB.GetBotOrder(windowBot) or nil
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
    local switched = windowBot ~= bot
    windowBot = bot
    if switched then
        orderAmount = 10
        selectedItemId = nil
        feedback = nil
        searchPendingAt = nil
        lastSearch = { bot = bot, kind = orderKind, text = "", items = {} }
        if win.searchBox then win.searchBox:SetText("") end
        if win.amountBox then win.amountBox:SetText("10") end
    end
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
