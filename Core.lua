-- TortoiseBots/Core.lua — slash, throttle, poll orchestration, SavedVariables init
-- Vanilla 1.12 / 11200 safe. No libs.

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
TB.version = "0.1.0"

-- SavedVariables defaults (global + per-char)
local function initDB()
    if not TortoiseBotsDB then TortoiseBotsDB = {} end
    local db = TortoiseBotsDB
    if not db.roster then db.roster = {} end -- [name] = { addedAt, discovered }
    if not db.minimap then db.minimap = { x = 52, y = 52 } end
    if not db.frame then db.frame = { point = "CENTER", rpoint = "CENTER", x = 0, y = 15 } end
    if not db.pollInterval then db.pollInterval = 8 end
    if db.autoPoll == nil then db.autoPoll = true end
    -- migration: old roster as list
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

function TB.NormalizeName(s)
    s = s or ""
    s = string.gsub(s, "^%s+", ""); s = string.gsub(s, "%s+$", "")
    if s == "" then return nil end
    -- capitalize first, lower rest (matches normalizePlayerName)
    s = string.lower(s)
    s = string.gsub(s, "^%l", string.upper)
    -- keep only valid chars (let server reject rest)
    return s
end

-- Throttle: one SendChatMessage per 0.35s, queue if needed
TB._sendQueue = TB._sendQueue or {}
TB._lastSend = 0
TB._sendDelay = 0.35

function TB.CanSend()
    return (GetTime() - (TB._lastSend or 0)) >= TB._sendDelay
end

function TB.SendBotCommand(cmd, opts)
    opts = opts or {}
    cmd = cmd or ""
    cmd = string.gsub(cmd, "^%s+", ""); cmd = string.gsub(cmd, "%s+$", "")
    if cmd == "" then return false end
    local full = ".bot " .. cmd
    if TB.CanSend() and not opts.queued then
        TB._lastSend = GetTime()
        SendChatMessage(full)
        TB.lastCommand = cmd
        TB.lastCommandAt = GetTime()
        if TB.OnCommandSent then TB.OnCommandSent(cmd) end
        return true
    else
        table.insert(TB._sendQueue, { cmd = cmd, t = GetTime() })
        if not TB._queueFrame then
            TB._queueFrame = CreateFrame("Frame")
            TB._queueFrame:SetScript("OnUpdate", function()
                if table.getn(TB._sendQueue) == 0 then return end
                if not TB.CanSend() then return end
                local item = table.remove(TB._sendQueue, 1)
                TB.SendBotCommand(item.cmd, { queued = true })
            end)
        end
        return false
    end
end

-- Poll orchestration
TB._lastPoll = 0
TB._pendingListConfirm = 0 -- require 2 consecutive missing to mark offline (anti-flicker)

function TB.PollList(force)
    local iv = TortoiseBotsDB and TortoiseBotsDB.pollInterval or 8
    if not force and (GetTime() - TB._lastPoll) < 5 then return end -- hard throttle 5s
    TB._lastPoll = GetTime()
    TB.SendBotCommand("list")
    -- also refresh stats occasionally for counts
    if math.random() < 0.3 then TB.SendBotCommand("stats") end
end

function TB.RequestPollSoon(delay)
    delay = delay or 1.2
    local f = TB._pollFrame
    if not f then
        f = CreateFrame("Frame")
        TB._pollFrame = f
        f.elapsed = 0
        f.wait = nil
        f:SetScript("OnUpdate", function()
            if not this.wait then return end
            this.elapsed = this.elapsed + arg1
            if this.elapsed >= this.wait then
                this.wait = nil; this.elapsed = 0
                TB.PollList(true)
            end
        end)
    end
    f.wait = delay; f.elapsed = 0
end

-- Slash
SLASH_TORTOISEBOTS1 = "/tortoise"
SLASH_TORTOISEBOTS2 = "/tbot"
SLASH_TORTOISEBOTS3 = "/tb"
SlashCmdList["TORTOISEBOTS"] = function(msg)
    msg = string.gsub(msg or "", "^%s+", ""); msg = string.gsub(msg, "%s+$", "")
    msg = string.lower(msg)
    if msg == "help" or msg == "h" then
        TB.Print("Commands: /tb — toggle panel, /tb help — this, /tb list — poll")
        return
    elseif msg == "list" then
        TB.PollList(true); TB.Print("Polling .bot list…")
        return
    elseif msg == "resetpos" then
        TortoiseBotsDB.frame = { point="CENTER", rpoint="CENTER", x=0, y=15 }
        if TB.frame then TB.frame:ClearAllPoints(); TB.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15) end
        TB.Print("Position reset.")
        return
    end
    if TB.Toggle then TB.Toggle() else TB.Print("UI not loaded yet.") end
end

function TB.Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8a657TortoiseBots:|r " .. tostring(msg)) end
end

-- Lifecycle frame
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_LOGIN")
ef:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TortoiseBots" then
        initDB()
        if TB.InitRoster then TB.InitRoster() end
        if TB.InitComms then TB.InitComms() end
        if TB.InitUI then TB.InitUI() end
        if TB.InitMinimap then TB.InitMinimap() end
        TB.Print("v" .. TB.version .. " loaded. /tb to open. Requires TortoiseBots module on server.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        -- initial poll shortly after login (defer to avoid login spam)
        TB.RequestPollSoon(3.5)
    end
end)

-- Periodic poll while panel shown (and slower while hidden if autoPoll)
local pf = CreateFrame("Frame")
pf.elapsed = 0
pf:SetScript("OnUpdate", function()
    pf.elapsed = pf.elapsed + arg1
    if pf.elapsed < 1 then return end
    pf.elapsed = 0
    if not TortoiseBotsDB or not TortoiseBotsDB.autoPoll then return end
    local shown = TB.frame and TB.frame:IsVisible()
    local iv = shown and (TortoiseBotsDB.pollInterval or 8) or 20
    if (GetTime() - TB._lastPoll) >= iv then TB.PollList() end
end)
