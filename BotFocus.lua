-- TortoiseBotsManager/BotFocus.lua
-- Per-bot focus mark: the raid mark a damage dealer or tank attacks first
-- instead of Skull. Shown as a raid-icon button in the Bots overview row and
-- in the bot panel's Behaviour view; a click opens the eight marks.
-- Hidden without the `focus-mark` capability and on healers (the server
-- refuses them too).
--
--   .bot focus <bot|party> <mark|clear|status>
--   TBM:BOTSTATE|<bot>|...,focus=<mark>           (state lives in the bot state)
--   TBM:ACTION_ACK|focus|<scope>|<n>|<mark>
--   TBM:ACTION_ERR|focus|healer|<msg> | focus|cc-mark|<msg> | focus|no-bot|<msg>
--
-- Focus Skull and the dungeon run's focus put every bot back on Skull; the
-- next BOTSTATE shows it, so the button always reads the server's mark.

local TB = TortoiseBots
local C = TB.C or {}

local CAP = "focus-mark"
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- Skull first: it is everyone's default.
local FOCUS_ORDER = { "skull", "cross", "square", "moon", "triangle", "diamond", "circle", "star" }

local function norm(name) return name and TB.NormalizeName(name) or nil end

function TB.HasFocusCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

function TB.FocusMarks() return FOCUS_ORDER end

-- The server's focus mark for a bot ("skull" by default), nil while unknown.
function TB.GetFocusMark(name)
    local st = TB.GetBotState and TB.GetBotState(name)
    return st and st.focus or nil
end

function TB.FocusMarkLabel(mark)
    if mark == "none" then return "None" end
    return (mark and C.CC_MARK_LABELS and C.CC_MARK_LABELS[mark]) or "?"
end

function TB.FocusMarkIcon(mark)
    local index = mark and C.CC_MARK_ICONS and C.CC_MARK_ICONS[mark]
    return index and (ICON_PATH .. index) or nil
end

-- Whether a bot gets the focus control: the server reports the field, and
-- the bot does not fight as a healer.
function TB.FocusShown(name)
    if not TB.HasFocusCapability() then return false end
    local st = TB.GetBotState and TB.GetBotState(name)
    if not st or not st.focus then return false end
    return TB.BotSpecKind == nil or TB.BotSpecKind(st.specs) ~= "heal"
end

-- ── commands ────────────────────────────────────────────────────────────────
function TB.BuildFocusCommand(scope, mark)
    local lower = string.lower(TB.Trim(scope or ""))
    if lower ~= "party" and lower ~= "raid" then lower = norm(scope) end
    mark = mark and string.lower(TB.Trim(mark)) or nil
    if not lower or lower == "" or not mark then return nil end
    if mark ~= "clear" and mark ~= "status" and not (C.CC_MARK_LABELS and C.CC_MARK_LABELS[mark]) then
        return nil
    end
    return "focus " .. lower .. " " .. mark
end

function TB.SendFocus(name, mark)
    local cmd = TB.BuildFocusCommand(name, mark)
    if not cmd then return false end
    return TB.SendBotCommand(cmd)
end

-- ACK routing; errors fall through to the generic status/log line.
function TB.OnFocusAck(packet)
    local intent = packet.intent or ""
    if intent ~= "focus" and intent ~= "focus status" then return false end
    if intent == "focus" and TB.SetStatus then
        local _, _, bot = string.find(packet.scope or "", "^bot:(.+)$")
        TB.SetStatus((bot or "Party") .. ": focus " .. TB.FocusMarkLabel(packet.executor), "ok")
    end
    if TB.RefreshBots then TB.RefreshBots() end
    return true
end

-- ── mark menu ───────────────────────────────────────────────────────────────
-- One row per mark with its icon. A mark another bot holds as its CC mark is
-- greyed out with the owner's name: the server refuses it, since focus fire
-- would break the crowd control.
function TB.BuildFocusMenu(name, addButton)
    name = norm(name)
    if not name then return 0 end
    local current = TB.GetFocusMark(name)
    local count = 0
    for _, mark in ipairs(FOCUS_ORDER) do
        local owner = mark ~= "skull" and TB.GetCcOwner and TB.GetCcOwner(mark) or nil
        local text = TB.FocusMarkLabel(mark)
        if mark == "skull" then text = text .. " (default)" end
        if owner then text = text .. " |cff8c8c8c(CC: " .. owner .. ")|r" end
        local choice = mark
        count = count + 1
        addButton({ text = text,
            checked = (current == mark) and 1 or nil,
            disabled = owner and 1 or nil,
            func = function() TB.SendFocus(name, choice) end })
    end
    return count
end

local focusMenu
function TB.OpenFocusMenu(name)
    name = norm(name)
    if not name or not TB.FocusShown(name) then return false end
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if not focusMenu then
        focusMenu = CreateFrame("Frame", "TortoiseBotsManagerFocusMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(focusMenu, function()
        TB.BuildFocusMenu(name, UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, focusMenu, "cursor")
    return true
end

local function focusTooltip(button)
    button:SetScript("OnEnter", function()
        if not this.bot then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Focus mark: " .. TB.FocusMarkLabel(TB.GetFocusMark(this.bot)))
        GameTooltip:AddLine("The raid mark this bot attacks first. When that mark is on no mob it takes Skull.", 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Focus Skull and the dungeon run put every bot back on Skull.", 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Click to pick a mark.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A square raid-icon button (Bots overview rows).
function TB.CreateFocusIconButton(parent, size)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(size); b:SetHeight(size)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetWidth(size - 6); b.icon:SetHeight(size - 6)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    focusTooltip(b)
    b:SetScript("OnClick", function()
        if this.bot then TB.OpenFocusMenu(this.bot) end
    end)
    return b
end

function TB.UpdateFocusIconButton(button, name)
    if not TB.FocusShown(name) then
        button.bot = nil
        button:Hide()
        return false
    end
    local mark = TB.GetFocusMark(name)
    button.bot = norm(name)
    local icon = TB.FocusMarkIcon(mark)
    if icon then button.icon:SetTexture(icon); button.icon:Show() else button.icon:Hide() end
    button:Show()
    return true
end

-- ── bot panel block ─────────────────────────────────────────────────────────
local ROW_H = 20
local PANEL_W = 330
local block

function TB.CreateFocusBlock(panel, parent)
    block = {}
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(PANEL_W - 24); b:SetHeight(ROW_H)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetWidth(14); b.icon:SetHeight(14)
    b.icon:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    focusTooltip(b)
    b:SetScript("OnClick", function()
        if this.bot then TB.OpenFocusMenu(this.bot) end
    end)
    b:Hide()
    block.button = b
    panel.focusBlock = block
end

-- `top` is the y offset (negative, from the panel's top) where the button
-- goes; returns the y offset below it, or `top` when hidden.
function TB.RenderFocusBlock(bot, top)
    if not block then return top end
    local b = block.button
    if not bot or not TB.FocusShown(bot) then
        b.bot = nil
        b:Hide()
        return top
    end
    local mark = TB.GetFocusMark(bot)
    b.bot = norm(bot)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", 12, top)
    b:SetText("Focus mark: " .. TB.FocusMarkLabel(mark))
    local icon = TB.FocusMarkIcon(mark)
    if icon then b.icon:SetTexture(icon); b.icon:Show() else b.icon:Hide() end
    b:Show()
    return top - ROW_H - 6
end
