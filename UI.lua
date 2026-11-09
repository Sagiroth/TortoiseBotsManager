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
    rebuff   = "Bots re-cast missing group buffs.",
    ["totem party drop"] = "Shaman bots drop totems.",
    downtime = "Send this alt to its class trainer, vendor and repair, then back to you.",
    ["strategy +grind"] = "Bots grind on their own.",
    ["strategy reset"] = "Strategy changes back to defaults.",
}

function TB.ActionTooltip(intent)
    return ACTION_TOOLTIPS[intent]
end

-- Title line (the button label) plus a wrapped description.
local function setButtonTooltip(button, text, title)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local binding = this.bindingIntent and TB.BindingText and TB.BindingText(this.bindingIntent) or nil
        if title then
            GameTooltip:SetText(binding and (title .. " (" .. binding .. ")") or title)
            GameTooltip:AddLine(text, 0.9, 0.9, 0.9, 1)
        else
            local shown = binding and (text .. " (" .. binding .. ")") or text
            GameTooltip:SetText(shown)
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
    CARD_ENGAGE_H = 48,
    CARD_PULL_H   = 68,
    CARD_MOVE_H   = 72,
    CARD_SWITCH_H = 48,
    CARD_TACTIC_H = 48,
    CARD_REST_H   = 116,
    CARD_FORM_H   = 100,
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
    TB.ApplySurface(card, "card")

    if titleText then
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        title:SetText(titleText)
        TB.SetTextColor(title, opts.titleColor or color("title"))
        card.title = title
    end

    if opts.line then
        local line = card:CreateTexture(nil, "ARTWORK")
        line:SetTexture(1, 1, 1, 0.06)
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
    if not opts.template then TB.StyleButton(button) end
    button:SetWidth(width or 110)
    button:SetHeight(height or 26)
    if opts.x or opts.y or opts.point or opts.relTo then
        button:SetPoint(opts.point or "TOPLEFT", opts.relTo or parent, opts.relPoint or "TOPLEFT", opts.x or 0, opts.y or 0)
    end
    if label then
        button:SetText(label)
    end
    if opts.intent then button.bindingIntent = opts.intent end

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

    -- With an icon at the left, centre the label in the space beside it.
    if (opts.icon or opts.raidIcon) and button.GetFontString and (width or 110) >= 70 then
        local fs = button:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", button, "CENTER", 9, 0)
        end
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
    -- A mode: outlined, and the picked one filled gold (still clickable,
    -- so it never looks like a disabled action).
    pill.flatKind = "mode"
    pill.baseLabel = label
    TB.PaintButton(pill)
    function pill:SetActive(active)
        TB.SetButtonActive(self, active)
        if self.baseLabel then
            self:SetText(active and ("|cffffffff" .. self.baseLabel .. "|r") or self.baseLabel)
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

    local minus = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
    minus:SetWidth(22); minus:SetHeight(opts.height or 18)
    minus:SetPoint("LEFT", row, "LEFT", 0, 0)
    minus:SetText("-")

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    label:SetWidth(opts.labelWidth or 60)
    label:SetJustifyH("CENTER")

    local plus = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
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

-- A list line's zebra stripe: every other row a shade lighter.
function TB.UI.StripeRow(row, index)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture(1, 1, 1, math.mod(index, 2) == 1 and 0.035 or 0.012)
    row.stripe = bg
    return bg
end

-- A tab's heading: a small uppercase title in the section gold, with an
-- optional muted note after it.
function TB.UI.CreateHeading(parent, text, note, x, y)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 2, y or -3)
    title:SetText(string.upper(text))
    TB.SetTextColor(title, color("title"))
    local sub
    if note then
        sub = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("LEFT", title, "RIGHT", 8, 0)
        sub:SetText(note)
        TB.SetTextColor(sub, color("faint"))
    end
    return title, sub
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
    parent:SetClampedToScreen(true)
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
    TB.ApplySurface(parent, "window")
    TB.AddWindowHeader(parent, 34)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerFrame") end

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(24); icon:SetHeight(24)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD or 10, -6)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    TB.StyleTitle(title, 14)
    TB.versionTitle = title
    if TB.RefreshVersionLine then TB.RefreshVersionLine() else
        title:SetText("|cffd8a657Tortoise|r|cff4ecb5aBots|r |cfffff2ccManager|r  |cffffd200v"
            .. (TB.version or "?") .. "|r")
    end

    local versionLine = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    versionLine:SetPoint("TOPLEFT", parent, "TOPLEFT", (C.PAD or 10) + 32, -21)
    versionLine:SetWidth(330)
    versionLine:SetJustifyH("LEFT")
    TB.SetTextColor(versionLine, color("faint"))
    TB.versionLine = versionLine
    if TB.RefreshVersionLine then TB.RefreshVersionLine() end

    -- A warm glow behind the title, fading down the header band.
    local glow = parent:CreateTexture(nil, "BORDER")
    if not TB.SetMediaTexture(glow, "gradient") then glow:SetTexture(1, 1, 1, 0) end
    glow:SetVertexColor(0.78, 0.53, 0.14, 0.10)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -2)
    glow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -2)
    glow:SetHeight(33)

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -8, -8)

    -- Mini mode: swap this window for the small fight bar.
    local mini = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"), "mode")
    mini:SetWidth(40); mini:SetHeight(18)
    mini:SetPoint("RIGHT", close, "LEFT", -4, 0)
    mini:SetText("Mini")
    setButtonTooltip(mini, "Swap this window for a small bar with the fight buttons. Its + button brings the window back. Also /tbm mini.", "Mini mode")
    mini:SetScript("OnClick", function() TB.RequestMode("mini") end)
    TB.miniButton = mini
    -- Info: the server's version and switches (ServerInfo.lua).
    local info = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"), "mode")
    info:SetWidth(40); info:SetHeight(18)
    info:SetPoint("RIGHT", mini, "LEFT", -4, 0)
    info:SetText("Info")
    setButtonTooltip(info, "What this server has switched on: dungeon runs, hiring, world buffs and more.", "Server info")
    info:SetScript("OnClick", function() if TB.ToggleServerInfo then TB.ToggleServerInfo() end end)
    TB.infoButton = info
    -- Issue #33: the mouse-enabled drag bar spans the header corner over these
    -- buttons and eats their clicks in the 1.12 client. End the bar left of
    -- Mini and raise both buttons above it; the rest of the header still drags.
    dragBar:ClearAllPoints()
    dragBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    dragBar:SetPoint("BOTTOMRIGHT", info, "BOTTOMLEFT", -6, 0)
    close:SetFrameLevel(dragBar:GetFrameLevel() + 2)
    mini:SetFrameLevel(dragBar:GetFrameLevel() + 2)
    info:SetFrameLevel(dragBar:GetFrameLevel() + 2)

end
-- Class filter: two compact rows of 5 small chips on their own row under the
-- search box (roster frame is 480 wide: 5 x (88 + 4) + 6 + 6 = 472).
local CLASS_CHIP_IDS = { nil, 1, 2, 3, 4, 5, 7, 8, 9, 11 }

local function classChipLabel(classId)
    if classId == nil then return "All" end
    if classId == 6 then return "DK" end
    local name = (C.CLASS_NAMES and C.CLASS_NAMES[classId]) or ("#" .. tostring(classId))
    return name
end

function TB.PaintClassChips()
    for _, chip in ipairs(TB.classChips or {}) do
        if chip.SetActive then chip:SetActive(TB.classFilter == chip.classId) end
    end
end

-- Class filter: "All" plus one icon chip per class on a single row under
-- the search box; the picked chip is filled gold, the rest dimmed.
local function createRosterClassChips(parent)
    local chips = {}
    local x = 0
    for i = 1, table.getn(CLASS_CHIP_IDS) do
        local id = CLASS_CHIP_IDS[i]
        local width = (id == nil) and 34 or 24
        local chip = TB.UI.CreateTogglePill(parent, (id == nil) and "All" or nil, width, 20, {
            point = "TOPLEFT",
            x = x,
            y = -24,
            tip = (id == nil) and "Show every class" or ("Show only " .. ((C.CLASS_NAMES and C.CLASS_NAMES[id]) or "this class") .. " bots"),
            tipTitle = classChipLabel(id),
            onClick = function()
                TB.classFilter = id
                TB.PaintClassChips()
                TB.Refresh()
            end,
        })
        if id ~= nil then
            local icon = chip:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(16); icon:SetHeight(16)
            icon:SetPoint("CENTER", chip, "CENTER", 0, 0)
            TB.SetClassIcon(icon, id)
            chip.icon = icon
            local setActive = chip.SetActive
            function chip:SetActive(active)
                setActive(self, active)
                if self.icon and self.icon.SetAlpha then self.icon:SetAlpha(active and 1 or 0.6) end
            end
        end
        chip.classId = id
        table.insert(chips, chip)
        x = x + width + 2
    end
    local caption = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caption:SetPoint("LEFT", chips[table.getn(chips)], "RIGHT", 8, 0)
    caption:SetText("Filter by class")
    TB.SetTextColor(caption, color("faint"))
    TB.classChips = chips
    TB.PaintClassChips()
    return chips
end

CreateFilterRow = function(parent)
    local search = CreateFrame("EditBox", "TortoiseBotsManagerSearch", parent, "InputBoxTemplate")
    search:SetWidth(180); search:SetHeight(20)
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search
    TB.StyleEditBox(search, "Search by name")

    local clear = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"), "mode")
    clear:SetWidth(42); clear:SetHeight(20)
    clear:SetPoint("LEFT", search, "RIGHT", 4, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
        TB.filterText = ""
        TB.Refresh()
    end)
    TB.searchClear = clear

    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -5)
    count:SetWidth(200)
    count:SetJustifyH("RIGHT")
    TB.SetTextColor(count, color("muted"))
    TB.countLabel = count
    createRosterClassChips(parent)
end

-- Clickable roster header: each button sorts by its column, clicking again
-- reverses. The marker shows the active column and direction.
local function paintRosterHeaders(parent)
    local sort = TB.rosterSort or { key = "status", dir = 1 }
    -- Buttons own their text through the client FontString; the created
    -- label keeps the column width while the button frames the click area.
    for _, btn in ipairs(parent.headerBtns or {}) do
        local fs = btn.headerLabel
        if fs then
            if sort.key == btn.sortKey then
                fs:SetText(string.upper(btn.headerText) .. (sort.dir == 1 and " ^" or " v"))
                TB.SetTextColor(fs, color("gold"))
            else
                fs:SetText(string.upper(btn.headerText))
                TB.SetTextColor(fs, color("faint"))
            end
        end
    end
end

function TB.PaintRosterHeaders()
    if TB.rosterFrame then paintRosterHeaders(TB.rosterFrame) end
end

local function createRosterColumnHeaders(parent)
    local checkAll = CreateFrame("CheckButton", "TortoiseBotsManagerCheckAll", parent, "UICheckButtonTemplate")
    checkAll:SetWidth(20); checkAll:SetHeight(20)
    checkAll:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -48)
    TB.StyleCheckButton(checkAll)
    setButtonTooltip(checkAll, "Select or deselect all bots")
    checkAll:SetScript("OnClick", function()
        local isChecked = this:GetChecked() and true or false
        TB.SelectAllRoster(isChecked)
    end)
    TB.checkAll = checkAll

    local left = 46
    local headers = {
        { text = "Name", width = (C.ROSTER_NAME_W or 112) - 17, sortKey = "name" },
        { text = "Class", width = C.ROSTER_CLASS_W or 70, sortKey = "class" },
        { text = "Status", width = C.ROSTER_STATUS_W or 138, sortKey = "status" },
        { text = "Last location", width = 88, sortKey = nil },
    }
    parent.headerBtns = {}
    local x = left
    for _, header in ipairs(headers) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -48)
        btn:SetWidth(header.width)
        btn:SetHeight(16)
        btn:RegisterForClicks("LeftButtonUp")
        btn:EnableMouse(true)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        fs:SetWidth(header.width)
        fs:SetJustifyH("LEFT")
        if header.sortKey then
            btn.sortKey = header.sortKey
            setButtonTooltip(btn, "Sort by " .. string.lower(header.text))
            btn:SetScript("OnClick", function()
                if TB.SetRosterSort then TB.SetRosterSort(this.sortKey) end
            end)
        else
            btn:EnableMouse(false)
        end
        table.insert(parent.headerBtns, btn)
        btn.headerText = header.text
        btn.headerLabel = fs
        x = x + header.width + (C.GAP_BTN or 4)
    end
    paintRosterHeaders(parent)
end

CreateScroll = function(parent)
    createRosterColumnHeaders(parent)
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -68)
    -- The scroll bar hangs 6px right of the frame: keep frame + bar
    -- inside the content width so the bar never leaves the window.
    scroll:SetWidth(W - (C.PAD or 10) * 2 - 22)
    scroll:SetHeight(ROW_N * ROW_H + 4)
    scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh) end)
    TB.scroll = scroll

    local rows = {}
    for i = 1, ROW_N do table.insert(rows, CreateRow(parent, scroll, i)) end
    TB.rows = rows
end

CreateRow = function(parent, scroll, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(W - (C.PAD or 10) * 2 - 22)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(index - 1) * ROW_H)
    TB.ApplySurface(row, "row")
    row:EnableMouse(true)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetWidth(20); row.check:SetHeight(20)
    row.check:SetPoint("LEFT", row, "LEFT", 5, 0)
    TB.StyleCheckButton(row.check)
    row.check:SetScript("OnClick", function()
        local entry = this:GetParent().entry
        if entry then TB.ToggleRosterSelection(entry.name, this:GetChecked() and true or false) end
    end)

    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetWidth(16); row.classIcon:SetHeight(16)
    row.classIcon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

    local nameWidth = (C.ROSTER_NAME_W or 112) - 17
    local classWidth = C.ROSTER_CLASS_W or 70
    local statusWidth = C.ROSTER_STATUS_W or 138
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.classIcon, "RIGHT", 3, 0)
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
    row.location:SetWidth(88)
    row.location:SetJustifyH("LEFT")
    TB.SetTextColor(row.location, color("muted"))

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetTexture(1, 1, 1, 0.04)

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
    bar:SetPoint("TOPLEFT", TB.scroll, "BOTTOMLEFT", 0, -6)
    bar:SetWidth(W - (C.PAD or 10) * 2)
    bar:SetHeight(58)

    -- Top line: how many are picked, and the two group-wide helpers that
    -- need no selection. Bottom line: the five selection actions, equal
    -- width across the bar.
    local selection = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selection:SetPoint("LEFT", bar, "LEFT", 2, 15)
    selection:SetWidth(150)
    selection:SetJustifyH("LEFT")
    TB.selectionLabel = selection
    TB.SetTextColor(selection, color("muted"))

    local function button(label, width, action, verb, tip, kind)
        local b = TB.UI.CreateButton(bar, label, width, 24, {
            onClick = function() lifecycleCommand(action, verb) end,
            tip = tip,
        })
        if kind then b.flatKind = kind; TB.PaintButton(b) end
        return b
    end

    local BW, GAP = 92, 5
    local login  = button("Login", BW, "login", "add", "Log in selected offline owned bots; on an alt-bot playing alone, take it back as your companion")
    login:SetPoint("LEFT", bar, "LEFT", 0, -13)
    local logout = button("Logout", BW, "logout", "logout", "Log out selected online owned bots")
    logout:SetPoint("LEFT", login, "RIGHT", GAP, 0)
    local invite = button("Invite", BW, "invite", "invite", "Invite selected online bots not in your group")
    invite:SetPoint("LEFT", logout, "RIGHT", GAP, 0)
    local kick   = button("Kick", BW, "kick", "uninvite", "Kick selected online bots from your group", "danger")
    kick:SetPoint("LEFT", invite, "RIGHT", GAP, 0)
    local summon = button("Summon", BW, "summon", "summon", "Summon selected online bots")
    summon:SetPoint("LEFT", kick, "RIGHT", GAP, 0)
    local altsummary = TB.UI.CreateButton(bar, "Alt summary", 88, 18, {
        onClick = function()
            if TB.RequestAltSummary then TB.RequestAltSummary() end
        end,
        tip = "Ask each alt-bot playing on its own what it did while you were away. The answers appear in the Log tab, one line per alt-bot.",
    })
    altsummary.flatKind = "mode"; TB.PaintButton(altsummary)
    altsummary:SetPoint("LEFT", bar, "LEFT", W - (C.PAD or 10) * 2 - 88, 15)
    local fill = TB.UI.CreateButton(bar, "Fill party", 72, 18, {
        onClick = function()
            local names = TB.GetFillPartyNames and TB.GetFillPartyNames() or {}
            if table.getn(names) > 0 and TB.QueueRosterBatch then
                TB.QueueRosterBatch("invite", names)
            elseif TB.SetStatus then
                TB.SetStatus("No bots to fill the party.", "muted")
            end
        end,
        tip = "Invite online bots until the party is full (5). Needs no selection.",
    })
    fill.flatKind = "mode"; TB.PaintButton(fill)
    fill:SetPoint("LEFT", bar, "LEFT", W - (C.PAD or 10) * 2 - 88 - GAP - 72, 15)

    TB.lifecycleButtons = { login = login, logout = logout, invite = invite, kick = kick, summon = summon, fill = fill, altsummary = altsummary }
    TB.rosterBar = bar
    return bar
end

-- One click, whatever the view (Fight/Camp buttons, the mini bar): toggles,
-- strategies, timed pulls and the other special intents go their own way.
function TB.RunActionIntent(intent)
    if TB.PartyToggleKey and TB.PartyToggleKey(intent) then
        TB.SendPartyToggle(TB.PartyToggleKey(intent))
    elseif intent == "strategy +grind" or intent == "strategy -grind" then
        TB.SendGrindToggle()
    elseif intent == "strategy reset" then
        TB.SendStrategyCommand("reset")
    elseif string.sub(intent, 1, 9) == "strategy " and TB.SendStrategy then
        TB.SendStrategy(string.sub(intent, 10))
    elseif intent == "release" then
        TB.SendActionIntent(TB.DeathIntent and TB.DeathIntent() or "release")
    elseif intent == "pull" or intent == "pullback" then
        TB.SendActionIntent(TB.PullIntent and TB.PullIntent(intent) or intent)
    elseif string.sub(intent, 1, 7) == "stance " then
        TB.SetStance(string.sub(intent, 8))
    elseif intent == "ready" then
        TB.SendReadyCheck()
    elseif intent == "totem party drop" then
        TB.SendTotemDrop()
    elseif intent == "downtime" then
        TB.SendDowntime()
    else
        TB.SendActionIntent(intent)
    end
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
        tip = ((def and def.tip) or ACTION_TOOLTIPS[intent] or ("Send .bot action " .. intent))
            .. (def and " Right-click: pin it to the mini bar." or ""),
        tipTitle = label,
        onClick = function()
            if arg1 == "RightButton" and def and TB.ToggleMiniFavorite then
                TB.ToggleMiniFavorite(intent)
            else
                TB.RunActionIntent(intent)
            end
        end,
    })
    -- Right-click pins the action to the mini bar's favourites.
    if def then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    return button
end

TB.UI.CreateActionButton = makeActionButton

-- ── Per-card builders for Actions (Fight & Camp) ───────────────────────────

local function BuildScopeCard(parent)
    local scopeCard = CreateFrame("Frame", nil, parent)
    scopeCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scopeCard:SetWidth(W - (C.PAD or 10) * 2)
    scopeCard:SetHeight(32)
    TB.ApplySurface(scopeCard, "card")
    -- Who gets the orders: a gold edge on the left, the scope in bright text
    -- and a muted line on how to change it.
    local edge = scopeCard:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.9)
    edge:SetPoint("TOPLEFT", scopeCard, "TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", scopeCard, "BOTTOMLEFT", 1, 1)
    edge:SetWidth(2)

    local scopeIcon = scopeCard:CreateTexture(nil, "ARTWORK")
    scopeIcon:SetWidth(20); scopeIcon:SetHeight(20)
    scopeIcon:SetPoint("LEFT", scopeCard, "LEFT", 9, 0)
    scopeIcon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    scopeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    TB.scopeIcon = scopeIcon

    local hint = scopeCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("LEFT", scopeIcon, "RIGHT", 8, 0)
    hint:SetJustifyH("LEFT")
    TB.scopeHint = hint
    TB.SetTextColor(hint, color("text"))

    local note = scopeCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("LEFT", hint, "RIGHT", 8, 0)
    note:SetWidth(250)
    note:SetJustifyH("LEFT")
    TB.SetTextColor(note, color("faint"))
    TB.scopeNote = note

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
    ccMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ccMenu:EnableMouse(true)
    TB.ApplyBackdrop(ccMenu, 0.98, 1.0)

    TB.AddWindowHeader(ccMenu, 20)
    local ccTitle = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ccTitle:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -6)
    ccTitle:SetText("CC MARKS")
    TB.SetTextColor(ccTitle, color("title"))

    local ccHint = ccMenu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccHint:SetPoint("TOPLEFT", ccMenu, "TOPLEFT", 8, -24)
    ccHint:SetWidth(254)
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

        local clearButton = TB.UI.CreateButton(row, "Clear", 46, 20, {
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

    local closeBtn = CreateFrame("Button", nil, ccMenu, "UIPanelCloseButton")
    TB.StyleCloseButton(closeBtn, -3, -3, 16)
    closeBtn:SetScript("OnClick", function() TB.ToggleCcMenu() end)
    ccMenu.closeButton = closeBtn

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
                ccMenu:SetPoint("TOPRIGHT", buttons.ccMoon, "BOTTOMRIGHT", 0, -4)
            end
            ccMenu:Update()
        end
    end
    TB.ccMenu = ccMenu
    return ccMenu
end

local function BuildEngageCard(parent, buttons)
    -- Fight: Engage (attack, stop, interrupt, flee)
    local card = TB.UI.CreateCard(parent, "ENGAGE", W - (C.PAD or 10) * 2, 48, { y = -40, line = true })
    local btnY = -22
    buttons.attack    = makeActionButton(card, "attack", 110, 8, btnY)
    buttons.stop      = makeActionButton(card, "stop", 110, 126, btnY)
    buttons.interrupt = makeActionButton(card, "interrupt", 110, 244, btnY)
    buttons.flee      = makeActionButton(card, "flee", 110, 362, btnY)
    buttons.attack:SetHeight(22); buttons.stop:SetHeight(22)
    buttons.interrupt:SetHeight(22); buttons.flee:SetHeight(22)
    return card
end

local function BuildPullCard(parent, buttons)
    -- Pull & Focus: pull, pullback with timers, focus skull, cc mark cover
    -- the button row; End pull sits in the timer row as the small
    -- "stop pulling" escape next to the timing controls.
    local card = TB.UI.CreateCard(parent, "PULL & FOCUS", W - (C.PAD or 10) * 2, 68, { y = -96, line = true })
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

    buttons.endPull = makeActionButton(card, "end pull", 110, 244, -46)
    buttons.endPull:SetHeight(18)
    -- 12px icon inside the 18px button: the 3px top/bottom button bevels
    -- leave 12px of interior, so a 16px icon would bleed onto the borders.
    if buttons.endPull.icon then
        buttons.endPull.icon:SetWidth(12); buttons.endPull.icon:SetHeight(12)
    end
    buttons.focusSkull = makeActionButton(card, "focus skull", 110, 244, btnY)
    buttons.ccMoon     = makeActionButton(card, "cc moon", 110, 362, btnY)
    buttons.pull:SetHeight(22); buttons.pullback:SetHeight(22)
    buttons.focusSkull:SetHeight(22); buttons.ccMoon:SetHeight(22)
    buttons.ccMoon:SetText("CC Mark")
    buttons.ccMoon:SetScript("OnClick", function() TB.ToggleCcMenu() end)
    buttons.ccMark     = buttons.ccMoon
    addRaidIcon(buttons.focusSkull, 8)
    return card
end

local function BuildMoveCard(parent, buttons)
    -- Move: five orders plus stance pills inline on one row.
    local card = TB.UI.CreateCard(parent, "MOVE", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_MOVE_H or 76, { y = -172, line = true })
    local btnY = -24
    buttons.follow   = makeActionButton(card, "follow", 89, 8, btnY)
    buttons.stay     = makeActionButton(card, "stay", 89, 101, btnY)
    buttons.come     = makeActionButton(card, "come", 89, 194, btnY)
    buttons.hold     = buttons.come
    buttons.guard    = makeActionButton(card, "guard", 89, 287, btnY)
    buttons.free     = makeActionButton(card, "free", 89, 380, btnY)
    buttons.follow:SetHeight(20); buttons.stay:SetHeight(20); buttons.come:SetHeight(20)
    buttons.guard:SetHeight(20); buttons.free:SetHeight(20)
    TB.stancePills = {}
    local stanceIds = { "near", "tank", "turnback", "behind" }
    local stanceLabels = { near = "Near", tank = "Tank", turnback = "Turnback", behind = "Behind" }
    -- The melee stance pills get a caption so the row reads as a choice.
    local stanceCaption = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stanceCaption:SetPoint("TOPLEFT", card, "TOPLEFT", 9, -51)
    stanceCaption:SetWidth(56)
    stanceCaption:SetJustifyH("LEFT")
    stanceCaption:SetText("Melee")
    TB.SetTextColor(stanceCaption, color("muted"))
    card.stanceCaption = stanceCaption
    for i, id in ipairs(stanceIds) do
        local def = TB.GetActionDefinition and TB.GetActionDefinition("stance " .. id)
        local label = stanceLabels[id] or id
        local btn = TB.UI.CreateTogglePill(card, label, 98, 20, {
            x = 65 + (i - 1) * 102,
            y = -46,
            tip = ((def and def.tip) or (TB.ActionTooltip and TB.ActionTooltip("stance " .. id)) or "")
                .. " Right-click: pin it to the mini bar.",
            tipTitle = (label .. " stance"),
            onClick = function()
                if arg1 == "RightButton" and TB.ToggleMiniFavorite then
                    TB.ToggleMiniFavorite("stance " .. id)
                else
                    TB.SetStance(id)
                end
            end,
        })
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        TB.stancePills[id] = btn
    end
    TB.UpdateStancePills()
    return card
end

local function BuildSwitchesCard(parent, buttons)
    -- Party switches: state comes from the server (TBM:BOTSTATE) and shows
    -- as the button's look: lit gold when on, dimmed when off, gold text
    -- with "~" when the bots disagree. One row of five compact buttons.
    local card = TB.UI.CreateCard(parent, "PARTY SWITCHES", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_SWITCH_H or 48, { y = -252, line = true })
    local btnY = -22
    TB.toggleButtons = {}
    local switchIdx = 1
    for _, def in ipairs(C.ACTION_DEFINITIONS or {}) do
        if def.section == "switch" then
            local btn = makeActionButton(card, def.intent, 89, 8 + (switchIdx - 1) * 93, btnY)
            btn:SetHeight(22)
            if btn.icon then btn.icon:Hide() end
            btn.toggle = { key = def.toggle, intent = def.intent, label = def.label, tip = def.tip }
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
    local card = TB.UI.CreateCard(parent, "TACTICS", W - (C.PAD or 10) * 2, TB.UI.Grid.CARD_TACTIC_H or 48, { y = -308, line = true })
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
    -- Camp chores: Rest, ready, repair, sell, train, release, rebuff, reset, downtime.
    local card = TB.UI.CreateCard(campFrame, "REST, REPAIR & TRAIN", W - (C.PAD or 10) * 2, 146, { y = -18, line = true })
    local btnY = -24
    -- Rows by errand: recover, town chores, fixes; Downtime (own alts
    -- only) gets the last row with a line saying what it does.
    buttons.rest    = makeActionButton(card, "rest", 150, 8, btnY)
    buttons.ready   = makeActionButton(card, "ready", 150, 165, btnY)
    buttons.rebuff  = makeActionButton(card, "rebuff", 150, 322, btnY)
    buttons.repair  = makeActionButton(card, "repair", 150, 8, -54)
    buttons.sell    = makeActionButton(card, "sell", 150, 165, -54)
    buttons.learn   = makeActionButton(card, "learn", 150, 322, -54)
    buttons.release = makeActionButton(card, "release", 150, 8, -84)
    buttons.release.tooltipExtra = function()
        if TB.DeathIntent and TB.DeathIntent() == "corpse run" then
            return "Now: ghosts run back to their corpses."
        end
        return nil
    end
    buttons.resetTactics = makeActionButton(card, "strategy reset", 150, 165, -84)
    buttons.totem = makeActionButton(card, "totem party drop", 150, 322, -84)
    buttons.downtime = makeActionButton(card, "downtime", 150, 8, -114)
    local downtimeNote = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    downtimeNote:SetPoint("LEFT", buttons.downtime, "RIGHT", 10, 0)
    downtimeNote:SetWidth(296)
    downtimeNote:SetJustifyH("LEFT")
    downtimeNote:SetText("Own alts: trainer, vendor and repair, then back to you.")
    TB.SetTextColor(downtimeNote, color("faint"))
    card.downtimeNote = downtimeNote
    return card
end

local function BuildFormationCard(campFrame)
    -- Formation pills with a line describing the active one, two rows of five.
    local card = TB.UI.CreateCard(campFrame, "FORMATION", W - (C.PAD or 10) * 2, 100, { y = -168, line = true })
    local pills = {}
    local formationTips = {}
    for i, def in ipairs(C.FORMATIONS or {}) do
        local id = def.id
        local row = (i > 5) and 1 or 0
        local col = (i > 5) and (i - 6) or (i - 1)
        formationTips[id] = def.label .. ": " .. def.tip
        local btn = TB.UI.CreateTogglePill(card, def.label, 90, 20, {
            x = 8 + col * 93,
            y = -26 - row * 24,
            tip = def.tip .. " Applies to the whole party, or only the targeted bot.",
            tipTitle = def.label,
            onClick = function()
                TB.SetFormation(id)
            end,
        })
        pills[id] = btn
    end
    local formDesc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formDesc:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -78)
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

local function BuildQuestsCard(campFrame, buttons)
    -- Party quests: accept/share loop over grouped bots, grind toggles the
    -- autonomous grind strategy for the whole party.
    local card = TB.UI.CreateCard(campFrame, "QUESTS", W - (C.PAD or 10) * 2, 58, { y = -272, line = true })
    buttons.acceptQuest = TB.UI.CreateButton(card, "Accept", 150, 26, {
        x = 8, y = -24,
        icon = "Interface\\Icons\\INV_Misc_Book_08",
        tip = "Accept the quest you were offered on every grouped bot.",
        tipTitle = "Accept",
        onClick = function()
            TB.SendQuestOrders("accept")
        end,
    })
    buttons.shareQuest = TB.UI.CreateButton(card, "Share", 150, 26, {
        x = 165, y = -24,
        icon = "Interface\\Icons\\INV_Letter_15",
        tip = "Share your tracked quests with every grouped bot.",
        tipTitle = "Share",
        onClick = function()
            TB.SendQuestOrders("share")
        end,
    })
    buttons.grind = makeActionButton(card, "strategy +grind", 150, 322, -24)
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
TB.UI.BuildQuestsCard    = BuildQuestsCard

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
    TB.fightCards = {
        engage = BuildEngageCard(frame, buttons),
        pull = BuildPullCard(frame, buttons),
        move = BuildMoveCard(frame, buttons),
        switches = BuildSwitchesCard(frame, buttons),
        tactics = BuildTacticsCard(frame, buttons),
    }

    -- Build cards for Camp view
    BuildRestCard(campFrame, buttons)
    BuildFormationCard(campFrame)
    BuildQuestsCard(campFrame, buttons)

    local campTip = campFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    campTip:SetPoint("TOPLEFT", campFrame, "TOPLEFT", 6, -342)
    campTip:SetWidth(468); campTip:SetJustifyH("LEFT")
    campTip:SetText("Gear, bags and per-bot habits: bag icon on the Party tab, or target a bot and use Gear & bags on Fight.")
    TB.SetTextColor(campTip, color("muted"))
    TB.campFrame = campFrame
    TB.actionButtons = buttons
    TB.actions = buttons
    return frame
end

CreateStatusBar = function(parent)
    -- Footer: a darker strip under a hairline, the last reply on the left.
    local strip = parent:CreateTexture(nil, "BACKGROUND")
    strip:SetTexture(0, 0, 0, 0.28)
    strip:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 1, 1)
    strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    strip:SetHeight(23)
    local line = parent:CreateTexture(nil, "BORDER")
    local hl = TB.Theme("hairline")
    line:SetTexture(hl[1], hl[2], hl[3], hl[4])
    line:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 0)
    line:SetHeight(1)
    local dot = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", C.PAD or 10, 7)
    dot:SetText("|cff757575○|r")
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

    CreateStatusBar(main)

    -- Tab bar: flat text tabs spread across the full width; the open tab is
    -- bright with a gold underline, the others muted. One hairline under
    -- the whole bar separates navigation from content.
    local tabBar = CreateFrame("Frame", nil, main)
    tabBar:SetPoint("TOPLEFT", main, "TOPLEFT", C.PAD or 10, -38)
    tabBar:SetWidth(W - (C.PAD or 10) * 2)
    tabBar:SetHeight(24)
    local tabLine = tabBar:CreateTexture(nil, "BACKGROUND")
    tabLine:SetTexture(1, 1, 1, 0.08)
    tabLine:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabLine:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabLine:SetHeight(1)

    local function makeTab(label, offset)
        local button = CreateFrame("Button", nil, tabBar)
        button:SetWidth(76); button:SetHeight(24)
        button:SetPoint("LEFT", tabBar, "LEFT", offset, 0)
        button:EnableMouse(true); button:RegisterForClicks("LeftButtonUp")
        local fill = button:CreateTexture(nil, "BACKGROUND")
        if not TB.SetMediaTexture(fill, "gradient") then fill:SetTexture(1, 1, 1, 1) end
        fill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, 0)
        fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 0)
        fill:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 0.0)
        button.fill = fill
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        if text.SetFont then text:SetFont("Fonts\\FRIZQT__.TTF", 11) end
        text:SetText(label)
        button.text = text
        local underline = button:CreateTexture(nil, "ARTWORK")
        underline:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
        underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 0)
        underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 0)
        underline:SetHeight(2)
        underline:Hide()
        button.underline = underline
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 1, 0)
        highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        highlight:SetTexture(1, 1, 1, 0.05)
        return button
    end

    -- Tabs by kind of work: Fight (in a pull), Camp (between pulls), Party
    -- (who does what), Roster (who is logged in), Guild (claimed bots), Raid (raid only),
    -- Dungeon (only while the server runs the dungeon run leader), Loot (only
    -- while the server keeps loot history), Log.
    local tabActions = makeTab("Fight", 0)
    local tabCamp = makeTab("Camp", 80)
    local tabParty = makeTab("Party", 160)
    local tabGuild = makeTab("Guild", 240)
    local tabRoster = makeTab("Roster", 320)
    local tabRaid = makeTab("Raid", 400)
    local tabDungeon = makeTab("Dungeon", 480)
    local tabLoot = makeTab("Loot", 560)
    local tabLog = makeTab("Log", 640)
    local content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    content:SetWidth(W - (C.PAD or 10) * 2)
    content:SetHeight(360)

    local actionsFrame = CreateActions(content)
    local campFrame = TB.campFrame
    local rosterFrame = CreateFrame("Frame", nil, content)
    rosterFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    rosterFrame:SetWidth(W - (C.PAD or 10) * 2)
    rosterFrame:SetHeight(325)
    CreateFilterRow(rosterFrame)
    CreateScroll(rosterFrame)
    CreateRosterBar(rosterFrame)
    TB.rosterFrame = rosterFrame

    local function CreatePartyView(parent)
        local partyFrame = CreateFrame("Frame", nil, parent)
        partyFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        partyFrame:SetWidth(W - (C.PAD or 10) * 2)
        partyFrame:SetHeight(325)

        local title = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", partyFrame, "TOPLEFT", 4, -3)
        title:SetText("PARTY ROLES")
        TB.SetTextColor(title, color("title"))

        local subtitle = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
        subtitle:SetText("Pick each bot's role · click a row to target it")
        TB.SetTextColor(subtitle, color("faint"))
        partyFrame.title = title
        partyFrame.subtitle = subtitle

        local emptyMsg = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyMsg:SetPoint("CENTER", partyFrame, "CENTER", 0, -20)
        emptyMsg:SetWidth(380)
        emptyMsg:SetJustifyH("CENTER")
        emptyMsg:SetText("|cff888888No other party members.\nInvite your bots from the Roster tab to manage party roles.|r")
        partyFrame.emptyMsg = emptyMsg

        local inviteBtn = TB.UI.CreateButton(partyFrame, "Invite from Roster", 140, 22, {
            tip = "Open the Roster tab to invite your bots into the party.",
            tipTitle = "Invite from Roster",
            onClick = function()
                if TB.ShowTab then TB.ShowTab("roster") end
            end,
        })
        inviteBtn:SetPoint("CENTER", partyFrame, "CENTER", 0, -62)
        partyFrame.inviteButton = inviteBtn

        -- Row: class icon, name and level on the left; the role picker as
        -- one segmented control; on the right the CC mark, Summon and the
        -- gear & bags button, all on the row's centre line.
        local rows = {}
        for i = 1, 5 do
            local row = CreateFrame("Frame", nil, partyFrame)
            row:SetWidth(W - (C.PAD or 10) * 2)
            row:SetHeight(52)
            row:SetPoint("TOPLEFT", partyFrame, "TOPLEFT", 0, -(i - 1) * 56 - 22)
            row:EnableMouse(true)
            TB.ApplySurface(row, "row")

            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetWidth(2)
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
            row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

            local classIcon = row:CreateTexture(nil, "ARTWORK")
            classIcon:SetWidth(30); classIcon:SetHeight(30)
            classIcon:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.classIcon = classIcon

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -10)
            nameText:SetWidth(100)
            nameText:SetJustifyH("LEFT")
            row.nameText = nameText

            local descText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            descText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 48, 10)
            descText:SetWidth(100)
            descText:SetJustifyH("LEFT")
            TB.SetTextColor(descText, color("muted"))
            row.descText = descText

            local bagButton = TB.UI.CreateIconButton(row, 22, {
                point = "RIGHT",
                relTo = row,
                relPoint = "RIGHT",
                x = -10,
                y = 0,
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

            local summonButton = TB.UI.CreateIconButton(row, 22, {
                point = "RIGHT",
                relTo = row,
                relPoint = "RIGHT",
                x = -36,
                y = 0,
                icon = "Interface\\Icons\\Spell_Shadow_Twilight",
                texCoord = { 0.08, 0.92, 0.08, 0.92 },
                onClick = function()
                    if row.partyName and row.partyUnit ~= "player" then
                        TB.SendBotCommand(TB.BuildCommand("summon", row.partyName))
                    end
                end,
                tipTitle = "Summon",
                tip = "Summon this bot to you. Works out of combat and takes 3 seconds.",
            })
            summonButton:Hide()
            row.summonButton = summonButton

            local ccIcon = row:CreateTexture(nil, "ARTWORK")
            ccIcon:SetWidth(18); ccIcon:SetHeight(18)
            -- The CC mark keeps its own slot left of Summon, so no role
            -- picker (four-role Druids included) can cover it.
            ccIcon:SetPoint("RIGHT", row, "RIGHT", -64, 0)
            ccIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            ccIcon:Hide()
            row.ccIcon = ccIcon

            -- Kept for older callers; the mark icon speaks for itself.
            local ccLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ccLabel:SetPoint("RIGHT", ccIcon, "LEFT", -2, 0)
            ccLabel:SetText("CC")
            TB.SetTextColor(ccLabel, color("muted"))
            ccLabel:Hide()
            row.ccLabel = ccLabel

            local playerLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            playerLabel:SetPoint("RIGHT", row, "RIGHT", -12, 0)
            playerLabel:SetText("|cffd8a657You|r")
            row.playerLabel = playerLabel

            local roleButtons = {}
            for b = 1, 4 do
                local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                btn.smallLabel = true
                TB.StyleButton(btn)
                btn:SetWidth(74)
                btn:SetHeight(22)
                btn:SetPoint("LEFT", row, "LEFT", 150 + (b - 1) * 76, 0)
                -- Roles are a choice: outlined, the picked one filled gold.
                btn.flatKind = "mode"
                TB.PaintButton(btn)
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

        partyFrame.summonPartyBtn = TB.UI.CreateButton(partyFrame, "Summon Party", 100, 22, {
            point = "TOPLEFT",
            x = 6,
            y = -306,
            onClick = function()
                local names = {}
                local count = (GetNumPartyMembers and GetNumPartyMembers()) or 0
                for i = 1, count do
                    local name = UnitName and UnitName("party" .. i)
                    if name then table.insert(names, name) end
                end
                if table.getn(names) > 0 and TB.QueueRosterBatch then
                    TB.QueueRosterBatch("summon", names)
                elseif TB.SetStatus then
                    TB.SetStatus("No bots in your party to summon.", "muted")
                end
            end,
            tip = "Summon every bot in your party to you. Works out of combat.",
        })

        partyFrame.summonRaidBtn = TB.UI.CreateButton(partyFrame, "Summon Raid", 100, 22, {
            point = "TOPLEFT",
            x = 112,
            y = -306,
            onClick = function()
                local names = {}
                local count = (GetNumRaidMembers and GetNumRaidMembers()) or 0
                for i = 1, count do
                    local name = UnitName and UnitName("raid" .. i)
                    if name and TB.GetBotState and TB.GetBotState(name) then table.insert(names, name) end
                end
                if table.getn(names) > 0 and TB.QueueRosterBatch then
                    TB.QueueRosterBatch("summon", names)
                elseif TB.SetStatus then
                    TB.SetStatus("No bots in your raid to summon.", "muted")
                end
            end,
            tip = "Summon every bot in your raid to you. Works out of combat.",
        })
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
            return TB.UI.CreateCard(raidFrame, titleText, W - (C.PAD or 10) * 2, height, { y = y, line = true })
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

-- Clickable guild headers mirror the roster ones: the marker shows the
-- active column and direction.
local function paintGuildHeaders(parent)
    local sort = TB.guildSort or { key = "level", dir = -1 }
    for _, btn in ipairs(parent.headerBtns or {}) do
        local fs = btn.headerLabel
        if fs then
            if sort.key == btn.sortKey then
                fs:SetText(string.upper(btn.headerText) .. (sort.dir == 1 and " ^" or " v"))
                TB.SetTextColor(fs, color("gold"))
            else
                fs:SetText(string.upper(btn.headerText))
                TB.SetTextColor(fs, color("faint"))
            end
        end
    end
end

function TB.PaintGuildHeaders()
    if TB.guildFrame and TB.guildFrame.headerBtns then paintGuildHeaders(TB.guildFrame) end
end

    local function CreateGuildView(parent)
        local guildFrame = CreateFrame("Frame", nil, parent)
        guildFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        guildFrame:SetWidth(W - (C.PAD or 10) * 2)
        guildFrame:SetHeight(325)

        -- Top search / count row
        local search = CreateFrame("EditBox", "TortoiseBotsManagerGuildSearch", guildFrame, "InputBoxTemplate")
        search:SetWidth(150); search:SetHeight(20)
        search:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 0, 0)
        search:SetAutoFocus(false)
        search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
        search:SetScript("OnTextChanged", function()
            TB.guildFilterText = this:GetText() or ""
            if TB.RefreshGuildView then TB.RefreshGuildView() end
        end)
        guildFrame.searchBox = search
        TB.StyleEditBox(search, "Search guild bots")

        local clear = TB.StyleButton(CreateFrame("Button", nil, guildFrame, "UIPanelButtonTemplate"), "mode")
        clear:SetWidth(42); clear:SetHeight(20)
        clear:SetPoint("LEFT", search, "RIGHT", 4, 0)
        clear:SetText("Clear")
        clear:SetScript("OnClick", function()
            search:SetText("")
            search:ClearFocus()
            TB.guildFilterText = ""
            if TB.RefreshGuildView then TB.RefreshGuildView() end
        end)

        local count = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetPoint("TOPRIGHT", guildFrame, "TOPRIGHT", -2, -5)
        count:SetWidth(240)
        count:SetJustifyH("RIGHT")
        TB.SetTextColor(count, color("muted"))
        guildFrame.countLabel = count

        -- Column headers
        local checkAll = CreateFrame("CheckButton", "TortoiseBotsManagerGuildCheckAll", guildFrame, "UICheckButtonTemplate")
        checkAll:SetWidth(20); checkAll:SetHeight(20)
        checkAll:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 4, -44)
        TB.StyleCheckButton(checkAll)
        setButtonTooltip(checkAll, "Select or deselect all claimed bots")
        checkAll:SetScript("OnClick", function()
            local isChecked = this:GetChecked() and true or false
            TB.SelectAllClaimed(isChecked)
        end)
        guildFrame.checkAll = checkAll

        local headers = {
            { text = "Name", width = 80, x = 46, sortKey = "name" },
            { text = "Level", width = 64, x = 128, sortKey = "level" },
            { text = "Gear", width = 52, x = 194, sortKey = nil },
            { text = "Status", width = 70, x = 248, sortKey = "status" },
            { text = "Role · Order", width = 134, x = 324, sortKey = nil },
        }
        guildFrame.headerBtns = {}
        for _, h in ipairs(headers) do
            local btn = CreateFrame("Button", nil, guildFrame)
            btn:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", h.x, -44)
            btn:SetWidth(h.width)
            btn:SetHeight(16)
            btn:RegisterForClicks("LeftButtonUp")
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -5)
            fs:SetWidth(h.width)
            fs:SetJustifyH("LEFT")
            btn.headerText = h.text
            btn.headerLabel = fs
            if h.sortKey then
                btn.sortKey = h.sortKey
                setButtonTooltip(btn, "Sort by " .. string.lower(h.text))
                btn:SetScript("OnClick", function()
                    if TB.SetGuildSort then TB.SetGuildSort(this.sortKey) end
                end)
            else
                btn:EnableMouse(false)
            end
            table.insert(guildFrame.headerBtns, btn)
        end
        paintGuildHeaders(guildFrame)

        -- Guild bank access bots can reach: rank, bank tabs, gold. Red when
        -- a bank tab is denied or gold is off; grey when the server leaves
        -- ranks alone or no bank is unlocked yet.
        local access = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        access:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 2, -29)
        access:SetWidth(W - (C.PAD or 10) * 2 - 130)
        access:SetJustifyH("LEFT")
        TB.SetTextColor(access, color("muted"))
        guildFrame.accessLine = access

        local rankBtn = TB.StyleButton(CreateFrame("Button", nil, guildFrame, "UIPanelButtonTemplate"), "mode")
        rankBtn:SetWidth(56); rankBtn:SetHeight(18)
        rankBtn:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", W - (C.PAD or 10) * 2 - 56, -25)
        rankBtn:SetText("Rank")
        setButtonTooltip(rankBtn, "Change the guild rank bots get", "Bots' rank")
        rankBtn:SetScript("OnClick", function()
            if TB.OpenOrderRankMenu then TB.OpenOrderRankMenu(this) end
        end)
        guildFrame.rankBtn = rankBtn
        local GUILD_ROW_H = 36
        local GUILD_ROW_N = 7
        local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerGuildScroll", guildFrame, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 0, -64)
        scroll:SetWidth(W - (C.PAD or 10) * 2 - 22)
        scroll:SetHeight(GUILD_ROW_N * GUILD_ROW_H + 4)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(GUILD_ROW_H, TB.RefreshGuildView)
        end)
        guildFrame.scroll = scroll

        -- The row tooltip body lives in one function so a late step history
        -- (TBM:ORDER_STEPS_END) can redraw the tooltip of the row under the
        -- cursor. A resting hover arms a 0.4 s dwell timer (cancelled on
        -- leave) before asking the server for that bot's steps, and only
        -- when the bot has an order; the repaint passes noRequest so it
        -- never sends a second request.
        local ensureStepsDwellFrame -- defined below, called from the tooltip
        function TB.ShowGuildRowTooltip(row, noRequest)
            local entry = row and row.entry
            if not entry then return end
            TB._guildTipRow = row
            TB._guildTipOwner = row
            if not noRequest and TB.GetBotOrder and TB.GetBotOrder(entry.name)
                and TB.RequestOrderSteps then
                TB._stepsDwell = { name = entry.name, at = (GetTime and GetTime()) or 0 }
                ensureStepsDwellFrame()
            end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
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
            -- Row professions from the CLAIMED snapshot ride the row itself;
            -- the cached Professions snapshot stays the fallback (it carries
            -- skill max). A hover never sends a request.
            local profText = TB.ClaimedProfsLine and TB.ClaimedProfsLine(entry) or nil
            if not profText and TB.HasProfessionsCapability and TB.HasProfessionsCapability() and TB.GetProfessions then
                profText = TB.ProfessionTooltipLine and TB.ProfessionTooltipLine(entry.name) or nil
            end
            if profText then
                GameTooltip:AddLine(profText, 1, 1, 1)
            end
            if TB.GetBotOrder and TB.OrderTooltipText then
                local order = TB.GetBotOrder(entry.name)
                local orderText = order and TB.OrderTooltipText(order) or nil
                if orderText then
                    GameTooltip:AddLine(orderText, 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end

        -- Hover requests wait for a 0.4 s rest before going out; leaving the
        -- row cancels the wait. The timer frame sends at most the bot it was
        -- armed for, and RequestOrderSteps still applies its own gates.
        local STEPS_DWELL = 0.4
        local stepsDwellFrame
        function ensureStepsDwellFrame()
            if stepsDwellFrame then return end
            stepsDwellFrame = CreateFrame("Frame", "TortoiseBotsManagerStepsDwell")
            stepsDwellFrame:SetScript("OnUpdate", function()
                local dwell = TB._stepsDwell
                if not dwell then return end
                if ((GetTime and GetTime()) or 0) - (dwell.at or 0) < STEPS_DWELL then return end
                TB._stepsDwell = nil
                if TB.RequestOrderSteps then TB.RequestOrderSteps(dwell.name) end
            end)
        end

        -- A committed step list redraws the tooltip only while it still shows
        -- that bot's row; every other case is left alone.
        function TB.RepaintGuildRowTooltip(bot)
            local row = TB._guildTipRow
            if not row or not row.entry then return end
            if TB.NormalizeName(row.entry.name) ~= bot then return end
            if not row:IsVisible() then return end
            if GameTooltip.IsOwned then
                if not GameTooltip:IsOwned(row) then return end
            elseif TB._guildTipOwner ~= row then
                return
            end
            TB.ShowGuildRowTooltip(row, true)
        end

        local rows = {}
        for i = 1, GUILD_ROW_N do
            local row = CreateFrame("Frame", nil, guildFrame)
            row:SetWidth(W - (C.PAD or 10) * 2 - 22)
            row:SetHeight(GUILD_ROW_H - 2)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * GUILD_ROW_H)
            TB.ApplySurface(row, "row")
            row:EnableMouse(true)

            -- Two lines per bot: who it is on top, its order below; the
            -- buttons sit in a right-hand column, two per line.
            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetWidth(2)
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
            row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)

            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetWidth(20); row.check:SetHeight(20)
            row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
            TB.StyleCheckButton(row.check)
            row.check:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry then TB.ToggleClaimedSelection(entry.name, this:GetChecked() and true or false) end
            end)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 46, 8)
            row.name:SetWidth(80)
            row.name:SetJustifyH("LEFT")

            row.lvlClass = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.lvlClass:SetPoint("LEFT", row, "LEFT", 128, 8)
            row.lvlClass:SetWidth(64)
            row.lvlClass:SetJustifyH("LEFT")

            row.gearBadge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.gearBadge:SetPoint("LEFT", row, "LEFT", 194, 8)
            row.gearBadge:SetWidth(52)
            row.gearBadge:SetJustifyH("LEFT")

            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.status:SetPoint("LEFT", row, "LEFT", 248, 8)
            row.status:SetWidth(70)
            row.status:SetJustifyH("LEFT")

            -- Guild order line: the bot's current order and its progress
            -- (TB.OrderRowText); the Order/Cancel buttons sit at its right.
            row.orderLine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.orderLine:SetPoint("LEFT", row, "LEFT", 46, -8)
            row.orderLine:SetWidth(272)
            row.orderLine:SetJustifyH("LEFT")

            local bagBtn = TB.UI.CreateIconButton(row, 18, {
                point = "LEFT",
                relTo = row,
                relPoint = "LEFT",
                x = 25,
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

            local roleBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            roleBtn.flatKind = "mode"
            roleBtn:SetWidth(74); roleBtn:SetHeight(16)
            roleBtn:SetPoint("LEFT", row, "LEFT", 322, 8)
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

            local ordBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            ordBtn:SetWidth(44); ordBtn:SetHeight(16)
            ordBtn:SetPoint("LEFT", row, "LEFT", 322, -8)
            ordBtn:SetText("Order")
            ordBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.OpenOrderWindow then TB.OpenOrderWindow(entry.name) end
            end)
            setButtonTooltip(ordBtn, "Open the order window for this bot.", "Order")
            row.ordBtn = ordBtn

            local cancelBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            cancelBtn.flatKind = "danger"
            cancelBtn:SetWidth(50); cancelBtn:SetHeight(16)
            cancelBtn:SetPoint("LEFT", row, "LEFT", 368, -8)
            cancelBtn:SetText("Cancel")
            cancelBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.ConfirmOrderCancel then TB.ConfirmOrderCancel(entry.name) end
            end)
            setButtonTooltip(cancelBtn, "Remove this bot's current order. Cancelling also ends keep-in-stock and no-limit orders.", "Cancel order")
            row.cancelBtn = cancelBtn

            local moveBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            moveBtn:SetWidth(36); moveBtn:SetHeight(16)
            moveBtn:SetPoint("LEFT", row, "LEFT", 420, -8)
            moveBtn:SetText("Move")
            moveBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.OpenOrderReassignMenu then
                    TB.OpenOrderReassignMenu(entry.name, this)
                end
            end)
            setButtonTooltip(moveBtn, "Hand this sub-order to another guild bot.", "Reassign")
            row.moveBtn = moveBtn

            local relBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            relBtn.flatKind = "danger"
            relBtn:SetWidth(58); relBtn:SetHeight(16)
            relBtn:SetPoint("LEFT", row, "LEFT", 398, 8)
            relBtn:SetText("Release")
            relBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.ConfirmReleaseClaimedBot then
                    TB.ConfirmReleaseClaimedBot(entry.name)
                end
            end)
            setButtonTooltip(relBtn, "Release this bot back to the wandering bot pool (/gkick)")
            row.relBtn = relBtn

            -- Enchant Meet: same-slot twin of Release (only one shows). The
            -- giver's own order row shows Meet until the order finishes; the
            -- click sends "order <bot> meet" like the other order commands.
            local meetBtn = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
            meetBtn.flatKind = "primary"
            meetBtn:SetWidth(58); meetBtn:SetHeight(16)
            meetBtn:SetPoint("LEFT", row, "LEFT", 398, 8)
            meetBtn:SetText("Meet")
            meetBtn:SetScript("OnClick", function()
                local entry = this:GetParent().entry
                if entry and TB.SendOrderMeet then TB.SendOrderMeet(entry.name) end
            end)
            setButtonTooltip(meetBtn, "Ask the bot to walk to you for the enchant trade.", "Meet")
            meetBtn.tooltipExtra = function()
                local why = this and this.meetWhy or nil
                if why then return why end
                if this and not this.enabled and TB.OrderMeetState and this:GetParent() then
                    local entry = this:GetParent().entry
                    local order = entry and TB.GetBotOrder and TB.GetBotOrder(entry.name) or nil
                    if order then
                        local _, reason = TB.OrderMeetState(order)
                        return reason
                    end
                end
                return nil
            end
            row.meetBtn = meetBtn

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(row)
            hl:SetTexture(1, 1, 1, 0.04)

            row:SetScript("OnEnter", function() TB.ShowGuildRowTooltip(this) end)
            row:SetScript("OnLeave", function()
                TB._guildTipRow = nil
                TB._guildTipOwner = nil
                TB._stepsDwell = nil
                GameTooltip:Hide()
            end)

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
        bar:SetPoint("TOPLEFT", guildFrame, "TOPLEFT", 0, -(64 + GUILD_ROW_N * GUILD_ROW_H + 6))
        bar:SetWidth(W - (C.PAD or 10) * 2)
        bar:SetHeight(26)

        local selection = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        selection:SetPoint("LEFT", bar, "LEFT", 2, 0)
        selection:SetWidth(85)
        selection:SetJustifyH("LEFT")
        TB.SetTextColor(selection, color("muted"))
        guildFrame.selectionLabel = selection

        local inviteBtn = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
        inviteBtn:SetWidth(70); inviteBtn:SetHeight(24)
        inviteBtn:SetPoint("LEFT", bar, "LEFT", 104, 0)
        inviteBtn:SetText("Invite")
        setButtonTooltip(inviteBtn, "Invite selected online claimed bots to your party. A full party becomes a raid.")
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

        local summonBtn = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
        summonBtn:SetWidth(70); summonBtn:SetHeight(24)
        summonBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 5, 0)
        summonBtn:SetText("Summon")
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

        local syncBtn = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
        syncBtn:SetWidth(56); syncBtn:SetHeight(24)
        syncBtn:SetPoint("LEFT", summonBtn, "RIGHT", 5, 0)
        syncBtn:SetText("Sync")
        setButtonTooltip(syncBtn, "Sync claimed guild bots and roster from server")
        syncBtn:SetScript("OnClick", function()
            if TB.PollList then TB.PollList(true) end
        end)
        guildFrame.syncBtn = syncBtn

        local fillBtn = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
        fillBtn:SetWidth(68); fillBtn:SetHeight(24)
        fillBtn:SetPoint("LEFT", syncBtn, "RIGHT", 5, 0)
        fillBtn:SetText("Fill raid")
        setButtonTooltip(fillBtn, "Invite online claimed bots until the raid is full (40). Needs no selection.")
        fillBtn:SetScript("OnClick", function()
            local names = TB.GetFillRaidNames and TB.GetFillRaidNames() or {}
            if table.getn(names) > 0 then
                if TB.QueueRosterBatch then
                    TB.QueueRosterBatch("invite", names)
                else
                    for _, n in ipairs(names) do TB.SendBotCommand("invite " .. n) end
                end
            elseif TB.SetStatus then
                TB.SetStatus("No bots to fill the raid.", "muted")
            end
        end)
        guildFrame.fillBtn = fillBtn

        local orderBtn = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
        orderBtn.flatKind = "primary"
        orderBtn:SetWidth(86); orderBtn:SetHeight(24)
        orderBtn:SetPoint("LEFT", fillBtn, "RIGHT", 5, 0)
        orderBtn:SetText("Guild order")
        setButtonTooltip(orderBtn, "Pick a recipe, see which guild bots know it, then order.", "Guild order")
        orderBtn:SetScript("OnClick", function()
            if TB.OpenGuildOrderWindow then TB.OpenGuildOrderWindow() end
        end)
        guildFrame.orderBtn = orderBtn
        guildFrame.guildBar = bar
        return guildFrame
    end

    local guildFrame = CreateGuildView(content)

    local function CreateLogView(parent)
        local logFrame = CreateFrame("Frame", nil, parent)
        logFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        logFrame:SetWidth(W - (C.PAD or 10) * 2)
        logFrame:SetHeight(325)

        TB.UI.CreateHeading(logFrame, "Bot activity", "Bot messages and server replies, newest first")

        local clearBtn = TB.StyleButton(CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate"), "mode")
        clearBtn:SetWidth(56); clearBtn:SetHeight(18)
        clearBtn:SetPoint("TOPRIGHT", logFrame, "TOPRIGHT", 0, 2)
        clearBtn:SetText("Clear")
        setButtonTooltip(clearBtn, "Clear recorded activity history")
        clearBtn:SetScript("OnClick", function()
            if TB.ClearLogHistory then TB.ClearLogHistory() end
            if TB.RefreshLogView then TB.RefreshLogView() end
        end)


        local LOG_ROW_H = 18
        local LOG_ROW_N = 16
        local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerLogScroll", logFrame, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", logFrame, "TOPLEFT", 0, -22)
        scroll:SetWidth(W - (C.PAD or 10) * 2 - 22)
        scroll:SetHeight(LOG_ROW_N * LOG_ROW_H + 4)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(LOG_ROW_H, TB.RefreshLogView)
        end)
        TB.logScroll = scroll

        local rows = {}
        for i = 1, LOG_ROW_N do
            local row = CreateFrame("Frame", nil, logFrame)
            row:SetWidth(W - (C.PAD or 10) * 2 - 22)
            row:SetHeight(LOG_ROW_H)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * LOG_ROW_H)
            TB.UI.StripeRow(row, i)

            local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeText:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
            timeText:SetWidth(40)
            timeText:SetJustifyH("LEFT")
            TB.SetTextColor(timeText, color("faint"))
            row.timeText = timeText

            local tagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tagText:SetPoint("LEFT", timeText, "RIGHT", 2, 0)
            tagText:SetWidth(30)
            tagText:SetJustifyH("LEFT")
            tagText:SetText("|cffb08a48Bot|r")
            row.tagText = tagText

            local msgText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            msgText:SetPoint("LEFT", tagText, "RIGHT", 4, 0)
            msgText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            msgText:SetJustifyH("LEFT")
            msgText:SetHeight(14)
            row.msgText = msgText

            table.insert(rows, row)
        end
        TB.logRows = rows
        return logFrame
    end

    local logFrame = CreateLogView(content)
    local dungeonFrame = TB.CreateRunTab(content)
    local lootFrame = TB.CreateLootTab and TB.CreateLootTab(content) or nil

    function TB.RefreshLogView()
        if not TB.logScroll or not TB.logRows then return end
        local history = TB.GetLogHistory and TB.GetLogHistory() or {}
        local total = table.getn(history)
        local LOG_ROW_H = 18
        local LOG_ROW_N = 16
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
                TB.SetClassIcon(row.classIcon, classId)
                local movement = unit ~= "player" and TB.MovementLabel and TB.MovementLabel(name) or nil
                row.descText:SetText(lvlText .. (movement and (" · " .. movement) or (" " .. (className or ""))))
                if unit ~= "player" and TB.GetBotState and TB.GetBotState(name)
                    and TB.HasServerCapability and TB.HasServerCapability("inventory") then
                    row.bagButton:Show()
                else
                    row.bagButton:Hide()
                end
                if unit ~= "player" then
                    row.summonButton:Show()
                else
                    row.summonButton:Hide()
                end
                row.accent:SetTexture(col[1], col[2], col[3], 0.95)
                if unit == "player" then
                    row:SetBackdropColor(0.10, 0.09, 0.07, 0.96)
                else
                    local rc = TB.Theme("row")
                    row:SetBackdropColor(rc[1], rc[2], rc[3], rc[4])
                end

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
                    row.playerLabel:Show()
                else
                    row.playerLabel:Hide()
                end

                local roles = isPlayer and TB.Roles.PLAYER_ROLES or TB.Roles.GetClassRoles(classId)
                local currentRole
                if isPlayer then
                    currentRole = TB.Roles.GetPlayerRole()
                else
                    currentRole = TB.Roles.GetBotRole(name, classId)
                end
                -- One segmented control: buttons 2px apart, four-role rows
                -- narrower so the CC mark column on the right stays free.
                local roleCount = table.getn(roles)
                local roleWidth = roleCount >= 4 and 60 or 78
                local roleStep = roleWidth + 2

                for b = 1, 4 do
                    local btn = row.roleButtons[b]
                    local role = roles[b]
                    btn:ClearAllPoints()
                    btn:SetWidth(roleWidth)
                    btn:SetPoint("LEFT", row, "LEFT", 150 + (b - 1) * roleStep, 0)
                    if role then
                        local isSelected = currentRole == role.id
                        local shown = TB.Roles.ShortLabel and TB.Roles.ShortLabel(role.label) or role.label
                        if isSelected then
                            btn:SetText("|cffffffff" .. shown .. "|r")
                        else
                            btn:SetText("|cff9a978f" .. shown .. "|r")
                        end
                        TB.SetButtonActive(btn, isSelected)

                        local capturedRole = role
                        local capturedName = name
                        local playerRoleToken = TB.Roles.GetPlayerRoleToken(capturedRole.id)
                        btn:SetScript("OnClick", function()
                            if isPlayer then
                                TB.Roles.SetPlayerRole(capturedRole)
                            else
                                TB.Roles.SetBotRole(capturedName, capturedRole, classId)
                            end
                            TB.RefreshPartyView()
                        end)

                        if isPlayer then
                            setButtonTooltip(btn, "Tell your bots you play as " .. capturedRole.label ..
                                " (bots use " .. playerRoleToken .. "). Your own spec does not change.")
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
            if TB.partyFrame.inviteButton then TB.partyFrame.inviteButton:Show() end
        else
            TB.partyFrame.emptyMsg:Hide()
            if TB.partyFrame.inviteButton then TB.partyFrame.inviteButton:Hide() end
        end
    end

    function TB.RefreshGuildView()
        if not TB.guildFrame or not TB.guildFrame.rows then return end
        local frame = TB.guildFrame
        if frame.headerBtns then paintGuildHeaders(frame) end
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

        if frame.accessLine then
            local orderCap = TB.HasOrderCapability and TB.HasOrderCapability() or false
            local accessText = orderCap and TB.OrderAccessText and TB.OrderAccessText() or nil
            if orderCap and accessText then
                frame.accessLine:SetText(accessText.text)
                if accessText.bad then frame.accessLine:SetTextColor(1, 0.34, 0.28)
                else frame.accessLine:SetTextColor(0.62, 0.60, 0.56) end
                frame.accessLine:Show()
            elseif orderCap then
                frame.accessLine:SetText("Bank access: waiting for the server...")
                frame.accessLine:SetTextColor(0.62, 0.60, 0.56)
                frame.accessLine:Show()
            else
                frame.accessLine:Hide()
            end
        end
        if frame.rankBtn then
            local orderCap = TB.HasOrderCapability and TB.HasOrderCapability() or false
            local access = orderCap and TB.GetOrderAccess and TB.GetOrderAccess() or nil
            local mayOrder = orderCap and TB.CanGiveOrders and TB.CanGiveOrders() or false
            if orderCap and access and access.canSetRank and access.rankIndex and mayOrder then
                frame.rankBtn:Show()
                frame.rankBtn:Enable()
            else
                frame.rankBtn:Hide()
            end
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

        FauxScrollFrame_Update(frame.scroll, total, 7, 36)
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
                row.accent:SetTexture(classColor[1], classColor[2], classColor[3], entry.online and 0.95 or 0.45)
                if isSelected then
                    local sel, selEdge = TB.Theme("rowSel"), TB.Theme("rowSelEdge")
                    row:SetBackdropColor(sel[1], sel[2], sel[3], sel[4])
                    row:SetBackdropBorderColor(selEdge[1], selEdge[2], selEdge[3], selEdge[4])
                else
                    local rc, re = TB.Theme("row"), TB.Theme("rowEdge")
                    row:SetBackdropColor(rc[1], rc[2], rc[3], rc[4])
                    row:SetBackdropBorderColor(re[1], re[2], re[3], re[4])
                end

                row.lvlClass:SetText(entry.level .. " " .. (entry.className or ""))
                if entry.gearLocked then
                    row.gearBadge:SetText("|cffffd200Locked|r")
                else
                    row.gearBadge:SetText("|cff4ecb5aLeveling|r")
                end

                local statusColor = entry.online and "|cff4ecb5a" or "|cff757575"
                local statusStr = entry.status or (entry.online and "Online" or "Offline")
                statusStr = string.upper(string.sub(statusStr, 1, 1)) .. string.sub(statusStr, 2)
                if entry.group then statusColor, statusStr = "|cff42a5f5", "In party" end
                row.status:SetText(statusColor .. (entry.online and "● " or "○ ") .. statusStr .. "|r")

                -- Guild order line: hidden with no capability, greyed with no
                -- officer-note right (TB.CanGiveOrders), else order + buttons.
                -- Sub-order rows indent under their parent and show a Move
                -- button to hand them to another guild bot.
                local orderCap = TB.HasOrderCapability and TB.HasOrderCapability() or false
                local order = orderCap and TB.GetBotOrder and TB.GetBotOrder(entry.name) or nil
                local mayOrder = orderCap and TB.CanGiveOrders and TB.CanGiveOrders() or false
                if row.orderLine then
                    if orderCap then
                        row.orderLine:SetText((order and TB.OrderRowText)
                            and TB.OrderRowText(order) or "|cff666666No order|r")
                        row.orderLine:Show()
                    else
                        row.orderLine:Hide()
                    end
                end
                if row.ordBtn then
                    if orderCap then
                        row.ordBtn:Show()
                        if mayOrder then row.ordBtn:Enable() else row.ordBtn:Disable() end
                    else
                        row.ordBtn:Hide()
                    end
                end
                if row.cancelBtn then
                    if orderCap and order then
                        row.cancelBtn:Show()
                        if mayOrder then row.cancelBtn:Enable() else row.cancelBtn:Disable() end
                    else
                        row.cancelBtn:Hide()
                    end
                end
                local showMeet = orderCap and order and TB.OrderNeedsMeet
                    and TB.OrderNeedsMeet(order) or false
                local meetOk, meetWhy = false, nil
                if showMeet and TB.OrderMeetState then
                    meetOk, meetWhy = TB.OrderMeetState(order)
                end
                if row.meetBtn then
                    if showMeet then
                        row.meetBtn:Show()
                        if mayOrder and meetOk then row.meetBtn:Enable() else row.meetBtn:Disable() end
                        row.meetBtn.meetWhy = meetWhy
                    else
                        row.meetBtn:Hide()
                    end
                end
                if row.relBtn then
                    -- Meet borrows this slot on unfinished enchant rows; the
                    -- other rows always show Release for claimed bots.
                    if showMeet then row.relBtn:Hide() else row.relBtn:Show() end
                end
                if row.moveBtn then
                    if orderCap and order and order.parent and mayOrder then
                        row.moveBtn:Show()
                        row.moveBtn:Enable()
                    else
                        row.moveBtn:Hide()
                    end
                end

                -- Role button label
                local currentRoleId = dbRoles[entry.name]
                local roleLabel = TB.Roles.GetRoleLabel(entry.classId, currentRoleId, "Role")
                if roleLabel == "Role" and table.getn(TB.Roles.GetClassRoles(entry.classId)) > 0 then
                    roleLabel = TB.Roles.GetClassRoles(entry.classId)[1].label
                end
                row.roleBtn:SetText(TB.Roles.ShortLabel and TB.Roles.ShortLabel(roleLabel) or roleLabel)

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
        if frame.fillBtn then
            local fillable = TB.GetFillRaidNames and TB.GetFillRaidNames() or {}
            if table.getn(fillable) > 0 then frame.fillBtn:Enable() else frame.fillBtn:Disable() end
        end
        if frame.orderBtn then
            local orderCap = TB.HasOrderCapability and TB.HasOrderCapability() or false
            local mayOrder = orderCap and TB.CanGiveOrders and TB.CanGiveOrders() or false
            if orderCap then
                frame.orderBtn:Show()
                if mayOrder then frame.orderBtn:Enable() else frame.orderBtn:Disable() end
            else
                frame.orderBtn:Hide()
            end
        end
    end

    local tabs = {
        { name = "actions", tab = tabActions, frame = actionsFrame },
        { name = "camp",    tab = tabCamp,    frame = campFrame },
        { name = "party",   tab = tabParty,   frame = partyFrame },
        { name = "guild",   tab = tabGuild,   frame = guildFrame },
        { name = "roster",  tab = tabRoster,  frame = rosterFrame },
        { name = "raid",    tab = tabRaid,    frame = raidFrame },
        { name = "dungeon", tab = tabDungeon, frame = dungeonFrame },
        { name = "loot",    tab = tabLoot,    frame = lootFrame },
        { name = "log",     tab = tabLog,     frame = logFrame },
    }

    local function inRaid()
        return ((GetNumRaidMembers and GetNumRaidMembers()) or 0) > 0
    end

    local function tabShown(name)
        if name == "raid" then return inRaid() end
        if name == "dungeon" then return serverHasCap("dungeon-run") end
        if name == "loot" then return serverHasCap("loot-log") end
        return true
    end

    -- Responsive tab bar layout: adjusts width and stride to fit 6 to 9 tabs.
    local function layoutTabs()
        local visibleCount = 0
        for _, t in ipairs(tabs) do
            if tabShown(t.name) then
                visibleCount = visibleCount + 1
            end
        end
        -- Equal shares of the full bar width, whatever the count.
        local barW = W - (C.PAD or 10) * 2
        local tabW = math.floor(barW / math.max(visibleCount, 1))
        local step = tabW
        local x = math.floor((barW - tabW * visibleCount) / 2)
        for _, t in ipairs(tabs) do
            if tabShown(t.name) then
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
        if not tabShown(name) then name = "actions" end
        local known = false
        for _, t in ipairs(tabs) do
            if t.name == name then known = true end
        end
        if not known then name = "actions" end
        layoutTabs()
        for _, t in ipairs(tabs) do
            if t.name == name then
                t.frame:Show()
                t.tab.text:SetTextColor(1, 0.94, 0.80)
                t.tab.underline:Show()
                t.tab.fill:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 0.14)
                t.tab:Disable()
            else
                t.frame:Hide()
                t.tab.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
                t.tab.underline:Hide()
                t.tab.fill:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 0)
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
            if TB.RequestOrderList then TB.RequestOrderList() end
        elseif name == "party" then
            if TB.RefreshPartyView then TB.RefreshPartyView() end
        elseif name == "log" then
            if TB.RefreshLogView then TB.RefreshLogView() end
        elseif name == "loot" then
            if TB.RefreshLootView then TB.RefreshLootView() end
        elseif name == "raid" then
            if TB.RefreshRaidView then TB.RefreshRaidView() end
        elseif name == "dungeon" then
            if TB.RefreshRunTab then TB.RefreshRunTab() end
            if TB.OpenRunWindow then TB.OpenRunWindow() end
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

    -- Joining or leaving a raid adds or removes the Raid tab; the server's
    -- dungeon-run and loot-log capabilities do the same for the Dungeon and
    -- Loot tabs.
    TB.UpdateRaidTab = function()
        local current = TortoiseBotsDB and TortoiseBotsDB.activeTab
        if current and not tabShown(current) then
            showTab("actions")
        else
            layoutTabs()
        end
    end

    TB.ShowTab = showTab
    TB.tabActions, TB.tabParty, TB.tabRoster, TB.tabLog = tabActions, tabParty, tabRoster, tabLog
    TB.tabDungeon, TB.dungeonFrame = tabDungeon, dungeonFrame
    TB.tabLoot, TB.lootFrame = tabLoot, lootFrame
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
    local dot = "|cff757575○|r"
    if kind == "ok" then
        c = color("green")
        dot = "|cff4ecb5a●|r"
    elseif kind == "warn" then
        c = color("red")
        dot = "|cffff5555!|r"
    elseif kind == "pending" then
        c = color("yellow")
        dot = "|cffffb300...|r"
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
            TB.SetClassIcon(row.classIcon, entry.classId)
            if row.classIcon.SetAlpha then row.classIcon:SetAlpha((entry.st and entry.st.online) and 1 or 0.45) end
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
                local sel, selEdge = TB.Theme("rowSel"), TB.Theme("rowSelEdge")
                row:SetBackdropColor(sel[1], sel[2], sel[3], sel[4])
                row:SetBackdropBorderColor(selEdge[1], selEdge[2], selEdge[3], selEdge[4])
                row.accent:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
            else
                local rc, re = TB.Theme("row"), TB.Theme("rowEdge")
                row:SetBackdropColor(rc[1], rc[2], rc[3], rc[4])
                row:SetBackdropBorderColor(re[1], re[2], re[3], re[4])
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
    if TB.rosterFrame then paintRosterHeaders(TB.rosterFrame) end
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
        local fillBtn = TB.lifecycleButtons.fill
        if fillBtn then
            local fillable = TB.GetFillPartyNames and TB.GetFillPartyNames() or {}
            local busy = TB.IsRosterBatchActive and TB.IsRosterBatchActive("invite")
            if not busy and serverSupports("invite") and table.getn(fillable) > 0 then
                fillBtn:Enable()
            else
                fillBtn:Disable()
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
    if TB.RefreshCampControls then TB.RefreshCampControls() end
    -- Flee and downtime are newer server intents: disable them on servers
    -- that do not advertise the capability rather than let the click fail.
    if TB.actionButtons.flee then
        if serverHasCap("flee") then TB.actionButtons.flee:Enable() else TB.actionButtons.flee:Disable() end
    end
    if TB.actionButtons.downtime then
        if serverHasCap("downtime") then TB.actionButtons.downtime:Enable() else TB.actionButtons.downtime:Disable() end
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
        TB.SetTextColor(TB.scopeHint, color("text"))
    end
    if TB.scopeNote then
        TB.scopeNote:SetText(scope == "party" and "Target one of your bots to command it alone."
            or "Only this bot gets the orders below.")
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

-- An on/off button's look: lit gold and white text when on, dimmed grey
-- text when off, gold text with "~" when the bots disagree. The word stays
-- in the label (colour alone is not enough: red/green is unreadable for
-- colour-blind players). Colour codes in the text hold through hover/press.
local function paintSwitch(btn, label, state)
    if state == "on" then
        btn:SetText("|cffffffff" .. label .. " On|r")
    elseif state == "mixed" then
        btn:SetText("|cffffd200" .. label .. " ~|r")
    else
        btn:SetText("|cff8a8a8a" .. label .. " Off|r")
    end
    TB.SetButtonActive(btn, state == "on")
end

-- Party switch buttons follow the server's state (TBM:BOTSTATE).
function TB.RefreshToggleButtons()
    for key, btn in pairs(TB.toggleButtons or {}) do
        local state = TB.GetPartyToggleState and TB.GetPartyToggleState(key) or nil
        if key == "aoe" and not state and TB.aoeEnabled then state = "on" end
        paintSwitch(btn, btn.toggle.label, state)
        if TB.togglePending and TB.togglePending[key] then btn:Disable() else btn:Enable() end
    end
    local moveMode = TB.GetPartyMoveMode and TB.GetPartyMoveMode() or nil
    for _, mode in ipairs({ "follow", "stay", "guard", "free" }) do
        local btn = TB.actionButtons and TB.actionButtons[mode]
        if btn then TB.SetButtonActive(btn, moveMode == mode) end
    end
end

-- Camp toggle labels: grind follows the last "Strategy change" reply.
function TB.RefreshCampControls()
    if not TB.actionButtons then return end
    if TB.actionButtons.grind then
        local state = TB.GetGrindState and TB.GetGrindState() or nil
        paintSwitch(TB.actionButtons.grind, "Grind", state == "on" and "on" or "off")
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
