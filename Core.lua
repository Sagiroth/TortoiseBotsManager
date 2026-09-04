-- TortoiseBotsManager/Core.lua
-- Responsibilities:
--   * UI-preference SavedVariables init + migration
--   * Throttled SendChatMessage queue for ".bot …"
--   * Authoritative roster poll orchestration (.bot roster)
--   * Slash commands (/tbm primary, /tb /tbot aliases)
--   * Lifecycle (ADDON_LOADED, PLAYER_ENTERING_WORLD)
--
-- Non-responsibilities: roster model (Roster.lua), protocol parsing (Comms.lua), layout (UI.lua).

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
local C = TB.C or {} -- from Constants.lua (defensive fallback)

TB.version = (C and C.VERSION) or TB.version or "0.1.0"
TB.ADDON_NAME = "TortoiseBotsManager"

-- ── SavedVariables (UI preferences only) ─────────────────────────────────────
local function initDB()
    if not TortoiseBotsDB then TortoiseBotsDB = {} end
    local db = TortoiseBotsDB

    -- Roster ownership is durable on the server now.  Drop old local roster
    -- shapes so they cannot accidentally become authoritative after reload.
    db.roster = nil
    db.rosterList = nil

    -- C may be nil if Constants.lua failed to load; use hard defaults.
    local defMinimap = (C and C.MINIMAP_DEFAULT) or { x = 52, y = 52 }
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if db.minimap.x == nil then db.minimap.x = defMinimap.x end
    if db.minimap.y == nil then db.minimap.y = defMinimap.y end
    if type(db.frame) ~= "table" then db.frame = {} end
    if not db.frame.point then db.frame.point = "CENTER" end
    if not db.frame.rpoint then db.frame.rpoint = "CENTER" end
    if db.frame.x == nil then db.frame.x = 0 end
    if db.frame.y == nil then db.frame.y = 15 end
    if not db.pollInterval then db.pollInterval = (C and C.POLL_PANEL_IV) or 8 end
    if db.autoPoll == nil then db.autoPoll = true end
    if type(db.botRoles) ~= "table" then db.botRoles = {} end
    if db.activeTab ~= "actions" and db.activeTab ~= "party" and db.activeTab ~= "roster" and db.activeTab ~= "log" then
        db.activeTab = "actions"
    end
end

-- The server still consumes normal chat commands on this client version.
-- Hide transport echoes and machine-readable TBM payloads.  Turtle clients
-- may omit ChatFrame_AddMessageEventFilter, so also guard the legacy global
-- ChatFrame_OnEvent dispatcher when it exists; critical non-TBM errors stay
-- visible.
local function parseBotLifecycleMessage(message)
    if not message or type(message) ~= "string" then return nil end
    local _, _, b, m = string.find(message, "^Bot%s+(%S+)%s+queued for login;%s*it will follow%s+(%S+)%s+after entering the world%.?")
    if b and m then
        return b .. " queued for login (following " .. m .. ")"
    end
    local _, _, b2 = string.find(message, "^Bot%s+(%S+)%s+logout requested;%s*durable ownership was retained%.?")
    if b2 then
        return b2 .. " logout requested"
    end
    local _, _, b3 = string.find(message, "^Summoning%s+(%S+)%s+to a safe position near you %(3s%);%s*it will follow on arrival%.?")
    if b3 then
        return "Summoning " .. b3 .. " to your position (3s)"
    end
    local _, _, t = string.find(message, "^Pullback requested:%s*tank%s+(%S+)%s+is using its native pull strategy%.?")
    if t then
        return "Pullback requested for tank " .. t
    end
    local _, _, bo = string.find(message, "^Character%s+'([^']+)'%s+is already online")
    if bo then
        return "Character '" .. bo .. "' is already online"
    end
    local _, _, bow = string.find(message, "^Character%s+'([^']+)'%s+is already owned")
    if bow then
        return "Character '" .. bow .. "' is already owned"
    end
    local _, _, f = string.find(message, "^Failed to add bot%s+(%S+)")
    if f then
        return "Failed to add bot " .. f
    end
    local _, _, fs = string.find(message, "^Failed to summon bot%s+'([^']+)'")
    if fs then
        return "Failed to summon bot '" .. fs .. "'"
    end
    local _, _, bnf = string.find(message, "^Bot%s+'([^']+)'%s+not found or not online")
    if bnf then
        return "Bot '" .. bnf .. "' not found or not online"
    end
    local _, _, bd = string.find(message, "^Bot%s+'([^']+)'%s+is dead")
    if bd then
        return "Bot '" .. bd .. "' is dead"
    end
    local _, _, bc = string.find(message, "^Bot%s+'([^']+)'%s+is in combat")
    if bc then
        return "Bot '" .. bc .. "' is in combat"
    end
    return nil
end

function TB.LogMessage(cleanMsg, rawMsg)
    local timeStr = (date and date("%H:%M:%S")) or (os and os.date and os.date("%H:%M:%S")) or "00:00:00"
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.logHistory = TortoiseBotsDB.logHistory or {}
    table.insert(TortoiseBotsDB.logHistory, {
        time = timeStr,
        msg = cleanMsg,
        raw = rawMsg or cleanMsg,
    })
    if table.getn(TortoiseBotsDB.logHistory) > 150 then
        table.remove(TortoiseBotsDB.logHistory, 1)
    end
    if TB.RefreshLogView then
        TB.RefreshLogView()
    end
end

function TB.GetLogHistory()
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.logHistory = TortoiseBotsDB.logHistory or {}
    return TortoiseBotsDB.logHistory
end

function TB.ClearLogHistory()
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.logHistory = {}
end

local function isBotCommandMessage(message)
    if not message then return false end
    if string.find(message, "^%.bot$") or string.find(message, "^%.bot%s") or string.find(message, "^TBM:") then
        return true
    end
    if string.find(message, "^Bot commands:") then
        local now = (GetTime and GetTime()) or 0
        if now - (TB._lastEnabledPrint or 0) > 1 then
            TB._lastEnabledPrint = now
            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffd8a657TortoiseBots:|r |cff20ff20Enabled|r")
            end
        end
        return true
    end
    local cleanMsg = parseBotLifecycleMessage(message)
    if cleanMsg then
        TB.LogMessage(cleanMsg, message)
        return true
    end
    return false
end

local CHAT_FILTER_EVENTS = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
}

local function installBotCommandChatFilter()
    if TB._chatFilterInstalled then return end
    local installed = false
    local function filter(_, _, message)
        if isBotCommandMessage(message) then return true end
    end
    if ChatFrame_AddMessageEventFilter then
        for eventName in pairs(CHAT_FILTER_EVENTS) do
            ChatFrame_AddMessageEventFilter(eventName, filter)
        end
        installed = true
    end
    if ChatFrame_OnEvent and not TB._chatEventFilterInstalled then
        local previousChatFrameOnEvent = ChatFrame_OnEvent
        ChatFrame_OnEvent = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
            local eventName = event
            local message = arg1
            if type(a1) == "string" then
                eventName = a1
                message = a2 or arg1
            elseif type(a2) == "string" then
                eventName = a2
                message = a3 or arg1
            end
            if eventName and CHAT_FILTER_EVENTS[eventName] and isBotCommandMessage(message) then
                return
            end
            return previousChatFrameOnEvent(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
        end
        TB._chatEventFilterInstalled = true
        installed = true
    end
    TB._chatFilterInstalled = installed
end

-- ── Throttled send queue ────────────────────────────────────────────────────
local sendQueue = {} -- { {cmd, at} }
local lastSend = 0
local capabilitiesRequested = false
local rosterBatchQueue = {}
local activeRosterBatch = nil
local rosterBatchFrame
local rosterBatchId = 0

function TB.CanSend()
    local now = (GetTime and GetTime()) or 0
    local delay = (C and C.SEND_DELAY) or 0.35
    return (now - (lastSend or 0)) >= delay
end

local queueFrame -- lazy

local function ensureQueueFrame()
    if queueFrame then return end
    queueFrame = CreateFrame("Frame", "TortoiseBotsManagerQueueFrame")
    queueFrame:SetScript("OnUpdate", function()
        if table.getn(sendQueue) == 0 then return end
        if not TB.CanSend() then return end
        local item = table.remove(sendQueue, 1)
        if item and item.cmd then
            TB.SendBotCommand(item.cmd, item.opts or { queued = true })
        end
    end)
end
function TB.SendBotCommand(cmd, opts)
    opts = opts or {}
    cmd = TB.Trim(cmd or "")
    if cmd == "" then return false end

    local full = ".bot " .. cmd
    if TB.CanSend() then
        lastSend = (GetTime and GetTime()) or 0
        if SendChatMessage then SendChatMessage(full) end
        TB.lastCommand   = cmd
        TB.lastCommandAt = lastSend
        if TB.OnCommandSent then TB.OnCommandSent(cmd) end
        if opts.rosterBatch and TB.OnRosterBatchCommandSent then
            TB.OnRosterBatchCommandSent(cmd)
        end
        local verb = string.lower(string.gsub(cmd, "%s+.*", ""))
        if verb == "roster" or verb == "list" then
            TB._lastPoll = lastSend
            if TB.OnListCommandSent then TB.OnListCommandSent(verb) end
        end
        return true
    else
        table.insert(sendQueue, {
            cmd = cmd, opts = opts, at = (GetTime and GetTime()) or 0,
        })
        if TB.OnCommandQueued then TB.OnCommandQueued(cmd) end
        ensureQueueFrame()
        return false
    end
end

-- Roster lifecycle batches are serialized at the server-response boundary.
-- The generic transport queue still handles chat throttling, but a second
-- invite is not released until the first invite has been accepted or rejected.
local function rosterBatchNow()
    return (GetTime and GetTime()) or 0
end

local startRosterBatch

local function finishRosterBatch(batch)
    if activeRosterBatch ~= batch then return end
    activeRosterBatch = nil
    if rosterBatchFrame and rosterBatchFrame.Hide then rosterBatchFrame:Hide() end
    local total = table.getn(batch.names)
    local completed = batch.succeeded or 0
    local failed = batch.failed or 0
    if TB.SetStatus then
        local kind = failed > 0 and "warn" or "ok"
        local outcome = batch.verb == "invite" and "joined" or "acknowledged"
        TB.SetStatus(batch.verb .. " complete · " .. completed .. "/" .. total .. " " .. outcome, kind)
    end
    local nextBatch = table.remove(rosterBatchQueue, 1)
    if nextBatch then startRosterBatch(nextBatch) end
end

local function rosterBatchTimeout()
    local batch = activeRosterBatch
    if not batch or not batch.sentAt then return end
    local timeout = (C and C.ACTION_TIMEOUT) or 8
    if batch.verb == "invite" and batch.inviteDispatched then
        timeout = (C and C.INVITE_ACCEPT_TIMEOUT) or 20
    end
    if rosterBatchNow() - batch.sentAt < timeout then return end

    local name = batch.names[batch.index]
    if not name then return end
    local message = name .. " " .. batch.verb .. " timed out."
    if batch.verb == "invite" and batch.inviteDispatched then
        if TB.CompleteOperation then
            TB.CompleteOperation(name, batch.verb, false, message)
        end
        if TB.OnRosterBatchResult then
            TB.OnRosterBatchResult(name, batch.verb, false, message)
        end
    elseif (batch.attempts or 0) < 2 then
        batch.sentAt = nil
        if TB.AcknowledgeOperation then TB.AcknowledgeOperation(name, batch.verb) end
        if TB.BeginOperation then TB.BeginOperation(name, batch.verb, true) end
        if TB.SetStatus then TB.SetStatus("Retrying " .. batch.verb .. " for " .. name .. "…", "pending") end
        TB.SendBotCommand(batch.command, { rosterBatch = true })
    else
        if TB.CompleteOperation then
            TB.CompleteOperation(name, batch.verb, false, message)
        end
        if TB.OnRosterBatchResult then
            TB.OnRosterBatchResult(name, batch.verb, false, message)
        end
    end
end

local function ensureRosterBatchFrame()
    if rosterBatchFrame then return end
    rosterBatchFrame = CreateFrame("Frame", "TortoiseBotsManagerRosterBatchFrame")
    rosterBatchFrame:SetScript("OnUpdate", function()
        rosterBatchTimeout()
    end)
end

startRosterBatch = function(batch)
    activeRosterBatch = batch
    batch.index = 1
    batch.attempts = 0
    batch.succeeded = 0
    batch.failed = 0

    local timeout = (batch.verb == "invite" and (C and C.INVITE_ACCEPT_TIMEOUT))
        or (C and C.ACTION_TIMEOUT) or 8
    local batchDeadline = rosterBatchNow() + timeout * (table.getn(batch.names) * 2 + 1)
    for _, name in ipairs(batch.names) do
        if TB.BeginOperation then TB.BeginOperation(name, batch.verb, true) end
        local st = TB.GetState and TB.GetState(name) or nil
        if st and st.operation then st.operation.deadline = batchDeadline end
    end

    ensureRosterBatchFrame()
    if rosterBatchFrame.Show then rosterBatchFrame:Show() end
    batch.command = TB.BuildCommand(batch.verb, batch.names[batch.index])
    TB.SendBotCommand(batch.command, { rosterBatch = true })
end

function TB.IsRosterBatchActive(verb)
    verb = verb and string.lower(TB.Trim(verb)) or nil
    if activeRosterBatch and (not verb or activeRosterBatch.verb == verb) then return true end
    for _, batch in ipairs(rosterBatchQueue) do
        if not verb or batch.verb == verb then return true end
    end
    return false
end

function TB.QueueRosterBatch(verb, names)
    verb = string.lower(TB.Trim(verb or ""))
    if verb == "" or type(names) ~= "table" then return false end
    local clean, seen = {}, {}
    for _, name in ipairs(names) do
        name = TB.NormalizeName and TB.NormalizeName(name or "") or name
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(clean, name)
        end
    end
    if table.getn(clean) == 0 then return false end

    rosterBatchId = rosterBatchId + 1
    local batch = { id = rosterBatchId, verb = verb, names = clean }
    table.insert(rosterBatchQueue, batch)
    if not activeRosterBatch then
        startRosterBatch(table.remove(rosterBatchQueue, 1))
    elseif TB.SetStatus then
        TB.SetStatus(verb .. " queued · " .. table.getn(clean) .. " bots", "pending")
    end
    return true
end

function TB.OnRosterBatchCommandSent(cmd)
    local batch = activeRosterBatch
    if not batch or batch.command ~= cmd then return false end
    batch.sentAt = rosterBatchNow()
    batch.inviteDispatched = nil
    batch.attempts = (batch.attempts or 0) + 1
    return true
end

function TB.OnRosterBatchInviteDispatched(name)
    local batch = activeRosterBatch
    name = TB.NormalizeName and TB.NormalizeName(name or "") or name
    if not batch or not batch.sentAt or batch.verb ~= "invite"
        or batch.names[batch.index] ~= name then
        return false
    end
    batch.inviteDispatched = true
    batch.sentAt = rosterBatchNow()
    return true
end

function TB.OnRosterBatchInviteJoined(name)
    if not TB.OnRosterBatchResult then return false end
    return TB.OnRosterBatchResult(name, "invite", true)
end

function TB.OnRosterBatchResult(name, verb, success)
    local batch = activeRosterBatch
    name = TB.NormalizeName and TB.NormalizeName(name or "") or name
    verb = string.lower(TB.Trim(verb or ""))
    if not batch or not batch.sentAt or batch.verb ~= verb
        or batch.names[batch.index] ~= name then
        return false
    end

    batch.sentAt = nil
    if success then batch.succeeded = batch.succeeded + 1
    else batch.failed = batch.failed + 1 end
    batch.index = batch.index + 1
    batch.attempts = 0

    local nextName = batch.names[batch.index]
    if not nextName then
        finishRosterBatch(batch)
        return true
    end
    batch.command = TB.BuildCommand(batch.verb, nextName)
    TB.SendBotCommand(batch.command, { rosterBatch = true })
    return true
end

-- One gameplay intent is one server request.  Roster selection never enters
-- this path; the server resolves dynamic scope from the normal WoW target.
function TB.SendActionIntent(intent)
    intent = TB.Trim(intent or "")
    if intent == "" then return false end
    return TB.SendBotCommand("action " .. intent)
end

function TB.SetFormation(formationId)
    formationId = TB.Trim(formationId or "default")
    TB.currentFormation = formationId
    local scope, botName = TB.GetTargetScope and TB.GetTargetScope() or "party"
    if scope == "bot" and botName then
        TB.SendBotCommand("formation " .. botName .. " " .. formationId)
    else
        TB.SendBotCommand("formation " .. formationId)
    end
    if TB.UpdateFormationPills then TB.UpdateFormationPills() end
end

function TB.RequestServerCapabilities()
    if capabilitiesRequested then return false end
    capabilitiesRequested = true
    return TB.SendBotCommand("help")
end

-- ── Poll orchestration ──────────────────────────────────────────────────────
TB._lastPoll = TB._lastPoll or 0
local pendingReconcileFrame

local function scheduleReconcile()
    local wait = (C and C.POLL_WAIT) or 1.2
    if pendingReconcileFrame then
        pendingReconcileFrame.wait = wait
        pendingReconcileFrame.elapsed = 0
        if pendingReconcileFrame.Show then pendingReconcileFrame:Show() end
        return
    end
    pendingReconcileFrame = CreateFrame("Frame", "TortoiseBotsManagerReconcileFrame")
    pendingReconcileFrame.elapsed = 0
    pendingReconcileFrame.wait = wait
    pendingReconcileFrame:SetScript("OnUpdate", function()
        if not this.wait then return end
        this.elapsed = (this.elapsed or 0) + (arg1 or 0)
        if this.elapsed >= this.wait then
            local w = this.wait
            this.wait = nil
            this.elapsed = 0
            if this.Hide then this:Hide() end
            if w and TB.ReconcilePoll then TB.ReconcilePoll() end
        end
    end)
    if pendingReconcileFrame.Show then pendingReconcileFrame:Show() end
end

-- Called only after a roster/list command has actually left the client,
-- including commands released from the throttle queue.
TB._pollPending = TB._pollPending or false
TB._pollQueued = false
TB.OnListCommandSent = function(verb)
    TB._pollQueued = false
    TB._pollPending = true
    if TB.BeginPoll then TB.BeginPoll(verb) end
    scheduleReconcile()
end

function TB.PollList(force)
    local now = (GetTime and GetTime()) or 0
    local throttle = (C and (C.ROSTER_THROTTLE or C.LIST_THROTTLE)) or 5
    if TB._pollPending or TB._pollQueued then return false end
    if not force and (TB._lastPoll or 0) > 0 and (now - TB._lastPoll) < throttle then
        return false
    end
    TB._pollQueued = true
    local sent = TB.SendBotCommand("roster")
    return sent
end

local pollFrame
function TB.RequestPollSoon(delay)
    delay = delay or (C and C.POLL_AFTER_CMD) or 1.4
    if type(delay) ~= "number" then delay = 1.4 end
    if not pollFrame then
        pollFrame = CreateFrame("Frame", "TortoiseBotsManagerPollFrame")
        pollFrame.elapsed = 0
        pollFrame.wait = nil
        pollFrame:SetScript("OnUpdate", function()
            if not this.wait then return end
            this.elapsed = (this.elapsed or 0) + (arg1 or 0)
            if this.elapsed >= this.wait then
                this.wait = nil; this.elapsed = 0
                if this.Hide then this:Hide() end
                TB.PollList(true)
            end
        end)
    end
    pollFrame.wait = delay
    pollFrame.elapsed = 0
    if pollFrame.Show then pollFrame:Show() end
end
-- ── Slash ───────────────────────────────────────────────────────────────────
SLASH_TORTOISEBOTSMANAGER1 = "/tbm"
SLASH_TORTOISEBOTSMANAGER2 = "/tb"
SLASH_TORTOISEBOTSMANAGER3 = "/tbot"
SLASH_TORTOISEBOTSMANAGER4 = "/tortoise"
SlashCmdList["TORTOISEBOTSMANAGER"] = function(msg)
    msg = string.lower(TB.Trim(msg or ""))
    if msg == "help" or msg == "h" then
        TB.Print("Commands: /tbm — toggle, /tbm party — show party, /tbm log — show log, /tbm list — poll, /tbm resetpos — center, /tbm help — this")
        return
    elseif msg == "party" then
        if TB.frame and not TB.frame:IsVisible() and TB.Toggle then TB.Toggle() end
        if TB.ShowTab then TB.ShowTab("party") end
        return
    elseif msg == "log" then
        if TB.frame and not TB.frame:IsVisible() and TB.Toggle then TB.Toggle() end
        if TB.ShowTab then TB.ShowTab("log") end
        return
    elseif msg == "list" then
        TB.PollList(true); TB.Print("Polling server roster…"); return
    elseif msg == "resetpos" then
        TortoiseBotsDB.frame = { point = "CENTER", rpoint = "CENTER", x = 0, y = 15 }
        if TB.frame then TB.frame:ClearAllPoints(); TB.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15) end
        TB.Print("Position reset."); return
    end
    if TB.Toggle then TB.Toggle() else TB.Print("UI not loaded yet.") end
end

function TB.Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8a657TortoiseBots Manager:|r " .. tostring(msg)) end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────
local ef = CreateFrame("Frame", "TortoiseBotsManagerCoreFrame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and (arg1 == "TortoiseBotsManager" or arg1 == "TortoiseBots") then
        initDB()
        installBotCommandChatFilter()
        if TB.InitRoster  then TB.InitRoster()  end
        if TB.InitComms   then TB.InitComms()   end
        if TB.InitUI      then TB.InitUI()      end
        if TB.InitMinimap then TB.InitMinimap() end
        TB.Print("v" .. TB.version .. " loaded. /tbm to open. Requires TortoiseBots module on server.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        installBotCommandChatFilter()
        if TB.RequestServerCapabilities then TB.RequestServerCapabilities() end
        TB.RequestPollSoon(3.5)
    end
end)

-- Periodic poll (panel open: 8s, hidden: 20s, respects autoPoll)
local pf = CreateFrame("Frame", "TortoiseBotsManagerAutoPoll")
pf.elapsed = 0
pf:SetScript("OnUpdate", function()
    pf.elapsed = (pf.elapsed or 0) + (arg1 or 0)
    if (pf.elapsed or 0) < 1 then return end
    pf.elapsed = 0
    local now = (GetTime and GetTime()) or 0
    if TB.UpdateStateTimers then TB.UpdateStateTimers(now) end
    if not TortoiseBotsDB or not TortoiseBotsDB.autoPoll then return end
    local shown = TB.frame and TB.frame:IsVisible()
    local fallbackPanel = (C and C.POLL_PANEL_IV) or 8
    local fallbackHidden = (C and C.POLL_HIDDEN_IV) or 20
    local iv = shown and (TortoiseBotsDB.pollInterval or fallbackPanel) or fallbackHidden
    if type(iv) ~= "number" then iv = fallbackHidden end
    if (now - (TB._lastPoll or 0)) >= iv then TB.PollList() end
end)
