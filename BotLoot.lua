-- TortoiseBotsManager/BotLoot.lua
-- Loot history tab: what the player's own party bots (owned alts and hired
-- companions) looted or rolled in this session.
--
-- History is per character, kept in SavedVariables (newest first, at most
-- 2000 rows), and survives relogs. On login the addon asks the server for
-- the last 24 hours of rows, starting from the last synced cursor, with no
-- duplicates. The server only ever reports bots that were in the player's
-- party at the time of the event.
--
-- The server advertises "loot-log" in TBM:CAPS. No capability: no tab, no
-- sends. Every CAPS line replaces the set, so the gate is re-checked on each
-- one (a restart that drops the feature hides everything again).
--
-- Sends (byte-exact, Inventory.cpp HandleLootLog):
--   "lootlog"          -> the first page (up to 40 rows)
--   "lootlog <cursor>" -> the next page; cursors are opaque, sent back unchanged
-- Inbound:
--   TBM:LOOT_BEGIN|<n>|<nextCursor>
--   TBM:LOOT|<ts>|<bot>|<event>|<itemId>|<item>|<sourceType>|<source>|<quality>
--   TBM:LOOT_END|<nextCursor>
-- An empty nextCursor means no more pages. The cursor "expired" means the
-- piece it pointed at was pruned: drop it and start again from the top.
-- Errors ride the generic ACTION_ERR replies (Comms.lua): "expired" restarts
-- the catch-up, "no-bot" and "invalid" are reported as-is.
--
-- Row shapes (LootAction.cpp / LootRollAction.cpp / LootHistoryPolicy.h):
--   StoreLootAction: item row. <itemId> is the item id, <item> the item
--     name, <quality> numeric 0-6.
--   LootMoney: money row. <item> is the copper amount, <itemId> the corpse
--     entry, <quality> empty.
--   LootRoll: roll row. <item> is the item name, <itemId> holds
--     "vote:itemId:reason" (vote is need/greed/disenchant/pass); the reason
--     follows the second colon and may itself hold colons.
-- sourceType is corpse, chest, gathering, object or other; source its name.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local CAP = "loot-log"
local MAX_ROWS = 2000
local QUALITY_NAMES = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" }
local ROW_TYPES = { "all", "items", "rolls" }
local KNOWN_EVENTS = { StoreLootAction = true, LootMoney = true, LootRoll = true }

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function trim(text) local s = TB.Trim(text or "") return s end

TB.LOOT_HISTORY_MAX = MAX_ROWS

-- ── capability gate ─────────────────────────────────────────────────────
function TB.HasLootCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

-- ── store ─────────────────────────────────────────────────────────────────
-- Per character: db.loot[charKey] = { rows, cursor }. Rows are newest first.
local function charKey()
    if UnitName then
        local name = UnitName("player")
        if name and name ~= "" then return name end
    end
    return "-"
end
TB.LootCharKey = charKey

local function store(writable)
    TortoiseBotsDB = TortoiseBotsDB or {}
    local key = charKey()
    if type(TortoiseBotsDB.loot) ~= "table" then
        if not writable then return nil end
        TortoiseBotsDB.loot = {}
    end
    local perChar = TortoiseBotsDB.loot[key]
    if type(perChar) ~= "table" then
        if not writable then return nil end
        perChar = {}
        TortoiseBotsDB.loot[key] = perChar
    end
    if type(perChar.rows) ~= "table" then
        if not writable then return nil end
        perChar.rows = {}
    end
    return perChar
end

function TB.GetLootHistory()
    local perChar = store(false)
    return (perChar and perChar.rows) or {}
end

function TB.GetLootCursor()
    local perChar = store(false)
    return (perChar and perChar.cursor) or ""
end

local function setCursor(cursor)
    local perChar = store(true)
    if cursor and cursor ~= "" then
        perChar.cursor = cursor
    else
        perChar.cursor = nil
    end
end

-- A row is new when its (timestamp, bot, event, itemId, item) key was never
-- stored. Catch-up pages overlap the stored history, so every page is
-- filtered through this before it is merged.
local function rowKey(row)
    return (row.ts or "") .. "|" .. (row.bot or "") .. "|" .. (row.event or "")
        .. "|" .. tostring(row.itemId or "") .. "|" .. (row.item or "")
end

-- Merge page rows (newest first from the server) into the stored history,
-- skipping duplicates, and drop the oldest past 2000. Returns the count of
-- rows actually added. Both lists merge by timestamp: a resumed catch-up can
-- surface rows older than the stored ones (a bot that joined the party
-- since), so fresh rows slot into place instead of always landing on top.
local function mergeRows(pageRows)
    local perChar = store(true)
    local rows = perChar.rows
    local seen = {}
    for _, row in ipairs(rows) do seen[rowKey(row)] = true end
    local fresh = {}
    for _, row in ipairs(pageRows) do
        local key = rowKey(row)
        if not seen[key] then
            seen[key] = true
            table.insert(fresh, row)
        end
    end
    local merged = {}
    local i, j = 1, 1
    while i <= table.getn(fresh) or j <= table.getn(rows) do
        local a, b = fresh[i], rows[j]
        if b == nil or (a ~= nil and (a.ts or "") >= (b.ts or "")) then
            table.insert(merged, a)
            i = i + 1
        else
            table.insert(merged, b)
            j = j + 1
        end
    end
    while table.getn(merged) > MAX_ROWS do table.remove(merged) end
    perChar.rows = merged
    return table.getn(fresh)
end
TB.MergeLootRows = mergeRows

-- Wipes this character's stored history (the tab's Clear button). The cursor
-- goes too: the next catch-up starts from the top.
function TB.ClearLootHistory()
    TortoiseBotsDB = TortoiseBotsDB or {}
    if type(TortoiseBotsDB.loot) == "table" then
        TortoiseBotsDB.loot[charKey()] = nil
    end
    if TB.RefreshLootView then TB.RefreshLootView() end
end

-- ── filters ───────────────────────────────────────────────────────────────
-- filters = { bot, item, quality, source, rowType }. Empty means unfiltered;
-- rowType is all/items/rolls. Quality -1 or nil means any quality; money
-- rows have no quality and only pass when quality is unfiltered.
local filters = { bot = "", item = "", quality = -1, source = "", rowType = "all" }

function TB.GetLootFilters()
    return { bot = filters.bot, item = filters.item, quality = filters.quality,
        source = filters.source, rowType = filters.rowType }
end

function TB.SetLootFilter(key, value)
    if key == "bot" or key == "item" or key == "source" then
        filters[key] = trim(value)
    elseif key == "quality" then
        local n = tonumber(value)
        filters.quality = (n and n >= 0 and n <= 6) and math.floor(n) or -1
    elseif key == "rowType" then
        value = string.lower(trim(value))
        filters.rowType = (value == "items" or value == "rolls") and value or "all"
    else
        return false
    end
    if TB.RefreshLootView then TB.RefreshLootView() end
    return true
end

local function rowIsRoll(row)
    return row.event == "LootRoll"
end

local function rowMatches(row, f)
    if f.rowType == "items" and rowIsRoll(row) then return false end
    if f.rowType == "rolls" and not rowIsRoll(row) then return false end
    if f.bot ~= "" and not string.find(string.lower(row.bot or ""), string.lower(f.bot), 1, true) then
        return false
    end
    if f.item ~= "" and not string.find(string.lower(row.item or ""), string.lower(f.item), 1, true) then
        return false
    end
    if f.quality >= 0 and row.quality ~= f.quality then return false end
    if f.source ~= "" then
        local hay = string.lower((row.sourceType or "") .. " " .. (row.source or ""))
        if not string.find(hay, string.lower(f.source), 1, true) then return false end
    end
    return true
end

-- Newest first, filtered. Every filter combines with the others.
function TB.GetFilteredLoot()
    local out = {}
    for _, row in ipairs(TB.GetLootHistory()) do
        if rowMatches(row, filters) then table.insert(out, row) end
    end
    return out
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

-- One TBM:LOOT line. Returns nil for anything that is not a well-formed loot
-- row (wrong shape, unknown event, bad number): like the INV stream, a bad
-- line is dropped, never half-kept.
local function parseLootLine(msg)
    if string.sub(msg or "", 1, 9) ~= "TBM:LOOT|" then return nil end
    local fields = splitProtocol(string.sub(msg, 10))
    if table.getn(fields) ~= 8 then return nil end
    local event = trim(fields[3])
    if not KNOWN_EVENTS[event] then return nil end
    local bot = norm(fields[2])
    if not bot or bot == "" then return nil end
    local row = { ts = trim(fields[1]), bot = bot, event = event }
    if event == "LootMoney" then
        local copper = tonumber(trim(fields[5]))
        if not copper then return nil end
        row.copper = copper
        row.item = tostring(copper)
        local entry = tonumber(trim(fields[4]))
        row.itemId = entry or trim(fields[4])
    elseif event == "LootRoll" then
        -- info2 rides in <itemId> ("vote:itemId:reason"), the item name in
        -- <item> (LootRollAction.cpp LogLootRoll).
        local _, _, vote, rest = string.find(trim(fields[4]), "^([%a]+):(.*)$")
        vote = vote and string.lower(vote) or ""
        if vote ~= "need" and vote ~= "greed" and vote ~= "disenchant" and vote ~= "pass" then
            return nil
        end
        local _, _, idText, reason = string.find(rest or "", "^(%d+):?(.*)$")
        if not idText or idText == "" then return nil end
        row.vote = vote
        row.itemId = tonumber(idText)
        row.item = trim(fields[5])
        if row.item == "" then return nil end
        row.reason = trim(reason)
        if row.reason == "" then row.reason = nil end
    else
        local id = tonumber(trim(fields[4]))
        if not id then return nil end
        row.itemId = id
        row.item = trim(fields[5])
        if row.item == "" then return nil end
        local quality = tonumber(trim(fields[8]))
        if quality and quality >= 0 and quality <= 6 then
            row.quality = math.floor(quality)
        end
    end
    row.sourceType = trim(fields[6])
    if row.sourceType == "" then row.sourceType = "other" end
    row.source = trim(fields[7])
    return row
end
TB.ParseLootLine = parseLootLine

-- Inbound router hook (Comms OnSystemMessage calls it like TB.ParseRunMessage;
-- the lootlog ACTION_ERR lines ride ParseActionMessage into TB.OnLootError).
local receiving = nil

function TB.ParseLootMessage(msg)
    if string.sub(msg or "", 1, 4) ~= "TBM:" then return false end
    local _, _, count, nextCursor = string.find(msg, "^TBM:LOOT_BEGIN|(%d+)|(.*)$")
    if count then
        receiving = { expected = tonumber(count), rows = {}, nextCursor = nextCursor or "" }
        return true
    end
    if string.sub(msg, 1, 9) == "TBM:LOOT|" then
        local row = parseLootLine(msg)
        if receiving and row then table.insert(receiving.rows, row) end
        return true
    end
    local _, _, endCursor = string.find(msg, "^TBM:LOOT_END|(.*)$")
    if endCursor ~= nil then
        local batch = receiving
        receiving = nil
        if batch then
            -- A pruned piece answers the cursor "expired": drop it and start
            -- again from the top (same as the ACTION_ERR expired reply).
            if endCursor == "expired" then
                setCursor(nil)
                if TB.SetStatus then
                    TB.SetStatus("Loot history: the saved page is gone, starting over.", "warn")
                end
                if TB.RequestLootPage then TB.RequestLootPage(nil) end
            else
                local added = mergeRows(batch.rows)
                if endCursor ~= "" then
                    setCursor(endCursor)
                    if TB.RequestLootPage then TB.RequestLootPage(endCursor) end
                else
                    setCursor(nil)
                end
                if TB.SetStatus then
                    TB.SetStatus("Loot history · " .. added .. " new rows", "ok")
                end
            end
            if TB.RefreshLootView then TB.RefreshLootView() end
        end
        return true
    end
    return false
end

-- ── sends ─────────────────────────────────────────────────────────────────
-- Catch-up on login: TB.NoteLootLogin runs from the login event (Core polls
-- the roster there), from the stored cursor so only new rows come down.
function TB.RequestLootPage(cursor)
    if not TB.HasLootCapability() then return false end
    cursor = trim(cursor)
    if cursor == "" then
        return TB.SendBotCommand("lootlog")
    end
    return TB.SendBotCommand("lootlog " .. cursor)
end

local loginSynced = false

function TB.NoteLootLogin()
    if loginSynced then return false end
    if not TB.HasLootCapability() then return false end
    loginSynced = true
    return TB.RequestLootPage(TB.GetLootCursor())
end

-- The server keeps no push stream for loot: rows written after login only
-- arrive on the next catch-up. Re-read the newest page while logged in so a
-- drop shows up in the tab within a poll interval. Pages overlap the stored
-- history, so repeats are merged away; a page still in flight is left alone.
local LOOT_POLL_SECONDS = 30
local nextLootPoll = 0
local lootPollFrame = CreateFrame("Frame")
lootPollFrame:SetScript("OnUpdate", function()
    local now = (GetTime and GetTime()) or 0
    if now < nextLootPoll then return end
    nextLootPoll = now + LOOT_POLL_SECONDS
    if loginSynced and not receiving and TB.HasLootCapability() then
        TB.RequestLootPage(nil)
    end
end)

-- Lose the capability (a restart that drops the feature): forget the
-- in-flight page and hide the tab again via the shared tab updater.
function TB.NoteLootCaps()
    if TB.UpdateRaidTab then TB.UpdateRaidTab() end
    if not TB.HasLootCapability() then
        receiving = nil
        loginSynced = false
    end
    if TB.RefreshLootView then TB.RefreshLootView() end
end

-- ACTION_ERR routing for the lootlog intent (called from ParseActionMessage):
-- "expired" restarts the catch-up from the top, "no-bot" and "invalid" are
-- reported and stop the catch-up.
function TB.OnLootError(packet)
    if not packet or packet.intent ~= "lootlog" then return false end
    if packet.code == "expired" then
        setCursor(nil)
        if TB.SetStatus then TB.SetStatus("Loot history: the saved page is gone, starting over.", "warn") end
        TB.RequestLootPage(nil)
        return true
    end
    receiving = nil
    return false
end

-- ── tab ───────────────────────────────────────────────────────────────────
local tab

local function qualityHex(quality)
    if quality and GetItemQualityColor then
        local _, _, _, hex = GetItemQualityColor(quality)
        if hex then return hex end
    end
    return "|cffffffff"
end
TB.LootQualityHex = qualityHex

local function qualityName(quality)
    if quality and quality >= 0 and quality <= 6 then return QUALITY_NAMES[quality + 1] end
    return nil
end

local function timeTail(ts)
    local _, _, tail = string.find(ts or "", "(%d%d:%d%d:%d%d)%s*$")
    if tail then return tail end
    return trim(ts)
end
TB.LootTimeTail = timeTail

local function formatCopper(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local text = ""
    if g > 0 then text = text .. "|cffffd700" .. g .. "g|r " end
    if g > 0 or s > 0 then text = text .. "|cffc7c7cf" .. s .. "s|r " end
    return text .. "|cffeda55f" .. c .. "c|r"
end
TB.FormatLootMoney = formatCopper

local VOTE_LABEL = { need = "Need", greed = "Greed", disenchant = "Disenchant", pass = "Pass" }
local VOTE_COLOR = { need = "|cff00ff00", greed = "|cffffd200", disenchant = "|cffa335ee", pass = "|cff9d9d9d" }

-- One row of text: time, bot, item in its quality colour (or the money), the
-- roll vote with its reason, and the source. Money rows have no item or vote.
local function rowText(row)
    local parts = {}
    table.insert(parts, timeTail(row.ts))
    table.insert(parts, row.bot or "?")
    if row.event == "LootMoney" then
        table.insert(parts, formatCopper(row.copper))
    else
        table.insert(parts, qualityHex(row.quality) .. "[" .. (row.item or ("item #" .. tostring(row.itemId or "?"))) .. "]|r")
        if rowIsRoll(row) then
            local vote = VOTE_LABEL[row.vote] or row.vote or "?"
            local voteText = (VOTE_COLOR[row.vote] or "") .. vote .. "|r"
            if row.reason then voteText = voteText .. " (" .. row.reason .. ")" end
            table.insert(parts, voteText)
        end
    end
    local source = row.source or ""
    if source ~= "" then
        table.insert(parts, (row.sourceType or "other") .. ": " .. source)
    elseif row.sourceType and row.sourceType ~= "other" then
        table.insert(parts, row.sourceType)
    end
    return table.concat(parts, " · ")
end
TB.LootRowText = rowText

local LOOT_ROW_H = 18
local LOOT_ROW_N = 11

function TB.CreateLootTab(parent)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local tw = (C.PANEL_W or 500) - (C.PAD or 10) * 2
    tab:SetWidth(tw); tab:SetHeight(325)

    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", 6, 0)
    title:SetText("|cffd8a657Loot history|r")

    local clearBtn = TB.StyleButton(CreateFrame("Button", nil, tab, "UIPanelButtonTemplate"))
    clearBtn:SetWidth(65); clearBtn:SetHeight(18)
    clearBtn:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -24, 2)
    clearBtn:SetText("Clear")
    if TB.UI and TB.UI.SetTooltip then
        TB.UI.SetTooltip(clearBtn, "Wipe this character's stored loot history")
    end
    clearBtn:SetScript("OnClick", function()
        if TB.ClearLootHistory then TB.ClearLootHistory() end
        if TB.RefreshLootView then TB.RefreshLootView() end
    end)
    tab.clearButton = clearBtn

    -- Filter row: bot, item, source searches plus the quality and row-type
    -- steppers. Every filter combines with the others.
    local function searchBox(name, x, width, key, tip)
        local box = CreateFrame("EditBox", name, tab, "InputBoxTemplate")
        box:SetWidth(width); box:SetHeight(20)
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", x, -20)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        box:SetScript("OnTextChanged", function()
            if TB.SetLootFilter then TB.SetLootFilter(key, this:GetText()) end
        end)
        if tip and TB.UI and TB.UI.SetTooltip then TB.UI.SetTooltip(box, tip) end
        return box
    end
    tab.botSearch = searchBox("TortoiseBotsManagerLootBotSearch", 6, 76, "bot", "Show only this bot")
    tab.itemSearch = searchBox("TortoiseBotsManagerLootItemSearch", 86, 112, "item", "Show only items with this name")
    tab.sourceSearch = searchBox("TortoiseBotsManagerLootSourceSearch", 202, 84, "source", "Show only this source")

    local function stepper(x, width, label, set, tip)
        local row = CreateFrame("Frame", nil, tab)
        row:SetWidth(width); row:SetHeight(18)
        row:SetPoint("TOPLEFT", tab, "TOPLEFT", x, -22)
        row:EnableMouse(true)
        local minus = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
        minus:SetWidth(20); minus:SetHeight(18)
        minus:SetPoint("LEFT", row, "LEFT", 0, 0)
        minus:SetText("-")
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        text:SetWidth(width - 44)
        text:SetJustifyH("CENTER")
        local plus = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
        plus:SetWidth(20); plus:SetHeight(18)
        plus:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        plus:SetText("+")
        local function paint() text:SetText(label() or "") end
        minus:SetScript("OnClick", function() set(-1); paint() end)
        plus:SetScript("OnClick", function() set(1); paint() end)
        if tip and TB.UI and TB.UI.SetTooltip then TB.UI.SetTooltip(row, tip) end
        row.label = text
        row.paint = paint
        row.minus = minus
        row.plus = plus
        paint()
        return row
    end
    tab.qualityStep = stepper(290, 100, function()
        local q = TB.GetLootFilters and TB.GetLootFilters().quality or -1
        if q < 0 then return "Any" end
        return qualityName(q) or "Any"
    end, function(dir)
        local q = (TB.GetLootFilters and TB.GetLootFilters().quality) or -1
        q = q + dir
        if q < -1 then q = 6 end
        if q > 6 then q = -1 end
        if TB.SetLootFilter then TB.SetLootFilter("quality", q) end
    end, "Item quality")
    tab.typeStep = stepper(394, 76, function()
        local t = (TB.GetLootFilters and TB.GetLootFilters().rowType) or "all"
        if t == "items" then return "Items" end
        if t == "rolls" then return "Rolls" end
        return "All"
    end, function(dir)
        local t = (TB.GetLootFilters and TB.GetLootFilters().rowType) or "all"
        local idx = 1
        for i, name in ipairs(ROW_TYPES) do if name == t then idx = i end end
        idx = idx + dir
        if idx < 1 then idx = table.getn(ROW_TYPES) end
        if idx > table.getn(ROW_TYPES) then idx = 1 end
        if TB.SetLootFilter then TB.SetLootFilter("rowType", ROW_TYPES[idx]) end
    end, "Row type: items, rolls, or all")

    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerLootScroll", tab, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -44)
    scroll:SetWidth(tw)
    scroll:SetHeight(LOOT_ROW_N * LOOT_ROW_H + 4)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(LOOT_ROW_H, TB.RefreshLootView)
    end)
    TB.lootScroll = scroll

    local rows = {}
    for i = 1, LOOT_ROW_N do
        local row = CreateFrame("Frame", nil, tab)
        row:SetWidth(tw - 20)
        row:SetHeight(LOOT_ROW_H)
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * LOOT_ROW_H)
        local line = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
        line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        line:SetJustifyH("LEFT")
        line:SetHeight(14)
        row.line = line
        table.insert(rows, row)
    end
    TB.lootRows = rows

    local empty = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
    empty:SetWidth(tw - 40)
    empty:SetJustifyH("CENTER")
    empty:SetText("|cff888888No loot yet. Your party bots' loot and rolls land here.|r")
    TB.SetTextColor(empty, color("muted"))
    tab.emptyMsg = empty

    tab:Hide()
    return tab
end

function TB.RefreshLootView()
    if not TB.lootScroll or not TB.lootRows then return end
    local list = TB.GetFilteredLoot and TB.GetFilteredLoot() or {}
    local total = table.getn(list)
    FauxScrollFrame_Update(TB.lootScroll, total, LOOT_ROW_N, LOOT_ROW_H)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(TB.lootScroll)) or 0
    for i = 1, LOOT_ROW_N do
        local row = TB.lootRows[i]
        local entry = list[offset + i]
        if entry then
            row.line:SetText(rowText(entry))
            row:Show()
        else
            row:Hide()
        end
    end
    if tab and tab.emptyMsg then
        if total == 0 then tab.emptyMsg:Show() else tab.emptyMsg:Hide() end
    end
    if tab then
        if tab.qualityStep and tab.qualityStep.paint then tab.qualityStep.paint() end
        if tab.typeStep and tab.typeStep.paint then tab.typeStep.paint() end
    end
end
