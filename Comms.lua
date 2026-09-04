-- TortoiseBotsManager/Comms.lua
-- Protocol: send ".bot <verb> [name] [extra]" and parse CHAT_MSG_SYSTEM replies.
--
-- Source of truth for every pattern is commands/BotCommands.cpp (module repo).
-- Keep PAT lenient (substring, not full equality) so minor wording tweaks don't
-- silently break the addon. Anchored where possible.
--
-- Flow:
--   UI/Core calls TB.SendBotCommand("summon Aran")
--     → Throttled SendChatMessage
--     → TB.OnCommandSent  (optimistic state)
--   Server whispers CHAT_MSG_SYSTEM "Summoning Aran to a safe position near you…"
--     → TB.OnSystemMessage (reconcile, status, refresh)

local TB = TortoiseBots
local C = TB.C or {}
if not C.STATUS then C.STATUS = {
    OFFLINE="offline", OFFLINE_PENDING="offline-pending", UNKNOWN="unknown", FAILED="failed",
    QUEUED="queued", STARTING="starting", ONLINE="online", COMMANDING="commanding",
    SUMMONING="summoning", INVITING="inviting", KICKING="kicking", REMOVING="removing",
} end

-- Matches BotCommands.cpp at the TortoiseBots headless-command baseline.
-- If server changes wording, update here and add commit SHA to comment.
local PAT = {
    queued        = "queued for login",                            -- Bot X queued for login; it will follow
    alreadyOnline = "already online and cannot be claimed",
    sameAccount   = "You may only control characters on your account",
    summoning     = "Summoning (.+) to a safe position near you",    -- native safe-position summon
    summonFail    = "cannot be summoned",
    alreadySummon = "already being summoned",
    inviteSent    = "Invitation sent to bot",
    inviteReject  = "was rejected by the native group handler",
    uninviteSent  = "Uninvite sent for bot",
    noBotsOnline  = "No owned PlayerBots are online",
    willStay      = "will stay",
    nowFollowing  = "now following",
    pullback      = "Pullback requested: tank",
    pullbackNoTarget = "You have no target",
    pullbackTargetMissing = "Target not found",
    pullbackDead   = "Target is dead",
    pullbackCombat = "Target is already in combat",
    pullbackHostile = "Target is not hostile",
    pullbackNoTank = "No tank bot found",
    pullbackBusy   = "Pullback already active",
    pullbackWorld  = "You must be in world to use pullback",
    pullbackFailed = "could not start a pull",
    pullbackAssignFailed = "could not be assigned to you for pullback",
    removed       = "Removal requested for bot",
    -- list line: PSendSysMessage("%s: %s, random %u, AI %u", name, state, random, hasAI)
    listLine      = "^(.+): (.+), random (%d+), AI (%d+)",
    statsLine     = "Owned PlayerBots: (%d+) online",
    helpLine      = "Bot commands:",
    statusLine    = "^(.+): (.+), AI (%d+), movement (%S+), random (%d+), owner (.+)%.?$",
    forwarded     = "Forwarded command for",
    nowGuarding   = "will guard this position",
    nowFree       = "is free to move",
    nowAttacking  = "will attack your selected target",
    nowReady       = "will run a readiness check",
    formationSet   = "formation set to",
    addFailed     = "Failed to add bot",
    summonFailed  = "Failed to summon bot",
    summonNoWorld = "is not in world",
    summonTeleporting = "is already teleporting",
    summonTaxi    = "is on a taxi",
    summonAssignFailed = "could not be assigned to you for summon",
    followFailed  = "could not enter follow mode",
    stayFailed    = "could not enter stay mode",
    addNotFound   = "Character '[^']+' not found",
    botNotFound   = "Bot '[^']+' not found",
    removeFailed  = "not found or not removable",
    noAI          = "has no AI yet",
    unknownCommand = "Unknown bot command",
    unknownModuleCommand = "Unknown command",
}

local serverCommands = {}
local serverCapabilitiesKnown = false
local responseHistory = {}
local function splitProtocol(text)
    local fields = {}
    local start = 1
    while true do
        local at = string.find(text, "|", start, true)
        if at then
            table.insert(fields, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(fields, string.sub(text, start))
            break
        end
    end
    return fields
end

local function actionLabel(intent)
    if C.ACTION_LABELS and C.ACTION_LABELS[intent] then return C.ACTION_LABELS[intent] end
    return intent
end

local function setActionAck(fields)
    if table.getn(fields) ~= 4 then return nil end
    local intent, scope, count, executor = fields[1], fields[2], fields[3], fields[4]
    if TB.Trim(intent) == "" or (scope ~= "party" and string.sub(scope, 1, 4) ~= "bot:")
        or not string.find(count, "^%d+$") or TB.Trim(executor) == "" then
        return nil
    end
    if string.sub(scope, 1, 4) == "bot:" and TB.Trim(string.sub(scope, 5)) == "" then return nil end
    return {
        intent = intent,
        scope = scope,
        count = tonumber(count),
        executor = executor,
    }
end

local function setActionError(fields)
    if table.getn(fields) ~= 3 or TB.Trim(fields[1]) == "" or TB.Trim(fields[2]) == "" then
        return nil
    end
    return { intent = fields[1], code = fields[2], message = fields[3] }
end

-- Parse the machine-readable gameplay response.  This is public so the Lua
-- harness and alternate front ends can consume packets without scraping text.
function TB.ParseActionMessage(msg)
    if not msg or msg == "" then return false end
    local ackPrefix = "TBM:ACTION_ACK|"
    if string.sub(msg, 1, string.len(ackPrefix)) == ackPrefix then
        local packet = setActionAck(splitProtocol(string.sub(msg, string.len(ackPrefix) + 1)))
        if not packet then
            TB.lastActionError = { intent = "unknown", code = "malformed", message = "Malformed action response." }
            if TB.SetStatus then TB.SetStatus("Malformed action response.", "warn") end
            return true, "error", TB.lastActionError
        end
        TB.lastActionAck = packet
        TB.lastActionError = nil
        if packet.intent == "aoe" then
            TB.aoePending = false
            if packet.executor == "on" or packet.executor == "off" then
                TB.aoeEnabled = packet.executor == "on"
                if TB.actionButtons and TB.actionButtons.aoe then
                    TB.actionButtons.aoe:SetText("AoE " .. (TB.aoeEnabled and "On" or "Off"))
                end
            end
        end
        local scope = packet.scope == "party" and "party" or packet.scope
        local text = actionLabel(packet.intent) .. " accepted · " .. scope .. " · " .. packet.count
        if packet.executor ~= "-" then text = text .. " (" .. packet.executor .. ")" end
        if TB.SetStatus then TB.SetStatus(text, "ok") end
        if TB.Refresh then TB.Refresh() end
        return true, "ack", packet
    end

    local errorPrefix = "TBM:ACTION_ERR|"
    if string.sub(msg, 1, string.len(errorPrefix)) == errorPrefix then
        local packet = setActionError(splitProtocol(string.sub(msg, string.len(errorPrefix) + 1)))
        if not packet then
            packet = { intent = "unknown", code = "malformed", message = "Malformed action response." }
        end
        TB.lastActionError = packet
        TB.lastActionAck = nil
        if packet.intent == "aoe" then TB.aoePending = false end
        local text = actionLabel(packet.intent) .. ": " .. packet.code
        if packet.message ~= "" then text = text .. " — " .. packet.message end
        if TB.SetStatus then TB.SetStatus(text, "warn") end
        if TB.Refresh then TB.Refresh() end
        return true, "error", packet
    end
    return false
end

function TB.HasServerCommand(command)
    if not command then return false end
    return serverCommands[string.lower(TB.Trim(command))] and true or false
end

function TB.ServerCapabilitiesKnown()
    return serverCapabilitiesKnown
end

local function updateServerCommands(msg)
    if string.find(msg, "^TortoiseBots:%s*Enabled") then
        serverCapabilitiesKnown = true
        TB._serverCommands = serverCommands
        if TB.Refresh then TB.Refresh() end
        return true
    end
    local _, _, list = string.find(msg, "^Bot commands:%s*(.*)$")
    if not list then return false end
    for key in pairs(serverCommands) do serverCommands[key] = nil end
    local start = 1
    while true do
        local first, last, command = string.find(list, "([^/]+)", start)
        if not command then break end
        command = string.lower(TB.Trim(command))
        command = string.gsub(command, "[%s%.]+$", "")
        if command ~= "" then serverCommands[command] = true end
        start = last + 1
    end
    serverCapabilitiesKnown = true
    TB._serverCommands = serverCommands
    if TB.Refresh then TB.Refresh() end
    return true
end

function TB.GetResponseHistory()
    return responseHistory
end

function TB.RecordAIResponse(name, msg, kind)
    if not msg or msg == "" then return end
    table.insert(responseHistory, { name = name, message = msg, kind = kind or "info" })
    while table.getn(responseHistory) > 8 do table.remove(responseHistory, 1) end
    TB.lastAIResponse = { name = name, message = msg, kind = kind or "info" }
    local statusKind = kind == "error" and "warn" or (kind == "pending" and "pending" or "ok")
    if TB.SetStatus then TB.SetStatus((name and (name .. ": ") or "") .. msg, statusKind) end
end

local function messageBotName(msg)
    local _, _, name = string.find(msg, "'([^']+)'")
    if not name then _, _, name = string.find(msg, "[Bb]ot ([^%s%.,;]+)") end
    if not name then _, _, name = string.find(msg, "for ([^%s%.,;]+) was rejected") end
    if not name then _, _, name = string.find(msg, "for ([^%s:]+):") end
    return name and TB.NormalizeName(name) or nil
end

local function lastCommandVerb()
    local command = TB.lastCommand or ""
    return string.lower(string.gsub(command, "%s+.*", ""))
end

local function lastCommandBotName(expectedVerb)
    local command = TB.lastCommand or ""
    local verb = lastCommandVerb()
    if expectedVerb and verb ~= expectedVerb then return nil end
    local rest = TB.Trim(string.gsub(command, "^%S+%s*", ""))
    local _, _, name = string.find(rest, "^(%S+)")
    return name and TB.NormalizeName(name) or nil
end

local function rollbackTransient(msg, includeStarting, expectedVerb)
    expectedVerb = expectedVerb or lastCommandVerb()
    local name = messageBotName(msg) or lastCommandBotName(expectedVerb)
    if not name or not TB.GetState then return end
    local st = TB.GetState(name)
    if not st then return end
    if st.operation and expectedVerb and st.operation.verb ~= expectedVerb then
        return
    elseif st.operation then
        if TB.CompleteOperation then TB.CompleteOperation(name, expectedVerb, false, msg) end
    elseif st.status == C.STATUS.SUMMONING or st.status == C.STATUS.INVITING
        or st.status == C.STATUS.REMOVING or (includeStarting and st.status == C.STATUS.STARTING) then
        st.status = st.online and C.STATUS.ONLINE or C.STATUS.OFFLINE
    end
end

local function markFailure(msg, includeStarting, expectedVerb)
    rollbackTransient(msg, includeStarting, expectedVerb)
    if TB.SetStatus then TB.SetStatus(msg, "warn") end
    if TB.RequestPollSoon then TB.RequestPollSoon((C and C.POLL_AFTER_CMD) or 1.4) end
end

local function acknowledgeAction(msg, verb, movement)
    local name = messageBotName(msg) or lastCommandBotName(verb)
    if not name or not TB.GetState then return false end
    local st = TB.GetState(name)
    if st and st.operation and st.operation.verb ~= verb then return false end
    local completed = TB.CompleteOperation and TB.CompleteOperation(name, verb, true, msg)
    st = TB.GetState(name)
    if st and completed and movement then st.movement = movement end
    return completed and true or false
end

-- ── outbound ────────────────────────────────────────────────────────────────
function TB.BuildCommand(verb, name, extra)
    verb  = TB.Trim(verb or "")
    name  = TB.NormalizeName(name or "")
    extra = TB.Trim(extra or "")
    if name and name ~= "" then
        if extra ~= "" then return verb .. " " .. name .. " " .. extra end
        return verb .. " " .. name
    else
        if extra ~= "" then return verb .. " " .. extra end
        return verb
    end
end

local function commandTargetName(cmd)
    local rest = TB.Trim(string.gsub(cmd or "", "^%S+%s*", ""))
    local _, _, name = string.find(rest, "^(%S+)")
    return name and TB.NormalizeName(name) or nil
end

function TB.OnCommandQueued(cmd)
    local verb = string.lower(string.gsub(cmd or "", "%s+.*", ""))
    local name = commandTargetName(cmd)
    if name and verb ~= "list" and verb ~= "roster" and verb ~= "stats"
        and verb ~= "help" and verb ~= "action" and TB.BeginOperation then
        if verb == "add" then TB.AddToRoster(name) end
        TB.BeginOperation(name, verb, true)
        if TB.Refresh then TB.Refresh() end
    end
end

function TB.OnCommandSent(cmd)
    local verb = string.lower(string.gsub(cmd, "%s+.*", ""))
    local name = commandTargetName(cmd)

    if verb == "list" or verb == "roster" then
        -- Actual send time is authoritative for throttle (Core also sets
        -- _lastPoll).  The structured stream commits the roster at END.
        return
    end

    if verb == "add" and name then TB.AddToRoster(name) end
    if name and verb ~= "action" and TB.BeginOperation then
        TB.BeginOperation(name, verb, false)
    end

    if verb == "command" and name then
        local st = TB.GetState and TB.GetState(name) or nil
        if st then
            st.pendingAI = true
            st.pendingAIUntil = ((GetTime and GetTime()) or 0) + (C.ACTION_TIMEOUT or 8)
        end
    end
    if verb == "summon" and name then
        if TB.SetStatus then TB.SetStatus("Summoning " .. name .. "…", "pending") end
    end
    if TB.Refresh then TB.Refresh() end
    if verb ~= "action" then TB.RequestPollSoon((C and C.POLL_AFTER_CMD) or 1.4) end
end

-- ── inbound (CHAT_MSG_SYSTEM) ───────────────────────────────────────────────
function TB.InitComms()
    local f = CreateFrame("Frame", "TortoiseBotsManagerCommsFrame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function()
        if event == "CHAT_MSG_SYSTEM" then TB.OnSystemMessage(arg1 or "")
        elseif event == "CHAT_MSG_WHISPER" then TB.OnWhisperMessage(arg1 or "", arg2 or "")
        elseif event == "CHAT_MSG_ADDON" then TB.OnAddonMessage(arg1 or "", arg2 or "", arg3 or "", arg4 or "") end
    end)
end

function TB.OnWhisperMessage(msg, sender)
    local name = TB.NormalizeName(sender or "")
    local st = name and TB.GetState and TB.GetState(name) or nil
    if not st or not st.pendingAI or not st.operation or st.operation.verb ~= "command" then return end
    local now = (GetTime and GetTime()) or 0
    if st.pendingAIUntil and now > st.pendingAIUntil then
        st.pendingAI = nil
        return
    end
    st.pendingAI = nil
    if TB.CompleteOperation then TB.CompleteOperation(name, "command", true, msg) end
    TB.RecordAIResponse(name, msg, "info")
end

function TB.OnAddonMessage(prefix, msg, channel, sender)
    local name = TB.NormalizeName(sender or "")
    local st = name and TB.GetState and TB.GetState(name) or nil
    if not st or not st.pendingAI or not st.operation or st.operation.verb ~= "command" then return end
    st.pendingAI = nil
    if TB.CompleteOperation then TB.CompleteOperation(name, "command", true, msg) end
    TB.RecordAIResponse(name, msg, "info")
end

function TB.OnSystemMessage(msg)
    if not msg or msg == "" then return end
    local handled = false

    local rosterHandled, rosterKind, rosterData = false, nil, nil
    if TB.ParseRosterMessage then
        rosterHandled, rosterKind, rosterData = TB.ParseRosterMessage(msg)
    end
    if rosterHandled then
        if rosterKind == "begin" then
            if TB.SetStatus then TB.SetStatus("Syncing roster…", "pending") end
        elseif rosterKind == "end" then
            if TB.SetStatus then TB.SetStatus("Roster updated · " .. tostring(rosterData), "ok") end
        elseif rosterKind == "error" then
            local message = rosterData and rosterData.message or "Roster request failed."
            if TB.SetStatus then TB.SetStatus("Roster: " .. message, "warn") end
        end
        TB.lastSystem = msg
        return
    end

    local actionHandled = TB.ParseActionMessage and TB.ParseActionMessage(msg)
    if actionHandled then
        TB.lastSystem = msg
        return
    end
    if updateServerCommands(msg) then
        if TB.SetStatus then TB.SetStatus(msg, "muted") end
        TB.lastSystem = msg
        return
    end

    do
        local _, _, n, lifecycle, ai, movement, random, owner = string.find(msg, PAT.statusLine)
        if n then
            local enteredWorld = lifecycle == "in world"
            TB.SetState(n, {
                online = true,
                enteredWorld = enteredWorld,
                hasAI = (ai == "1"),
                movement = movement,
                random = (random == "1"),
                lifecycle = lifecycle,
                owner = owner,
            })
            local st = TB.GetState(n)
            if st and st.operation and st.operation.verb == "status" then st.operation = nil end
            if st and not st.operation then
                st.lastError = nil
                if lifecycle == "removing" then st.status = C.STATUS.REMOVING
                elseif lifecycle == "in world" then st.status = C.STATUS.ONLINE
                elseif lifecycle == "starting" then st.status = C.STATUS.STARTING
                else st.status = C.STATUS.UNKNOWN end
            end
            if TB.SetStatus then TB.SetStatus(msg, "ok") end
            if TB.Refresh then TB.Refresh() end
            return
        end
    end

    -- 1) list line (may arrive N times per poll)
    do
        local _, _, n, s, r, a = string.find(msg, PAT.listLine)
        if n then
            TB.ConfirmSeen(n, {
                enteredWorld = (s == "in world"),
                random = (r == "1"),
                hasAI  = (a == "1"),
            })
            if TB.SetStatus then TB.SetStatus(msg, "ok") end
            if TB.Refresh  then TB.Refresh() end
            return -- list lines are exclusive
        end
    end

    if string.find(msg, PAT.noBotsOnline) then
        TB.MarkPollGotAny()
        if TB.SetStatus then TB.SetStatus("No owned bots online.", "muted") end
        if TB.Refresh  then TB.Refresh() end
        return
    end
    if string.find(msg, PAT.statsLine) then
        -- stats alone doesn't prove list window, but counts as activity
        if TB.SetStatus then TB.SetStatus(msg, "muted") end
        return
    end

    -- 2) action replies (optimistic → confirmed / rolled back)
    if string.find(msg, PAT.queued) then
        local _, _, botName = string.find(msg, "Bot (%S+) queued")
        if botName then TB.SetState(botName, { status = C.STATUS.STARTING, online = false }) end
        if TB.SetStatus then TB.SetStatus(msg, "pending") end
        TB.RequestPollSoon(C.POLL_AFTER_ADD); handled = true

    elseif string.find(msg, PAT.summoning) then
        local _, _, botName = string.find(msg, "Summoning (%S+)")
        if botName then
            if TB.AcknowledgeOperation then TB.AcknowledgeOperation(botName, "summon") end
            local st = TB.GetState and TB.GetState(botName) or nil
            if st then
                st.status = C.STATUS.SUMMONING
                st.summonPendingUntil = ((GetTime and GetTime()) or 0) + (C.SUMMON_SETTLE or 15)
            end
        end
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.inviteSent) then
        acknowledgeAction(msg, "invite")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.inviteReject) then
        markFailure(msg, false, "invite"); handled = true

    elseif string.find(msg, PAT.uninviteSent) then
        acknowledgeAction(msg, "uninvite")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.willStay) then
        acknowledgeAction(msg, "stay", "stay")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.nowFollowing) then
        acknowledgeAction(msg, "follow", "follow")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.nowGuarding) then
        acknowledgeAction(msg, "guard", "guard")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.nowFree) then
        acknowledgeAction(msg, "free", "free")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.nowAttacking) then
        acknowledgeAction(msg, "attack")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.nowReady) then
        acknowledgeAction(msg, "ready")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.formationSet) then
        acknowledgeAction(msg, "formation")
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.pullback) then
        if TB.SetStatus then TB.SetStatus(msg, "pending") end; handled = true

    elseif string.find(msg, PAT.forwarded) then
        local name = messageBotName(msg) or lastCommandBotName("command")
        if name and TB.GetState then
            local st = TB.GetState(name)
            if st and st.operation and st.operation.verb == "command" then
                st.status = C.STATUS.COMMANDING
            end
        end
        if TB.RecordAIResponse then TB.RecordAIResponse(name, msg, "pending")
        elseif TB.SetStatus then TB.SetStatus(msg, "ok") end
        handled = true

    elseif string.find(msg, PAT.removed) then
        if TB.SetStatus then TB.SetStatus(msg, "pending") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.addFailed) or string.find(msg, PAT.addNotFound) then
        markFailure(msg, true, "add"); handled = true

    elseif string.find(msg, PAT.removeFailed) then
        markFailure(msg, false, "remove"); handled = true

    elseif string.find(msg, PAT.summonFailed) or string.find(msg, PAT.summonNoWorld)
        or string.find(msg, PAT.summonTeleporting) or string.find(msg, PAT.summonTaxi)
        or string.find(msg, PAT.summonFail) or string.find(msg, PAT.alreadySummon)
        or string.find(msg, PAT.summonAssignFailed) then
        markFailure(msg, false, "summon"); handled = true

    elseif string.find(msg, PAT.followFailed) then
        markFailure(msg, false, "follow"); handled = true

    elseif string.find(msg, PAT.stayFailed) then
        markFailure(msg, false, "stay"); handled = true

    elseif string.find(msg, PAT.pullbackNoTarget) or string.find(msg, PAT.pullbackTargetMissing)
        or string.find(msg, PAT.pullbackDead) or string.find(msg, PAT.pullbackCombat)
        or string.find(msg, PAT.pullbackHostile) or string.find(msg, PAT.pullbackNoTank)
        or string.find(msg, PAT.pullbackBusy) or string.find(msg, PAT.pullbackWorld)
        or string.find(msg, PAT.pullbackFailed) or string.find(msg, PAT.pullbackAssignFailed) then
        if TB.SetStatus then TB.SetStatus(msg, "warn") end; handled = true

    elseif string.find(msg, PAT.noAI) or string.find(msg, PAT.botNotFound)
        or string.find(msg, PAT.unknownCommand) or string.find(msg, PAT.unknownModuleCommand) then
        markFailure(msg, true, nil); handled = true

    elseif string.find(msg, PAT.alreadyOnline) or string.find(msg, PAT.sameAccount) then
        markFailure(msg, true, "add")
        handled = true
    end

    if handled and TB.Refresh then TB.Refresh() end
    TB.lastSystem = msg
end
