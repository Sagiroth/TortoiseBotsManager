-- TortoiseBotsManager regression harness.
-- Run with: lua5.1 tests/regression.lua .
--
-- The mock intentionally models the small Vanilla 1.12 widget surface used by
-- the addon.  In particular, CheckButtons own checked state and every Button
--/CheckButton may register clicks; generic Frames may not.

local root = arg[1] or "."
local frames = {}
local sent = {}
local now = 10
local targetExists = true
local targetNameValue = "Training Dummy"
local partyMembers = {}

local function object(kind, parent)
    local value = {
        kind = kind,
        parent = parent,
        scripts = {},
        visible = true,
        text = "",
        enabled = true,
        checked = false,
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
        if self.kind ~= "Button" and self.kind ~= "CheckButton" then
            error("RegisterForClicks called on non-button")
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
    function methods:SetChecked(checked) self.checked = checked and true or false end
    function methods:GetChecked() return self.checked end
    function methods:ClearFocus() end
    function methods:Show() self.visible = true end
    function methods:Hide() self.visible = false end
    function methods:IsVisible() return self.visible end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:GetParent() return self.parent end
    function methods:StartMoving() end
    function methods:StopMovingOrSizing() end
    function methods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 15 end
    function methods:GetCenter() return 0, 0 end
    function methods:GetEffectiveScale() return 1 end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end

    methods.__index = methods
    return setmetatable(value, methods)
end

function CreateFrame(kind, name, parent)
    local frame = object(kind, parent)
    frame.name = name
    if name then frames[name] = frame end
    return frame
end

TortoiseBotsDB = { roster = { Stale = { addedAt = 1 } }, rosterList = { "Legacy" }, activeTab = "party" }
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local chatFilters = {}
function ChatFrame_AddMessageEventFilter(eventName, filter) chatFilters[eventName] = filter end
local chatEventPassed = false
function ChatFrame_OnEvent() chatEventPassed = true end
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
    if unit == "target" then return targetExists and targetNameValue or nil end
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
assert(chatFilters.CHAT_MSG_SYSTEM and chatFilters.CHAT_MSG_SAY and chatFilters.CHAT_MSG_PARTY,
    "command and protocol echoes should register local filters")
assert(chatFilters.CHAT_MSG_SAY(nil, nil, ".bot action stay") == true
    and chatFilters.CHAT_MSG_SYSTEM(nil, nil, "TBM:ACTION_ACK|stay|party|2|-") == true
    and not chatFilters.CHAT_MSG_SYSTEM(nil, nil, "A critical server error"), "chat noise must be hidden locally")
assert(chatFilters.CHAT_MSG_SYSTEM(nil, nil, "Bot Arcana queued for login; it will follow Valguard after entering the world.") == true,
    "bot login announcement must be intercepted")
local history = TB.GetLogHistory()
assert(table.getn(history) > 0, "log history must contain intercepted bot event")
assert(history[table.getn(history)].msg == "Arcana queued for login (following Valguard)", "message must be tidied")
event, arg1 = "CHAT_MSG_SYSTEM", "TBM:ROSTER_BEGIN0"
chatEventPassed = false
ChatFrame_OnEvent()
assert(not chatEventPassed, "legacy chat dispatcher must hide structured roster noise")
event, arg1 = "CHAT_MSG_SYSTEM", "Bot Arcana logout requested; durable ownership was retained."
chatEventPassed = false
ChatFrame_OnEvent()
assert(not chatEventPassed, "legacy chat dispatcher must intercept bot logout message")
assert(history[table.getn(history)].msg == "Arcana logout requested", "logout message must be tidied in history")
event, arg1 = "CHAT_MSG_SYSTEM", "A critical server error"
ChatFrame_OnEvent()
assert(chatEventPassed, "legacy chat dispatcher must preserve critical errors")
assert(TortoiseBotsDB.roster == nil and TortoiseBotsDB.rosterList == nil,
    "old local roster data must be ignored and removed")
assert(TortoiseBotsDB.activeTab == "actions", "Actions must be the default tab")
assert(TB.actionsFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Actions tab must be visible by default")
assert(TB.rosterFrame.point and TB.rosterFrame.point[1] == "TOPLEFT",
    "rosterFrame must have anchor point set")
TB.ShowTab("roster")
assert(TB.rosterFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Roster tab must become visible after ShowTab('roster')")
TB.ShowTab("log")
assert(TB.logFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.rosterFrame:IsVisible(),
    "Log tab must become visible after ShowTab('log')")
TB.ShowTab("actions")
assert(TB.actionsFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Actions tab must be restored after ShowTab('actions')")
assert(TB.rows and table.getn(TB.rows) == TB.C.ROW_N, "all roster rows must be created")
assert(TB.rows[1].kind == "Frame", "roster rows must be passive containers")
assert(TB.rows[1].check and TB.rows[1].check.kind == "CheckButton",
    "roster rows must expose checkbox selection")
assert(TB.rows[1].btnRemove == nil and TB.rows[1].btnFollow == nil
    and TB.rows[1].btnSummon == nil, "rows must not contain lifecycle/gameplay controls")
assert(TB.commandBox == nil and TB.commandButton == nil,
    "advanced command box must stay hidden")
assert(TB.statsButton == nil and TB.helpButton == nil,
    "server tools must not displace the compact surfaces")
assert(TB.actionButtons and TB.lifecycleButtons, "Actions and lifecycle bars must exist")
assert(TB.actionButtons.pull and TB.C.ACTIONS[3] == "pull",
    "distinct mature Pull behavior must remain exposed")
assert(rawget(TB, "selected") == nil, "legacy gameplay selection alias must not exist")

-- A structured snapshot is authoritative and includes offline owned rows.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
local rows = TB.GetDisplayRows("")
assert(table.getn(rows) == 3, "snapshot must render all owned rows, including offline")
assert(rows[1].name == "Alpha" and rows[1].className == "Warrior",
    "snapshot class and name must be retained")
assert(rows[2].name == "Gamma" and rows[2].className == "Druid",
    "Druid class IDs must render as Druid")
assert(TB.GetState("Bravo").status == TB.C.STATUS.OFFLINE,
    "offline snapshot state must remain offline")
assert(TB.GetState("Alpha").location == "map:1,zone:2,area:3",
    "snapshot location must be retained")
assert(TB.GetRosterCount() == 3, "roster count must come from snapshot")

-- Display rows constantly show all bots with their state
assert(table.getn(TB.GetDisplayRows("")) == 3, "roster must constantly show all bots")
assert(table.getn(TB.GetDisplayRows("alpha")) == 1, "text search must filter by bot name")

-- Class colors and status badge
local warriorColor = TB.GetClassColor(1)
assert(warriorColor and warriorColor.hex == "ffc79c6e", "Warrior class color must match Turtle palette")
local badge = TB.StatusBadge(TB.GetState("Alpha"), false)
assert(string.find(badge, "Online"), "Status badge for online state must display Online")

-- Action button icons
assert(TB.actionButtons.attack and TB.actionButtons.attack.icon, "Attack button must have an icon")
assert(TB.actionButtons.focusSkull and (TB.actionButtons.focusSkull.icon or TB.actionButtons.focusSkull.raidIcon),
    "Focus skull must have an icon")
assert(TB.actionButtons.hold and TB.actionButtons.hold.icon, "Hold button must have an icon")
assert(TB.actionButtons.ready and TB.actionButtons.ready.icon, "Ready check button must have an icon")

-- Formation pills
assert(TB.formationPills and TB.formationPills.shield and TB.formationPills.near,
    "Formation pills must exist")
assert(not TB.formationPills.shield.enabled, "Shield should start disabled (active)")
assert(TB.formationPills.near.enabled, "Near should start enabled")
now = now + 1
this = TB.formationPills.near
TB.formationPills.near.scripts.OnClick(TB.formationPills.near)
assert(TB.currentFormation == "near", "Clicking near pill must set current formation to near")
assert(not TB.formationPills.near.enabled and TB.formationPills.shield.enabled,
    "Active formation pill must become disabled")

-- Local names and legacy list responses cannot add an offline canonical row.
TB.AddToRoster("ClientOnly")
assert(TB.GetRosterEntry("ClientOnly") == nil, "client-only names are not roster rows")
TB.OnSystemMessage("ClientOnly: offline, random 0, AI 0")
assert(TB.GetRosterEntry("ClientOnly") == nil, "legacy list cannot add offline ownership")

-- Checkbox selection is multi-select and independent from Actions.
TB.Refresh()
local alphaRow, bravoRow, gammaRow = TB.rows[1], TB.rows[3], TB.rows[2]
this = alphaRow.check; alphaRow.check:SetChecked(true); alphaRow.check.scripts.OnClick(alphaRow.check)
this = bravoRow.check; bravoRow.check:SetChecked(true); bravoRow.check.scripts.OnClick(bravoRow.check)
assert(TB.IsRosterSelected("Alpha") and TB.IsRosterSelected("Bravo"),
    "checkboxes must select multiple names")
this = alphaRow.check; alphaRow.check:SetChecked(false); alphaRow.check.scripts.OnClick(alphaRow.check)
assert(not TB.IsRosterSelected("Alpha") and TB.IsRosterSelected("Bravo"),
    "unchecking a box must deselect that name")
this = alphaRow.check; alphaRow.check:SetChecked(true); alphaRow.check.scripts.OnClick(alphaRow.check)
assert(table.getn(TB.GetEligibleRosterNames("logout")) == 1
    and TB.GetEligibleRosterNames("logout")[1] == "Alpha",
    "mixed logout selection must use only live eligible names")
assert(table.getn(TB.GetEligibleRosterNames("login")) == 1
    and TB.GetEligibleRosterNames("login")[1] == "Bravo",
    "mixed login selection must use only offline eligible names")

-- Master Select All Checkbox
TB.ClearRosterSelection()
assert(not TB.checkAll:GetChecked(), "checkAll must start unchecked when nothing is selected")
this = TB.checkAll; TB.checkAll:SetChecked(true); TB.checkAll.scripts.OnClick(TB.checkAll)
assert(TB.IsRosterSelected("Alpha") and TB.IsRosterSelected("Bravo") and TB.IsRosterSelected("Gamma"),
    "clicking checkAll must select all displayed roster entries")
assert(TB.checkAll:GetChecked(), "checkAll must remain checked when all entries are selected")
assert(table.getn(TB.GetEligibleRosterNames("summon")) == 2,
    "all live bots (Alpha, Gamma) must be eligible for summon when all selected")
this = TB.checkAll; TB.checkAll:SetChecked(false); TB.checkAll.scripts.OnClick(TB.checkAll)
assert(table.getn(TB.GetSelectedRosterNames()) == 0,
    "unchecking checkAll must deselect all entries")
assert(not TB.checkAll:GetChecked(), "checkAll must be unchecked after clearing")
TB.ToggleRosterSelection("Alpha", true)
TB.ToggleRosterSelection("Bravo", true)

now = now + 1
local beforeLogin = table.getn(sent)
this = TB.lifecycleButtons.login
TB.lifecycleButtons.login.scripts.OnClick(TB.lifecycleButtons.login)
assert(table.getn(sent) == beforeLogin + 1 and sent[table.getn(sent)] == ".bot add Bravo",
    "Login must send one command for the eligible subset")

TB.ClearRosterSelection()
TB.ToggleRosterSelection("Alpha", true)
TB.ToggleRosterSelection("Gamma", true)
now = now + 1
local beforeInvite = table.getn(sent)
this = TB.lifecycleButtons.invite
TB.lifecycleButtons.invite.scripts.OnClick(TB.lifecycleButtons.invite)
assert(table.getn(sent) == beforeInvite + 1 and sent[table.getn(sent)] == ".bot invite Alpha",
    "Invite must skip selected bots already in the group")
now = now + 1
local beforeKick = table.getn(sent)
this = TB.lifecycleButtons.kick
TB.lifecycleButtons.kick.scripts.OnClick(TB.lifecycleButtons.kick)
assert(table.getn(sent) == beforeKick + 1 and sent[table.getn(sent)] == ".bot uninvite Gamma",
    "Kick must use only selected group members")

-- Gameplay actions never inspect roster selection and issue exactly one intent.
local selectedBeforeAction = table.getn(TB.GetSelectedRosterNames())
now = now + 1
local beforeAttack = table.getn(sent)
this = TB.actionButtons.attack
TB.actionButtons.attack.scripts.OnClick(TB.actionButtons.attack)
assert(table.getn(sent) == beforeAttack + 1 and sent[table.getn(sent)] == ".bot action attack",
    "Attack must send exactly one action intent")
assert(table.getn(TB.GetSelectedRosterNames()) == selectedBeforeAction,
    "gameplay actions must not couple to roster checkbox selection")
now = now + 1
local beforeAoe = table.getn(sent)
this = TB.actionButtons.aoe
TB.actionButtons.aoe.scripts.OnClick(TB.actionButtons.aoe)
assert(table.getn(sent) == beforeAoe + 1 and sent[table.getn(sent)] == ".bot action aoe on",
    "AoE must send one toggle intent")
assert(TB.aoePending, "AoE should remain pending until the server responds")
TB.OnSystemMessage("TBM:ACTION_ERR|aoe|failed|No scoped bot accepted")
assert(not TB.aoePending and not TB.aoeEnabled, "rejected AoE must not drift local state")
now = now + 1
local beforeAoeRetry = table.getn(sent)
this = TB.actionButtons.aoe
TB.actionButtons.aoe.scripts.OnClick(TB.actionButtons.aoe)
assert(table.getn(sent) == beforeAoeRetry + 1 and sent[table.getn(sent)] == ".bot action aoe on",
    "AoE retry must request the previous known state")
TB.OnSystemMessage("TBM:ACTION_ACK|aoe|party|2|on")
assert(TB.aoeEnabled and TB.actionButtons.aoe.text == "AoE On",
    "accepted AoE state must be reflected by the ACK")

-- Target/context feedback is descriptive, not a universal scope promise.
targetNameValue = "Alpha"
TB.Refresh()
assert(TB.GetActionScope() == "bot:Alpha" and TB.scopeHint.text == "Target: Alpha",
    "owned target should be shown as context only")
assert(not TB.actionButtons.attack.enabled and not TB.actionButtons.pull.enabled
    and not TB.actionButtons.pullback.enabled,
    "owned bot targets must disable enemy-only actions")
assert(TB.actionButtons.stay.enabled and TB.actionButtons.follow.enabled
    and TB.actionButtons.aoe.enabled, "dynamic actions remain usable for owned targets")
targetNameValue = "Enemy"
TB.Refresh()
assert(TB.GetActionScope() == "party" and TB.scopeHint.text == "Party actions",
    "non-owned targets should use neutral context wording")
assert(TB.actionButtons.attack.enabled and TB.actionButtons.pull.enabled
    and TB.actionButtons.pullback.enabled,
    "normal targets should enable enemy-only actions")
now = now + 1
local beforePull = table.getn(sent)
this = TB.actionButtons.pull
TB.actionButtons.pull.scripts.OnClick(TB.actionButtons.pull)
assert(table.getn(sent) == beforePull + 1 and sent[table.getn(sent)] == ".bot action pull",
    "Pull must send the supported ordinary-pull intent")
now = now + 1
this = TB.actionButtons.come
TB.actionButtons.come.scripts.OnClick(TB.actionButtons.come)
assert(sent[table.getn(sent)] == ".bot action come", "Come button must send action come")

now = now + 1
this = TB.actionButtons.ready
TB.actionButtons.ready.scripts.OnClick(TB.actionButtons.ready)
assert(sent[table.getn(sent)] == ".bot action ready", "Ready button must send action ready")

targetExists = false
TB.Refresh()
assert(not TB.actionButtons.attack.enabled and not TB.actionButtons.pull.enabled
    and not TB.actionButtons.pullback.enabled,
    "missing targets must disable enemy-only actions")
targetExists = true
TB.Refresh()

-- Structured action feedback remains machine-readable and terse.
TB.OnSystemMessage("TBM:ACTION_ACK|attack|party|2|-")
assert(TB.lastActionAck and TB.lastActionAck.intent == "attack"
    and TB.lastActionAck.scope == "party" and TB.lastActionAck.count == 2,
    "structured action ACK must be parsed")
TB.OnSystemMessage("TBM:ACTION_ERR|pullback|NO_TARGET|Select a living target")
assert(TB.lastActionError and TB.lastActionError.code == "NO_TARGET",
    "structured action ERR must be parsed")

-- Polling now requests the authoritative roster command and deduplicates
-- queued refreshes; BuildCommand remains available for legacy callers.
TB._pollPending = false; TB._pollQueued = false
now = now + 1
TB.SendActionIntent("stop")
TB._pollPending = false; TB._pollQueued = false
local beforeRosterPoll = table.getn(sent)
assert(not TB.PollList(true) and TB._pollQueued, "queued roster poll must mark itself queued")
local afterQueuedPoll = table.getn(sent)
assert(not TB.PollList(true) and table.getn(sent) == afterQueuedPoll,
    "queued roster refreshes must not duplicate")
now = now + 1
local queueFrame = frames["TortoiseBotsManagerQueueFrame"]
assert(queueFrame, "queued roster poll must create a send queue")
this, arg1 = queueFrame, 0.1
queueFrame.scripts.OnUpdate(queueFrame)
assert(table.getn(sent) == beforeRosterPoll + 1 and sent[table.getn(sent)] == ".bot roster",
    "queued roster poll must send once when throttle clears")
assert(not TB._pollQueued and TB._pollPending, "sent roster poll must become pending")
assert(TB.BuildCommand("command", "Alpha", "dps assist") == "command Alpha dps assist",
    "BuildCommand API must preserve legacy formatting")
assert(TB.BuildCommand("action", nil, "focus skull") == "action focus skull",
    "BuildCommand must preserve command-only formatting")

print("PASS: TortoiseBotsManager regression checks")
