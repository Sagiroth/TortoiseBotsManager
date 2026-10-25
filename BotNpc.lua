-- TortoiseBotsManager/BotNpc.lua
-- Per-bot NPC errands for the open bot: gossip, hearth, trainer, flights.
--
-- Every mature verb behind these buttons needs a nearby NPC or object
-- server-side, so the bot answers with short chat/whisper lines instead of
-- the structured TBM:INV_* snapshot:
--   "talk" opens gossip on the targeted NPC ("gossip hello" chain,
--   EmoteStrategy talk entry, ChatCommandHandlerStrategy.cpp "talk" node)
--   "home" binds at an innkeeper ("This inn is my new home",
--   SetHomeAction.cpp:68)
--   "trainer learn" learns green spells at the targeted trainer
--   ("--- Can learn from <name> ---" header, TrainerAction.cpp:251)
--   "taxi ?" lists this flight master's routes ("=== Taxi ===" then
--   "<n>: <name>" lines, TaxiAction.cpp:49-62); "taxi <n>" flies that leg.
-- Flights are strictly list+pick: no bare-taxi button exists, because a bare
-- "taxi" with no stored route buys nothing (TaxiAction.cpp:66-85).
-- Clicks go through the existing "command <bot> <verb>" proxy
-- (HandleMatureCommand, TB-research/commands/Party.cpp:822); one-shot
-- confirmations stay on the command-op gate, only the "=== Taxi ===" burst
-- is captured, and only for the open NPC bot while its query is pending.
--
-- Brief rule (two review bugs elsewhere): whisper/list parsing must only
-- consume lines of an open reply from that bot and must complete its
-- operation. The taxi burst arms on send, consumes only after its header,
-- times out after 8 quiet seconds, and completes the command op on every
-- terminal path (header+lines, empty list, timeout, close, bot switch).

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local NW = 300
local NH = 274
local ROWS = 6

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── model ─────────────────────────────────────────────────────────────────
-- [bot] = { at, pending, header, flights = { { n, name } } }
local npcs = {}

function TB.GetNpcErrands(name)
    name = norm(name)
    return name and npcs[name] or nil
end

local function entry(name)
    name = norm(name)
    if not name then return nil end
    local e = npcs[name]
    if not e then e = { flights = {} }; npcs[name] = e end
    return e
end

function TB.SetNpcPending(name, pending)
    name = norm(name)
    if not name then return end
    local e = entry(name)
    e.pending = pending and true or false
    e.header = false
    e.at = now()
end

local function clearOp(name)
    if TB.CompleteOperation then TB.CompleteOperation(name, "command", true, "NPC query sent.") end
    local st = TB.GetState and TB.GetState(name) or nil
    if st then st.pendingAI = nil; st.pendingAIUntil = nil end
end

-- One-shot sends (talk/home/trainer/learn/leader): the reply is a short
-- confirmation on the command-op gate, so nothing is armed here.
function TB.SendNpcTalk(name)
    name = norm(name)
    if not name then return false end
    if TB.SetStatus then TB.SetStatus(name .. " talks to the selected NPC…", "pending") end
    return TB.SendBotCommand("command " .. name .. " talk")
end

function TB.SendNpcHome(name)
    name = norm(name)
    if not name then return false end
    if TB.SetStatus then TB.SetStatus(name .. " binds at this inn…", "pending") end
    return TB.SendBotCommand("command " .. name .. " home")
end

function TB.SendNpcTrainerLearn(name)
    name = norm(name)
    if not name then return false end
    if TB.SetStatus then TB.SetStatus(name .. " learns from this trainer…", "pending") end
    return TB.SendBotCommand("command " .. name .. " trainer learn")
end

function TB.SendNpcGiveLeader(name)
    name = norm(name)
    if not name then return false end
    if TB.SetStatus then TB.SetStatus(name .. " passes you the lead…", "pending") end
    return TB.SendBotCommand("command " .. name .. " give leader")
end

-- Parses "12: Stormwind, Elwynn" (TaxiAction.cpp:60 "<n>: <name>").
local function parseFlightLine(msg)
    if not msg then return nil end
    local _, _, n, label = string.find(msg, "^(%d+)%s*:%s*(.+)$")
    n = tonumber(n)
    if not n or not label then return nil end
    label = TB.Trim(label)
    if label == "" then return nil end
    return n, label
end
TB.ParseFlightLine = parseFlightLine

-- Returns "header" / flight count / false. Only lines from the open NPC bot
-- while its taxi query is pending reach the list; anything else stays on the
-- command-op gate so talk/home/trainer/leader confirmations keep working.
-- The bot has no end-of-list marker (one whisper per line), so later lines
-- after 8 quiet seconds fall back to the gate, completing the op.
function TB.ConsumeTaxiReply(name, msg)
    name = norm(name)
    if not name or not msg or msg == "" then return false end
    if name ~= TB.GetNpcBot() then return false end
    local e = npcs[name]
    if not e or not e.pending then return false end
    if now() - (e.at or 0) > (C.ACTION_TIMEOUT or 8) then
        e.pending = false
        e.header = false
        clearOp(name)
        if TB.RefreshNpc then TB.RefreshNpc() end
        return false
    end
    if string.find(msg, "=== Taxi ===") then
        e.flights = {}
        e.header = true
        e.at = now()
        if TB.RefreshNpc then TB.RefreshNpc() end
        return "header"
    end
    if not e.header then return false end
    local n, label = parseFlightLine(msg)
    if not n then return false end
    e.flights = e.flights or {}
    for _, known in ipairs(e.flights) do
        if known.n == n then return table.getn(e.flights) end
    end
    table.insert(e.flights, { n = n, name = label })
    e.at = now()
    if TB.RefreshNpc then TB.RefreshNpc() end
    return table.getn(e.flights)
end

function TB.RequestFlights(name)
    name = norm(name)
    if not name then return false end
    local e = entry(name)
    e.flights = {}
    e.pending = true
    e.header = false
    e.at = now()
    page = 1
    local sent = TB.SendBotCommand("command " .. name .. " taxi ?")
    -- The proxy acks with "Forwarded command" but no completion line ever
    -- follows a list query, so the command op is completed on send: leaving
    -- it would show a working state until it times out.
    clearOp(name)
    if TB.SetStatus then TB.SetStatus("Asking " .. name .. " for flights…", "pending") end
    if TB.RefreshNpc then TB.RefreshNpc() end
    return sent
end

function TB.SendNpcFly(name, n)
    name = norm(name)
    n = tonumber(n)
    if not name or not n then return false end
    local e = npcs[name]
    if e then e.pending = false; e.header = false end
    if TB.SetStatus then TB.SetStatus(name .. " flies…", "pending") end
    return TB.SendBotCommand("command " .. name .. " taxi " .. n)
end

-- ── window ────────────────────────────────────────────────────────────────
local npc
local currentBot
local page = 1

function TB.GetNpcBot()
    return npc and npc:IsVisible() and currentBot or nil
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

local function orderButton(parent, label, x, y, tip, tipTitle, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(134); b:SetHeight(22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    setTooltip(b, tipTitle, { tip })
    return b
end

local function createNpc()
    npc = CreateFrame("Frame", "TortoiseBotsManagerBotNpc", TB.frame or UIParent)
    npc:SetWidth(NW); npc:SetHeight(NH)
    npc:SetFrameStrata("DIALOG")
    npc:EnableMouse(true)
    npc:SetMovable(true)
    npc:SetClampedToScreen(true)
    npc:RegisterForDrag("LeftButton")
    npc:SetScript("OnDragStart", function() npc:StartMoving() end)
    npc:SetScript("OnDragStop", function()
        npc:StopMovingOrSizing()
        -- 1.12-safe: StopMovingOrSizing detaches the anchor from the
        -- logical parent (see UI.lua drag header), so re-anchor with
        -- GetLeft/GetTop instead of ever calling GetPoint() after a drag.
        local left, top = npc:GetLeft(), npc:GetTop()
        if left and top then
            npc:ClearAllPoints()
            npc:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerBotNpc") end
    TB.ApplyBackdrop(npc, 0.98, 1.0)

    local name = npc:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", npc, "TOPLEFT", 12, -10)
    name:SetWidth(NW - 50); name:SetJustifyH("LEFT")
    npc.nameText = name

    local close = CreateFrame("Button", nil, npc, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", npc, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseNpc() end)

    npc.talk = orderButton(npc, "Talk", 12, -38,
        "The bot greets the NPC you both stand at.",
        "Talk", function()
            if currentBot then TB.SendNpcTalk(currentBot) end
        end)
    npc.home = orderButton(npc, "Bind home", 154, -38,
        "The bot binds its hearthstone at this innkeeper.",
        "Bind home", function()
            if currentBot then TB.SendNpcHome(currentBot) end
        end)
    npc.trainer = orderButton(npc, "Train spells", 12, -64,
        "The bot learns what it can from the trainer you both stand at.",
        "Train spells", function()
            if currentBot then TB.SendNpcTrainerLearn(currentBot) end
        end)
    npc.leader = orderButton(npc, "Take lead", 154, -64,
        "The bot passes party leadership to you.",
        "Take lead", function()
            if currentBot then TB.SendNpcGiveLeader(currentBot) end
        end)

    local flights = npc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    flights:SetPoint("TOPLEFT", npc, "TOPLEFT", 12, -92)
    flights:SetText("FLIGHTS")
    TB.SetTextColor(flights, color("gold"))
    local flightHint = npc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flightHint:SetPoint("TOPLEFT", npc, "TOPLEFT", 140, -92)
    flightHint:SetWidth(NW - 152); flightHint:SetJustifyH("RIGHT")
    flightHint:SetText("Be at a flight master.")
    TB.SetTextColor(flightHint, color("muted"))

    npc.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, npc, "UIPanelButtonTemplate")
        row:SetWidth(NW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", npc, "TOPLEFT", 12, -108 - (i - 1) * 22)
        row:SetScript("OnClick", function()
            if currentBot and this.flightN then TB.SendNpcFly(currentBot, this.flightN) end
        end)
        table.insert(npc.rows, row)
    end
    local flightEmpty = npc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flightEmpty:SetPoint("TOPLEFT", npc, "TOPLEFT", 12, -168)
    flightEmpty:SetWidth(NW - 24); flightEmpty:SetJustifyH("CENTER")
    flightEmpty:SetText("Stand at a flight master and click Find flights.")
    TB.SetTextColor(flightEmpty, color("muted"))
    npc.flightEmpty = flightEmpty


    npc.ask = CreateFrame("Button", nil, npc, "UIPanelButtonTemplate")
    npc.ask:SetWidth(134); npc.ask:SetHeight(22)
    npc.ask:SetPoint("TOPLEFT", npc, "TOPLEFT", 12, -108 - ROWS * 22)
    npc.ask:SetText("Find flights")
    npc.ask:SetScript("OnClick", function()
        if currentBot then TB.RequestFlights(currentBot) end
    end)
    setTooltip(npc.ask, "Find flights", { "Lists this flight master's routes, then pick one." })

    local prev = CreateFrame("Button", nil, npc, "UIPanelButtonTemplate")
    prev:SetWidth(26); prev:SetHeight(22)
    prev:SetPoint("TOPLEFT", npc, "TOPLEFT", 154, -108 - ROWS * 22)
    prev:SetText("<")
    prev:SetScript("OnClick", function() page = page - 1; TB.RefreshNpc() end)
    npc.prevPage = prev
    local nextBtn = CreateFrame("Button", nil, npc, "UIPanelButtonTemplate")
    nextBtn:SetWidth(26); nextBtn:SetHeight(22)
    nextBtn:SetPoint("TOPLEFT", npc, "TOPLEFT", 262, -108 - ROWS * 22)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function() page = page + 1; TB.RefreshNpc() end)
    npc.nextPage = nextBtn
    local pageText = npc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("TOPLEFT", npc, "TOPLEFT", 182, -112 - ROWS * 22)
    pageText:SetWidth(78); pageText:SetJustifyH("CENTER")
    TB.SetTextColor(pageText, color("muted"))
    npc.pageText = pageText

    npc:Hide()
    TB.botNpc = npc
end

local function renderRows()
    local e = currentBot and npcs[currentBot] or nil
    local list = (e and e.flights) or {}
    local pages = math.max(1, math.ceil(table.getn(list) / ROWS))
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    for i, row in ipairs(npc.rows) do
        local flight = list[(page - 1) * ROWS + i]
        if flight then
            row.flightN = flight.n
            row:SetText(flight.n .. ": " .. flight.name)
            setTooltip(row, flight.name, { "Click: fly this leg." })
            row:Show()
            row:Enable()
        else
            row.flightN = nil
            row:SetText("")
            row:Hide()
        end
    end
    npc.pageText:SetText(page .. " / " .. pages)
    if page > 1 then npc.prevPage:Enable() else npc.prevPage:Disable() end
    if page < pages then npc.nextPage:Enable() else npc.nextPage:Disable() end
    if e and e.pending and table.getn(list) == 0 then
        npc.ask:SetText("Asking…")
        npc.ask:Disable()
    else
        npc.ask:SetText("Find flights")
        npc.ask:Enable()
    end
    if npc.flightEmpty then
        if table.getn(list) == 0 then npc.flightEmpty:Show() else npc.flightEmpty:Hide() end
    end
    return list
end

function TB.RefreshNpc()
    if not npc or not npc:IsVisible() or not currentBot then return end
    local entry = (TB.GetRosterEntry and TB.GetRosterEntry(currentBot))
        or (TB.GetClaimedEntry and TB.GetClaimedEntry(currentBot)) or nil
    local classId = entry and entry.classId
    local col = (classId and C.CLASS_COLORS and C.CLASS_COLORS[classId]) or color("gold")
    npc.nameText:SetText(currentBot or "")
    npc.nameText:SetTextColor(col[1], col[2], col[3])
    local e = npcs[currentBot]
    local list = renderRows()
    if e and e.header then
        if table.getn(list) == 0 then
            npc.ask:SetText("No flights here")
        else
            npc.ask:SetText("Find flights")
        end
    end
end

function TB.OpenNpc(name)
    name = norm(name)
    if not name then return false end
    if not npc then createNpc() end
    if currentBot and currentBot ~= name then TB.SetNpcPending(currentBot, false) end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.SetMode then TB.SetMode("full") end
    if currentBot ~= name then page = 1 end
    currentBot = name
    npc:ClearAllPoints()
    local anchor = (TB.botPanel and TB.botPanel.IsVisible and TB.botPanel:IsVisible()) and TB.botPanel or TB.frame
    if anchor and anchor ~= TB.frame then
        local aRight = anchor.GetRight and anchor:GetRight()
        local fLeft = TB.frame and TB.frame.GetLeft and TB.frame:GetLeft()
        local aLeft = anchor.GetLeft and anchor:GetLeft()
        if aRight and fLeft and aRight <= fLeft then
            -- The panel sits LEFT of main: anchor right of the panel would
            -- land on main, so dock left of the panel (or right of main
            -- when the panel hugs the left screen edge).
            if aLeft and aLeft - NW - 4 >= 0 then
                npc:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
            elseif TB.frame then
                npc:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
            else
                npc:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        else
            local right = anchor.GetRight and anchor:GetRight()
            local screen = GetScreenWidth and GetScreenWidth()
            local scale = (anchor.GetScale and anchor:GetScale()) or 1
            if right and screen and (right + NW + 4) * scale > screen then
                -- The panel sits right of main: anchoring left of the panel
                -- would land on top of main, so dock left of main instead.
                npc:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
            else
                npc:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        end
    elseif TB.frame then
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + NW + 4) * scale > screen then
            npc:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            npc:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        npc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    npc:Show()
    TB.RefreshNpc()
    return true
end

function TB.CloseNpc()
    if currentBot then TB.SetNpcPending(currentBot, false) end
    if npc then npc:Hide() end
end
