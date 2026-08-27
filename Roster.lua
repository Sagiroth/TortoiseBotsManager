-- TortoiseBotsManager/Roster.lua
-- Owner of two things:
--   1) persisted roster  (TortoiseBotsDB.roster)  — names you added, survives reload
--   2) live state        (private `state`)         — online/starting/offline per name, plus group
--
-- Invariant: server is truth. `state` is optimistic and reconciled on every
-- `.bot list` reply. No caller outside this file touches `state` directly —
-- use GetState / GetDisplayRows / IsInGroup.

local TB = TortoiseBots
local C = TB.C

-- ── private state ───────────────────────────────────────────────────────────
-- state[Name] = { online=bool, enteredWorld=bool, hasAI=bool, random=bool,
--                 status=STATUS.*, onlinePending=0|1, discovered=bool }
local state = {}
local groupMembers = {} -- [Name]=true if in player's party/raid

-- poll reconciliation: which names were seen in the current .bot list window
local pollSeen = {}      -- [Name]=true for this poll
local pollActive = false
local pollGotAny = false -- did we receive any list/noBots line this window?

-- expose read-only snapshots for UI/tooltips (no mutation)
TB._debugState = state
TB._debugGroup = groupMembers

local function dbRoster()
    if TortoiseBotsDB and TortoiseBotsDB.roster then return TortoiseBotsDB.roster end
    return {}
end

-- ── lifecycle ───────────────────────────────────────────────────────────────
function TB.InitRoster()
    for name, _ in pairs(dbRoster()) do
        if not state[name] then state[name] = { status = C.STATUS.OFFLINE, online = false } end
    end
end

-- ── poll window ─────────────────────────────────────────────────────────────
function TB.BeginPoll()
    for k in pairs(pollSeen) do pollSeen[k]=nil end
    pollActive = true
    pollGotAny = false
end

function TB.MarkPollSeen(name)
    name = TB.NormalizeName(name)
    if name then pollSeen[name]=true; pollGotAny=true end
end

function TB.MarkPollGotAny()
    pollGotAny = true
end

-- Called ~1.2s after .bot list was sent, once replies should have arrived.
-- If we got at least one list/noBots line, any online name not seen is stale.
-- Requires 2 consecutive misses to go offline (avoids flicker on lag).
function TB.ReconcilePoll()
    if not pollActive then return end
    if not pollGotAny then pollActive=false; return end -- no reply yet / lag
    pollActive=false
    for name, st in pairs(state) do
        if st.online and not pollSeen[name] then
            st.onlinePending = (st.onlinePending or 0) + 1
            if st.onlinePending >= 2 then
                st.online=false; st.status=C.STATUS.OFFLINE
                st.enteredWorld=false; st.hasAI=false
            else
                st.status=C.STATUS.OFFLINE_PENDING
            end
        end
    end
    if TB.Refresh then TB.Refresh() end
end

-- ── roster (persisted) ──────────────────────────────────────────────────────
function TB.GetRosterNames()
    local out, seen = {}, {}
    for n in pairs(dbRoster()) do seen[n]=true end
    for n, st in pairs(state) do if st.online and not seen[n] then seen[n]=true end end
    for n in pairs(seen) do table.insert(out, n) end
    table.sort(out)
    return out
end

function TB.GetRosterCount() return TB.CountKeys(dbRoster()) end

function TB.AddToRoster(name, opts)
    opts = opts or {}
    name = TB.NormalizeName(name)
    if not name then return false, "Invalid name." end
    local db = TortoiseBotsDB
    if not db.roster[name] then
        db.roster[name] = { addedAt = time(), discovered = opts.discovered and true or false }
    end
    if not state[name] then state[name] = { status = C.STATUS.OFFLINE, online = false } end
    state[name].discovered = opts.discovered
    return true
end

function TB.RemoveFromRoster(name)
    name = TB.NormalizeName(name)
    if not name then return end
    if TortoiseBotsDB and TortoiseBotsDB.roster then TortoiseBotsDB.roster[name] = nil end
    if state[name] and not state[name].online then state[name] = nil end
end

-- ── live state (ephemeral) ──────────────────────────────────────────────────
function TB.GetState(name)
    name = TB.NormalizeName(name)
    return name and state[name] or nil
end

function TB.GetAllState() return state end -- for count; treat as read-only

function TB.IsInGroup(name)
    name = TB.NormalizeName(name)
    return name and groupMembers[name] and true or false
end

function TB.SetState(name, fields)
    name = TB.NormalizeName(name)
    if not name then return end
    if not state[name] then state[name] = { status = C.STATUS.OFFLINE, online = false } end
    for k, v in pairs(fields) do state[name][k] = v end
    if fields.online then
        if TortoiseBotsDB and TortoiseBotsDB.roster and not TortoiseBotsDB.roster[name] then
            TB.AddToRoster(name, { discovered = true })
        end
    end
end

function TB.MarkAllOfflinePending()
    -- kept for "No owned PlayerBots are online." — also handled by ReconcilePoll
    for _, st in pairs(state) do
        if st.online then
            st.onlinePending = (st.onlinePending or 0) + 1
            if st.onlinePending >= 2 then
                st.online = false; st.status = C.STATUS.OFFLINE
                st.enteredWorld = false; st.hasAI = false
            else
                st.status = C.STATUS.OFFLINE_PENDING
            end
        end
    end
end

function TB.ConfirmSeen(name, info)
    -- info = { enteredWorld, random, hasAI }
    name = TB.NormalizeName(name)
    if not name then return end
    local st = state[name]
    if not st then st = {}; state[name] = st end
    st.online = true; st.onlinePending = 0
    st.enteredWorld = info.enteredWorld
    st.random       = info.random
    st.hasAI        = info.hasAI
    -- clear transient immediately on confirm — server truth wins over optimistic "summoning/inviting"
    st.status = info.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
    TB.MarkPollSeen(name)
    TB.AddToRoster(name, { discovered = true })
end

-- Sorted view for UI
function TB.GetDisplayRows(filter)
    filter = string.lower(filter or "")
    local rows = {}
    local seen = {}
    for _, n in ipairs(TB.GetRosterNames()) do seen[n]=true end
    for n, st in pairs(state) do if st.online then seen[n]=true end end

    for name in pairs(seen) do
        if filter == "" or string.find(string.lower(name), filter, 1, true) then
            local st = state[name] or { status = C.STATUS.OFFLINE, online = false }
            table.insert(rows, { name=name, st=st, inGroup = groupMembers[name] and true or false })
        end
    end
    table.sort(rows, function(a,b)
        if a.st.online ~= b.st.online then return a.st.online end
        return a.name < b.name
    end)
    return rows
end

-- ── group tracking (authoritative, not inferred) ────────────────────────────
local gf = CreateFrame("Frame", "TortoiseBotsManagerGroupWatcher")
gf:RegisterEvent("GROUP_ROSTER_UPDATE")
gf:RegisterEvent("PARTY_MEMBERS_CHANGED")
gf:RegisterEvent("PLAYER_ENTERING_WORLD")
gf:SetScript("OnEvent", function()
    local members = {}
    for i = 1, GetNumPartyMembers() do
        local n = UnitName("party"..i)
        if n and n ~= "" then members[TB.NormalizeName(n) or n] = true end
    end
    for i = 1, GetNumRaidMembers() do
        local n = UnitName("raid"..i)
        if n and n ~= "" then members[TB.NormalizeName(n) or n] = true end
    end
    local selfName = UnitName("player")
    if selfName then members[TB.NormalizeName(selfName) or selfName] = true end
    for k in pairs(groupMembers) do groupMembers[k]=nil end
    for k,v in pairs(members) do groupMembers[k]=v end
    if TB.Refresh then TB.Refresh() end
end)
