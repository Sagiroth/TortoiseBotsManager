-- TortoiseBotsManager/Settings.lua
-- Small options window: window scale (automatic from the screen height
-- until the slider overrides it), minimap button on/off, mini-bar lock,
-- and the roster poll switch and interval the auto-poller already reads.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local SW = 280

local function color(name) return COL[name] or { 1, 1, 1 } end

-- ── model ──────────────────────────────────────────────────────────────────
function TB.DefaultWindowScale()
    local sh = (GetScreenHeight and GetScreenHeight()) or 768
    if sh < 700 then return 0.82
    elseif sh < 860 then return 0.90
    else return 1 end
end

function TB.ClampWindowScale(value)
    local n = tonumber(value)
    if not n then return nil end
    if n < 0.7 then n = 0.7 end
    if n > 1.1 then n = 1.1 end
    return math.floor(n * 100 + 0.5) / 100
end

-- Stored override, or the automatic scale while it is unset or stale.
function TB.GetWindowScale()
    local db = TortoiseBotsDB or {}
    return TB.ClampWindowScale(db.windowScale) or TB.DefaultWindowScale()
end

function TB.ApplyWindowScale()
    if TB.frame and TB.frame.SetScale then TB.frame:SetScale(TB.GetWindowScale()) end
end

-- A nil scale clears the override and returns to automatic.
function TB.SetWindowScale(value)
    TortoiseBotsDB = TortoiseBotsDB or {}
    if value == nil then
        TortoiseBotsDB.windowScale = nil
    else
        local n = TB.ClampWindowScale(value)
        if not n then return end
        TortoiseBotsDB.windowScale = n
    end
    TB.ApplyWindowScale()
    if TB.RefreshSettings then TB.RefreshSettings() end
end

function TB.ClampPollInterval(value)
    local n = math.floor(tonumber(value) or 8)
    if n < 4 then n = 4 end
    if n > 60 then n = 60 end
    return n
end

function TB.SetPollInterval(value)
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.pollInterval = TB.ClampPollInterval(value)
    if TB.RefreshSettings then TB.RefreshSettings() end
end

function TB.SetAutoPoll(on)
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.autoPoll = on and true or false
    if TB.RefreshSettings then TB.RefreshSettings() end
end

function TB.SetMiniLocked(locked)
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.miniLocked = locked and true or false
    if TB.RefreshSettings then TB.RefreshSettings() end
end

-- ── window ─────────────────────────────────────────────────────────────────
local win

local function scaleText()
    local db = TortoiseBotsDB or {}
    local pct = math.floor(TB.GetWindowScale() * 100 + 0.5) .. "%"
    if type(db.windowScale) == "number" then return pct end
    return "Auto (" .. pct .. ")"
end

local function checkRow(y, name, label)
    local check = CreateFrame("CheckButton", name, win, "UICheckButtonTemplate")
    TB.StyleCheckButton(check)
    check:SetWidth(20); check:SetHeight(20)
    check:SetPoint("TOPLEFT", win, "TOPLEFT", 12, y)
    local text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetWidth(SW - 52); text:SetJustifyH("LEFT")
    text:SetText(label)
    TB.SetTextColor(text, color("text"))
    return check
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerSettingsWindow", TB.frame or UIParent)
    win:SetWidth(SW); win:SetHeight(200)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function() win:StartMoving() end)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local left, top = win:GetLeft(), win:GetTop()
        if left and top then
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerSettingsWindow") end
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -9)
    TB.StyleTitle(title, 14)
    title:SetText("Settings")
    TB.SetTextColor(title, color("title"))
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseSettings() end)

    local scaleLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    scaleLabel:SetWidth(110); scaleLabel:SetJustifyH("LEFT")
    scaleLabel:SetText("Window size")
    TB.SetTextColor(scaleLabel, color("text"))
    local auto = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"), "mode")
    auto:SetWidth(46); auto:SetHeight(18)
    auto:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -36)
    auto:SetText("Auto")
    auto:SetScript("OnClick", function() TB.SetWindowScale(nil) end)
    win.scaleValue = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.scaleValue:SetPoint("RIGHT", auto, "LEFT", -6, 0)
    win.scaleValue:SetWidth(100); win.scaleValue:SetJustifyH("RIGHT")
    TB.SetTextColor(win.scaleValue, color("muted"))

    local slider = CreateFrame("Slider", "TortoiseBotsManagerSettingsScale", win)
    slider:SetWidth(SW - 24); slider:SetHeight(18)
    slider:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -58)
    slider:EnableMouse(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0.7, 1.1)
    slider:SetValueStep(0.01)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(0.02, 0.02, 0.03, 1)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(6)
    slider:SetValue(TB.GetWindowScale())
    -- Back at the automatic value the drag ends in Auto, not in a manual
    -- override of the same size.
    slider:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        if math.abs(v - TB.GetWindowScale()) < 0.0005 then return end
        TB.SetWindowScale(v)
    end)
    win.slider = slider

    win.minimapCheck = checkRow(-88, "TortoiseBotsManagerSettingsMinimap", "Minimap button")
    win.minimapCheck:SetScript("OnClick", function()
        TB.SetMinimapShown(this:GetChecked() and true or false)
    end)
    win.lockCheck = checkRow(-114, "TortoiseBotsManagerSettingsLock", "Lock mini bar")
    win.lockCheck:SetScript("OnClick", function()
        TB.SetMiniLocked(this:GetChecked() and true or false)
    end)
    win.pollCheck = checkRow(-140, "TortoiseBotsManagerSettingsPoll", "Auto refresh roster")
    win.pollCheck:SetScript("OnClick", function()
        TB.SetAutoPoll(this:GetChecked() and true or false)
    end)

    local pollLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pollLabel:SetPoint("TOPLEFT", win, "TOPLEFT", 36, -166)
    pollLabel:SetWidth(90); pollLabel:SetJustifyH("LEFT")
    pollLabel:SetText("Refresh every")
    TB.SetTextColor(pollLabel, color("text"))
    win.pollStepper = TB.UI.CreateStepper(win, {
        point = "LEFT", relTo = pollLabel, relPoint = "RIGHT", x = 8, y = 0,
        get = function()
            local db = TortoiseBotsDB or {}
            return TB.ClampPollInterval(db.pollInterval)
        end,
        set = function(val) TB.SetPollInterval(val) end,
        format = function(val) return val .. " s" end,
    })

    win:Hide()
    TB.settingsWindow = win
end

function TB.RefreshSettings()
    if not win or not win:IsVisible() then return end
    local db = TortoiseBotsDB or {}
    win.scaleValue:SetText(scaleText())
    win.slider:SetValue(TB.GetWindowScale())
    win.minimapCheck:SetChecked(db.minimapShown ~= false)
    win.lockCheck:SetChecked(db.miniLocked and true or false)
    local pollOn = db.autoPoll ~= false
    win.pollCheck:SetChecked(pollOn)
    win.pollStepper.repaint()
    if pollOn then
        win.pollStepper.minus:Enable()
        win.pollStepper.plus:Enable()
    else
        win.pollStepper.minus:Disable()
        win.pollStepper.plus:Disable()
    end
end

function TB.OpenSettings()
    if not win then createWindow() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + SW + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RefreshSettings()
    return true
end

function TB.CloseSettings()
    if win then win:Hide() end
end

function TB.ToggleSettings()
    if win and win:IsVisible() then TB.CloseSettings() else TB.OpenSettings() end
end
