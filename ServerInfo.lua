-- TortoiseBotsManager/ServerInfo.lua
-- Server info window: the server's version and its player-facing switches,
-- from ".bot features":
--   Server features: <key> <value>, ...           (hidden from chat)
--   TBM:FEATURE|<key>|<value>|<label>             (one per switch)
-- <value> is "on", "off" or a number. An older server answers the command
-- with an unknown-command line and the window says so.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local IW = 300
local IROWS = 18

local function color(name) return COL[name] or { 1, 1, 1 } end

-- features = { { key, value, label } } in the server's order.
local features = {}
local pending = false

function TB.GetServerFeatures()
    return features
end

-- Inbound router hook (Comms OnSystemMessage).
function TB.ParseFeatureMessage(msg)
    if not msg then return false end
    if string.find(msg, "^Server features:") then
        features = {}
        pending = false
        if TB.RefreshServerInfo then TB.RefreshServerInfo() end
        return true
    end
    local _, _, key, value, label = string.find(msg, "^TBM:FEATURE|([^|]+)|([^|]*)|(.*)$")
    if not key then return false end
    table.insert(features, { key = key, value = value, label = label })
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
    return true
end

local win

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerInfoWindow", TB.frame or UIParent)
    win:SetWidth(IW); win:SetHeight(84 + IROWS * 18)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerInfoWindow") end
    TB.ApplyBackdrop(win, 0.98, 1.0)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -10)
    title:SetText("Server")
    TB.SetTextColor(title, color("gold"))
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseServerInfo() end)

    win.version = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.version:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    win.version:SetWidth(IW - 24); win.version:SetJustifyH("LEFT")
    TB.SetTextColor(win.version, color("muted"))

    win.rows = {}
    for i = 1, IROWS do
        local y = -56 - (i - 1) * 18
        local lamp = win:CreateTexture(nil, "OVERLAY")
        lamp:SetWidth(8); lamp:SetHeight(8)
        lamp:SetPoint("TOPLEFT", win, "TOPLEFT", 14, y - 4)
        local label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", win, "TOPLEFT", 28, y)
        label:SetWidth(IW - 100); label:SetJustifyH("LEFT")
        local value = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", win, "TOPLEFT", IW - 72, y)
        value:SetWidth(60); value:SetJustifyH("RIGHT")
        table.insert(win.rows, { lamp = lamp, label = label, value = value })
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -60)
    win.empty:SetWidth(IW - 24); win.empty:SetJustifyH("LEFT")
    TB.SetTextColor(win.empty, color("muted"))

    win.refresh = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.refresh:SetWidth(88); win.refresh:SetHeight(22)
    win.refresh:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
    win.refresh:SetText("Refresh")
    win.refresh:SetScript("OnClick", function() TB.RequestServerFeatures() end)

    win:Hide()
    TB.infoWindow = win
end

function TB.RefreshServerInfo()
    if not win or not win:IsVisible() then return end
    win.version:SetText("TortoiseBots " .. tostring(TB.serverVersion or "?"))
    local count = table.getn(features)
    for i, row in ipairs(win.rows) do
        local f = features[i]
        if f then
            row.label:SetText(f.label)
            row.value:SetText(f.value)
            if f.value == "on" then
                row.lamp:SetTexture(0.30, 0.90, 0.45, 1)
                TB.SetTextColor(row.value, color("green"))
            elseif f.value == "off" then
                row.lamp:SetTexture(0.45, 0.45, 0.45, 1)
                TB.SetTextColor(row.value, color("muted"))
            else
                row.lamp:SetTexture(0.95, 0.72, 0.28, 1)
                TB.SetTextColor(row.value, color("gold"))
            end
            row.lamp:Show(); row.label:Show(); row.value:Show()
        else
            row.lamp:Hide(); row.label:Hide(); row.value:Hide()
        end
    end
    if count > 0 then
        win.empty:Hide()
    else
        win.empty:SetText(pending and "Asking the server..." or "This server does not list its switches (an older module).")
        win.empty:Show()
    end
end

function TB.RequestServerFeatures()
    pending = true
    features = {}
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
    return TB.SendBotCommand("features")
end

function TB.OpenServerInfo()
    if not win then createWindow() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + IW + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RequestServerFeatures()
    return true
end

function TB.CloseServerInfo()
    pending = false
    if win then win:Hide() end
end

function TB.ToggleServerInfo()
    if win and win:IsVisible() then TB.CloseServerInfo() else TB.OpenServerInfo() end
end
