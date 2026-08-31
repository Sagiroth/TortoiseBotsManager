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
--   Server whispers CHAT_MSG_SYSTEM "Summoning Aran to your location (5y)…"
--     → TB.OnSystemMessage (reconcile, status, refresh)

local TB = TortoiseBots
local C = TB.C or {}
if not C.STATUS then C.STATUS = { OFFLINE="offline", OFFLINE_PENDING="offline-pending", STARTING="starting", ONLINE="online", SUMMONING="summoning", INVITING="inviting", REMOVING="removing" } end

-- Matches BotCommands.cpp at the TortoiseBots headless-command baseline.
-- If server changes wording, update here and add commit SHA to comment.
local PAT = {
    queued        = "queued for login",                            -- Bot X queued for login; it will follow
    alreadyOnline = "already online and cannot be claimed",
    sameAccount   = "You may only control characters on your account",
    summoning     = "Summoning (.+) to your location",              -- Summoning X to your location (5y)
    summonFail    = "cannot be summoned",
    alreadySummon = "already being summoned",
    inviteSent    = "Invitation sent to bot",
    inviteReject  = "was rejected by the native group handler",
    uninviteSent  = "Uninvite sent for bot",
    noBotsOnline  = "No owned PlayerBots are online",
    willStay      = "will stay",
    nowFollowing  = "now following",
    pullback      = "Pullback: tank",
    removed       = "Removal requested for bot",
    -- list line: PSendSysMessage("%s: %s, random %u, AI %u", name, state, random, hasAI)
    listLine      = "^(.+): (.+), random (%d+), AI (%d+)",
    statsLine     = "Owned PlayerBots: (%d+) online",
    helpLine      = "Bot commands:",
    addFailed     = "Failed to add bot",
    summonFailed  = "Failed to summon bot",
    summonNoWorld = "is not in world",
    summonTeleporting = "is already teleporting",
    summonTaxi    = "is on a taxi",
    followFailed  = "could not enter follow mode",
    stayFailed    = "could not enter stay mode",
    addNotFound   = "Character '[^']+' not found",
    botNotFound   = "Bot '[^']+' not found",
}

local function messageBotName(msg)
    local _, _, name = string.find(msg, "'([^']+)'")
    if not name then _, _, name = string.find(msg, "[Bb]ot ([^%s%.,;]+)") end
    if not name then _, _, name = string.find(msg, "for ([^%s%.,;]+) was rejected") end
    return name and TB.NormalizeName(name) or nil
end

local function lastCommandBotName(expectedVerb)
    local command = TB.lastCommand or ""
    local verb = string.lower(string.gsub(command, "%s+.*", ""))
    if expectedVerb and verb ~= expectedVerb then return nil end
    local rest = TB.Trim(string.gsub(command, "^%S+%s*", ""))
    local _, _, name = string.find(rest, "^(%S+)")
    return name and TB.NormalizeName(name) or nil
end

local function rollbackTransient(msg, includeStarting, expectedVerb)
    local name = messageBotName(msg) or lastCommandBotName(expectedVerb)
    if not name or not TB.GetState then return end
    local st = TB.GetState(name)
    if not st then return end
    if st.status == C.STATUS.SUMMONING or st.status == C.STATUS.INVITING
        or (includeStarting and st.status == C.STATUS.STARTING) then
        st.status = st.online and C.STATUS.ONLINE or C.STATUS.OFFLINE
    end
end

local function markFailure(msg, includeStarting, expectedVerb)
    rollbackTransient(msg, includeStarting, expectedVerb)
    if TB.SetStatus then TB.SetStatus(msg, "warn") end
    if TB.RequestPollSoon then TB.RequestPollSoon((C and C.POLL_AFTER_CMD) or 1.4) end
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

function TB.OnCommandSent(cmd)
    local verb = string.lower(string.gsub(cmd, "%s+.*", ""))
    local rest = TB.Trim(string.gsub(cmd, "^%S+%s*", ""))
    local name = TB.NormalizeName(rest)

    if verb == "list" then
        -- actual send time is authoritative for throttle (Core also sets _lastPoll)
        if TB.BeginPoll then TB.BeginPoll() end
        return
    end

    if verb == "summon" and name then
        TB.SetState(name, { status = C.STATUS.SUMMONING })
        if TB.SetStatus then TB.SetStatus("Summoning " .. name .. "…", "pending") end
    elseif verb == "invite" and name then
        TB.SetState(name, { status = C.STATUS.INVITING })
    elseif verb == "add" and name then
        TB.AddToRoster(name)
        TB.SetState(name, { status = C.STATUS.STARTING, online = false })
    elseif verb == "remove" and name then
        TB.SetState(name, { status = C.STATUS.REMOVING })
    end
    if TB.Refresh then TB.Refresh() end
    TB.RequestPollSoon((C and C.POLL_AFTER_CMD) or 1.4)

    -- clear stale transient after 4s if server never replied (e.g., throttled)
    if (verb == "summon" or verb == "invite") and name and C.STATUS then
        local captured = name; local v = verb
        local f = CreateFrame("Frame")
        f.elapsed=0; f:SetScript("OnUpdate", function()
            this.elapsed=(this.elapsed or 0)+(arg1 or 0)
            if (this.elapsed or 0) >=4 then
                this:SetScript("OnUpdate", nil)
                if this.Hide then this:Hide() end
                local st = TB.GetState and TB.GetState(captured) or nil
                if st and ((v=="summon" and st.status==C.STATUS.SUMMONING) or (v=="invite" and st.status==C.STATUS.INVITING)) then
                    -- no confirm — revert to truth
                    st.status = st.online and C.STATUS.ONLINE or C.STATUS.OFFLINE
                    if TB.Refresh then TB.Refresh() end
                end
            end
        end)
        if f.Show then f:Show() end
    end
end

-- ── inbound (CHAT_MSG_SYSTEM) ───────────────────────────────────────────────
function TB.InitComms()
    local f = CreateFrame("Frame", "TortoiseBotsManagerCommsFrame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function()
        if event == "CHAT_MSG_SYSTEM" then TB.OnSystemMessage(arg1 or "") end
    end)
end

function TB.OnSystemMessage(msg)
    if not msg or msg == "" then return end
    local handled = false

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
        TB.MarkAllOfflinePending()
        if TB.SetStatus then TB.SetStatus("No owned bots online.", "muted") end
        if TB.Refresh  then TB.Refresh() end
        return
    end
    if string.find(msg, PAT.statsLine) then
        -- stats alone doesn't prove list window, but counts as activity
        if TB.SetStatus then TB.SetStatus(msg, "muted") end
        return
    end
    if string.find(msg, PAT.helpLine) then
        if TB.SetStatus then TB.SetStatus(msg, "muted") end
        return
    end

    -- 2) action replies (optimistic → confirmed / rolled back)
    if string.find(msg, PAT.queued) then
        local _, _, botName = string.find(msg, "Bot (%S+) queued")
        if botName then TB.SetState(botName, { status = C.STATUS.STARTING, online = false }) end
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        TB.RequestPollSoon(C.POLL_AFTER_ADD); handled = true

    elseif string.find(msg, PAT.summoning) then
        local _, _, botName = string.find(msg, "Summoning (%S+)")
        if botName then TB.SetState(botName, { status = C.STATUS.SUMMONING }) end
        if TB.SetStatus then TB.SetStatus(msg, "ok") end; handled = true

    elseif string.find(msg, PAT.inviteSent) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.inviteReject) then
        markFailure(msg, false, "invite"); handled = true

    elseif string.find(msg, PAT.uninviteSent) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.willStay) or string.find(msg, PAT.nowFollowing) or string.find(msg, PAT.pullback) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end; handled = true

    elseif string.find(msg, PAT.removed) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.addFailed) or string.find(msg, PAT.addNotFound)
        or string.find(msg, PAT.botNotFound) then
        markFailure(msg, true, "add"); handled = true

    elseif string.find(msg, PAT.summonFailed) or string.find(msg, PAT.summonNoWorld)
        or string.find(msg, PAT.summonTeleporting) or string.find(msg, PAT.summonTaxi)
        or string.find(msg, PAT.summonFail) or string.find(msg, PAT.alreadySummon) then
        markFailure(msg, false, "summon"); handled = true

    elseif string.find(msg, PAT.followFailed) then
        markFailure(msg, false, "follow"); handled = true

    elseif string.find(msg, PAT.stayFailed) then
        markFailure(msg, false, "stay"); handled = true

    elseif string.find(msg, PAT.alreadyOnline) or string.find(msg, PAT.sameAccount) then
        markFailure(msg, true, "add")
        handled = true
    end

    if handled and TB.Refresh then TB.Refresh() end
    TB.lastSystem = msg
end
