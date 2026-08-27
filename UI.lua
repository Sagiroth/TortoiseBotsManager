-- TortoiseBots/UI.lua — single panel, 520x520, Vanilla 1.12 safe
local TB = TortoiseBots
local PANEL_W, PANEL_H = 520, 520
local ROW_H, ROW_N = 36, 8
local COLORS = {
    gold = {0.95,0.72,0.28},
    text = {0.92,0.90,0.84},
    muted= {0.62,0.60,0.56},
    green= {0.30,0.90,0.45},
    red  = {1.00,0.34,0.28},
    yellow={1.00,0.82,0.10},
    blue = {0.42,0.76,1.00},
    bg   = {0.025,0.032,0.045},
}

local function setCF(fs, c) if fs and c then fs:SetTextColor(c[1],c[2],c[3]) end end
local function applyBackdrop(frame, alpha, borderA)
    frame:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=11,
        insets={left=3,right=3,top=3,bottom=3},
    })
    frame:SetBackdropColor(COLORS.bg[1],COLORS.bg[2],COLORS.bg[3], alpha or 0.96)
    frame:SetBackdropBorderColor(0.48,0.36,0.15, borderA or 0.90)
end

local function statusColor(st)
    if not st then return COLORS.muted end
    if st.status=="online" then return COLORS.green end
    if st.status=="starting" or st.status=="summoning" or st.status=="inviting" then return COLORS.yellow end
    if st.status=="offline-pending" or st.status=="removing" then return COLORS.muted end
    return COLORS.muted
end
local function statusText(st, inGroup)
    if not st or not st.online then
        if st and st.status=="starting" then return "Starting"
        elseif st and st.status=="summoning" then return "Summoning…"
        elseif st and st.status=="inviting" then return "Inviting…"
        elseif st and st.status=="removing" then return "Removing…"
        else return "Offline" end
    end
    if st.enteredWorld==false then return "Starting" end
    if inGroup then return "Online · Group" end
    return "Online"
end

function TB.InitUI()
    local db = TortoiseBotsDB
    local main = CreateFrame("Frame", "TortoiseBotsFrame", UIParent)
    main:SetWidth(PANEL_W); main:SetHeight(PANEL_H)
    main:SetPoint(db.frame.point or "CENTER", UIParent, db.frame.rpoint or "CENTER", db.frame.x or 0, db.frame.y or 15)
    main:SetFrameStrata("DIALOG"); main:SetMovable(true); main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", function() this:StartMoving() end)
    main:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local p,_,rp,x,y = this:GetPoint()
        db.frame.point=p; db.frame.rpoint=rp; db.frame.x=x; db.frame.y=y
    end)
    applyBackdrop(main, 0.98, 1.0); main:Hide()
    TB.frame = main
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsFrame") end

    -- header
    local icon = main:CreateTexture(nil,"ARTWORK")
    icon:SetWidth(24); icon:SetHeight(24); icon:SetPoint("TOPLEFT", main,"TOPLEFT", 14, -8)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); icon:SetTexCoord(0.08,0.92,0.08,0.92)
    local title = main:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("LEFT", icon,"RIGHT", 7,0)
    title:SetText("TortoiseBots  |cffffd200v"..(TB.version or "?").."|r")
    setCF(title, COLORS.gold)
    local hdrGlow = main:CreateTexture(nil,"BACKGROUND")
    hdrGlow:SetTexture(0.55,0.35,0.08,0.12)
    hdrGlow:SetPoint("TOPLEFT", main,"TOPLEFT", 8,-5); hdrGlow:SetPoint("TOPRIGHT", main,"TOPRIGHT", -8,-5); hdrGlow:SetHeight(32)
    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", main,"TOPRIGHT", -3,-3)
    local divider = main:CreateTexture(nil,"ARTWORK")
    divider:SetTexture(0.48,0.36,0.15,0.70); divider:SetPoint("TOPLEFT", main,"TOPLEFT", 12,-39); divider:SetPoint("TOPRIGHT", main,"TOPRIGHT", -12,-39); divider:SetHeight(1)

    -- search + refresh
    local searchLabel = main:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", main,"TOPLEFT", 14,-50); searchLabel:SetText("Filter"); setCF(searchLabel, COLORS.muted)
    local search = CreateFrame("EditBox", "TortoiseBotsSearch", main, "InputBoxTemplate")
    search:SetWidth(170); search:SetHeight(22); search:SetPoint("LEFT", searchLabel,"RIGHT", 8,0)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        TB.filterText = this:GetText() or ""
        TB.Refresh()
    end)
    TB.searchBox = search
    local clearBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    clearBtn:SetWidth(45); clearBtn:SetHeight(18); clearBtn:SetPoint("LEFT", search,"RIGHT", 6,0); clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

    local refreshBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    refreshBtn:SetWidth(64); refreshBtn:SetHeight(18); refreshBtn:SetPoint("LEFT", clearBtn,"RIGHT", 8,0); refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() TB.PollList(true) end)

    local countLabel = main:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    countLabel:SetPoint("LEFT", refreshBtn,"RIGHT", 10,0); countLabel:SetWidth(110); countLabel:SetJustifyH("LEFT"); setCF(countLabel, COLORS.muted)
    TB.countLabel = countLabel

    -- scroll
    local scroll = CreateFrame("ScrollFrame", "TortoiseBotsScroll", main, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", main,"TOPLEFT", 12, -75); scroll:SetWidth(PANEL_W-24); scroll:SetHeight(ROW_N*ROW_H+4)
    TB.scroll = scroll

    -- rows
    TB.rows = {}
    TB.selected = nil
    for i=1, ROW_N do
        local row = CreateFrame("Frame", nil, main)
        row:SetWidth(PANEL_W-24-22); row:SetHeight(ROW_H-2)
        row:SetPoint("TOPLEFT", scroll,"TOPLEFT", 0, - (i-1)*ROW_H)
        applyBackdrop(row, 0.62, 0.52)
        row.accent = row:CreateTexture(nil,"ARTWORK")
        row.accent:SetWidth(3); row.accent:SetPoint("TOPLEFT", row,"TOPLEFT", 3,-4); row.accent:SetPoint("BOTTOMLEFT", row,"BOTTOMLEFT", 3,4)
        row.accent:SetTexture(0.78,0.53,0.14,0.95)
        row.hover = row:CreateTexture(nil,"HIGHLIGHT")
        row.hover:SetAllPoints(row); row.hover:SetTexture(0.95,0.72,0.28,0.08)
        row.icon = row:CreateTexture(nil,"ARTWORK")
        row.icon:SetWidth(20); row.icon:SetHeight(20); row.icon:SetPoint("LEFT", row,"LEFT", 10,0); row.icon:SetTexCoord(0.08,0.92,0.08,0.92)
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.name = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.icon,"RIGHT", 8,6); row.name:SetWidth(96); row.name:SetJustifyH("LEFT")
        row.status = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row.icon,"RIGHT", 8,-8); row.status:SetWidth(110); row.status:SetJustifyH("LEFT")
        row:EnableMouse(true)
        row:SetScript("OnClick", function()
            if not this.entry then return end
            if arg1=="RightButton" then
                -- right click: quick remove from roster if offline
                if not this.entry.st.online then
                    TB.RemoveFromRoster(this.entry.name); TB.Refresh(); TB.SetStatus("Removed "..this.entry.name.." from roster (offline).","muted")
                end
                return
            end
            TB.selected = this.entry.name
            TB.Refresh()
        end)
        row:SetScript("OnEnter", function()
            if this.entry then
                GameTooltip:SetOwner(this,"ANCHOR_RIGHT")
                GameTooltip:SetText(this.entry.name)
                GameTooltip:AddLine(statusText(this.entry.st, this.entry.inGroup), 1,1,1)
                if this.entry.st.random then GameTooltip:AddLine("Random bot", 0.62,0.60,0.56) end
                if this.entry.st.hasAI==false and this.entry.st.online then GameTooltip:AddLine("No AI yet (starting)",1,0.34,0.28) end
                if this.entry.inGroup then GameTooltip:AddLine("In your group",0.42,0.76,1.00) end
                if not this.entry.st.online then GameTooltip:AddLine("Right-click to remove from roster",0.62,0.60,0.56) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- per-row buttons: Summ / Fol / Inv / Stay / X
        local function mkBtn(w, label, tip)
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetWidth(w); b:SetHeight(16)
            b:SetText(label)
            b:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip or label); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return b
        end
        row.btnSummon = mkBtn(42,"Summ","Summon to you (.bot summon)")
        row.btnSummon:SetPoint("RIGHT", row,"RIGHT", -116,0)
        row.btnSummon:SetScript("OnClick", function()
            local e = this:GetParent().entry; if not e then return end
            if not e.st.online then TB.SendBotCommand(TB.BuildCommand("add", e.name))
            else TB.SendBotCommand(TB.BuildCommand("summon", e.name)) end
        end)
        row.btnFollow = mkBtn(32,"Fol","Follow (.bot follow)")
        row.btnFollow:SetPoint("LEFT", row.btnSummon,"RIGHT", 2,0)
        row.btnFollow:SetScript("OnClick", function()
            local e = this:GetParent().entry; if not e then return end
            TB.SendBotCommand(TB.BuildCommand("follow", e.name))
        end)
        row.btnInvite = mkBtn(32,"Inv","Invite to group (.bot invite)")
        row.btnInvite:SetPoint("LEFT", row.btnFollow,"RIGHT", 2,0)
        row.btnInvite:SetScript("OnClick", function()
            local e = this:GetParent().entry; if not e then return end
            if e.inGroup then TB.SendBotCommand(TB.BuildCommand("uninvite", e.name))
            else TB.SendBotCommand(TB.BuildCommand("invite", e.name)) end
        end)
        row.btnStay = mkBtn(34,"Stay","Stay (.bot stay)")
        row.btnStay:SetPoint("LEFT", row.btnInvite,"RIGHT", 2,0)
        row.btnStay:SetScript("OnClick", function()
            local e = this:GetParent().entry; if not e then return end
            TB.SendBotCommand(TB.BuildCommand("stay", e.name))
        end)
        -- X is small, separate
        local xBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        xBtn:SetWidth(18); xBtn:SetHeight(16); xBtn:SetPoint("LEFT", row.btnStay,"RIGHT", 2,0); xBtn:SetText("X")
        xBtn:SetScript("OnClick", function()
            local e = this:GetParent().entry; if not e then return end
            TB.SendBotCommand(TB.BuildCommand("remove", e.name))
            -- also schedule roster cleanup after poll confirms
        end)
        xBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText("Despawn (.bot remove)"); GameTooltip:AddLine("Right-click row when offline to forget",0.62,0.60,0.56); GameTooltip:Show()
        end)
        xBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.btnRemove = xBtn

        table.insert(TB.rows, row)
    end
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_H, TB.Refresh)
    end)

    -- add bar
    local addLabel = main:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", scroll,"BOTTOMLEFT", 2, -10); addLabel:SetText("Add bot:"); setCF(addLabel, COLORS.muted)
    local addBox = CreateFrame("EditBox", "TortoiseBotsAddBox", main, "InputBoxTemplate")
    addBox:SetWidth(170); addBox:SetHeight(20); addBox:SetPoint("LEFT", addLabel,"RIGHT", 8,0); addBox:SetAutoFocus(false)
    addBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    addBox:SetScript("OnEnterPressed", function()
        local t = this:GetText() or ""
        t = TB.NormalizeName(t)
        if t and t~="" then TB.SendBotCommand(TB.BuildCommand("add", t)); TB.AddToRoster(t); this:SetText(""); TB.Refresh() end
        this:ClearFocus()
    end)
    TB.addBox = addBox
    local addBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
    addBtn:SetWidth(58); addBtn:SetHeight(18); addBtn:SetPoint("LEFT", addBox,"RIGHT", 6,0); addBtn:SetText("Spawn")
    addBtn:SetScript("OnClick", function()
        local t = addBox:GetText() or ""
        t = TB.NormalizeName(t)
        if not t or t=="" then TB.SetStatus("Enter a character name.", "warn"); return end
        TB.SendBotCommand(TB.BuildCommand("add", t)); TB.AddToRoster(t); addBox:SetText(""); TB.Refresh()
    end)
    local addTip = main:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    addTip:SetPoint("LEFT", addBtn,"RIGHT", 8,0); addTip:SetText("same account only"); setCF(addTip, COLORS.muted)

    -- bulk bar
    local bulk = CreateFrame("Frame", nil, main)
    bulk:SetPoint("TOPLEFT", addLabel,"BOTTOMLEFT", 0, -12); bulk:SetWidth(PANEL_W-24); bulk:SetHeight(22)
    local function bulkBtn(label, w, tip, fn)
        local b = CreateFrame("Button", nil, bulk, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(18); b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local b1 = bulkBtn("Summon All", 78, "Summon all online bots", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("summon", e.name)) end end
    end)
    b1:SetPoint("LEFT", bulk,"LEFT", 0,0)
    local b2 = bulkBtn("Follow All", 72, "All follow you", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("follow", e.name)) end end
    end)
    b2:SetPoint("LEFT", b1,"RIGHT", 4,0)
    local b3 = bulkBtn("Stay All", 64, "All stay", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online then TB.SendBotCommand(TB.BuildCommand("stay", e.name)) end end
    end)
    b3:SetPoint("LEFT", b2,"RIGHT", 4,0)
    local b4 = bulkBtn("Invite All", 72, "Invite all online", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.st.online and not e.inGroup then TB.SendBotCommand(TB.BuildCommand("invite", e.name)) end end
    end)
    b4:SetPoint("LEFT", b3,"RIGHT", 4,0)
    local b5 = bulkBtn("Uninvite All", 80, "Remove all bots from group", function()
        for _, e in ipairs(TB.GetDisplayRows(TB.filterText or "")) do if e.inGroup then TB.SendBotCommand(TB.BuildCommand("uninvite", e.name)) end end
    end)
    b5:SetPoint("LEFT", b4,"RIGHT", 4,0)

    -- selection bar
    local selLabel = main:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    selLabel:SetPoint("TOPLEFT", bulk,"BOTTOMLEFT", 2, -8); selLabel:SetWidth(PANEL_W-28); selLabel:SetJustifyH("LEFT"); setCF(selLabel, COLORS.text)
    TB.selLabel = selLabel

    local selBar = CreateFrame("Frame", nil, main)
    selBar:SetPoint("TOPLEFT", selLabel,"BOTTOMLEFT", 0, -4); selBar:SetWidth(PANEL_W-24); selBar:SetHeight(20)
    local function selBtn(label,w,tip,fn)
        local b = CreateFrame("Button", nil, selBar, "UIPanelButtonTemplate")
        b:SetWidth(w); b:SetHeight(18); b:SetText(label)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    local sb1 = selBtn("Follow", 52, "Selected follows", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("follow", TB.selected)) end end)
    sb1:SetPoint("LEFT", selBar,"LEFT", 0,0)
    local sb2 = selBtn("Stay", 48, "Selected stays", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("stay", TB.selected)) end end)
    sb2:SetPoint("LEFT", sb1,"RIGHT", 4,0)
    local sb3 = selBtn("Summon", 58, "Summon selected", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("summon", TB.selected)) end end)
    sb3:SetPoint("LEFT", sb2,"RIGHT", 4,0)
    local sb4 = selBtn("Invite", 52, "Invite/Kick selected", function()
        if not TB.selected then return end
        local st = TB.state[TB.selected]
        local inG = TB.groupMembers[TB.selected]
        if inG then TB.SendBotCommand(TB.BuildCommand("uninvite", TB.selected))
        else TB.SendBotCommand(TB.BuildCommand("invite", TB.selected)) end
    end)
    sb4:SetPoint("LEFT", sb3,"RIGHT", 4,0)
    local sb5 = selBtn("Pull", 44, "Tank pull your target (.bot pullback)", function() TB.SendBotCommand("pullback") end)
    sb5:SetPoint("LEFT", sb4,"RIGHT", 4,0)
    local sb6 = selBtn("Reset", 48, "Reset AI (.bot command <name> reset)", function() if TB.selected then TB.SendBotCommand(TB.BuildCommand("command", TB.selected, "reset")) end end)
    sb6:SetPoint("LEFT", sb5,"RIGHT", 4,0)
    TB.selButtons = {sb1,sb2,sb3,sb4,sb5,sb6}

    -- status bar
    local status = main:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", main,"BOTTOMLEFT", 14, 10); status:SetWidth(PANEL_W-28); status:SetJustifyH("LEFT"); setCF(status, COLORS.muted)
    status:SetText("Ready. /tb to toggle. Add your alts, then Spawn.")
    TB.statusText = status

    -- initial
    TB.Refresh()
end

function TB.SetStatus(msg, kind)
    if not TB.statusText then return end
    msg = msg or ""
    if string.len(msg) > 120 then msg = string.sub(msg, 1, 120) .. "…" end
    local c = COLORS.muted
    if kind=="ok" then c=COLORS.green elseif kind=="warn" then c=COLORS.red elseif kind=="pending" then c=COLORS.yellow end
    TB.statusText:SetText(msg)
    setCF(TB.statusText, c)
end

function TB.Refresh()
    if not TB.scroll or not TB.rows then return end
    local filter = TB.filterText or ""
    local rows = TB.GetDisplayRows(filter)
    local total, online = 0, 0
    for _, e in pairs(TB.state) do total=total+1; if e.online then online=online+1 end end
    -- roster count
    local rosterN = 0; for _ in pairs(TortoiseBotsDB and TortoiseBotsDB.roster or {}) do rosterN=rosterN+1 end
    if TB.countLabel then TB.countLabel:SetText(string.format("%d roster · %d online", rosterN, online)) end

    FauxScrollFrame_Update(TB.scroll, table.getn(rows), ROW_N, ROW_H)
    local offset = FauxScrollFrame_GetOffset(TB.scroll)
    for i=1, ROW_N do
        local row = TB.rows[i]
        local idx = i + offset
        local e = rows[idx]
        row.entry = e
        if e then
            row:Show()
            row.name:SetText(e.name)
            row.status:SetText(statusText(e.st, e.inGroup))
            setCF(row.status, statusColor(e.st))
            -- highlight selected
            if TB.selected == e.name then
                row:SetBackdropColor(0.12,0.10,0.04, 0.92)
                row.accent:SetTexture(0.95,0.72,0.28,1)
            else
                row:SetBackdropColor(COLORS.bg[1],COLORS.bg[2],COLORS.bg[3], 0.62)
                row.accent:SetTexture(0.78,0.53,0.14,0.95)
            end
            -- buttons enable
            local on = e.st.online
            local starting = (e.st.status=="starting" or e.st.status=="summoning" or e.st.status=="inviting")
            row.btnSummon:SetText(on and "Summ" or "Spawn")
            row.btnSummon:Enable(); row.btnFollow:Enable(); row.btnInvite:Enable(); row.btnStay:Enable(); row.btnRemove:Enable()
            -- disable per rules
            if not on and e.st.status~="offline" and e.st.status~="offline-pending" then
                -- starting/summoning: disable most
                row.btnFollow:Disable(); row.btnInvite:Disable(); row.btnStay:Disable()
            elseif not on then
                row.btnFollow:Disable(); row.btnInvite:Disable(); row.btnStay:Disable()
                -- summon becomes spawn
            end
            if on and not e.st.enteredWorld then
                row.btnSummon:Disable(); row.btnFollow:Disable(); row.btnStay:Disable()
            end
            if on and e.st.status=="summoning" then row.btnSummon:Disable() end
            -- invite label
            row.btnInvite:SetText(e.inGroup and "Kick" or "Inv")
            -- icon: try class (future), else question
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetAlpha(on and 1 or 0.55)
        else
            row:Hide(); row.entry=nil
        end
    end
    -- selection label
    if TB.selLabel then
        if TB.selected then
            local st = TB.state[TB.selected]
            local inG = TB.groupMembers[TB.selected]
            TB.selLabel:SetText("Selected: " .. TB.selected .. "  ·  " .. statusText(st, inG) .. (inG and " · in group" or ""))
            setCF(TB.selLabel, COLORS.text)
        else
            TB.selLabel:SetText("Selected: none  — click a row")
            setCF(TB.selLabel, COLORS.muted)
        end
    end
    if TB.selButtons then
        local hasSel = TB.selected ~= nil
        for _, b in ipairs(TB.selButtons) do if hasSel then b:Enable() else b:Disable() end end
    end
end

function TB.Toggle()
    if not TB.frame then return end
    if TB.frame:IsVisible() then TB.frame:Hide() else TB.frame:Show(); TB.Refresh(); TB.PollList(true) end
end
