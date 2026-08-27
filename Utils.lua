-- TortoiseBots/Utils.lua — pure, testable helpers. No frame creation.
local TB = TortoiseBots
local C = TB.C

-- strings
function TB.Trim(s)
    s = s or ""
    s = string.gsub(s, "^%s+", "")
    return string.gsub(s, "%s+$", "")
end

function TB.NormalizeName(s)
    s = TB.Trim(s)
    if s == "" then return nil end
    s = string.lower(s)
    s = string.gsub(s, "^%l", string.upper) -- capitalize
    return s
end

-- colors / ui helpers (no side effects beyond frame)
function TB.SetTextColor(fs, rgb)
    if fs and rgb then fs:SetTextColor(rgb[1], rgb[2], rgb[3]) end
end

function TB.ApplyBackdrop(frame, alpha, borderA)
    local c = C.COLOR
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 11,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], alpha or 0.96)
    frame:SetBackdropBorderColor(0.48, 0.36, 0.15, borderA or 0.90)
end

function TB.StatusColor(st)
    local c = C.COLOR
    if not st then return c.muted end
    if st.status == C.STATUS.ONLINE then return c.green end
    if st.status == C.STATUS.STARTING or st.status == C.STATUS.SUMMONING or st.status == C.STATUS.INVITING then
        return c.yellow
    end
    return c.muted
end

function TB.StatusText(st, inGroup)
    local S = C.STATUS
    if not st or not st.online then
        if st and st.status == S.STARTING  then return "Starting" end
        if st and st.status == S.SUMMONING then return "Summoning…" end
        if st and st.status == S.INVITING  then return "Inviting…" end
        if st and st.status == S.REMOVING  then return "Removing…" end
        return "Offline"
    end
    if st.enteredWorld == false then return "Starting" end
    if inGroup then return "Online · Group" end
    return "Online"
end

-- table
function TB.CountKeys(t)
    local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n
end
