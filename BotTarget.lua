-- TortoiseBotsManager/BotTarget.lua
-- Target-a-bot shortcut: a key binding ("Open bot controls for target") and
-- a small button next to the target frame, both opening the existing bot
-- panel for the targeted bot. Nothing opens by itself on target change.
-- Shown only when the target is one of my bots.

local TB = TortoiseBots

local function norm(name) return name and TB.NormalizeName(name) or nil end

-- The targeted bot's name, or nil when the target is not one of my bots.
-- A target counts as mine when the server tracks it (roster or bot state);
-- pets, enemies and other players never qualify.
function TB.GetTargetBot()
    if not (UnitExists and UnitExists("target")) then return nil end
    local name = UnitName and norm(UnitName("target"))
    if not name then return nil end
    if TB.GetBotState and TB.GetBotState(name) then return name end
    local st = TB.GetState and TB.GetState(name)
    if st and st.online then return name end
    return nil
end

function TB.TargetBotWanted()
    return TB.GetTargetBot() ~= nil
end

-- Opens the bot panel for the targeted bot. Returns false (and sends
-- nothing) when the target is not one of my bots.
function TB.OpenTargetBotPanel()
    local name = TB.GetTargetBot()
    if not name then return false end
    if TB.OpenBotPanel then return TB.OpenBotPanel(name) end
    return false
end

-- A nil hide flag shows the button; set false from Settings to hide it.
function TB.TargetButtonShown()
    local db = TortoiseBotsDB or {}
    if db.targetButton == false then return false end
    return true
end

function TB.SetTargetButtonShown(shown)
    TortoiseBotsDB = TortoiseBotsDB or {}
    if shown then
        TortoiseBotsDB.targetButton = nil
    else
        TortoiseBotsDB.targetButton = false
    end
    if TB.RefreshTargetButton then TB.RefreshTargetButton() end
    if TB.RefreshSettings then TB.RefreshSettings() end
end

local button

function TB.RefreshTargetButton()
    if not button then return end
    if TB.TargetBotWanted() and TB.TargetButtonShown() then
        button:Show()
    else
        button:Hide()
    end
end

local function targetFrameAnchor()
    -- TargetFrame is stock 1.12 FrameXML; on clients without it (or while
    -- the frame is hidden) the button has nowhere to sit.
    if type(getglobal) == "function" then
        local okFrame, frame = pcall(getglobal, "TargetFrame")
        if okFrame and type(frame) == "table" then return frame end
    end
    return nil
end

function TB.CreateTargetButton()
    if button then return button end
    local anchor = targetFrameAnchor()
    if not anchor then return nil end
    local b = TB.UI.CreateIconButton(anchor, 22, {
        icon = "Interface\\Buttons\\Button-Backpack-Up",
        tipTitle = "Bot controls",
        tip = "Open this bot's gear, bags and behaviour.",
        onClick = function() TB.OpenTargetBotPanel() end,
    })
    b:SetPoint("LEFT", anchor, "RIGHT", -8, -10)
    b:Hide()
    button = b
    TB.targetButton = b
    return b
end

-- Kept beside InitUI: the target frame exists from login, so create the
-- button once and refresh it on every target change.
local watcher
function TB.InitTargetButton()
    if not TB.CreateTargetButton then return end
    TB.CreateTargetButton()
    if watcher then return end
    watcher = CreateFrame("Frame", "TortoiseBotsManagerTargetButtonWatcher")
    watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    watcher:SetScript("OnEvent", function()
        if TB.RefreshTargetButton then TB.RefreshTargetButton() end
    end)
    if TB.RefreshTargetButton then TB.RefreshTargetButton() end
end
