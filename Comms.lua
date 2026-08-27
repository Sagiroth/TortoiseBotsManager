-- TortoiseBots/Comms.lua — send .bot and parse CHAT_MSG_SYSTEM
local TB = TortoiseBots

local function trim(s) s=s or ""; s=string.gsub(s,"^%s+",""); return string.gsub(s,"%s+$","") end

-- Patterns for system messages (must match BotCommands.cpp exact strings)
-- Keep lenient: server wording may shift slightly.
local PAT = {
    queued       = "queued for login", -- "Bot X queued for login; it will follow Y after entering"
    alreadyOnline= "already online and cannot be claimed",
    notFound     = "not found",
    sameAccount  = "You may only control characters on your account",
    summoning    = "Summoning (.+) to your location",
    summonFail   = "cannot be summoned",
    alreadySummon= "already being summoned",
    inviteSent   = "Invitation sent to bot",
    inviteReject = "was rejected by the native group handler",
    uninviteSent = "Uninvite sent for bot",
    noBotsOnline = "No owned PlayerBots are online",
    listLine     = "^(.+): (.+), random (%d+), AI (%d+)", -- "%s: %s, random %u, AI %u"
    statsLine    = "Owned PlayerBots: (%d+) online",
    willStay     = "will stay",
    nowFollowing = "now following",
    pullback     = "Pullback: tank",
    removed      = "Removal requested for bot",
    humanReclaim = "is not a module%-owned",
}

function TB.InitComms()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function()
        if event ~= "CHAT_MSG_SYSTEM" then return end
        local msg = arg1 or ""
        TB.OnSystemMessage(msg)
    end)
end

function TB.OnCommandSent(cmd)
    -- set transient states
    local verb = string.lower(string.gsub(cmd, "%s+.*", ""))
    local rest = trim(string.gsub(cmd, "^%S+%s*", ""))
    local name = TB.NormalizeName(rest)
    if verb == "summon" and name then
        TB.SetState(name, { status="summoning" })
        if TB.SetStatus then TB.SetStatus("Summoning " .. name .. "…", "pending") end
    elseif verb == "invite" and name then
        TB.SetState(name, { status="inviting" })
    elseif verb == "add" and name then
        TB.AddToRoster(name); TB.SetState(name, { status="starting", online=false })
    elseif verb == "remove" and name then
        TB.SetState(name, { status="removing" })
    end
    if TB.Refresh then TB.Refresh() end
    -- poll soon to confirm
    TB.RequestPollSoon(1.4)
end

function TB.OnSystemMessage(msg)
    if not msg or msg=="" then return end
    local handled = false

    -- 1) List lines (can be multiple per poll)
    -- Server sends per-bot: "Name: in world, random 0, AI 1" or "Name: starting, random 0, AI 0"
    local nm, stateStr, rStr, aiStr = string.gsub(msg, PAT.listLine, "%1|%2|%3|%4") -- test if matches
    -- use strfind with captures instead
    local _,_, n, s, r, a = string.find(msg, PAT.listLine)
    if n then
        local enteredWorld = (s == "in world")
        local random = (r == "1")
        local hasAI = (a == "1")
        TB.ConfirmSeen(n, { enteredWorld=enteredWorld, random=random, hasAI=hasAI })
        handled = true
        if TB.SetStatus then TB.SetStatus(msg, "ok") end
        if TB.Refresh then TB.Refresh() end
        return
    end

    if string.find(msg, PAT.noBotsOnline) then
        TB.MarkAllOfflinePending()
        -- second poll will confirm offline
        if TB.SetStatus then TB.SetStatus("No owned bots online.", "muted") end
        if TB.Refresh then TB.Refresh() end
        return
    end

    if string.find(msg, PAT.statsLine) then
        if TB.SetStatus then TB.SetStatus(msg, "muted") end
        return
    end

    -- 2) Action replies
    if string.find(msg, PAT.queued) then
        local _,_, botName = string.find(msg, "Bot (%S+) queued")
        if botName then TB.SetState(botName, { status="starting", online=false }) end
        TB.SetStatus(msg, "ok"); TB.RequestPollSoon(2); handled=true
    elseif string.find(msg, PAT.summoning) then
        local _,_, botName = string.find(msg, "Summoning (%S+)")
        if botName then TB.SetState(botName, { status="summoning" }) end
        TB.SetStatus(msg, "ok"); handled=true
    elseif string.find(msg, PAT.inviteSent) then
        TB.SetStatus(msg, "ok"); handled=true
        -- keep inviting for 4s then poll
        TB.RequestPollSoon(1.5)
    elseif string.find(msg, PAT.inviteReject) then
        TB.SetStatus(msg, "warn"); handled=true
    elseif string.find(msg, PAT.willStay) or string.find(msg, PAT.nowFollowing) or string.find(msg, PAT.pullback) then
        TB.SetStatus(msg, "ok"); handled=true
    elseif string.find(msg, PAT.removed) then
        TB.SetStatus(msg, "ok"); TB.RequestPollSoon(1.2); handled=true
    elseif string.find(msg, PAT.alreadyOnline) or string.find(msg, PAT.sameAccount) or string.find(msg, PAT.summonFail) or string.find(msg, PAT.alreadySummon) then
        TB.SetStatus(msg, "warn"); handled=true
        -- reconcile: reset transient status
        local _,_, nm2 = string.find(msg, "'(%S+)'")
        if nm2 then
            local st = TB.state[TB.NormalizeName(nm2) or nm2]
            if st and (st.status=="summoning" or st.status=="inviting") then st.status = st.online and "online" or "offline" end
        end
    end

    if handled and TB.Refresh then TB.Refresh() end

    -- 3) Track raw last system for debug status
    TB.lastSystem = msg
end

-- Helper: build command string safely
function TB.BuildCommand(verb, name, extra)
    verb = trim(verb or "")
    name = TB.NormalizeName(name or "")
    extra = trim(extra or "")
    if name and name~="" then
        if extra~="" then return verb.." "..name.." "..extra end
        return verb.." "..name
    else
        if extra~="" then return verb.." "..extra end
        return verb
    end
end
