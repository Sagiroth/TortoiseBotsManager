-- TortoiseBotsManager/MiniBar.lua
-- Minimal mode: a small, draggable bar with the fight buttons as icons.
-- The full window and the bar are two views of the same controls: every
-- icon sends the same intent as its Fight-tab button and follows the same
-- enable rules (enemy-target actions grey out without an enemy target).
--
-- TortoiseBotsDB.mode = "full" | "mini"; the bar stays on screen in "mini".

local TB = TortoiseBots
local C = TB.C or {}

local ICON = 28
local STEP = 30

-- Order follows a fight: engage, pull, focus, move, then the AoE switch.
local ITEMS = {
    { intent = "attack",      needsEnemy = true },
    { intent = "stop" },
    { intent = "interrupt",   needsEnemy = true },
    { intent = "flee",        cap = "flee" },
    { intent = "pull",        needsEnemy = true, pull = true },
    { intent = "pullback",    needsEnemy = true, pull = true },
    { intent = "focus skull", raidIcon = 8 },
    { intent = "follow" },
    { intent = "stay" },
    { intent = "come" },
    { intent = "aoe",         toggle = "aoe" },
}

local bar

local function tooltipFor(item)
    local labels = C.ACTION_LABELS or {}
    local title = labels[item.intent] or item.intent
    local text = TB.ActionTooltip and TB.ActionTooltip(item.intent) or ""
    if item.pull then
        local db = TortoiseBotsDB or {}
        local seconds = item.intent == "pullback" and db.pullbackDelay or db.pullDelay
        text = text .. " Timer: " .. TB.ClampPullSeconds(seconds) .. " s (set it in the full window)."
    end
    return title, text
end

local function makeIcon(parent, item, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(ICON); b:SetHeight(ICON)
    b:SetPoint("LEFT", parent, "LEFT", 34 + (index - 1) * STEP, 0)
    b:RegisterForClicks("LeftButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    if item.raidIcon then
        b.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. item.raidIcon)
    else
        b.icon:SetTexture((C.ACTION_ICONS or {})[item.intent])
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.18)
    if item.toggle then
        b.lamp = b:CreateTexture(nil, "OVERLAY")
        b.lamp:SetWidth(8); b.lamp:SetHeight(8)
        b.lamp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    b.item = item
    b:SetScript("OnEnter", function()
        local title, text = tooltipFor(this.item)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        if text ~= "" then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, 1) end
        if TB.GetActionScopeHint then
            GameTooltip:AddLine(TB.GetActionScopeHint(), 0.62, 0.60, 0.56)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        local it = this.item
        if it.toggle then
            TB.SendPartyToggle(it.toggle)
        elseif it.pull then
            TB.SendActionIntent(TB.PullIntent and TB.PullIntent(it.intent) or it.intent)
        else
            TB.SendActionIntent(it.intent)
        end
    end)
    return b
end

local function savePosition()
    local left, top = bar:GetLeft(), bar:GetTop()
    if not left or not top then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.miniBar = { x = left, y = top }
end

local function createBar()
    bar = CreateFrame("Frame", "TortoiseBotsManagerMiniBar", UIParent)
    bar:SetWidth(34 + table.getn(ITEMS) * STEP + 32)
    bar:SetHeight(ICON + 10)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:EnableMouse(true)
    TB.ApplyBackdrop(bar, 0.9, 0.9)
    local pos = TortoiseBotsDB and TortoiseBotsDB.miniBar
    if pos and pos.x and pos.y then
        bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end

    -- The turtle is the drag handle (the whole bar is full of buttons).
    local handle = CreateFrame("Button", nil, bar)
    handle:SetWidth(22); handle:SetHeight(22)
    handle:SetPoint("LEFT", bar, "LEFT", 7, 0)
    handle:RegisterForDrag("LeftButton")
    local turtle = handle:CreateTexture(nil, "ARTWORK")
    turtle:SetAllPoints(handle)
    turtle:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle")
    turtle:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    handle:SetScript("OnDragStart", function() bar:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        savePosition()
    end)
    handle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("TortoiseBots - mini mode")
        GameTooltip:AddLine("Drag to move. The + button opens the full window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.icons = {}
    for i, item in ipairs(ITEMS) do
        bar.icons[item.intent] = makeIcon(bar, item, i)
    end

    local expand = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    expand:SetWidth(22); expand:SetHeight(22)
    expand:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    expand:SetText("+")
    expand:SetScript("OnClick", function() TB.SetMode("full") end)
    expand:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Full window")
        GameTooltip:AddLine("Switch back to the full TortoiseBots window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    expand:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.expand = expand
    bar:Hide()
    TB.miniBar = bar
end

local function setUsable(b, usable)
    if usable then
        b:Enable()
        if b.icon.SetVertexColor then b.icon:SetVertexColor(1, 1, 1) end
    else
        b:Disable()
        if b.icon.SetVertexColor then b.icon:SetVertexColor(0.35, 0.35, 0.35) end
    end
end

function TB.RefreshMiniBar()
    if not bar or not bar:IsVisible() then return end
    local enemy = TB.HasEnemyTarget and TB.HasEnemyTarget() or false
    for _, item in ipairs(ITEMS) do
        local b = bar.icons[item.intent]
        local usable = true
        if item.needsEnemy and not enemy then usable = false end
        if item.cap and not (TB.HasServerCapability and TB.HasServerCapability(item.cap)) then usable = false end
        if item.toggle then
            local state = TB.GetPartyToggleState and TB.GetPartyToggleState(item.toggle)
            if state == "on" then b.lamp:SetTexture(0.30, 0.90, 0.45, 1)
            elseif state == "off" then b.lamp:SetTexture(0.45, 0.45, 0.45, 1)
            else b.lamp:SetTexture(0.95, 0.72, 0.28, 1) end
            if TB.togglePending and TB.togglePending[item.toggle] then usable = false end
        end
        setUsable(b, usable)
    end
end

-- "mini": hide the window, show the bar. "full": the other way round.
function TB.SetMode(mode)
    if mode ~= "mini" then mode = "full" end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.mode = mode
    if not bar then createBar() end
    if mode == "mini" then
        if TB.CloseBotPanel then TB.CloseBotPanel() end
        if TB.frame then TB.frame:Hide() end
        bar:Show()
        TB.RefreshMiniBar()
    else
        bar:Hide()
        if TB.frame and not TB.frame:IsVisible() then
            TB.frame:Show()
            if TB.Refresh then TB.Refresh() end
            if TB.PollList then TB.PollList(true) end
        end
    end
end

function TB.GetMode()
    return (TortoiseBotsDB and TortoiseBotsDB.mode == "mini") and "mini" or "full"
end

-- Minimap button and /tbm: show or hide whichever view the mode uses.
function TB.ToggleMiniBar()
    if not bar then createBar() end
    if bar:IsVisible() then bar:Hide() else bar:Show(); TB.RefreshMiniBar() end
end

-- Target changes decide which icons are usable.
local watcher = CreateFrame("Frame", "TortoiseBotsManagerMiniBarWatcher")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        -- Mini mode survives a reload: bring the bar back.
        if TB.GetMode() == "mini" and TB.uiReady then
            if not bar then createBar() end
            bar:Show()
        end
    end
    TB.RefreshMiniBar()
end)
