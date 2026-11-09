-- TortoiseBotsManager/ActiveOrders.lua
-- One list of every order the guild bots are working on: who, what, how far,
-- and the full story of the picked one (state, live step, step history),
-- with Cancel and New order beside it. The guild row tooltip stays short and
-- points here for the detail.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local AW = 360
local ROW_H = 30
local ROW_N = 5
local STEP_N = 5
local STEP_H = 14
local WIN_H = 452
local REFRESH_EVERY = 1.5
local LIST_EVERY = 8

local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

local win
local picked = nil
local rowsView = {}
local lastRefresh = 0
local lastList = 0

local function findPicked()
    if not picked then return nil end
    for _, entry in ipairs(rowsView) do
        if entry.order.bot == picked then return entry.order end
    end
    return nil
end

local function kv(lines, label, value)
    if value and value ~= "" then
        table.insert(lines, "|cffd8a657" .. label .. "|r  " .. value)
    end
end

local function refreshSteps()
    local steps = (picked and TB.OrderStepsList and TB.OrderStepsList(picked)) or {}
    local total = table.getn(steps)
    FauxScrollFrame_Update(win.stepScroll, total, STEP_N, STEP_H)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(win.stepScroll)) or 0
    for i = 1, STEP_N do
        local step = steps[offset + i]
        if step then
            win.stepRows[i]:SetText("|cff9a9a9a" .. step.age .. "|r   " .. step.text)
        else
            win.stepRows[i]:SetText("")
        end
    end
    if total == 0 then win.stepsEmpty:Show() else win.stepsEmpty:Hide() end
end

local function fillDetail(order)
    if not order then
        win.title:SetText(""); win.state:SetText(""); win.info:SetText("")
    else
        win.title:SetText((order.item or "?") .. "  |cffffffff" .. tostring(order.have or 0) .. "/" .. tostring(order.want or 0) .. "|r")
        local stateText = (TB.OrderStateColor and TB.OrderStateColor(order.state) or "") .. (TB.OrderStateLabel and TB.OrderStateLabel(order.state) or "") .. "|r"
        local reason = TB.OrderReasonLabel and TB.OrderReasonLabel(order.reason)
        if reason then stateText = stateText .. "  |cff9a9a9a" .. reason .. "|r" end
        win.state:SetText((TB.OrderTypeLabel and TB.OrderTypeLabel(order.type) or "") .. "  ·  " .. stateText)
        local lines = {}
        kv(lines, "Zone", order.zone)
        kv(lines, "Now", TB.OrderStepLabel and TB.OrderStepLabel(order))
        if order.hours == "inf" then kv(lines, "Farm time", "no limit")
        elseif order.hours and order.hours > 0 then kv(lines, "Farm time", math.floor(order.hours) .. " h") end
        kv(lines, "Difficulty", TB.OrderDifficultyLabel and TB.OrderDifficultyLabel(order.difficulty))
        local need = TB.OrderNeedText and TB.OrderNeedText(order)
        if need then table.insert(lines, need) end
        win.info:SetText(table.concat(lines, "\n"))
    end
    refreshSteps()
end

function TB.RefreshActiveOrders()
    if not win or not win:IsVisible() then return end
    rowsView = TB.GetOrderTree and TB.GetOrderTree() or {}
    local total = table.getn(rowsView)
    FauxScrollFrame_Update(win.scroll, total, ROW_N, ROW_H)
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(win.scroll)) or 0
    for i = 1, ROW_N do
        local row = win.rows[i]
        local entry = rowsView[offset + i]
        if entry then
            local order = entry.order
            row.bot = order.bot
            row.nameText:SetText(string.rep("  ", entry.depth or 0) .. (order.bot or "?"))
            row.infoText:SetText(TB.OrderRowText and TB.OrderRowText(order) or "")
            if order.bot == picked then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.bot = nil
            row:Hide()
        end
    end
    if total == 0 then
        win.empty:Show()
    else
        win.empty:Hide()
    end
    local order = findPicked()
    if not order and total > 0 then
        order = rowsView[1].order
        picked = order.bot
        if TB.RequestOrderSteps then TB.RequestOrderSteps(picked) end
    elseif not order then
        picked = nil
    end
    if order then
        fillDetail(order)
        win.cancelBtn:Enable()
    else
        fillDetail(nil)
        win.cancelBtn:Disable()
    end
    for i = 1, ROW_N do
        local row = win.rows[i]
        if row.bot == picked then row.sel:Show() else row.sel:Hide() end
    end
    lastRefresh = now()
end

local function pick(bot)
    picked = bot
    if bot and TB.RequestOrderSteps then TB.RequestOrderSteps(bot) end
    TB.RefreshActiveOrders()
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerActiveOrdersWindow", TB.frame or UIParent)
    win:SetWidth(AW); win:SetHeight(WIN_H)
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
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerActiveOrdersWindow") end
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -9)
    TB.StyleTitle(title, 14)
    title:SetText("Active orders")
    TB.SetTextColor(title, color("title"))
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseActiveOrders() end)

    local wip = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wip:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    wip:SetWidth(AW - 24); wip:SetJustifyH("LEFT")
    wip:SetText("Work in progress, there may be bugs")
    TB.SetTextColor(wip, { 1, 0.82, 0, 1 })
    win.wipNote = wip

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -50)
    hint:SetWidth(AW - 24); hint:SetJustifyH("LEFT")
    hint:SetText("Click an order to see what the bot is doing.")
    TB.SetTextColor(hint, color("muted"))

    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerActiveOrdersScroll", win, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -66)
    scroll:SetWidth(AW - 28)
    scroll:SetHeight(ROW_N * ROW_H + 4)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_H, TB.RefreshActiveOrders)
    end)
    win.scroll = scroll

    win.rows = {}
    for i = 1, ROW_N do
        local row = CreateFrame("Button", nil, win)
        row:SetWidth(AW - 34); row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -(56 + (i - 1) * ROW_H))
        row:RegisterForClicks("LeftButtonUp")
        TB.ApplySurface(row, "row")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints(row)
        row.sel:SetTexture(0.85, 0.65, 0.34, 0.18)
        row.sel:Hide()
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
        row.nameText:SetWidth(AW - 50); row.nameText:SetJustifyH("LEFT")
        TB.SetTextColor(row.nameText, color("title"))
        row.infoText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.infoText:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -15)
        row.infoText:SetWidth(AW - 50); row.infoText:SetJustifyH("LEFT")
        TB.SetTextColor(row.infoText, color("text"))
        row:SetScript("OnClick", function()
            if this.bot then pick(this.bot) end
        end)
        row:Hide()
        win.rows[i] = row
    end

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -76)
    win.empty:SetWidth(AW - 24); win.empty:SetJustifyH("LEFT")
    win.empty:SetText("No bot has an order right now. Press Order on a bot in the Guild tab to give one.")
    TB.SetTextColor(win.empty, color("muted"))

    local top = 56 + ROW_N * ROW_H + 8
    local rule = win:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -top)
    rule:SetWidth(AW - 24); rule:SetHeight(1)
    rule:SetTexture(0.85, 0.65, 0.34, 0.35)

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(top + 8))
    win.title:SetWidth(AW - 24); win.title:SetJustifyH("LEFT")
    TB.SetTextColor(win.title, color("title"))

    win.state = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.state:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(top + 28))
    win.state:SetWidth(AW - 24); win.state:SetJustifyH("LEFT")

    win.info = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(top + 46))
    win.info:SetWidth(AW - 24); win.info:SetJustifyH("LEFT"); win.info:SetJustifyV("TOP")
    TB.SetTextColor(win.info, color("text"))

    local stepsTop = top + 46 + 66
    local stepsHead = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stepsHead:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -stepsTop)
    stepsHead:SetText("Steps, newest first")
    TB.SetTextColor(stepsHead, color("title"))

    local stepScroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerActiveStepsScroll", win, "FauxScrollFrameTemplate")
    stepScroll:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -(stepsTop + 14))
    stepScroll:SetWidth(AW - 28)
    stepScroll:SetHeight(STEP_N * STEP_H)
    stepScroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(STEP_H, refreshSteps)
    end)
    win.stepScroll = stepScroll
    win.stepRows = {}
    for i = 1, STEP_N do
        local fs = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -(stepsTop + 14 + (i - 1) * STEP_H))
        fs:SetWidth(AW - 46); fs:SetJustifyH("LEFT")
        TB.SetTextColor(fs, color("text"))
        win.stepRows[i] = fs
    end
    win.stepsEmpty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.stepsEmpty:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -(stepsTop + 14))
    win.stepsEmpty:SetText("No steps recorded yet.")
    TB.SetTextColor(win.stepsEmpty, color("muted"))

    win.cancelBtn = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"), "mode")
    win.cancelBtn:SetWidth(110); win.cancelBtn:SetHeight(20)
    win.cancelBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
    win.cancelBtn:SetText("Cancel order")
    win.cancelBtn:SetScript("OnClick", function()
        if picked and TB.ConfirmOrderCancel then TB.ConfirmOrderCancel(picked) end
    end)

    win:SetScript("OnUpdate", function()
        local t = now()
        if t - lastRefresh >= REFRESH_EVERY then TB.RefreshActiveOrders() end
        if t - lastList >= LIST_EVERY then
            lastList = t
            if TB.RequestOrderList then TB.RequestOrderList() end
        end
    end)

    win:Hide()
    TB.activeOrdersWindow = win
end

function TB.OpenActiveOrders()
    if not (TB.HasOrderCapability and TB.HasOrderCapability()) then
        if TB.Print then TB.Print("Orders are not available: the server has not announced order support yet. Try /tbm sync or /reload.") end
        return false
    end
    if not win then
        local ok, err = pcall(createWindow)
        if not ok then
            win = nil
            if TB.Print then TB.Print("Active orders window failed: " .. tostring(err)) end
            return false
        end
    end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseSettings then TB.CloseSettings() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + AW + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    lastList = now()
    if TB.RequestOrderList then TB.RequestOrderList() end
    TB.RefreshActiveOrders()
    return true
end

function TB.CloseActiveOrders()
    if win then win:Hide() end
end

function TB.ToggleActiveOrders()
    if win and win:IsVisible() then TB.CloseActiveOrders() else TB.OpenActiveOrders() end
end
