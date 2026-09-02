-- TortoiseBotsManager/Roster.lua
--
-- The server-owned snapshot is the only roster authority.  SavedVariables are
-- intentionally not consulted here: offline ownership rows arrive in the
-- TBM:ROSTER_BEGIN/ROSTER/ROSTER_END stream and disappear only when the server
-- says they do.  Legacy .bot list/status replies are retained as an online
-- diagnostic until the first structured snapshot has completed.

local TB = TortoiseBots
local C = TB.C or {}
local S = C.STATUS or {
    OFFLINE = "offline", OFFLINE_PENDING = "offline-pending", UNKNOWN = "unknown",
    FAILED = "failed", QUEUED = "queued", STARTING = "starting", ONLINE = "online",
    COMMANDING = "commanding", SUMMONING = "summoning", INVITING = "inviting",
    KICKING = "kicking", REMOVING = "removing",
}
C.STATUS = S

-- state[name] is ephemeral client state layered over the latest server row.
-- source == "snapshot" is displayable; other sources are compatibility
-- diagnostics/optimistic lifecycle state and never create an offline roster row.
local state = {}
local groupMembers = {}
local groupKnown = false
local rosterSnapshotReady = false
local rosterSnapshotCount = 0
local rosterSnapshotError = nil
local receiving = nil
local legacyState = {}

-- Legacy list reconciliation remains useful when talking to an older module,
-- but is deliberately not used once a structured snapshot is available.
local pollSeen = {}
local pollActive = false
local pollGotAny = false
local pollNoReplyCount = 0

TB.rosterSelection = TB.rosterSelection or {}
TB._debugState = state
TB._debugGroup = groupMembers
TB.rosterSnapshotReady = false

local function normalize(name)
    return TB.NormalizeName and TB.NormalizeName(name or "") or name
end

local function now()
    return (GetTime and GetTime()) or 0
end

local function clearTable(t)
    for key in pairs(t) do t[key] = nil end
end

local function isOfflineValue(value)
    value = string.lower(TB.Trim(value or ""))
    return value == "" or value == "offline" or value == "logged out"
        or value == "logout" or value == "removed" or value == "not online"
end

local function serverStatus(value)
    local text = string.lower(TB.Trim(value or ""))
    if isOfflineValue(text) then return S.OFFLINE, false, false end
    if text == "starting" or text == "pending" or text == "loading" then
        return S.STARTING, true, false
    end
    if text == "removing" or text == "stopping" or text == "logging out" then
        return S.REMOVING, true, false
    end
    if text == "online" or text == "in world" or text == "in_world" then
        return S.ONLINE, true, true
    end
    return S.UNKNOWN, false, false
end

local function displayState(st)
    if not st then return false end
    if st.source == "snapshot" then return true end
    -- Before structured support is available, only live legacy diagnostics are
    -- allowed through.  An offline client-side name never becomes a row.
    return not rosterSnapshotReady and st.source == "legacy" and st.online == true
end

local function isControllable(st)
    if not st or st.operation then return false end
    if st.serverState then
        return st.serverState == "online" or st.serverState == "in world"
            or st.serverState == "in_world"
    end
    return st.online == true and st.status ~= S.UNKNOWN and st.status ~= S.FAILED
        and st.status ~= S.STARTING and st.status ~= S.REMOVING
end

local function setSnapshotRow(row)
    local name = normalize(row.name)
    if not name then return nil end
    local status, online, enteredWorld = serverStatus(row.serverState)
    local classId = tonumber(row.classId) or 0
    local location = TB.Trim(row.location or "")
    if location == "" or location == "-" then location = nil end
    -- The protocol promises pipe-safe fields.  Keep the UI safe even if an
    -- older module violates that promise.
    if location then location = string.gsub(location, "|", "/") end
    return {
        guid = tostring(row.guid or ""),
        name = name,
        classId = classId,
        className = (C.CLASS_NAMES and C.CLASS_NAMES[classId]) or tostring(row.classId or "?"),
        serverState = string.lower(TB.Trim(row.serverState or "")),
        state = row.serverState,
        group = row.group == true and true or false,
        location = location,
        source = "snapshot",
        status = status,
        online = online,
        enteredWorld = enteredWorld,
        hasAI = online and true or false,
        onlinePending = 0,
    }
end

local function splitPipe(text)
    local out = {}
    local start = 1
    while true do
        local at = string.find(text, "|", start, true)
        if at then
            table.insert(out, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(out, string.sub(text, start))
            break
        end
    end
    return out
end

local function protocolFields(msg, prefix)
    if string.sub(msg, 1, string.len(prefix)) ~= prefix then return nil end
    return splitPipe(string.sub(msg, string.len(prefix) + 1))
end

local function snapshotError(code, message)
    rosterSnapshotError = {
        code = TB.Trim(code or "unknown"),
        message = TB.Trim(message or "Roster request failed."),
    }
    receiving = nil
    TB._pollPending = false
    TB._pollQueued = false
    TB.rosterSnapshotError = rosterSnapshotError
    if TB.Refresh then TB.Refresh() end
end

local function commitSnapshot(rows)
    local previousSelection = {}
    for name in pairs(TB.rosterSelection) do previousSelection[name] = true end
    clearTable(state)
    clearTable(legacyState)
    local present = {}
    for _, row in ipairs(rows) do
        local entry = setSnapshotRow(row)
        if entry and not present[entry.name] then
            state[entry.name] = entry
            present[entry.name] = true
        end
    end
    clearTable(TB.rosterSelection)
    for name in pairs(previousSelection) do
        if state[name] then TB.rosterSelection[name] = true end
    end
    rosterSnapshotReady = true
    TB.rosterSnapshotReady = true
    rosterSnapshotCount = table.getn(rows)
    rosterSnapshotError = nil
    TB.rosterSnapshotError = nil
    TB._pollPending = false
    TB._pollQueued = false
    pollActive = false
    if TB.Refresh then TB.Refresh() end
end

-- Called by Comms.lua for each structured line.  Return true for every
-- TBM-prefixed line, including malformed lines, so legacy text handlers do not
-- reinterpret a protocol error as a bot name.
function TB.ParseRosterMessage(msg)
    if not msg or msg == "" then return false end

    local fields = protocolFields(msg, "TBM:ROSTER_BEGIN|")
    if fields then
        if table.getn(fields) ~= 1 or not string.find(fields[1], "^%d+$") then
            snapshotError("malformed_begin", "Malformed roster snapshot.")
            return true, "error"
        end
        receiving = { expected = tonumber(fields[1]), rows = {}, names = {} }
        rosterSnapshotError = nil
        TB.rosterSnapshotError = nil
        return true, "begin", receiving.expected
    end

    fields = protocolFields(msg, "TBM:ROSTER|")
    if fields then
        if not receiving or table.getn(fields) ~= 6 then
            snapshotError("malformed_row", "Malformed roster snapshot.")
            return true, "error"
        end
        local guid, name, classId, serverState, group, location = unpack(fields)
        if TB.Trim(guid) == "" or TB.Trim(name) == "" or not string.find(classId, "^%d+$")
            or TB.Trim(serverState) == "" or (group ~= "0" and group ~= "1")
            or TB.Trim(location) == "" then
            snapshotError("malformed_row", "Malformed roster snapshot.")
            return true, "error"
        end
        local normalized = normalize(name)
        if not normalized or receiving.names[normalized] then
            snapshotError("malformed_row", "Malformed roster snapshot.")
            return true, "error"
        end
        receiving.names[normalized] = true
        table.insert(receiving.rows, {
            guid = guid,
            name = name,
            classId = classId,
            serverState = serverState,
            group = group == "1",
            location = location,
        })
        return true, "row", normalized
    end

    if msg == "TBM:ROSTER_END" then
        if not receiving then
            snapshotError("unexpected_end", "Unexpected roster snapshot end.")
            return true, "error"
        end
        local batch = receiving
        receiving = nil
        if table.getn(batch.rows) ~= batch.expected then
            snapshotError("count_mismatch", "Incomplete roster snapshot.")
            return true, "error"
        end
        commitSnapshot(batch.rows)
        return true, "end", batch.expected
    end

    fields = protocolFields(msg, "TBM:ROSTER_ERROR|")
    if fields then
        if table.getn(fields) ~= 2 then
            snapshotError("malformed_error", "Roster request failed.")
        else
            snapshotError(fields[1], fields[2])
        end
        return true, "error", rosterSnapshotError
    end

    return false
end

function TB.HasRosterSnapshot()
    return rosterSnapshotReady
end

function TB.GetRosterSnapshotError()
    return rosterSnapshotError
end

function TB.GetRosterSnapshot()
    local rows = {}
    for _, entry in ipairs(TB.GetDisplayRows and TB.GetDisplayRows("") or {}) do
        table.insert(rows, entry)
    end
    return rows
end

-- ── lifecycle ───────────────────────────────────────────────────────────────
function TB.InitRoster()
    clearTable(state)
    clearTable(groupMembers)
    clearTable(TB.rosterSelection)
    clearTable(legacyState)
    clearTable(pollSeen)
    rosterSnapshotReady = false
    rosterSnapshotCount = 0
    rosterSnapshotError = nil
    receiving = nil
    groupKnown = false
    pollActive = false
    pollGotAny = false
    pollNoReplyCount = 0
    TB.rosterSnapshotReady = false
    TB.rosterSnapshotError = nil
end

-- ── legacy poll window ──────────────────────────────────────────────────────
function TB.BeginPoll(verb)
    clearTable(pollSeen)
    pollActive = true
    pollGotAny = false
    TB._pollVerb = verb or "roster"
end

function TB.MarkPollSeen(name)
    name = normalize(name)
    if name and pollActive then
        pollSeen[name] = true
        pollGotAny = true
    end
end

function TB.MarkPollGotAny()
    pollGotAny = true
end

function TB.ReconcilePoll()
    if not pollActive then return end
    pollActive = false
    if TB._pollPending ~= nil then TB._pollPending = false end
    -- A structured snapshot commits itself at ROSTER_END; this path is only
    -- for the compatibility .bot list stream.
    if rosterSnapshotReady then return end
    if not pollGotAny then
        pollNoReplyCount = pollNoReplyCount + 1
        if pollNoReplyCount >= (C.POLL_NO_REPLY_LIMIT or 2) then
            for _, st in pairs(state) do
                if st.source == "legacy" and st.online and not st.operation then
                    st.status = S.UNKNOWN
                end
            end
        end
        if TB.Refresh then TB.Refresh() end
        return
    end
    pollNoReplyCount = 0
    for name, st in pairs(state) do
        if st.source == "legacy" and st.online and not pollSeen[name] then
            st.onlinePending = (st.onlinePending or 0) + 1
            if st.onlinePending >= 2 then
                st.online = false
                st.status = S.OFFLINE
                st.enteredWorld = false
                st.hasAI = false
            else
                st.status = S.OFFLINE_PENDING
            end
        end
    end
    if TB.Refresh then TB.Refresh() end
end

-- ── compatibility roster APIs (never persisted) ────────────────────────────
function TB.GetRosterNames()
    local out = {}
    for name, st in pairs(state) do
        if displayState(st) then table.insert(out, name) end
    end
    table.sort(out)
    return out
end

function TB.GetRosterCount()
    if rosterSnapshotReady then return rosterSnapshotCount end
    local count = 0
    for _, st in pairs(state) do
        if displayState(st) then count = count + 1 end
    end
    return count
end

function TB.AddToRoster(name, opts)
    -- Legacy callers may still optimistically track a named add, but this is
    -- never persisted and an offline diagnostic is intentionally undisplayable.
    name = normalize(name)
    if not name then return false, "Invalid name." end
    if not state[name] then
        state[name] = {
            name = name, source = "legacy", status = S.OFFLINE, online = false,
            enteredWorld = false, hasAI = false,
        }
    end
    state[name].discovered = opts and opts.discovered and true or nil
    legacyState[name] = state[name]
    return true
end

function TB.RemoveFromRoster(name)
    name = normalize(name)
    if not name then return end
    local st = state[name]
    if st and st.source ~= "snapshot" then state[name] = nil end
    legacyState[name] = nil
    TB.rosterSelection[name] = nil
end

-- ── live/diagnostic state ───────────────────────────────────────────────────
function TB.GetState(name)
    name = normalize(name)
    return name and state[name] or nil
end

function TB.GetAllState()
    return state
end

function TB.IsInGroup(name)
    name = normalize(name)
    if not name then return false end
    if groupMembers[name] then return true end
    if groupKnown then return false end
    local st = state[name]
    return st and st.group == true or false
end

function TB.SetState(name, fields)
    name = normalize(name)
    if not name then return end
    fields = fields or {}
    if not state[name] then
        state[name] = { name = name, source = "legacy", status = S.OFFLINE, online = false }
        legacyState[name] = state[name]
    end
    local st = state[name]
    for key, value in pairs(fields) do st[key] = value end
    if fields.serverState then
        st.status, st.online, st.enteredWorld = serverStatus(fields.serverState)
    elseif fields.online == false then
        st.enteredWorld = false
        st.hasAI = false
        st.random = nil
    elseif fields.online then
        if not st.status or st.status == S.OFFLINE then st.status = S.ONLINE end
        st.enteredWorld = fields.enteredWorld ~= false
    end
    if st.source ~= "snapshot" then legacyState[name] = st end
end

local function operationTimeout(verb)
    if verb == "add" then return C.ADD_TIMEOUT or 30 end
    if verb == "remove" or verb == "logout" then return C.REMOVE_TIMEOUT or 15 end
    return C.ACTION_TIMEOUT or 8
end

function TB.BeginOperation(name, verb, queued)
    name = normalize(name)
    if not name or not verb then return nil end
    if not state[name] then
        state[name] = { name = name, source = "legacy", status = S.OFFLINE, online = false }
        legacyState[name] = state[name]
    end
    local st = state[name]
    local operation = {
        verb = verb, queued = queued and true or false, startedAt = now(),
        deadline = now() + operationTimeout(verb),
    }
    st.operation = operation
    st.lastError = nil
    if verb == "add" then
        st.online = false; st.enteredWorld = false; st.hasAI = false
        st.status = queued and S.QUEUED or S.STARTING
    elseif queued then
        st.status = S.QUEUED
    elseif verb == "remove" or verb == "logout" then
        st.status = S.REMOVING
    elseif verb == "summon" then
        st.status = S.SUMMONING
    elseif verb == "invite" then
        st.status = S.INVITING
    elseif verb == "uninvite" then
        st.status = S.KICKING
    elseif verb ~= "status" then
        st.status = S.COMMANDING
    end
    return operation
end

function TB.IsOperationPending(name, verb)
    local st = TB.GetState(name)
    return st and st.operation and (not verb or st.operation.verb == verb) or false
end

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
    if success then
        st.lastError = nil
        if st.online then st.status = st.enteredWorld and S.ONLINE or S.STARTING
        else st.status = S.OFFLINE end
    else
        st.lastError = message or "Command failed."
        if (verb == "remove" or verb == "logout") and st.online then st.status = S.ONLINE
        elseif st.online then st.status = st.enteredWorld and S.ONLINE or S.STARTING
        else st.status = S.OFFLINE end
    end
    if TB.Refresh then TB.Refresh() end
    return true
end

function TB.UpdateStateTimers(current)
    current = current or now()
    local changed = false
    local timedOutName
    for name, st in pairs(state) do
        if st.summonPendingUntil and current >= st.summonPendingUntil then
            st.summonPendingUntil = nil
            if not st.operation and st.online then
                st.status = st.enteredWorld and S.ONLINE or S.STARTING
                changed = true
            end
        end
        if st.pendingAI and st.pendingAIUntil and current >= st.pendingAIUntil then
            st.pendingAI = nil; st.pendingAIUntil = nil; changed = true
        end
        local operation = st.operation
        if operation and current >= operation.deadline then
            st.operation = nil
            st.lastError = operation.verb .. " timed out."
            if operation.verb == "add" then
                st.online = false; st.enteredWorld = false; st.hasAI = false; st.status = S.FAILED
            elseif operation.verb == "status" then
                st.status = S.UNKNOWN
            elseif operation.verb == "remove" or operation.verb == "logout" then
                st.status = st.online and S.UNKNOWN or S.OFFLINE
            elseif st.online then
                st.status = st.enteredWorld and S.ONLINE or S.STARTING
            else
                st.status = S.OFFLINE
            end
            timedOutName = timedOutName or name
            changed = true
        end
    end
    if timedOutName and TB.SetStatus then TB.SetStatus(timedOutName .. ": operation timed out.", "warn") end
    if changed and TB.Refresh then TB.Refresh() end
end

function TB.ConfirmSeen(name, info)
    name = normalize(name)
    if not name then return end
    info = info or {}
    local st = state[name]
    if not st then
        if rosterSnapshotReady then return end
        st = { name = name, source = "legacy" }
        state[name] = st
        legacyState[name] = st
    end
    st.online = true
    st.onlinePending = 0
    st.enteredWorld = info.enteredWorld ~= false
    st.random = info.random
    st.hasAI = info.hasAI
    st.serverState = st.enteredWorld and "online" or "starting"
    st.status = st.enteredWorld and S.ONLINE or S.STARTING
    TB.MarkPollSeen(name)
end

-- ── server-backed roster rows ───────────────────────────────────────────────
function TB.GetDisplayRows(filter)
    filter = string.lower(filter or "")
    local rows = {}
    for name, st in pairs(state) do
        if displayState(st) and (filter == "" or string.find(string.lower(name), filter, 1, true)) then
            table.insert(rows, {
                name = name,
                guid = st.guid,
                classId = st.classId,
                className = st.className,
                state = st.state,
                serverState = st.serverState,
                location = st.location,
                st = st,
                inGroup = TB.IsInGroup(name),
            })
        end
    end
    table.sort(rows, function(a, b)
        if a.st.online ~= b.st.online then return a.st.online end
        return a.name < b.name
    end)
    return rows
end

function TB.GetRosterEntry(name)
    name = normalize(name)
    local st = name and state[name] or nil
    if not st or st.source ~= "snapshot" then return nil end
    return st
end

-- ── checkbox selection and lifecycle eligibility ────────────────────────────
function TB.ClearRosterSelection()
    clearTable(TB.rosterSelection)
    if TB.Refresh then TB.Refresh() end
end

function TB.IsRosterSelected(name)
    name = normalize(name)
    return name and TB.rosterSelection[name] and true or false
end

function TB.ToggleRosterSelection(name, selected)
    name = normalize(name)
    local st = name and state[name] or nil
    if not st or st.source ~= "snapshot" then return false end
    if selected == nil then selected = not TB.rosterSelection[name] end
    if selected then TB.rosterSelection[name] = true else TB.rosterSelection[name] = nil end
    if TB.Refresh then TB.Refresh() end
    return selected and true or false
end

function TB.GetSelectedRosterNames()
    local names = {}
    for name in pairs(TB.rosterSelection) do
        local st = state[name]
        if st and st.source == "snapshot" then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

local function lifecycleEligible(name, action)
    local st = state[name]
    if not st or st.source ~= "snapshot" or st.operation then return false end
    local live = isControllable(st)
    local grouped = TB.IsInGroup(name)
    action = string.lower(TB.Trim(action or ""))
    if action == "login" or action == "add" then return not live and st.serverState == "offline" end
    if action == "logout" or action == "remove" then return live end
    if action == "invite" then return live and not grouped end
    if action == "kick" or action == "uninvite" then return live and grouped end
    if action == "summon" then return live end
    return false
end

function TB.IsRosterActionEligible(name, action)
    name = normalize(name)
    return name and lifecycleEligible(name, action) or false
end

function TB.GetEligibleRosterNames(action)
    local names = {}
    for _, name in ipairs(TB.GetSelectedRosterNames()) do
        if lifecycleEligible(name, action) then table.insert(names, name) end
    end
    return names
end

-- Friendly aliases for callers that describe the same contextual bottom bar.
TB.GetEligibleSelection = TB.GetEligibleRosterNames
TB.GetSelectedNames = TB.GetSelectedRosterNames

-- ── group tracking (client group events refine snapshot membership) ──────────
local gf = CreateFrame("Frame", "TortoiseBotsManagerGroupWatcher")
gf:RegisterEvent("GROUP_ROSTER_UPDATE")
gf:RegisterEvent("PARTY_MEMBERS_CHANGED")
gf:RegisterEvent("PLAYER_ENTERING_WORLD")
gf:SetScript("OnEvent", function()
    local members = {}
    local partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, partyCount do
        local n = UnitName("party" .. i)
        if n and n ~= "" then members[normalize(n) or n] = true end
    end
    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    for i = 1, raidCount do
        local n = UnitName("raid" .. i)
        if n and n ~= "" then members[normalize(n) or n] = true end
    end
    local selfName = UnitName and UnitName("player") or nil
    if selfName then members[normalize(selfName) or selfName] = true end
    clearTable(groupMembers)
    for key, value in pairs(members) do groupMembers[key] = value end
    groupKnown = true

    for name, st in pairs(state) do
        if st.source == "snapshot" then st.group = members[name] and true or false end
        if st.operation and st.operation.verb == "invite" and members[name] then
            TB.CompleteOperation(name, "invite", true, "Group invite accepted.")
        elseif st.operation and st.operation.verb == "uninvite" and not members[name] then
            TB.CompleteOperation(name, "uninvite", true, "Bot left your group.")
        end
    end
    if TB.Refresh then TB.Refresh() end
end)
