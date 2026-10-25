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
    -- Hired companions are not roster rows, but the server reports them.
    if name and TB.GetBotState and TB.GetBotState(name) then return false end
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
        if TB.GetBotState and TB.GetBotState(name) then
            return "bot:" .. name, name
        end
    end
    return "party", nil
end

function TB.HasEnemyTarget()
    return hasValidEnemyTarget()
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

-- Newer server features are advertised in the roster's TBM:CAPS trailer.
local function serverHasCap(name)
    return TB.HasServerCapability and TB.HasServerCapability(name) or false
end

local function serverSupports(command)
    if not TB.ServerCapabilitiesKnown or not TB.ServerCapabilitiesKnown() then return true end
    return TB.HasServerCommand and TB.HasServerCommand(command) or false
end

local ACTION_TOOLTIPS = {
    attack   = "Bots attack your target. Healers keep healing. Needs an enemy target.",
    stop     = "Bots stop fighting and drop their target (heals still run).",
    pull     = "The tank pulls your target and fights it where it stands. The others wait for the timer below, then join.",
    follow   = "Bots follow you in the chosen formation.",
    stay     = "Bots hold their current position.",
    come     = "Bots run to where you stand and stay there (good for corner pulls).",
    hold     = "Bots run to where you stand and stay there (good for corner pulls).",
    guard    = "Bots plant themselves where they stand and fight anything close.",
    free     = "Bots leave their guard posts and move freely again.",
    ["stance near"]     = "Default scrum: melee crowds close around the target.",
    ["stance tank"]     = "Tank goes toe-to-toe, turning the target away from the party.",
    ["stance turnback"] = "Melee holds the far side of the target, away from your casters.",
    ["stance behind"]   = "Melee works the target's rear, clear of frontal cleaves.",
    ["focus skull"] = "Marks your target with Skull (or uses the existing Skull) and every DPS bot focuses it.",
    ["cc moon"]     = "Opens the Marks panel: give each raid icon to one bot, which keeps that mob crowd-controlled.",
    aoe      = "Area-of-effect spells for DPS bots.",
    ready    = "Ready check: bots report health, mana and drinks.",
    interrupt = "The best bot with a ready interrupt stops your target's cast.",
    flee     = "Get out: bots stop fighting and run after you without attacking. Attack, Pull, Follow or Stay brings them back.",
    ["strategy ~kite"]     = "Bots keep their distance from enemies while fighting.",
    ["strategy ~mark rti"] = "Bots mark the next target with Skull on their own when the fight starts.",
    ["strategy ~focus"]    = "Every DPS bot burns down one target instead of spreading damage.",
    ["strategy ~aoe fear"] = "Bots may use fear effects against groups. Held back inside instances.",
    sell     = "Bots sell their grey junk to a vendor near you.",
    learn    = "Target a class trainer first: bots of that class learn every spell they can pay for (with their own gold).",
    release  = "Dead bots release their spirit; once they are ghosts this button turns into Corpse run.",
}

function TB.ActionTooltip(intent)
    return ACTION_TOOLTIPS[intent]
end

-- Title line (the button label) plus a wrapped description.
local function setButtonTooltip(button, text, title)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if title then
            GameTooltip:SetText(title)
            GameTooltip:AddLine(text, 0.9, 0.9, 0.9, 1)
        else
            GameTooltip:SetText(text)
        end
        if this.tooltipExtra then
            local extra = this.tooltipExtra()
            if extra then GameTooltip:AddLine(extra, COL.muted[1], COL.muted[2], COL.muted[3], 1) end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

-- ── Component kit and layout grid ──────────────────────────────────────────
TB.UI = TB.UI or {}

TB.UI.Grid = {
    CONTENT_W     = W - (C.PAD or 10) * 2,
    PAD           = C.PAD or 10,
    GAP_BTN       = C.GAP_BTN or 4,
    BTN_H         = 26,
    BTN_H_SM      = 22,
    ROW_H         = ROW_H,
    CARD_ENGAGE_H = 56,
    CARD_PULL_H   = 76,
    CARD_MOVE_H   = 76,
    CARD_SWITCH_H = 54,
    CARD_TACTIC_H = 46,
    CARD_REST_H   = 88,
    CARD_FORM_H   = 76,
}

TB.UI.SetTooltip  = setButtonTooltip
TB.UI.AddRaidIcon = addRaidIcon

function TB.UI.CreateCard(parent, titleText, width, height, opts)
    opts = opts or {}
    width = width or TB.UI.Grid.CONTENT_W
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    card:SetWidth(width)
    card:SetHeight(height or 58)
    TB.ApplyBackdrop(card, opts.bgAlpha or 0.45, opts.edgeAlpha or 0.35)

    if titleText then
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        title:SetText(titleText)
        TB.SetTextColor(title, opts.titleColor or color("gold"))
        card.title = title
    end

    if opts.line then
        local line = card:CreateTexture(nil, "ARTWORK")
        line:SetTexture(0.48, 0.36, 0.15, 0.30)
        line:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -19)
        line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -19)
        line:SetHeight(1)
        card.line = line
    end

    return card
end

function TB.UI.CreateButton(parent, label, width, height, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent, opts.template or "UIPanelButtonTemplate")
    button:SetWidth(width or 110)
    button:SetHeight(height or 26)
    if opts.x or opts.y or opts.point or opts.relTo then
        button:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    if label then
        button:SetText(label)
    end

    if opts.icon then
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetWidth(16); icon:SetHeight(16)
        icon:SetPoint("LEFT", button, "LEFT", 5, 0)
        icon:SetTexture(opts.icon)
        if opts.texCoord then
            icon:SetTexCoord(opts.texCoord[1], opts.texCoord[2], opts.texCoord[3], opts.texCoord[4])
        elseif opts.intent ~= "focus skull" and opts.intent ~= "cc moon" then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        button.icon = icon
    end

    if opts.raidIcon then
        addRaidIcon(button, opts.raidIcon)
    end

    if opts.lamp then
        local lamp = button:CreateTexture(nil, "OVERLAY")
        lamp:SetWidth(8); lamp:SetHeight(8)
        lamp:SetPoint("RIGHT", button, "RIGHT", -9, 0)
        button.lamp = lamp
    end

    if opts.tip then
        setButtonTooltip(button, opts.tip, opts.tipTitle or label)
    end

    if opts.onClick then
        button:SetScript("OnClick", opts.onClick)
    elseif opts.intent then
        button:SetScript("OnClick", function()
            TB.SendActionIntent(opts.intent)
        end)
    end

    return button
end

function TB.UI.CreateTogglePill(parent, label, width, height, opts)
    opts = opts or {}
    local pill = TB.UI.CreateButton(parent, label, width or 74, height or 20, opts)
    function pill:SetActive(active)
        self.isActive = active and true or false
        if active then
            self:Disable()
        else
            self:Enable()
        end
    end
    return pill
end

function TB.UI.CreateStepper(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    if opts.relTo or opts.x or opts.y or opts.point then
        row:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetWidth(opts.width or 108)
    row:SetHeight(opts.height or 18)

    local minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    minus:SetWidth(22); minus:SetHeight(opts.height or 18)
    minus:SetPoint("LEFT", row, "LEFT", 0, 0)
    minus:SetText("-")

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    label:SetWidth(opts.labelWidth or 38)
    label:SetJustifyH("CENTER")

    local plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    plus:SetWidth(22); plus:SetHeight(opts.height or 18)
    plus:SetPoint("LEFT", label, "RIGHT", 2, 0)
    plus:SetText("+")

    local function getVal()
        if opts.get then return opts.get() end
        return 0
    end

    local function paint()
        local v = getVal()
        if opts.format then
            label:SetText(opts.format(v))
        else
            label:SetText(tostring(v))
        end
    end

    local function bump(delta)
        if opts.set then
            opts.set(getVal() + delta)
        end
        paint()
    end

    local step = opts.step or 1
    local shiftStep = opts.shiftStep or 5
    minus:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then bump(-shiftStep) else bump(-step) end
    end)
    plus:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then bump(shiftStep) else bump(step) end
    end)

    if opts.tip then
        setButtonTooltip(minus, opts.tip, opts.tipTitle)
        setButtonTooltip(plus, opts.tip, opts.tipTitle)
    end

    paint()
    row.label = label
    row.repaint = paint
    row.minus = minus
    row.plus = plus
    row.bump = bump
    return row
end

function TB.UI.CreateRow(parent, width, height, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    if opts.relTo or opts.x or opts.y or opts.point then
        row:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    row:SetWidth(width or TB.UI.Grid.CONTENT_W)
    row:SetHeight(height or TB.UI.Grid.ROW_H)
    return row
end

function TB.UI.CreateIconButton(parent, size, opts)
    opts = opts or {}
    size = size or 20
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(opts.width or size)
    btn:SetHeight(opts.height or size)
    if opts.relTo or opts.x or opts.y or opts.point then
        btn:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    btn:RegisterForClicks("LeftButtonUp")

    if opts.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(btn)
        icon:SetTexture(opts.icon)
        if opts.texCoord then
            icon:SetTexCoord(opts.texCoord[1], opts.texCoord[2], opts.texCoord[3], opts.texCoord[4])
        end
        btn.icon = icon
    end

    if opts.highlight ~= false then
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(btn)
        hl:SetTexture(1, 1, 1, 0.2)
        btn.highlight = hl
    end

    if opts.onClick then
        btn:SetScript("OnClick", opts.onClick)
    end

    if opts.onEnter then
        btn:SetScript("OnEnter", opts.onEnter)
    elseif opts.tip then
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if opts.tipTitle then
                GameTooltip:SetText(opts.tipTitle)
                local tipText = type(opts.tip) == "function" and opts.tip() or opts.tip
                GameTooltip:AddLine(tipText, 0.9, 0.9, 0.9, 1)
            else
                local tipText = type(opts.tip) == "function" and opts.tip() or opts.tip
                GameTooltip:SetText(tipText, 1, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
    end
    if opts.onLeave then
        btn:SetScript("OnLeave", opts.onLeave)
    elseif opts.tip then
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return btn
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
    -- Dedicated drag header bar across the top.
    -- Moving dragging to a dedicated header prevents clicks on child action buttons
    -- (Attack, Stop, etc.) from inadvertently triggering drag events on the main dialog.
    -- Crucially: in the WoW 1.12 client, calling GetPoint() after StopMovingOrSizing()
    -- triggers a fatal C++ access violation (0x007A2452) because StopMovingOrSizing()
    -- anchors to the root screen layout (CSimpleTop) which lacks a Lua CScriptObject.
    -- Instead, we re-anchor safely to UIParent using GetLeft() / GetTop().
    local dragBar = CreateFrame("Frame", "TortoiseBotsManagerDragHeader", parent)
    dragBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, 0)
    dragBar:SetHeight(32)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() parent:StartMoving() end)
    dragBar:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        local left, top = parent:GetLeft(), parent:GetTop()
        if left and top then
            parent:ClearAllPoints()
            parent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            db.frame = db.frame or {}
            db.frame.point = "TOPLEFT"
            db.frame.rpoint = "BOTTOMLEFT"
            db.frame.x = left
            db.frame.y = top
        end
    end)
    TB.dragHeader = dragBar
    TB.ApplyBackdrop(parent, 0.98, 1.0)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerFrame") end

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22); icon:SetHeight(22)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD or 10, -7)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    TB.versionTitle = title
    if TB.RefreshVersionLine then TB.RefreshVersionLine() else
        title:SetText("|cffd8a657Tortoise|r|cff4ecb5aBots|r |cfffff2ccManager|r  |cffffd200v"
            .. (TB.version or "?") .. "|r")
    end

    local versionLine = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    versionLine:SetPoint("TOPLEFT", parent, "TOPLEFT", (C.PAD or 10) + 28, -24)
    versionLine:SetWidth(400)
    versionLine:SetJustifyH("LEFT")
    TB.versionLine = versionLine
    if TB.RefreshVersionLine then TB.RefreshVersionLine() end

    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(0.55, 0.35, 0.08, 0.12)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -4)
    glow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -4)
    glow:SetHeight(30)

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)

    -- Mini mode: swap this window for the small fight bar.
    local mini = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    mini:SetWidth(44); mini:SetHeight(20)
    mini:SetPoint("RIGHT", close, "LEFT", -2, 0)
    mini:SetText("Mini")
    setButtonTooltip(mini, "Swap this window for a small bar with the fight buttons. Its + button brings the window back. Also /tbm mini.", "Mini mode")
    mini:SetScript("OnClick", function() TB.RequestMode("mini") end)
    TB.miniButton = mini
    -- Issue #33: the mouse-enabled drag bar spans the header corner over these
    -- buttons and eats their clicks in the 1.12 client. End the bar left of
    -- Mini and raise both buttons above it; the rest of the header still drags.
    dragBar:ClearAllPoints()
    dragBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    dragBar:SetPoint("BOTTOMRIGHT", mini, "BOTTOMLEFT", -6, 0)
    close:SetFrameLevel(dragBar:GetFrameLevel() + 2)
    mini:SetFrameLevel(dragBar:GetFrameLevel() + 2)

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
        if entry.st and entry.st.altBot then
            GameTooltip:AddLine("Login takes it back as your companion, Logout logs it out.", COL.muted[1], COL.muted[2], COL.muted[3], true)
        end
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
        return TB.UI.CreateButton(bar, label, width, 22, {
            onClick = function() lifecycleCommand(action, verb) end,
            tip = tip,
        })
    end

    local login  = button("Login", 56, "login", "add", "Log in selected offline owned bots; on an alt-bot playing alone, take it back as your companion")
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
    local def = TB.GetActionDefinition and (TB.GetActionDefinition(intent) or (TB.C and TB.C.ACTIONS_BY_INTENT and TB.C.ACTIONS_BY_INTENT[intent]))
    local labels = C.ACTION_LABELS or {}
    local label = (def and def.label) or labels[intent] or intent
    local icons = (C and C.ACTION_ICONS) or {}
    local icon = (def and def.icon) or icons[intent]
    local raidIcon = def and def.raidIcon

    local button = TB.UI.CreateButton(parent, label, width, 26, {
        x = x,
        y = y,
        intent = intent,
        icon = icon,
        raidIcon = raidIcon,
        tip = (def and def.tip) or ACTION_TOOLTIPS[intent] or ("Send .bot action " .. intent),
        tipTitle = label,
        onClick = function()
            if TB.PartyToggleKey and TB.PartyToggleKey(intent) then
                TB.SendPartyToggle(TB.PartyToggleKey(intent))
            elseif string.sub(intent, 1, 9) == "strategy " and TB.SendStrategy then
                TB.SendStrategy(string.sub(intent, 10))
            elseif intent == "release" then
                TB.SendActionIntent(TB.DeathIntent and TB.DeathIntent() or "release")
            elseif intent == "pull" or intent == "pullback" then
                TB.SendActionIntent(TB.PullIntent and TB.PullIntent(intent) or intent)
            else
                TB.SendActionIntent(intent)
            end
        end,
    })
    return button
end

TB.UI.CreateActionButton = makeActionButton

-- ── Per-card builders for Actions (Fight & Camp) ───────────────────────────

local function BuildScopeCard(parent)
    local scopeCard = CreateFrame("Frame", nil, parent)
    scopeCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
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
    hint:SetWidth(320)
    hint:SetJustifyH("LEFT")
    TB.scopeHint = hint
    TB.SetTextColor(hint, color("muted"))

    -- Shown while one of your bots is targeted: opens its gear/bags panel.
    local gearButton = TB.UI.CreateButton(scopeCard, "Gear & bags", 104, 22, {
        point = "RIGHT",
        relTo = scopeCard,
        relPoint = "RIGHT",
        x = -8,
        y = 0,
        tip = "Open the targeted bot's gear, bags and behaviour.",
        tipTitle = "Gear & bags",
        onClick = function()
            local _, name = targetScope()
            if name and TB.OpenBotPanel then TB.OpenBotPanel(name) end
        end,
    })
    gearButton:Hide()
    TB.scopeGearButton = gearButton

    return scopeCard
end

local function BuildCcMenu(parent, buttons)
    -- Marks panel: one row per raid icon. Each row shows the current owner
    -- (server-owned CC assignment, "-" when none), a cycler that assigns the
    -- next online bot by explicit name ("cc <mark> <Bot>"), and a clear button
    -- ("cc clear <Owner>"). No WoW targeting is needed: the server resolves
    -- names directly. Opened by the Actions "CC Mark" button; stays open so
    -- several marks can be assigned in one go.
    local ccMenu = CreateFrame("Frame", "TortoiseBotsManagerCcMenu", parent)
    ccMenu:SetWidth(300)
    ccMenu:SetHeight(280)
    ccMenu:SetFrameStrata("DIALOG")
    ccMenu:EnableMouse(true)
    TB.ApplyBackdrop(ccMenu, 0.98, 1.0)

    local ccTitle = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ccTitle:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -6)
    ccTitle:SetText("CC Marks")
    TB.SetTextColor(ccTitle, color("gold"))

    local ccHint = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccHint:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -22)
    ccHint:SetWidth(284)
    ccHint:SetJustifyH("LEFT")
    ccHint:SetText("Assign each mark to one bot by name.")
    TB.SetTextColor(ccHint, color("muted"))
    ccMenu.hint = ccHint

    local ccButtons = {}
    local ccRows = {}
    for i, mark in ipairs(C.CC_MARKS or {}) do
        local markId = mark.id
        local row = TB.UI.CreateRow(ccMenu, 284, 24, { x = 8, y = -40 - (i - 1) * 26 })

        local markIcon = row:CreateTexture(nil, "OVERLAY")
        markIcon:SetWidth(16); markIcon:SetHeight(16)
        markIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
        markIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark.icon)
        markIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local markLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        markLabel:SetPoint("LEFT", row, "LEFT", 20, 0)
        markLabel:SetWidth(62)
        markLabel:SetJustifyH("LEFT")
        markLabel:SetText(mark.label)
        TB.SetTextColor(markLabel, color("gold"))

        local ownerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ownerText:SetPoint("LEFT", row, "LEFT", 84, 0)
        ownerText:SetWidth(78)
        ownerText:SetJustifyH("LEFT")
        ownerText:SetText("-")
        TB.SetTextColor(ownerText, color("muted"))

        local cycleButton = TB.UI.CreateButton(row, "Next", 64, 20, {
            point = "LEFT",
            relTo = row,
            relPoint = "LEFT",
            x = 164,
            y = 0,
            tip = "Assign " .. mark.label .. " to the next online bot by name",
            onClick = function()
                local cands = TB.GetCcCandidates and TB.GetCcCandidates() or {}
                if table.getn(cands) == 0 then return end
                local current = TB.GetCcOwner and TB.GetCcOwner(markId) or nil
                local idx = 0
                for j, name in ipairs(cands) do
                    if name == current then idx = j break end
                end
                idx = math.mod(idx, table.getn(cands)) + 1
                TB.SendActionIntent("cc " .. markId .. " " .. cands[idx])
            end,
        })
        cycleButton.mark = markId

        local clearButton = TB.UI.CreateButton(row, "X", 46, 20, {
            point = "LEFT",
            relTo = row,
            relPoint = "LEFT",
            x = 230,
            y = 0,
            tip = "Clear " .. mark.label .. " from its current owner",
            onClick = function()
                local owner = TB.GetCcOwner and TB.GetCcOwner(markId) or nil
                if owner then
                    TB.SendActionIntent("cc clear " .. owner)
                end
            end,
        })
        clearButton.mark = markId

        ccRows[markId] = { ownerText = ownerText, cycle = cycleButton, clear = clearButton }
        ccButtons[markId] = cycleButton
    end
    ccMenu.buttons = ccButtons
    ccMenu.rows = ccRows

    local clearAllButton = TB.UI.CreateButton(ccMenu, "Clear all", 120, 22, {
        x = 8,
        y = -250,
        tip = "Clear every CC mark from every bot",
        onClick = function()
            TB.SendActionIntent("cc clear")
        end,
    })
    ccMenu.clearAll = clearAllButton
    ccMenu:Hide()

    ccMenu.Update = function()
        for _, mark in ipairs(C.CC_MARKS or {}) do
            local row = ccRows[mark.id]
            if row then
                local owner = TB.GetCcOwner and TB.GetCcOwner(mark.id) or nil
                row.ownerText:SetText(owner or "-")
            end
        end
    end

    TB.ToggleCcMenu = function()
        if ccMenu:IsVisible() then
            ccMenu:Hide()
        else
            ccMenu:Show()
            ccMenu:ClearAllPoints()
            if buttons and buttons.ccMoon then
                ccMenu:SetPoint("TOPLEFT", buttons.ccMoon, "BOTTOMLEFT", 0, -4)
            end
            ccMenu:Update()
        end
    end
    TB.ccMenu = ccMenu
    return ccMenu
end

local function BuildEngageCard(parent, buttons)
    -- Fight: Engage (attack, stop, interrupt, flee)
    local card = TB.UI.CreateCard(parent, "ENGAGE", W - (C.PAD or 10) * 2, 56, { y = -38, line = true })
    local btnY = -22
    buttons.attack    = makeActionButton(card, "attack", 110, 8, btnY)
    buttons.stop      = makeActionButton(card, "stop", 110, 126, btnY)
    buttons.interrupt = makeActionButton(card, "interrupt", 110, 244, btnY)
    buttons.flee      = makeActionButton(card, "flee", 110, 362, btnY)
    return card
end

local function BuildPullCard(parent, buttons)
    -- Pull & Focus: pull, pullback with timers, focus skull, cc mark cover
    -- the button row; End pull sits in the timer row as the small
    -- "stop pulling" escape next to the timing controls.
    local card = TB.UI.CreateCard(parent, "PULL & FOCUS", W - (C.PAD or 10) * 2, 76, { y = -98, line = true })
    local btnY = -22
    buttons.pull      = makeActionButton(card, "pull", 110, 8, btnY)
    buttons.pullback  = makeActionButton(card, "pullback", 110, 126, btnY)

    buttons.pullTimer = TB.UI.CreateStepper(card, {
        relTo = buttons.pull,
        point = "TOPLEFT",
        relPoint = "BOTTOMLEFT",
        x = 1,
        y = -2,
        tip = "Seconds the other bots wait before joining a Pull (0-60, shift-click = 5).",
        tipTitle = "Pull timer",
        get = function()
            local dbNow = TortoiseBotsDB or {}
            return TB.ClampPullSeconds(dbNow.pullDelay)
        end,
        set = function(val)
            TortoiseBotsDB = TortoiseBotsDB or {}
            TortoiseBotsDB.pullDelay = TB.ClampPullSeconds(val)
        end,
        format = function(val)
            return val .. " s"
        end,
    })

    buttons.pullbackTimer = TB.UI.CreateStepper(card, {
        relTo = buttons.pullback,
        point = "TOPLEFT",
        relPoint = "BOTTOMLEFT",
        x = 1,
        y = -2,
        tip = "Seconds the other bots wait after the tank is back from a Pull back (0-60, shift-click = 5).",
        tipTitle = "Pull timer",
        get = function()
            local dbNow = TortoiseBotsDB or {}
            return TB.ClampPullSeconds(dbNow.pullbackDelay)
        end,
        set = function(val)
            TortoiseBotsDB = TortoiseBotsDB or {}
            TortoiseBotsDB.pullbackDelay = TB.ClampPullSeconds(val)
        end,
        format = function(val)
            return val .. " s"
        end,
    })

    TB.pullTimers = { pull = buttons.pullTimer, pullback = buttons.pullbackTimer }

    buttons.endPull = makeActionButton(card, "end pull", 110, 244, -48)
    buttons.focusSkull = makeActionButton(card, "focus skull", 110, 244, btnY)
    buttons.ccMoon     = makeActionButton(card, "cc moon", 110, 362, btnY)
    buttons.ccMoon:SetText("CC Mark")
    buttons.ccMoon:SetScript("OnClick", function() TB.ToggleCcMenu() end)
    buttons.ccMark     = buttons.ccMoon
    addRaidIcon(buttons.focusSkull, 8)
    return card
end

local function BuildMoveCard(parent, buttons)
    -- Move: five orders plus stance pills inline on one row.
    local card = TB.UI.CreateCard(parent, "MOVE", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_MOVE_H or 86, { y = -182, line = true })
    local btnY = -24
    buttons.follow   = makeActionButton(card, "follow", 88, 8, btnY)
    buttons.stay     = makeActionButton(card, "stay", 88, 100, btnY)
    buttons.come     = makeActionButton(card, "come", 88, 192, btnY)
    buttons.hold     = buttons.come
    buttons.guard    = makeActionButton(card, "guard", 88, 284, btnY)
    buttons.free     = makeActionButton(card, "free", 88, 376, btnY)
    buttons.follow:SetHeight(20); buttons.stay:SetHeight(20); buttons.come:SetHeight(20)
    buttons.guard:SetHeight(20); buttons.free:SetHeight(20)
    TB.stancePills = {}
    local stanceIds = { "near", "tank", "turnback", "behind" }
    local stanceLabels = { near = "Near", tank = "Tank", turnback = "Turnback", behind = "Behind" }
    for i, id in ipairs(stanceIds) do
        local def = TB.GetActionDefinition and TB.GetActionDefinition("stance " .. id)
        local label = stanceLabels[id] or id
        local btn = TB.UI.CreateTogglePill(card, label, 104, 20, {
            x = 8 + (i - 1) * 108,
            y = -50,
            tip = (def and def.tip) or (TB.ActionTooltip and TB.ActionTooltip("stance " .. id)),
            tipTitle = (label .. " stance"),
            onClick = function()
                TB.SetStance(id)
            end,
        })
        TB.stancePills[id] = btn
    end
    TB.UpdateStancePills()
    return card
end

local function BuildSwitchesCard(parent, buttons)
    -- Party switches: state comes from the server (TBM:BOTSTATE), the lamp
    -- shows it at a glance (green on, grey off, gold mixed/unknown). One
    -- row of five compact buttons fits the content width; icons are left
    -- off so the state words clear the lamp on the narrow buttons.
    local card = TB.UI.CreateCard(parent, "PARTY SWITCHES", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_SWITCH_H or 54, { y = -262, line = true })
    local btnY = -22
    TB.toggleButtons = {}
    local switchIdx = 1
    for _, def in ipairs(C.ACTION_DEFINITIONS or {}) do
        if def.section == "switch" then
            local btn = makeActionButton(card, def.intent, 88, 8 + (switchIdx - 1) * 96, btnY)
            if btn.icon then btn.icon:Hide() end
            btn.toggle = { key = def.toggle, intent = def.intent, label = def.label, tip = def.tip }
            btn.lamp = btn:CreateTexture(nil, "OVERLAY")
            btn.lamp:SetWidth(8); btn.lamp:SetHeight(8)
            btn.lamp:SetPoint("RIGHT", btn, "RIGHT", -9, 0)
            setButtonTooltip(btn, def.tip .. " Click to switch for the whole party (or only the targeted bot).",
                def.label)
            TB.toggleButtons[def.toggle] = btn
            switchIdx = switchIdx + 1
        end
    end
    buttons.aoe = TB.toggleButtons.aoe
    buttons.autoCc = TB.toggleButtons.autocc
    buttons.loot = TB.toggleButtons.loot
    buttons.sap = TB.toggleButtons.sap
    buttons.spread = TB.toggleButtons.spread
    return card
end

local function BuildTacticsCard(parent, buttons)
    -- Combat tactics: one-shot strategy orders (kiting, auto-mark, focus
    -- fire, fear). The server confirms each via "Strategy change" text.
    local card = TB.UI.CreateCard(parent, "TACTICS", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_TACTIC_H or 46, { y = -288, line = true })
    buttons.tacticKite = makeActionButton(card, "strategy ~kite", 110, 8, -22)
    buttons.tacticMark = makeActionButton(card, "strategy ~mark rti", 110, 126, -22)
    buttons.tacticFocus = makeActionButton(card, "strategy ~focus", 110, 244, -22)
    buttons.tacticAoeFear = makeActionButton(card, "strategy ~aoe fear", 110, 362, -22)
    buttons.tacticKite:SetHeight(22)
    buttons.tacticMark:SetHeight(22)
    buttons.tacticFocus:SetHeight(22)
    buttons.tacticAoeFear:SetHeight(22)
    return card
end

local function BuildRestCard(campFrame, buttons)
    -- Camp chores: Rest, ready, repair, sell, train, release
    local card = TB.UI.CreateCard(campFrame, "REST, REPAIR & TRAIN", W - (C.PAD or 10) * 2, 88, { y = -18, line = true })
    local btnY = -24
    buttons.rest    = makeActionButton(card, "rest", 148, 8, btnY)
    buttons.ready   = makeActionButton(card, "ready", 148, 164, btnY)
    buttons.repair  = makeActionButton(card, "repair", 148, 320, btnY)
    buttons.sell    = makeActionButton(card, "sell", 148, 8, -54)
    buttons.learn   = makeActionButton(card, "learn", 148, 164, -54)
    buttons.release = makeActionButton(card, "release", 148, 320, -54)
    buttons.release.tooltipExtra = function()
        if TB.DeathIntent and TB.DeathIntent() == "corpse run" then
            return "Now: ghosts run back to their corpses."
        end
        return nil
    end
    return card
end

local function BuildFormationCard(campFrame)
    -- Formation pills with a line describing the active one.
    local card = TB.UI.CreateCard(campFrame, "FORMATION", W - (C.PAD or 10) * 2, 76, { y = -110, line = true })
    local pills = {}
    local formationTips = {}
    for i, def in ipairs(C.FORMATIONS or {}) do
        local id = def.id
        formationTips[id] = def.label .. ": " .. def.tip
        local btn = TB.UI.CreateTogglePill(card, def.label, 74, 20, {
            x = 8 + (i - 1) * 78,
            y = -26,
            tip = def.tip .. " Applies to the whole party, or only the targeted bot.",
            tipTitle = def.label,
            onClick = function()
                TB.SetFormation(id)
            end,
        })
        pills[id] = btn
    end
    local formDesc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formDesc:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -54)
    formDesc:SetWidth(460); formDesc:SetJustifyH("LEFT")
    TB.SetTextColor(formDesc, color("muted"))

    TB.formationPills = pills
    TB.UpdateFormationPills = function()
        local active = TB.currentFormation or "shield"
        for id, btn in pairs(pills) do
            btn:SetActive(id == active)
        end
        formDesc:SetText(formationTips[active] or "")
    end
    TB.UpdateFormationPills()
    return card
end

TB.UI.BuildScopeCard     = BuildScopeCard
TB.UI.BuildCcMenu        = BuildCcMenu
TB.UI.BuildEngageCard    = BuildEngageCard
TB.UI.BuildPullCard      = BuildPullCard
TB.UI.BuildMoveCard      = BuildMoveCard
TB.UI.BuildSwitchesCard  = BuildSwitchesCard
TB.UI.BuildTacticsCard   = BuildTacticsCard
TB.UI.BuildRestCard      = BuildRestCard
TB.UI.BuildFormationCard = BuildFormationCard

CreateActions = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetWidth(W - (C.PAD or 10) * 2)
    frame:SetHeight(300)

    -- Scope Banner Card
    BuildScopeCard(frame)

    -- Camp: the between-fights view, a sibling of the Fight view.
    local campFrame = CreateFrame("Frame", nil, parent)
    campFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    campFrame:SetWidth(W - (C.PAD or 10) * 2)
    campFrame:SetHeight(300)
    local campHint = campFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    campHint:SetPoint("TOPLEFT", campFrame, "TOPLEFT", 6, 0)
    campHint:SetWidth(468); campHint:SetJustifyH("LEFT")
    TB.SetTextColor(campHint, color("muted"))
    TB.campScopeHint = campHint

    local buttons = {}

    -- Build cards for Fight view
    BuildCcMenu(frame, buttons)
    BuildEngageCard(frame, buttons)
    BuildPullCard(frame, buttons)
    BuildMoveCard(frame, buttons)
    BuildSwitchesCard(frame, buttons)
    BuildTacticsCard(frame, buttons)

    -- Build cards for Camp view
    BuildRestCard(campFrame, buttons)
    BuildFormationCard(campFrame)

    local campTip = campFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    campTip:SetPoint("TOPLEFT", campFrame, "TOPLEFT", 6, -196)
    campTip:SetWidth(468); campTip:SetJustifyH("LEFT")
    campTip:SetText("Gear, bags and per-bot habits: bag icon on the Party tab, or target a bot and use Gear & bags on Fight.")
    TB.SetTextColor(campTip, color("muted"))

    TB.campFrame = campFrame
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
    fs:SetText("Ready.")
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
        button:SetWidth(76); button:SetHeight(20)
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

    -- Tabs by kind of work: Fight (in a pull), Camp (between pulls), Party
    -- (who does what), Roster (who is logged in), Guild (claimed bots), Raid (raid only), Log.
    local tabActions = makeTab("Fight", 0)
    local tabCamp = makeTab("Camp", 80)
    local tabParty = makeTab("Party", 160)
    local tabRoster = makeTab("Roster", 240)
    local tabGuild = makeTab("Guild", 320)
    local tabRaid = makeTab("Raid", 400)
    local tabLog = makeTab("Log", 480)
    local content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    content:SetWidth(W - (C.PAD or 10) * 2)
    content:SetHeight(330)

    local actionsFrame = CreateActions(content)
    local campFrame = TB.campFrame
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
        subtitle:SetText("|cff888888(role buttons · bag = gear & bags · click a row to target)|r")

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
            descText:SetWidth(260)
            descText:SetJustifyH("LEFT")
            TB.SetTextColor(descText, color("muted"))
            row.descText = descText

            local ccIcon = row:CreateTexture(nil, "ARTWORK")
            ccIcon:SetWidth(18); ccIcon:SetHeight(18)
            -- Keep the indicator in its own lower-right slot. Role buttons are
            -- reflowed to the upper row below, so four-role classes (notably
            -- Druids) can never cover the assignment icon.
            ccIcon:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
            ccIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            ccIcon:Hide()
            row.ccIcon = ccIcon

            local ccLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ccLabel:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -31, 5)
            ccLabel:SetText("CC")
            TB.SetTextColor(ccLabel, color("muted"))
            row.ccLabel = ccLabel

            local playerLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            playerLabel:SetPoint("LEFT", row, "LEFT", 150, 0)
            playerLabel:SetText("|cffd8a657[ Player / Master ]|r")
            row.playerLabel = playerLabel

            -- Gear & bags panel for a controllable bot (shown when the server
            -- reports the bot in TBM:BOTSTATE).
            local bagButton = TB.UI.CreateIconButton(row, 22, {
                point = "TOPRIGHT",
                relTo = row,
                relPoint = "TOPRIGHT",
                x = -8,
                y = -4,
                icon = "Interface\\Buttons\\Button-Backpack-Up",
                onClick = function()
                    if row.partyName and TB.OpenBotPanel then TB.OpenBotPanel(row.partyName) end
                end,
                onEnter = function()
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Gear & bags")
                    GameTooltip:AddLine("Open " .. (row.partyName or "this bot") .. "'s gear, bags and behaviour.",
                        0.9, 0.9, 0.9, 1)
                    GameTooltip:Show()
                end,
                onLeave = function() GameTooltip:Hide() end,
            })
            bagButton:Hide()
            row.bagButton = bagButton

            local roleButtons = {}
            for b = 1, 4 do
                local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                btn:SetWidth(78)
                btn:SetHeight(22)
                btn:SetPoint("LEFT", row, "LEFT", 150 + (b - 1) * 82, 8)
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

    local function CreateRaidView(parent)
        local raidFrame = CreateFrame("Frame", nil, parent)
        raidFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        raidFrame:SetWidth(W - (C.PAD or 10) * 2)
        raidFrame:SetHeight(330)

        local intro = raidFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 6, 0)
        intro:SetWidth(468); intro:SetJustifyH("LEFT")
        intro:SetText("Orders go to your bots in this raid. Target one of your bots to send an order to that bot only.")
        TB.SetTextColor(intro, color("muted"))

        local function card(titleText, y, height)
            return TB.UI.CreateCard(raidFrame, titleText, W - (C.PAD or 10) * 2, height, { y = y, line = false })
        end
        local function button(parent, label, width, x, y, intent, tip)
            return TB.UI.CreateButton(parent, label, width, 24, { x = x, y = y, intent = intent, tip = tip })
        end
        local function note(parent, text, y)
            local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
            fs:SetWidth(464); fs:SetJustifyH("LEFT")
            fs:SetText(text)
            TB.SetTextColor(fs, color("muted"))
            return fs
        end

        local encounters = card("ENCOUNTER HELPERS", -18, 78)
        raidFrame.tankface = button(encounters, "Tank face away", 180, 8, -24, "raid tankface",
            "Target the dragon (Onyxia and other dragons): tank bots turn it away so breath and cleave miss the raid.")
        raidFrame.douse = button(encounters, "Douse runes", 180, 196, -24, "raid douse",
            "Molten Core: bots douse the nearby runes with Aqual or Eternal Quintessence (they must carry one).")
        note(encounters, "Bots switch to boss tactics on their own in supported raids; these are the manual extras.", -54)

        local custom = card("TURTLE CUSTOM RAIDS", -100, 78)
        raidFrame.customToggle = button(custom, "Custom tactics: ?", 180, 8, -24, nil,
            "Scripted boss moves for Emerald Sanctum, Lower Karazhan and Karazhan Crypt. Turn off to steer the bots yourself.")
        raidFrame.customToggle.lamp = raidFrame.customToggle:CreateTexture(nil, "OVERLAY")
        raidFrame.customToggle.lamp:SetWidth(8); raidFrame.customToggle.lamp:SetHeight(8)
        raidFrame.customToggle.lamp:SetPoint("RIGHT", raidFrame.customToggle, "RIGHT", -9, 0)
        raidFrame.customToggle:SetScript("OnClick", function()
            local state = TB.GetRaidCustomState and TB.GetRaidCustomState()
            TB.SendActionIntent(state == "on" and "raid custom off" or "raid custom on")
        end)
        raidFrame.customCheck = button(custom, "Check", 90, 196, -24, "raid custom status",
            "Ask every bot whether custom raid tactics are on.")
        note(custom, "The server can switch these off entirely (AiPlayerbot.EnableCustomRaidTactics).", -54)

        local status = card("BOT RAID TACTICS", -182, 146)
        raidFrame.statusButton = button(status, "Check bots", 120, 8, -24, nil,
            "List the boss tactics each bot has loaded for this raid.")
        raidFrame.statusButton:SetScript("OnClick", function()
            if TB.ClearRaidStatus then TB.ClearRaidStatus() end
            TB.SendActionIntent("raid status")
        end)
        local list = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        list:SetPoint("TOPLEFT", status, "TOPLEFT", 10, -56)
        list:SetWidth(460); list:SetJustifyH("LEFT")
        if list.SetJustifyV then list:SetJustifyV("TOP") end
        list:SetText("")
        raidFrame.statusList = list
        return raidFrame
    end

    local raidFrame = CreateRaidView(content)

    local function CreateGuildView(parent)
        local guildFrame = CreateFrame("Frame", nil, parent)
        guildFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        guildFrame:SetWidth(W - (C.PAD or 10) * 2)
        guildFrame:SetHeight(325)

        -- Top search / count row
        local search = CreateFrame("EditBox", "TortoiseBotsManagerGuildSearch", guildFrame, "InputBoxTemplate")
        search:SetWidth(150); search:SetHeight(20)
        search:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 6, 0)
        search:SetAutoFocus(false)
        search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        search:SetScript("OnTextChanged", function()
            TB.guildFilterText = this:GetText() or ""
            if TB.RefreshGuildView then TB.RefreshGuildView() end
        end)
        guildFrame.searchBox = search

        local clear = CreateFrame("Button", nil, guildFrame, "UIPanelButtonTemplate")
        clear:SetWidth(42); clear:SetHeight(18)
        clear:SetPoint("LEFT", search, "RIGHT", 4, 0)
        clear:SetText("Clear")
        clear:SetScript("OnClick", function()
            search:SetText("")
            search:ClearFocus()
            TB.guildFilterText = ""
            if TB.RefreshGuildView then TB.RefreshGuildView() end
        end)

        local count = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("TOPRIGHT", guildFrame, "TOPRIGHT", -6, -2)
        count:SetWidth(240)
        count:SetJustifyH("RIGHT")
        TB.SetTextColor(count, color("muted"))
        guildFrame.countLabel = count

        -- Column headers
        local checkAll = CreateFrame("CheckButton", "TortoiseBotsManagerGuildCheckAll", guildFrame, "UICheckButtonTemplate")
        checkAll:SetWidth(20); checkAll:SetHeight(20)
        checkAll:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 4, -20)
        setButtonTooltip(checkAll, "Select or deselect all claimed bots")
        checkAll:SetScript("OnClick", function()
            local isChecked = this:GetChecked() and true or false
            TB.SelectAllClaimed(isChecked)
        end)
        guildFrame.checkAll = checkAll

        local headers = {
            { text = "Name", width = 96, x = 28 },
            { text = "Level / Class", width = 84, x = 126 },
            { text = "Gear", width = 64, x = 212 },
            { text = "Status", width = 64, x = 278 },
            { text = "Bag", width = 24, x = 344 },
            { text = "Role", width = 52, x = 372 },
            { text = "Kick", width = 30, x = 428 },
        }
        for _, h in ipairs(headers) do
            local fs = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", h.x, -24)
            fs:SetWidth(h.width)
            fs:SetText(h.text)
            TB.SetTextColor(fs, color("muted"))
        end

        local GUILD_ROW_H = 32
        local GUILD_ROW_N = 7
        local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerGuildScroll", guildFrame, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 0, -42)
        scroll:SetWidth(W - (C.PAD or 10) * 2)
        scroll:SetHeight(GUILD_ROW_N * GUILD_ROW_H + 4)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(GUILD_ROW_H, TB.RefreshGuildView)
        end)
        guildFrame.scroll = scroll

        local rows = {}
        for i = 1, GUILD_ROW_N do
            local row = CreateFrame("Frame", nil, guildFrame)
            row:SetWidth(W - (C.PAD or 10) * 2 - 18)
            row:SetHeight(GUILD_ROW_H - 2)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * GUILD_ROW_H)
            TB.ApplyBackdrop(row, 0.62, 0.45)
            row:EnableMouse(true)

            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetWidth(3)
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
            row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetWidth(20); row.check:SetHeight(20)
            row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.check:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry then TB.ToggleClaimedSelection(entry.name, this:GetChecked() and true or false) end
            end)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 28, 0)
            row.name:SetWidth(96)
            row.name:SetJustifyH("LEFT")

            row.lvlClass = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.lvlClass:SetPoint("LEFT", row, "LEFT", 126, 0)
            row.lvlClass:SetWidth(84)
            row.lvlClass:SetJustifyH("LEFT")

            row.gearBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.gearBadge:SetPoint("LEFT", row, "LEFT", 212, 0)
            row.gearBadge:SetWidth(64)
            row.gearBadge:SetJustifyH("LEFT")

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.status:SetPoint("LEFT", row, "LEFT", 278, 0)
            row.status:SetWidth(64)
            row.status:SetJustifyH("LEFT")

            local bagBtn = TB.UI.CreateIconButton(row, 20, {
                point = "LEFT",
                relTo = row,
                relPoint = "LEFT",
                x = 346,
                y = 0,
                icon = "Interface\\Buttons\\Button-Backpack-Up",
                onClick = function()
                    local entry = this:GetParent().entry
                    if entry and TB.OpenBotPanel then TB.OpenBotPanel(entry.name, "inv") end
                end,
                onEnter = function()
                    local entry = this:GetParent().entry
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Gear & Bags")
                    GameTooltip:AddLine("Open " .. (entry and entry.name or "this bot") .. "'s gear, bags and paperdoll.", 0.9, 0.9, 0.9, 1)
                    GameTooltip:Show()
                end,
                onLeave = function() GameTooltip:Hide() end,
            })
            row.bagBtn = bagBtn

            local roleBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            roleBtn:SetWidth(52); roleBtn:SetHeight(20)
            roleBtn:SetPoint("LEFT", row, "LEFT", 372, 0)
            roleBtn:SetText("Role")
            roleBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if not entry then return end
                TB.Roles.CycleBotRole(entry.name, entry.classId)
                if TB.RefreshGuildView then TB.RefreshGuildView() end
            end)
            roleBtn:SetScript("OnEnter", function()
                local entry = this:GetParent().entry
                if not entry then return end
                local dbRoles = (TortoiseBotsDB and TortoiseBotsDB.botRoles) or {}
                local currentId = dbRoles[entry.name]
                local curLabel = TB.Roles.GetRoleLabel(entry.classId, currentId, "Default")
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText("Combat Role: " .. curLabel)
                GameTooltip:AddLine("Click to cycle to the next combat role.", 0.9, 0.9, 0.9, 1)
                GameTooltip:Show()
            end)
            roleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.roleBtn = roleBtn


            local relBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            relBtn:SetWidth(30); relBtn:SetHeight(20)
            relBtn:SetPoint("LEFT", row, "LEFT", 428, 0)
            relBtn:SetText("Rel")
            relBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.ConfirmReleaseClaimedBot then
                    TB.ConfirmReleaseClaimedBot(entry.name)
                end
            end)
            setButtonTooltip(relBtn, "Release this bot back to the wandering bot pool (/gkick)")
            row.relBtn = relBtn

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(row)
            hl:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.08)

            row:SetScript("OnEnter", function()
                local entry = this.entry
                if not entry then return end
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(entry.name)
                GameTooltip:AddLine("Level " .. entry.level .. " " .. (entry.className or "") .. " · " .. (entry.status or "Unknown"), 1, 1, 1)
                if entry.location then
                    GameTooltip:AddLine("Location: " .. entry.location, COL.muted[1], COL.muted[2], COL.muted[3])
                end
                if entry.gearLocked then
                    GameTooltip:AddLine("|cffffd200Gear Hard-Locked (Lvl 60)|r\nBot will never self-equip or auto-vendor gear. 100% player managed.", 1, 0.82, 0)
                else
                    GameTooltip:AddLine("|cff4ecb5aLeveling Freedom (1-59)|r\nBot equips world upgrades. Preserves all blues and epics in bags.", 0.3, 0.9, 0.3)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            table.insert(rows, row)
        end
        guildFrame.rows = rows

        -- Empty state message
        local emptyMsg = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyMsg:SetPoint("CENTER", guildFrame, "CENTER", 0, -10)
        emptyMsg:SetWidth(420)
        emptyMsg:SetJustifyH("CENTER")
        emptyMsg:SetText("|cffd8a657No Claimed Guild Bots|r\n\n|cffffffffYou can claim autonomous wandering bots in the world as your personal raid roster alt-bots!|r\n\n|cff888888Invite any unguilded bot to your guild using:|r\n|cff4ecb5a/ginvite <BotName>|r\n\n|cff888888Claimed bots preserve the gear you give them, never auto-vendor at 60, and can be inspected, geared, and summoned here.|r")
        guildFrame.emptyMsg = emptyMsg

        -- Bottom Guild Action Bar
        local bar = CreateFrame("Frame", nil, guildFrame)
        bar:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 0, -(42 + GUILD_ROW_N * GUILD_ROW_H + 4))
        bar:SetWidth(W - (C.PAD or 10) * 2)
        bar:SetHeight(34)

        local selection = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        selection:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 8)
        selection:SetWidth(85)
        selection:SetJustifyH("LEFT")
        TB.SetTextColor(selection, color("muted"))
        guildFrame.selectionLabel = selection

        local inviteBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        inviteBtn:SetWidth(110); inviteBtn:SetHeight(22)
        inviteBtn:SetPoint("LEFT", selection, "RIGHT", 4, 0)
        inviteBtn:SetText("Invite to Raid")
        setButtonTooltip(inviteBtn, "Invite selected online claimed bots to your raid or party")
        inviteBtn:SetScript("OnClick", function()
            local names = TB.GetEligibleClaimedNames and TB.GetEligibleClaimedNames("invite") or {}
            if table.getn(names) > 0 then
                if TB.QueueRosterBatch then
                    TB.QueueRosterBatch("invite", names)
                else
                    for _, n in ipairs(names) do TB.SendBotCommand("invite " .. n) end
                end
            elseif TB.SetStatus then
                TB.SetStatus("No eligible selected bots to invite.", "muted")
            end
        end)
        guildFrame.inviteBtn = inviteBtn

        local summonBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        summonBtn:SetWidth(110); summonBtn:SetHeight(22)
        summonBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 4, 0)
        summonBtn:SetText("Summon to Raid")
        setButtonTooltip(summonBtn, "Summon selected online claimed bots to your position")
        summonBtn:SetScript("OnClick", function()
            local names = TB.GetEligibleClaimedNames and TB.GetEligibleClaimedNames("summon") or {}
            if table.getn(names) > 0 then
                for _, n in ipairs(names) do TB.SendBotCommand("summon " .. n) end
            elseif TB.SetStatus then
                TB.SetStatus("No eligible selected bots to summon.", "muted")
            end
        end)
        guildFrame.summonBtn = summonBtn

        local syncBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        syncBtn:SetWidth(56); syncBtn:SetHeight(22)
        syncBtn:SetPoint("LEFT", summonBtn, "RIGHT", 4, 0)
        syncBtn:SetText("Sync")
        setButtonTooltip(syncBtn, "Sync claimed guild bots and roster from server")
        syncBtn:SetScript("OnClick", function()
            if TB.PollList then TB.PollList(true) end
        end)
        guildFrame.syncBtn = syncBtn

        guildFrame.guildBar = bar
        return guildFrame
    end

    local guildFrame = CreateGuildView(content)

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
                local movement = unit ~= "player" and TB.MovementLabel and TB.MovementLabel(name) or nil
                row.descText:SetText(lvlText .. " " .. (className or "")
                    .. (movement and (" · " .. movement) or ""))
                if unit ~= "player" and TB.GetBotState and TB.GetBotState(name)
                    and TB.HasServerCapability and TB.HasServerCapability("inventory") then
                    row.bagButton:Show()
                else
                    row.bagButton:Hide()
                end
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

                local isPlayer = unit == "player"
                if isPlayer then
                    row.playerLabel:ClearAllPoints()
                    row.playerLabel:SetPoint("LEFT", row, "LEFT", 150, -13)
                    row.playerLabel:Show()
                else
                    row.playerLabel:Hide()
                end

                local roles = TB.Roles.GetClassRoles(classId)
                local currentRole
                if isPlayer then
                    currentRole = TB.Roles.GetPlayerRole(classId)
                else
                    currentRole = TB.Roles.GetBotRole(name, classId)
                end
                -- Four-role rows need a reserved CC column on the right.
                -- Keep the normal button width for other classes so their
                -- longer role labels remain readable.
                local roleCount = table.getn(roles)
                local roleWidth = roleCount >= 4 and 70 or 78
                local roleStep = roleCount >= 4 and 72 or 82

                for b = 1, 4 do
                    local btn = row.roleButtons[b]
                    local role = roles[b]
                    btn:ClearAllPoints()
                    btn:SetWidth(roleWidth)
                    btn:SetPoint("LEFT", row, "LEFT", 150 + (b - 1) * roleStep, 8)
                    if role then
                        local isSelected = currentRole == role.id
                        if isSelected then
                            btn:SetText("|cffffd200" .. role.label .. "|r")
                        else
                            btn:SetText("|cffa0a0a0" .. role.label .. "|r")
                        end

                        local capturedRole = role
                        local capturedName = name
                        local playerRoleToken = TB.Roles.GetPlayerRoleToken(capturedRole.id)
                        btn:SetScript("OnClick", function()
                            if isPlayer then
                                TB.Roles.SetPlayerRole(capturedRole, classId)
                            else
                                TB.Roles.SetBotRole(capturedName, capturedRole, classId)
                            end
                            TB.RefreshPartyView()
                        end)

                        if isPlayer then
                            setButtonTooltip(btn, "Set your role to " .. capturedRole.label ..
                                " (bots use " .. playerRoleToken .. ").")
                        else
                            setButtonTooltip(btn, "Set " .. capturedName .. " role to " .. capturedRole.label ..
                                (capturedRole.strat ~= "" and (" (" .. capturedRole.strat .. ")") or ""))
                        end
                        btn:Show()
                    else
                        btn:Hide()
                    end
                end

                row:Show()
            else
                row:Hide()
                row.partyUnit = nil
                row.partyName = nil
                row.ccMark = nil
                row.ccIcon:Hide()
                row.bagButton:Hide()
            end
        end

        if partyCount == 0 then
            TB.partyFrame.emptyMsg:Show()
        else
            TB.partyFrame.emptyMsg:Hide()
        end
    end

    function TB.RefreshGuildView()
        if not TB.guildFrame or not TB.guildFrame.rows then return end
        local frame = TB.guildFrame
        local allBots = TB.GetClaimedBots and TB.GetClaimedBots(TB.guildFilterText) or {}
        local total = table.getn(allBots)
        local onlineCount = 0
        local lockedCount = 0
        for _, b in ipairs(allBots) do
            if b.online then onlineCount = onlineCount + 1 end
            if b.gearLocked then lockedCount = lockedCount + 1 end
        end

        if frame.countLabel then
            frame.countLabel:SetText("Claimed: " .. total .. "  (|cff4ecb5a" .. onlineCount
                .. " online|r, |cffffd200" .. lockedCount .. " locked|r)")
        end

        if total == 0 then
            if frame.emptyMsg then frame.emptyMsg:Show() end
            if frame.scroll then frame.scroll:Hide() end
            if frame.guildBar then frame.guildBar:Hide() end
            for _, row in ipairs(frame.rows) do row:Hide() end
            return
        end

        if frame.emptyMsg then frame.emptyMsg:Hide() end
        if frame.scroll then frame.scroll:Show() end
        if frame.guildBar then frame.guildBar:Show() end

        FauxScrollFrame_Update(frame.scroll, total, 7, 32)
        local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(frame.scroll)) or 0
        local dbRoles = (TortoiseBotsDB and TortoiseBotsDB.botRoles) or {}

        local allSelected = total > 0
        for i = 1, 7 do
            local row = frame.rows[i]
            local idx = offset + i
            if idx <= total then
                local entry = allBots[idx]
                row.entry = entry
                row.claimedName = entry.name
                local isSelected = TB.IsClaimedSelected and TB.IsClaimedSelected(entry.name) or false
                if not isSelected then allSelected = false end
                row.check:SetChecked(isSelected)

                local classColor = C.CLASS_COLORS and C.CLASS_COLORS[entry.classId] or COL.gold
                row.name:SetText(entry.name)
                row.name:SetTextColor(classColor[1], classColor[2], classColor[3])

                row.lvlClass:SetText(entry.level .. " " .. (entry.className or ""))
                if entry.gearLocked then
                    row.gearBadge:SetText("|cffffd200[Locked]|r")
                else
                    row.gearBadge:SetText("|cff4ecb5a[Leveling]|r")
                end

                local statusColor = entry.online and "|cff4ecb5a" or "|cff888888"
                local statusStr = entry.status or (entry.online and "Online" or "Offline")
                if entry.group then statusStr = statusStr .. " (P)" end
                row.status:SetText(statusColor .. statusStr .. "|r")

                -- Role button label
                local currentRoleId = dbRoles[entry.name]
                local roleLabel = TB.Roles.GetRoleLabel(entry.classId, currentRoleId, "Role")
                if roleLabel == "Role" and table.getn(TB.Roles.GetClassRoles(entry.classId)) > 0 then
                    roleLabel = TB.Roles.GetClassRoles(entry.classId)[1].label
                end
                row.roleBtn:SetText(roleLabel)


                row:Show()
            else
                row:Hide()
            end
        end

        if frame.checkAll then
            frame.checkAll:SetChecked(allSelected)
        end

        local selCount = TB.GetClaimedSelectionCount and TB.GetClaimedSelectionCount() or 0
        if frame.selectionLabel then
            frame.selectionLabel:SetText(selCount .. " selected")
        end
        if frame.inviteBtn then
            if selCount > 0 then frame.inviteBtn:Enable() else frame.inviteBtn:Disable() end
        end
        if frame.summonBtn then
            if selCount > 0 then frame.summonBtn:Enable() else frame.summonBtn:Disable() end
        end
    end

    local tabs = {
        { name = "actions", tab = tabActions, frame = actionsFrame },
        { name = "camp",    tab = tabCamp,    frame = campFrame },
        { name = "party",   tab = tabParty,   frame = partyFrame },
        { name = "roster",  tab = tabRoster,  frame = rosterFrame },
        { name = "guild",   tab = tabGuild,   frame = guildFrame },
        { name = "raid",    tab = tabRaid,    frame = raidFrame },
        { name = "log",     tab = tabLog,     frame = logFrame },
    }

    local function inRaid()
        return ((GetNumRaidMembers and GetNumRaidMembers()) or 0) > 0
    end

    -- Responsive tab bar layout: adjusts width and stride to fit 6 or 7 tabs.
    local function layoutTabs()
        local visibleCount = 0
        for _, t in ipairs(tabs) do
            if t.name ~= "raid" or inRaid() then
                visibleCount = visibleCount + 1
            end
        end
        local tabW = (visibleCount > 6) and 66 or 76
        local step = (visibleCount > 6) and 68 or 80
        local x = 0
        for _, t in ipairs(tabs) do
            if t.name ~= "raid" or inRaid() then
                t.tab:ClearAllPoints()
                t.tab:SetPoint("LEFT", tabBar, "LEFT", x, 0)
                t.tab:SetWidth(tabW)
                t.tab:Show()
                x = x + step
            else
                t.tab:Hide()
            end
        end
    end

    local function showTab(name)
        if name == "raid" and not inRaid() then name = "actions" end
        local known = false
        for _, t in ipairs(tabs) do
            if t.name == name then known = true end
        end
        if not known then name = "actions" end
        layoutTabs()
        for _, t in ipairs(tabs) do
            if t.name == name then
                t.frame:Show()
                t.tab.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
                t.tab:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
                t.tab:Disable()
            else
                t.frame:Hide()
                t.tab.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
                t.tab:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
                t.tab:Enable()
            end
        end
        if name == "roster" then
            TB.Refresh()
            if not TB.HasRosterSnapshot or not TB.HasRosterSnapshot() then
                TB.PollList(true)
            end
        elseif name == "guild" then
            if TB.RefreshGuildView then TB.RefreshGuildView() end
            if not TB.claimedSnapshotReady then
                TB.PollList(true)
            end
        elseif name == "party" then
            if TB.RefreshPartyView then TB.RefreshPartyView() end
        elseif name == "log" then
            if TB.RefreshLogView then TB.RefreshLogView() end
        elseif name == "raid" then
            if TB.RefreshRaidView then TB.RefreshRaidView() end
        else
            TB.Refresh()
        end
        TortoiseBotsDB.activeTab = name
    end

    local initial = (TortoiseBotsDB and TortoiseBotsDB.activeTab) or "actions"
    showTab(initial)
    for _, t in ipairs(tabs) do
        local tabName = t.name
        t.tab:SetScript("OnClick", function() showTab(tabName) end)
    end

    -- Joining or leaving a raid adds or removes the Raid tab.
    TB.UpdateRaidTab = function()
        local current = TortoiseBotsDB and TortoiseBotsDB.activeTab
        if current == "raid" and not inRaid() then
            showTab("actions")
        else
            layoutTabs()
        end
    end

    TB.ShowTab = showTab
    TB.tabActions, TB.tabParty, TB.tabRoster, TB.tabLog = tabActions, tabParty, tabRoster, tabLog
    TB.tabGuild, TB.guildFrame = tabGuild, guildFrame
    TB.tabRaid, TB.raidFrame = tabRaid, raidFrame
    TB.tabCamp = tabCamp
    TB.actionsFrame, TB.partyFrame, TB.rosterFrame, TB.logFrame = actionsFrame, partyFrame, rosterFrame, logFrame

    local targetWatcher = CreateFrame("Frame", "TortoiseBotsManagerTargetWatcher")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
    targetWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
    targetWatcher:RegisterEvent("UNIT_HEALTH")
    targetWatcher:SetScript("OnEvent", function()
        if event == "UNIT_HEALTH" then
            -- Only party deaths/resurrections matter (Release/Corpse run).
            if arg1 and string.find(arg1, "^party") and TB.RefreshDeathButton then TB.RefreshDeathButton() end
            return
        end
        if (event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED") and TB.UpdateRaidTab then
            TB.UpdateRaidTab()
        end
        -- The Marks panel assigns by explicit bot name, so targeting no
        -- longer affects it: refresh owners instead of hiding it.
        if TB.ccMenu and TB.ccMenu:IsVisible() and TB.ccMenu.Update then TB.ccMenu:Update() end
        TB.Refresh()
    end)
    main:Hide()
    TB.frame = main
    TB.uiReady = true
    TB.Refresh()
    -- Mini mode survives a reload: the login events fire before InitUI on
    -- first load, so restore the bar view here as well.
    if TB.GetMode and TB.GetMode() == "mini" and TB.SetMode then
        TB.SetMode("mini")
    end
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
    TB.RefreshToggleButtons()
    TB.RefreshDeathButton()
    -- Flee is a newer server intent: hide it from servers that do not
    -- advertise it rather than let the click fail.
    if TB.actionButtons.flee then
        if serverHasCap("flee") then TB.actionButtons.flee:Enable() else TB.actionButtons.flee:Disable() end
    end
    if TB.UpdateFormationPills then TB.UpdateFormationPills() end
    if TB.UpdateStancePills then TB.UpdateStancePills() end

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
    if TB.campScopeHint then
        TB.campScopeHint:SetText(botName and ("Orders go to " .. botName .. " only (your target).")
            or "Orders go to your whole party. Target one of your bots to send them to that bot only.")
    end
    if TB.RefreshMiniBar then TB.RefreshMiniBar() end
    if TB.scopeGearButton then
        if botName and serverHasCap("inventory") then TB.scopeGearButton:Show() else TB.scopeGearButton:Hide() end
    end
end

-- Party switch buttons: "AoE On" / "AoE Off" / "AoE Mixed", lamp colour.
function TB.RefreshToggleButtons()
    for key, btn in pairs(TB.toggleButtons or {}) do
        local state = TB.GetPartyToggleState and TB.GetPartyToggleState(key) or nil
        if key == "aoe" and not state and TB.aoeEnabled then state = "on" end
        local word = state == "on" and "On" or (state == "mixed" and "Mixed" or "Off")
        btn:SetText(btn.toggle.label .. " " .. word)
        if state == "on" then btn.lamp:SetTexture(0.30, 0.90, 0.45, 1)
        elseif state == "off" then btn.lamp:SetTexture(0.45, 0.45, 0.45, 1)
        else btn.lamp:SetTexture(0.95, 0.72, 0.28, 1) end
        if TB.togglePending and TB.togglePending[key] then btn:Disable() else btn:Enable() end
    end
end

-- Release while a party bot lies dead, Corpse run once they are ghosts.
function TB.DeathIntent()
    local dead, ghost = false, false
    local count = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, count do
        local unit = "party" .. i
        if UnitIsGhost and UnitIsGhost(unit) then
            ghost = true
        elseif UnitIsDead and UnitIsDead(unit) then
            dead = true
        end
    end
    if dead then return "release" end
    if ghost then return "corpse run" end
    return nil
end

function TB.RefreshDeathButton()
    local btn = TB.actionButtons and TB.actionButtons.release
    if not btn then return end
    local intent = TB.DeathIntent()
    btn:SetText(intent == "corpse run" and "Corpse run" or "Release")
    if intent then btn:Enable() else btn:Disable() end
end

-- ── raid tab model ──────────────────────────────────────────────────────────
local raidStatus = {}     -- [bot] = "molten core,onyxia" | "outdoor"
local raidCustom = {}     -- [bot] = "on" | "off"
local raidCustomAll = nil -- last party-wide custom on/off ACK

function TB.ClearRaidStatus()
    for key in pairs(raidStatus) do raidStatus[key] = nil end
    if TB.RefreshRaidView then TB.RefreshRaidView() end
end

function TB.GetRaidCustomState()
    local on, off = false, false
    for _, v in pairs(raidCustom) do
        if v == "on" then on = true else off = true end
    end
    if not on and not off then return raidCustomAll end
    if on and off then return "mixed" end
    return on and "on" or "off"
end

-- ACK routing from Comms.ParseActionMessage for the raid-only intents.
function TB.OnRaidAck(packet)
    local intent = packet.intent or ""
    local _, _, botName = string.find(packet.scope or "", "^bot:(.+)$")
    if intent == "raid status" and botName then
        raidStatus[TB.NormalizeName(botName)] = packet.executor
        local n = 0
        for _ in pairs(raidStatus) do n = n + 1 end
        if TB.SetStatus then TB.SetStatus("Raid tactics reported by " .. n .. " bot(s).", "ok") end
        if TB.RefreshRaidView then TB.RefreshRaidView() end
        return true
    end
    if intent == "raid custom status" and botName then
        raidCustom[TB.NormalizeName(botName)] = packet.executor == "off" and "off" or "on"
        if TB.SetStatus then TB.SetStatus("Custom tactics: " .. (TB.GetRaidCustomState() or "?"), "ok") end
        if TB.RefreshRaidView then TB.RefreshRaidView() end
        return true
    end
    if intent == "raid custom on" or intent == "raid custom off" then
        for key in pairs(raidCustom) do raidCustom[key] = nil end
        raidCustomAll = intent == "raid custom on" and "on" or "off"
        if TB.RefreshRaidView then TB.RefreshRaidView() end
    end
    return false
end

function TB.RefreshRaidView()
    local frame = TB.raidFrame
    if not frame then return end
    local state = TB.GetRaidCustomState()
    local word = state == "on" and "On" or (state == "off" and "Off" or (state == "mixed" and "Mixed" or "?"))
    frame.customToggle:SetText("Custom tactics: " .. word)
    if state == "on" then frame.customToggle.lamp:SetTexture(0.30, 0.90, 0.45, 1)
    elseif state == "off" then frame.customToggle.lamp:SetTexture(0.45, 0.45, 0.45, 1)
    else frame.customToggle.lamp:SetTexture(0.95, 0.72, 0.28, 1) end

    local names = {}
    for name in pairs(raidStatus) do table.insert(names, name) end
    table.sort(names)
    local lines = {}
    for i, name in ipairs(names) do
        if i > 6 then
            table.insert(lines, "|cff9d9d9d… and " .. (table.getn(names) - 6) .. " more|r")
            break
        end
        local tactics = raidStatus[name]
        if tactics == "outdoor" then tactics = "|cff9d9d9dno boss tactics loaded|r" end
        table.insert(lines, "|cffd8a657" .. name .. "|r  " .. tactics)
    end
    if table.getn(lines) == 0 then
        lines = { "|cff9d9d9dClick Check bots to see which boss tactics each bot has loaded.|r" }
    end
    frame.statusList:SetText(table.concat(lines, "\n"))
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
    if TB.guildFrame and TB.guildFrame:IsVisible() and TB.RefreshGuildView then
        TB.RefreshGuildView()
    end
end

function TB.Toggle()
    if not TB.uiReady or not TB.frame then return end
    if TB.GetMode and TB.GetMode() == "mini" and TB.ToggleMiniBar then
        TB.ToggleMiniBar()
        return
    end
    if TB.frame:IsVisible() then
        TB.frame:Hide()
    else
        TB.frame:Show()
        TB.Refresh()
        TB.PollList(true)
    end
end
