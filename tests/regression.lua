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
function GetNumPartyMembers() return 0 end
function GetNumRaidMembers() return 0 end
function UnitName(unit) if unit == "player" then return "Tester" end end
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
assert(TB.statsButton and TB.helpButton, "stats and help commands must have explicit controls")
assert(TB.commandBox and TB.commandButton, "selected-bot command input must be available")
assert(TB.refreshButton and TB.addButton, "list and add commands must have explicit controls")
assert(TB.partyButtons and TB.partyButtons.summon and TB.partyButtons.follow and TB.partyButtons.invite,
    "party command controls must be available")

local refreshed, refreshError = pcall(TB.Refresh)
assert(refreshed, refreshError)

TB.AddToRoster("Alpha")
TB.Refresh()
local row = TB.rows[1]
assert(row.entry and row.entry.name == "Alpha", "roster entry must render")
this, arg1 = row, "LeftButton"
row.scripts.OnClick(row)
assert(TB.selected == "Alpha", "left-click must select a roster row")
assert(not TB.commandButton.enabled, "selected actions must be disabled for offline bots")
this, arg1 = row, "RightButton"
row.scripts.OnClick(row)
assert(TB.GetState("Alpha") == nil, "right-click must forget an offline roster row")

local reconcileCalls = 0
local realReconcile = TB.ReconcilePoll
TB.ReconcilePoll = function() reconcileCalls = reconcileCalls + 1 end
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
TB.SetState("Alpha", { online = true, enteredWorld = true, status = TB.C.STATUS.ONLINE })
TB.OnCommandSent("invite Alpha")
assert(TB.GetState("Alpha").status == TB.C.STATUS.INVITING, "invite must enter optimistic state")
TB.OnSystemMessage("The group invitation for Alpha was rejected by the native group handler.")
assert(TB.GetState("Alpha").status == TB.C.STATUS.ONLINE, "invite rejection must roll back optimistic state")
assert(lastStatusKind == "warn", "invite rejection must be surfaced as a warning")
local pollsBeforeUninvite = pollRequests
TB.OnSystemMessage("Uninvite sent for bot Alpha.")
assert(lastStatusKind == "ok", "uninvite response must be surfaced as success")
assert(pollRequests > pollsBeforeUninvite, "uninvite response must schedule reconciliation")
TB.OnSystemMessage("Bot commands: add/remove/follow/invite/uninvite/stay/list/stats/pullback/summon/command")
assert(lastStatusKind == "muted", "help response must be surfaced as informational")

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

now = 40
this, arg1 = TB.statsButton, "LeftButton"
TB.statsButton.scripts.OnClick(TB.statsButton)
assert(sent[table.getn(sent)] == ".bot stats", "stats control must send the stats command")
now = 41
this, arg1 = TB.helpButton, "LeftButton"
TB.helpButton.scripts.OnClick(TB.helpButton)
assert(sent[table.getn(sent)] == ".bot help", "help control must send the server help command")
TB.selected = "Alpha"
TB.commandBox:SetText("dps assist")
now = 42
this, arg1 = TB.commandButton, "LeftButton"
TB.commandButton.scripts.OnClick(TB.commandButton)
assert(sent[table.getn(sent)] == ".bot command Alpha dps assist", "command control must forward selected-bot commands")

TB.SetState("Alpha", { online = true, enteredWorld = true, status = TB.C.STATUS.ONLINE })
TB.Refresh()
local activeRow = TB.rows[1]
now = 43
this, arg1 = activeRow.btnSummon, "LeftButton"
activeRow.btnSummon.scripts.OnClick(activeRow.btnSummon)
assert(sent[table.getn(sent)] == ".bot summon Alpha", "row summon control must send summon")
now = 44
this, arg1 = activeRow.btnFollow, "LeftButton"
activeRow.btnFollow.scripts.OnClick(activeRow.btnFollow)
assert(sent[table.getn(sent)] == ".bot follow Alpha", "row follow control must send follow")
now = 45
this, arg1 = activeRow.btnInvite, "LeftButton"
activeRow.btnInvite.scripts.OnClick(activeRow.btnInvite)
assert(sent[table.getn(sent)] == ".bot invite Alpha", "row invite control must send invite")
now = 46
this, arg1 = TB.selButtons[1], "LeftButton"
TB.selButtons[1].scripts.OnClick(TB.selButtons[1])
assert(sent[table.getn(sent)] == ".bot stay Alpha", "selected stay control must send stay")
now = 47
this, arg1 = TB.selButtons[2], "LeftButton"
TB.selButtons[2].scripts.OnClick(TB.selButtons[2])
assert(sent[table.getn(sent)] == ".bot pullback", "pullback control must send pullback")
now = 48
this, arg1 = TB.selButtons[3], "LeftButton"
TB.selButtons[3].scripts.OnClick(TB.selButtons[3])
assert(sent[table.getn(sent)] == ".bot command Alpha reset", "reset control must send command")
now = 49
this, arg1 = TB.partyButtons.follow, "LeftButton"
TB.partyButtons.follow.scripts.OnClick(TB.partyButtons.follow)
assert(sent[table.getn(sent)] == ".bot follow Alpha", "party follow control must send follow")
now = 50
this, arg1 = activeRow.btnRemove, "LeftButton"
activeRow.btnRemove.scripts.OnClick(activeRow.btnRemove)
assert(sent[table.getn(sent)] == ".bot remove Alpha", "row remove control must send remove")
now = 51
TB.addBox:SetText("Charlie")
this, arg1 = TB.addButton, "LeftButton"
TB.addButton.scripts.OnClick(TB.addButton)
assert(sent[table.getn(sent)] == ".bot add Charlie", "add control must send add")
now = 52
this, arg1 = TB.refreshButton, "LeftButton"
TB.refreshButton.scripts.OnClick(TB.refreshButton)
assert(sent[table.getn(sent)] == ".bot list", "refresh control must send list")
now = 53
this, arg1 = TB.partyButtons.summon, "LeftButton"
TB.partyButtons.summon.scripts.OnClick(TB.partyButtons.summon)
assert(sent[table.getn(sent)] == ".bot summon Alpha", "party summon control must send summon")
now = 54
this, arg1 = TB.partyButtons.invite, "LeftButton"
TB.partyButtons.invite.scripts.OnClick(TB.partyButtons.invite)
assert(sent[table.getn(sent)] == ".bot invite Alpha", "party invite control must send invite")
TB._debugGroup.Alpha = true
TB.Refresh()
now = 55
this, arg1 = activeRow.btnInvite, "LeftButton"
activeRow.btnInvite.scripts.OnClick(activeRow.btnInvite)
assert(sent[table.getn(sent)] == ".bot uninvite Alpha", "row kick control must send uninvite")
TB.SetStatus = oldSetStatus
TB.RequestPollSoon = oldRequestPollSoon

print("PASS: TortoiseBotsManager regression checks")
