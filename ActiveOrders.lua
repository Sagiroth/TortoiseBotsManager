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
local ROW_N = 6
local DETAIL_LINES = 11
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

local function firstLines(text, limit)
    local out, count = {}, 0
    for line in string.gfind(text or "", "[^\n]+") do
        count = count + 1
        if count > limit then
            table.insert(out, "...")
            break
        end
        table.insert(out, line)
    end
    return table.concat(out, "\n")
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
        win.detail:SetText(firstLines(TB.OrderTooltipText and TB.OrderTooltipText(order) or "", DETAIL_LINES))
        win.cancelBtn:Enable()
        win.newBtn:Enable()
    else
        win.detail:SetText("")
        win.cancelBtn:Disable()
        win.newBtn:Disable()
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
    win:SetWidth(AW); win:SetHeight(380)
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

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    hint:SetWidth(AW - 24); hint:SetJustifyH("LEFT")
    hint:SetText("Click an order to see what the bot is doing.")
    TB.SetTextColor(hint, color("muted"))

    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerActiveOrdersScroll", win, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -54)
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
    win.empty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -64)
    win.empty:SetWidth(AW - 24); win.empty:SetJustifyH("LEFT")
    win.empty:SetText("No bot has an order right now. Press Order on a bot in the Guild tab to give one.")
    TB.SetTextColor(win.empty, color("muted"))

    win.detail = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.detail:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(56 + ROW_N * ROW_H + 10))
    win.detail:SetWidth(AW - 24); win.detail:SetJustifyH("LEFT"); win.detail:SetJustifyV("TOP")
    TB.SetTextColor(win.detail, color("text"))

    win.cancelBtn = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"), "mode")
    win.cancelBtn:SetWidth(110); win.cancelBtn:SetHeight(20)
    win.cancelBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
    win.cancelBtn:SetText("Cancel order")
    win.cancelBtn:SetScript("OnClick", function()
        if picked and TB.ConfirmOrderCancel then TB.ConfirmOrderCancel(picked) end
    end)

    win.newBtn = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"), "mode")
    win.newBtn:SetWidth(110); win.newBtn:SetHeight(20)
    win.newBtn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 130, 10)
    win.newBtn:SetText("New order")
    win.newBtn:SetScript("OnClick", function()
        if picked and TB.OpenOrderWindow then TB.OpenOrderWindow(picked) end
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
