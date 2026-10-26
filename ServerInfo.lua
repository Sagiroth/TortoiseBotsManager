-- TortoiseBotsManager/ServerInfo.lua
-- Server info window, two tabs:
--   Main: the server's version and its player-facing switches, from
--     ".bot features":
--       Server features: <key> <value>, ...       (hidden from chat)
--       TBM:FEATURE|<key>|<value>|<label>         (one per switch)
--     <value> is "on", "off" or a number.
--   All: a search over every bot setting, from ".bot features all <text>":
--       Config: N keys match '<text>'.            (hidden from chat)
--       TBM:CONFIG_BEGIN|<matches>
--       TBM:CONFIG|<key>|<value>                  (at most 200)
--       TBM:CONFIG_END|<shown>|<matches>
-- An older server answers with an unknown-command line and the window says so.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local IW = 320
local IROWS = 18

local function color(name) return COL[name] or { 1, 1, 1 } end

-- features = { { key, value, label } } in the server's order.
local features = {}
local pending = false
-- config = { { key, value } } of the last search; configTotal = its matches.
local config = {}
local configTotal = 0
local configPending = false
local configQuery = ""
local configPage = 1
local tab = "main"

function TB.GetServerFeatures()
    return features
end

function TB.GetServerConfig()
    return config, configTotal
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
    if string.find(msg, "^Config: %d+ keys match") then return true end
    local _, _, total = string.find(msg, "^TBM:CONFIG_BEGIN|(%d+)")
    if total then
        config = {}
        configTotal = tonumber(total)
        configPage = 1
        return true
    end
    if string.find(msg, "^TBM:CONFIG_END|") then
        configPending = false
        if TB.RefreshServerInfo then TB.RefreshServerInfo() end
        return true
    end
    local _, _, ckey, cvalue = string.find(msg, "^TBM:CONFIG|([^|]+)|(.*)$")
    if ckey then
        table.insert(config, { key = ckey, value = cvalue })
        return true
    end
    local _, _, key, value, label = string.find(msg, "^TBM:FEATURE|([^|]+)|([^|]*)|(.*)$")
    if not key then return false end
    table.insert(features, { key = key, value = value, label = label })
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
    return true
end

local win

local function tabButton(label, x, key)
    local b = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    b:SetWidth(80); b:SetHeight(20)
    b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -34)
    b:SetText(label)
    b:SetScript("OnClick", function() TB.SetServerInfoTab(key) end)
    return b
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerInfoWindow", TB.frame or UIParent)
    win:SetWidth(IW); win:SetHeight(126 + IROWS * 18)
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
    win.version:SetPoint("TOPLEFT", win, "TOPLEFT", 90, -16)
    win.version:SetWidth(IW - 130); win.version:SetJustifyH("LEFT")
    TB.SetTextColor(win.version, color("muted"))

    win.tabMain = tabButton("Main", 12, "main")
    win.tabAll = tabButton("All settings", 94, "all")
    win.tabAll:SetWidth(100)

    -- All: search box, Enter or Search asks the server.
    win.search = CreateFrame("EditBox", "TortoiseBotsManagerInfoSearch", win, "InputBoxTemplate")
    win.search:SetWidth(IW - 112); win.search:SetHeight(20)
    win.search:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -62)
    win.search:SetAutoFocus(false)
    win.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    win.search:SetScript("OnEnterPressed", function()
        this:ClearFocus()
        TB.SearchServerConfig(this:GetText())
    end)
    win.searchButton = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.searchButton:SetWidth(80); win.searchButton:SetHeight(20)
    win.searchButton:SetPoint("TOPLEFT", win, "TOPLEFT", IW - 92, -62)
    win.searchButton:SetText("Search")
    win.searchButton:SetScript("OnClick", function() TB.SearchServerConfig(win.search:GetText()) end)

    win.rows = {}
    for i = 1, IROWS do
        local y = -90 - (i - 1) * 18
        local lamp = win:CreateTexture(nil, "OVERLAY")
        lamp:SetWidth(8); lamp:SetHeight(8)
        lamp:SetPoint("TOPLEFT", win, "TOPLEFT", 14, y - 4)
        local label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", win, "TOPLEFT", 28, y)
        label:SetWidth(IW - 130); label:SetJustifyH("LEFT")
        local value = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", win, "TOPLEFT", IW - 102, y)
        value:SetWidth(90); value:SetJustifyH("RIGHT")
        table.insert(win.rows, { lamp = lamp, label = label, value = value })
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -94)
    win.empty:SetWidth(IW - 24); win.empty:SetJustifyH("LEFT")
    TB.SetTextColor(win.empty, color("muted"))

    win.refresh = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.refresh:SetWidth(88); win.refresh:SetHeight(22)
    win.refresh:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
    win.refresh:SetText("Refresh")
    win.refresh:SetScript("OnClick", function() TB.RequestServerFeatures() end)
    win.prev = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.prev:SetWidth(26); win.prev:SetHeight(22)
    win.prev:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
    win.prev:SetText("<")
    win.prev:SetScript("OnClick", function() configPage = configPage - 1; TB.RefreshServerInfo() end)
    win.next = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.next:SetWidth(26); win.next:SetHeight(22)
    win.next:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 128, 10)
    win.next:SetText(">")
    win.next:SetScript("OnClick", function() configPage = configPage + 1; TB.RefreshServerInfo() end)
    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 40, 16)
    win.pageText:SetWidth(86); win.pageText:SetJustifyH("CENTER")
    TB.SetTextColor(win.pageText, color("muted"))
    win.count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.count:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 16)
    win.count:SetWidth(IW - 170); win.count:SetJustifyH("RIGHT")
    TB.SetTextColor(win.count, color("muted"))

    win:Hide()
    TB.infoWindow = win
end

local function hideRow(row)
    row.lamp:Hide(); row.label:Hide(); row.value:Hide()
end

local function renderMain()
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
            hideRow(row)
        end
    end
    if table.getn(features) > 0 then
        win.empty:Hide()
    else
        win.empty:SetText(pending and "Asking the server..." or "This server does not list its switches (an older module).")
        win.empty:Show()
    end
end

local function renderAll()
    local count = table.getn(config)
    local pages = math.max(1, math.ceil(count / IROWS))
    if configPage > pages then configPage = pages end
    if configPage < 1 then configPage = 1 end
    for i, row in ipairs(win.rows) do
        local entry = config[(configPage - 1) * IROWS + i]
        if entry then
            row.label:SetText(entry.key)
            row.value:SetText(entry.value)
            TB.SetTextColor(row.value, color("gold"))
            row.lamp:Hide(); row.label:Show(); row.value:Show()
        else
            hideRow(row)
        end
    end
    win.pageText:SetText(configPage .. " / " .. pages)
    if configPage > 1 then win.prev:Enable() else win.prev:Disable() end
    if configPage < pages then win.next:Enable() else win.next:Disable() end
    if configPending then
        win.empty:SetText("Asking the server...")
        win.empty:Show()
    elseif configQuery == "" then
        win.empty:SetText("Type part of a setting name (e.g. hire, loot, dungeon), then Enter.")
        win.empty:Show()
    elseif count == 0 then
        win.empty:SetText("No setting matches '" .. configQuery .. "' (or an older server).")
        win.empty:Show()
    else
        win.empty:Hide()
    end
    if configQuery ~= "" and not configPending then
        if configTotal > count then
            win.count:SetText(count .. " of " .. configTotal .. " shown: narrow the search")
        else
            win.count:SetText(configTotal .. " settings")
        end
    else
        win.count:SetText("")
    end
end

function TB.RefreshServerInfo()
    if not win or not win:IsVisible() then return end
    win.version:SetText("TortoiseBots " .. tostring(TB.serverVersion or "?"))
    local main = tab == "main"
    TB.SetButtonActive(win.tabMain, main)
    TB.SetButtonActive(win.tabAll, not main)
    if main then
        win.search:Hide(); win.searchButton:Hide()
        win.prev:Hide(); win.next:Hide(); win.pageText:Hide(); win.count:Hide()
        win.refresh:Show()
        renderMain()
    else
        win.search:Show(); win.searchButton:Show()
        win.prev:Show(); win.next:Show(); win.pageText:Show(); win.count:Show()
        win.refresh:Hide()
        renderAll()
    end
end

function TB.SetServerInfoTab(key)
    tab = key == "all" and "all" or "main"
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
end

function TB.RequestServerFeatures()
    pending = true
    features = {}
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
    return TB.SendBotCommand("features")
end

function TB.SearchServerConfig(text)
    text = string.gsub(TB.Trim(text or ""), "[|%c]", "")
    configQuery = text
    config = {}
    configTotal = 0
    configPage = 1
    if string.len(text) < 2 then
        configQuery = ""
        if TB.RefreshServerInfo then TB.RefreshServerInfo() end
        return false
    end
    configPending = true
    if TB.RefreshServerInfo then TB.RefreshServerInfo() end
    return TB.SendBotCommand("features all " .. text)
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
    -- The main window's height, so it reads as its extension.
    local mainH = frame and frame.GetHeight and frame:GetHeight()
    if mainH and mainH > 0 then win:SetHeight(mainH) end
    win:Show()
    TB.RequestServerFeatures()
    return true
end

function TB.CloseServerInfo()
    pending = false
    configPending = false
    if win then win:Hide() end
end

function TB.ToggleServerInfo()
    if win and win:IsVisible() then TB.CloseServerInfo() else TB.OpenServerInfo() end
end
