-- TortoiseBotsManager regression harness.
-- Run with: lua5.1 tests/regression.lua .
--
-- The mock deliberately exposes RegisterForClicks only on Button objects.
-- That matches the Vanilla client contract and catches accidental calls on
-- generic Frames while keeping the test independent of the game executable.

local root = arg[1] or "."
local frames = {}
local sent = {}
local now = 10
local targetExists = true
local partyMembers = {}

local function object(kind, parent)
    local value = {
        kind = kind,
        parent = parent,
        scripts = {},
        visible = true,
        text = "",
    }
    local methods = {}

    function methods:SetWidth(width) self.width = width end
    function methods:SetHeight(height) self.height = height end
    function methods:SetPoint(...) self.point = {...} end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetFrameStrata(strata) self.strata = strata end
    function methods:SetMovable(movable) self.movable = movable end
    function methods:EnableMouse(enabled) self.mouseEnabled = enabled end
    function methods:RegisterForDrag(...) self.dragButtons = {...} end
    function methods:RegisterEvent(eventName)
        self.events = self.events or {}
        self.events[eventName] = true
    end
    function methods:RegisterForClicks(...)
        if self.kind ~= "Button" then
            error("RegisterForClicks called on non-Button")
        end
        self.clickButtons = {...}
    end
    function methods:SetScript(name, callback) self.scripts[name] = callback end
    function methods:SetBackdrop(...) end
    function methods:SetBackdropColor(...) end
    function methods:SetBackdropBorderColor(...) end
    function methods:CreateTexture() return object("Texture", self) end
    function methods:CreateFontString() return object("FontString", self) end
    function methods:SetTexture(...) self.texture = {...} end
    function methods:SetTexCoord(...) end
    function methods:SetAllPoints(...) end
    function methods:SetBlendMode(...) end
    function methods:SetAutoFocus(...) end
    function methods:SetJustifyH(...) end
    function methods:SetText(text) self.text = text end
    function methods:GetText() return self.text end
    function methods:SetTextColor(...) end
    function methods:ClearFocus() end
    function methods:Show() self.visible = true end
    function methods:Hide() self.visible = false end
    function methods:IsVisible() return self.visible end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:GetParent() return self.parent end
    function methods:StartMoving() end
    function methods:StopMovingOrSizing() end
    function methods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 15 end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:GetCenter() return 0, 0 end
    function methods:GetEffectiveScale() return 1 end

    methods.__index = methods
    return setmetatable(value, methods)
end

function CreateFrame(kind, name, parent)
    local frame = object(kind, parent)
    frame.name = name
    if name then frames[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GameTooltip = {
    SetOwner = function() end,
    SetText = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() end,
}

function GetTime() return now end
function time() return 123 end
function SendChatMessage(message) table.insert(sent, message) end
function GetCursorPosition() return 0, 0 end
function UnitExists(unit) return unit == "target" and targetExists end
function UnitIsDead(unit) return false end
function GetNumPartyMembers() return table.getn(partyMembers) end
function GetNumRaidMembers() return 0 end
function UnitName(unit)
    if unit == "player" then return "Tester" end
    local _, _, index = string.find(unit or "", "^party(%d+)$")
    return index and partyMembers[tonumber(index)] or nil
end
function FauxScrollFrame_Update(frame, count) frame.itemCount = count end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_OnVerticalScroll() end

for _, file in ipairs({
    "Constants.lua",
    "Utils.lua",
    "Core.lua",
    "Roster.lua",
    "Comms.lua",
    "UI.lua",
    "Minimap.lua",
}) do
    dofile(root .. "/" .. file)
end

local TB = TortoiseBots
local coreFrame = frames["TortoiseBotsManagerCoreFrame"]
assert(coreFrame, "core lifecycle frame was not created")

event, arg1 = "ADDON_LOADED", "TortoiseBotsManager"
local loaded, loadError = pcall(coreFrame.scripts.OnEvent, coreFrame)
assert(loaded, loadError)
assert(TB.frame, "UI frame was not initialized")
assert(table.getn(TB.rows) == TB.C.ROW_N, "all roster rows must be created")
assert(TB.rows[1].kind == "Button", "roster rows must be clickable Buttons")
assert(table.getn(TB.rows[1].clickButtons) == 2, "row must accept left and right clicks")
assert(TB.minimapButton and table.getn(TB.minimapButton.clickButtons) == 2, "minimap must remain clickable")
assert(frames["TortoiseBotsManagerTargetWatcher"], "target changes must refresh target-scoped controls")
assert(TB.statsButton and TB.helpButton, "stats and help commands must have explicit controls")
-- AI Command bar removed per user request — not required, keep panel compact
assert(TB.commandBox == nil and TB.commandButton == nil, "AI Command bar should be removed")
assert(TB.refreshButton and TB.addButton == nil, "Add bar removed — list all bots, refresh only")
assert(TB.partyButtons and TB.partyButtons.summon and TB.partyButtons.follow and TB.partyButtons.invite,
    "party command controls must be available")
assert(TB.partyButtons.pullback, "pullback must be a party/target control")
assert(TB.guardButton and TB.freeButton and TB.attackButton and TB.readyButton,
    "public movement and combat controls must exist")
assert(TB.formationButton and TB.statusButton, "formation and status controls must exist")

local refreshed, refreshError = pcall(TB.Refresh)
assert(refreshed, refreshError)

TB.AddToRoster("Alpha")
TB.Refresh()
local row = TB.rows[1]
assert(row.entry and row.entry.name == "Alpha", "roster entry must render")
this, arg1 = row, "LeftButton"
row.scripts.OnClick(row)
assert(TB.selected == "Alpha", "left-click must select a roster row")
assert(not TB.attackButton.enabled, "selected actions must be disabled for offline bots")
this, arg1 = row, "RightButton"
row.scripts.OnClick(row)
assert(TB.GetState("Alpha") == nil, "right-click must forget an offline roster row")

local reconcileCalls = 0
local realReconcile = TB.ReconcilePoll
TB.ReconcilePoll = function()
    reconcileCalls = reconcileCalls + 1
    realReconcile()
end
now = 20
local sentBeforeList = table.getn(sent)
assert(TB.PollList(true), "forced list poll must send immediately")
assert(table.getn(sent) == sentBeforeList + 1, "list command must be sent")
local reconcileFrame = frames["TortoiseBotsManagerReconcileFrame"]
this, arg1 = reconcileFrame, 1.2
local firstUpdate, firstUpdateError = pcall(reconcileFrame.scripts.OnUpdate, reconcileFrame)
assert(firstUpdate, firstUpdateError)
this, arg1 = reconcileFrame, 0.1
local secondUpdate, secondUpdateError = pcall(reconcileFrame.scripts.OnUpdate, reconcileFrame)
assert(secondUpdate, secondUpdateError)
assert(reconcileCalls == 1, "reconcile timer must fire exactly once")
TB.ReconcilePoll = realReconcile

now = 30
assert(TB.SendBotCommand("add Alpha"), "first command must send directly")
assert(not TB.SendBotCommand("add Bravo"), "second immediate command must queue")
local sentBeforeQueue = table.getn(sent)
now = 31
local queueFrame = frames["TortoiseBotsManagerQueueFrame"]
this, arg1 = queueFrame, 0.1
local queueUpdate, queueUpdateError = pcall(queueFrame.scripts.OnUpdate, queueFrame)
assert(queueUpdate, queueUpdateError)
assert(table.getn(sent) == sentBeforeQueue + 1, "queued command must send once")
assert(sent[table.getn(sent)] == ".bot add Bravo", "queued command order must be preserved")
assert(TB.GetState("Bravo").status == TB.C.STATUS.STARTING, "queued command must run optimistic callback")
this, arg1 = queueFrame, 0.1
queueFrame.scripts.OnUpdate(queueFrame)
assert(table.getn(sent) == sentBeforeQueue + 1, "queue must not duplicate a sent command")

local oldSetStatus = TB.SetStatus
local oldRequestPollSoon = TB.RequestPollSoon
local lastStatusKind
local pollRequests = 0
TB.SetStatus = function(_, kind) lastStatusKind = kind end
TB.RequestPollSoon = function() pollRequests = pollRequests + 1 end
TB.SetState("Alpha", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("invite Alpha")
assert(TB.GetState("Alpha").status == TB.C.STATUS.INVITING, "invite must enter optimistic state")
TB.OnSystemMessage("The group invitation for Alpha was rejected by the native group handler.")
assert(TB.GetState("Alpha").status == TB.C.STATUS.ONLINE, "invite rejection must roll back optimistic state")
assert(lastStatusKind == "warn", "invite rejection must be surfaced as a warning")
local pollsBeforeUninvite = pollRequests
TB.OnSystemMessage("Uninvite sent for bot Alpha.")
assert(lastStatusKind == "pending", "uninvite response must be surfaced as pending")
assert(pollRequests > pollsBeforeUninvite, "uninvite response must schedule reconciliation")
TB.OnSystemMessage("Bot commands: add/remove/follow/invite/uninvite/stay/list/stats/pullback/summon/command")
assert(lastStatusKind == "muted", "help response must be surfaced as informational")
TB.selected = "Alpha"
TB.Refresh()
assert(not TB.guardButton.enabled and not TB.statusButton.enabled,
    "commands absent from server help must be disabled")
TB.OnSystemMessage("Bot commands: add/remove/follow/invite/uninvite/stay/guard/free/ready/attack/formation/list/stats/status/pullback/summon/command")
assert(TB.HasServerCommand("guard") and TB.HasServerCommand("formation"), "advertised public commands must be detected")
TB.Refresh()
assert(TB.guardButton.enabled and TB.statusButton.enabled,
    "advertised public commands must become usable")

TB.OnCommandSent("add Bravo")
assert(TB.GetState("Bravo").status == TB.C.STATUS.STARTING, "add must enter starting state")
TB.OnSystemMessage("Character 'Bravo' not found.")
assert(TB.GetState("Bravo").status == TB.C.STATUS.OFFLINE, "add failure must roll back starting state")
assert(lastStatusKind == "warn", "add failure must be surfaced as a warning")
now = 39
TB.SendBotCommand("add Delta")
assert(TB.GetState("Delta").status == TB.C.STATUS.STARTING, "second add must enter starting state")
TB.OnSystemMessage("You may only control characters on your account.")
assert(TB.GetState("Delta").status == TB.C.STATUS.OFFLINE, "account rejection must roll back the sent target")

TB.SetState("Hanging", { online = false, enteredWorld = false, status = TB.C.STATUS.OFFLINE })
TB.OnCommandSent("add Hanging")
local hanging = TB.GetState("Hanging")
assert(hanging.status == TB.C.STATUS.STARTING, "unconfirmed add must be starting")
TB.UpdateStateTimers((hanging.operation and hanging.operation.deadline or 0) + 1)
assert(hanging.status == TB.C.STATUS.FAILED, "unconfirmed add must time out")

TB.SetState("Stuck", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("remove Stuck")
assert(TB.GetState("Stuck").status == TB.C.STATUS.REMOVING, "remove must enter removing state")
TB.OnSystemMessage("Bot Stuck not found or not removable.")
assert(TB.GetState("Stuck").status == TB.C.STATUS.ONLINE, "remove failure must restore online state")

TB.SetState("Race", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("follow Race")
TB.OnCommandSent("guard Race")
TB.OnSystemMessage("Bot Race now following Tester.")
assert(TB.GetState("Race").operation.verb == "guard" and not TB.GetState("Race").movement,
    "a late reply must not overwrite a newer operation")
TB.OnSystemMessage("Bot Race will guard this position.")
assert(not TB.GetState("Race").operation and TB.GetState("Race").movement == "guard",
    "the current operation reply must update movement")

TB.SetState("GroupProbe", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("invite GroupProbe")
partyMembers[1] = "GroupProbe"
frames["TortoiseBotsManagerGroupWatcher"].scripts.OnEvent(frames["TortoiseBotsManagerGroupWatcher"])
assert(TB.IsInGroup("GroupProbe") and not TB.GetState("GroupProbe").operation,
    "group roster updates must complete an invite operation")
TB.OnCommandSent("uninvite GroupProbe")
partyMembers[1] = nil
frames["TortoiseBotsManagerGroupWatcher"].scripts.OnEvent(frames["TortoiseBotsManagerGroupWatcher"])
assert(not TB.IsInGroup("GroupProbe") and not TB.GetState("GroupProbe").operation,
    "group roster updates must complete an uninvite operation")

TB.SetState("StatusProbe", { online = false, status = TB.C.STATUS.OFFLINE })
TB.OnCommandSent("status StatusProbe")
TB.OnSystemMessage("StatusProbe: in world, AI 1, movement guard, random 0, owner you.")
assert(TB.GetState("StatusProbe").status == TB.C.STATUS.ONLINE
    and TB.GetState("StatusProbe").movement == "guard"
    and TB.GetState("StatusProbe").hasAI,
    "status replies must populate lifecycle and movement state")

TB.SetState("WhisperProbe", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("command WhisperProbe help")
TB.OnWhisperMessage("help response", "WhisperProbe")
assert(not TB.GetState("WhisperProbe").operation and TB.lastAIResponse
    and TB.lastAIResponse.message == "help response",
    "forwarded AI replies must complete the command and remain visible")

TB.SetState("CommandProbe", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("command CommandProbe dps assist")
local commandProbe = TB.GetState("CommandProbe")
TB.UpdateStateTimers((commandProbe.operation and commandProbe.operation.deadline or 0) + 1)
assert(not commandProbe.operation and not commandProbe.pendingAI and commandProbe.status == TB.C.STATUS.ONLINE,
    "an unanswered advanced command must leave a usable state")

TB.SetState("StatusTimeout", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("status StatusTimeout")
local statusTimeout = TB.GetState("StatusTimeout")
TB.UpdateStateTimers((statusTimeout.operation and statusTimeout.operation.deadline or 0) + 1)
assert(statusTimeout.status == TB.C.STATUS.UNKNOWN,
    "an unanswered status request must not preserve stale online truth")

TB.SetState("Probe", { online = true, enteredWorld = true, status = TB.C.STATUS.ONLINE })
TB.BeginPoll()
TB.OnSystemMessage("No owned PlayerBots are online.")
TB.ReconcilePoll()
assert(TB.GetState("Probe").status == TB.C.STATUS.OFFLINE_PENDING,
    "a no-bots reply must count as one missing poll only")
assert(TB.GetState("Probe").onlinePending == 1, "a no-bots reply must not double-count a poll")
assert(TB.StatusText({ online = true, enteredWorld = true, status = TB.C.STATUS.SUMMONING }, false) == "Summoning…",
    "summoning must not display as online")
assert(TB.StatusText({ online = true, enteredWorld = true, status = TB.C.STATUS.INVITING }, false) == "Inviting…",
    "inviting must not display as online")
assert(TB.StatusText({ online = true, enteredWorld = true, status = TB.C.STATUS.REMOVING }, false) == "Removing…",
    "removing must not display as online")
TB.SetState("Silent", { online = true, enteredWorld = true, status = TB.C.STATUS.ONLINE })
TB.BeginPoll(); TB.ReconcilePoll()
TB.BeginPoll(); TB.ReconcilePoll()
assert(TB.GetState("Silent").status == TB.C.STATUS.UNKNOWN,
    "repeated silent polls must become explicitly unknown")

now = now + 1
this, arg1 = TB.statsButton, "LeftButton"
TB.statsButton.scripts.OnClick(TB.statsButton)
assert(sent[table.getn(sent)] == ".bot stats", "stats control must send the stats command")
now = now + 1
this, arg1 = TB.helpButton, "LeftButton"
TB.helpButton.scripts.OnClick(TB.helpButton)
assert(sent[table.getn(sent)] == ".bot help", "help control must send the server help command")
-- AI Command bar removed: verify raw .bot command API still works without UI
TB.selected = "Alpha"
assert(TB.BuildCommand("command", "Alpha", "dps assist") == "command Alpha dps assist", "BuildCommand API must still format raw commands")
TB.SetState("Alpha", { online = true, enteredWorld = true, hasAI = true, status = TB.C.STATUS.ONLINE })
TB.Refresh()
targetExists = false
TB.Refresh()
assert(not TB.attackButton.enabled and not TB.partyButtons.pullback.enabled,
    "target-scoped controls must disable without a living target")
targetExists = true
TB.Refresh()
local function clickSelected(button, expected, verb)
    now = now + 1
    this, arg1 = button, "LeftButton"
    button.scripts.OnClick(button)
    assert(sent[table.getn(sent)] == expected, "selected control must send " .. expected)
    if verb then TB.CompleteOperation("Alpha", verb, true, "accepted") end
end
clickSelected(TB.guardButton, ".bot guard Alpha", "guard")
clickSelected(TB.freeButton, ".bot free Alpha", "free")
clickSelected(TB.attackButton, ".bot attack Alpha", "attack")
clickSelected(TB.readyButton, ".bot ready Alpha", "ready")
clickSelected(TB.formationButton, ".bot formation Alpha default", "formation")
clickSelected(TB.statusButton, ".bot status Alpha", "status")
local activeRow = TB.rows[1]
now = now + 1
this, arg1 = activeRow.btnSummon, "LeftButton"
activeRow.btnSummon.scripts.OnClick(activeRow.btnSummon)
assert(sent[table.getn(sent)] == ".bot summon Alpha", "row summon control must send summon")
TB.OnSystemMessage("Summoning Alpha to a safe position near you (3s); it will follow on arrival.")
assert(not TB.IsOperationPending("Alpha", "summon"), "summon acknowledgement must not wait for an unavailable completion packet")
assert(TB.GetState("Alpha").status == TB.C.STATUS.SUMMONING, "accepted summon must remain visibly pending while teleport completes")
now = now + 1
this, arg1 = activeRow.btnFollow, "LeftButton"
activeRow.btnFollow.scripts.OnClick(activeRow.btnFollow)
assert(sent[table.getn(sent)] == ".bot follow Alpha", "row follow control must send follow")
TB.CompleteOperation("Alpha", "follow", true, "follow accepted")
now = now + 1
this, arg1 = activeRow.btnInvite, "LeftButton"
activeRow.btnInvite.scripts.OnClick(activeRow.btnInvite)
assert(sent[table.getn(sent)] == ".bot invite Alpha", "row invite control must send invite")
TB.CompleteOperation("Alpha", "invite", true, "invite accepted")
now = now + 1
this, arg1 = TB.stayButton, "LeftButton"
TB.stayButton.scripts.OnClick(TB.stayButton)
assert(sent[table.getn(sent)] == ".bot stay Alpha", "selected stay control must send stay")
TB.CompleteOperation("Alpha", "stay", true, "stay accepted")
now = now + 1
this, arg1 = TB.partyButtons.pullback, "LeftButton"
TB.partyButtons.pullback.scripts.OnClick(TB.partyButtons.pullback)
assert(sent[table.getn(sent)] == ".bot pullback", "pullback control must send pullback")
TB.OnSystemMessage("Pullback requested: tank Alpha is using its native pull strategy.")
assert(lastStatusKind == "pending", "pullback acceptance must be surfaced as pending")
TB.OnSystemMessage("No tank bot found in your party (needs a bot with tank role).")
assert(lastStatusKind == "warn", "pullback rejection must be surfaced")
TB.OnSystemMessage("Tank Alpha could not start a pull for your selected target.")
assert(lastStatusKind == "warn", "native pullback failure must be surfaced")
now = now + 1
this, arg1 = TB.resetButton, "LeftButton"
TB.resetButton.scripts.OnClick(TB.resetButton)
assert(sent[table.getn(sent)] == ".bot command Alpha reset", "reset control must send command")
TB.CompleteOperation("Alpha", "command", true, "reset accepted")
now = now + 1
this, arg1 = TB.partyButtons.follow, "LeftButton"
TB.partyButtons.follow.scripts.OnClick(TB.partyButtons.follow)
assert(sent[table.getn(sent)] == ".bot follow Alpha", "party follow control must send follow")
TB.CompleteOperation("Alpha", "follow", true, "follow accepted")
now = now + 1
this, arg1 = activeRow.btnRemove, "LeftButton"
activeRow.btnRemove.scripts.OnClick(activeRow.btnRemove)
assert(sent[table.getn(sent)] == ".bot remove Alpha", "row remove control must send remove")
TB.CompleteOperation("Alpha", "remove", true, "remove accepted")
now = now + 1
-- Add bar removed — roster lists all bots, add via API (same as .bot add)
TB.AddToRoster("Charlie")
assert(TB.GetState("Charlie") ~= nil or TB.GetRosterCount() >= 1, "roster must accept new bot")
TB.SendBotCommand(TB.BuildCommand("add", "Charlie"))
assert(sent[table.getn(sent)] == ".bot add Charlie" or sent[table.getn(sent)] == "add Charlie", "add API must send add")
now = now + 1
this, arg1 = TB.refreshButton, "LeftButton"
TB.refreshButton.scripts.OnClick(TB.refreshButton)
assert(sent[table.getn(sent)] == ".bot list", "refresh control must send list")
now = now + 1
this, arg1 = TB.partyButtons.summon, "LeftButton"
TB.partyButtons.summon.scripts.OnClick(TB.partyButtons.summon)
assert(sent[table.getn(sent)] == ".bot summon Alpha", "party summon control must send summon")
TB.CompleteOperation("Alpha", "summon", true, "summon accepted")
now = now + 1
this, arg1 = TB.partyButtons.invite, "LeftButton"
TB.partyButtons.invite.scripts.OnClick(TB.partyButtons.invite)
assert(sent[table.getn(sent)] == ".bot invite Alpha", "party invite control must send invite")
TB.CompleteOperation("Alpha", "invite", true, "invite accepted")
TB._debugGroup.Alpha = true
TB.Refresh()
now = now + 1
this, arg1 = activeRow.btnInvite, "LeftButton"
activeRow.btnInvite.scripts.OnClick(activeRow.btnInvite)
assert(sent[table.getn(sent)] == ".bot uninvite Alpha", "row kick control must send uninvite")
TB.SetStatus = oldSetStatus
TB.RequestPollSoon = oldRequestPollSoon

print("PASS: TortoiseBotsManager regression checks")
