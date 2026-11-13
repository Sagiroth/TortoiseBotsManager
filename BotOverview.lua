-- TortoiseBotsManager/BotOverview.lua
-- "Bots" overview: one compact row per party bot with its name, class and
-- role, the fight switches that matter (Hold position, No dungeon Blink and
-- the chips the bot panel Behaviour view already shows), and a button that
-- opens the full bot panel. Reached from the Party tab, next to Blessings.
-- Rows reuse the existing behaviour chip definitions and SendBehavior, so no
-- command string is duplicated here.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local CAP = "choice"
local NAME_W = 92
local CHIP_W = 128
local CHIP_H = 20
local CHIP_STEP = 22
local ROW_STEP = 28
local MAX_ROWS = 5
local ROWS_TOP = 62
local PAD = 12
local WIN_W = PAD * 2 + NAME_W + 4 * CHIP_W + 5 * 4 + 76

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

local win

-- The party bots (sorted), with their class ids: units we can see, minus us.
local function overviewGroup()
    local bots, classIds = {}, {}
    local raid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    local ids = C.CLASS_NAME_TO_ID or {}
    local function add(unit)
        if unit == "player" then return end
        local name = UnitName and norm(UnitName(unit))
        if not name then return end
        local isBot = (TB.GetBotState and TB.GetBotState(name))
            or (TB.GetState and TB.GetState(name) and TB.GetState(name).online)
        if not isBot then return end
        table.insert(bots, name)
        local classId = nil
        if UnitClass then
            local className, classFile = UnitClass(unit)
            classId = ids[classFile or ""] or ids[className or ""]
        end
        if not classId and TB.BotClassId then classId = TB.BotClassId(name) end
        classIds[name] = classId
    end
    if raid > 0 then
        for i = 1, raid do add("raid" .. i) end
    else
        local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, party do add("party" .. i) end
    end
    table.sort(bots)
    return bots, classIds
end

function TB.GetOverviewGroup()
    return overviewGroup()
end

-- The chips that matter in a fight, in Behaviour-view order: Hold position,
-- No dungeon Blink, then the fight switches the bot panel already shows
-- (Loot, AoE, Auto CC, Save mana, Cooldowns, Watch threat, Potions). Max
-- four per row. Uses the same definitions, so labels and tips match.
local FIGHT_KEYS = { "hold", "noblink", "loot", "aoe", "autocc", "savemana", "boost", "threat", "potions" }

function TB.OverviewChips(name, classId)
    local defs = {}
    local byKey = {}
    for _, def in ipairs(C.BEHAVIORS or {}) do byKey[def.key] = def end
    local st = TB.GetBotState and TB.GetBotState(name) or nil
    for _, key in ipairs(FIGHT_KEYS) do
        local def = byKey[key]
        if def and table.getn(defs) < 4 then
            local shown = true
            if TB.BehaviorChipShown then
                shown = TB.BehaviorChipShown(def, st, classId)
            end
            if shown then table.insert(defs, def) end
        end
    end
    return defs
end

local function createRow(parent)
    local row = {}
    row.name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetWidth(NAME_W); row.name:SetJustifyH("LEFT")
    row.chips = {}
    for i = 1, 4 do
        local chip = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
        chip:SetWidth(CHIP_W); chip:SetHeight(CHIP_H)
        chip.lamp = chip:CreateTexture(nil, "OVERLAY")
        chip.lamp:SetWidth(8); chip.lamp:SetHeight(8)
        chip.lamp:SetPoint("RIGHT", chip, "RIGHT", -6, 0)
        chip:SetScript("OnEnter", function()
            if not this.def then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.def.label)
            GameTooltip:AddLine(this.def.tip, 0.9, 0.9, 0.9, 1)
            GameTooltip:AddLine("Click to switch on/off.", 0.9, 0.9, 0.9, 1)
            GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        chip:SetScript("OnClick", function()
            if this.bot and this.def and TB.SendBehavior then
                TB.SendBehavior(this.bot, this.def.key)
            end
        end)
        row.chips[i] = chip
    end
    row.open = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    row.open:SetWidth(72); row.open:SetHeight(CHIP_H)
    row.open:SetText("Controls")
    row.open:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bot controls")
        GameTooltip:AddLine("Open this bot's gear, bags and behaviour.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    row.open:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.open:SetScript("OnClick", function()
        if this.bot and TB.OpenBotPanel then TB.OpenBotPanel(this.bot) end
    end)
    return row
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerBots", TB.frame or UIParent)
    win:SetWidth(WIN_W); win:SetHeight(120)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerBots") end
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -9)
    title:SetText("Bots")
    TB.StyleTitle(title, 14)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseBots() end)

    win.rows = {}
    for r = 1, MAX_ROWS do win.rows[r] = createRow(win) end
    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.hint:SetJustifyH("LEFT")
    win.hint:SetText("One row per party bot. Chips switch the same behaviour as the bot panel.")
    TB.SetTextColor(win.hint, color("muted"))
    win:Hide()
    TB.botsWindow = win
end

function TB.RefreshBots()
    if not win or not win:IsVisible() then return end
    local bots, classIds = overviewGroup()
    local rowCount = math.min(table.getn(bots), MAX_ROWS)
    win:SetWidth(WIN_W)
    win:SetHeight(ROWS_TOP + rowCount * ROW_STEP + 26)
    for r, row in ipairs(win.rows) do
        local name = bots[r]
        if r <= rowCount and name then
            local classId = classIds[name]
            local top = -ROWS_TOP - (r - 1) * ROW_STEP
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, top - 4)
            row.name:SetText(name)
            local col = (classId and C.CLASS_COLORS and C.CLASS_COLORS[classId]) or color("gold")
            row.name:SetTextColor(col[1], col[2], col[3])
            local role = classId and TB.Roles and TB.Roles.GetBotRole and TB.Roles.GetBotRole(name, classId)
            local roleLabel = (classId and role and TB.Roles.GetRoleLabel
                and TB.Roles.GetRoleLabel(classId, role, nil)) or nil
            local className = (classId and C.CLASS_NAMES and C.CLASS_NAMES[classId])
                or (C.CLASS_NAMES and C.CLASS_NAMES[1]) or ""
            local second = roleLabel or className
            if second and second ~= "" then
                row.name:SetText(name .. "\n" .. second)
            end
            row.name:Show()
            local defs = TB.OverviewChips(name, classId)
            local st = TB.GetBotState and TB.GetBotState(name) or nil
            for i, chip in ipairs(row.chips) do
                local def = defs[i]
                if def then
                    local value = st and st[def.key]
                    chip:ClearAllPoints()
                    chip:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + 4 + (i - 1) * (CHIP_W + 4), top)
                    chip.def = def
                    chip.bot = name
                    local stateText = value == "on" and "On" or (value == "off" and "Off" or "?")
                    chip:SetText(def.label .. ": " .. stateText)
                    if value == "on" then chip.lamp:SetTexture(0.30, 0.90, 0.45, 1)
                    elseif value == "off" then chip.lamp:SetTexture(0.45, 0.45, 0.45, 1)
                    else chip.lamp:SetTexture(0.95, 0.72, 0.28, 1) end
                    if st then chip:Enable() else chip:Disable() end
                    chip:Show()
                else
                    chip:Hide()
                end
            end
            row.open:ClearAllPoints()
            row.open:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + 4 + 4 * (CHIP_W + 4), top)
            row.open.bot = name
            row.open:Show()
        else
            row.name:Hide()
            for _, chip in ipairs(row.chips) do chip:Hide() end
            row.open:Hide()
        end
    end
    win.hint:ClearAllPoints()
    win.hint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(ROWS_TOP + rowCount * ROW_STEP + 4))
    win.hint:SetWidth(WIN_W - PAD * 2)
    if TB.RefreshBotViews then TB.RefreshBotViews() end
end

function TB.BotsAvailable()
    local bots = overviewGroup()
    return table.getn(bots) > 0
end

function TB.OpenBots()
    if not TB.BotsAvailable() then return false end
    if not win then createWindow() end
    if TB.CloseBotPanel then TB.CloseBotPanel() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseBlessings then TB.CloseBlessings() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if TB.CloseActiveOrders then TB.CloseActiveOrders() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + WIN_W + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RefreshBots()
    return true
end

function TB.CloseBots()
    if win then win:Hide() end
end

function TB.ToggleBots()
    if win and win:IsVisible() then TB.CloseBots() else TB.OpenBots() end
end

-- The Party tab's entry point: shown when the group has a party bot, next
-- to the Blessings button.
function TB.UpdateBotsButton()
    local button = TB.partyFrame and TB.partyFrame.botsBtn
    if not button then return end
    if TB.BotsAvailable() then button:Show() else button:Hide() end
end

-- The choice capability does not gate this view; when it arrives, refresh
-- the rows the same way the bot panel repaints.
function TB.NoteChoiceCaps()
    if TB.RefreshBots then TB.RefreshBots() end
end

-- A changed group re-asks nothing (rows read the cached bot state), but the
-- window closes when the last party bot leaves.
local dueAt
local watcher = CreateFrame("Frame", "TortoiseBotsManagerBotsWatcher")
watcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
watcher:RegisterEvent("RAID_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
    if win and win:IsVisible() then dueAt = now() + 1 end
    if TB.UpdateBotsButton then TB.UpdateBotsButton() end
end)
watcher:SetScript("OnUpdate", function()
    if not dueAt or now() < dueAt then return end
    dueAt = nil
    if win and win:IsVisible() then TB.RefreshBots() end
end)
