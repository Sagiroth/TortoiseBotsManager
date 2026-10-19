-- TortoiseBotsManager/Utils.lua — pure, testable helpers. No frame creation.
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
    if st.status == C.STATUS.FAILED then return c.red end
    if st.status == C.STATUS.UNKNOWN then return c.red end
    if st.status == C.STATUS.ONLINE then return c.green end
    if st.status == C.STATUS.QUEUED or st.status == C.STATUS.COMMANDING
        or st.status == C.STATUS.STARTING or st.status == C.STATUS.SUMMONING
        or st.status == C.STATUS.INVITING or st.status == C.STATUS.KICKING
        or st.status == C.STATUS.REMOVING then
        return c.yellow
    end
    return c.muted
end

function TB.StatusText(st, inGroup)
    local S = C.STATUS
    if not st then return "Offline" end
    if st.operation and st.operation.verb == "status" then return "Checking…" end
    if st.status == S.FAILED then return "Failed" end
    if st.status == S.UNKNOWN then return "Unknown" end
    if st.status == S.QUEUED then return "Queued" end
    if st.status == S.SUMMONING then return "Summoning…" end
    if st.status == S.INVITING then return "Inviting…" end
    if st.status == S.KICKING then return "Kicking…" end
    if st.status == S.REMOVING then return "Removing…" end
    if st.status == S.COMMANDING then return "Working…" end
    if not st or not st.online then
        if st and st.status == S.STARTING  then return "Starting" end
        if st and st.status == S.OFFLINE_PENDING then return "Checking…" end
        return "Offline"
    end
    if st.enteredWorld == false then return "Starting" end
    if st.altBot then return "Alt-bot · Playing alone" end
    if st.movement and st.movement ~= "" and st.movement ~= "custom" then
        local movement = string.gsub(st.movement, "^%l", string.upper)
        if inGroup then return "Online · Group · " .. movement end
        return "Online · " .. movement
    end
    if inGroup then return "Online · Group" end
    return "Online"
end

function TB.GetClassColor(classId)
    local colors = (C and C.CLASS_COLORS) or {}
    if classId and colors[classId] then
        return colors[classId]
    end
    return { 0.92, 0.90, 0.84, hex = "ffebe6d6" }
end

function TB.StatusBadge(st, inGroup)
    local S = C.STATUS
    if not st then return "|cff757575○ Offline|r" end
    if st.operation and st.operation.verb == "status" then return "|cffffb300● Checking…|r" end
    if st.status == S.FAILED then return "|cffff5555● Failed|r" end
    if st.status == S.UNKNOWN then return "|cffff5555● Unknown|r" end
    if st.status == S.QUEUED then return "|cffffb300● Queued|r" end
    if st.status == S.SUMMONING then return "|cffffb300● Summoning…|r" end
    if st.status == S.INVITING then return "|cffffb300● Inviting…|r" end
    if st.status == S.KICKING then return "|cffffb300● Kicking…|r" end
    if st.status == S.REMOVING then return "|cffffb300● Removing…|r" end
    if st.status == S.COMMANDING then return "|cffffb300● Working…|r" end
    if not st.online then
        if st.status == S.STARTING then return "|cffffb300● Starting|r" end
        if st.status == S.OFFLINE_PENDING then return "|cffffb300● Checking…|r" end
        return "|cff757575○ Offline|r"
    end
    if st.enteredWorld == false then return "|cffffb300● Starting|r" end
    if st.altBot then return "|cffb388ff● Alt-bot|r · Playing alone" end
    if inGroup then
        if st.movement and st.movement ~= "" and st.movement ~= "custom" then
            local mv = string.gsub(st.movement, "^%l", string.upper)
            return "|cff42a5f5● Group|r · " .. mv
        end
        return "|cff42a5f5● Group|r"
    end
    if st.movement and st.movement ~= "" and st.movement ~= "custom" then
        local mv = string.gsub(st.movement, "^%l", string.upper)
        return "|cff4ecb5a● Online|r · " .. mv
    end
    return "|cff4ecb5a● Online|r"
end

-- table
function TB.CountKeys(t)
    local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n
end

-- ── Unified Role Policy ─────────────────────────────────────────────────────
TB.Roles = {}

function TB.Roles.GetClassRoles(classId)
    if type(classId) == "string" and TB.C and TB.C.CLASS_NAME_TO_ID then
        classId = TB.C.CLASS_NAME_TO_ID[classId] or classId
    end
    return (TB.C and TB.C.CLASS_ROLES and TB.C.CLASS_ROLES[classId]) or {}
end

function TB.Roles.FindRole(classId, roleId)
    if not roleId and type(classId) == "string" then
        roleId = classId
        classId = nil
    end
    if not roleId then return nil end
    local lowerRole = type(roleId) == "string" and string.lower(roleId) or nil
    if classId then
        local roles = TB.Roles.GetClassRoles(classId)
        for _, r in ipairs(roles) do
            if r.id == roleId or (lowerRole and r.label and string.lower(r.label) == lowerRole) then
                return r
            end
        end
        return nil
    end
    if TB.C and TB.C.CLASS_ROLES then
        for _, roles in pairs(TB.C.CLASS_ROLES) do
            for _, r in ipairs(roles) do
                if r.id == roleId or (lowerRole and r.label and string.lower(r.label) == lowerRole) then
                    return r
                end
            end
        end
    end
    return nil
end

function TB.Roles.GetBotRole(botName, classId)
    local dbRoles = (TortoiseBotsDB and TortoiseBotsDB.botRoles) or {}
    local currentId = dbRoles[botName]
    local roles = TB.Roles.GetClassRoles(classId)
    if not currentId and roles[1] then
        currentId = roles[1].id
    end
    return currentId, TB.Roles.FindRole(classId, currentId)
end

function TB.Roles.GetPlayerRole(classId)
    local roleId = TortoiseBotsDB and TortoiseBotsDB.playerRole
    local roles = TB.Roles.GetClassRoles(classId)
    if not roleId and roles[1] then
        roleId = roles[1].id
    end
    return roleId, TB.Roles.FindRole(classId, roleId)
end

function TB.Roles.GetRoleLabel(classId, roleId, fallback)
    if not roleId and type(classId) == "string" then
        roleId = classId
        classId = nil
    end
    local role = TB.Roles.FindRole(classId, roleId)
    if role then return role.label end
    return fallback or roleId or "Default"
end

function TB.Roles.GetPlayerRoleToken(roleId)
    if roleId == "tank" then return "tank" end
    if roleId == "heal" then return "healer" end
    return "dps"
end

function TB.Roles.SetPlayerRole(role, classId)
    local roleDef = type(role) == "table" and role or TB.Roles.FindRole(classId, role)
    if not roleDef then return false end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.playerRole = roleDef.id
    local token = TB.Roles.GetPlayerRoleToken(roleDef.id)
    TB.SendBotCommand("role self " .. token)
    if TB.Print then TB.Print("Your role set to " .. roleDef.label) end
    return true
end

function TB.Roles.SetBotRole(botName, role, classId)
    local roleDef = type(role) == "table" and role or TB.Roles.FindRole(classId, role)
    if not roleDef or not botName then return false end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.botRoles = TortoiseBotsDB.botRoles or {}
    local previousRole = TortoiseBotsDB.botRoles[botName]
    TortoiseBotsDB.botRoles[botName] = roleDef.id

    if roleDef.id == "tank" then
        TB.SendBotCommand("role " .. botName .. " tank")
    else
        if previousRole == "tank" then
            TB.SendBotCommand("role " .. botName .. " clear")
        end
        if roleDef.strat and roleDef.strat ~= "" then
            TB.SendBotCommand("command " .. botName .. " " .. roleDef.strat)
        end
    end
    if TB.Print then TB.Print(botName .. " role set to " .. roleDef.label) end
    return true
end

function TB.Roles.CycleBotRole(botName, classId)
    local roles = TB.Roles.GetClassRoles(classId)
    local roleCount = table.getn(roles)
    if roleCount == 0 then return nil end
    local currentId = (TortoiseBotsDB and TortoiseBotsDB.botRoles and TortoiseBotsDB.botRoles[botName])
    local nextIndex = 1
    for idx, r in ipairs(roles) do
        if r.id == currentId then
            nextIndex = math.mod(idx, roleCount) + 1
            break
        end
    end
    local newRole = roles[nextIndex]
    TB.Roles.SetBotRole(botName, newRole, classId)
    return newRole
end

