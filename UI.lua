-- TortoiseBots/UI.lua
-- Layout (top → bottom):
--   Header (title + close)
--   Filter row (search + Clear + Refresh + count)
--   Scroll list (6 rows, FauxScroll)
--   Add bar (EditBox + Spawn)
--   Party bar (bulk actions + target-scoped Pullback)
--   Selected bar (per-bot public controls + Reset)
--   Status bar
--
-- Grouping principle: no same-scope duplicates.
--   Row: per-bot quick (Summ/Spawn, Follow, Invite) + Remove (X)
--   Party: filtered bulk (Summon, Follow, Invite, Kick) + target Pullback
--   Selected: public single-bot actions + Reset
-- Every visual knob lives in Constants.lua. Helpers are top-level locals.

local TB = TortoiseBots
local C  = TB.C
local W, H   = C.PANEL_W, C.PANEL_H
local ROW_H, ROW_N = C.ROW_H, C.ROW_N
local COL = C.COLOR

-- ── forward decls ───────────────────────────────────────────────────────────
local CreateHeader, CreateFilterRow, CreateScroll, CreateRow
local CreateHeader, CreateFilterRow, CreateScroll, CreateRow
local CreatePartyBar, CreateSelectedBar, CreateStatusBar
local RefreshCounts, RefreshRows, RefreshSelection

local function hasCurrentTarget()
    if not UnitExists then return true end
    return UnitExists("target") and (not UnitIsDead or not UnitIsDead("target"))
end

local function serverSupports(command)
    if not TB.ServerCapabilitiesKnown or not TB.ServerCapabilitiesKnown() then return true end
    return TB.HasServerCommand and TB.HasServerCommand(command) or false
end

-- ── helpers ─────────────────────────────────────────────────────────────────
local function onRowClick(row)
    if not row.entry then return end
    if arg1 == "RightButton" and not row.entry.st.online then
        local name = row.entry.name
        TB.RemoveFromRoster(name)
        TB.Refresh()
        TB.SetStatus("Removed " .. name .. " from roster (offline).", "muted")
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
    if row.entry.st.lastError then
        GameTooltip:AddLine(row.entry.st.lastError, COL.red[1], COL.red[2], COL.red[3])
    end
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
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerFrame") end

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22); icon:SetHeight(22); icon:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD, -7)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle"); icon:SetTexCoord(0.08,0.92,0.08,0.92)

    -- Themed title: Tortoise (gold) + Bots (turtle green) + Manager (ivory) + version
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("|cffd8a657Tortoise|r|cff4ecb5aBots|r |cfffff2ccManager|r  |cffffd200v" .. (TB.version or "?") .. "|r")

    local glow = parent:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(0.55,0.35,0.08,0.12)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -4); glow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -4); glow:SetHeight(30)

    local close = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2,-2)

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(0.48,0.36,0.15,0.70)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", C.PAD, -34); divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -C.PAD, -34); divider:SetHeight(1)
end

CreateFilterRow = function(parent)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); label:SetText("Filter"); TB.SetTextColor(label, COL.muted)

    local search = CreateFrame("EditBox", "TortoiseBotsManagerSearch", parent, "InputBoxTemplate")
    search:SetWidth(135); search:SetHeight(20); search:SetPoint("LEFT", label, "RIGHT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed",  function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search

    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetWidth(40); clear:SetHeight(18); clear:SetPoint("LEFT", search, "RIGHT", C.GAP_BTN, 0); clear:SetText("Clear")
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

    local refresh = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refresh:SetWidth(54); refresh:SetHeight(18); refresh:SetPoint("LEFT", clear, "RIGHT", C.GAP_BTN, 0); refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() TB.PollList(true) end)
    TB.refreshButton = refresh

    local stats = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    stats:SetWidth(46); stats:SetHeight(18); stats:SetPoint("LEFT", refresh, "RIGHT", C.GAP_BTN, 0); stats:SetText("Stats")
    stats:SetScript("OnClick", function() TB.SendBotCommand("stats") end)
    TB.statsButton = stats

    local help = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    help:SetWidth(40); help:SetHeight(18); help:SetPoint("LEFT", stats, "RIGHT", C.GAP_BTN, 0); help:SetText("Help")
    help:SetScript("OnClick", function() TB.SendBotCommand("help") end)
    TB.helpButton = help

    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("LEFT", help, "RIGHT", 6, 0); count:SetWidth(88); count:SetJustifyH("LEFT"); TB.SetTextColor(count, COL.muted)
    TB.countLabel = count
end

CreateScroll = function(parent)
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsManagerScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -24); scroll:SetWidth(W- C.PAD*2); scroll:SetHeight(ROW_N*ROW_H+4)
    scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh) end)
    TB.scroll = scroll

    local rows = {}
    for i = 1, ROW_N do
        local row = CreateRow(scroll, i)
        table.insert(rows, row)
    end
    TB.rows = rows
    TB.selected = nil
end

-- Row: per-bot quick — Summ/Spawn, Follow, Invite — plus Remove (X). Compact 32px.
CreateRow = function(scroll, index)
    local row = CreateFrame("Button", nil, scroll)
    row:SetWidth(W - C.PAD*2 - 18); row:SetHeight(ROW_H-2)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, - (index-1)*ROW_H)
    TB.ApplyBackdrop(row, 0.62, 0.52)

    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetWidth(3); row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3); row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)
    row.accent:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.95)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints(row); row.hover:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(18); row.icon:SetHeight(18); row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexCoord(0.08,0.92,0.08,0.92); row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 5); row.name:SetWidth(102); row.name:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", row.icon, "RIGHT", 6, -7); row.status:SetWidth(102); row.status:SetJustifyH("LEFT")

    row:EnableMouse(true); row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function() onRowClick(this) end)
    row:SetScript("OnEnter", function() rowTooltip(this) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function mkBtn(w, label, tip)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(15); b:SetText(label)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip or label); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    -- 3 quick per-bot + Remove. Fixed right-aligned, no overflow.
    local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    xBtn:SetWidth(18); xBtn:SetHeight(15); xBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0);
    xBtn:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        TB.SendBotCommand(TB.BuildCommand("remove", e.name))
    end)
    xBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT"); GameTooltip:SetText("Remove (.bot remove)")
        GameTooltip:AddLine("Despawns bot. Right-click row when offline to forget.", COL.muted[1], COL.muted[2], COL.muted[3])
        GameTooltip:Show()
    end)
    xBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.btnRemove = xBtn

    row.btnInvite = mkBtn(36, "Invite", "Group invite (.bot invite)")
    row.btnInvite:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)
    row.btnInvite:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        if e.inGroup then TB.SendBotCommand(TB.BuildCommand("uninvite", e.name))
        else TB.SendBotCommand(TB.BuildCommand("invite", e.name)) end
    end)

    row.btnFollow = mkBtn(36, "Follow", "Follow you (.bot follow)")
    row.btnFollow:SetPoint("RIGHT", row.btnInvite, "LEFT", -2, 0)
    row.btnFollow:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        TB.SendBotCommand(TB.BuildCommand("follow", e.name))
    end)

    row.btnSummon = mkBtn(44, "Summ", "Summon to you (.bot summon)")
    row.btnSummon:SetPoint("RIGHT", row.btnFollow, "LEFT", -2, 0)
    row.btnSummon:SetScript("OnClick", function()
        local e = this:GetParent().entry; if not e then return end
        if not e.st.online then TB.SendBotCommand(TB.BuildCommand("add", e.name))
        else TB.SendBotCommand(TB.BuildCommand("summon", e.name)) end
    end)

    return row
end

-- Party bar: filtered bulk scope plus target-scoped pullback (Party tab, first)
CreatePartyBar = function(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); bar:SetWidth(W- C.PAD*2); bar:SetHeight(18)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", bar, "LEFT", 0, 0); title:SetText("Party:"); TB.SetTextColor(title, COL.muted)

    local function btn(label, w, tip, fn)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(17); b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local b1 = btn("Summon All", 76, "Summon all online bots to you", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do
            if e.st.online and e.st.enteredWorld and e.st.status ~= C.STATUS.UNKNOWN
                and e.st.status ~= C.STATUS.FAILED and not e.st.operation and serverSupports("summon") then
                TB.SendBotCommand(TB.BuildCommand("summon", e.name))
            end
        end
    end); b1:SetPoint("LEFT", title, "RIGHT", 6, 0)

    local b2 = btn("Follow All", 72, "All online follow you", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do
            if e.st.online and e.st.enteredWorld and e.st.status ~= C.STATUS.UNKNOWN
                and e.st.status ~= C.STATUS.FAILED and not e.st.operation and serverSupports("follow") then
                TB.SendBotCommand(TB.BuildCommand("follow", e.name))
            end
        end
    end); b2:SetPoint("LEFT", b1, "RIGHT", C.GAP_BTN, 0)

    local b3 = btn("Invite All", 72, "Invite all online to group", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do
            if e.st.online and e.st.enteredWorld and e.st.status ~= C.STATUS.UNKNOWN
                and e.st.status ~= C.STATUS.FAILED and not e.inGroup and not e.st.operation
                and serverSupports("invite") then
                TB.SendBotCommand(TB.BuildCommand("invite", e.name))
            end
        end
    end); b3:SetPoint("LEFT", b2, "RIGHT", C.GAP_BTN, 0)

    local b4 = btn("Kick All", 66, "Uninvite all visible bots in your group", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do
            if e.st.online and e.st.enteredWorld and e.st.status ~= C.STATUS.UNKNOWN
                and e.st.status ~= C.STATUS.FAILED and e.inGroup and not e.st.operation
                and serverSupports("uninvite") then
                TB.SendBotCommand(TB.BuildCommand("uninvite", e.name))
            end
        end
    end); b4:SetPoint("LEFT", b3, "RIGHT", C.GAP_BTN, 0)

    local b5 = btn("Pullback", 64, "Ask a tank bot to use its native pull-and-return strategy on your target (.bot pullback)", function()
        if not serverSupports("pullback") then
            TB.SetStatus("The server does not advertise pullback.", "warn")
        elseif hasCurrentTarget() then
            TB.SendBotCommand("pullback")
        else
            TB.SetStatus("Select a living target first.", "warn")
        end
    end); b5:SetPoint("LEFT", b4, "RIGHT", C.GAP_BTN, 0)

    TB.partyButtons = { summon = b1, follow = b2, invite = b3, kick = b4, pullback = b5 }
    return bar
end

-- Selected bar: public single-bot controls. Always visible below tabs — with divider for organisation.
CreateSelectedBar = function(parent)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); label:SetWidth(W- C.PAD*2); label:SetJustifyH("LEFT"); TB.SetTextColor(label, COL.text)
    TB.selLabel = label

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4); bar:SetWidth(W- C.PAD*2); bar:SetHeight(36)

    local function sbtn(text, w, tip, fn)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(17); b:SetText(text)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local function selectedCommand(verb, tip, width)
        local b = sbtn(verb, width, tip, function()
            if TB.selected then TB.SendBotCommand(TB.BuildCommand(string.lower(verb), TB.selected)) end
        end)
        return b
    end

    local follow = selectedCommand("Follow", "Selected bot follows you (.bot follow)", 52)
    follow:SetPoint("LEFT", bar, "LEFT", 0, 0)
    local stay = selectedCommand("Stay", "Selected bot stays (.bot stay)", 46)
    stay:SetPoint("LEFT", follow, "RIGHT", C.GAP_BTN, 0)
    local guard = selectedCommand("Guard", "Selected bot guards this position (.bot guard)", 50)
    guard:SetPoint("LEFT", stay, "RIGHT", C.GAP_BTN, 0)
    local free = selectedCommand("Free", "Selected bot is free to move (.bot free)", 48)
    free:SetPoint("LEFT", guard, "RIGHT", C.GAP_BTN, 0)
    local status = selectedCommand("Status", "Show lifecycle and movement status (.bot status)", 52)
    status:SetPoint("LEFT", free, "RIGHT", C.GAP_BTN, 0)

    local attack = selectedCommand("Attack", "Selected bot attacks your current target (.bot attack)", 54)
    attack:SetPoint("LEFT", bar, "LEFT", 0, -19)
    local ready = selectedCommand("Ready", "Ask selected bot for a readiness check (.bot ready)", 50)
    ready:SetPoint("LEFT", attack, "RIGHT", C.GAP_BTN, 0)

    local formationIndex = 1
    local formation
    formation = sbtn("Form: " .. C.FORMATIONS[formationIndex], 100, "Cycle the fixed formation catalog (.bot formation)", function()
        if not TB.selected then return end
        TB.SendBotCommand(TB.BuildCommand("formation", TB.selected, C.FORMATIONS[formationIndex]))
        formationIndex = formationIndex + 1
        if formationIndex > table.getn(C.FORMATIONS) then formationIndex = 1 end
        formation:SetText("Form: " .. C.FORMATIONS[formationIndex])
    end)
    formation:SetPoint("LEFT", ready, "RIGHT", C.GAP_BTN, 0)

    local reset = sbtn("Reset", 52, "Reset selected bot AI (.bot command reset)", function()
        if TB.selected then TB.SendBotCommand(TB.BuildCommand("command", TB.selected, "reset")) end
    end)
    reset:SetPoint("LEFT", formation, "RIGHT", C.GAP_BTN, 0)

    TB.selButtons = { follow, stay, guard, free, status, attack, ready, formation, reset }
    TB.followButton, TB.stayButton = follow, stay
    TB.guardButton, TB.freeButton = guard, free
    TB.statusButton, TB.attackButton, TB.readyButton = status, attack, ready
    TB.formationButton, TB.resetButton = formation, reset
    return bar
end

CreateStatusBar = function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", C.PAD, 8); fs:SetWidth(W- C.PAD*2); fs:SetJustifyH("LEFT"); TB.SetTextColor(fs, COL.muted)
    fs:SetText("Ready. /tb to toggle. Add your alts, then Spawn.")
    TB.statusText = fs
end

-- ── public ──────────────────────────────────────────────────────────────────
function TB.InitUI()
    if TB.uiReady then return end
    TB.uiReady = false
    local main = CreateFrame("Frame", "TortoiseBotsManagerFrame", UIParent)
    CreateHeader(main)
    -- Small-screen scaling: 500×395 is roomy on 1080p, too big on 800×600
    if main.SetScale then
        local sh = (GetScreenHeight and GetScreenHeight() or 768)
        if sh < 700 then main:SetScale(0.82)
        elseif sh < 860 then main:SetScale(0.90)
        else main:SetScale(1) end
    end


    -- Tabs: Party (first, all buttons) | Roster (list) — custom backdrop tabs
    local tabBar = CreateFrame("Frame", nil, main)
    tabBar:SetPoint("TOPLEFT", main, "TOPLEFT", C.PAD, -40); tabBar:SetWidth(W- C.PAD*2); tabBar:SetHeight(20)

    local function MakeTab(label, offset)
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetWidth(72); btn:SetHeight(20); btn:SetPoint("LEFT", tabBar, "LEFT", offset, 0)
        btn:EnableMouse(true); btn:RegisterForClicks("LeftButtonUp")
        TB.ApplyBackdrop(btn, 0.88, 0.9)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 1); fs:SetText(label)
        btn.text = fs
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(btn); hl:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.10)
        return btn
    end
    local tabParty = MakeTab("Party", 0)
    local tabRoster = MakeTab("Roster", 76)

    local rosterFrame = CreateFrame("Frame", nil, main)
    rosterFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6); rosterFrame:SetWidth(W- C.PAD*2); rosterFrame:SetHeight(220)
    local partyFrame = CreateFrame("Frame", nil, main)
    partyFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6); partyFrame:SetWidth(W- C.PAD*2); partyFrame:SetHeight(40)

    CreateFilterRow(rosterFrame)
    CreateScroll(rosterFrame)

    local partyBar = CreatePartyBar(partyFrame)
    -- Selected controls: inside Party tab only (with divider below partyBar)
    local divSel = partyFrame:CreateTexture(nil, "ARTWORK")
    divSel:SetTexture(0.48,0.36,0.15,0.30)
    divSel:SetPoint("TOPLEFT", partyBar, "BOTTOMLEFT", 0, -6); divSel:SetPoint("TOPRIGHT", partyBar, "BOTTOMRIGHT", 0, -6); divSel:SetHeight(1)
    local selectedBar = CreateSelectedBar(partyFrame)
    if TB.selLabel then
        TB.selLabel:ClearAllPoints()
        TB.selLabel:SetPoint("TOPLEFT", divSel, "BOTTOMLEFT", 0, -6)
    end
    if selectedBar then
        selectedBar:ClearAllPoints()
        selectedBar:SetPoint("TOPLEFT", TB.selLabel, "BOTTOMLEFT", 0, -4)
    end

    CreateStatusBar(main)

    local function ShowTab(name)
        if name == "party" then
            partyFrame:Show(); rosterFrame:Hide()
            tabParty.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabRoster.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabParty:Disable(); tabRoster:Enable()
        else
            rosterFrame:Show(); partyFrame:Hide()
            tabRoster.text:SetTextColor(COL.gold[1], COL.gold[2], COL.gold[3])
            tabParty.text:SetTextColor(COL.muted[1], COL.muted[2], COL.muted[3])
            tabRoster:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.95)
            tabParty:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], 0.62)
            tabRoster:Disable(); tabParty:Enable()
        end
        TortoiseBotsDB.activeTab = name
    end
    local initial = TortoiseBotsDB.activeTab or "party"
    ShowTab(initial)
    tabParty:SetScript("OnClick", function() ShowTab("party") end)
    tabRoster:SetScript("OnClick", function() ShowTab("roster") end)
    TB.ShowTab = ShowTab
    TB.tabParty = tabParty
    TB.tabRoster = tabRoster
    TB.rosterFrame = rosterFrame
    TB.partyFrame = partyFrame
    local targetWatcher = CreateFrame("Frame", "TortoiseBotsManagerTargetWatcher")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:SetScript("OnEvent", function() TB.Refresh() end)
    main:Hide()
    TB.frame = main
    TB.uiReady = true
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

function TB.IsDangerousCommand(command)
    command = string.lower(TB.Trim(command or ""))
    local dangerous = {
        "destroy", "cheat", "debug", "cdebug", "set value", "give leader",
        "guild promote", "guild demote", "guild remove", "guild leader",
        "sendmail", "mail", "ah bid", "faction", "cast", "logout",
    }
    for _, prefix in ipairs(dangerous) do
        if command == prefix or string.find(command, "^" .. prefix .. "%s") then return true end
    end
    return false
end

RefreshCounts = function()
    local online = 0
    for _, st in pairs(TB.GetAllState()) do if st.online then online = online + 1 end end
    if TB.countLabel then TB.countLabel:SetText(string.format("%d roster · %d online", TB.GetRosterCount(), online)) end
end

RefreshRows = function(rows)
    FauxScrollFrame_Update(TB.scroll, table.getn(rows), ROW_N, ROW_H)
    local offset = FauxScrollFrame_GetOffset(TB.scroll) or 0
    for i = 1, ROW_N do
        local row = TB.rows[i]
        if not row then break end
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
            row.btnSummon:Enable(); row.btnFollow:Enable(); row.btnInvite:Enable(); row.btnRemove:Enable()

            if not on then
                row.btnFollow:Disable(); row.btnInvite:Disable()
            elseif not e.st.enteredWorld then
                row.btnSummon:Disable(); row.btnFollow:Disable(); row.btnInvite:Disable()
            end
            if on then
                if not serverSupports("summon") then row.btnSummon:Disable() end
            elseif not serverSupports("add") then
                row.btnSummon:Disable()
            end
            if not serverSupports("follow") then row.btnFollow:Disable() end
            if not serverSupports(e.inGroup and "uninvite" or "invite") then row.btnInvite:Disable() end
            if not serverSupports("remove") then row.btnRemove:Disable() end
            if e.st.status == C.STATUS.UNKNOWN then
                row.btnSummon:Disable(); row.btnFollow:Disable(); row.btnInvite:Disable()
            end
            if e.st.operation then
                row.btnSummon:Disable(); row.btnFollow:Disable(); row.btnInvite:Disable(); row.btnRemove:Disable()
            end
            row.btnInvite:SetText(e.inGroup and "Kick" or "Invite")
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
        TB.selLabel:SetText("Selected: none — click a row")
        TB.SetTextColor(TB.selLabel, COL.muted)
    end
    if TB.selButtons then
        local hasSel = TB.selected ~= nil
        local selectedState = hasSel and TB.GetState(TB.selected) or nil
        local canAct = selectedState and selectedState.online and selectedState.enteredWorld
            and selectedState.hasAI ~= false and selectedState.status ~= C.STATUS.UNKNOWN
            and selectedState.status ~= C.STATUS.FAILED and not selectedState.operation
        local optional = {
            [TB.followButton] = "follow", [TB.stayButton] = "stay",
            [TB.guardButton] = "guard", [TB.freeButton] = "free", [TB.attackButton] = "attack",
            [TB.readyButton] = "ready", [TB.formationButton] = "formation",
            [TB.resetButton] = "command",
        }
        for _, b in ipairs(TB.selButtons) do
            if b == TB.statusButton then
                if selectedState and selectedState.online and not selectedState.operation and serverSupports("status") then
                    b:Enable()
                else
                    b:Disable()
                end
            elseif b == TB.attackButton then
                if canAct and hasCurrentTarget() and serverSupports(optional[b]) then b:Enable() else b:Disable() end
            elseif optional[b] then
                if canAct and serverSupports(optional[b]) then b:Enable() else b:Disable() end
            elseif canAct then b:Enable() else b:Disable() end
        end

    end
    if TB.RefreshTargetControls then TB.RefreshTargetControls() end
end

function TB.RefreshTargetControls()
    if not TB.partyButtons or not TB.partyButtons.pullback then return end
    if hasCurrentTarget() and serverSupports("pullback") then TB.partyButtons.pullback:Enable()
    else TB.partyButtons.pullback:Disable() end
end

function TB.RefreshPartyLabels()
    if not TB.partyButtons then return end
    local suffix = TB.Trim(TB.filterText or "") == "" and " All" or " Vis"
    TB.partyButtons.summon:SetText("Summon" .. suffix)
    TB.partyButtons.follow:SetText("Follow" .. suffix)
    TB.partyButtons.invite:SetText("Invite" .. suffix)
    TB.partyButtons.kick:SetText("Kick" .. suffix)
end

function TB.Refresh()
    if not TB.uiReady or not TB.frame or not TB.scroll or not TB.rows then return end
    local rows = TB.GetDisplayRows(TB.filterText or "")
    TB.RefreshPartyLabels()
    RefreshCounts()
    RefreshRows(rows)
    RefreshSelection()
end

function TB.Toggle()
    if not TB.uiReady or not TB.frame then return end
    if TB.frame:IsVisible() then TB.frame:Hide()
    else TB.frame:Show(); TB.Refresh(); TB.PollList(true) end
end
