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

-- Expose both pieces for small UI controls that need to explain where an
-- action will land. Gameplay still resolves the authoritative scope server-side.
function TB.GetTargetScope()
    return targetScope()
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
    attack   = "Order scoped bots to attack selected enemy target",
    stop     = "Stop combat and reset target (instant heals remain active)",
    pull     = "Tank uses the native pull action; it does not return to the pull position.",
    pullback = "Tank uses the native pull action and returns to the pull position.",
    follow   = "Scoped bots follow you in designated formation",
    stay     = "Scoped bots hold their current position",
    come     = "Scoped bots run to your position",
    hold     = "Order scoped bots to run directly to your position and stay there (corner pull)",
    ["focus skull"] = "Focus damage on target marked with Skull (RTI 8)",
    ["cc moon"]     = "Choose the raid icon this scoped bot should own for crowd control",
    aoe      = "Toggle area-of-effect spells on/off",
    ready    = "Perform ready check: bots report HP, mana, water, and status",
    interrupt = "Interrupt the selected enemy's active spell with the best ready bot",
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
    local search = CreateFrame("EditBox", "TortoiseBotsManagerSearch", parent, "InputBoxTemplate")
    search:SetWidth(180); search:SetHeight(20)
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search

    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetWidth(42); clear:SetHeight(18)
    clear:SetPoint("LEFT", search, "RIGHT", 4, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
        TB.filterText = ""
        TB.Refresh()
    end)

    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -2)
    count:SetWidth(200)
    count:SetJustifyH("RIGHT")
    TB.SetTextColor(count, color("muted"))
    TB.countLabel = count
end

local function createRosterColumnHeaders(parent)
    local checkAll = CreateFrame("CheckButton", "TortoiseBotsManagerCheckAll", parent, "UICheckButtonTemplate")
    checkAll:SetWidth(20); checkAll:SetHeight(20)
    checkAll:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -20)
    setButtonTooltip(checkAll, "Select or deselect all bots")
    checkAll:SetScript("OnClick", function()
        local isChecked = this:GetChecked() and true or false
        TB.SelectAllRoster(isChecked)
    end)
    TB.checkAll = checkAll

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
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -24)
        fs:SetWidth(header.width)
        fs:SetText(header.text)
        TB.SetTextColor(fs, color("muted"))
        x = x + header.width + (C.GAP_BTN or 4)
    end
end

CreateScroll = function(parent)
    createRosterColumnHeaders(parent)
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -42)
    scroll:SetWidth(W - (C.PAD or 10) * 2)
    scroll:SetHeight(ROW_N * ROW_H + 4)
    scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh) end)
    TB.scroll = scroll

    local rows = {}
    for i = 1, ROW_N do table.insert(rows, CreateRow(parent, scroll, i)) end
    TB.rows = rows
end

CreateRow = function(parent, scroll, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(W - (C.PAD or 10) * 2 - 18)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(index - 1) * ROW_H)
    TB.ApplyBackdrop(row, 0.62, 0.45)
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
        if entry then TB.ToggleRosterSelection(entry.name, this:GetChecked() and true or false) end
    end)

    local nameWidth = C.ROSTER_NAME_W or 118
    local classWidth = C.ROSTER_CLASS_W or 70
    local statusWidth = C.ROSTER_STATUS_W or 145
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
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

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.08)

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
    if table.getn(names) > 0 and action == "invite" and TB.QueueRosterBatch then
        TB.QueueRosterBatch(verb, names)
    else
        for _, name in ipairs(names) do
            TB.SendBotCommand(TB.BuildCommand(verb, name))
        end
    end
    if table.getn(names) == 0 and TB.SetStatus then
        TB.SetStatus("No eligible selected bots.", "muted")
    end
end

CreateRosterBar = function(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(42 + ROW_N * ROW_H + 4))
    bar:SetWidth(W - (C.PAD or 10) * 2)
    bar:SetHeight(34)

    local selection = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selection:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 8)
    selection:SetWidth(95)
    selection:SetJustifyH("LEFT")
    TB.selectionLabel = selection
    TB.SetTextColor(selection, color("muted"))

    local function button(label, width, action, verb, tip)
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetWidth(width); btn:SetHeight(22)
        btn:SetText(label)
        btn:SetScript("OnClick", function() lifecycleCommand(action, verb) end)
        setButtonTooltip(btn, tip)
        return btn
    end

    local login  = button("Login", 56, "login", "add", "Log in selected offline owned bots")
    login:SetPoint("LEFT", selection, "RIGHT", 4, 0)
    local logout = button("Logout", 62, "logout", "logout", "Log out selected online owned bots")
    logout:SetPoint("LEFT", login, "RIGHT", C.GAP_BTN or 4, 0)
    local invite = button("Invite", 56, "invite", "invite", "Invite selected online bots not in your group")
    invite:SetPoint("LEFT", logout, "RIGHT", C.GAP_BTN or 4, 0)
    local kick   = button("Kick", 50, "kick", "uninvite", "Kick selected online bots from your group")
    kick:SetPoint("LEFT", invite, "RIGHT", C.GAP_BTN or 4, 0)
    local summon = button("Summon", 66, "summon", "summon", "Summon selected online bots")
    summon:SetPoint("LEFT", kick, "RIGHT", C.GAP_BTN or 4, 0)

    TB.lifecycleButtons = { login = login, logout = logout, invite = invite, kick = kick, summon = summon }
    TB.rosterBar = bar
    return bar
end

local function makeActionButton(parent, intent, width, x, y)
    local labels = C.ACTION_LABELS or {}
    local label = labels[intent] or intent
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width); button:SetHeight(26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(label)

    local icons = (C and C.ACTION_ICONS) or {}
    if icons[intent] then
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetWidth(16); icon:SetHeight(16)
        icon:SetPoint("LEFT", button, "LEFT", 5, 0)
        icon:SetTexture(icons[intent])
        if intent ~= "focus skull" and intent ~= "cc moon" then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        button.icon = icon
    end

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
    if button and not button.raidIcon then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(16); icon:SetHeight(16)
        icon:SetPoint("LEFT", button, "LEFT", 5, 0)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.raidIcon = icon
    end
end

CreateActions = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetWidth(W - (C.PAD or 10) * 2)
    frame:SetHeight(350)

    -- Scope Banner Card
    local scopeCard = CreateFrame("Frame", nil, frame)
    scopeCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    scopeCard:SetWidth(W - (C.PAD or 10) * 2)
    scopeCard:SetHeight(36)
    TB.ApplyBackdrop(scopeCard, 0.65, 0.50)

    local scopeIcon = scopeCard:CreateTexture(nil, "ARTWORK")
    scopeIcon:SetWidth(20); scopeIcon:SetHeight(20)
    scopeIcon:SetPoint("LEFT", scopeCard, "LEFT", 8, 0)
    scopeIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    scopeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    TB.scopeIcon = scopeIcon

    local scopeTitle = scopeCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scopeTitle:SetPoint("TOPLEFT", scopeIcon, "TOPRIGHT", 8, 2)
    scopeTitle:SetText("TARGET / COMMAND SCOPE")
    TB.SetTextColor(scopeTitle, color("gold"))

    local hint = scopeCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", scopeIcon, "BOTTOMRIGHT", 8, -1)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    TB.scopeHint = hint
    TB.SetTextColor(hint, color("muted"))

    local function makeSection(titleText, yOffset, cardHeight)
        local card = CreateFrame("Frame", nil, frame)
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        card:SetWidth(W - (C.PAD or 10) * 2)
        card:SetHeight(cardHeight)
        TB.ApplyBackdrop(card, 0.45, 0.35)

        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        title:SetText(titleText)
        TB.SetTextColor(title, color("gold"))

        local line = card:CreateTexture(nil, "ARTWORK")
        line:SetTexture(0.48, 0.36, 0.15, 0.30)
        line:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -19)
        line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -19)
        line:SetHeight(1)
        return card
    end

    local cardCombat = makeSection("COMBAT & ENGAGEMENT", -40, 88)
    local cardTactics= makeSection("TACTICS & UTILITY", -132, 58)
    local cardMove   = makeSection("FORMATION & MOVEMENT", -194, 88)

    local btnY = -24
    local buttons = {}

    -- The CC button opens a compact mark picker instead of forcing Moon as the
    -- only choice.  Targeting an owned bot first makes the assignment explicit;
    -- with a normal enemy target the server still chooses a capable executor.
    local ccMenu = CreateFrame("Frame", "TortoiseBotsManagerCcMenu", frame)
    ccMenu:SetWidth(246)
    ccMenu:SetHeight(154)
    ccMenu:SetFrameStrata("DIALOG")
    ccMenu:EnableMouse(true)
    TB.ApplyBackdrop(ccMenu, 0.98, 1.0)

    local ccTitle = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ccTitle:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -6)
    ccTitle:SetText("Assign CC mark")
    TB.SetTextColor(ccTitle, color("gold"))

    local ccHint = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccHint:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -22)
    ccHint:SetWidth(230)
    ccHint:SetJustifyH("LEFT")
    TB.SetTextColor(ccHint, color("muted"))
    ccMenu.hint = ccHint

    local ccButtons = {}
    for i, mark in ipairs(C.CC_MARKS or {}) do
        local markButton = CreateFrame("Button", nil, ccMenu, "UIPanelButtonTemplate")
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        markButton:SetWidth(114)
        markButton:SetHeight(25)
        markButton:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 7 + column * 119, -44 - row * 27)
        markButton:SetText(mark.label)
        local markIcon = markButton:CreateTexture(nil, "OVERLAY")
        markIcon:SetWidth(16); markIcon:SetHeight(16)
        markIcon:SetPoint("LEFT", markButton, "LEFT", 5, 0)
        markIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark.icon)
        markIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        markButton.mark = mark.id
        markButton.icon = markIcon
        markButton:SetScript("OnClick", function()
            TB.SendActionIntent("cc " .. mark.id)
            ccMenu:Hide()
        end)
        setButtonTooltip(markButton, "Assign " .. mark.label .. " to the scoped CC bot")
        ccButtons[mark.id] = markButton
    end
    ccMenu.buttons = ccButtons
    ccMenu:Hide()

    ccMenu.Update = function()
        local scope, botName = targetScope()
        if scope == "bot" and botName then
            local current = TB.GetCcAssignment and TB.GetCcAssignment(botName) or nil
            local label = current and C.CC_MARK_LABELS and C.CC_MARK_LABELS[current]
            ccHint:SetText("Bot: " .. botName .. (label and (" · current " .. label) or " · choose an icon"))
        else
            ccHint:SetText("Party: automatic CC. Target a bot first to assign it.")
        end
    end

    TB.ToggleCcMenu = function()
        if ccMenu:IsVisible() then
            ccMenu:Hide()
        else
            ccMenu:Show()
            ccMenu:ClearAllPoints()
            ccMenu:SetPoint("TOPLEFT", buttons.ccMoon, "BOTTOMLEFT", 0, -4)
            ccMenu:Update()
        end
    end
    TB.ccMenu = ccMenu

    buttons.attack   = makeActionButton(cardCombat, "attack", 108, 8, btnY)
    buttons.stop     = makeActionButton(cardCombat, "stop", 108, 122, btnY)
    buttons.pull     = makeActionButton(cardCombat, "pull", 108, 236, btnY)
    buttons.pullback = makeActionButton(cardCombat, "pullback", 118, 350, btnY)
    buttons.interrupt = makeActionButton(cardCombat, "interrupt", 118, 8, -54)

    buttons.focusSkull = makeActionButton(cardTactics, "focus skull", 108, 8, btnY)
    buttons.ccMoon     = makeActionButton(cardTactics, "cc moon", 108, 122, btnY)
    buttons.ccMoon:SetText("CC Mark")
    buttons.ccMoon:SetScript("OnClick", function() TB.ToggleCcMenu() end)
    buttons.ccMark     = buttons.ccMoon
    addRaidIcon(buttons.focusSkull, 8)
    addRaidIcon(buttons.ccMoon, 5)
    buttons.aoe        = makeActionButton(cardTactics, "aoe", 108, 236, btnY)
    buttons.aoe:SetText("AoE Off")
    buttons.ready      = makeActionButton(cardTactics, "ready", 118, 350, btnY)

    buttons.follow   = makeActionButton(cardMove, "follow", 148, 8, btnY)
    buttons.stay     = makeActionButton(cardMove, "stay", 148, 164, btnY)
    buttons.come     = makeActionButton(cardMove, "come", 148, 320, btnY)
    buttons.hold     = buttons.come

    -- Formation pills
    local formLabel = cardMove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    formLabel:SetPoint("TOPLEFT", cardMove, "TOPLEFT", 8, -58)
    formLabel:SetText("Formation:")
    TB.SetTextColor(formLabel, color("muted"))

    local pills = {}
    local function makeFormationPill(id, label, width, x, y, tip)
        local btn = CreateFrame("Button", nil, cardMove, "UIPanelButtonTemplate")
        btn:SetWidth(width); btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", cardMove, "TOPLEFT", x, y)
        btn:SetText(label)
        setButtonTooltip(btn, tip or ("Set formation to " .. label))
        btn:SetScript("OnClick", function()
            TB.SetFormation(id)
        end)
        pills[id] = btn
        return btn
    end

    makeFormationPill("shield", "Shield", 70, 72, -56, "Dungeon standard: tank front, melee flank, healer rear")
    makeFormationPill("near",   "Near",   64, 146, -56, "Tight stack within 4y for narrow corridors & patrols")
    makeFormationPill("queue",  "Queue",  64, 214, -56, "Single file column behind master")
    makeFormationPill("arrow",  "Arrow",  64, 282, -56, "V-wedge pointing forward for open terrain")
    makeFormationPill("circle", "Circle", 64, 350, -56, "360-degree defensive perimeter")

    TB.formationPills = pills
    TB.UpdateFormationPills = function()
        local active = TB.currentFormation or "shield"
        for id, btn in pairs(pills) do
            if id == active then
                btn:Disable()
            else
                btn:Enable()
            end
        end
    end
    TB.UpdateFormationPills()

    local guide = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    guide:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -290)
    guide:SetWidth(464)
    guide:SetJustifyH("LEFT")
    guide:SetText("|cff626056Tip: target a bot in Party, then use CC Mark to assign its raid icon; target an enemy for Attack/Pull/Interrupt. Click a Formation for spacing.|r")

    TB.actionButtons = buttons
    TB.actions = buttons
    return frame
end

CreateStatusBar = function(parent)
    local dot = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", C.PAD or 10, 8)
    dot:SetText("|cff4ecb5a●|r")
    TB.statusDot = dot

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    fs:SetWidth(W - (C.PAD or 10) * 2 - 20)
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
    local tabParty = makeTab("Party", 86)
    local tabRoster = makeTab("Roster", 172)
    local tabLog = makeTab("Log", 258)
    local content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    content:SetWidth(W - (C.PAD or 10) * 2)
    content:SetHeight(350)

    local actionsFrame = CreateActions(content)
    local rosterFrame = CreateFrame("Frame", nil, content)
    rosterFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    rosterFrame:SetWidth(W - (C.PAD or 10) * 2)
    rosterFrame:SetHeight(325)
    CreateFilterRow(rosterFrame)
    CreateScroll(rosterFrame)
    CreateRosterBar(rosterFrame)

    local function CreatePartyView(parent)
        local partyFrame = CreateFrame("Frame", nil, parent)
        partyFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        partyFrame:SetWidth(W - (C.PAD or 10) * 2)
        partyFrame:SetHeight(325)

        local title = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", partyFrame, "TOPLEFT", 6, 0)
        title:SetText("|cffd8a657Active Party Roles|r")

        local subtitle = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
        subtitle:SetText("|cff888888(role buttons · CC icon = mark · click bot row to target)|r")

        local emptyMsg = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyMsg:SetPoint("CENTER", partyFrame, "CENTER", 0, -20)
        emptyMsg:SetWidth(380)
        emptyMsg:SetJustifyH("CENTER")
        emptyMsg:SetText("|cff888888No other party members.\nInvite your bots from the Roster tab to manage party roles.|r")
        partyFrame.emptyMsg = emptyMsg

        local rows = {}
        for i = 1, 5 do
            local row = CreateFrame("Frame", nil, partyFrame)
            row:SetWidth(W - (C.PAD or 10) * 2)
            row:SetHeight(52)
            row:SetPoint("TOPLEFT", partyFrame, "TOPLEFT", 0, -(i - 1) * 56 - 22)
            row:EnableMouse(true)
            TB.ApplyBackdrop(row, 0.62, 0.45)

            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetWidth(3)
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
            row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
            nameText:SetWidth(130)
            nameText:SetJustifyH("LEFT")
            row.nameText = nameText

            local descText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            descText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 8)
            descText:SetWidth(130)
            descText:SetJustifyH("LEFT")
            TB.SetTextColor(descText, color("muted"))
            row.descText = descText

            local ccIcon = row:CreateTexture(nil, "ARTWORK")
            ccIcon:SetWidth(18); ccIcon:SetHeight(18)
            ccIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
            ccIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            ccIcon:Hide()
            row.ccIcon = ccIcon

            local ccLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ccLabel:SetPoint("RIGHT", ccIcon, "LEFT", -4, 0)
            ccLabel:SetText("CC")
            TB.SetTextColor(ccLabel, color("muted"))
            row.ccLabel = ccLabel

            local playerLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            playerLabel:SetPoint("LEFT", row, "LEFT", 150, 0)
            playerLabel:SetText("|cffd8a657[ Player / Master ]|r")
            row.playerLabel = playerLabel

            local roleButtons = {}
            for b = 1, 4 do
                local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                btn:SetWidth(78)
                btn:SetHeight(22)
                btn:SetPoint("LEFT", row, "LEFT", 150 + (b - 1) * 82, 0)
                roleButtons[b] = btn
            end
            row.roleButtons = roleButtons

            row:SetScript("OnMouseUp", function()
                if arg1 and arg1 ~= "LeftButton" then return end
                if not row.partyUnit or row.partyUnit == "player" then return end
                if TargetUnit then
                    TargetUnit(row.partyUnit)
                elseif TargetByName and row.partyName then
                    TargetByName(row.partyName, true)
                end
                if TB.Refresh then TB.Refresh() end
            end)
            row:SetScript("OnEnter", function()
                if not row.partyName then return end
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:SetText(row.partyName)
                local mark = row.ccMark and C.CC_MARK_LABELS and C.CC_MARK_LABELS[row.ccMark]
                if mark then
                    GameTooltip:AddLine("CC mark: " .. mark, 0.9, 0.9, 0.9, 1)
                elseif row.partyUnit ~= "player" then
                    GameTooltip:AddLine("CC mark: not reported", COL.muted[1], COL.muted[2], COL.muted[3])
                end
                if row.partyUnit ~= "player" then
                    GameTooltip:AddLine("Click row to target this bot for CC assignment.", COL.muted[1], COL.muted[2], COL.muted[3])
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            table.insert(rows, row)
        end
        partyFrame.rows = rows
        return partyFrame
    end

    local partyFrame = CreatePartyView(content)

    local function CreateLogView(parent)
        local logFrame = CreateFrame("Frame", nil, parent)
        logFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        logFrame:SetWidth(W - (C.PAD or 10) * 2)
        logFrame:SetHeight(325)

        local title = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 6, 0)
        title:SetText("|cffd8a657Bot activity log|r")

        local clearBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
        clearBtn:SetWidth(65); clearBtn:SetHeight(18)
        clearBtn:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", -24, 2)
        clearBtn:SetText("Clear")
        setButtonTooltip(clearBtn, "Clear recorded activity history")
        clearBtn:SetScript("OnClick", function()
            if TB.ClearLogHistory then TB.ClearLogHistory() end
            if TB.RefreshLogView then TB.RefreshLogView() end
        end)


        local LOG_ROW_H = 18
        local LOG_ROW_N = 14
        local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerLogScroll", logFrame, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 0, -22)
        scroll:SetWidth(W - (C.PAD or 10) * 2)
        scroll:SetHeight(LOG_ROW_N * LOG_ROW_H + 4)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(LOG_ROW_H, TB.RefreshLogView)
        end)
        TB.logScroll = scroll

        local rows = {}
        for i = 1, LOG_ROW_N do
            local row = CreateFrame("Frame", nil, logFrame)
            row:SetWidth(W - (C.PAD or 10) * 2 - 20)
            row:SetHeight(LOG_ROW_H)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * LOG_ROW_H)

            local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeText:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
            timeText:SetWidth(60)
            timeText:SetJustifyH("LEFT")
            TB.SetTextColor(timeText, color("muted"))
            row.timeText = timeText

            local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tagText:SetPoint("LEFT", timeText, "RIGHT", 2, 0)
            tagText:SetWidth(38)
            tagText:SetJustifyH("LEFT")
            tagText:SetText("|cffd8a657[Bot]|r")
            row.tagText = tagText

            local msgText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            msgText:SetPoint("LEFT", tagText, "RIGHT", 4, 0)
            msgText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            msgText:SetJustifyH("LEFT")
            row.msgText = msgText

            table.insert(rows, row)
        end
        TB.logRows = rows
        return logFrame
    end

    local logFrame = CreateLogView(content)

    function TB.RefreshLogView()
        if not TB.logScroll or not TB.logRows then return end
        local history = TB.GetLogHistory and TB.GetLogHistory() or {}
        local total = table.getn(history)
        local LOG_ROW_H = 18
        local LOG_ROW_N = 14
        FauxScrollFrame_Update(TB.logScroll, total, LOG_ROW_N, LOG_ROW_H)
        local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(TB.logScroll)) or 0
        for i = 1, LOG_ROW_N do
            local row = TB.logRows[i]
            local idx = total - (offset + i - 1)
            if idx >= 1 and idx <= total then
                local item = history[idx]
                row.timeText:SetText(item.time or "")
                row.msgText:SetText(item.msg or "")
                row:Show()
            else
                row:Hide()
            end
        end
    end

    function TB.RefreshPartyView()
        if not TB.partyFrame or not TB.partyFrame.rows then return end
        local partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        local units = { "player" }
        for i = 1, partyCount do
            table.insert(units, "party" .. i)
        end

        local dbRoles = (TortoiseBotsDB and TortoiseBotsDB.botRoles) or {}

        for i = 1, 5 do
            local row = TB.partyFrame.rows[i]
            local unit = units[i]
            if unit and (unit == "player" or (UnitExists and UnitExists(unit))) then
                local name = (UnitName and UnitName(unit)) or (unit == "player" and "Player" or ("Party " .. i))
                row.partyUnit = unit
                row.partyName = name
                local level = (UnitLevel and UnitLevel(unit)) or 0
                local lvlText = (level and level > 0 and ("Lvl " .. level)) or "Lvl ??"
                local className, classFileName = (UnitClass and UnitClass(unit)) or "Unknown", "UNKNOWN"
                local classId = (classFileName and TB.C.CLASS_NAME_TO_ID and TB.C.CLASS_NAME_TO_ID[classFileName])
                    or (className and TB.C.CLASS_NAME_TO_ID and TB.C.CLASS_NAME_TO_ID[className])
                    or 1
                local col = (TB.C.CLASS_COLORS and TB.C.CLASS_COLORS[classId]) or COL.gold

                row.nameText:SetText(name)
                row.nameText:SetTextColor(col[1], col[2], col[3])
                row.descText:SetText(lvlText .. " " .. (className or ""))
                row.accent:SetTexture(col[1], col[2], col[3], 0.95)

                local ccMark = unit ~= "player" and TB.GetCcAssignment and TB.GetCcAssignment(name) or nil
                row.ccMark = ccMark
                local ccIconId = ccMark and C.CC_MARK_ICONS and C.CC_MARK_ICONS[ccMark]
                if ccIconId then
                    row.ccIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. ccIconId)
                    row.ccIcon:Show()
                else
                    row.ccIcon:Hide()
                end

                if unit == "player" then
                    row.playerLabel:Show()
                    for b = 1, 4 do row.roleButtons[b]:Hide() end
                else
                    row.playerLabel:Hide()
                    local roles = (TB.C.CLASS_ROLES and TB.C.CLASS_ROLES[classId]) or {}
                    local currentRole = dbRoles[name] or (roles[1] and roles[1].id)

                    for b = 1, 4 do
                        local btn = row.roleButtons[b]
                        local role = roles[b]
                        if role then
                            local isSelected = (currentRole == role.id)
                            if isSelected then
                                btn:SetText("|cffffd200" .. role.label .. "|r")
                            else
                                btn:SetText("|cffa0a0a0" .. role.label .. "|r")
                            end

                            local capturedRole = role
                            local capturedName = name
                            btn:SetScript("OnClick", function()
                                TortoiseBotsDB.botRoles = TortoiseBotsDB.botRoles or {}
                                TortoiseBotsDB.botRoles[capturedName] = capturedRole.id
                                if capturedRole.strat and capturedRole.strat ~= "" then
                                    TB.SendBotCommand("command " .. capturedName .. " " .. capturedRole.strat)
                                end
                                TB.Print(capturedName .. " role set to " .. capturedRole.label)
                                TB.RefreshPartyView()
                            end)

                            setButtonTooltip(btn, "Set " .. capturedName .. " role to " .. capturedRole.label .. (capturedRole.strat ~= "" and (" (" .. capturedRole.strat .. ")") or ""))
                            btn:Show()
                        else
                            btn:Hide()
                        end
                    end
                end
                row:Show()
            else
                row:Hide()
                row.partyUnit = nil
                row.partyName = nil
                row.ccMark = nil
                row.ccIcon:Hide()
            end
        end

        if partyCount == 0 then
            TB.partyFrame.emptyMsg:Show()
        else
            TB.partyFrame.emptyMsg:Hide()
        end
    end

    local function showTab(name)
        if name == "roster" then
            rosterFrame:Show(); actionsFrame:Hide(); partyFrame:Hide(); logFrame:Hide()
            tabRoster.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabActions.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabParty.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabLog.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabLog:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:Disable(); tabActions:Enable(); tabParty:Enable(); tabLog:Enable()
            TB.Refresh()
            if not TB.HasRosterSnapshot or not TB.HasRosterSnapshot() then
                TB.PollList(true)
            end
        elseif name == "party" then
            partyFrame:Show(); actionsFrame:Hide(); rosterFrame:Hide(); logFrame:Hide()
            tabParty.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabActions.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabLog.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabLog:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabParty:Disable(); tabActions:Enable(); tabRoster:Enable(); tabLog:Enable()
            if TB.RefreshPartyView then TB.RefreshPartyView() end
        elseif name == "log" then
            logFrame:Show(); actionsFrame:Hide(); rosterFrame:Hide(); partyFrame:Hide()
            tabLog.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabActions.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabParty.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabLog:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabLog:Disable(); tabActions:Enable(); tabParty:Enable(); tabRoster:Enable()
            if TB.RefreshLogView then TB.RefreshLogView() end
        else
            actionsFrame:Show(); partyFrame:Hide(); rosterFrame:Hide(); logFrame:Hide()
            tabActions.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabParty.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabLog.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabActions:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabLog:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabActions:Disable(); tabParty:Enable(); tabRoster:Enable(); tabLog:Enable()
            TB.Refresh()
        end
        TortoiseBotsDB.activeTab = name
    end

    local initial = (TortoiseBotsDB and TortoiseBotsDB.activeTab) or "actions"
    if initial ~= "roster" and initial ~= "party" and initial ~= "log" then initial = "actions" end
    showTab(initial)
    tabActions:SetScript("OnClick", function() showTab("actions") end)
    tabParty:SetScript("OnClick", function() showTab("party") end)
    tabRoster:SetScript("OnClick", function() showTab("roster") end)
    tabLog:SetScript("OnClick", function() showTab("log") end)

    TB.ShowTab = showTab
    TB.tabActions, TB.tabParty, TB.tabRoster, TB.tabLog = tabActions, tabParty, tabRoster, tabLog
    TB.actionsFrame, TB.partyFrame, TB.rosterFrame, TB.logFrame = actionsFrame, partyFrame, rosterFrame, logFrame

    local targetWatcher = CreateFrame("Frame", "TortoiseBotsManagerTargetWatcher")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
    targetWatcher:SetScript("OnEvent", function()
        if TB.ccMenu and TB.ccMenu:IsVisible() then TB.ccMenu:Hide() end
        TB.Refresh()
    end)

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
    local dot = "|cff757575●|r"
    if kind == "ok" then
        c = color("green")
        dot = "|cff4ecb5a●|r"
    elseif kind == "warn" then
        c = color("red")
        dot = "|cffff5555●|r"
    elseif kind == "pending" then
        c = color("yellow")
        dot = "|cffffb300●|r"
    end
    if TB.statusDot then TB.statusDot:SetText(dot) end
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
    local allState = (TB.GetAllState and TB.GetAllState()) or {}
    local total = 0
    local online = 0
    for name, st in pairs(allState) do
        if st.source == "snapshot" then
            total = total + 1
            if st.serverState == "online" or st.online then online = online + 1 end
        end
    end
    if total == 0 then
        local rows = TB.GetDisplayRows("")
        total = table.getn(rows)
        for _, entry in ipairs(rows) do
            if entry.st and (entry.st.serverState == "online" or entry.st.online) then
                online = online + 1
            end
        end
    end
    if TB.countLabel then
        TB.countLabel:SetText(string.format("%d owned · %d online", total, online))
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
            local classCol = TB.GetClassColor and TB.GetClassColor(entry.classId)
            row.name:SetText(entry.name or "")
            if entry.st and entry.st.online and classCol then
                TB.SetTextColor(row.name, classCol)
            else
                TB.SetTextColor(row.name, color("muted"))
            end
            row.class:SetText(entry.className or tostring(entry.classId or "?"))
            if classCol then
                TB.SetTextColor(row.class, classCol)
            end
            if TB.StatusBadge then
                row.status:SetText(TB.StatusBadge(entry.st, entry.inGroup))
            else
                row.status:SetText(TB.StatusText(entry.st, entry.inGroup))
                TB.SetTextColor(row.status, TB.StatusColor(entry.st))
            end
            row.location:SetText(entry.location or "-")
            row.check:SetChecked(TB.IsRosterSelected(entry.name))
            if TB.IsRosterSelected(entry.name) then
                row:SetBackdropColor(0.18, 0.14, 0.05, 0.95)
                row:SetBackdropBorderColor(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 0.9)
                row.accent:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
            else
                row:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.65)
                row:SetBackdropBorderColor(0.48, 0.36, 0.15, 0.40)
                if classCol and entry.st and entry.st.online then
                    row.accent:SetTexture(classCol[1], classCol[2], classCol[3], 0.95)
                else
                    row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.60)
                end
            end
        else
            row:Hide()
            row.entry = nil
        end
    end
end

RefreshRosterSelection = function()
    if TB.checkAll then
        local rows = (TB.GetDisplayRows and TB.GetDisplayRows(TB.filterText or "")) or {}
        local count = table.getn(rows)
        local allSelected = count > 0
        if count == 0 then
            allSelected = false
        else
            for _, r in ipairs(rows) do
                if not TB.IsRosterSelected(r.name) then
                    allSelected = false
                    break
                end
            end
        end
        TB.checkAll:SetChecked(allSelected)
    end
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
            local busy = TB.IsRosterBatchActive and TB.IsRosterBatchActive(command)
            if not busy and serverSupports(command) and table.getn(eligible) > 0 then
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
    local targetOnly = { "attack", "pull", "pullback", "interrupt" }
    for _, key in ipairs(targetOnly) do
        if hasEnemyTarget then TB.actionButtons[key]:Enable() else TB.actionButtons[key]:Disable() end
    end
    if TB.aoePending then TB.actionButtons.aoe:Disable() else TB.actionButtons.aoe:Enable() end
    if TB.UpdateFormationPills then TB.UpdateFormationPills() end

    local scope, botName = targetScope()
    if TB.scopeIcon then
        if scope == "party" then
            TB.scopeIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
        else
            TB.scopeIcon:SetTexture("Interface\\Icons\\INV_Misc_Head_Human_01")
        end
    end
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
    if TB.partyFrame and TB.partyFrame:IsVisible() and TB.RefreshPartyView then
        TB.RefreshPartyView()
    end
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
