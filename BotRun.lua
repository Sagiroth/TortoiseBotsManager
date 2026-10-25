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
--   "commander bind <LeadBot> [<Bot> ...]" (a party of up to five bots)
--   "commander unbind" / "commander status"
--   "cmd enter near" (nearest entrance trigger within ReactDistance)
--   "run list" -> "Dungeon plans: <name> (map <m>, <s> steps[, <u> not
--     supported yet])[, ...]" + TBM:ACTION_ACK|run list|plans|<n>|-
--   "run start [plan] [from leg|step N]" / pause / resume / skip /
--     "stop [reason]" / status
-- Inbound:
--   TBM:RUN|<plan>|<state>|<step>/<steps>|<leg>|<kind>|<phase>|<note>
--     [|left <K>][|speed <x> (test)]
--   The first 8 fields always exist; later fields are optional extras.
--   "no run" is TBM:RUN|-|none|0/0|-|-|-|no run.
--   TBM:ACTION_ACK/ERR for the commander / cmd / run intents (generic
--   routing in Comms.lua; labels live in C.ACTION_LABELS).
--
-- Any player order to the party (.bot action, .bot cmd, whispers) pauses a
-- running run until resume: the window says so, and SendActionIntent warns
-- on the status line when a run is running.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local RW = 300
local RWINDOW = 456
local PROW = 3

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

-- ACK/ERR routing for the run intents (called from ParseActionMessage):
-- "run status" with no run answers "no run" plus this ACK, so clear the
-- model; every other ACK/ERR keeps the generic status text.
function TB.OnRunAck(packet)
    if not packet then return false end
    local intent = packet.intent or ""
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
    return TB.SendBotCommand(cmd)
end

-- Binds the targeted bot plus up to four grouped owned bots as its party:
-- the commander leaves its own party on bind, so the lead plus the bots
-- beside it are the party to be.
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
        return false
    end
    local names = { lead }
    local grouped = TB.GetGroupedBotNames and TB.GetGroupedBotNames() or {}
    for _, name in ipairs(grouped) do
        if table.getn(names) >= 5 then break end
        if name ~= lead then table.insert(names, name) end
    end
    return sendRun("commander bind " .. table.concat(names, " "))
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
    return TB.SendBotCommand("run list")
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
    return TB.SendBotCommand(cmd)
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
    if reason == "" then return TB.SendBotCommand("run stop") end
    return TB.SendBotCommand("run stop " .. reason)
end

function TB.SendRunStatus()
    return sendRun("run status")
end

-- The combat/move warn: any player order pauses a running run, so a click
-- on a gameplay action while a run is running says so on the status line.
-- Returns true when a running run was warned about.
function TB.WarnRunPause()
    if run and run.state == "running" then
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
local stopReason = ""

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
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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
    win:SetWidth(RW); win:SetHeight(RWINDOW)
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

    -- Party: bind a lead bot + its group, enter the dungeon, status.
    local party = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    party:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -56)
    party:SetText("PARTY")
    TB.SetTextColor(party, color("gold"))
    win.bind = smallButton(win, "Bind", 88, 12, -74,
        "Bind", "Bind your target as the lead bot, with its group beside it.",
        function() TB.SendRunBind() end)
    win.unbind = smallButton(win, "Unbind", 88, 104, -74,
        "Unbind", "Release the bound party (this ends a run).",
        function() TB.SendRunUnbind() end)
    win.enter = smallButton(win, "Enter", 88, 196, -74,
        "Enter", "The party walks through the nearest dungeon entrance.",
        function() TB.SendRunEnter() end)
    win.cmdStatus = smallButton(win, "Status", 88, 12, -100,
        "Party status", "Ask who the bound party is.",
        function() TB.SendRunCommanderStatus() end)
    win.bindHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.bindHint:SetPoint("TOPLEFT", win, "TOPLEFT", 104, -104)
    win.bindHint:SetWidth(RW - 116); win.bindHint:SetJustifyH("LEFT")
    win.bindHint:SetText("Target the lead bot, then Bind.")
    TB.SetTextColor(win.bindHint, color("muted"))

    -- Plan: paged list from "run list"; Start takes the picked plan.
    local plan = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plan:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -128)
    plan:SetText("PLAN")
    TB.SetTextColor(plan, color("gold"))
    win.planHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planHint:SetPoint("TOPLEFT", win, "TOPLEFT", 140, -128)
    win.planHint:SetWidth(RW - 152); win.planHint:SetJustifyH("RIGHT")
    win.planHint:SetText("Plans come from the server.")
    TB.SetTextColor(win.planHint, color("muted"))
    win.planRows = {}
    for i = 1, PROW do
        local row = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        row:SetWidth(RW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -144 - (i - 1) * 22)
        row:SetScript("OnClick", function()
            if this.planName then TB.SetRunSelectedPlan(this.planName) end
        end)
        table.insert(win.planRows, row)
    end
    win.planEmpty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planEmpty:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -168)
    win.planEmpty:SetWidth(RW - 24); win.planEmpty:SetJustifyH("CENTER")
    win.planEmpty:SetText("Click Plans to load the dungeon list.")
    TB.SetTextColor(win.planEmpty, color("muted"))
    win.plans = smallButton(win, "Plans", 88, 12, -144 - PROW * 22,
        "Plans", "Load the dungeon plans from the server.",
        function() TB.SendRunList() end)
    win.planPrev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.planPrev:SetWidth(26); win.planPrev:SetHeight(22)
    win.planPrev:SetPoint("TOPLEFT", win, "TOPLEFT", 104, -144 - PROW * 22)
    win.planPrev:SetText("<")
    win.planPrev:SetScript("OnClick", function() planPage = planPage - 1; TB.RefreshRunWindow() end)
    win.planNext = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.planNext:SetWidth(26); win.planNext:SetHeight(22)
    win.planNext:SetPoint("TOPLEFT", win, "TOPLEFT", 212, -144 - PROW * 22)
    win.planNext:SetText(">")
    win.planNext:SetScript("OnClick", function() planPage = planPage + 1; TB.RefreshRunWindow() end)
    win.planPageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.planPageText:SetPoint("TOPLEFT", win, "TOPLEFT", 132, -148 - PROW * 22)
    win.planPageText:SetWidth(78); win.planPageText:SetJustifyH("CENTER")
    TB.SetTextColor(win.planPageText, color("muted"))

    -- Controls: Start / Pause-Resume / Skip / Stop + reason.
    local ctlY = -144 - PROW * 22 - 28
    local ctl = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ctl:SetPoint("TOPLEFT", win, "TOPLEFT", 12, ctlY)
    ctl:SetText("CONTROLS")
    TB.SetTextColor(ctl, color("gold"))
    win.start = smallButton(win, "Start", 88, 12, ctlY - 18,
        "Start", "Start the picked plan (or the plan of the lead bot's map).",
        function() TB.SendRunStart(selectedPlan) end)
    win.pause = smallButton(win, "Pause", 88, 104, ctlY - 18,
        "Pause", "Pause the run; the bots hold what they do.",
        function() TB.SendRunPause() end)
    win.resume = smallButton(win, "Resume", 88, 104, ctlY - 18,
        "Resume", "Go on with the paused run (regroups first).",
        function() TB.SendRunResume() end)
    win.skip = smallButton(win, "Skip", 88, 196, ctlY - 18,
        "Skip", "Leave out the current step and go on.",
        function() TB.SendRunSkip() end)
    win.stop = smallButton(win, "Stop", 88, 12, ctlY - 44,
        "Stop", "End the run; the bots stay where they are, still bound.",
        function() TB.SendRunStop(stopReason) end)
    win.stopBox = CreateFrame("EditBox", "TortoiseBotsManagerRunStopBox", win, "InputBoxTemplate")
    win.stopBox:SetWidth(168); win.stopBox:SetHeight(20)
    win.stopBox:SetPoint("TOPLEFT", win, "TOPLEFT", 108, ctlY - 44)
    win.stopBox:SetAutoFocus(false)
    win.stopBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    win.stopBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    win.stopBox:SetScript("OnTextChanged", function()
        stopReason = this:GetText() or ""
    end)
    setTooltip(win.stopBox, "Stop reason", { "Optional: why the run ends (shown in the note)." })
    local stopHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stopHint:SetPoint("TOPLEFT", win, "TOPLEFT", 108, ctlY - 66)
    stopHint:SetWidth(168); stopHint:SetJustifyH("LEFT")
    stopHint:SetText("Stop reason (optional).")
    TB.SetTextColor(stopHint, color("muted"))
    win.stopHint = stopHint

    -- Status: plan, state lamp, step x/y progress, leg, phase, note.
    local stY = ctlY - 88
    local st = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    st:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY)
    st:SetText("STATUS")
    TB.SetTextColor(st, color("gold"))
    win.runLamp = win:CreateTexture(nil, "OVERLAY")
    win.runLamp:SetWidth(8); win.runLamp:SetHeight(8)
    win.runLamp:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 22)
    win.runState = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runState:SetPoint("LEFT", win.runLamp, "RIGHT", 4, 0)
    win.runState:SetWidth(112); win.runState:SetJustifyH("LEFT")
    win.runStep = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runStep:SetPoint("TOPLEFT", win, "TOPLEFT", 140, stY - 21)
    win.runStep:SetWidth(RW - 152); win.runStep:SetJustifyH("RIGHT")
    win.runBar = CreateFrame("Frame", nil, win)
    win.runBar:SetWidth(RW - 24); win.runBar:SetHeight(10)
    win.runBar:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 38)
    -- A 10px bar is thinner than the 11px tooltip border edgeSize, so a
    -- plain dark backing replaces the tooltip backdrop here.
    local barBg = win.runBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(win.runBar)
    win.runFill = win.runBar:CreateTexture(nil, "ARTWORK")
    win.runFill:SetHeight(6)
    win.runLeg = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runLeg:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 52)
    win.runLeg:SetWidth(RW - 24); win.runLeg:SetJustifyH("LEFT")
    win.runPhase = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runPhase:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 66)
    win.runPhase:SetWidth(RW - 24); win.runPhase:SetJustifyH("LEFT")
    win.runNote = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.runNote:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 80)
    win.runNote:SetWidth(RW - 24); win.runNote:SetJustifyH("LEFT")
    TB.SetTextColor(win.runNote, color("muted"))
    win.warn = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.warn:SetPoint("TOPLEFT", win, "TOPLEFT", 12, stY - 108)
    win.warn:SetWidth(RW - 24); win.warn:SetJustifyH("LEFT")
    win.warn:SetText("Any order you give the party pauses the run until Resume.")
    TB.SetTextColor(win.warn, color("muted"))

    win:Hide()
    TB.runWindow = win
end

local function renderPlans()
    local count = table.getn(plans)
    local pages = math.max(1, math.ceil(count / PROW))
    if planPage > pages then planPage = pages end
    if planPage < 1 then planPage = 1 end
    for i, row in ipairs(win.planRows) do
        local plan = plans[(planPage - 1) * PROW + i]
        if plan then
            row.planName = plan.name
            -- One line per row: name + steps (+ unsupported tail). The map
            -- lives in the tooltip: even the longest plan name must fit.
            local text = plan.name .. " · " .. tostring(plan.steps or 0) .. " steps"
            if (plan.unsupported or 0) > 0 then
                text = text .. " · " .. plan.unsupported .. " unsupported"
            end
            if plan.name == selectedPlan then text = "|cffffd200" .. text .. "|r" end
            row:SetText(text)
            setTooltip(row, plan.name, {
                "Map " .. tostring(plan.map or "?") .. " · " .. tostring(plan.steps or 0) .. " steps.",
                "Click: start the run with this plan.",
            })
            row:Show()
            row:Enable()
        else
            row.planName = nil
            row:SetText("")
            row:Hide()
        end
    end
    win.planPageText:SetText(planPage .. " / " .. pages)
    if planPage > 1 then win.planPrev:Enable() else win.planPrev:Disable() end
    if planPage < pages then win.planNext:Enable() else win.planNext:Disable() end
    if plansPending then
        win.plans:SetText("Asking…")
        win.plans:Disable()
    else
        win.plans:SetText("Plans")
        win.plans:Enable()
    end
    if win.planEmpty then
        if count == 0 then win.planEmpty:Show() else win.planEmpty:Hide() end
    end
end

function TB.RefreshRunWindow()
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
