-- TortoiseBots/UI.lua
-- Layout (top → bottom):
--   Header (title + close)
--   Filter row (search + Clear + Refresh + count)
--   Scroll list (8 rows, FauxScroll)
--   Add bar (EditBox + Spawn)
--   Bulk bar (Summon/Follow/Stay/Invite/Uninvite All)
--   Selection bar (label + 6 actions for selected bot)
--   Status bar
--
-- Every visual knob lives in Constants.lua. Every helper is a local function
-- so InitUI reads as a flat composition, not a 300-line closure.

local TB = TortoiseBots
local C  = TB.C
local W, H   = C.PANEL_W, C.PANEL_H
local ROW_H, ROW_N = C.ROW_H, C.ROW_N
local COL = C.COLOR

-- ── forward decls (so helpers stay top-level) ───────────────────────────────
local CreateHeader, CreateFilterRow, CreateScroll, CreateRow
local CreateAddBar, CreateBulkBar, CreateSelectionBar, CreateStatusBar
local RefreshCounts, RefreshRows, RefreshSelection

-- ── panel state owned by UI ─────────────────────────────────────────────────
-- TB.frame, TB.scroll, TB.rows, TB.selected, TB.filterText, TB.countLabel, TB.selLabel, TB.statusText, TB.searchBox, TB.addBox

-- ── helpers ─────────────────────────────────────────────────────────────────
local function onRowClick(row)
    if not row.entry then return end
    if arg1 == "RightButton" and not row.entry.st.online then
        TB.RemoveFromRoster(row.entry.name)
        TB.Refresh()
        TB.SetStatus("Removed " .. row.entry.name .. " from roster (offline).", "muted")
        return
    end
    TB.selected = row.entry.name
    TB.Refresh()
end

local function rowTooltip(row)
    if not row.entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.entry.name)
    GameTooltip:AddLine(TB.StatusText(row.entry.st, row.entry.inGroup), 1,1,1)
    if row.entry.st.random then GameTooltip:AddLine("Random bot", COL.muted[1], COL.muted[2], COL.muted[3]) end
    if row.entry.st.hasAI == false and row.entry.st.online then
        GameTooltip:AddLine("No AI yet (starting)", 1, 0.34, 0.28)
    end
    if row.entry.inGroup then GameTooltip:AddLine("In your group", COL.blue[1], COL.blue[2], COL.blue[3]) end
    if not row.entry.st.online then GameTooltip:AddLine("Right-click to remove from roster", COL.muted[1], COL.muted[2], COL.muted[3]) end
    GameTooltip:Show()
end

-- ── section factories ───────────────────────────────────────────────────────

CreateHeader = function(parent)
    local db = TortoiseBotsDB
    parent:SetWidth(W); parent:SetHeight(H)
    parent:SetPoint(db.frame.point or "CENTER", UIParent, db.frame.rpoint or "CENTER", db.frame.x or 0, db.frame.y or 15)
    parent:SetFrameStrata("DIALOG"); parent:SetMovable(true); parent:EnableMouse(true)
    parent:RegisterForDrag("LeftButton")
    parent:SetScript("OnDragStart", function() this:StartMoving() end)
    parent:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local p, _, rp, x, y = this:GetPoint()
        db.frame.point=p; db.frame.rpoint=rp; db.frame.x=x; db.frame.y=y
    end)
    TB.ApplyBackdrop(parent, 0.98, 1.0)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsFrame") end

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(24); icon:SetHeight(24); icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -8)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); icon:SetTexCoord(0.08,0.92,0.08,0.92)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    title:SetText("TortoiseBots  |cffffd200v" .. (TB.version or "?") .. "|r")
    TB.SetTextColor(title, COL.gold)

    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(0.55,0.35,0.08,0.12)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -5); glow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -5); glow:SetHeight(32)

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -3)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(0.48,0.36,0.15,0.70)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -39); divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -39); divider:SetHeight(1)
end

CreateFilterRow = function(parent)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -50); label:SetText("Filter"); TB.SetTextColor(label, COL.muted)

    local search = CreateFrame("EditBox", "TortoiseBotsSearch", parent, "InputBoxTemplate")
    search:SetWidth(170); search:SetHeight(22); search:SetPoint("LEFT", label, "RIGHT", 8, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed",  function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search

    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetWidth(45); clear:SetHeight(18); clear:SetPoint("LEFT", search, "RIGHT", 6, 0); clear:SetText("Clear")
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

    local refresh = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refresh:SetWidth(64); refresh:SetHeight(18); refresh:SetPoint("LEFT", clear, "RIGHT", 8, 0); refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() TB.PollList(true) end)

    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("LEFT", refresh, "RIGHT", 10, 0); count:SetWidth(110); count:SetJustifyH("LEFT"); TB.SetTextColor(count, COL.muted)
    TB.countLabel = count
end

CreateScroll = function(parent)
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -75); scroll:SetWidth(W-24); scroll:SetHeight(ROW_N*ROW_H+4)
    scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh) end)
    TB.scroll = scroll

    TB.rows = {}; TB.selected = nil
    for i = 1, ROW_N do
        local row = CreateRow(scroll, i)
        table.insert(TB.rows, row)
    end
end

CreateRow = function(scroll, index)
    local row = CreateFrame("Frame", nil, scroll)
    row:SetWidth(W-24-22); row:SetHeight(ROW_H-2)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, - (index-1)*ROW_H)
    TB.ApplyBackdrop(row, 0.62, 0.52)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3); row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -4); row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 4)
    row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints(row); row.hover:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(20); row.icon:SetHeight(20); row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.icon:SetTexCoord(0.08,0.92,0.08,0.92); row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 6); row.name:SetWidth(96); row.name:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.icon, "RIGHT", 8, -8); row.status:SetWidth(110); row.status:SetJustifyH("LEFT")

    row:EnableMouse(true); row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function() onRowClick(this) end)
    row:SetScript("OnEnter", function() rowTooltip(this) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function mkBtn(w, label, tip)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(16); b:SetText(label)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip or label); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    row.btnSummon = mkBtn(42, "Summ", "Summon to you (.bot summon)")
    row.btnSummon:SetPoint("RIGHT", row, "RIGHT", -116, 0)
    row.btnSummon:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        if not e.st.online then TB.SendBotCommand(TB.BuildCommand("add", e.name))
        else TB.SendBotCommand(TB.BuildCommand("summon", e.name)) end
    end)

    row.btnFollow = mkBtn(32, "Fol", "Follow (.bot follow)")
    row.btnFollow:SetPoint("LEFT", row.btnSummon, "RIGHT", 2, 0)
    row.btnFollow:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        TB.SendBotCommand(TB.BuildCommand("follow", e.name))
    end)

    row.btnInvite = mkBtn(32, "Inv", "Invite to group (.bot invite)")
    row.btnInvite:SetPoint("LEFT", row.btnFollow, "RIGHT", 2, 0)
    row.btnInvite:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        if e.inGroup then TB.SendBotCommand(TB.BuildCommand("uninvite", e.name))
        else TB.SendBotCommand(TB.BuildCommand("invite", e.name)) end
    end)

    row.btnStay = mkBtn(34, "Stay", "Stay (.bot stay)")
    row.btnStay:SetPoint("LEFT", row.btnInvite, "RIGHT", 2, 0)
    row.btnStay:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        TB.SendBotCommand(TB.BuildCommand("stay", e.name))
    end)

    local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    xBtn:SetWidth(18); xBtn:SetHeight(16); xBtn:SetPoint("LEFT", row.btnStay, "RIGHT", 2, 0); xBtn:SetText("X")
    xBtn:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        TB.SendBotCommand(TB.BuildCommand("remove", e.name))
    end)
    xBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT"); GameTooltip:SetText("Despawn (.bot remove)")
        GameTooltip:AddLine("Right-click row when offline to forget", COL.muted[1], COL.muted[2], COL.muted[3])
        GameTooltip:Show()
    end)
    xBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.btnRemove = xBtn

    return row
end

CreateAddBar = function(parent, anchorFrame)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 2, -10); label:SetText("Add bot:"); TB.SetTextColor(label, COL.muted)

    local box = CreateFrame("EditBox", "TortoiseBotsAddBox", parent, "InputBoxTemplate")
    box:SetWidth(170); box:SetHeight(20); box:SetPoint("LEFT", label, "RIGHT", 8, 0); box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    box:SetScript("OnEnterPressed", function()
        local t = TB.NormalizeName(this:GetText() or "")
        if t and t ~= "" then TB.SendBotCommand(TB.BuildCommand("add", t)); TB.AddToRoster(t); this:SetText(""); TB.Refresh() end
        this:ClearFocus()
    end)
    TB.addBox = box

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(58); btn:SetHeight(18); btn:SetPoint("LEFT", box, "RIGHT", 6, 0); btn:SetText("Spawn")
    btn:SetScript("OnClick", function()
        local t = TB.NormalizeName(box:GetText() or "")
        if not t or t == "" then TB.SetStatus("Enter a character name.", "warn"); return end
        TB.SendBotCommand(TB.BuildCommand("add", t)); TB.AddToRoster(t); box:SetText(""); TB.Refresh()
    end)

    local tip = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip:SetPoint("LEFT", btn, "RIGHT", 8, 0); tip:SetText("same account only"); TB.SetTextColor(tip, COL.muted)

    return label -- anchor for next section
end

CreateBulkBar = function(parent, anchorLabel)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -12); bar:SetWidth(W-24); bar:SetHeight(22)

    local function bulkBtn(label, w, tip, fn)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(18); b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local b1 = bulkBtn("Summon All", 78, "Summon all online bots", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("summon", e.name)) end end
    end); b1:SetPoint("LEFT", bar, "LEFT", 0, 0)

    local b2 = bulkBtn("Follow All", 72, "All follow you", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("follow", e.name)) end end
    end); b2:SetPoint("LEFT", b1, "RIGHT", 4, 0)

    local b3 = bulkBtn("Stay All", 64, "All stay", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("stay", e.name)) end end
    end); b3:SetPoint("LEFT", b2, "RIGHT", 4, 0)

    local b4 = bulkBtn("Invite All", 72, "Invite all online", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online and not e.inGroup then TB.SendBotCommand(TB.BuildCommand("invite", e.name)) end end
    end); b4:SetPoint("LEFT", b3, "RIGHT", 4, 0)

    local b5 = bulkBtn("Uninvite All", 80, "Remove all bots from group", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.inGroup then TB.SendBotCommand(TB.BuildCommand("uninvite", e.name)) end end
    end); b5:SetPoint("LEFT", b4, "RIGHT", 4, 0)

    return bar
end

CreateSelectionBar = function(parent, anchorBar)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchorBar, "BOTTOMLEFT", 2, -8); label:SetWidth(W-28); label:SetJustifyH("LEFT"); TB.SetTextColor(label, COL.text)
    TB.selLabel = label

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4); bar:SetWidth(W-24); bar:SetHeight(20)

    local function selBtn(text, w, tip, fn)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(18); b:SetText(text)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local s1 = selBtn("Follow", 52, "Selected follows", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("follow", TB.selected)) end end)
    s1:SetPoint("LEFT", bar, "LEFT", 0, 0)
    local s2 = selBtn("Stay", 48, "Selected stays", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("stay", TB.selected)) end end)
    s2:SetPoint("LEFT", s1, "RIGHT", 4, 0)
    local s3 = selBtn("Summon", 58, "Summon selected", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("summon", TB.selected)) end end)
    s3:SetPoint("LEFT", s2, "RIGHT", 4, 0)
    local s4 = selBtn("Invite", 52, "Invite/Kick selected", function()
        if not TB.selected then return end
        if TB.IsInGroup(TB.selected) then TB.SendBotCommand(TB.BuildCommand("uninvite", TB.selected))
        else TB.SendBotCommand(TB.BuildCommand("invite", TB.selected)) end
    end); s4:SetPoint("LEFT", s3, "RIGHT", 4, 0)
    local s5 = selBtn("Pull", 44, "Tank pull your target (.bot pullback)", function() TB.SendBotCommand("pullback") end)
    s5:SetPoint("LEFT", s4, "RIGHT", 4, 0)
    local s6 = selBtn("Reset", 48, "Reset AI (.bot command <name> reset)", function()
        if TB.selected then TB.SendBotCommand(TB.BuildCommand("command", TB.selected, "reset")) end
    end); s6:SetPoint("LEFT", s5, "RIGHT", 4, 0)

    TB.selButtons = { s1, s2, s3, s4, s5, s6 }
    return bar
end

CreateStatusBar = function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 10); fs:SetWidth(W-28); fs:SetJustifyH("LEFT"); TB.SetTextColor(fs, COL.muted)
    fs:SetText("Ready. /tb to toggle. Add your alts, then Spawn.")
    TB.statusText = fs
end

-- ── public ──────────────────────────────────────────────────────────────────
function TB.InitUI()
    local main = CreateFrame("Frame", "TortoiseBotsFrame", UIParent)
    CreateHeader(main)
    CreateFilterRow(main)
    CreateScroll(main)
    local addAnchor = CreateAddBar(main, TB.scroll)
    local bulkBar   = CreateBulkBar(main, addAnchor)
    CreateSelectionBar(main, bulkBar)
    CreateStatusBar(main)
    main:Hide()
    TB.frame = main
    TB.Refresh()
end

function TB.SetStatus(msg, kind)
    if not TB.statusText then return end
    msg = msg or ""
    if string.len(msg) > 120 then msg = string.sub(msg, 1, 120) .. "…" end
    local c = COL.muted
    if kind == "ok"      then c = COL.green
    elseif kind == "warn"   then c = COL.red
    elseif kind == "pending" then c = COL.yellow end
    TB.statusText:SetText(msg); TB.SetTextColor(TB.statusText, c)
end

RefreshCounts = function()
    local online = 0
    for _, st in pairs(TB.GetAllState()) do if st.online then online = online + 1 end end
    if TB.countLabel then TB.countLabel:SetText(string.format("%d roster · %d online", TB.GetRosterCount(), online)) end
end

RefreshRows = function(rows)
    FauxScrollFrame_Update(TB.scroll, table.getn(rows), ROW_N, ROW_H)
    local offset = FauxScrollFrame_GetOffset(TB.scroll)
    for i = 1, ROW_N do
        local row = TB.rows[i]
        local e   = rows[i + offset]
        row.entry = e
        if e then
            row:Show()
            row.name:SetText(e.name)
            row.status:SetText(TB.StatusText(e.st, e.inGroup))
            TB.SetTextColor(row.status, TB.StatusColor(e.st))

            if TB.selected == e.name then
                row:SetBackdropColor(0.12, 0.10, 0.04, 0.92)
                row.accent:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
            else
                row:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
                row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)
            end

            local on = e.st.online
            row.btnSummon:SetText(on and "Summ" or "Spawn")
            row.btnSummon:Enable(); row.btnFollow:Enable(); row.btnInvite:Enable(); row.btnStay:Enable(); row.btnRemove:Enable()

            if not on and e.st.status ~= C.STATUS.OFFLINE and e.st.status ~= C.STATUS.OFFLINE_PENDING then
                row.btnFollow:Disable(); row.btnInvite:Disable(); row.btnStay:Disable()
            elseif not on then
                row.btnFollow:Disable(); row.btnInvite:Disable(); row.btnStay:Disable()
            end
            if on and not e.st.enteredWorld then
                row.btnSummon:Disable(); row.btnFollow:Disable(); row.btnStay:Disable()
            end
            if on and e.st.status == C.STATUS.SUMMONING then row.btnSummon:Disable() end

            row.btnInvite:SetText(e.inGroup and "Kick" or "Inv")
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetAlpha(on and 1 or 0.55)
        else
            row:Hide(); row.entry = nil
        end
    end
end

RefreshSelection = function()
    if not TB.selLabel then return end
    if TB.selected then
        local st = TB.GetState(TB.selected)
        local inG = TB.IsInGroup(TB.selected)
        TB.selLabel:SetText("Selected: " .. TB.selected .. "  ·  " .. TB.StatusText(st, inG) .. (inG and " · in group" or ""))
        TB.SetTextColor(TB.selLabel, COL.text)
    else
        TB.selLabel:SetText("Selected: none  — click a row")
        TB.SetTextColor(TB.selLabel, COL.muted)
    end
    if TB.selButtons then
        local hasSel = TB.selected ~= nil
        for _, b in ipairs(TB.selButtons) do if hasSel then b:Enable() else b:Disable() end end
    end
end

function TB.Refresh()
    if not TB.scroll or not TB.rows then return end
    local rows = TB.GetDisplayRows(TB.filterText or "")
    RefreshCounts()
    RefreshRows(rows)
    RefreshSelection()
end

function TB.Toggle()
    if not TB.frame then return end
    if TB.frame:IsVisible() then TB.frame:Hide()
    else TB.frame:Show(); TB.Refresh(); TB.PollList(true) end
end
