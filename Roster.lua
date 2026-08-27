-- TortoiseBots/Roster.lua — owned roster + live state model
local TB = TortoiseBots

-- Live state per name: { online, enteredWorld, hasAI, random, grouped, status }
-- status: "offline" | "starting" | "online" | "offline-pending" | "human" | "inviting" | "summoning"
TB.state = TB.state or {}
TB.groupMembers = TB.groupMembers or {} -- name -> bool in player's group

local function getDBRoster()
    if TortoiseBotsDB and TortoiseBotsDB.roster then return TortoiseBotsDB.roster end
    return {}
end

function TB.InitRoster()
    -- ensure state entries for persisted roster
    for name, _ in pairs(getDBRoster()) do
        if not TB.state[name] then TB.state[name] = { status = "offline", online = false } end
    end
end

function TB.GetRosterNames()
    local out = {}
    for n, _ in pairs(getDBRoster()) do table.insert(out, n) end
    -- also include any live-discovered names not yet persisted
    for n, st in pairs(TB.state) do
        if st.online and not getDBRoster()[n] then table.insert(out, n) end
    end
    table.sort(out)
    return out
end

function TB.AddToRoster(name, opts)
    opts = opts or {}
    name = TB.NormalizeName(name)
    if not name then return false, "Invalid name." end
    local db = TortoiseBotsDB
    if not db.roster[name] then
        db.roster[name] = { addedAt = time(), discovered = opts.discovered and true or false }
    end
    if not TB.state[name] then TB.state[name] = { status = "offline", online=false } end
    TB.state[name].discovered = opts.discovered
    return true
end

function TB.RemoveFromRoster(name)
    name = TB.NormalizeName(name)
    if not name then return end
    if TortoiseBotsDB and TortoiseBotsDB.roster then TortoiseBotsDB.roster[name] = nil end
    -- keep state as offline for a moment for UI feedback, then purge if offline
    if TB.state[name] and not TB.state[name].online then TB.state[name] = nil end
end

function TB.SetState(name, fields)
    name = TB.NormalizeName(name)
    if not name then return end
    if not TB.state[name] then TB.state[name] = { status="offline", online=false } end
    for k,v in pairs(fields) do TB.state[name][k]=v end
    if fields.online ~= nil and fields.online then
        -- ensure roster knows about discovered online bots
        if TortoiseBotsDB and TortoiseBotsDB.roster and not TortoiseBotsDB.roster[name] then
            TB.AddToRoster(name, { discovered=true })
        end
    end
end

function TB.MarkAllOfflinePending()
    for _, st in pairs(TB.state) do
        if st.online then
            st.onlinePending = (st.onlinePending or 0) + 1
            if st.onlinePending >= 2 then
                st.online = false; st.status = "offline"; st.enteredWorld = false; st.hasAI = false
            else
                st.status = "offline-pending"
            end
        end
    end
end

function TB.ConfirmSeen(name, info)
    -- info: { enteredWorld, random, hasAI }
    name = TB.NormalizeName(name)
    if not name then return end
    local st = TB.state[name]
    if not st then st = {}; TB.state[name]=st end
    st.online = true; st.onlinePending = 0
    st.enteredWorld = info.enteredWorld
    st.random = info.random
    st.hasAI = info.hasAI
    if st.status == "inviting" or st.status == "summoning" then
        -- keep transient status for a bit, but mark online underneath
    else
        st.status = info.enteredWorld and "online" or "starting"
    end
    -- ensure in roster
    TB.AddToRoster(name, { discovered=true })
end

function TB.GetDisplayRows(filter)
    filter = string.lower(filter or "")
    local rows = {}
    -- union of roster + live online
    local seen = {}
    for _, n in ipairs(TB.GetRosterNames()) do seen[n]=true end
    for n, st in pairs(TB.state) do if st.online then seen[n]=true end end
    for name, _ in pairs(seen) do
        if filter == "" or string.find(string.lower(name), filter, 1, true) then
            local st = TB.state[name] or { status="offline", online=false }
            local inGroup = TB.groupMembers[name] and true or false
            table.insert(rows, { name=name, st=st, inGroup=inGroup })
        end
    end
    table.sort(rows, function(a,b)
        -- online first, then alpha
        if a.st.online ~= b.st.online then return a.st.online end
        return a.name < b.name
    end)
    return rows
end

-- Group membership tracking (accurate, not inferred from .bot)
local gf = CreateFrame("Frame")
gf:RegisterEvent("GROUP_ROSTER_UPDATE")
gf:RegisterEvent("PARTY_MEMBERS_CHANGED")
gf:RegisterEvent("PLAYER_ENTERING_WORLD")
gf:SetScript("OnEvent", function()
    local members = {}
    for i=1, GetNumPartyMembers() do
        local n = UnitName("party"..i)
        if n and n~="" then members[TB.NormalizeName(n) or n]=true end
    end
    -- raid not expected for this addon, but handle
    for i=1, GetNumRaidMembers() do
        local n = UnitName("raid"..i)
        if n and n~="" then members[TB.NormalizeName(n) or n]=true end
    end
    local selfName = UnitName("player")
    if selfName then members[TB.NormalizeName(selfName) or selfName]=true end
    TB.groupMembers = members
    if TB.Refresh then TB.Refresh() end
end)
