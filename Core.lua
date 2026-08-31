-- TortoiseBotsManager/Core.lua
-- Responsibilities:
--   * SavedVariables init + migration
--   * Throttled SendChatMessage queue for ".bot …"
--   * Poll orchestration (.bot list)
--   * Slash commands (/tbm primary, /tb /tbot aliases)
--   * Lifecycle (ADDON_LOADED, PLAYER_ENTERING_WORLD)
--
-- Non-responsibilities: roster model (Roster.lua), protocol parsing (Comms.lua), layout (UI.lua).

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
local C = TB.C or {} -- from Constants.lua (defensive fallback)

TB.version = (C and C.VERSION) or TB.version or "0.1.0"
TB.ADDON_NAME = "TortoiseBotsManager"

-- ── SavedVariables ──────────────────────────────────────────────────────────
local function initDB()
    if not TortoiseBotsDB then TortoiseBotsDB = {} end
    local db = TortoiseBotsDB

    if not db.roster  then db.roster  = {} end -- [Name] = { addedAt, discovered }
    -- C may be nil if Constants.lua failed to load; use hard defaults
    local defMinimap = (C and C.MINIMAP_DEFAULT) or { x = 52, y = 52 }
    if not db.minimap then db.minimap = { x = defMinimap.x, y = defMinimap.y } end
    if not db.frame   then db.frame   = { point = "CENTER", rpoint = "CENTER", x = 0, y = 15 } end
    if not db.pollInterval then db.pollInterval = (C and C.POLL_PANEL_IV) or 8 end
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
            TB.SendBotCommand(item.cmd, { queued = true })
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
        if string.lower(string.gsub(cmd, "%s+.*", "")) == "list" then
            TB._lastPoll = lastSend
            if TB.OnListCommandSent then TB.OnListCommandSent() end
        end
        return true
    else
        table.insert(sendQueue, { cmd = cmd, at = (GetTime and GetTime()) or 0 })
        ensureQueueFrame()
        return false
    end
end

-- ── Poll orchestration ──────────────────────────────────────────────────────
TB._lastPoll = TB._lastPoll or 0
local pendingReconcileFrame

local function scheduleReconcile()
    if pendingReconcileFrame then
        pendingReconcileFrame.wait = 1.2
        pendingReconcileFrame.elapsed = 0
        if pendingReconcileFrame.Show then pendingReconcileFrame:Show() end
        return
    end
    pendingReconcileFrame = CreateFrame("Frame", "TortoiseBotsManagerReconcileFrame")
    pendingReconcileFrame.elapsed = 0
    pendingReconcileFrame.wait = 1.2
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

-- Called only after a list command has actually left the client, including
-- commands released from the throttle queue.
TB.OnListCommandSent = scheduleReconcile

function TB.PollList(force)
    local now = (GetTime and GetTime()) or 0
    local throttle = (C and C.LIST_THROTTLE) or 5
    if not force and (now - (TB._lastPoll or 0)) < throttle then return end
    if TB.BeginPoll then TB.BeginPoll() end
    local sent = TB.SendBotCommand("list")
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
        TB.Print("Commands: /tbm — toggle, /tbm list — poll, /tbm resetpos — center, /tbm help — this")
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
        if TB.InitRoster  then TB.InitRoster()  end
        if TB.InitComms   then TB.InitComms()   end
        if TB.InitUI      then TB.InitUI()      end
        if TB.InitMinimap then TB.InitMinimap() end
        TB.Print("v" .. TB.version .. " loaded. /tbm to open. Requires TortoiseBots module on server.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
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
    if not TortoiseBotsDB or not TortoiseBotsDB.autoPoll then return end
    local shown = TB.frame and TB.frame:IsVisible()
    local fallbackPanel = (C and C.POLL_PANEL_IV) or 8
    local fallbackHidden = (C and C.POLL_HIDDEN_IV) or 20
    local iv = shown and (TortoiseBotsDB.pollInterval or fallbackPanel) or fallbackHidden
    if type(iv) ~= "number" then iv = fallbackHidden end
    local now = (GetTime and GetTime()) or 0
    if (now - (TB._lastPoll or 0)) >= iv then TB.PollList() end
end)
