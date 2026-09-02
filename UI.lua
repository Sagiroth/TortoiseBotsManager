-- TortoiseBotsManager/UI.lua
--
-- Two independent surfaces:
--   Actions — compact gameplay intents.  Every click sends exactly one
--             `.bot action ...` command and never inspects roster selection.
--   Roster  — server snapshot rows with checkbox multi-select and a contextual
--             lifecycle/group bar.  Selection is used only by that bar.
--
-- The panel uses only Vanilla 1.12 widgets and keeps command construction in
-- Comms.lua for callers that still use the legacy raw command API.

local TB = TortoiseBots
local C  = TB.C or {}
local W, H = C.PANEL_W or 500, C.PANEL_H or 395
local ROW_H, ROW_N = C.ROW_H or 28, C.ROW_N or 7
local COL = C.COLOR or {}

local CreateHeader, CreateFilterRow, CreateScroll, CreateRow
local CreateRosterBar, CreateActions, CreateStatusBar
local RefreshCounts, RefreshRows, RefreshRosterSelection

local function color(name, fallback)
    return COL[name] or fallback or { 1, 1, 1 }
end

local function hasCurrentTarget()
    if UnitExists and not UnitExists("target") then return false end
    if UnitIsDead and UnitIsDead("target") then return false end
    return true
end
local function targetIsPlayer()
    return not UnitIsPlayer or UnitIsPlayer("target")
end

local function targetName()
    if UnitExists and not UnitExists("target") then return nil end
    if not UnitName then return nil end
    local name = UnitName("target")
    return name and TB.NormalizeName(name) or nil
end

local function hasValidEnemyTarget()
    if not hasCurrentTarget() then return false end
    if not targetIsPlayer() then return true end
    local name = targetName()
    if name and TB.GetRosterEntry then
        local entry = TB.GetRosterEntry(name)
        if entry and entry.source == "snapshot" and entry.serverState ~= "offline" then
            return false
        end
    end
    return true
end

local function targetScope()
    local name = targetName()
    if targetIsPlayer() and name and TB.GetRosterEntry then
        local entry = TB.GetRosterEntry(name)
        local serverState = entry and (entry.serverState or (entry.st and entry.st.serverState))
        if entry and serverState == "online" then
            return "bot:" .. (entry.name or name), entry.name or name
        end
    end
    return "party", nil
end

function TB.GetActionScope()
    local scope = targetScope()
    return scope
end

function TB.GetActionScopeHint()
    local scope, name = targetScope()
    if scope == "party" then return "Party actions" end
    return "Target: " .. name
end

local function serverSupports(command)
    if not TB.ServerCapabilitiesKnown or not TB.ServerCapabilitiesKnown() then return true end
    return TB.HasServerCommand and TB.HasServerCommand(command) or false
end

local ACTION_TOOLTIPS = {
    pull = "Tank uses the native pull action; it does not return to the pull position.",
    pullback = "Tank uses the native pull action and returns to the pull position.",
}

local function setButtonTooltip(button, text)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── section factories ───────────────────────────────────────────────────────
CreateHeader = function(parent)
    local db = TortoiseBotsDB or {}
    parent:SetWidth(W)
    parent:SetHeight(H)
    local frameDB = db.frame or {}
    parent:SetPoint(frameDB.point or "CENTER", UIParent, frameDB.rpoint or "CENTER",
        frameDB.x or 0, frameDB.y or 15)
    parent:SetFrameStrata("DIALOG")
    parent:SetMovable(true)
    parent:EnableMouse(true)
    parent:RegisterForDrag("LeftButton")
    parent:SetScript("OnDragStart", function() this:StartMoving() end)
    parent:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local p, _, rp, x, y = this:GetPoint()
        db.frame = db.frame or {}
        db.frame.point, db.frame.rpoint = p, rp
        db.frame.x, db.frame.y = x, y
    end)
    TB.ApplyBackdrop(parent, 0.98, 1.0)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerFrame") end

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22); icon:SetHeight(22)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD or 10, -7)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("|cffd8a657Tortoise|r|cff4ecb5aBots|r |cfffff2ccManager|r  |cffffd200v"
        .. (TB.version or "?") .. "|r")

    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(0.55, 0.35, 0.08, 0.12)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -4)
    glow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -4)
    glow:SetHeight(30)

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(0.48, 0.36, 0.15, 0.70)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD or 10, -34)
    divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(C.PAD or 10), -34)
    divider:SetHeight(1)
end

CreateFilterRow = function(parent)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    label:SetText("Filter")
    TB.SetTextColor(label, color("muted"))

    local search = CreateFrame("EditBox", "TortoiseBotsManagerSearch", parent, "InputBoxTemplate")
    search:SetWidth(145); search:SetHeight(20)
    search:SetPoint("LEFT", label, "RIGHT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search

    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetWidth(40); clear:SetHeight(18)
    clear:SetPoint("LEFT", search, "RIGHT", C.GAP_BTN or 4, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
        TB.filterText = ""
        TB.Refresh()
    end)

    local refresh = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refresh:SetWidth(58); refresh:SetHeight(18)
    refresh:SetPoint("LEFT", clear, "RIGHT", C.GAP_BTN or 4, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() TB.PollList(true) end)
    TB.refreshButton = refresh

    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("LEFT", refresh, "RIGHT", 6, 0)
    count:SetWidth(150)
    count:SetJustifyH("LEFT")
    TB.SetTextColor(count, color("muted"))
    TB.countLabel = count
end

local function createRosterColumnHeaders(parent)
    local left = 26
    local headers = {
        { text = "Name", width = C.ROSTER_NAME_W or 118 },
        { text = "Class", width = C.ROSTER_CLASS_W or 70 },
        { text = "Status", width = C.ROSTER_STATUS_W or 145 },
        { text = "Last location", width = 100 },
    }
    local x = left
    for _, header in ipairs(headers) do
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
        fs:SetWidth(header.width)
        fs:SetText(header.text)
        TB.SetTextColor(fs, color("muted"))
        x = x + header.width + (C.GAP_BTN or 4)
    end
end

CreateScroll = function(parent)
    createRosterColumnHeaders(parent)
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -20)
    scroll:SetWidth(W - (C.PAD or 10) * 2)
    scroll:SetHeight(ROW_N * ROW_H + 4)
    scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh) end)
    TB.scroll = scroll

    local rows = {}
    for i = 1, ROW_N do table.insert(rows, CreateRow(scroll, i)) end
    TB.rows = rows
end

CreateRow = function(scroll, index)
    local row = CreateFrame("Frame", nil, scroll)
    row:SetWidth(W - (C.PAD or 10) * 2 - 18)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(index - 1) * ROW_H)
    TB.ApplyBackdrop(row, 0.62, 0.52)
    row:EnableMouse(true)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
    row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetWidth(20); row.check:SetHeight(20)
    row.check:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.check:SetScript("OnClick", function()
        local entry = this:GetParent().entry
        if entry then TB.ToggleRosterSelection(entry.name, this:GetChecked()) end
    end)

    local nameWidth = C.ROSTER_NAME_W or 118
    local classWidth = C.ROSTER_CLASS_W or 70
    local statusWidth = C.ROSTER_STATUS_W or 145
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.name:SetWidth(nameWidth)
    row.name:SetJustifyH("LEFT")

    row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.class:SetPoint("LEFT", row.name, "RIGHT", C.GAP_BTN or 4, 0)
    row.class:SetWidth(classWidth)
    row.class:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.class, "RIGHT", C.GAP_BTN or 4, 0)
    row.status:SetWidth(statusWidth)
    row.status:SetJustifyH("LEFT")

    row.location = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.location:SetPoint("LEFT", row.status, "RIGHT", C.GAP_BTN or 4, 0)
    row.location:SetWidth(100)
    row.location:SetJustifyH("LEFT")
    TB.SetTextColor(row.location, color("muted"))

    row:SetScript("OnEnter", function()
        local entry = this.entry
        if not entry then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name)
        GameTooltip:AddLine(TB.StatusText(entry.st, entry.inGroup), 1, 1, 1)
        if entry.location then GameTooltip:AddLine("Last: " .. entry.location, COL.muted[1], COL.muted[2], COL.muted[3]) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function lifecycleCommand(action, verb)
    local names = TB.GetEligibleRosterNames and TB.GetEligibleRosterNames(action) or {}
    for _, name in ipairs(names) do
        TB.SendBotCommand(TB.BuildCommand(verb, name))
    end
    if table.getn(names) == 0 and TB.SetStatus then
        TB.SetStatus("No eligible selected bots.", "muted")
    end
end

CreateRosterBar = function(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(ROW_N * ROW_H + 29))
    bar:SetWidth(W - (C.PAD or 10) * 2)
    bar:SetHeight(34)

    local selection = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selection:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    selection:SetWidth(105)
    selection:SetJustifyH("LEFT")
    TB.selectionLabel = selection
    TB.SetTextColor(selection, color("muted"))

    local function button(label, width, action, verb, tip)
        local button = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        button:SetWidth(width); button:SetHeight(18)
        button:SetText(label)
        button:SetScript("OnClick", function() lifecycleCommand(action, verb) end)
        setButtonTooltip(button, tip)
        return button
    end

    local login = button("Login", 52, "login", "add", "Log in selected offline owned bots")
    login:SetPoint("LEFT", selection, "RIGHT", 4, 0)
    local logout = button("Logout", 58, "logout", "logout", "Log out selected online owned bots")
    logout:SetPoint("LEFT", login, "RIGHT", C.GAP_BTN or 4, 0)
    local invite = button("Invite", 52, "invite", "invite", "Invite selected online bots not in your group")
    invite:SetPoint("LEFT", logout, "RIGHT", C.GAP_BTN or 4, 0)
    local kick = button("Kick", 46, "kick", "uninvite", "Kick selected online bots from your group")
    kick:SetPoint("LEFT", invite, "RIGHT", C.GAP_BTN or 4, 0)
    local summon = button("Summon", 60, "summon", "summon", "Summon selected online bots")
    summon:SetPoint("LEFT", kick, "RIGHT", C.GAP_BTN or 4, 0)

    TB.lifecycleButtons = { login = login, logout = logout, invite = invite, kick = kick, summon = summon }
    TB.rosterBar = bar
    return bar
end

local function makeActionButton(parent, intent, width, x, y)
    local labels = C.ACTION_LABELS or {}
    local label = labels[intent] or intent
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width); button:SetHeight(24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)
    setButtonTooltip(button, ACTION_TOOLTIPS[intent] or "Send .bot action " .. intent)
    button:SetScript("OnClick", function()
        if intent == "aoe" then
            if TB.aoePending then return end
            local enabled = not TB.aoeEnabled
            TB.aoePending = true
            TB.SendActionIntent("aoe " .. (enabled and "on" or "off"))
        else
            TB.SendActionIntent(intent)
        end
    end)
    return button
end

local function addRaidIcon(button, iconIndex)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(14); icon:SetHeight(14)
    icon:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.raidIcon = icon
end

CreateActions = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetWidth(W - (C.PAD or 10) * 2)
    frame:SetHeight(300)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    title:SetText("Actions")
    TB.SetTextColor(title, color("gold"))

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    hint:SetWidth(W - (C.PAD or 10) * 2)
    hint:SetJustifyH("LEFT")
    TB.scopeHint = hint
    TB.SetTextColor(hint, color("muted"))

    local rowY1, rowY2 = -48, -78
    local buttons = {}
    buttons.attack = makeActionButton(frame, "attack", 70, 0, rowY1)
    buttons.stop = makeActionButton(frame, "stop", 62, 74, rowY1)
    buttons.pull = makeActionButton(frame, "pull", 62, 140, rowY1)
    buttons.pullback = makeActionButton(frame, "pullback", 76, 206, rowY1)
    buttons.come = makeActionButton(frame, "come", 62, 286, rowY1)
    buttons.stay = makeActionButton(frame, "stay", 62, 0, rowY2)
    buttons.follow = makeActionButton(frame, "follow", 66, 66, rowY2)
    buttons.focusSkull = makeActionButton(frame, "focus skull", 92, 136, rowY2)
    buttons.ccMoon = makeActionButton(frame, "cc moon", 82, 232, rowY2)
    addRaidIcon(buttons.focusSkull, 8)
    addRaidIcon(buttons.ccMoon, 5)
    buttons.aoe = makeActionButton(frame, "aoe", 78, 318, rowY2)
    buttons.aoe:SetText("AoE Off")

    TB.actionButtons = buttons
    TB.actions = buttons
    return frame
end

CreateStatusBar = function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", C.PAD or 10, 8)
    fs:SetWidth(W - (C.PAD or 10) * 2)
    fs:SetJustifyH("LEFT")
    TB.SetTextColor(fs, color("muted"))
    fs:SetText("Ready. Select Actions or Roster.")
    TB.statusText = fs
end

-- ── public ──────────────────────────────────────────────────────────────────
function TB.InitUI()
    if TB.uiReady then return end
    TB.uiReady = false
    TB.filterText = TB.filterText or ""
    TB.aoeEnabled = false

    local main = CreateFrame("Frame", "TortoiseBotsManagerFrame", UIParent)
    CreateHeader(main)
    if main.SetScale then
        local sh = (GetScreenHeight and GetScreenHeight()) or 768
        if sh < 700 then main:SetScale(0.82)
        elseif sh < 860 then main:SetScale(0.90)
        else main:SetScale(1) end
    end

    local tabBar = CreateFrame("Frame", nil, main)
    tabBar:SetPoint("TOPLEFT", main, "TOPLEFT", C.PAD or 10, -40)
    tabBar:SetWidth(W - (C.PAD or 10) * 2)
    tabBar:SetHeight(20)

    local function makeTab(label, offset)
        local button = CreateFrame("Button", nil, tabBar)
        button:SetWidth(82); button:SetHeight(20)
        button:SetPoint("LEFT", tabBar, "LEFT", offset, 0)
        button:EnableMouse(true); button:RegisterForClicks("LeftButtonUp")
        TB.ApplyBackdrop(button, 0.88, 0.9)
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", button, "CENTER", 0, 1)
        text:SetText(label)
        button.text = text
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(button)
        highlight:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.10)
        return button
    end

    local tabActions = makeTab("Actions", 0)
    local tabRoster = makeTab("Roster", 86)
    local content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    content:SetWidth(W - (C.PAD or 10) * 2)
    content:SetHeight(325)

    local actionsFrame = CreateActions(content)
    local rosterFrame = CreateFrame("Frame", nil, content)
    rosterFrame:SetWidth(W - (C.PAD or 10) * 2)
    rosterFrame:SetHeight(325)
    CreateFilterRow(rosterFrame)
    CreateScroll(rosterFrame)
    CreateRosterBar(rosterFrame)

    local function showTab(name)
        if name == "roster" then
            rosterFrame:Show(); actionsFrame:Hide()
            tabRoster.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabActions.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:Disable(); tabActions:Enable()
        else
            actionsFrame:Show(); rosterFrame:Hide()
            tabActions.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabRoster.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabActions:Disable(); tabRoster:Enable()
        end
        TortoiseBotsDB.activeTab = name
    end

    local initial = (TortoiseBotsDB and TortoiseBotsDB.activeTab) or "actions"
    if initial ~= "roster" then initial = "actions" end
    showTab(initial)
    tabActions:SetScript("OnClick", function() showTab("actions") end)
    tabRoster:SetScript("OnClick", function() showTab("roster") end)

    TB.ShowTab = showTab
    TB.tabActions, TB.tabRoster = tabActions, tabRoster
    TB.actionsFrame, TB.rosterFrame = actionsFrame, rosterFrame

    local targetWatcher = CreateFrame("Frame", "TortoiseBotsManagerTargetWatcher")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:SetScript("OnEvent", function() TB.Refresh() end)

    main:Hide()
    TB.frame = main
    TB.uiReady = true
    TB.Refresh()
end

function TB.SetStatus(msg, kind)
    if not TB.statusText then return end
    msg = msg or ""
    if string.len(msg) > 120 then msg = string.sub(msg, 1, 120) .. "…" end
    local c = color("muted")
    if kind == "ok" then c = color("green")
    elseif kind == "warn" then c = color("red")
    elseif kind == "pending" then c = color("yellow") end
    TB.statusText:SetText(msg)
    TB.SetTextColor(TB.statusText, c)
end

-- Raw command callers retain the old safety helper even though the advanced
-- command box is intentionally no longer part of the UI.
function TB.IsDangerousCommand(command)
    command = string.lower(TB.Trim(command or ""))
    local dangerous = {
        "destroy", "cheat", "debug", "cdebug", "set value", "give leader",
        "guild promote", "guild demote", "guild remove", "guild leader",
        "sendmail", "mail", "ah bid", "faction", "cast", "logout",
    }
    for _, prefix in ipairs(dangerous) do
        if command == prefix or string.find(command, "^" .. prefix .. "%s") then return true end
    end
    return false
end

RefreshCounts = function()
    local rows = TB.GetDisplayRows("")
    local online = 0
    for _, entry in ipairs(rows) do
        if entry.st and entry.st.serverState == "online" then online = online + 1 end
    end
    if TB.countLabel then
        TB.countLabel:SetText(string.format("%d owned · %d online", table.getn(rows), online))
    end
end

RefreshRows = function(rows)
    FauxScrollFrame_Update(TB.scroll, table.getn(rows), ROW_N, ROW_H)
    local offset = FauxScrollFrame_GetOffset(TB.scroll) or 0
    for i = 1, ROW_N do
        local row = TB.rows[i]
        if not row then break end
        local entry = rows[i + offset]
        row.entry = entry
        if entry then
            row:Show()
            row.name:SetText(entry.name or "")
            row.class:SetText(entry.className or tostring(entry.classId or "?"))
            row.status:SetText(TB.StatusText(entry.st, entry.inGroup))
            row.location:SetText(entry.location or "-")
            TB.SetTextColor(row.status, TB.StatusColor(entry.st))
            row.check:SetChecked(TB.IsRosterSelected(entry.name))
            if TB.IsRosterSelected(entry.name) then
                row:SetBackdropColor(0.12, 0.10, 0.04, 0.92)
                row.accent:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
            else
                row:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
                row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)
            end
        else
            row:Hide()
            row.entry = nil
        end
    end
end

RefreshRosterSelection = function()
    if TB.selectionLabel then
        local names = TB.GetSelectedRosterNames and TB.GetSelectedRosterNames() or {}
        TB.selectionLabel:SetText(table.getn(names) .. " selected")
        TB.SetTextColor(TB.selectionLabel, table.getn(names) > 0 and color("text") or color("muted"))
    end
    if TB.lifecycleButtons then
        local actions = { "login", "logout", "invite", "kick", "summon" }
        for _, action in ipairs(actions) do
            local button = TB.lifecycleButtons[action]
            local eligible = TB.GetEligibleRosterNames and TB.GetEligibleRosterNames(action) or {}
            local command = action
            if action == "login" then command = "add"
            elseif action == "kick" then command = "uninvite" end
            if serverSupports(command) and table.getn(eligible) > 0 then
                button:Enable()
            else
                button:Disable()
            end
        end
    end
end

function TB.RefreshActionControls()
    if not TB.actionButtons then return end
    local hasEnemyTarget = hasValidEnemyTarget()
    local targetOnly = { "attack", "pull", "pullback" }
    for _, key in ipairs(targetOnly) do
        if hasEnemyTarget then TB.actionButtons[key]:Enable() else TB.actionButtons[key]:Disable() end
    end
    if TB.aoePending then TB.actionButtons.aoe:Disable() else TB.actionButtons.aoe:Enable() end
    if TB.scopeHint then
        TB.scopeHint:SetText(TB.GetActionScopeHint())
        TB.SetTextColor(TB.scopeHint, color("muted"))
    end
end

function TB.Refresh()
    if not TB.uiReady or not TB.frame or not TB.scroll or not TB.rows then return end
    local rows = TB.GetDisplayRows(TB.filterText or "")
    RefreshCounts()
    RefreshRows(rows)
    RefreshRosterSelection()
    TB.RefreshActionControls()
end

function TB.Toggle()
    if not TB.uiReady or not TB.frame then return end
    if TB.frame:IsVisible() then
        TB.frame:Hide()
    else
        TB.frame:Show()
        TB.Refresh()
        TB.PollList(true)
    end
end
