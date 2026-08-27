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
local C = TB.C

-- Matches BotCommands.cpp exact strings @07cf7976 / 7353989c baseline.
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
}

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
        -- reconcile scheduled in Core.PollList; ensure one if list was queued
        if TB.ReconcilePoll then
            -- Core already scheduled; if this was a queued list, ensure window
            if not string.find(cmd, "stats") then
                -- nudge reconcile
            end
        end
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
    TB.RequestPollSoon(C.POLL_AFTER_CMD)

    -- clear stale transient after 4s if server never replied (e.g., throttled)
    if (verb == "summon" or verb == "invite") and name then
        local captured = name; local v = verb
        local f = CreateFrame("Frame")
        f.elapsed=0; f:SetScript("OnUpdate", function()
            this.elapsed=this.elapsed+arg1
            if this.elapsed>=4 then
                this:SetScript("OnUpdate", nil)
                local st = TB.GetState(captured)
                if st and ((v=="summon" and st.status==C.STATUS.SUMMONING) or (v=="invite" and st.status==C.STATUS.INVITING)) then
                    -- no confirm — revert to truth
                    st.status = st.online and C.STATUS.ONLINE or C.STATUS.OFFLINE
                    if TB.Refresh then TB.Refresh() end
                end
            end
        end)
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
        if TB.SetStatus then TB.SetStatus(msg, "warn") end; handled = true

    elseif string.find(msg, PAT.willStay) or string.find(msg, PAT.nowFollowing) or string.find(msg, PAT.pullback) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end; handled = true

    elseif string.find(msg, PAT.removed) then
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        TB.RequestPollSoon(C.POLL_AFTER_CMD); handled = true

    elseif string.find(msg, PAT.alreadyOnline) or string.find(msg, PAT.sameAccount)
        or string.find(msg, PAT.summonFail) or string.find(msg, PAT.alreadySummon) then
        if TB.SetStatus then TB.SetStatus(msg, "warn") end
        local _, _, nm = string.find(msg, "'(%S+)'")
        if nm then
            local st = TB.GetState(nm)
            if st and (st.status == C.STATUS.SUMMONING or st.status == C.STATUS.INVITING) then
                st.status = st.online and C.STATUS.ONLINE or C.STATUS.OFFLINE
            end
        end
        handled = true
    end

    if handled and TB.Refresh then TB.Refresh() end
    TB.lastSystem = msg
end
