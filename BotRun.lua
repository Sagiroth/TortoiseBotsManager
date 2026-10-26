-- TortoiseBotsManager/BotRun.lua
-- Dungeon run window (Preview): drives the server's opt-in run leader
-- (docs/play/commands/commander.md "Run Leader (.bot run)").
--
-- The server appends "dungeon-run" to "TBM:CAPS|..." only while
-- AiPlayerbot.DungeonSelfClear and AiPlayerbot.RemoteCommander are both on.
-- No capability: no button, no window, no sends. Every CAPS line replaces
-- the set, so the gate is re-checked on each one (a restart that drops the
-- feature hides everything again).
--
-- Sends (byte-exact, one per click; Commander.cpp):
--   "commander bind <LeadBot> [<Bot> ...] inparty" (bot-led: up to five
--     bots, you stay in the party)
--   "commander unbind" / "commander status"
--   "cmd enter near" (nearest entrance trigger within ReactDistance)
--   "run list" -> "Dungeon plans: <name> (map <m>, <s> steps[, <u> not
--     supported yet])[, ...]" + TBM:ACTION_ACK|run list|plans|<n>|-
--   "run start [plan] [from leg|step N] [player [tank <Bot>]]" (player:
--     you lead, the start binds your party itself) / pause / resume / skip /
--     "stop [reason]" / status
-- Inbound:
--   TBM:RUN|<plan>|<state>|<step>/<steps>|<leg>|<kind>|<phase>|<note>
--     [|left <K>][|speed <x> (test)]
--   The first 8 fields always exist; later fields are optional extras.
--   "no run" is TBM:RUN|-|none|0/0|-|-|-|no run.
--   TBM:ACTION_ACK/ERR for the commander / cmd / run intents (generic
--   routing in Comms.lua; labels live in C.ACTION_LABELS).
--
-- Bot-led: any player order to the party (.bot action, .bot cmd, whispers)
-- pauses a running run until resume: the window says so, and
-- SendActionIntent warns on the status line when a run is running.
-- Player-led: your orders are obeyed and never pause the run.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local RW = 300
local PROW = 5

local CAP = "dungeon-run"

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end

-- ── capability gate ─────────────────────────────────────────────────────
function TB.HasRunCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

-- ── model ─────────────────────────────────────────────────────────────────
-- run = { plan, state, step, steps, leg, kind, phase, note, left, speed }
local run = nil

function TB.GetRun()
    return run
end

-- plans = { { name, map, steps, unsupported } }, from the "run list" reply.
local plans = {}
local plansAt = 0
local plansPending = false

function TB.GetRunPlans()
    return plans
end

function TB.IsRunListPending()
    return plansPending
end

-- Parses one loaded plan: "uldaman (map 70, 41 steps, 2 not supported yet)".
-- Returns name, map, steps, unsupported. The "not supported" tail appears
-- only when some step is unsupported (Commander.cpp:6938-6940).
local function parsePlanEntry(text)
    if not text or text == "" then return nil end
    local _, _, name, map, steps, unsupported = string.find(text,
        "^%s*(.-)%s*%(%s*map%s+(%d+)%s*,%s*(%d+)%s+steps%s*(.-)%)%s*$")
    if not name or name == "" then return nil end
    local unsup = 0
    if unsupported and unsupported ~= "" then
        local _, _, n = string.find(unsupported, "(%d+)%s+not supported yet")
        unsup = tonumber(n) or 0
    end
    return name, tonumber(map), tonumber(steps), unsup
end
TB.ParseRunPlanEntry = parsePlanEntry

-- Parses the "run list" reply: "Dungeon plans: <entry>[, <entry> ...]" or
-- "Dungeon plans: none loaded". Commas split entries, but they also sit
-- inside the "(map …, … steps…)"tails, so split on "), " boundaries.
local function parsePlanList(msg)
    if not msg then return nil end
    local _, _, body = string.find(msg, "^Dungeon plans:%s*(.-)%s*$")
    if not body then return nil end
    if body == "none loaded" then return {} end
    local list = {}
    local rest = body
    while rest and rest ~= "" do
        local cut = string.find(rest, "%)%s*,%s*", 1)
        local entry
        if cut then
            entry = string.sub(rest, 1, cut)
            rest = string.sub(rest, cut + 1)
            rest = string.gsub(rest, "^%s*,%s*", "")
        else
            entry = rest
            rest = ""
        end
        local name, map, steps, unsupported = parsePlanEntry(entry)
        if name then
            table.insert(list, { name = name, map = map, steps = steps,
                unsupported = unsupported or 0 })
        end
    end
    return list
end
TB.ParseRunPlanList = parsePlanList

-- TBM:RUN|<plan>|<state>|<step>/<steps>|<leg>|<kind>|<phase>|<note>
-- [|left <K>][|speed <x> (test)]
-- The note never holds a "|" (the server turns them into spaces), so split
-- the first 8 fields and treat the rest as optional extras.
local function parseRunLine(msg)
    if not msg then return nil end
    local prefix = "TBM:RUN|"
    if string.sub(msg, 1, string.len(prefix)) ~= prefix then return nil end
    -- Plan, state, step/steps, leg, kind: the first five separators. The
    -- tail (phase, note, extras) holds no "|" of its own — the server
    -- turns them into spaces — so it splits at its first two separators.
    local fields = {}
    local rest = string.sub(msg, string.len(prefix) + 1)
    while table.getn(fields) < 5 do
        local at = string.find(rest, "|", 1, true)
        if not at then return nil end
        table.insert(fields, string.sub(rest, 1, at - 1))
        rest = string.sub(rest, at + 1)
    end
    local at = string.find(rest, "|", 1, true)
    if not at then return nil end
    table.insert(fields, string.sub(rest, 1, at - 1)) -- phase
    rest = string.sub(rest, at + 1)
    local note, extras
    at = string.find(rest, "|", 1, true)
    if at then
        note = string.sub(rest, 1, at - 1)
        extras = string.sub(rest, at + 1)
    else
        note = rest
    end
    local plan, state, frac, leg, kind, phase = fields[1], fields[2],
        fields[3], fields[4], fields[5], fields[6]
    if plan == "" or state == "" or frac == "" or leg == "" or kind == ""
        or phase == "" then
        return nil
    end
    local _, _, step, steps = string.find(frac, "^(%d+)/(%d+)$")
    if not step then return nil end
    if note == "" then note = "-" end
    local out = {
        plan = plan,
        state = state,
        step = tonumber(step),
        steps = tonumber(steps),
        leg = leg,
        kind = kind,
        phase = phase,
        note = note,
        left = nil,
        speed = nil,
    }
    -- Optional extras: "|left <K>" (packs deferred), "|speed <x> (test)".
    if extras and extras ~= "" then
        for extra in string.gfind(extras, "[^|]+") do
            local _, _, left = string.find(extra, "^%s*left%s+(%d+)%s*$")
            if left then out.left = tonumber(left) end
            local _, _, speed = string.find(extra, "^%s*speed%s+(.-)%s*$")
            if speed and speed ~= "" then out.speed = speed end
        end
    end
    return out
end
TB.ParseRunLine = parseRunLine

-- Inbound router hook (called from Comms OnSystemMessage): the TBM:RUN
-- status line and the "run list" plan reply.
function TB.ParseRunMessage(msg)
    if not msg or msg == "" then return false end
    if string.sub(msg, 1, 8) == "TBM:RUN|" then
        local parsed = parseRunLine(msg)
        if not parsed then return false end
        run = parsed
        if TB.RefreshRunWindow then TB.RefreshRunWindow() end
        return true, "run", parsed
    end
    local list = parsePlanList(msg)
    if list then
        plans = list
        plansAt = (GetTime and GetTime()) or 0
        plansPending = false
        if TB.RefreshRunWindow then TB.RefreshRunWindow() end
        if TB.SetStatus then
            if table.getn(list) == 0 then
                TB.SetStatus("No dungeon plans loaded.", "warn")
            else
                TB.SetStatus("Dungeon plans · " .. table.getn(list), "ok")
            end
        end
        return true, "plans", list
    end
    return false
end

-- ── feedback ──────────────────────────────────────────────────────────────
-- The window's answer line: what was sent, then the server's ACK or ERR.
local feedback = nil

local function setFeedback(text, kind)
    feedback = { text = text, kind = kind }
    if TB.RefreshRunWindow then TB.RefreshRunWindow() end
end

function TB.GetRunFeedback()
    return feedback
end

local FEEDBACK_LABEL = {
    ["commander bind"] = "Bind", ["commander unbind"] = "Unbind", ["commander status"] = "Party status",
    ["cmd enter"] = "Enter", ["run list"] = "Plans", ["run start"] = "Start", ["run pause"] = "Pause",
    ["run resume"] = "Resume", ["run skip"] = "Skip", ["run stop"] = "Stop", ["run status"] = "Status",
}

local function feedbackLabel(intent)
    for prefix, label in pairs(FEEDBACK_LABEL) do
        if string.sub(intent or "", 1, string.len(prefix)) == prefix then return label end
    end
    return nil
end

local function sent(cmd, ok)
    local label = feedbackLabel(cmd)
    if ok and label then setFeedback(label .. " sent, waiting for the server...", "pending") end
    return ok
end

function TB.OnRunError(packet)
    local label = packet and feedbackLabel(packet.intent)
    if not label then return false end
    -- The window's own status ask with no run is no refusal: just no run.
    if packet.intent == "run status" and packet.code == "not-bound" then
        run = { plan = "-", state = "none", step = 0, steps = 0, leg = "-",
            kind = "-", phase = "-", note = "no run" }
        if TB.RefreshRunWindow then TB.RefreshRunWindow() end
        return false
    end
    local message = packet.message ~= "" and packet.message or packet.code
    if string.len(message) > 80 then message = string.sub(message, 1, 77) .. "..." end
    setFeedback("|cffff5050" .. label .. " refused:|r " .. message, "err")
    return false
end

-- ACK/ERR routing for the run intents (called from ParseActionMessage):
-- "run status" with no run answers "no run" plus this ACK, so clear the
-- model; every other ACK/ERR keeps the generic status text.
function TB.OnRunAck(packet)
    if not packet then return false end
    local intent = packet.intent or ""
    local label = feedbackLabel(intent)
    if label then
        local text = "|cff40ff40" .. label .. " done.|r"
        if intent == "run list" then text = "|cff40ff40" .. packet.count .. " plans loaded.|r"
        elseif packet.executor ~= "-" then text = "|cff40ff40" .. label .. " done:|r " .. packet.executor end
        setFeedback(text, "ok")
    end
    if intent == "run status" and packet.executor == "-"
        and (packet.count or 0) == 0 then
        run = { plan = "-", state = "none", step = 0, steps = 0, leg = "-",
            kind = "-", phase = "-", note = "no run" }
        if TB.RefreshRunWindow then TB.RefreshRunWindow() end
    end
    return false
end

-- ── sends ─────────────────────────────────────────────────────────────────
-- All gated on the capability: without it nothing goes out.
local function sendRun(cmd)
    if not TB.HasRunCapability() then return false end
    cmd = TB.Trim(cmd or "")
    if cmd == "" then return false end
    return sent(cmd, TB.SendBotCommand(cmd))
end

-- Binds the targeted bot plus up to four grouped owned bots as its party.
-- "inparty": you stay in the party (it needs you to lead it) and the lead
-- bot takes the lead from you while the binding stands.
function TB.SendRunBind()
    local lead
    if TB.GetTargetScope then
        local _, bot = TB.GetTargetScope()
        lead = bot
    end
    if not lead then
        if TB.SetStatus then
            TB.SetStatus("Target a bot first: it leads the bound party.", "warn")
        end
        setFeedback("|cffff5050Bind:|r target your tank bot first; it leads the party.", "err")
        return false
    end
    local names = { lead }
    local grouped = TB.GetGroupedBotNames and TB.GetGroupedBotNames() or {}
    for _, name in ipairs(grouped) do
        if table.getn(names) >= 5 then break end
        if name ~= lead then table.insert(names, name) end
    end
    return sendRun("commander bind " .. table.concat(names, " ") .. " inparty")
end

function TB.SendRunUnbind()
    return sendRun("commander unbind")
end

function TB.SendRunCommanderStatus()
    return sendRun("commander status")
end

-- The party walks through the nearest dungeon entrance (the server picks
-- the trigger within ReactDistance).
function TB.SendRunEnter()
    return sendRun("cmd enter near")
end

function TB.SendRunList()
    if not TB.HasRunCapability() then return false end
    plansPending = true
    if TB.RefreshRunWindow then TB.RefreshRunWindow() end
    return sent("run list", TB.SendBotCommand("run list"))
end

function TB.SendRunStart(plan, fromKind, fromValue)
    if not TB.HasRunCapability() then return false end
    plan = TB.Trim(plan or "")
    local cmd = "run start"
    if plan ~= "" and plan ~= "-" then cmd = cmd .. " " .. plan end
    fromKind = TB.Trim(fromKind or "")
    fromValue = TB.Trim(fromValue or "")
    if (fromKind == "leg" or fromKind == "step") and fromValue ~= "" then
        cmd = cmd .. " from " .. fromKind .. " " .. fromValue
    end
    if TB.GetRunMode() == "player" then
        cmd = cmd .. " player"
        -- A targeted bot is the run's puller; else the server takes the
        -- party's first tank bot (a player tank needs one named).
        if TB.GetTargetScope then
            local _, bot = TB.GetTargetScope()
            if bot then cmd = cmd .. " tank " .. bot end
        end
    end
    return sent(cmd, TB.SendBotCommand(cmd))
end

function TB.SendRunPause()
    return sendRun("run pause")
end

function TB.SendRunResume()
    return sendRun("run resume")
end

function TB.SendRunSkip()
    return sendRun("run skip")
end

function TB.SendRunStop(reason)
    if not TB.HasRunCapability() then return false end
    reason = TB.Trim(reason or "")
    -- The server keeps 80 printable characters (RunStopNote).
    reason = string.gsub(reason, "[%c|]", "")
    if string.len(reason) > 80 then reason = string.sub(reason, 1, 80) end
    reason = TB.Trim(reason)
    if reason == "" then return sent("run stop", TB.SendBotCommand("run stop")) end
    return sent("run stop", TB.SendBotCommand("run stop " .. reason))
end

function TB.SendRunStatus()
    return sendRun("run status")
end

-- The combat/move warn: any player order pauses a running run, so a click
-- on a gameplay action while a run is running says so on the status line.
-- Returns true when a running run was warned about.
function TB.WarnRunPause()
    if run and run.state == "running" and TB.GetRunMode() ~= "player" then
        if TB.SetStatus then
            TB.SetStatus("That order pauses the dungeon run (Resume to go on).", "warn")
        end
        return true
    end
    return false
end

-- ── window ────────────────────────────────────────────────────────────────
local win
local selectedPlan = nil
local planPage = 1
local planSearch = ""
local planZone = nil
-- The search list is open (Change) or closed (the zone's plan only).
local planPicker = false
local stopReason = ""
-- "bot": a bot tank leads, you stay in the party; "player": you lead.
local runMode = "bot"

function TB.GetRunMode()
    return runMode
end

function TB.SetRunMode(mode)
    runMode = (mode == "player") and "player" or "bot"
    if TB.RefreshRunWindow then TB.RefreshRunWindow() end
end

function TB.GetRunWindowOpen()
    return win and win:IsVisible() or false
end

function TB.GetRunSelectedPlan()
    return selectedPlan
end

function TB.SetRunSelectedPlan(name)
    selectedPlan = (name and name ~= "") and name or nil
    if TB.RefreshRunWindow then TB.RefreshRunWindow() end
end

function TB.SetRunStopReason(text)
    stopReason = text or ""
end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function smallButton(parent, label, width, x, y, tipTitle, tip, onClick)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    setTooltip(b, tipTitle, { tip })
    return b
end

local function lampColor(state)
    if state == "running" then return 0.30, 0.90, 0.45 end
    if state == "paused" then return 1.00, 0.82, 0.10 end
    if state == "done" then return 0.62, 0.60, 0.56 end
    return 0.45, 0.45, 0.45
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerRunWindow", TB.frame or UIParent)
    win:SetWidth(RW); win:SetHeight(500)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function() win:StartMoving() end)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        -- 1.12-safe: StopMovingOrSizing detaches the anchor from the
        -- logical parent (see UI.lua drag header), so re-anchor with
        -- GetLeft/GetTop instead of ever calling GetPoint() after a drag.
        local left, top = win:GetLeft(), win:GetTop()
        if left and top then
            win:ClearAllPoints()
            win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerRunWindow") end
    TB.ApplyBackdrop(win, 0.98, 1.0)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -10)
    title:SetWidth(RW - 50); title:SetJustifyH("LEFT")
    title:SetText("Dungeon run  |cff9d9d9dPreview|r")
    TB.SetTextColor(title, color("gold"))

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseRunWindow() end)

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -36)
    head:SetWidth(RW - 24); head:SetJustifyH("LEFT")
    head:SetText("Your bots clear a dungeon plan by themselves.")
    TB.SetTextColor(head, color("muted"))

    -- Mode: who leads the run (tooltips say which role each one suits).
    local mode = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mode:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -56)
    mode:SetText("MODE")
    TB.SetTextColor(mode, color("gold"))
    win.modeBot = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    -- A segmented switch: the two halves touch, the picked one is filled.
    win.modeBot:SetWidth(139); win.modeBot:SetHeight(24)
    win.modeBot:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -73)
    win.modeBot:SetScript("OnClick", function() TB.SetRunMode("bot") end)
    setTooltip(win.modeBot, "Bots lead", {
        "Suggested when you play healer or DPS.",
        "A bot tank leads the way and pulls; you stay in the party and follow.",
        "Bind first (target the tank bot), then Start.",
        "Your own orders to the bots pause the run until Resume.",
    })
    win.modeYou = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.modeYou:SetWidth(139); win.modeYou:SetHeight(24)
    win.modeYou:SetPoint("TOPLEFT", win, "TOPLEFT", 149, -73)
    win.modeYou:SetScript("OnClick", function() TB.SetRunMode("player") end)
    setTooltip(win.modeYou, "I lead", {
        "Suggested when you play the tank.",
        "You walk where you like; the bots pull the plan's packs near you,",
        "mark, crowd-control, rest and revive. Your orders never pause it.",
        "No Bind needed: Start binds your party. Target a bot to make it",
        "the puller (needed when no bot in your party is a tank).",
    })
    win.modeHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.modeHint:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -100)
    win.modeHint:SetWidth(RW - 24); win.modeHint:SetJustifyH("LEFT")
    TB.SetTextColor(win.modeHint, color("muted"))

    -- Party: bind a lead bot + its group, enter the dungeon, status.
    local party = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    party:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -122)
    party:SetText("PARTY")
    TB.SetTextColor(party, color("gold"))
    win.bind = smallButton(win, "Bind", 88, 12, -140,
        "Bind", "Bind your target as the lead bot, with its group beside it.",
        function() TB.SendRunBind() end)
    win.unbind = smallButton(win, "Unbind", 88, 104, -140,
        "Unbind", "Release the bound party (this ends a run).",
        function() TB.SendRunUnbind() end)
    win.enter = smallButton(win, "Enter", 88, 196, -140,
        "Enter", "The party walks through the nearest dungeon entrance.",
        function() TB.SendRunEnter() end)
    win.cmdStatus = smallButton(win, "Status", 88, 12, -166,
        "Party status", "Ask who the bound party is.",
        function() TB.SendRunCommanderStatus() end)
    win.bindHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.bindHint:SetPoint("TOPLEFT", win, "TOPLEFT", 104, -170)
    win.bindHint:SetWidth(RW - 116); win.bindHint:SetJustifyH("LEFT")
    win.bindHint:SetText("Target the lead bot, then Bind.")
    TB.SetTextColor(win.bindHint, color("muted"))

    -- Plan: the dungeon the player stands in picks its plan (or lists its
    -- wings); Change opens a search over every plan. Start takes the pick.
    local plan = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plan:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -198)
    plan:SetText("PLAN")
    TB.SetTextColor(plan, color("gold"))
    win.planPick = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.planPick:SetPoint("TOPLEFT", win, "TOPLEFT", 52, -197)
    win.planPick:SetWidth(156); win.planPick:SetJustifyH("LEFT")
    win.planToggle = smallButton(win, "Change", 76, 212, -192,
        "Change plan", "Search every plan and pick another one.",
        function() TB.SetRunPlanPicker(not planPicker) end)
    win.planHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planHint:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -218)
    win.planHint:SetWidth(RW - 24); win.planHint:SetJustifyH("LEFT")
    TB.SetTextColor(win.planHint, color("muted"))
    win.planSearch = CreateFrame("EditBox", "TortoiseBotsManagerRunPlanSearch", win, "InputBoxTemplate")
    win.planSearch:SetWidth(RW - 34); win.planSearch:SetHeight(20)
    win.planSearch:SetPoint("TOPLEFT", win, "TOPLEFT", 18, -234)
    win.planSearch:SetAutoFocus(false)
    win.planSearch:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    win.planSearch:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    win.planSearch:SetScript("OnTextChanged", function()
        planSearch = this:GetText() or ""
        planPage = 1
        TB.RefreshRunWindow()
    end)
    setTooltip(win.planSearch, "Search plans", { "Type part of a dungeon name, e.g. scarlet or kraul." })
    win.planRows = {}
    for i = 1, PROW do
        local row = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
        row:SetWidth(RW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -260 - (i - 1) * 22)
        row:SetScript("OnClick", function()
            if this.planName then
                planPicker = false
                TB.SetRunSelectedPlan(this.planName)
            end
        end)
        table.insert(win.planRows, row)
    end
    win.planEmpty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planEmpty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -284)
    win.planEmpty:SetWidth(RW - 24); win.planEmpty:SetJustifyH("CENTER")
    TB.SetTextColor(win.planEmpty, color("muted"))
    win.plans = smallButton(win, "Reload", 88, 12, -262 - PROW * 22,
        "Reload plans", "Load the dungeon plans from the server again.",
        function() TB.SendRunList() end)
    win.planPrev = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.planPrev:SetWidth(26); win.planPrev:SetHeight(22)
    win.planPrev:SetPoint("TOPLEFT", win, "TOPLEFT", 104, -262 - PROW * 22)
    win.planPrev:SetText("<")
    win.planPrev:SetScript("OnClick", function() planPage = planPage - 1; TB.RefreshRunWindow() end)
    win.planNext = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.planNext:SetWidth(26); win.planNext:SetHeight(22)
    win.planNext:SetPoint("TOPLEFT", win, "TOPLEFT", 212, -262 - PROW * 22)
    win.planNext:SetText(">")
    win.planNext:SetScript("OnClick", function() planPage = planPage + 1; TB.RefreshRunWindow() end)
    win.planPageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planPageText:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -266 - PROW * 22)
    win.planPageText:SetWidth(78); win.planPageText:SetJustifyH("CENTER")
    TB.SetTextColor(win.planPageText, color("muted"))
    win:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    win:SetScript("OnEvent", function() TB.RefreshRunWindow() end)

    -- Controls: Start / Pause-Resume / Skip / Stop + reason.
    -- Everything below the plan hangs off win.lower, which the plan section
    -- moves down when it opens its list (layoutPlanSection).
    win.lower = CreateFrame("Frame", nil, win)
    win.lower:SetWidth(RW); win.lower:SetHeight(1)
    win.lower:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, -240)
    local lower = win.lower
    local ctlY = 0
    local ctl = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ctl:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, ctlY)
    ctl:SetText("CONTROLS")
    TB.SetTextColor(ctl, color("gold"))
    win.start = smallButton(lower, "Start", 88, 12, ctlY - 18,
        "Start", "Start the picked plan (or the plan of the lead bot's map).",
        function() TB.SendRunStart(selectedPlan) end)
    win.pause = smallButton(lower, "Pause", 88, 104, ctlY - 18,
        "Pause", "Pause the run; the bots hold what they do.",
        function() TB.SendRunPause() end)
    win.resume = smallButton(lower, "Resume", 88, 104, ctlY - 18,
        "Resume", "Go on with the paused run (regroups first).",
        function() TB.SendRunResume() end)
    win.skip = smallButton(lower, "Skip", 88, 196, ctlY - 18,
        "Skip", "Leave out the current step and go on.",
        function() TB.SendRunSkip() end)
    win.stop = smallButton(lower, "Stop", 88, 12, ctlY - 44,
        "Stop", "End the run; the bots stay where they are, still bound.",
        function() TB.SendRunStop(stopReason) end)
    win.stopBox = CreateFrame("EditBox", "TortoiseBotsManagerRunStopBox", win, "InputBoxTemplate")
    win.stopBox:SetWidth(168); win.stopBox:SetHeight(20)
    win.stopBox:SetPoint("TOPLEFT", lower, "TOPLEFT", 108, ctlY - 44)
    win.stopBox:SetAutoFocus(false)
    win.stopBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    win.stopBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    win.stopBox:SetScript("OnTextChanged", function()
        stopReason = this:GetText() or ""
    end)
    setTooltip(win.stopBox, "Stop reason", { "Optional: why the run ends (shown in the note)." })
    -- What the last click did: sent, then the server's answer.
    win.feedback = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.feedback:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, ctlY - 70)
    win.feedback:SetWidth(RW - 24); win.feedback:SetJustifyH("LEFT")
    win.feedback:SetText("")

    -- Status: plan, state lamp, step x/y progress, leg, phase, note.
    local stY = ctlY - 102
    local st = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    st:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY)
    st:SetText("STATUS")
    TB.SetTextColor(st, color("gold"))
    win.runLamp = win:CreateTexture(nil, "OVERLAY")
    win.runLamp:SetWidth(8); win.runLamp:SetHeight(8)
    win.runLamp:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 22)
    win.runState = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runState:SetPoint("LEFT", win.runLamp, "RIGHT", 4, 0)
    win.runState:SetWidth(112); win.runState:SetJustifyH("LEFT")
    win.runStep = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runStep:SetPoint("TOPLEFT", lower, "TOPLEFT", 140, stY - 21)
    win.runStep:SetWidth(RW - 152); win.runStep:SetJustifyH("RIGHT")
    win.runBar = CreateFrame("Frame", nil, win)
    win.runBar:SetWidth(RW - 24); win.runBar:SetHeight(10)
    win.runBar:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 38)
    -- A 10px bar is thinner than the 11px tooltip border edgeSize, so a
    -- plain dark backing replaces the tooltip backdrop here.
    local barBg = win.runBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(win.runBar)
    win.runFill = win.runBar:CreateTexture(nil, "ARTWORK")
    win.runFill:SetHeight(6)
    win.runLeg = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runLeg:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 52)
    win.runLeg:SetWidth(RW - 24); win.runLeg:SetJustifyH("LEFT")
    win.runPhase = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runPhase:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 66)
    win.runPhase:SetWidth(RW - 24); win.runPhase:SetJustifyH("LEFT")
    win.runNote = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runNote:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 80)
    win.runNote:SetWidth(RW - 24); win.runNote:SetJustifyH("LEFT")
    TB.SetTextColor(win.runNote, color("muted"))
    win.warn = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.warn:SetPoint("TOPLEFT", lower, "TOPLEFT", 12, stY - 108)
    win.warn:SetWidth(RW - 24); win.warn:SetJustifyH("LEFT")
    win.warn:SetText("Your orders pause the run until Resume.")
    TB.SetTextColor(win.warn, color("muted"))

    win:Hide()
    TB.runWindow = win
end

-- Plan names are lower_snake ("scarlet_library"); the client's zone text is
-- "Scarlet Monastery". Both compare as lower-case letters and digits with a
-- leading "the" dropped; a zone whose name differs from its plans' names
-- maps to their common prefix here.
local ZONE_PLAN_PREFIX = {
    stockade = "stormwindstockade",
    templeofatalhakkar = "sunkentemple",
    blackrockspire = "lowerblackrockspire",
    scarletmonastery = "scarlet",
}
local PLAN_TITLE = { zulfarrak = "Zul'Farrak" }

local function planKey(text)
    local key = string.lower(text or "")
    key = string.gsub(key, "^the[%s_]+", "")
    return (string.gsub(key, "[^%l%d]", ""))
end

function TB.RunPlanTitle(name)
    if PLAN_TITLE[name] then return PLAN_TITLE[name] end
    local title = string.gsub(name or "", "_", " ")
    return (string.gsub(title, "(%a)(%w*)", function(a, b) return string.upper(a) .. b end))
end

-- The plans of the zone the player stands in (a dungeon with one plan per
-- wing gives several), in the server's order.
function TB.GetZoneRunPlans()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local key = planKey(zone)
    if key == "" then return {}, zone end
    local prefix = ZONE_PLAN_PREFIX[key] or key
    local out = {}
    for _, plan in ipairs(plans) do
        if string.sub(planKey(plan.name), 1, string.len(prefix)) == prefix then table.insert(out, plan) end
    end
    return out, zone
end

-- What the list shows: the search's matches, else the zone's plans first.
local function visiblePlans()
    local here, zone = TB.GetZoneRunPlans()
    local query = planKey(planSearch)
    local out = {}
    if query ~= "" then
        for _, plan in ipairs(plans) do
            if string.find(planKey(plan.name), query, 1, true) then table.insert(out, plan) end
        end
        return out, here, zone
    end
    local seen = {}
    for _, plan in ipairs(here) do table.insert(out, plan); seen[plan.name] = true end
    for _, plan in ipairs(plans) do
        if not seen[plan.name] then table.insert(out, plan) end
    end
    return out, here, zone
end

-- Height of everything hung off win.lower (controls, answer, status).
local LOWER_H = 236

local function placeRows(top, count)
    for i, row in ipairs(win.planRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 12, top - (i - 1) * 22)
        if i > count then
            row.planName = nil
            row:Hide()
        end
    end
end

local function fillRow(row, plan)
    row.planName = plan.name
    -- One line per row: name + steps (+ unsupported tail). The map
    -- lives in the tooltip: even the longest plan name must fit.
    local text = TB.RunPlanTitle(plan.name) .. " · " .. tostring(plan.steps or 0) .. " steps"
    if (plan.unsupported or 0) > 0 then
        text = text .. " · " .. plan.unsupported .. " unsupported"
    end
    if plan.name == selectedPlan then text = "|cffffd200" .. text .. "|r" end
    row:SetText(text)
    setTooltip(row, TB.RunPlanTitle(plan.name), {
        plan.name .. " · map " .. tostring(plan.map or "?") .. " · " .. tostring(plan.steps or 0) .. " steps.",
        "Click: pick this plan for Start.",
    })
    row:Show()
    row:Enable()
end

local function findPlan(name)
    for _, plan in ipairs(plans) do
        if plan.name == name then return plan end
    end
    return nil
end

local function renderPlans()
    local shown, here, zone = visiblePlans()
    -- On entering a zone with plans: its one plan is picked, or a pick from
    -- elsewhere is dropped so Start never runs another dungeon's plan.
    if zone ~= planZone and table.getn(here) > 0 then
        local keep = false
        for _, plan in ipairs(here) do
            if plan.name == selectedPlan then keep = true end
        end
        if not keep then selectedPlan = table.getn(here) == 1 and here[1].name or nil end
    end
    if table.getn(plans) > 0 then planZone = zone end

    local nHere = table.getn(here)
    local picked = selectedPlan and findPlan(selectedPlan)
    win.planPick:SetText(picked and (TB.RunPlanTitle(picked.name) .. " · " .. tostring(picked.steps or 0) .. " steps")
        or "|cff9d9d9dnone|r")
    win.planToggle:SetText(planPicker and "Done" or "Change")
    local listTop, bottom
    if planPicker then
        win.planSearch:Show()
        listTop = -260
        local count = table.getn(shown)
        local pages = math.max(1, math.ceil(count / PROW))
        if planPage > pages then planPage = pages end
        if planPage < 1 then planPage = 1 end
        placeRows(listTop, PROW)
        for i, row in ipairs(win.planRows) do
            local plan = shown[(planPage - 1) * PROW + i]
            if plan then fillRow(row, plan) else row.planName = nil; row:SetText(""); row:Hide() end
        end
        win.planPageText:SetText(planPage .. " / " .. pages)
        win.planPageText:Show(); win.planPrev:Show(); win.planNext:Show(); win.plans:Show()
        if planPage > 1 then win.planPrev:Enable() else win.planPrev:Disable() end
        if planPage < pages then win.planNext:Enable() else win.planNext:Disable() end
        if plansPending then
            win.plans:SetText("Asking…")
            win.plans:Disable()
        else
            win.plans:SetText("Reload")
            win.plans:Enable()
        end
        if table.getn(plans) == 0 then
            win.planEmpty:SetText("No plans yet: Reload asks the server.")
            win.planEmpty:Show()
        elseif count == 0 then
            win.planEmpty:SetText("No plan matches the search.")
            win.planEmpty:Show()
        else
            win.planEmpty:Hide()
        end
        if planKey(planSearch) ~= "" then
            win.planHint:SetText(count .. " of " .. table.getn(plans) .. " plans match.")
        else
            win.planHint:SetText("Type part of a name, then click a plan.")
        end
        bottom = listTop - PROW * 22 - 26
    else
        win.planSearch:Hide()
        win.planPageText:Hide(); win.planPrev:Hide(); win.planNext:Hide(); win.plans:Hide()
        win.planEmpty:Hide()
        listTop = -234
        -- A dungeon with wings lists just its plans to pick from.
        local wings = nHere > 1 and nHere or 0
        if wings > PROW then wings = PROW end
        placeRows(listTop, wings)
        for i = 1, wings do fillRow(win.planRows[i], here[i]) end
        if table.getn(plans) == 0 then
            win.planHint:SetText(plansPending and "Loading the plans..." or "No plans loaded: Change, then Reload.")
        elseif nHere == 1 then
            win.planHint:SetText("|cff40ff40In " .. zone .. ".|r Wrong plan? Change.")
        elseif nHere > 1 then
            win.planHint:SetText("|cff40ff40In " .. zone .. ":|r pick a wing.")
        elseif picked then
            win.planHint:SetText("Picked from the list. Change to pick another.")
        else
            win.planHint:SetText("No dungeon here: Start uses the lead bot's dungeon.")
        end
        bottom = wings > 0 and (listTop - wings * 22 - 4) or -230
    end
    win.lower:ClearAllPoints()
    win.lower:SetPoint("TOPLEFT", win, "TOPLEFT", 0, bottom - 10)
    win:SetHeight(-(bottom - 10) + LOWER_H)
end

function TB.SetRunPlanPicker(open)
    planPicker = open and true or false
    if TB.RefreshRunWindow then TB.RefreshRunWindow() end
end

-- ── Dungeon tab (main window): what the modes are, the run at a glance and
-- the way into the run window, which is too tall for the tab itself.
local tab

function TB.CreateRunTab(parent)
    tab = CreateFrame("Frame", nil, parent)
    tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local tw = (C.PANEL_W or 500) - (C.PAD or 10) * 2
    tab:SetWidth(tw); tab:SetHeight(325)
    local w = tw - 12
    local function line(font, y, text, col)
        local fs = tab:CreateFontString(nil, "OVERLAY", font)
        fs:SetPoint("TOPLEFT", tab, "TOPLEFT", 6, y)
        fs:SetWidth(w); fs:SetJustifyH("LEFT")
        fs:SetText(text or "")
        if col then TB.SetTextColor(fs, color(col)) end
        return fs
    end
    line("GameFontNormal", -6, "Dungeon run", "gold")
    line("GameFontHighlightSmall", -26, "Your bots clear a whole dungeon by its plan: pulls, crowd control, boss tactics, rests and revives.", "muted")
    line("GameFontNormalSmall", -62, "BOTS LEAD", "gold")
    line("GameFontHighlightSmall", -78, "A bot tank leads and pulls; you stay in the party. Best when you heal or deal damage.")
    line("GameFontNormalSmall", -106, "I LEAD", "gold")
    line("GameFontHighlightSmall", -122, "You walk where you like; the bots pull the packs near you. Best when you tank.")
    line("GameFontNormalSmall", -158, "RUN", "gold")
    tab.state = line("GameFontHighlightSmall", -174, "No run.")
    tab.note = line("GameFontHighlightSmall", -190, "", "muted")
    tab.open = TB.StyleButton(CreateFrame("Button", nil, tab, "UIPanelButtonTemplate"))
    tab.open:SetWidth(160); tab.open:SetHeight(22)
    tab.open:SetPoint("TOPLEFT", tab, "TOPLEFT", 6, -222)
    tab.open:SetText("Open run window")
    tab.open:SetScript("OnClick", function() TB.OpenRunWindow() end)
    tab:Hide()
    return tab
end

function TB.RefreshRunTab()
    if not tab then return end
    local st = run
    if not st or st.state == "none" then
        tab.state:SetText("No run.")
        tab.note:SetText("Pick a mode and a plan in the run window, then Start.")
        return
    end
    tab.state:SetText(TB.RunPlanTitle(st.plan) .. " · " .. string.gsub(st.state or "", "^%l", string.upper)
        .. " · step " .. tostring(st.step or 0) .. " of " .. tostring(st.steps or 0))
    tab.note:SetText(st.note or "")
end

function TB.RefreshRunWindow()
    TB.RefreshRunTab()
    if not win or not win:IsVisible() then return end
    renderPlans()
    local st = run or { state = "none", plan = "-", step = 0, steps = 0,
        leg = "-", kind = "-", phase = "-", note = "no run" }
    local r, g, b = lampColor(st.state)
    win.runLamp:SetTexture(r, g, b, 1)
    local stateWord = st.state == "none" and "No run"
        or string.gsub(st.state or "none", "^%l", string.upper)
    win.runState:SetText((st.plan or "-") .. " · " .. stateWord)
    if (st.steps or 0) > 0 then
        win.runStep:SetText("Step " .. tostring(st.step or 0) .. " of " .. tostring(st.steps))
        local frac = (st.step or 0) / st.steps
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
        win.runFill:SetWidth(math.floor((RW - 28) * frac + 0.5))
        win.runFill:SetPoint("LEFT", win.runBar, "LEFT", 2, 0)
        win.runFill:SetTexture(r, g, b, 1)
        win.runFill:Show()
    else
        win.runStep:SetText("-")
        win.runFill:Hide()
    end
    win.runLeg:SetText("Leg: " .. (st.leg or "-") .. "   Step: " .. (st.kind or "-"))
    local phase = "Phase: " .. (st.phase or "-")
    if st.left then phase = phase .. "   Left: " .. tostring(st.left) end
    if st.speed then phase = phase .. "   Speed: " .. tostring(st.speed) end
    win.runPhase:SetText(phase)
    win.runNote:SetText(st.note or "-")
    -- Controls follow the state: Start only with no run, Pause only while
    -- running, Resume/Skip only with a live run, Stop while one goes.
    local live = st.state == "running" or st.state == "paused"
    local running = st.state == "running"
    if live then win.start:Disable() else win.start:Enable() end
    if running then
        win.pause:Show()
        win.resume:Hide()
        win.pause:Enable()
    else
        win.pause:Hide()
        win.resume:Show()
        if st.state == "paused" then win.resume:Enable() else win.resume:Disable() end
    end
    if live then win.skip:Enable() else win.skip:Disable() end
    win.feedback:SetText(feedback and feedback.text or "|cff9d9d9dClick a button: the server's answer shows here.|r")
    local playerLed = runMode == "player"
    -- Switch look: the picked mode is framed and lit, the other one dimmed.
    win.modeBot:SetText(playerLed and "|cff8a8a8aBots lead|r" or "|cffffffffBots lead|r")
    win.modeYou:SetText(playerLed and "|cffffffffI lead|r" or "|cff8a8a8aI lead|r")
    TB.SetButtonActive(win.modeBot, not playerLed)
    TB.SetButtonActive(win.modeYou, playerLed)
    if live then win.modeBot:Disable(); win.modeYou:Disable()
    else win.modeBot:Enable(); win.modeYou:Enable() end
    if playerLed then
        win.modeHint:SetText("You lead; bots pull near you. Best for tanks.")
        win.bindHint:SetText("Start binds your party. Target = puller.")
        win.bind:Disable()
        win.warn:SetText("Your orders never pause the run.")
    else
        win.modeHint:SetText("A bot tank leads. Best for healers and DPS.")
        win.bindHint:SetText("Target the lead bot, then Bind.")
        win.bind:Enable()
        win.warn:SetText("Your orders pause the run until Resume.")
    end
    if live then win.stop:Enable() else win.stop:Disable() end
end

function TB.OpenRunWindow()
    if not TB.HasRunCapability() then return false end
    if not win then createWindow() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.SetMode then TB.SetMode("full") end
    win:ClearAllPoints()
    local anchor = (TB.botPanel and TB.botPanel.IsVisible and TB.botPanel:IsVisible()) and TB.botPanel or TB.frame
    if anchor and anchor ~= TB.frame then
        local aRight = anchor.GetRight and anchor:GetRight()
        local fLeft = TB.frame and TB.frame.GetLeft and TB.frame:GetLeft()
        local aLeft = anchor.GetLeft and anchor:GetLeft()
        if aRight and fLeft and aRight <= fLeft then
            -- The panel sits LEFT of main: anchor right of the panel would
            -- land on main, so dock left of the panel (or right of main
            -- when the panel hugs the left screen edge).
            if aLeft and aLeft - RW - 4 >= 0 then
                win:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
            elseif TB.frame then
                win:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
            else
                win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        else
            local right = anchor.GetRight and anchor:GetRight()
            local screen = GetScreenWidth and GetScreenWidth()
            local scale = (anchor.GetScale and anchor:GetScale()) or 1
            if right and screen and (right + RW + 4) * scale > screen then
                -- The panel sits right of main: anchoring left of the panel
                -- would land on top of main, so dock left of main instead.
                win:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
            else
                win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        end
    elseif TB.frame then
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + RW + 4) * scale > screen then
            win:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            win:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RefreshRunWindow()
    TB.SendRunList()
    TB.SendRunStatus()
    return true
end

function TB.CloseRunWindow()
    plansPending = false
    if win then win:Hide() end
end

-- The capability can disappear mid-session (a restart with the feature
-- off): close the window and drop the model so no stale state lingers.
function TB.NoteRunCaps()
    if TB.UpdateRaidTab then TB.UpdateRaidTab() end
    if TB.HasRunCapability() then
        if TB.RefreshRunWindow then TB.RefreshRunWindow() end
        return
    end
    run = nil
    plans = {}
    plansPending = false
    selectedPlan = nil
    if win and win:IsVisible() then win:Hide() end
end
