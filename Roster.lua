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
local pollNoReplyCount = 0

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
    if name and pollActive then pollSeen[name]=true; pollGotAny=true end
end

function TB.MarkPollGotAny()
    pollGotAny = true
end

-- Called ~1.2s after .bot list was sent, once replies should have arrived.
-- If we got at least one list/noBots line, any online name not seen is stale.
-- Requires 2 consecutive misses to go offline (avoids flicker on lag).
function TB.ReconcilePoll()
    if not pollActive then return end
    pollActive=false
    if TB._pollPending ~= nil then TB._pollPending=false end
    if not pollGotAny then
        pollNoReplyCount = pollNoReplyCount + 1
        if pollNoReplyCount >= (C.POLL_NO_REPLY_LIMIT or 2) then
            for _, st in pairs(state) do
                if st.online and not st.operation then st.status=C.STATUS.UNKNOWN end
            end
        end
        if TB.Refresh then TB.Refresh() end
        return -- no reply yet / lag; preserve truth as Unknown after repeated silence
    end
    pollNoReplyCount = 0
    for name, st in pairs(state) do
        if st.online and not pollSeen[name] then
            st.onlinePending = (st.onlinePending or 0) + 1
            if st.onlinePending >= 2 then
                st.online=false; st.status=C.STATUS.OFFLINE
                st.enteredWorld=false; st.hasAI=false
                if st.operation and st.operation.verb == "remove" then st.operation=nil end
            else
                if not (st.operation and st.operation.verb == "remove") then
                    st.status=C.STATUS.OFFLINE_PENDING
                end
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
    groupMembers[name] = nil
    if TB.selected == name then TB.selected = nil end
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
    fields = fields or {}
    if not state[name] then state[name] = { status = C.STATUS.OFFLINE, online = false } end
    for k, v in pairs(fields) do state[name][k] = v end
    if fields.online == false then
        state[name].enteredWorld = false
        state[name].hasAI = false
        state[name].random = nil
    end
    if fields.online then
        if TortoiseBotsDB and TortoiseBotsDB.roster and not TortoiseBotsDB.roster[name] then
            TB.AddToRoster(name, { discovered = true })
        end
    end
end

local function operationTimeout(verb)
    if verb == "add" then return C.ADD_TIMEOUT or 30 end
    if verb == "remove" then return C.REMOVE_TIMEOUT or 15 end
    return C.ACTION_TIMEOUT or 8
end

function TB.BeginOperation(name, verb, queued)
    name = TB.NormalizeName(name)
    if not name or not verb then return nil end
    if not state[name] then state[name] = { status = C.STATUS.OFFLINE, online = false } end
    local now = (GetTime and GetTime()) or 0
    local operation = {
        verb = verb,
        queued = queued and true or false,
        startedAt = now,
        deadline = now + operationTimeout(verb),
    }
    state[name].operation = operation
    state[name].lastError = nil
    if verb ~= "command" then
        state[name].pendingAI = nil
        state[name].pendingAIUntil = nil
    end
    if verb == "add" then
        state[name].online = false
        state[name].enteredWorld = false
        state[name].hasAI = false
        state[name].status = queued and C.STATUS.QUEUED or C.STATUS.STARTING
    elseif queued then
        state[name].status = C.STATUS.QUEUED
    elseif verb == "remove" then
        state[name].status = C.STATUS.REMOVING
    elseif verb == "summon" then
        state[name].status = C.STATUS.SUMMONING
    elseif verb == "invite" then
        state[name].status = C.STATUS.INVITING
    elseif verb == "uninvite" then
        state[name].status = C.STATUS.KICKING
    elseif verb ~= "status" then
        state[name].status = C.STATUS.COMMANDING
    end
    return operation
end

function TB.IsOperationPending(name, verb)
    local st = TB.GetState(name)
    return st and st.operation and (not verb or st.operation.verb == verb) or false
end

-- Some server actions acknowledge receipt before the gameplay transition is
-- complete. Clear the command acknowledgement without presenting that as a
-- completed gameplay action; the caller keeps an explicit transient status.
function TB.AcknowledgeOperation(name, verb)
    local st = TB.GetState(name)
    if not st or not st.operation or (verb and st.operation.verb ~= verb) then return false end
    st.operation = nil
    st.lastError = nil
    return true
end

function TB.CompleteOperation(name, verb, success, message)
    local st = TB.GetState(name)
    if not st or (st.operation and verb and st.operation.verb ~= verb) then return false end
    if st.operation then st.operation = nil end
    if verb == "command" then
        st.pendingAI = nil
        st.pendingAIUntil = nil
    end
    if success then
        st.lastError = nil
        if st.online then st.status = st.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
        else st.status = C.STATUS.OFFLINE end
    else
        st.lastError = message or "Command failed."
        if verb == "remove" and st.online then st.status = C.STATUS.ONLINE
        elseif st.online then st.status = st.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
        else st.status = C.STATUS.OFFLINE end
    end
    if TB.Refresh then TB.Refresh() end
    return true
end

function TB.UpdateStateTimers(now)
    now = now or ((GetTime and GetTime()) or 0)
    local changed = false
    local timedOutName
    for name, st in pairs(state) do
        if st.summonPendingUntil and now >= st.summonPendingUntil then
            st.summonPendingUntil = nil
            if not st.operation and st.online then
                st.status = st.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
                changed = true
            end
        end
        if st.pendingAI and st.pendingAIUntil and now >= st.pendingAIUntil then
            st.pendingAI = nil
            st.pendingAIUntil = nil
            changed = true
        end
        local operation = st.operation
        if operation and now >= operation.deadline then
            st.operation = nil
            if operation.verb == "command" then
                st.pendingAI = nil
                st.pendingAIUntil = nil
            end
            st.lastError = operation.verb .. " timed out."
            if operation.verb == "add" then
                st.online = false
                st.enteredWorld = false
                st.hasAI = false
                st.status = C.STATUS.FAILED
            elseif operation.verb == "status" then
                st.status = C.STATUS.UNKNOWN
            elseif operation.verb == "remove" then
                st.status = st.online and C.STATUS.UNKNOWN or C.STATUS.OFFLINE
            elseif st.online then
                st.status = st.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
            else
                st.status = C.STATUS.OFFLINE
            end
            timedOutName = timedOutName or name
            changed = true
        end
    end
    if timedOutName and TB.SetStatus then
        TB.SetStatus(timedOutName .. ": operation timed out.", "warn")
    end
    if changed and TB.Refresh then TB.Refresh() end
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
    local operation = st.operation
    if operation and operation.verb == "add" and info.enteredWorld then
        st.operation = nil
        st.lastError = nil
        st.status = C.STATUS.ONLINE
    elseif operation and operation.verb == "remove" then
        st.status = C.STATUS.REMOVING
    elseif operation and operation.verb == "summon" then
        st.status = C.STATUS.SUMMONING
    elseif operation and operation.verb == "invite" then
        st.status = C.STATUS.INVITING
    elseif operation then
        -- A list snapshot confirms presence, but not completion of a named
        -- action. Keep the optimistic state until its matching reply arrives
        -- or the operation timer expires.
        st.status = st.status or (info.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING)
    else
        st.lastError = nil
        st.status = info.enteredWorld and C.STATUS.ONLINE or C.STATUS.STARTING
    end
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
    for name, st in pairs(state) do
        if st.operation and st.operation.verb == "invite" and members[name] then
            TB.CompleteOperation(name, "invite", true, "Group invite accepted.")
        elseif st.operation and st.operation.verb == "uninvite" and not members[name] then
            TB.CompleteOperation(name, "uninvite", true, "Bot left your group.")
        end
    end
    if TB.Refresh then TB.Refresh() end
end)
