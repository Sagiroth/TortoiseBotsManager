-- TortoiseBots/Core.lua
-- Responsibilities:
--   * SavedVariables init + migration
--   * Throttled SendChatMessage queue for ".bot …"
--   * Poll orchestration (.bot list)
--   * Slash commands (/tb /tbot /tortoise)
--   * Lifecycle (ADDON_LOADED, PLAYER_ENTERING_WORLD)
--
-- Non-responsibilities: roster model (Roster.lua), protocol parsing (Comms.lua), layout (UI.lua).

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
local C = TB.C -- from Constants.lua

TB.version = C.VERSION

-- ── SavedVariables ──────────────────────────────────────────────────────────
local function initDB()
    if not TortoiseBotsDB then TortoiseBotsDB = {} end
    local db = TortoiseBotsDB

    if not db.roster  then db.roster  = {} end -- [Name] = { addedAt, discovered }
    if not db.minimap then db.minimap = { x = C.MINIMAP_DEFAULT.x, y = C.MINIMAP_DEFAULT.y } end
    if not db.frame   then db.frame   = { point = "CENTER", rpoint = "CENTER", x = 0, y = 15 } end
    if not db.pollInterval then db.pollInterval = C.POLL_PANEL_IV end
    if db.autoPoll == nil  then db.autoPoll = true end

    -- migration: old list form
    if db.rosterList then
        for _, n in ipairs(db.rosterList) do
            local key = TB.NormalizeName(n)
            if key and not db.roster[key] then db.roster[key] = { addedAt = time() } end
        end
        db.rosterList = nil
    end

    if not TortoiseBotsCharDB then TortoiseBotsCharDB = {} end
    if not TortoiseBotsCharDB.recent then TortoiseBotsCharDB.recent = {} end
end

-- ── Throttled send queue ────────────────────────────────────────────────────
local sendQueue = {} -- { {cmd, at} }
local lastSend = 0

function TB.CanSend()
    return (GetTime() - lastSend) >= C.SEND_DELAY
end

local queueFrame -- lazy

local function ensureQueueFrame()
    if queueFrame then return end
    queueFrame = CreateFrame("Frame", "TortoiseBotsQueueFrame")
    queueFrame:SetScript("OnUpdate", function()
        if table.getn(sendQueue) == 0 then return end
        if not TB.CanSend() then return end
        local item = table.remove(sendQueue, 1)
        TB.SendBotCommand(item.cmd, { queued = true })
    end)
end

function TB.SendBotCommand(cmd, opts)
    opts = opts or {}
    cmd = TB.Trim(cmd or "")
    if cmd == "" then return false end

    local full = ".bot " .. cmd
    if TB.CanSend() and not opts.queued then
        lastSend = GetTime()
        SendChatMessage(full)
        TB.lastCommand   = cmd
        TB.lastCommandAt = lastSend
        if TB.OnCommandSent then TB.OnCommandSent(cmd) end
        -- track actual send time for poll throttle
        if string.lower(string.gsub(cmd, "%s+.*", "")) == "list" then
            TB._lastPoll = lastSend
        end
        return true
    else
        table.insert(sendQueue, { cmd = cmd, at = GetTime() })
        ensureQueueFrame()
        return false
    end
end

-- ── Poll orchestration ──────────────────────────────────────────────────────
TB._lastPoll = 0
local pendingReconcileFrame

local function scheduleReconcile()
    if pendingReconcileFrame then pendingReconcileFrame.wait = 1.2; pendingReconcileFrame.elapsed=0; return end
    pendingReconcileFrame = CreateFrame("Frame", "TortoiseBotsReconcileFrame")
    pendingReconcileFrame.elapsed=0; pendingReconcileFrame.wait=1.2
    pendingReconcileFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= this.wait then
            this.wait=nil; this.elapsed=0
            if TB.ReconcilePoll then TB.ReconcilePoll() end
        end
    end)
end

function TB.PollList(force)
    if not force and (GetTime() - TB._lastPoll) < C.LIST_THROTTLE then return end
    -- begin poll window before send so confirms can mark seen
    if TB.BeginPoll then TB.BeginPoll() end
    local sent = TB.SendBotCommand("list")
    if not sent then
        -- queued — _lastPoll will be set when actually sent via OnCommandSent
        -- still schedule reconcile for when it does send (will be re-scheduled on send)
    end
    scheduleReconcile()
    if math.random() < 0.3 then TB.SendBotCommand("stats") end
end

local pollFrame
function TB.RequestPollSoon(delay)
    delay = delay or C.POLL_AFTER_CMD
    if not pollFrame then
        pollFrame = CreateFrame("Frame", "TortoiseBotsPollFrame")
        pollFrame.elapsed = 0
        pollFrame.wait = nil
        pollFrame:SetScript("OnUpdate", function()
            if not this.wait then return end
            this.elapsed = this.elapsed + arg1
            if this.elapsed >= this.wait then
                this.wait = nil; this.elapsed = 0
                TB.PollList(true)
            end
        end)
    end
    pollFrame.wait = delay
    pollFrame.elapsed = 0
end

-- ── Slash ───────────────────────────────────────────────────────────────────
SLASH_TORTOISEBOTS1 = "/tortoise"
SLASH_TORTOISEBOTS2 = "/tbot"
SLASH_TORTOISEBOTS3 = "/tb"
SlashCmdList["TORTOISEBOTS"] = function(msg)
    msg = string.lower(TB.Trim(msg or ""))
    if msg == "help" or msg == "h" then
        TB.Print("Commands: /tb — toggle panel, /tb list — poll, /tb resetpos — center window, /tb help — this")
        return
    elseif msg == "list" then
        TB.PollList(true); TB.Print("Polling .bot list…"); return
    elseif msg == "resetpos" then
        TortoiseBotsDB.frame = { point = "CENTER", rpoint = "CENTER", x = 0, y = 15 }
        if TB.frame then TB.frame:ClearAllPoints(); TB.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15) end
        TB.Print("Position reset."); return
    end
    if TB.Toggle then TB.Toggle() else TB.Print("UI not loaded yet.") end
end

function TB.Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8a657TortoiseBots:|r " .. tostring(msg)) end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────
local ef = CreateFrame("Frame", "TortoiseBotsCoreFrame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TortoiseBots" then
        initDB()
        if TB.InitRoster  then TB.InitRoster()  end
        if TB.InitComms   then TB.InitComms()   end
        if TB.InitUI      then TB.InitUI()      end
        if TB.InitMinimap then TB.InitMinimap() end
        TB.Print("v" .. TB.version .. " loaded. /tb to open. Requires TortoiseBots module on server.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        TB.RequestPollSoon(3.5)
    end
end)

-- Periodic poll (panel open: 8s, hidden: 20s, respects autoPoll)
local pf = CreateFrame("Frame", "TortoiseBotsAutoPoll")
pf.elapsed = 0
pf:SetScript("OnUpdate", function()
    pf.elapsed = pf.elapsed + arg1
    if pf.elapsed < 1 then return end
    pf.elapsed = 0
    if not TortoiseBotsDB or not TortoiseBotsDB.autoPoll then return end
    local shown = TB.frame and TB.frame:IsVisible()
    local iv = shown and (TortoiseBotsDB.pollInterval or C.POLL_PANEL_IV) or C.POLL_HIDDEN_IV
    if (GetTime() - TB._lastPoll) >= iv then TB.PollList() end
end)
