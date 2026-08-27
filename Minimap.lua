-- TortoiseBots/Minimap.lua — draggable minimap button. No business logic here.
local TB = TortoiseBots
local C  = TB.C

function TB.InitMinimap()
    local db = TortoiseBotsDB
    local btn = CreateFrame("Button", "TortoiseBotsMinimapButton", Minimap)
    btn:SetWidth(32); btn:SetHeight(32); btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true); btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetWidth(52); bg:SetHeight(52); bg:SetPoint("TOPLEFT", btn, "TOPLEFT", -10, 10)
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18); icon:SetHeight(18); icon:SetPoint("CENTER", btn, "CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01"); icon:SetTexCoord(0.08,0.92,0.08,0.92)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"); hl:SetAllPoints(btn); hl:SetBlendMode("ADD")

    local function updatePos()
        local x, y = db.minimap.x or C.MINIMAP_DEFAULT.x, db.minimap.y or C.MINIMAP_DEFAULT.y
        local ang = math.atan2(y, x)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(ang)*C.MINIMAP_RADIUS, math.sin(ang)*C.MINIMAP_RADIUS)
    end
    updatePos()

    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" then TB.PollList(true); TB.Print("Polling…")
        else TB.Toggle() end
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("TortoiseBots")
        GameTooltip:AddLine("Left-click: toggle panel", 1,1,1)
        GameTooltip:AddLine("Right-click: refresh list", 1,1,1)
        GameTooltip:AddLine("Drag: move button", C.COLOR.muted[1], C.COLOR.muted[2], C.COLOR.muted[3])
        local online = 0; for _, s in pairs(TB.GetAllState()) do if s.online then online = online + 1 end end
        GameTooltip:AddLine(online .. " online", C.COLOR.blue[1], C.COLOR.blue[2], C.COLOR.blue[3])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnDragStart", function()
        this:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px/scale, py/scale
            db.minimap.x, db.minimap.y = px - mx, py - my
            updatePos()
        end)
    end)
    btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)

    TB.minimapButton   = btn
    TB.UpdateMinimapPos = updatePos
end
