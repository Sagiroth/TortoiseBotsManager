-- TortoiseBotsManager regression harness.
-- Run with: lua5.1 tests/regression.lua .
--
-- The mock intentionally models the small Vanilla 1.12 widget surface used by
-- the addon.  In particular, CheckButtons own checked state and every Button
--/CheckButton may register clicks; generic Frames may not.

local root = arg[1] or "."
if not table.getn then table.getn = function(t) return t and #t or 0 end end
if not unpack then unpack = table.unpack end
if not math.mod then math.mod = math.fmod end
local frames = {}
local sent = {}
local addonSent = {}
local now = 10
local targetExists = true
local targetNameValue = "Training Dummy"
local partyMembers = {}
local partyClassName = "Priest"
tradePartner = nil

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
    function methods:SetFrameLevel(level) self.frameLevel = level end
    function methods:GetFrameLevel() return self.frameLevel or 0 end
    function methods:SetPoint(...) self.points = self.points or {} table.insert(self.points, {...}) self.point = {...} end
    function methods:ClearAllPoints() self.points = {} self.point = nil end
    function methods:GetNumPoints() return self.points and table.getn(self.points) or 0 end
    function methods:GetPoint(index)
        self.points = self.points or {}
        if index then return unpack(self.points[index] or {}) end
        local last = self.points[table.getn(self.points)]
        if last then return unpack(last) end
    end
    function methods:SetFrameStrata(strata) self.strata = strata end
    function methods:SetMovable(movable) self.movable = movable end
    function methods:SetClampedToScreen(clamped) self.clamped = clamped end
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
    function methods:SetAllPoints(other)
        other = other or self.parent
        self.points = self.points or {}
        table.insert(self.points, { "TOPLEFT", other, "TOPLEFT", 0, 0 })
        table.insert(self.points, { "TOPRIGHT", other, "TOPRIGHT", 0, 0 })
        self.point = { "TOPRIGHT", other, "TOPRIGHT", 0, 0 }
    end
    function methods:SetBlendMode(...) end
    function methods:SetAutoFocus(...) end
    function methods:SetJustifyH(...) end
    function methods:SetText(text) self.text = text end
    function methods:GetText() return self.text end
    function methods:GetFontString()
        -- 1.12 UIPanelButtonTemplate buttons own a centered label FontString.
        if not self.fontString then
            self.fontString = object("FontString", self)
            self.fontString:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
        return self.fontString
    end
    function methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
    function methods:SetVertexColor(...) end
    function methods:SetJustifyV(...) end
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
    function methods:GetLeft() return self.x or 100 end
    function methods:GetTop() return (self.y or 100) + (self.height or 50) end
    function methods:GetRight() return (self.x or 100) + (self.width or 118) end
    function methods:GetBottom() return (self.y or 100) end
    function methods:GetCenter() return 0, 0 end
    function methods:GetEffectiveScale() return 1 end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end

    methods.__index = methods
    return setmetatable(value, methods)
end

function CreateFrame(kind, name, parent, template)
    local frame = object(kind, parent)
    frame.name = name
    if template == "UIPanelCloseButton" then
        frame.width = 32
        frame.height = 32
    end
    if name then frames[name] = frame end
    return frame
end

TortoiseBotsDB = { roster = { Stale = { addedAt = 1 } }, rosterList = { "Legacy" }, activeTab = "legacy" }
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
UISpecialFrames = {}
SlashCmdList = {}
local defaultChatMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) table.insert(defaultChatMessages, msg) end }
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
StaticPopupDialogs = StaticPopupDialogs or {}
local lastPopupShown = nil
function StaticPopup_Show(which) lastPopupShown = which end
function time() return 123 end
function SendChatMessage(message) table.insert(sent, message) end
function SendAddonMessage(prefix, message, channel)
    table.insert(addonSent, { prefix = prefix, message = message, channel = channel })
end
function GetCursorPosition() return 0, 0 end
function GetScreenWidth() return 1024 end
function UnitExists(unit)
    if unit == "player" then return true end
    if unit == "target" then return targetExists end
    local _, _, index = string.find(unit or "", "^party(%d+)$")
    return index and tonumber(index) <= table.getn(partyMembers) or false
end
local deadUnits, ghostUnits = {}, {}
function UnitIsDead(unit) return deadUnits[unit] or false end
function UnitIsGhost(unit) return ghostUnits[unit] or false end
local itemCache = {}
function GetItemInfo(id)
    local item = itemCache[id]
    if not item then return nil end
    return item.name, "item:" .. id .. ":0:0:0", item.quality or 1, 1, "Armor", "Cloth", 1, "", item.texture
end
function UnitLevel(unit) return 60 end
function UnitClass(unit)
    if unit == "player" then return "Warrior", "WARRIOR" end
    return partyClassName, string.upper(partyClassName)
end
function GetNumPartyMembers() return table.getn(partyMembers) end
function GetNumRaidMembers() return 0 end
function UnitName(unit)
    if unit == "player" then return "Tester" end
    if unit == "target" then return targetExists and targetNameValue or nil end
    if unit == "NPC" then return tradePartner end
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
    "BotPanel.lua",
    "BotNpc.lua",
    "BotVault.lua",
    "BotRun.lua",
    "BotLoot.lua",
    "BotOrder.lua",
    "ServerInfo.lua",
    "MiniBar.lua",
    "Minimap.lua",
    "Bindings.lua",
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
    and chatFilters.CHAT_MSG_SYSTEM(nil, nil, "TBM:VERSION|2026-09-25-v7") == true
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
event, arg1 = "CHAT_MSG_SAY", ".bot action stay"
chatEventPassed = false
ChatFrame_OnEvent()
assert(not chatEventPassed, "legacy chat dispatcher must hide .bot say commands")
event, arg1 = "CHAT_MSG_SYSTEM", "Bot commands: add/remove/logout/roster"
chatEventPassed = false
ChatFrame_OnEvent()
assert(not chatEventPassed, "legacy chat dispatcher must intercept Bot commands server message")
assert(defaultChatMessages[table.getn(defaultChatMessages)] == "|cffd8a657TortoiseBots:|r |cff20ff20Enabled|r",
    "Bot commands must be replaced with TortoiseBots: Enabled")
-- The current server's .bot help response only confirms the module is enabled.
TB.OnSystemMessage("TortoiseBots: Enabled")
assert(TortoiseBotsDB.roster == nil and TortoiseBotsDB.rosterList == nil,
    "old local roster data must be ignored and removed")
assert(TortoiseBotsDB.activeTab == "actions", "Actions must be the default tab")
assert(TB.actionsFrame:IsVisible() and not TB.partyFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.guildFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Actions tab must be visible by default")
assert(TB.rosterFrame.point and TB.rosterFrame.point[1] == "TOPLEFT",
    "rosterFrame must have anchor point set")
TB.ShowTab("party")
assert(TB.partyFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.guildFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Party tab must become visible after ShowTab('party')")
TB.ShowTab("roster")
assert(TB.rosterFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.partyFrame:IsVisible() and not TB.guildFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Roster tab must become visible after ShowTab('roster')")
TB.ShowTab("guild")
assert(TB.guildFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.partyFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.logFrame:IsVisible(),
    "Guild tab must become visible after ShowTab('guild')")
TB.ShowTab("log")
assert(TB.logFrame:IsVisible() and not TB.actionsFrame:IsVisible() and not TB.partyFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.guildFrame:IsVisible(),
    "Log tab must become visible after ShowTab('log')")
TB.ShowTab("actions")
assert(TB.actionsFrame:IsVisible() and not TB.partyFrame:IsVisible() and not TB.rosterFrame:IsVisible() and not TB.guildFrame:IsVisible() and not TB.logFrame:IsVisible(),
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
assert(TB.actionButtons.pull and TB.GetActionDefinition("pull") ~= nil,
    "distinct mature Pull behavior must remain exposed")
assert(TB.C.CC_MARKS and TB.C.CC_MARK_LABELS.circle == "Circle"
    and TB.C.CC_MARK_ICONS.moon == 5, "all CC raid marks must have stable labels/icons")
assert(TB.ccMenu and TB.ccMenu.buttons.circle and TB.ccMenu.buttons.moon,
    "CC Mark must expose a compact raid-icon picker")
assert(rawget(TB, "selected") == nil, "legacy gameplay selection alias must not exist")

-- A structured snapshot is authoritative and includes offline owned rows.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
TB.OnSystemMessage("TBM:CC_ASSIGN_BEGIN|1")
TB.OnSystemMessage("TBM:CC_ASSIGN|Alpha|circle")
TB.OnSystemMessage("TBM:CC_ASSIGN_END")
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
assert(TB.GetRosterEntry("Alpha").ccMark == "circle",
    "CC assignment snapshot must expose the server-owned CC mark")
assert(TB.GetRosterCount() == 3, "roster count must come from snapshot")

-- Display rows constantly show all bots with their state
assert(table.getn(TB.GetDisplayRows("")) == 3, "roster must constantly show all bots")
assert(table.getn(TB.GetDisplayRows("alpha")) == 1, "text search must filter by bot name")

-- Alt-bots (TortoiseBots #872): the line after the snapshot marks owned
-- characters playing on their own; Login on one takes it back.
assert(not TB.GetState("Alpha").altBot, "no alt-bot flag before the alt-bot line")
assert(not TB.IsRosterActionEligible("Alpha", "login"), "an online companion is not a Login target")
TB.OnSystemMessage("TBM:ALTBOTS|Alpha")
assert(TB.GetState("Alpha").altBot and not TB.GetState("Gamma").altBot, "alt-bot line must flag only the named row")
assert(string.find(TB.StatusBadge(TB.GetState("Alpha"), false), "Alt%-bot"), "alt-bot badge must say Alt-bot")
assert(string.find(TB.StatusText(TB.GetState("Alpha"), false), "Playing alone"), "alt-bot status text")
assert(TB.IsRosterActionEligible("Alpha", "login"), "Login must take an alt-bot back")
assert(TB.IsRosterActionEligible("Alpha", "logout"), "Logout must log an alt-bot out")
assert(TB.IsRosterActionEligible("Bravo", "login"), "offline rows stay Login targets")
TB.OnSystemMessage("TBM:ALTBOTS|")
assert(not TB.GetState("Alpha").altBot, "an empty alt-bot line clears the flag")
TB.OnSystemMessage("TBM:ALTBOTS|Alpha")
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
assert(not TB.GetState("Alpha").altBot, "a new snapshot clears flags (older servers send no alt-bot line)")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")

-- Clients that double "|A"/"|T" pairs on server-delivered chat must still parse.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101||Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103||Tarbh|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
assert(TB.HasRosterSnapshot(), "doubled-pipe snapshot must commit")
assert(TB.GetRosterSnapshotError() == nil, "doubled-pipe snapshot must leave no error")
assert(table.getn(TB.GetDisplayRows("")) == 3, "doubled-pipe rows must all render")
assert(TB.GetState("Alpha").location == "map:1,zone:2,area:3", "restored A-initial row must keep exact fields")
assert(TB.GetState("Tarbh") ~= nil, "restored T-initial row must exist")
TB.OnSystemMessage("TBM:ALTBOTS||Alpha")
assert(TB.GetState("Alpha").altBot, "doubled-pipe alt-bot line must flag the named row")

-- Same bytes over the addon channel.
TB.OnAddonMessage("TBM", "TBM:ROSTER_BEGIN|2", "PARTY", "Tester")
TB.OnAddonMessage("TBM", "TBM:ROSTER|101||Alpha|1|online|0|map:1,zone:2,area:3", "PARTY", "Tester")
TB.OnAddonMessage("TBM", "TBM:ROSTER|104||Tilda|2|online|0|-", "PARTY", "Tester")
TB.OnAddonMessage("TBM", "TBM:ROSTER_END", "PARTY", "Tester")
assert(table.getn(TB.GetDisplayRows("")) == 2, "addon-channel doubled-pipe snapshot must commit")
assert(TB.GetRosterSnapshotError() == nil, "addon-channel doubled-pipe snapshot must leave no error")

-- One bad row must not empty the snapshot; the good rows still commit.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|broken-row")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
assert(TB.HasRosterSnapshot(), "snapshot with one bad row must still commit")
assert(table.getn(TB.GetDisplayRows("")) == 2, "good rows must render despite one bad row")
assert(TB.GetState("Alpha") ~= nil and TB.GetState("Gamma") ~= nil, "good rows must be addressable")
local partialErr = TB.GetRosterSnapshotError()
assert(partialErr and partialErr.code == "partial_rows", "skipped rows must be recorded for debugging")

-- Restore the canonical snapshot for the tests below.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")

-- Class colors and status badge
local warriorColor = TB.GetClassColor(1)
assert(warriorColor and warriorColor.hex == "ffc79c6e", "Warrior class color must match Tortoise palette")
local badge = TB.StatusBadge(TB.GetState("Alpha"), false)
assert(string.find(badge, "Online"), "Status badge for online state must display Online")

-- Action button icons
assert(TB.actionButtons.attack and TB.actionButtons.attack.icon, "Attack button must have an icon")
assert(TB.actionButtons.interrupt and TB.actionButtons.interrupt.icon, "Interrupt button must have an icon")
assert(TB.actionButtons.focusSkull and (TB.actionButtons.focusSkull.icon or TB.actionButtons.focusSkull.raidIcon),
    "Focus skull must have an icon")
assert(TB.actionButtons.hold and TB.actionButtons.hold.icon, "Hold button must have an icon")
assert(TB.actionButtons.ready and TB.actionButtons.ready.icon, "Ready check button must have an icon")

-- Formation pills
assert(TB.formationPills and TB.formationPills.shield and TB.formationPills.near,
    "Formation pills must exist")
assert(TB.formationPills.shield.isActive, "Shield should start picked")
assert((not TB.formationPills.near.isActive), "Near should start unpicked")
now = now + 1
this = TB.formationPills.near
TB.formationPills.near.scripts.OnClick(TB.formationPills.near)
assert(TB.currentFormation == "near", "Clicking near pill must set current formation to near")
assert(TB.formationPills.near.isActive and (not TB.formationPills.shield.isActive),
    "the picked formation pill lights up")
assert(table.getn(TB.C.FORMATIONS) == 10, "Camp must expose all ten server formations")
assert(TB.formationPills.far and TB.formationPills.melee and TB.formationPills.chaos
    and TB.formationPills.default, "New formation pills must exist")
assert((not TB.formationPills.far.isActive), "Far should start unpicked")
now = now + 1
this = TB.formationPills.far
TB.formationPills.far.scripts.OnClick(TB.formationPills.far)
assert(TB.currentFormation == "far", "Clicking far pill must set current formation to far")
assert(TB.formationPills.far.isActive and (not TB.formationPills.near.isActive),
    "the picked formation pill lights up, the previous one goes back")
now = now + 1
TB.SetFormation("shield")
assert(TB.currentFormation == "shield" and TB.formationPills.shield.isActive,
    "Formation must reset to shield for later cases")
assert(TB.actionButtons.rebuff and TB.actionButtons.resetTactics and TB.actionButtons.totem
    and TB.actionButtons.downtime
    and TB.actionButtons.acceptQuest and TB.actionButtons.shareQuest and TB.actionButtons.grind,
    "Camp chore buttons must exist")
assert(TB.UI.Grid.CARD_REST_H == 116 and TB.UI.Grid.CARD_FORM_H == 100,
    "Camp cards must fit the 480x330 content frame")
-- Constants: structured formation metadata must survive (no raw-list clobber),
assert(TB.C.FORMATIONS[1].id == "shield" and TB.C.FORMATIONS[1].label == "Shield",
    "structured formation metadata must remain intact")
assert(table.getn(TB.C.FORMATION_IDS) == 10 and TB.C.FORMATION_IDS[7] == "shield",
    "full formation ID list must live under FORMATION_IDS")
assert(table.getn(TB.C.CLASS_ROLES[3]) == 3 and TB.C.CLASS_ROLES[3][3].id == "survival",
    "Hunter must expose Survival alongside Beastmaster and Marksman")
assert(table.getn(TB.C.CLASS_ROLES[4]) == 3 and TB.C.CLASS_ROLES[4][3].id == "subtlety",
    "Rogue must expose Subtlety alongside Combat and Assassination")

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
TB.Refresh()
assert(TB.lifecycleButtons.login.enabled,
    "Login must enable for a selected offline snapshot row when the server is enabled")

now = now + 1
local beforeLogin = table.getn(sent)
this = TB.lifecycleButtons.login
TB.lifecycleButtons.login.scripts.OnClick(TB.lifecycleButtons.login)
assert(table.getn(sent) == beforeLogin + 1 and sent[table.getn(sent)] == ".bot add Bravo",
    "Login must send one command for the eligible subset")

TB.ClearRosterSelection()
TB.SetState("Gamma", { group = false })
TB.ToggleRosterSelection("Alpha", true)
TB.ToggleRosterSelection("Gamma", true)
assert(table.getn(TB.GetEligibleRosterNames("invite")) == 2,
    "two selected ungrouped bots must be eligible for invite")
now = now + 1
local beforeInvite = table.getn(sent)
this = TB.lifecycleButtons.invite
TB.lifecycleButtons.invite.scripts.OnClick(TB.lifecycleButtons.invite)
assert(TB.IsRosterBatchActive("invite"), "multi-invite must remain active until all results arrive")
assert(table.getn(sent) == beforeInvite + 1 and sent[table.getn(sent)] == ".bot invite Alpha",
    "multi-invite must send the first selected bot immediately")
now = now + 1
local queueFrame = frames["TortoiseBotsManagerQueueFrame"]
if queueFrame then
    this, arg1 = queueFrame, 0.1
    queueFrame.scripts.OnUpdate(queueFrame)
end
TB.OnSystemMessage("Invitation sent to bot Alpha; it may accept it asynchronously.")
-- Polling may replace optimistic state before the bot's asynchronous accept.
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|0|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
assert(table.getn(sent) == beforeInvite + 1,
    "multi-invite must wait for the first bot to join before sending the next invite")
partyMembers = { "Alpha" }
local groupWatcher = frames["TortoiseBotsManagerGroupWatcher"]
assert(groupWatcher, "group watcher must observe invite acceptance")
event, this = "GROUP_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
assert(table.getn(sent) == beforeInvite + 2 and sent[table.getn(sent)] == ".bot invite Gamma",
    "multi-invite must continue only after the first bot joins the group")
TB.OnSystemMessage("Invitation sent to bot Gamma; it may accept it asynchronously.")
partyMembers = { "Alpha", "Gamma" }
event, this = "GROUP_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
assert(not TB.IsRosterBatchActive("invite"), "multi-invite must finish after every bot joins")
partyMembers = { "Gamma" }
event, this = "GROUP_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
TB.Refresh()
TB.ClearRosterSelection()
TB.ToggleRosterSelection("Alpha", true)
TB.ToggleRosterSelection("Gamma", true)
now = now + 1
local beforeMixedInvite = table.getn(sent)
this = TB.lifecycleButtons.invite
TB.lifecycleButtons.invite.scripts.OnClick(TB.lifecycleButtons.invite)
assert(table.getn(sent) == beforeMixedInvite + 1 and sent[table.getn(sent)] == ".bot invite Alpha",
    "Invite must skip selected bots already in the group")
TB.OnSystemMessage("Invitation sent to bot Alpha; it may accept it asynchronously.")
partyMembers = { "Alpha", "Gamma" }
-- Canonical 1.12 raid event must be registered and drive the watcher.
assert(groupWatcher.events and groupWatcher.events["RAID_ROSTER_UPDATE"],
    "group watcher must listen for RAID_ROSTER_UPDATE (Vanilla 1.12 raid event)")
event, this = "RAID_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
assert(TB.IsInGroup("Alpha") and TB.IsInGroup("Gamma"),
    "RAID_ROSTER_UPDATE must refresh client group membership")
partyMembers = { "Gamma" }
event, this = "RAID_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
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
assert(TB.aoeEnabled and TB.actionButtons.aoe.isActive,
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

-- Marks panel: assignments go by explicit bot name, no targeting needed.
targetNameValue = "Alpha"
TB.Refresh()
now = now + 1
TB.SetFormation("far")
assert(sent[table.getn(sent)] == ".bot formation Alpha far",
    "targeted bot formation must use the bot-qualified scope")
now = now + 1
this = TB.actionButtons.ccMoon
TB.actionButtons.ccMoon.scripts.OnClick(TB.actionButtons.ccMoon)
assert(TB.ccMenu:IsVisible(), "CC Mark button must open the Marks panel")
assert(TB.ccMenu.rows and TB.ccMenu.rows.circle and TB.ccMenu.rows.moon,
    "Marks panel must expose one row per raid icon")
assert(TB.ccMenu.rows.circle.ownerText.text == "Alpha",
    "panel rows must show the current owner from the assignment cache")
-- Owner cycler sends an explicit-name intent and the panel stays open.
-- Candidates sort Alpha,Gamma; circle is owned by Alpha, so Next wraps to Gamma.
now = now + 1
this = TB.ccMenu.rows.circle.cycle
TB.ccMenu.rows.circle.cycle.scripts.OnClick(TB.ccMenu.rows.circle.cycle)
assert(sent[table.getn(sent)] == ".bot action cc circle Gamma",
    "cycling Circle must send the explicit-name CC intent")
assert(TB.ccMenu:IsVisible(), "Marks panel must stay open for batch assignment")
-- Exclusive ownership: the ACK moves the mark and evicts the old owner.
TB.OnSystemMessage("TBM:ACTION_ACK|cc circle Alpha|bot:Alpha|1|Alpha")
assert(TB.GetCcAssignment("Alpha") == "circle",
    "CC ACK must update the visible bot assignment")
TB.OnSystemMessage("TBM:ACTION_ACK|cc circle Gamma|bot:Gamma|1|Gamma")
assert(TB.GetCcAssignment("Gamma") == "circle" and TB.GetCcAssignment("Alpha") == nil,
    "exclusive ownership must evict the previous cached owner")
-- Row clear button clears only that mark's owner by name.
now = now + 1
this = TB.ccMenu.rows.circle.clear
TB.ccMenu.rows.circle.clear.scripts.OnClick(TB.ccMenu.rows.circle.clear)
assert(sent[table.getn(sent)] == ".bot action cc clear Gamma",
    "row Clear must send cc clear for the current owner")
TB.OnSystemMessage("TBM:ACTION_ACK|cc clear Gamma|bot:Gamma|1|Gamma")
assert(TB.GetCcAssignment("Gamma") == nil,
    "clear ACK must drop the named owner from the cache")
-- Clear-all button dismisses every owner at once.
TB.OnSystemMessage("TBM:ACTION_ACK|cc moon Tester|bot:Alpha|1|Alpha")
assert(TB.GetCcOwner("moon") == "Alpha", "panel owner lookup must find the moon owner")
now = now + 1
this = TB.ccMenu.clearAll
TB.ccMenu.clearAll.scripts.OnClick(TB.ccMenu.clearAll)
assert(sent[table.getn(sent)] == ".bot action cc clear",
    "Clear all must send the bare cc clear intent")
TB.OnSystemMessage("TBM:ACTION_ACK|cc clear|party|2|Alpha")
assert(TB.GetCcOwner("moon") == nil,
    "party-scoped clear ACK must empty the assignment cache")
targetNameValue = "Enemy"
TB.Refresh()
now = now + 1
local beforePull = table.getn(sent)
this = TB.actionButtons.pull
TB.actionButtons.pull.scripts.OnClick(TB.actionButtons.pull)
assert(table.getn(sent) == beforePull + 1 and sent[table.getn(sent)] == ".bot action pull",
    "Pull must send the supported ordinary-pull intent")

-- Adjustable pull timers: persisted settings, clamped steppers, CAPS-gated
-- seconds. Old servers (no CAPS line) keep the plain intents above.
assert(TortoiseBotsDB.pullDelay == 10 and TortoiseBotsDB.pullbackDelay == 3,
    "pull timers must default to 10 s / 3 s in SavedVariables")
assert(TB.pullTimers and TB.pullTimers.pull and TB.pullTimers.pullback,
    "pull steppers must exist under the Pull buttons")
assert(TB.pullTimers.pull.label.text == "10 s" and TB.pullTimers.pullback.label.text == "3 s",
    "stepper labels must show the persisted delays")
assert(TB.ClampPullSeconds(-4) == 0 and TB.ClampPullSeconds(61) == 60
    and TB.ClampPullSeconds(7.6) == 8 and TB.ClampPullSeconds("abc") == 0,
    "timer values must clamp to whole seconds in 0-60")
assert(TB.PullIntent("pull") == "pull" and TB.PullIntent("pullback") == "pullback",
    "without the capability Pull intents must stay plain")
assert(chatFilters.CHAT_MSG_SYSTEM(nil, nil, "TBM:CAPS|pull-seconds") == true,
    "CAPS trailer must be hidden from chat like other TBM: lines")
TB.OnSystemMessage("TBM:CAPS|pull-seconds")
assert(TB.PullIntent("pull") == "pull 10" and TB.PullIntent("pullback") == "pullback 3",
    "with the capability Pull intents must carry the persisted seconds")
-- Stepper bumps persist and repaint the "- N s +" label.
TortoiseBotsDB.pullDelay = TB.ClampPullSeconds(TortoiseBotsDB.pullDelay + 1)
TB.pullTimers.pull.repaint()
assert(TortoiseBotsDB.pullDelay == 11 and TB.pullTimers.pull.label.text == "11 s",
    "stepper bump must persist and repaint the label")
TortoiseBotsDB.pullDelay = TB.ClampPullSeconds(TortoiseBotsDB.pullDelay - 5)
TB.pullTimers.pull.repaint()
assert(TortoiseBotsDB.pullDelay == 6 and TB.pullTimers.pull.label.text == "6 s",
    "shift-click step of 5 must persist and repaint the label")
TortoiseBotsDB.pullDelay = 10
TB.pullTimers.pull.repaint()
-- Pull button sends seconds while the capability holds.
now = now + 1
local beforeTimedPull = table.getn(sent)
this = TB.actionButtons.pull
TB.actionButtons.pull.scripts.OnClick(TB.actionButtons.pull)
assert(table.getn(sent) == beforeTimedPull + 1 and sent[table.getn(sent)] == ".bot action pull 10",
    "Pull must send the timed intent while the server supports pull-seconds")
-- Mixed and unknown capability lists parse robustly.
TB.OnSystemMessage("TBM:CAPS|foo, pull-seconds|bar baz")
assert(TB.HasServerCapability("pull-seconds") and TB.HasServerCapability("foo")
    and TB.HasServerCapability("bar") and TB.HasServerCapability("baz"),
    "CAPS lists must parse comma/pipe/space separated entries")
TB.OnSystemMessage("TBM:CAPS|")
assert(not TB.HasServerCapability("pull-seconds"),
    "an empty CAPS line must clear capabilities")
TB.OnSystemMessage("TBM:CAPS|pull-seconds")
-- Pullback button likewise (clock advanced past the send throttle).
now = now + 1
local beforeTimedBack = table.getn(sent)
this = TB.actionButtons.pullback
TB.actionButtons.pullback.scripts.OnClick(TB.actionButtons.pullback)
assert(table.getn(sent) == beforeTimedBack + 1 and sent[table.getn(sent)] == ".bot action pullback 3",
    "Pull back must send the timed intent while the server supports pull-seconds")
now = now + 1
local beforeInterrupt = table.getn(sent)
this = TB.actionButtons.interrupt
TB.actionButtons.interrupt.scripts.OnClick(TB.actionButtons.interrupt)
assert(table.getn(sent) == beforeInterrupt + 1 and sent[table.getn(sent)] == ".bot action interrupt",
    "Interrupt must send one executor intent")
now = now + 1
this = TB.actionButtons.come
TB.actionButtons.come.scripts.OnClick(TB.actionButtons.come)
assert(sent[table.getn(sent)] == ".bot action come", "Come button must send action come")
now = now + 1
this = TB.actionButtons.guard
TB.actionButtons.guard.scripts.OnClick(TB.actionButtons.guard)
assert(sent[table.getn(sent)] == ".bot action guard", "Guard button must send action guard")
now = now + 1
this = TB.actionButtons.free
TB.actionButtons.free.scripts.OnClick(TB.actionButtons.free)
assert(sent[table.getn(sent)] == ".bot action free", "Free button must send action free")
now = now + 1
this = TB.stancePills.tank
TB.stancePills.tank.scripts.OnClick(TB.stancePills.tank)
assert(sent[table.getn(sent)] == ".bot action stance tank", "Tank stance pill must send stance tank")
assert(TB.currentStance == "tank" and TB.stancePills.tank.isActive and not TB.stancePills.near.isActive,
    "Active stance pill must become disabled")
TB.OnSystemMessage("TBM:ACTION_ACK|stance|party|2|tank")
assert(TB.lastActionAck and TB.lastActionAck.intent == "stance" and TB.lastActionAck.executor == "tank",
    "structured stance ACK must be parsed")
TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
TB.OnSystemMessage("TBM:BOTSTATE|Alpha|move=guard,loot=on,aoe=off,autocc=off,savemana=off,boost=on,threat=on,potions=on")
TB.OnSystemMessage("TBM:BOTSTATE_END")
assert(TB.MovementLabel("Alpha") == "Guarding", "guard movement must be labelled")

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
TB.OnSystemMessage("TBM:ACTION_ACK|interrupt|party|1|Arcana")
assert(TB.lastActionAck and TB.lastActionAck.intent == "interrupt"
    and TB.lastActionAck.executor == "Arcana",
    "structured interrupt ACK must be parsed")
TB.OnSystemMessage("TBM:ACTION_ERR|interrupt|not-casting|The target is not casting")
assert(TB.lastActionError and TB.lastActionError.intent == "interrupt"
    and TB.lastActionError.code == "not-casting",
    "structured interrupt ERR must be parsed")

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

-- Party view and role button test
partyMembers = { "Priestbot" }
TB.ShowTab("party")
TB.RefreshPartyView()
assert(TB.partyFrame.rows[1]:IsVisible(), "Player row must be visible")
assert(TB.partyFrame.rows[1].playerLabel:IsVisible(), "Player row must show player label")
local playerRow = TB.partyFrame.rows[1]
assert(playerRow.roleButtons[1]:IsVisible() and playerRow.roleButtons[2]:IsVisible(),
    "Player role buttons must be visible for the current class")
assert(type(playerRow.roleButtons[1].scripts.OnClick) == "function",
    "Player role button must have a click handler")
now = now + 1
local beforePlayerRole = table.getn(sent)
playerRow.roleButtons[1].scripts.OnClick()
assert(TortoiseBotsDB.playerRole == "tank",
    "Clicking the player Tank role must persist the selected role")
assert(table.getn(sent) == beforePlayerRole + 1 and sent[table.getn(sent)] == ".bot role self tank",
    "Clicking the player Tank role must send the self role command")
assert(playerRow.roleButtons[1].isActive and playerRow.roleButtons[1].text:find("Tank"),
    "Selected player role button must be highlighted gold")
assert(TB.partyFrame.rows[2]:IsVisible(), "Priestbot party row must be visible")
assert(TB.partyFrame.rows[2].nameText.text == "Priestbot", "Party row 2 must display Priestbot")
assert(TB.partyFrame.rows[2].roleButtons[1]:IsVisible() and TB.partyFrame.rows[2].roleButtons[1].text:find("Holy"),
    "Priestbot must have Holy role button")
assert(TB.partyFrame.rows[2].roleButtons[3]:IsVisible() and TB.partyFrame.rows[2].roleButtons[3].text:find("Shadow"),
    "Priestbot must have Shadow role button")

-- Click Shadow role button
now = now + 1
local beforeRoleCmd = table.getn(sent)
TB.partyFrame.rows[2].roleButtons[3].scripts.OnClick()
assert(TortoiseBotsDB.botRoles["Priestbot"] == "dps", "Priestbot role must be stored as dps")
assert(table.getn(sent) == beforeRoleCmd + 1 and sent[table.getn(sent)] == ".bot strategy +shadow,-holy,-discipline,-offdps Priestbot",
    "Clicking Shadow role must send Playerbot strategy command")
assert(TB.partyFrame.rows[2].roleButtons[3].isActive, "Selected Shadow button must be filled gold")

-- Tank designation uses the explicit role command (forced role + pull kit).
partyClassName = "Warrior"
partyMembers = { "Tankbot" }
TB.RefreshPartyView()
assert(TB.partyFrame.rows[2].nameText.text == "Tankbot", "Party row 2 must display Tankbot")
assert(TB.partyFrame.rows[2].roleButtons[1]:IsVisible() and TB.partyFrame.rows[2].roleButtons[1].text:find("Prot"),
    "Tankbot must have Protection role button")
now = now + 1
local beforeTankCmd = table.getn(sent)
TB.partyFrame.rows[2].roleButtons[1].scripts.OnClick()
assert(TortoiseBotsDB.botRoles["Tankbot"] == "tank", "Tankbot role must be stored as tank")
assert(table.getn(sent) == beforeTankCmd + 1 and sent[table.getn(sent)] == ".bot role Tankbot tank",
    "Clicking Tank role must send the explicit role command")
-- Demotion clears the stale forced tank before the spec strategy is applied.
-- Two commands in the same tick: first sends, second queues on SEND_DELAY.
now = now + 1
local beforeDemoteCmd = table.getn(sent)
TB.partyFrame.rows[2].roleButtons[2].scripts.OnClick()
assert(TortoiseBotsDB.botRoles["Tankbot"] == "dps", "Tankbot role must be stored as dps")
assert(table.getn(sent) == beforeDemoteCmd + 1
    and sent[table.getn(sent)] == ".bot role Tankbot clear",
    "Demotion from Tank must clear the forced role first")
now = now + 1
local queueFrame = frames["TortoiseBotsManagerQueueFrame"]
assert(queueFrame, "demotion spec strategy must queue behind the throttle")
this, arg1 = queueFrame, 0.1
queueFrame.scripts.OnUpdate(queueFrame)
assert(table.getn(sent) == beforeDemoteCmd + 2
    and sent[table.getn(sent)] == ".bot strategy +arms,-protection,-fury Tankbot",
    "Demotion spec strategy must follow after the throttle clears")
partyClassName = "Priest"
partyMembers = { "Priestbot" }
TB.RefreshPartyView()

TB.SetCcAssignment("Priestbot", "moon")
TB.RefreshPartyView()
assert(TB.partyFrame.rows[2].ccMark == "moon" and TB.partyFrame.rows[2].ccIcon:IsVisible(),
    "Party view must show the assigned CC icon beside each bot")
assert(TB.partyFrame.rows[2].ccIcon.texture[1] == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    "Party CC icon must match the assigned raid mark")
assert(TB.partyFrame.rows[2].ccIcon.point[1] == "BOTTOMRIGHT"
    and TB.partyFrame.rows[2].roleButtons[4].point[5] == 8,
    "CC icon must be reflowed below the role-button row")

-- Four-role rows reserve the lower-right CC column instead of letting the
-- fourth role button obscure the assigned mark (Druid is the current case).
partyClassName = "Druid"
TB.RefreshPartyView()
local druidRow = TB.partyFrame.rows[2]
assert(druidRow.roleButtons[4]:IsVisible()
    and druidRow.roleButtons[4].width == 70
    and druidRow.roleButtons[4].point[4] + druidRow.roleButtons[4].width <= 440,
    "Four-role rows must leave a dedicated column for the CC icon")
assert(druidRow.ccIcon.point[1] == "BOTTOMRIGHT"
    and druidRow.ccIcon.point[5] == 4
    and druidRow.ccLabel.point[1] == "BOTTOMRIGHT",
    "CC indicator must occupy the lower-right row slot")

-- ── addon command transport ────────────────────────────────────────────────
-- UI commands travel as addon messages only while the server says the core
-- dispatches them for this group (TBM:TRANSPORT|party). Until a verdict
-- arrives, after a group change, or when it reads "none", the ".bot" chat
-- transport stays.
TB.InvalidateAddonTransport()
now = now + 1
local beforeUnknownChat = table.getn(sent)
local beforeUnknownAddon = table.getn(addonSent)
TB.SendActionIntent("stay")
assert(table.getn(sent) == beforeUnknownChat + 1 and sent[table.getn(sent)] == ".bot action stay",
    "without a server verdict UI commands must keep using .bot chat")
assert(table.getn(addonSent) == beforeUnknownAddon,
    "no addon message may be sent before the server advertises the channel")

TB.OnSystemMessage("TBM:TRANSPORT|party")
now = now + 1
local beforePartyAddon = table.getn(addonSent)
local beforePartyChat = table.getn(sent)
TB.SendActionIntent("attack")
assert(table.getn(addonSent) == beforePartyAddon + 1,
    "the party verdict must send the command over the addon channel")
local addonCommand = addonSent[table.getn(addonSent)]
assert(addonCommand.prefix == "TBM" and addonCommand.message == "action attack"
    and addonCommand.channel == "PARTY",
    "addon command must carry the TBM prefix, the bare command and PARTY")
assert(table.getn(sent) == beforePartyChat, "addon transport must not also send a chat echo")

-- Replies on the addon channel are parsed exactly like system replies.
TB.OnAddonMessage("TBM", "TBM:ACTION_ACK|attack|party|2|-", "GUILD", "Tester")
assert(TB.lastActionAck and TB.lastActionAck.intent == "attack" and TB.lastActionAck.count == 2,
    "addon-channel replies must feed the structured parser")

-- A group change invalidates the verdict until the next roster reply.
local groupWatcher = frames["TortoiseBotsManagerGroupWatcher"]
assert(groupWatcher, "group watcher must exist")
event = "PARTY_MEMBERS_CHANGED"
groupWatcher.scripts.OnEvent(groupWatcher)
now = now + 1
local beforeStaleAddon = table.getn(addonSent)
local beforeStaleChat = table.getn(sent)
TB.SendActionIntent("come")
assert(table.getn(addonSent) == beforeStaleAddon,
    "a verdict invalidated by a group change must not use the addon channel")
assert(table.getn(sent) == beforeStaleChat + 1 and sent[table.getn(sent)] == ".bot action come",
    "a verdict invalidated by a group change must fall back to .bot chat")

-- Re-learned over the addon channel itself: the steady state once live.
TB.OnAddonMessage("TBM", "TBM:TRANSPORT|party", "GUILD", "Tester")
now = now + 1
local beforeRelearnAddon = table.getn(addonSent)
TB.SendActionIntent("focus skull")
assert(table.getn(addonSent) == beforeRelearnAddon + 1
    and addonSent[table.getn(addonSent)].message == "action focus skull",
    "an addon-delivered verdict must restore the addon transport")

-- "none" is a hard no: battleground group without a pre-battleground group.
TB.OnSystemMessage("TBM:TRANSPORT|none")
assert(TB.AddonCommandChannel() == nil, "the none verdict must not expose a channel")
now = now + 1
local beforeNoneChat = table.getn(sent)
local beforeNoneAddon = table.getn(addonSent)
TB.SendActionIntent("stay")
assert(table.getn(addonSent) == beforeNoneAddon
    and table.getn(sent) == beforeNoneChat + 1 and sent[table.getn(sent)] == ".bot action stay",
    "the none verdict must keep using .bot chat")

-- Version line: addon version on load, server version from TBM:VERSION.
assert(TB.versionLine and TB.versionLine.text == "TBM " .. TB.version .. " · server ? · by Sagiroth",
    "window must show addon version with unknown server before any reply")
assert(TB.versionTitle and string.find(TB.versionTitle.text, "v" .. TB.version, 1, true),
    "window title must carry the addon version")
TB.OnSystemMessage("TBM:VERSION|2026-09-25-v7")
assert(TB.serverVersion == "2026-09-25-v7", "TBM:VERSION must record the server build")
assert(TB.versionLine.text == "TBM " .. TB.version .. " · server 2026-09-25-v7 · by Sagiroth",
    "window must show both versions after the roster trailer")
TB.OnSystemMessage("TBM:TRANSPORT|party")
TB.serverVersion = nil
if TB.RefreshVersionLine then TB.RefreshVersionLine() end
assert(TB.versionLine.text == "TBM " .. TB.version .. " · server ? · by Sagiroth",
    "window must fall back to server ? without a version reply")
TB.OnSystemMessage("TBM:VERSION|2026-09-25-v7")
-- Older servers stay silent: unknown commands must not clobber the version.
TB.OnSystemMessage("Unknown bot command 'version'. Try .bot help")
assert(TB.serverVersion == "2026-09-25-v7",
    "unknown-command fallback must not clear a known server version")

-- Only the module prefix is a command reply; other addon prefixes stay on the
-- legacy AI-reply path.
-- Drag header isolation & safe position persistence (avoids 1.12 C++ GetPoint crash)
assert(TB.dragHeader and TB.dragHeader.scripts and TB.dragHeader.scripts["OnDragStart"],
    "drag header must have OnDragStart registered")
assert(TB.dragHeader.scripts["OnDragStop"], "drag header must have OnDragStop registered")
assert(not TB.frame.scripts["OnDragStart"], "main frame must not intercept window drag directly")
assert(not TB.frame.scripts["OnDragStop"], "main frame must not intercept window drag directly")
TB.dragHeader.scripts["OnDragStart"]()
TB.dragHeader.scripts["OnDragStop"]()
assert(TortoiseBotsDB.frame and TortoiseBotsDB.frame.point == "TOPLEFT",
    "OnDragStop must persist TOPLEFT position without crashing or calling GetPoint")
-- Issue #33: the mouse-enabled drag bar must end left of the Mini button and
-- both header buttons must sit above it, or the bar eats Mini clicks in 1.12.
assert(TB.dragHeader:GetNumPoints() == 2, "drag bar must keep two anchors after the Mini fix")
local barRight, barAnchor = TB.dragHeader:GetPoint(2)
assert(barRight == "BOTTOMRIGHT" and barAnchor == TB.infoButton,
    "drag bar must end at the Info button instead of spanning the header corner")
assert(TB.infoButton:GetFrameLevel() > TB.dragHeader:GetFrameLevel(),
    "Info must sit above the drag bar to receive clicks")
assert(TB.miniButton:GetFrameLevel() > TB.dragHeader:GetFrameLevel(),
    "Mini must sit above the drag bar to receive clicks")


-- ── Flee, party switches, out-of-combat chores ─────────────────────────────
local function lastAddon() return addonSent[table.getn(addonSent)].message end
TB.OnSystemMessage("TBM:TRANSPORT|party")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
assert(TB.HasServerCapability("flee") and TB.HasServerCapability("inventory"), "new caps must parse")
TB.Refresh()
assert(TB.actionButtons.flee and TB.actionButtons.flee.enabled, "Flee must be enabled when advertised")
now = now + 1
this = TB.actionButtons.flee
TB.actionButtons.flee.scripts.OnClick(TB.actionButtons.flee)
assert(lastAddon() == "action flee", "Flee must send the flee intent")
TB.OnSystemMessage("TBM:CAPS|pull-seconds")
TB.Refresh()
assert(not TB.actionButtons.flee.enabled, "Flee must be disabled on servers without the capability")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")

-- Downtime: capability-gated direct command for own alts.
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime")
TB.Refresh()
assert(TB.actionButtons.downtime and TB.actionButtons.downtime.enabled, "Downtime must be enabled when advertised")
now = now + 1
this = TB.actionButtons.downtime
TB.actionButtons.downtime.scripts.OnClick(TB.actionButtons.downtime)
assert(lastAddon() == "downtime", "Downtime must send the direct downtime command")
TB.OnSystemMessage("TBM:ACTION_ACK|downtime|party|2|-")
assert(TB.lastActionAck and TB.lastActionAck.intent == "downtime"
    and TB.lastActionAck.scope == "party" and TB.lastActionAck.count == 2,
    "downtime ACK must parse like other actions")
TB.OnSystemMessage("TBM:ACTION_ERR|downtime|refused|Gamma is a hired companion, not one of your own alts.")
assert(TB.lastActionError and TB.lastActionError.intent == "downtime"
    and TB.lastActionError.code == "refused",
    "downtime ERR must parse like other actions")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
TB.Refresh()
assert(not TB.actionButtons.downtime.enabled, "Downtime must be disabled on servers without the capability")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime")

-- Live specs pick the shown role (a hire has no saved role); values may hold spaces.
TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|7")
TB.OnSystemMessage("TBM:BOTSTATE|Rista|move=follow,specs=retribution")
TB.OnSystemMessage("TBM:BOTSTATE|Feyrielle|move=follow,specs=balance")
TB.OnSystemMessage("TBM:BOTSTATE|Holybot|move=follow,specs=holy+offdps")
TB.OnSystemMessage("TBM:BOTSTATE|Discbot|move=follow,specs=discipline")
TB.OnSystemMessage("TBM:BOTSTATE|Shamtank|move=follow,specs=tank shaman")
TB.OnSystemMessage("TBM:BOTSTATE|Furybot|move=follow,specs=fury")
TB.OnSystemMessage("TBM:BOTSTATE|Catbot|move=follow,specs=dps feral")
TB.OnSystemMessage("TBM:BOTSTATE_END")
assert(TB.Roles.GetBotRole("Rista", 2) == "dps", "retribution specs must show the paladin DPS role")
assert(TB.Roles.GetBotRole("Feyrielle", 11) == "boomkin", "balance specs must show Balance")
assert(TB.Roles.GetBotRole("Holybot", 5) == "heal", "a holy hire (holy+offdps) must show Holy")
assert(TB.Roles.GetBotRole("Discbot", 5) == "disc", "discipline specs must show Discipline")
assert(TB.Roles.GetBotRole("Shamtank", 7) == "tank", "the shaman tank kit must show Enh Tank")
assert(TB.Roles.GetBotRole("Furybot", 1) == "fury", "fury specs must show Fury")
assert(TB.Roles.GetBotRole("Catbot", 11) == "cat", "a spec with a space must parse")

-- Move modes: the shared mode lights up, an ACK moves it, Come waits for the poll.
partyMembers = { "Alpha", "Gamma" }
TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|2")
TB.OnSystemMessage("TBM:BOTSTATE|Alpha|move=follow")
TB.OnSystemMessage("TBM:BOTSTATE|Gamma|move=follow")
TB.OnSystemMessage("TBM:BOTSTATE_END")
assert(TB.actionButtons.follow.isActive and not TB.actionButtons.guard.isActive,
    "the shared move mode must be highlighted")
TB.OnSystemMessage("TBM:ACTION_ACK|guard|party|2|-")
assert(TB.actionButtons.guard.isActive and not TB.actionButtons.follow.isActive,
    "a guard ACK must move the highlight")
TB.OnSystemMessage("TBM:ACTION_ACK|stay|bot:Alpha|1|-")
assert(not TB.actionButtons.guard.isActive and not TB.actionButtons.stay.isActive,
    "a mixed party highlights no mode")
TB.OnSystemMessage("TBM:ACTION_ACK|come|party|2|-")
assert(TB.GetBotState("Gamma").move == "guard", "Come must not guess the end mode")

-- BOTSTATE drives the switches; a mixed party shows "~" and turns on.
TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|2")
TB.OnSystemMessage("TBM:BOTSTATE|Alpha|move=follow,loot=on,aoe=off,autocc=off,savemana=off,boost=on,threat=on,potions=on")
TB.OnSystemMessage("TBM:BOTSTATE|Gamma|move=flee,loot=off,aoe=off,autocc=off,savemana=on,boost=on,threat=on,potions=on")
TB.OnSystemMessage("TBM:BOTSTATE_END")
assert(TB.GetBotState("Alpha").move == "follow" and TB.GetBotState("gamma").savemana == "on",
    "BOTSTATE rows must be stored per bot")
assert(TB.GetPartyToggleState("loot") == "mixed" and TB.GetPartyToggleState("aoe") == "off",
    "party switch state must aggregate the bots")
assert(TB.toggleButtons.loot.text == "|cffffd200Loot ~|r" and (not TB.toggleButtons.autocc.isActive),
    "switch labels must show the server state (~ for mixed)")
assert(TB.MovementLabel("Gamma") == "Fleeing (passive)", "flee movement must be labelled")
now = now + 1
this = TB.toggleButtons.loot
TB.toggleButtons.loot.scripts.OnClick(TB.toggleButtons.loot)
assert(lastAddon() == "action loot on", "a mixed switch must turn on")
assert(not TB.toggleButtons.loot.enabled, "a switch waits for the server while pending")
TB.OnSystemMessage("TBM:ACTION_ACK|loot|party|2|on")
assert(TB.GetPartyToggleState("loot") == "on" and TB.toggleButtons.loot.enabled
    and TB.toggleButtons.loot.isActive, "the ACK must settle the switch")
now = now + 1
this = TB.toggleButtons.autocc
TB.toggleButtons.autocc.scripts.OnClick(TB.toggleButtons.autocc)
assert(lastAddon() == "action auto cc on", "Auto CC must send the auto cc intent")
TB.OnSystemMessage("TBM:ACTION_ERR|auto cc|failed|No scoped bot accepted")
assert(TB.GetPartyToggleState("autocc") == "off" and TB.toggleButtons.autocc.enabled,
    "a refused switch must not drift")
-- A single-bot ACK only changes that bot.
TB.OnSystemMessage("TBM:ACTION_ACK|aoe|bot:Alpha|1|on")
assert(TB.GetBotState("Alpha").aoe == "on" and TB.GetBotState("Gamma").aoe == "off"
    and TB.toggleButtons.aoe.text == "|cffffd200AoE ~|r", "a targeted switch must only update that bot")

-- P2: sap joins the switch row, spread rides the behavior verb, and the
-- row of five stays inside the 480-wide content.
assert(TB.toggleButtons.sap and TB.toggleButtons.spread, "sap and spread switches must exist")
local switchCount = 0
for _ in pairs(TB.toggleButtons) do switchCount = switchCount + 1 end
assert(switchCount == 5, "the switches card must hold exactly five toggles")
for _, btn in pairs(TB.toggleButtons) do
    assert(btn.point and btn.point[4] >= 0 and (btn.point[4] + (btn.width or 0)) <= 480,
        "every switch button must fit the 480-wide content")
end
TB.OnSystemMessage("TBM:BOTSTATE|Alpha|move=follow,loot=on,aoe=on,autocc=off,savemana=off,boost=on,threat=on,potions=on,sap=off,spread=off")
TB.OnSystemMessage("TBM:BOTSTATE|Gamma|move=flee,loot=on,aoe=on,autocc=off,savemana=on,boost=on,threat=on,potions=on,sap=off,spread=off")
now = now + 1
this = TB.toggleButtons.sap
TB.toggleButtons.sap.scripts.OnClick(TB.toggleButtons.sap)
assert(lastAddon() == "action sap on", "Sap must send the sap intent")
TB.OnSystemMessage("TBM:ACTION_ACK|sap|party|2|on")
assert(TB.GetPartyToggleState("sap") == "on" and TB.toggleButtons.sap.enabled
    and TB.toggleButtons.sap.isActive, "the sap ACK must settle the switch")
now = now + 1
this = TB.toggleButtons.spread
TB.toggleButtons.spread.scripts.OnClick(TB.toggleButtons.spread)
assert(lastAddon() == "behavior party spread on", "Spread must ride the behavior verb")
assert(not TB.toggleButtons.spread.enabled, "spread waits for the server while pending")
TB.OnSystemMessage("TBM:ACTION_ACK|behavior spread|party|2|on")
assert(TB.GetPartyToggleState("spread") == "on" and TB.toggleButtons.spread.enabled
    and TB.toggleButtons.spread.isActive, "the spread ACK must settle the switch")
TB.OnSystemMessage("TBM:ACTION_ERR|behavior spread|failed|No scoped bot accepted")
assert(TB.toggleButtons.spread.enabled, "a refused spread switch must not stick disabled")

-- P2: End pull and the four tactics buttons send their intents; the server
-- confirms tactics with "Strategy change" text.
now = now + 1
this = TB.actionButtons.endPull
TB.actionButtons.endPull.scripts.OnClick(TB.actionButtons.endPull)
assert(lastAddon() == "action end pull", "End pull must send the end pull intent")
for _, tactic in ipairs({ "tacticKite", "tacticMark", "tacticFocus", "tacticAoeFear" }) do
    now = now + 1
    this = TB.actionButtons[tactic]
    TB.actionButtons[tactic].scripts.OnClick(TB.actionButtons[tactic])
end
assert(lastAddon() == "strategy ~aoe fear", "tactics must send suffixless strategy changes")
local beforeStrategyOps = 0
for _, st in pairs({ TB.GetState("Alpha"), TB.GetState("Gamma") }) do
    if st and st.operation then beforeStrategyOps = beforeStrategyOps + 1 end
end
TB.OnSystemMessage("Strategy change '~kite' applied to 2 bot(s).")
assert(TB.lastSystem == "Strategy change '~kite' applied to 2 bot(s).",
    "a strategy change must be consumed as handled")
local afterStrategyOps = 0
for _, st in pairs({ TB.GetState("Alpha"), TB.GetState("Gamma") }) do
    if st and st.operation then afterStrategyOps = afterStrategyOps + 1 end
end
assert(afterStrategyOps == beforeStrategyOps, "a strategy reply must not start roster operations")

-- Layout: every Fight card keeps its re-stacked slot (no overlaps) and every
-- control fits the 360px content frame, with 8 px between cards.
local fightOrder = { "engage", "pull", "move", "switches", "tactics" }
local fightTops = { engage = -40, pull = -96, move = -172, switches = -252, tactics = -308 }
local fightHeights = { engage = 48, pull = 68, move = 72, switches = 48, tactics = 48 }
local fightBottom = { engage = 0, pull = 0, move = 0, switches = 0, tactics = 0 }
for _, id in ipairs(fightOrder) do
    local card = TB.fightCards[id]
    local _, _, _, _, top = card:GetPoint(1)
    assert(top == fightTops[id] and card.height == fightHeights[id],
        "fight card " .. id .. " must keep its integrated slot")
    assert(top <= 0 and -(top - card.height) <= 360, "fight card " .. id .. " must fit the 360px content")
    fightBottom[id] = top - card.height
end
for i = 2, table.getn(fightOrder) do
    assert(fightTops[fightOrder[i]] <= fightBottom[fightOrder[i - 1]],
        "fight card " .. fightOrder[i] .. " must start below " .. fightOrder[i - 1])
end
local function cardBottom(control, cardTop)
    local _, _, _, _, top = control:GetPoint(1)
    return cardTop + top - (control.height or 0)
end
local moveIds = { "follow", "stay", "come", "guard", "free" }
for _, id in ipairs(moveIds) do
    local btn = TB.actionButtons[id]
    assert(cardBottom(btn, fightTops.move) >= -360, "move control " .. id .. " must fit the 360px content")
end
for id, pill in pairs(TB.stancePills) do
    assert(cardBottom(pill, fightTops.move) >= -360, "stance pill " .. id .. " must fit the 360px content")
end
for key, btn in pairs(TB.toggleButtons) do
    assert(cardBottom(btn, fightTops.switches) >= -360, "switch " .. key .. " must fit the 360px content")
end
for _, id in ipairs({ "tacticKite", "tacticMark", "tacticFocus", "tacticAoeFear" }) do
    assert(cardBottom(TB.actionButtons[id], fightTops.tactics) >= -360,
        "tactic " .. id .. " must fit the 360px content")
end
for _, id in ipairs({ "attack", "stop", "interrupt", "flee" }) do
    assert(cardBottom(TB.actionButtons[id], fightTops.engage) >= -360,
        "engage control " .. id .. " must fit the 360px content")
end
assert(cardBottom(TB.actionButtons.endPull, fightTops.pull) >= -360, "end pull must fit the 360px content")
-- Release follows the party's death state.
TB.Refresh()
assert(not TB.actionButtons.release.enabled, "Release is idle while everyone lives")
deadUnits.party1 = true
TB.Refresh()
assert(TB.actionButtons.release.enabled and TB.actionButtons.release.text == "Release",
    "a dead bot enables Release")
deadUnits.party1 = nil
ghostUnits.party1 = true
TB.Refresh()
assert(TB.actionButtons.release.text == "Corpse run", "a ghost turns the button into Corpse run")
now = now + 1
this = TB.actionButtons.release
TB.actionButtons.release.scripts.OnClick(TB.actionButtons.release)
assert(lastAddon() == "action corpse run", "Corpse run must send the corpse run intent")
ghostUnits.party1 = nil
for _, intent in ipairs({ "rest", "repair", "sell", "learn" }) do
    now = now + 1
    this = TB.actionButtons[intent]
    TB.actionButtons[intent].scripts.OnClick(TB.actionButtons[intent])
    assert(lastAddon() == "action " .. intent, intent .. " must send its action intent")
end
assert(TB.formationPills.line, "the Line formation must be offered")

-- ── Party row bag button and the bot panel ─────────────────────────────────
TB.ShowTab("party")
local alphaRow
for _, row in ipairs(TB.partyFrame.rows) do
    if row.partyName == "Alpha" then alphaRow = row end
end
assert(alphaRow and alphaRow.bagButton.visible, "controllable bots get a bag button")
assert(string.find(alphaRow.descText.text, "Following", 1, true), "party rows show the movement mode")
assert(not TB.partyFrame.rows[1].bagButton.visible, "the player row has no bag button")
now = now + 1
alphaRow.bagButton.scripts.OnClick(alphaRow.bagButton)
assert(TB.botPanel and TB.botPanel.visible and TB.GetBotPanelBot() == "Alpha", "the bag button opens the panel")
assert(lastAddon() == "inv Alpha", "opening the panel requests the inventory")
local alphaOperation = TB.GetState("Alpha") and TB.GetState("Alpha").operation
assert(not alphaOperation or alphaOperation.verb ~= "inv",
    "an inventory request must not start a roster operation")

itemCache[159] = { name = "Refreshing Spring Water", quality = 1, texture = "Interface\\Icons\\INV_Drink_07" }
itemCache[2586] = { name = "Gamemaster's Robe", quality = 4, texture = "Interface\\Icons\\INV_Chest_Cloth_05" }
TB.OnSystemMessage("TBM:INV_BEGIN|Alpha|123456")
TB.OnSystemMessage("TBM:INV_EQ|4|2586|40|50")
TB.OnSystemMessage("TBM:INV_ITEM|255|23|6948|1|b")
TB.OnSystemMessage("TBM:INV_ITEM|20|3|1201|1|eu")
TB.OnSystemMessage("TBM:INV_ITEM|20|4|159|5|-")
TB.OnSystemMessage("TBM:INV_END|Alpha|30|46")
local inv = TB.GetInventory("Alpha")
assert(inv and inv.money == 123456 and inv.free == 30 and inv.total == 46
    and table.getn(inv.items) == 3 and inv.equipped[4].id == 2586, "inventory snapshot must parse")
assert(inv.items[2].equippable and inv.items[2].upgrade and inv.items[1].noTrade, "item flags must parse")
local chest = TB.botPanel.gearButtons[4]
assert(chest.entry and chest.entry.id == 2586 and chest.icon.texture[1] == "Interface\\Icons\\INV_Chest_Cloth_05",
    "equipped items render in their paper-doll slot")
assert(string.find(TB.botPanel.tabBags.text, "3", 1, true), "the Bags tab counts the items")

-- Gear: click → Unequip.
local menu = frames["TortoiseBotsManagerItemMenu"]
this = chest
chest.scripts.OnClick(chest)
assert(menu.visible and menu.first.text == "Unequip" and not menu.second.visible, "gear items offer Unequip")
now = now + 1
this = menu.first
menu.first.scripts.OnClick(menu.first)
assert(lastAddon() == "item Alpha unequip 255 4", "Unequip must address the equipment slot")

-- Bags: equip an upgrade, give a tradeable item.
TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
local upgrade = TB.botPanel.bagButtons[2]
assert(upgrade.visible and upgrade.entry.id == 1201 and upgrade.badge.visible, "upgrades are marked in the bag grid")
assert(not TB.botPanel.bagButtons[4].visible, "empty grid cells stay hidden")
this = upgrade
upgrade.scripts.OnClick(upgrade)
assert(menu.first.text == "Equip" and menu.first.enabled and menu.second.enabled, "bag items offer Equip and Give")
assert(menu.third.visible and menu.third.text == "Use", "bag items offer Use")
assert(menu.fourth.visible and menu.fourth.text == "Disenchant" and menu.fourth.enabled, "bag items offer Disenchant")
assert(menu.fifth.visible and menu.fifth.text == "Send by mail" and menu.fifth.enabled, "bag items offer Send by mail")
assert(menu.sixth.visible and menu.sixth.text == "Put to bank" and menu.sixth.enabled, "bag items offer Put to bank")
assert(menu.seventh.visible and menu.seventh.text == "|cffff5555Destroy|r", "bag items offer Destroy (red)")
assert(menu.height == 178, "the full menu fits seven rows")
-- P9: the menu flips left/right and above/below to stay on screen.
menu:Hide()
menu.x = 950
menu.y = 100
this = upgrade
upgrade.scripts.OnClick(upgrade)
assert(menu.point[1] == "TOPRIGHT", "the menu opens left of a right-edge slot")
menu.x = 100
menu.y = -50
menu:Hide()
this = upgrade
upgrade.scripts.OnClick(upgrade)
assert(menu.point[1] == "BOTTOMLEFT", "the menu opens above a low slot")
menu.x = nil
menu.y = nil
this = upgrade
upgrade.scripts.OnClick(upgrade)
now = now + 1
this = menu.first
menu.first.scripts.OnClick(menu.first)
assert(lastAddon() == "item Alpha equip 20 3", "Equip must address the bag slot")
local soulbound = TB.botPanel.bagButtons[1]
this = soulbound
soulbound.scripts.OnClick(soulbound)
assert(not menu.first.enabled and not menu.second.enabled, "soulbound junk cannot be equipped or given")
assert(not menu.fifth.enabled, "soulbound junk cannot be mailed away")
assert(menu.fourth.enabled and menu.sixth.enabled, "soulbound gear can still be disenchanted and banked")
menu:Hide()

-- Bags header: one-click upgrade sweep.
TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
assert(TB.botPanel.sweepButton.visible, "bags offer an upgrade sweep")
now = now + 1
this = TB.botPanel.sweepButton
TB.botPanel.sweepButton.scripts.OnClick(TB.botPanel.sweepButton)
assert(lastAddon() == "command Alpha d equip upgrades", "the sweep equips everything better")

-- Give without a trade window: pending, then re-sent when the window opens.
local junk = TB.botPanel.bagButtons[3]
this = junk
junk.scripts.OnClick(junk)
assert(menu.third.visible and menu.third.text == "Use", "bag items offer Use")
now = now + 1
this = menu.third
menu.third.scripts.OnClick(menu.third)
assert(lastAddon() == "command Alpha u |Hitem:159:0:0:0|h[Refreshing Spring Water]|h", "Use must send the item link")
this = junk
junk.scripts.OnClick(junk)
now = now + 1
this = menu.second
menu.second.scripts.OnClick(menu.second)
assert(lastAddon() == "item Alpha give 20 4", "Give must address the bag slot")
TB.OnSystemMessage("TBM:ACTION_ACK|item give|bot:Alpha|1|159 pending")
local beforeTrade = table.getn(addonSent)
tradePartner = "Alpha"
now = now + 1
event = "TRADE_SHOW"
frames["TortoiseBotsManagerTradeWatcher"].scripts.OnEvent()
assert(table.getn(addonSent) == beforeTrade + 1 and lastAddon() == "item Alpha give 20 4",
    "the give order is repeated once the trade window opens")
event = "TRADE_SHOW"
frames["TortoiseBotsManagerTradeWatcher"].scripts.OnEvent()
assert(table.getn(addonSent) == beforeTrade + 1, "the give order is repeated only once")
-- P9: the menu closes on a click outside it (panel-local catcher, no global hook).
this = junk
junk.scripts.OnClick(junk)
assert(menu.visible and menu.catcher.visible, "the menu shows its catcher")
menu.catcher.scripts.OnClick(menu.catcher)
assert(not menu.visible and not menu.catcher.visible and menu.owner == nil, "a click outside closes the menu")
-- P9: Destroy asks first and only sends on confirm.
this = junk
junk.scripts.OnClick(junk)
now = now + 1
this = menu.seventh
local beforeDestroy = table.getn(addonSent)
menu.seventh.scripts.OnClick(menu.seventh)
assert(table.getn(addonSent) == beforeDestroy, "Destroy must not send before the confirm")
assert(lastPopupShown == "TORTOISEBOTSMANAGER_DESTROY_ITEM", "Destroy must ask first")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_DESTROY_ITEM"] ~= nil, "destroy dialog must exist")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_DESTROY_ITEM"].text ==
    "Destroy |Hitem:159:0:0:0|h[Refreshing Spring Water]|h on Alpha?\n\nThis cannot be undone.",
    "the confirm must name the item with a single clean link")
StaticPopupDialogs["TORTOISEBOTSMANAGER_DESTROY_ITEM"].OnAccept()
assert(lastAddon() == "command Alpha destroy |Hitem:159:0:0:0|h[Refreshing Spring Water]|h",
    "confirming Destroy must send the item link")
-- P9: Use on an uncached item tells the player and sends once cached.
itemCache[159] = nil
this = junk
junk.scripts.OnClick(junk)
now = now + 1
this = menu.third
local beforeUse = table.getn(addonSent)
menu.third.scripts.OnClick(menu.third)
assert(table.getn(addonSent) == beforeUse, "Use on an uncached item must not send silently")
itemCache[159] = { name = "Refreshing Spring Water", quality = 1, texture = "Interface\\Icons\\INV_Drink_07" }
TB.botPanel.scripts.OnUpdate(TB.botPanel)
assert(lastAddon() == "command Alpha u |Hitem:159:0:0:0|h[Refreshing Spring Water]|h",
    "Use must send once the item is cached")
-- P9: Upkeep and Gear up disable while the bot is offline, like Trade.
TB.OpenBotPanel("Zed", "bags")
assert(not TB.botPanel.tradeButton.enabled and not TB.botPanel.upkeepButton.enabled
    and not TB.botPanel.gearUpButton.enabled, "offline footer actions must disable")
TB.OpenBotPanel("Alpha", "bags")
assert(TB.botPanel.tradeButton.enabled and TB.botPanel.upkeepButton.enabled
    and TB.botPanel.gearUpButton.enabled, "online footer actions must enable")

-- Behaviour chips toggle one bot and follow its BOTSTATE line.
TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
local saveMana = TB.botPanel.behaviorChips.savemana
assert(saveMana.visible and saveMana.text == "Save mana: Off", "behaviour chips show the bot's state")
now = now + 1
this = saveMana
saveMana.scripts.OnClick(saveMana)
assert(lastAddon() == "behavior Alpha savemana on", "a chip sends one behaviour toggle")
assert(not saveMana.enabled, "a chip waits for the server")
TB.OnSystemMessage("TBM:ACTION_ACK|behavior savemana|bot:Alpha|1|on")
TB.OnSystemMessage("TBM:BOTSTATE|Alpha|move=follow,loot=on,aoe=on,autocc=off,savemana=on,boost=on,threat=on,potions=on,mimic=off,spread=off")
assert(saveMana.enabled and saveMana.text == "Save mana: On" and TB.GetBotState("Gamma"),
    "a single BOTSTATE line updates one bot and keeps the others")
assert(TB.botPanel.behaviorChips.mimic.visible and TB.botPanel.behaviorChips.spread.visible,
    "mimic and spread chips render from the behaviour table")
now = now + 1
this = TB.botPanel.tradeButton
TB.botPanel.tradeButton.scripts.OnClick(TB.botPanel.tradeButton)
assert(lastAddon() == "item Alpha trade", "Trade opens a trade with the bot")
-- Footer: upkeep restocks, gear-up re-gears and reloads the panel view.
now = now + 1
this = TB.botPanel.upkeepButton
local beforeUpkeep = table.getn(addonSent)
TB.botPanel.upkeepButton.scripts.OnClick(TB.botPanel.upkeepButton)
assert(addonSent[beforeUpkeep + 1].message == "maintenance Alpha", "Upkeep restocks the bot")
this = TB.botPanel.gearUpButton
now = now + 1
local beforeGearUp = table.getn(addonSent)
TB.botPanel.gearUpButton.scripts.OnClick(TB.botPanel.gearUpButton)
assert(addonSent[beforeGearUp + 1].message == "autogear Alpha", "Gear up re-gears the bot")
-- Layout: six footer buttons fit the 330px panel with no overlap.
local footerSpan = 10 + 44 + 56 + 38 + 44 + 50 + 63 + 5 * 3
assert(footerSpan == 320, "footer (trade + refresh + NPC + bank + upkeep + auto-gear) must end at the x=320 tab edge")
assert(TB.botPanel.tradeButton.width == 44 and TB.botPanel.refreshButton.width == 56
    and TB.botPanel.npcButton.width == 38 and TB.botPanel.vaultButton.width == 44
    and TB.botPanel.upkeepButton.width == 50 and TB.botPanel.gearUpButton.width == 63,
    "footer buttons must keep their layout widths")
assert(TB.botPanel.vaultButton.text == "Bank" and TB.botPanel.gearUpButton.text == "AutoGear",
    "footer buttons must carry their short labels")
TB.CloseBotPanel()

-- ── Bot NPC errands (P10): talk/bind/learn/flights for the panel bot ──────
TB.OpenBotPanel("Alpha")
assert(TB.botPanel.npcButton and TB.botPanel.npcButton.visible, "the panel links to NPC errands")
now = now + 1
this = TB.botPanel.npcButton
TB.botPanel.npcButton.scripts.OnClick(TB.botPanel.npcButton)
assert(TB.botNpc and TB.botNpc.visible and TB.GetNpcBot() == "Alpha", "NPC opens for the panel bot")
now = now + 1
this = TB.botNpc.talk
TB.botNpc.talk.scripts.OnClick(TB.botNpc.talk)
assert(lastAddon() == "command Alpha talk", "Talk greets the nearby NPC")
now = now + 1
this = TB.botNpc.home
TB.botNpc.home.scripts.OnClick(TB.botNpc.home)
assert(lastAddon() == "command Alpha home", "Bind home binds at the innkeeper")
now = now + 1
this = TB.botNpc.trainer
TB.botNpc.trainer.scripts.OnClick(TB.botNpc.trainer)
assert(lastAddon() == "command Alpha trainer learn", "Learn trains at the targeted trainer")
now = now + 1
this = TB.botNpc.leader
TB.botNpc.leader.scripts.OnClick(TB.botNpc.leader)
assert(lastAddon() == "command Alpha give leader", "Make leader passes leadership to you")
now = now + 1
this = TB.botNpc.ask
TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
assert(lastAddon() == "command Alpha taxi ?", "Find flights lists the flight master's routes")
assert(not TB.botNpc.ask.enabled, "Find flights waits while the query is pending")
TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
assert(not TB.botNpc.rows[1].visible, "flight lines before the header must not seed the list")
TB.OnWhisperMessage("=== Taxi ===", "Alpha")
TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
TB.OnWhisperMessage("2: Ironforge, Dun Morogh", "Alpha")
TB.OnWhisperMessage("talk to the flight master", "Alpha")
assert(TB.botNpc.rows[1].visible and TB.botNpc.rows[1].flightN == 1, "flight rows render the parsed routes")
assert(TB.botNpc.rows[2].visible and TB.botNpc.rows[2].flightN == 2, "the second route renders too")
assert(not TB.botNpc.rows[3].visible, "empty flight rows stay hidden")
assert(TB.ParseFlightLine("bogus") == nil, "non-route whispers must not parse")
now = now + 1
this = TB.botNpc.rows[2]
TB.botNpc.rows[2].scripts.OnClick(TB.botNpc.rows[2])
assert(lastAddon() == "command Alpha taxi 2", "clicking a flight flies that leg")
-- Review geometry: the Ask row (y -240, h22) must end inside the window.
local askY = TB.botNpc.ask.point[5]
assert(askY == -108 - 6 * 22 and TB.botNpc.height >= -(askY - 22) + 12,
    "the Find flights row must sit inside the window with bottom padding")
-- Review paging: a hub burst of 10 routes pages 6 + 4 with BotPanel-style controls.
now = now + 1
this = TB.botNpc.ask
TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
TB.OnWhisperMessage("=== Taxi ===", "Alpha")
for i = 1, 10 do TB.OnWhisperMessage(i .. ": Stop " .. i, "Alpha") end
assert(table.getn(TB.GetNpcErrands("Alpha").flights) == 10, "ten hub routes must all parse")
assert(TB.botNpc.rows[1].flightN == 1 and TB.botNpc.rows[6].flightN == 6, "page one shows routes 1-6")
assert(not TB.botNpc.prevPage.enabled and TB.botNpc.nextPage.enabled, "page one enables next only")
assert(TB.botNpc.pageText.text == "1 / 2", "ten routes over six rows need two pages")
now = now + 1
this = TB.botNpc.nextPage
TB.botNpc.nextPage.scripts.OnClick(TB.botNpc.nextPage)
assert(TB.botNpc.rows[1].flightN == 7 and TB.botNpc.rows[4].flightN == 10, "page two shows routes 7-10")
assert(not TB.botNpc.rows[5].visible, "page two hides unused rows")
assert(TB.botNpc.prevPage.enabled and not TB.botNpc.nextPage.enabled, "page two enables prev only")
now = now + 1
this = TB.botNpc.rows[4]
TB.botNpc.rows[4].scripts.OnClick(TB.botNpc.rows[4])
assert(lastAddon() == "command Alpha taxi 10", "clicking a page-two flight flies that leg")
now = now + 1
this = TB.botNpc.prevPage
TB.botNpc.prevPage.scripts.OnClick(TB.botNpc.prevPage)
assert(TB.botNpc.rows[1].flightN == 1, "paging back restores routes 1-6")
TB.SetNpcPending("Alpha", false)
TB.CloseNpc()
assert(not TB.botNpc.visible, "NPC closes")
-- ── BotPanel spellbook (P6): 4th tab appended, indices 1-3 untouched ────────
TB.OpenBotPanel("Alpha")
assert(TB.botPanel.tabSpells and TB.botPanel.tabSpells.visible, "a 4th Spells tab must exist")
TB.botPanel.tabGear.scripts.OnClick(TB.botPanel.tabGear)
assert(TB.botPanel.gear.visible and not TB.botPanel.spells.visible, "Gear tab still shows the paper doll")
TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
assert(TB.botPanel.bags.visible and not TB.botPanel.spells.visible, "Bags tab still shows the grid")
TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
assert(TB.botPanel.behavior.visible and not TB.botPanel.spells.visible, "Behaviour tab still shows the chips")
TB.botPanel.tabSpells.scripts.OnClick(TB.botPanel.tabSpells)
assert(TB.botPanel.spells.visible and not TB.botPanel.gear.visible, "Spells tab shows the spellbook")
assert(table.getn(TB.botPanel.spellRows) == 12, "spellbook shows one page of rows")
now = now + 1
this = TB.botPanel.spellAsk
TB.botPanel.spellAsk.scripts.OnClick(TB.botPanel.spellAsk)
assert(lastAddon() == "command Alpha spells", "Ask for spellbook sends the proxy query")
assert(not TB.botPanel.spellAsk.enabled, "Ask waits while the query is pending")
TB.OnWhisperMessage("=== Spells ===", "Alpha")
TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
assert(TB.botPanel.spellRows[1].visible and TB.botPanel.spellRows[1].spellName == "Fireball",
    "spellbook rows render the parsed spells")
assert(not TB.botPanel.spellRows[2].visible, "empty rows stay hidden")
assert(TB.botPanel.spellPageText:GetText() == "1 / 1", "one spell fits on one page")
now = now + 1
this = TB.botPanel.spellRows[1]
TB.botPanel.spellRows[1].scripts.OnClick(TB.botPanel.spellRows[1])
assert(lastAddon() == "command Alpha cast Fireball", "clicking a spell casts it by exact name")
TB.SetSpellPending("Alpha", false)
TB.CloseBotPanel()

-- ── Bot vault (P8): bank + mailbox for the panel bot ─────────────────────
TB.OpenBotPanel("Alpha")
assert(TB.botPanel.vaultButton and TB.botPanel.vaultButton.visible, "the panel links to bank and mail")
now = now + 1
this = TB.botPanel.vaultButton
TB.botPanel.vaultButton.scripts.OnClick(TB.botPanel.vaultButton)
assert(lastAddon() == "command Alpha bank", "Bank / mail opens the vault bank list")
assert(TB.botVault and TB.botVault.visible and TB.GetVaultBot() == "Alpha", "the vault tracks the panel bot")
assert(TB.botVault.point and TB.botVault.point[2] == TB.botPanel, "the vault sits beside the open panel")
assert(table.getn(TB.botVault.rows) == 8, "the vault shows one page of rows")
TB.OnWhisperMessage("=== Bank ===", "Alpha")
TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3", "Alpha")
assert(TB.botVault.rows[1].visible and TB.botVault.rows[1].itemId == 1234,
    "vault rows render the parsed bank items")
assert(not TB.botVault.rows[2].visible, "empty vault rows stay hidden")
now = now + 1
this = TB.botVault.rows[1]
TB.botVault.rows[1].scripts.OnClick(TB.botVault.rows[1])
assert(lastAddon() == "command Alpha bank -|Hitem:1234:0:0:0|h[Linen Cloth]|h",
    "clicking a bank row withdraws it by link")
TB.SetVaultPending("Alpha", false)
now = now + 1
this = TB.botVault.tabMail
TB.botVault.tabMail.scripts.OnClick(TB.botVault.tabMail)
TB.RequestMailbox("Alpha")
assert(lastAddon() == "command Alpha mail ?", "the mailbox tab asks for its letters")
TB.OnWhisperMessage("=== Mailbox ===", "Alpha")
TB.OnWhisperMessage("#1 |cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r, |cff00ff000 day(s)", "Alpha")
assert(TB.botVault.rows[1].visible and TB.botVault.rows[1].mailN == 1,
    "mailbox rows render the parsed letters")
now = now + 1
this = TB.botVault.rows[1]
TB.botVault.rows[1].scripts.OnClick(TB.botVault.rows[1])
assert(lastAddon() == "command Alpha mail take 1", "clicking a letter takes it by index")
TB.SetVaultPending("Alpha", false)
TB.CloseVault()
assert(not TB.botVault.visible, "the vault closes")
TB.CloseBotPanel()
assert(not TB.botPanel.visible, "the panel closes")

-- ── Raid tab only exists in a raid ─────────────────────────────────────────
assert(not TB.tabRaid.visible, "no Raid tab outside a raid")
TB.ShowTab("raid")
assert(TB.actionsFrame.visible and not TB.raidFrame.visible, "the Raid tab cannot open outside a raid")
local realRaidMembers = GetNumRaidMembers
GetNumRaidMembers = function() return 10 end
TB.UpdateRaidTab()
assert(TB.tabRaid.visible, "the Raid tab appears in a raid")
TB.ShowTab("raid")
assert(TB.raidFrame.visible and not TB.actionsFrame.visible, "the Raid tab opens in a raid")
now = now + 1
this = TB.raidFrame.statusButton
TB.raidFrame.statusButton.scripts.OnClick(TB.raidFrame.statusButton)
assert(lastAddon() == "action raid status", "Check bots asks for raid status")
TB.OnSystemMessage("TBM:ACTION_ACK|raid status|bot:Alpha|1|molten core")
TB.OnSystemMessage("TBM:ACTION_ACK|raid status|bot:Gamma|1|outdoor")
assert(string.find(TB.raidFrame.statusList.text, "molten core", 1, true)
    and string.find(TB.raidFrame.statusList.text, "Gamma", 1, true), "raid status lists every bot")
now = now + 1
this = TB.raidFrame.customToggle
TB.raidFrame.customToggle.scripts.OnClick(TB.raidFrame.customToggle)
assert(lastAddon() == "action raid custom on", "custom tactics start from on")
TB.OnSystemMessage("TBM:ACTION_ACK|raid custom on|party|2|-")
assert(TB.raidFrame.customToggle.text == "Custom tactics: On", "custom tactics show the ACK state")
GetNumRaidMembers = realRaidMembers
TB.UpdateRaidTab()
assert(TB.actionsFrame.visible and not TB.tabRaid.visible, "leaving the raid closes the Raid tab")

-- Hired companions are no roster rows: BOTSTATE still makes them bot targets.
TB.OnSystemMessage("TBM:BOTSTATE|Hireling|move=follow,loot=on,aoe=off,autocc=off,savemana=off,boost=on,threat=on,potions=on")
local savedTarget, savedExists = targetNameValue, targetExists
targetExists, targetNameValue = true, "Hireling"
TB.Refresh()
assert(TB.GetActionScope() == "bot:Hireling" and TB.scopeGearButton.visible
    and not TB.actionButtons.attack.enabled, "a targeted hired companion is a bot scope with Gear & bags")
targetExists, targetNameValue = savedExists, savedTarget
TB.Refresh()


-- ── Tabs by kind of work, and mini mode ────────────────────────────────────
TB.ShowTab("camp")
assert(TB.campFrame.visible and not TB.actionsFrame.visible and TortoiseBotsDB.activeTab == "camp",
    "the Camp tab opens its own view")
assert(TB.tabActions.text.text == "Fight" and TB.tabCamp.visible, "Fight and Camp tabs exist")
assert(TB.actionButtons.rest.parent.parent == TB.campFrame and TB.actionButtons.attack.parent.parent == TB.actionsFrame,
    "chores live on Camp, fight buttons on Fight")
TB.ShowTab("actions")
assert(TB.actionsFrame.visible and not TB.campFrame.visible, "Fight hides Camp")

-- A fresh bar has no favourites, only the hint; a 1.2 save of the old
-- default icons is cleared once.
TortoiseBotsDB.miniFavorites = { "attack", "stop", "interrupt", "flee", "pull", "pullback", "focus skull",
    "follow", "stay", "come", "aoe" }
TortoiseBotsDB.miniFavoritesOwn = nil
assert(table.getn(TB.GetMiniFavorites()) == 0, "the old default favourites are cleared once")
TortoiseBotsDB.miniFavorites = { "attack", "stop", "interrupt", "flee", "pull", "pullback", "focus skull",
    "follow", "stay", "come", "aoe" }
assert(table.getn(TB.GetMiniFavorites()) == 11, "favourites the player kept stay")
TB.frame:Show()
TB.miniButton.scripts.OnClick(TB.miniButton)
local bar = frames["TortoiseBotsManagerMiniBar"]
TB.LayoutMiniBar()
assert(TB.GetMode() == "mini" and bar.visible and not TB.frame.visible, "Mini swaps the window for the bar")
targetExists, targetNameValue = false, nil
TB.Refresh()
assert(bar.icons.attack.usable == false and bar.icons.stop.usable and bar.icons.flee.usable,
    "mini icons follow the target rules")
this, arg1 = bar.icons.attack, "RightButton"
bar.icons.attack.scripts.OnClick(bar.icons.attack)
assert(not bar.icons.attack, "a greyed-out favourite still drops on right-click")
TB.ToggleMiniFavorite("attack")
arg1 = nil
now = now + 1
this = bar.icons.stop
bar.icons.stop.scripts.OnClick(bar.icons.stop)
assert(lastAddon() == "action stop", "mini icons send the same intents")
-- Category flyout and favourites.
TB.OpenMiniCategory("camp")
local fly = frames["TortoiseBotsManagerMiniFlyout"]
assert(fly.visible and TB.GetMiniCategory() == "camp", "a category icon opens its flyout")
local restEntry = fly.entries[1]
assert(restEntry.def and restEntry.def.intent == "rest", "the flyout lists the category's actions")
now = now + 1
this, arg1 = restEntry, "LeftButton"
restEntry.scripts.OnClick(restEntry)
assert(lastAddon() == "action rest", "a flyout click runs the action")
this, arg1 = restEntry, "RightButton"
restEntry.scripts.OnClick(restEntry)
assert(bar.icons.rest and bar.icons.rest.visible, "right-click pins the action to the bar")
this, arg1 = bar.icons.rest, "RightButton"
bar.icons.rest.scripts.OnClick(bar.icons.rest)
assert(not bar.icons.rest, "right-click on the bar unpins it")
this, arg1 = TB.actionButtons.rest, "RightButton"
TB.actionButtons.rest.scripts.OnClick(TB.actionButtons.rest)
assert(bar.icons.rest, "right-click in the full window pins the action to the mini bar")
TB.actionButtons.rest.scripts.OnClick(TB.actionButtons.rest)
assert(not bar.icons.rest, "a second right-click drops it again")
arg1 = nil
TB.OpenMiniCategory("camp")
assert(not fly.visible and TB.GetMiniCategory() == nil, "the same icon closes the flyout")
TB.Toggle()
assert(not bar.visible and not TB.frame.visible, "/tbm hides the bar in mini mode")
TB.Toggle()
assert(bar.visible, "/tbm shows the bar again in mini mode")
assert(bar.strata == "DIALOG", "mini bar must sit on DIALOG strata above action bars")
assert(bar.clamped == true, "mini bar must clamp to screen")
assert(bar.dragButtons and bar.dragButtons[1] == "LeftButton" and bar.scripts.OnDragStart and bar.scripts.OnDragStop,
    "mini bar background must be draggable")
local watcher = frames["TortoiseBotsManagerMiniBarWatcher"]
assert(watcher.events.PLAYER_ENTERING_WORLD and watcher.events.PLAYER_LOGIN,
    "mini bar watcher must restore on entering world and login")
event = "PLAYER_LOGIN"
bar:Hide()
watcher.scripts.OnEvent(watcher)
assert(bar.visible, "mini bar must restore on PLAYER_LOGIN without uiReady")
event = "PLAYER_ENTERING_WORLD"
bar:Hide()
TB.uiReady = false
watcher.scripts.OnEvent(watcher)
assert(bar.visible, "mini bar must restore on PLAYER_ENTERING_WORLD even when uiReady is false")
TB.uiReady = true
TortoiseBotsDB.miniBar = { x = 9999, y = 9999 }
SlashCmdList["TORTOISEBOTSMANAGER"]("resetpos")
assert(TortoiseBotsDB.miniBar == nil, "resetpos must clear the mini bar position")
assert(TB.miniBar.point[1] == "BOTTOM", "resetpos must re-anchor the mini bar")
bar.expand.scripts.OnClick(bar.expand)
assert(TB.GetMode() == "full" and TB.frame.visible and not bar.visible, "+ restores the full window")
targetExists, targetNameValue = true, "Enemy"
TB.Refresh()

-- A client that has not restarted since the update has no MiniBar.lua: the
-- Mini button must say so instead of doing nothing.
local realSetMode = TB.SetMode
TB.SetMode = nil
local chatBefore = table.getn(defaultChatMessages)
TB.miniButton.scripts.OnClick(TB.miniButton)
assert(table.getn(defaultChatMessages) == chatBefore + 1 and string.find(defaultChatMessages[table.getn(defaultChatMessages)], "restart the game client", 1, true),
    "Mini without MiniBar.lua tells the player to restart the client")
TB.SetMode = realSetMode

-- ── Claimed Guild Bots (Issue #489) ────────────────────────────────────────
local uninvitedGuildMembers = {}
function GuildUninvite(name) table.insert(uninvitedGuildMembers, name) end

TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(TB.HasServerCapability("claimed-roster"), "server CAPS must advertise claimed-roster")

-- Initial empty state: no claimed bots yet
TB.ShowTab("guild")
TB.RefreshGuildView()
assert(TB.guildFrame:IsVisible(), "Guild frame must be visible")
assert(TB.guildFrame.emptyMsg:IsVisible(), "Empty message must show when no bots are claimed")
assert(table.getn(TB.GetClaimedBots()) == 0, "Initial claimed bots list must be empty")

-- Streaming snapshot: 3 claimed bots with mixed levels and states
TB.OnSystemMessage("TBM:CLAIMED_BEGIN|3")
TB.OnSystemMessage("TBM:CLAIMED|201|Goldie|1|60|online|0|Ironforge|1")
TB.OnSystemMessage("TBM:CLAIMED|202|Silver|5|45|online|1|Duskwood|0")
TB.OnSystemMessage("TBM:CLAIMED|203|Bronze|8|20|offline|0|-|0")
TB.OnSystemMessage("TBM:CLAIMED_END")

assert(TB.claimedSnapshotReady, "claimedSnapshotReady must be true after stream")
local allClaimed = TB.GetClaimedBots()
assert(table.getn(allClaimed) == 3, "snapshot must retain all 3 claimed bots")
-- Sorting: level descending (60, 45, 20)
assert(allClaimed[1].name == "Goldie" and allClaimed[1].level == 60, "highest level bot must sort first")
assert(allClaimed[2].name == "Silver" and allClaimed[2].level == 45, "mid level bot must sort second")
assert(allClaimed[3].name == "Bronze" and allClaimed[3].level == 20, "lower level bot must sort third")

-- Gear locking policy state
assert(allClaimed[1].gearLocked == true, "Level 60 bot must have gearLocked = true")
assert(allClaimed[2].gearLocked == false, "Level 45 bot must have gearLocked = false")
assert(allClaimed[3].gearLocked == false, "Level 20 bot must have gearLocked = false")

-- Search filter
assert(table.getn(TB.GetClaimedBots("silver")) == 1 and TB.GetClaimedBots("silver")[1].name == "Silver",
    "search filter must find bot by name")
assert(table.getn(TB.GetClaimedBots("mage")) == 1 and TB.GetClaimedBots("mage")[1].name == "Bronze",
    "search filter must find bot by class name")

-- UI rendering on Guild tab
TB.ShowTab("guild")
assert(not TB.guildFrame.emptyMsg:IsVisible(), "empty message must be hidden when bots exist")
assert(TB.guildFrame.scroll:IsVisible(), "scroll frame must be visible when bots exist")

local row1, row2, row3 = TB.guildFrame.rows[1], TB.guildFrame.rows[2], TB.guildFrame.rows[3]
assert(row1:IsVisible() and row1.name:GetText() == "Goldie", "row 1 must render Goldie")
assert(row1.lvlClass:GetText() == "60 Warrior", "row 1 must render level and class")
assert(string.find(row1.gearBadge:GetText(), "Locked", 1, true) ~= nil, "row 1 must show Locked badge")
assert(row2:IsVisible() and row2.name:GetText() == "Silver", "row 2 must render Silver")
assert(string.find(row2.gearBadge:GetText(), "Leveling", 1, true) ~= nil, "row 2 must show Leveling badge")
assert(row3:IsVisible() and row3.name:GetText() == "Bronze", "row 3 must render Bronze")

-- Checkbox selection & multi-select
this = row1.check; row1.check:SetChecked(true); row1.check.scripts.OnClick(row1.check)
this = row3.check; row3.check:SetChecked(true); row3.check.scripts.OnClick(row3.check)
assert(TB.IsClaimedSelected("Goldie") and TB.IsClaimedSelected("Bronze"), "multi-select checkboxes must work")
assert(not TB.IsClaimedSelected("Silver"), "unchecked bot must not be selected")
assert(TB.GetClaimedSelectionCount() == 2, "selection count must be 2")

-- Eligibility checks:
-- Goldie is online and not in group (eligible for invite and summon)
-- Bronze is offline (not eligible for invite or summon)
local eligibleInv = TB.GetEligibleClaimedNames("invite")
assert(table.getn(eligibleInv) == 1 and eligibleInv[1] == "Goldie", "offline bot must be excluded from invite")
local eligibleSum = TB.GetEligibleClaimedNames("summon")
assert(table.getn(eligibleSum) == 1 and eligibleSum[1] == "Goldie", "offline bot must be excluded from summon")

-- Invite to Raid button
now = now + 1
local beforeGuildInvite = table.getn(addonSent)
this = TB.guildFrame.inviteBtn
TB.guildFrame.inviteBtn.scripts.OnClick(TB.guildFrame.inviteBtn)
assert(table.getn(addonSent) == beforeGuildInvite + 1 and lastAddon() == "invite Goldie",
    "Invite to Raid must send invite for eligible selected bots")

-- Summon to Raid button
now = now + 1
local beforeGuildSummon = table.getn(addonSent)
this = TB.guildFrame.summonBtn
TB.guildFrame.summonBtn.scripts.OnClick(TB.guildFrame.summonBtn)
assert(table.getn(addonSent) == beforeGuildSummon + 1 and lastAddon() == "summon Goldie",
    "Summon to Raid must send summon for eligible selected bots")

-- CheckAll master checkbox
this = TB.guildFrame.checkAll; TB.guildFrame.checkAll:SetChecked(true); TB.guildFrame.checkAll.scripts.OnClick(TB.guildFrame.checkAll)
assert(TB.GetClaimedSelectionCount() == 3, "checkAll must select all 3 claimed bots")
this = TB.guildFrame.checkAll; TB.guildFrame.checkAll:SetChecked(false); TB.guildFrame.checkAll.scripts.OnClick(TB.guildFrame.checkAll)
assert(TB.GetClaimedSelectionCount() == 0, "unchecking checkAll must clear selection")

-- Role button cycling
now = now + 1
this = row1.roleBtn
row1.roleBtn.scripts.OnClick(row1.roleBtn)
assert(TortoiseBotsDB.botRoles["Goldie"] ~= nil, "clicking role button must set botRoles in DB")

-- Gear & Bags button (opens BotPanel with Gear Locked badge)
this = row1.bagBtn
row1.bagBtn.scripts.OnClick(row1.bagBtn)
assert(TB.botPanel:IsVisible(), "Bot panel must open when bag button is clicked")
assert(string.find(TB.botPanel.subText:GetText(), "Gear Locked", 1, true) ~= nil,
    "Bot panel header must show Gear Locked badge for claimed 60 bot")

-- Release button with confirmation popup
now = now + 1
this = row1.relBtn
row1.relBtn.scripts.OnClick(row1.relBtn)
assert(lastPopupShown == "TORTOISE_RELEASE_CLAIMED_BOT", "Release must prompt confirmation dialog")
assert(StaticPopupDialogs["TORTOISE_RELEASE_CLAIMED_BOT"] ~= nil, "Release dialog specification must exist")
StaticPopupDialogs["TORTOISE_RELEASE_CLAIMED_BOT"].OnAccept()
assert(table.getn(uninvitedGuildMembers) == 1 and uninvitedGuildMembers[1] == "Goldie",
    "confirming Release must call GuildUninvite for the bot")

-- Direct release helper
TB.ReleaseClaimedBot("Silver")
assert(table.getn(uninvitedGuildMembers) == 2 and uninvitedGuildMembers[2] == "Silver",
    "ReleaseClaimedBot must call GuildUninvite directly")

-- Chat transport fallback for Guild actions when addon transport is unavailable
TB.SetAddonTransport("none")
now = now + 1
TB.ToggleClaimedSelection("Bronze", true)
local beforeChatSummon = table.getn(sent)
this = TB.guildFrame.summonBtn
-- Bronze is offline, so no summons
assert(table.getn(sent) == beforeChatSummon, "offline bot must not trigger summon")
TB.ToggleClaimedSelection("Goldie", true)
TB.guildFrame.summonBtn.scripts.OnClick(TB.guildFrame.summonBtn)
assert(table.getn(sent) == beforeChatSummon + 1 and sent[table.getn(sent)] == ".bot summon Goldie",
    "Summon to Raid must fall back to chat .bot summon when addon transport is none")

-- Sync button requests fresh snapshot
local pollCalled = false
local origPollList = TB.PollList
TB.PollList = function(forced) pollCalled = forced end
this = TB.guildFrame.syncBtn
TB.guildFrame.syncBtn.scripts.OnClick(TB.guildFrame.syncBtn)
assert(pollCalled == true, "Sync button must trigger forced PollList")
TB.PollList = origPollList

-- ── P7: class filter chips + fill buttons + keybinding handlers ─────────────
TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|0|map:4,zone:5,area:6")
TB.OnSystemMessage("TBM:ROSTER_END")
assert(table.getn(TB.classChips) == 10, "roster must show All plus 9 class filter chips")
local function frameEdges(f)
    local _, _, _, x, y = f:GetPoint(1)
    return x, x + f.width, y, y - f.height
end
for _, chip in ipairs(TB.classChips) do
    local left, right, top, bottom = frameEdges(chip)
    assert(left >= 0 and right <= 480,
        "class chip must stay inside the 480px roster frame")
    assert(top <= -22 and bottom >= -62,
        "class chips must sit on their own rows below the search box")
end
local searchLeft, searchRight, searchTop, searchBottom = frameEdges(TB.searchBox)
local clearLeft, clearRight, clearTop, clearBottom = frameEdges(TB.searchClear)
for _, chip in ipairs(TB.classChips) do
    local left, right, top, bottom = frameEdges(chip)
    local overlapsSearch = not (right <= searchLeft or left >= searchRight or top <= searchBottom or bottom >= searchTop)
    local overlapsClear = not (right <= clearLeft or left >= clearRight or top <= clearBottom or bottom >= clearTop)
    assert(not overlapsSearch and not overlapsClear,
        "class chips must not intersect the search box or Clear button")
end
assert(TB.classFilter == nil, "class filter must start on All")
TB.classFilter = 1
TB.PaintClassChips()
TB.Refresh()
assert(table.getn(TB.GetDisplayRows("")) == 1 and TB.GetDisplayRows("")[1].name == "Alpha",
    "Warrior filter must show only the Warrior row")
assert(table.getn(TB.GetDisplayRows("gamma")) == 0,
    "class filter must combine with the name search")
TB.classFilter = nil
TB.PaintClassChips()
TB.Refresh()
assert(table.getn(TB.GetDisplayRows("")) == 3, "clearing the class filter must restore all rows")
local chipWarrior = nil
for _, chip in ipairs(TB.classChips) do
    if chip.classId == 1 then chipWarrior = chip break end
end
assert(chipWarrior, "Warrior filter chip must exist")
this = chipWarrior
chipWarrior.scripts.OnClick(chipWarrior)
assert(TB.classFilter == 1 and table.getn(TB.GetDisplayRows("")) == 1,
    "clicking the Warrior chip must filter the roster rows")
assert(chipWarrior.isActive, "the active filter chip is picked (pill pattern)")
this = TB.classChips[1]
TB.classChips[1].scripts.OnClick(TB.classChips[1])
assert(TB.classFilter == nil and table.getn(TB.GetDisplayRows("")) == 3,
    "clicking All must clear the class filter")
assert(TB.lifecycleButtons.fill and TB.guildFrame.fillBtn,
    "Fill party and Fill raid buttons must exist")
local rosterSpan = 95 + 56 + 62 + 56 + 50 + 66 + 44 + 6 * 4
assert(rosterSpan <= 480, "roster bar (selection + 6 buttons) must fit the 480px frame")
local guildSpan = 85 + 110 + 110 + 56 + 56 + 4 * 4
assert(guildSpan <= 480, "guild bar (selection + 4 buttons) must fit the 480px frame")
local fillLeft, fillRight = frameEdges(TB.lifecycleButtons.fill)
assert(fillLeft >= 0 and fillRight <= 480, "Fill button must stay inside the roster frame")
partyMembers = { "Alpha", "Gamma", "Delta", "Epsilon" }
assert(table.getn(TB.GetFillPartyNames()) == 0,
    "Fill party must stay empty when the party is already full")
partyMembers = {}
local groupWatcher = frames["TortoiseBotsManagerGroupWatcher"]
groupWatcher.scripts.OnEvent(groupWatcher)
assert(TB.GetFillPartyNames()[1] == "Alpha" and TB.GetFillPartyNames()[2] == "Gamma",
    "Fill party must pick invite-eligible bots up to the party cap")
assert(table.getn(TB.GetFillRaidNames()) == 2 and TB.GetFillRaidNames()[1] == "Goldie",
    "Fill raid must pick online ungrouped claimed bots up to the raid cap")
partyMembers = {}
TB.SetAddonTransport("none")
now = now + 1
TortoiseBotsDB.pullDelay = nil
TortoiseBotsDB.pullbackDelay = nil
local beforeKeys = table.getn(sent)
assert(TB.SendKeyIntent("attack") == true, "keybinding Attack must send")
assert(sent[table.getn(sent)] == ".bot action attack", "keybinding Attack must send the attack intent")
now = now + 1
TB.OnSystemMessage("TBM:CAPS|flee,inventory,behavior,claimed-roster")
TB.SendKeyIntent("pull")
assert(sent[table.getn(sent)] == ".bot action pull", "keybinding Pull must send the plain intent without the timer cap")
now = now + 1
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
TortoiseBotsDB.pullDelay = 10
TB.SendKeyIntent("pull")
assert(sent[table.getn(sent)] == ".bot action pull 10", "keybinding Pull must honor the pull timer cap")
TortoiseBotsDB.pullDelay = nil
now = now + 1
TB.OnSystemMessage("TBM:CAPS|flee,inventory,behavior,claimed-roster")
assert(TB.SendKeyIntent("flee") == true, "keybinding Flee must send while the cap is advertised")
now = now + 1
TB.OnSystemMessage("TBM:CAPS|inventory,behavior,claimed-roster")
assert(TB.SendKeyIntent("flee") == false, "keybinding Flee must stay silent without the server cap")
assert(table.getn(sent) == beforeKeys + 4, "keybindings must send exactly one intent per press")

-- ── Dungeon run window (P11): capability-gated satellite ─────────────────
TB.OnSystemMessage("TBM:TRANSPORT|party")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.tabDungeon:IsVisible(), "no Dungeon tab without the capability")
assert(TB.OpenRunWindow() == false, "the run window stays shut without the capability")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,dungeon-run")
assert(TB.tabDungeon:IsVisible(), "the capability shows the Dungeon tab")
now = now + 1
this = TB.tabDungeon
TB.tabDungeon.scripts.OnClick(TB.tabDungeon)
assert(TB.dungeonFrame:IsVisible(), "the Dungeon tab shows its page")
assert(TB.runWindow and TB.runWindow:IsVisible(), "the Dungeon tab opens the run window")
local runQueue = frames["TortoiseBotsManagerQueueFrame"]
for _ = 1, 30 do
    if lastAddon() == "run status" then break end
    now = now + 1
    this, arg1 = runQueue, 0.5
    runQueue.scripts.OnUpdate(runQueue)
end
assert(lastAddon() == "run status", "opening asks for the run status")
assert(TB.runWindow.point and (TB.runWindow.point[2] == TB.frame or TB.runWindow.point[2] == TB.botPanel), "the run window sits beside main")
TB.OnSystemMessage("Dungeon plans: uldaman (map 70, 41 steps), ragefire_chasm (map 389, 120 steps, 3 not supported yet)")
assert(table.getn(TB.GetRunPlans()) == 2, "the plan list parses")
assert(chatFilters.CHAT_MSG_SYSTEM == nil or chatFilters.CHAT_MSG_SYSTEM(nil, nil, "Dungeon plans: uldaman (map 70, 41 steps)") == true,
    "the plan list stays out of the chat")
assert(not TB.runWindow.planRows[1]:IsVisible(), "outside a dungeon the list stays closed")
this = TB.runWindow.planToggle
TB.runWindow.planToggle.scripts.OnClick(TB.runWindow.planToggle)
assert(TB.runWindow.planRows[1].visible and TB.runWindow.planRows[1].planName == "uldaman",
    "plan rows render the parsed plans")
now = now + 1
this = TB.runWindow.planRows[2]
TB.runWindow.planRows[2].scripts.OnClick(TB.runWindow.planRows[2])
assert(TB.GetRunSelectedPlan() == "ragefire_chasm", "clicking a plan picks it")
now = now + 1
this = TB.runWindow.start
TB.runWindow.start.scripts.OnClick(TB.runWindow.start)
assert(lastAddon() == "run start ragefire_chasm", "Start sends the picked plan")
assert(string.find(TB.GetRunFeedback().text, "Start sent"), "a click says it was sent")
TB.OnSystemMessage("TBM:ACTION_ERR|run start|not-bound|You command no group.")
assert(string.find(TB.GetRunFeedback().text, "Start refused") and string.find(TB.runWindow.feedback.text, "You command no group"),
    "a refusal shows in the run window")
TB.OnSystemMessage("TBM:ACTION_ACK|run list|plans|36|-")
assert(string.find(TB.GetRunFeedback().text, "36 plans loaded"), "the plans ACK is understood, not malformed")
TB.OnSystemMessage("TBM:ACTION_ACK|run start|party|120|ragefire_chasm")
assert(string.find(TB.GetRunFeedback().text, "Start done"), "an ACK shows in the run window")
TB.OnSystemMessage("TBM:RUN|ragefire_chasm|running|1/120|tunnel|move|walk|walking to tunnel")
assert(TB.GetRun().state == "running", "the status line drives the model")
assert(TB.runWindow.runStep.text == "Step 1 of 120", "step x/y renders")
now = now + 1
this = TB.runWindow.pause
TB.runWindow.pause.scripts.OnClick(TB.runWindow.pause)
assert(lastAddon() == "run pause", "Pause sends")
TB.OnSystemMessage("TBM:RUN|ragefire_chasm|paused|1/120|tunnel|move|walk|paused by .bot run pause")
assert(TB.runWindow.resume.enabled and not TB.runWindow.pause:IsVisible(), "pause swaps Pause for Resume")
now = now + 1
this = TB.runWindow.resume
TB.runWindow.resume.scripts.OnClick(TB.runWindow.resume)
assert(lastAddon() == "run resume", "Resume sends")
now = now + 1
this = TB.runWindow.skip
TB.runWindow.skip.scripts.OnClick(TB.runWindow.skip)
assert(lastAddon() == "run skip", "Skip sends")
TB.SetRunStopReason("done for tonight")
now = now + 1
this = TB.runWindow.stop
TB.runWindow.stop.scripts.OnClick(TB.runWindow.stop)
assert(lastAddon() == "run stop done for tonight", "Stop sends the reason")
TB.SetRunStopReason("")
TB.OnSystemMessage("TBM:RUN|ragefire_chasm|done|5/120|tunnel|move|walk|stopped: done for tonight")
assert(not TB.runWindow.stop.enabled, "Stop waits once the run is done")
-- Plan search and the zone's plans.
TB.OnSystemMessage("Dungeon plans: uldaman (map 70, 41 steps), scarlet_library (map 189, 88 steps), scarlet_armory (map 189, 110 steps), stormwind_stockade (map 34, 95 steps), zulfarrak (map 209, 232 steps)")
assert(TB.RunPlanTitle("scarlet_library") == "Scarlet Library" and TB.RunPlanTitle("zulfarrak") == "Zul'Farrak",
    "plans show readable names")
TB.SetRunSelectedPlan(nil)
function GetRealZoneText() return "The Stockade" end
TB.RefreshRunWindow()
assert(TB.GetRunSelectedPlan() == "stormwind_stockade", "a dungeon with one plan picks it")
assert(string.find(TB.runWindow.planPick.text, "Stormwind Stockade"), "the picked plan shows by name")
TB.SetRunSelectedPlan(nil)
function GetRealZoneText() return "Scarlet Monastery" end
TB.RefreshRunWindow()
assert(TB.GetRunSelectedPlan() == nil, "a dungeon with several plans waits for a pick")
for _ = 1, 30 do
    if lastAddon() == "run here" then break end
    now = now + 1
    this, arg1 = runQueue, 0.5
    runQueue.scripts.OnUpdate(runQueue)
end
assert(lastAddon() == "run here", "a dungeon with wings asks the server which one")
assert(TB.runWindow.planRows[1].planName == "scarlet_library" and TB.runWindow.planRows[2].planName == "scarlet_armory",
    "the wings come first")
TB.OnSystemMessage("TBM:RUN_HERE|scarlet_armory|12")
assert(TB.GetRunSelectedPlan() == "scarlet_armory" and string.find(TB.runWindow.planPick.text, "Scarlet Armory"),
    "the server's answer picks the wing the player stands in")
function GetRealZoneText() return "Stormwind City" end
TB.SetRunPlanPicker(true)
this = TB.runWindow.planSearch
TB.runWindow.planSearch:SetText("ARMORY")
TB.runWindow.planSearch.scripts.OnTextChanged(TB.runWindow.planSearch)
assert(TB.runWindow.planRows[1].planName == "scarlet_armory" and not TB.runWindow.planRows[2]:IsVisible(),
    "the search filters the list")
TB.runWindow.planSearch:SetText("")
TB.runWindow.planSearch.scripts.OnTextChanged(TB.runWindow.planSearch)
GetRealZoneText = nil
this = TB.runWindow.planRows[1]
TB.runWindow.planRows[1].scripts.OnClick(TB.runWindow.planRows[1])
assert(not TB.runWindow.planSearch:IsVisible(), "a pick closes the search list")
-- Raid bind: targets the main tank, applies the layout, stops before the boss.
TB.OpenRunWindow()
TB.OnSystemMessage("TBM:RAID_LAYOUT|25|Alpha,Beta|Pri1 -> Alpha|Druid1|1=Alpha,Pri1;2=Beta,Druid1")
assert(TB.GetRaidLayout() and TB.GetRaidLayout().mainTank == "Alpha", "the raid layout parses main first")
assert(string.find(TB.runWindow.layout.text, "Main Alpha + 1 off", 1, true),
    "the layout renders under the bind row")
TB.OnSystemMessage("TBM:ACTION_ACK|commander bind|raid|25|Alpha")
assert(string.find(TB.GetRunFeedback().text, "Bind done") and string.find(TB.GetRunFeedback().text, "raid"),
    "the raid bind ACK names the scope")
this = TB.runWindow.untilBoss
TB.runWindow.untilBoss:SetChecked(true)
TB.runWindow.untilBoss.scripts.OnClick(TB.runWindow.untilBoss)
assert(TB.GetRunStopBeforeBoss() == true, "the checkbox arms stop-before-boss")
TB.OnSystemMessage("TBM:RAID_LAYOUT|warning|could not place: Gamma")
assert(TB.GetRaidLayout().warning and TB.runWindow.layout.text ~= "", "the layout warning shows")
TB.SetRunStopBeforeBoss(false)
-- Server info window: ".bot features" fills the switch list.
assert(TB.infoButton, "the header has an Info button")
this = TB.infoButton
TB.infoButton.scripts.OnClick(TB.infoButton)
for _ = 1, 30 do
    if lastAddon() == "features" then break end
    now = now + 1
    this, arg1 = runQueue, 0.5
    runQueue.scripts.OnUpdate(runQueue)
end
assert(TB.infoWindow:IsVisible() and lastAddon() == "features", "Info opens the window and asks the server")
assert(not TB.runWindow:IsVisible(), "Info closes the run window beside main")
TB.OnSystemMessage("Server features: dungeon-run on, hire-max 4")
TB.OnSystemMessage("TBM:FEATURE|dungeon-run|on|Dungeon runs")
TB.OnSystemMessage("TBM:FEATURE|hire-max|4|Hires per player")
assert(table.getn(TB.GetServerFeatures()) == 2, "the switches parse")
assert(TB.infoWindow.rows[1].label.text == "Dungeon runs" and TB.infoWindow.rows[2].value.text == "4",
    "the switches render")
assert(chatFilters.CHAT_MSG_SYSTEM == nil or chatFilters.CHAT_MSG_SYSTEM(nil, nil, "Server features: dungeon-run on") == true,
    "the summary stays out of the chat")
-- All settings: a search asks the server, the answer lists key and value.
TB.SetServerInfoTab("all")
assert(TB.infoWindow.search:IsVisible() and not TB.infoWindow.refresh:IsVisible(), "the All tab shows the search")
TB.SearchServerConfig("hire")
for _ = 1, 30 do
    if lastAddon() == "features all hire" then break end
    now = now + 1
    this, arg1 = runQueue, 0.5
    runQueue.scripts.OnUpdate(runQueue)
end
assert(lastAddon() == "features all hire", "a search sends .bot features all <text>")
TB.OnSystemMessage("Config: 2 keys match 'hire'.")
TB.OnSystemMessage("TBM:CONFIG_BEGIN|2")
TB.OnSystemMessage("TBM:CONFIG|HireEnabled|1")
TB.OnSystemMessage("TBM:CONFIG|HireMaxBotsPerPlayer|4")
TB.OnSystemMessage("TBM:CONFIG_END|2|2")
assert(TB.infoWindow.rows[2].label.text == "HireMaxBotsPerPlayer" and TB.infoWindow.rows[2].value.text == "4",
    "the settings render")
assert(chatFilters.CHAT_MSG_SYSTEM == nil or chatFilters.CHAT_MSG_SYSTEM(nil, nil, "Config: 2 keys match 'hire'.") == true,
    "the search summary stays out of the chat")
TB.SetServerInfoTab("main")
TB.CloseServerInfo()
TB.OpenRunWindow()
-- Mutual exclusion with the vault/NPC satellites.
TB.OpenBotPanel("Alpha")
TB.OpenVault("Alpha")
assert(not TB.runWindow:IsVisible() and TB.botVault:IsVisible(), "the vault closes the run window")
TB.OpenRunWindow()
assert(TB.runWindow:IsVisible() and not TB.botVault:IsVisible(), "the run window closes the vault")
TB.CloseBotPanel()
assert(not TB.runWindow:IsVisible(), "the run window closes with its parent")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.tabDungeon:IsVisible(), "losing the cap hides everything again")
assert(not TB.dungeonFrame:IsVisible(), "losing the cap leaves the Dungeon tab")
assert(TB.GetRun() == nil, "losing the cap drops the model")

-- ── Loot history tab: capability-gated catch-up stream ─────────────────────
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.tabLoot:IsVisible(), "no Loot tab without the capability")
assert(TB.RequestLootPage() == false, "nothing is sent without the capability")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,loot-log")
assert(TB.tabLoot:IsVisible(), "the capability shows the Loot tab")
now = now + 1
this = TB.tabLoot
TB.tabLoot.scripts.OnClick(TB.tabLoot)
assert(TB.lootFrame:IsVisible(), "the Loot tab shows its page")
assert(TB.lootRows and table.getn(TB.lootRows) == 11, "the Loot tab owns its scroll rows")

-- Catch-up on login starts from the stored cursor.
event, arg1 = "PLAYER_LOGIN", nil
coreFrame.scripts.OnEvent(coreFrame)
local lootQueue = frames["TortoiseBotsManagerQueueFrame"]
for _ = 1, 30 do
    if lastAddon() == "lootlog" then break end
    now = now + 1
    this, arg1 = lootQueue, 0.5
    lootQueue.scripts.OnUpdate(lootQueue)
end
assert(lastAddon() == "lootlog", "login asks for the first page without a cursor")
TortoiseBotsDB.loot = { Tester = { cursor = "piece@10", rows = {} } }
event, arg1 = "PLAYER_LOGIN", nil
-- NoteLootLogin runs once per session; a second call stays silent.
assert(TB.NoteLootLogin() == false, "login catch-up runs once per session")

-- Parsing of a LOOT line: item, money and roll rows.
local lootItem = TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:01|Alpha|StoreLootAction|2586|Gamemaster's Robe|corpse|Defias Thug|4")
assert(lootItem and lootItem.bot == "Alpha" and lootItem.itemId == 2586 and lootItem.quality == 4
    and lootItem.sourceType == "corpse" and lootItem.source == "Defias Thug", "item rows parse")
local lootMoney = TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:02|Gamma|LootMoney|812|1550|corpse|Kobold Vermin|")
assert(lootMoney and lootMoney.copper == 1550 and lootMoney.itemId == 812, "money rows carry copper and corpse entry")
local lootRoll = TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:03|Alpha|LootRoll|need:2586:for equiping as upgrade.|Gamemaster's Robe|corpse|Defias Thug|")
assert(lootRoll and lootRoll.vote == "need" and lootRoll.itemId == 2586 and lootRoll.item == "Gamemaster's Robe"
    and lootRoll.reason == "for equiping as upgrade.", "roll rows carry vote, item and reason")
local lootRollBare = TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:04|Alpha|LootRoll|pass:159:|Refreshing Spring Water|corpse|Murloc|")
assert(lootRollBare and lootRollBare.vote == "pass" and lootRollBare.reason == nil, "a missing reason stays empty")
assert(TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:05|Alpha|GatherLoot|7|8|corpse|X|") == nil,
    "unknown events are dropped")
assert(TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:06|Alpha|StoreLootAction|nope|Robe|corpse|X|4") == nil,
    "a bad item id drops the row")
assert(TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:07|Alpha|LootRoll|maybe:1:x|Robe|corpse|X|") == nil,
    "a bad vote drops the row")

-- Cursor handling: next page, empty end, expired restart.
TortoiseBotsDB.loot = nil
now = now + 1
TB.OnSystemMessage("TBM:LOOT_BEGIN|2|piece@99")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:02|Gamma|LootMoney|812|1550|corpse|Kobold Vermin|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:01|Alpha|StoreLootAction|2586|Gamemaster's Robe|corpse|Defias Thug|4")
TB.OnSystemMessage("TBM:LOOT_END|piece@99")
assert(TB.GetLootCursor() == "piece@99", "a page end stores its cursor")
assert(lastAddon() == "lootlog piece@99", "a page end asks for the next page")
local beforeExpired = table.getn(addonSent)
TB.OnSystemMessage("TBM:LOOT_BEGIN|1|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:03|Alpha|LootRoll|need:2586:for equiping as upgrade.|Gamemaster's Robe|corpse|Defias Thug|")
TB.OnSystemMessage("TBM:LOOT_END|")
assert(TB.GetLootCursor() == "", "an empty end clears the cursor")
assert(table.getn(addonSent) == beforeExpired, "an empty end asks for nothing more")
local history = TB.GetLootHistory()
assert(table.getn(history) == 3 and history[1].ts == "2026-10-27 12:00:03"
    and history[3].ts == "2026-10-27 12:00:01", "stored rows stay newest first")
assert(string.find(TB.lootRows[1].line.text, "Gamemaster's Robe", 1, true)
    and string.find(TB.lootRows[1].line.text, "Need", 1, true), "the newest row renders with its vote")
assert(string.find(TB.lootRows[2].line.text, "15s", 1, true), "money rows render as coins")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|lootlog|expired|Cursor piece was pruned.")
assert(TB.GetLootCursor() == "", "an expired cursor is dropped")
assert(lastAddon() == "lootlog", "an expired cursor restarts from the top")
now = now + 1
TB.OnSystemMessage("TBM:LOOT_BEGIN|0|expired")
TB.OnSystemMessage("TBM:LOOT_END|expired")
assert(TB.GetLootCursor() == "", "an expired page cursor is dropped")
assert(lastAddon() == "lootlog", "an expired page cursor restarts from the top")
TB.OnSystemMessage("TBM:ACTION_ERR|lootlog|no-bot|No live owned party bots are controllable.")
assert(TB.lastActionError and TB.lastActionError.code == "no-bot", "no-bot errors are reported")
TB.OnSystemMessage("TBM:ACTION_ERR|lootlog|invalid|Usage: .bot lootlog [cursor]")
assert(TB.lastActionError and TB.lastActionError.code == "invalid", "invalid errors are reported")

-- Dedupe on catch-up: a re-sent page adds nothing twice.
local beforeDedupe = table.getn(TB.GetLootHistory())
TB.OnSystemMessage("TBM:LOOT_BEGIN|2|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:02|Gamma|LootMoney|812|1550|corpse|Kobold Vermin|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:01|Alpha|StoreLootAction|2586|Gamemaster's Robe|corpse|Defias Thug|4")
TB.OnSystemMessage("TBM:LOOT_END|")
assert(table.getn(TB.GetLootHistory()) == beforeDedupe, "catch-up pages add no duplicates")
TB.OnSystemMessage("TBM:LOOT_BEGIN|1|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 11:00:00|Beta|StoreLootAction|1201|Old Sword|corpse|Old Mob|2")
TB.OnSystemMessage("TBM:LOOT_END|")
history = TB.GetLootHistory()
assert(table.getn(history) == beforeDedupe + 1 and history[table.getn(history)].bot == "Beta",
    "older catch-up rows slot into place, newest first")
-- The 2000-entry cap: the oldest rows drop.
local many = {}
for i = 1, 2002 do
    table.insert(many, { ts = "2026-10-27 12:" .. string.format("%02d", math.mod(i, 60)) .. ":00",
        bot = "Alpha", event = "LootMoney", itemId = i, item = tostring(i), copper = i,
        sourceType = "corpse", source = "Mob " .. i })
end
TB.ClearLootHistory()
assert(TB.MergeLootRows(many) == 2002, "a fresh page merges in full")
history = TB.GetLootHistory()
assert(table.getn(history) == 2000 and history[1].itemId == 1 and history[2000].itemId == 2000,
    "stored history caps at 2000 rows, oldest dropped")

-- Filters: bot, item, quality, source, row type, combined.
TB.ClearLootHistory()
TB.OnSystemMessage("TBM:LOOT_BEGIN|3|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:03|Alpha|LootRoll|need:2586:for equiping as upgrade.|Gamemaster's Robe|corpse|Defias Thug|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:02|Gamma|LootMoney|812|1550|corpse|Kobold Vermin|")
TB.OnSystemMessage("TBM:LOOT|2026-10-27 12:00:01|Alpha|StoreLootAction|2586|Gamemaster's Robe|corpse|Defias Thug|4")
TB.OnSystemMessage("TBM:LOOT_END|")
TB.SetLootFilter("bot", "gamma")
assert(table.getn(TB.GetFilteredLoot()) == 1, "the bot filter matches one bot")
TB.SetLootFilter("bot", "")
TB.SetLootFilter("item", "robe")
assert(table.getn(TB.GetFilteredLoot()) == 2, "the item filter matches item and roll rows")
TB.SetLootFilter("quality", 4)
assert(table.getn(TB.GetFilteredLoot()) == 1, "the quality filter keeps only that quality")
TB.SetLootFilter("quality", -1)
TB.SetLootFilter("item", "")
TB.SetLootFilter("source", "kobold")
assert(table.getn(TB.GetFilteredLoot()) == 1, "the source filter matches corpse names")
TB.SetLootFilter("source", "")
TB.SetLootFilter("rowType", "rolls")
assert(table.getn(TB.GetFilteredLoot()) == 1 and TB.GetFilteredLoot()[1].event == "LootRoll",
    "the rolls filter keeps only votes")
TB.SetLootFilter("rowType", "items")
assert(table.getn(TB.GetFilteredLoot()) == 2, "the items filter drops votes")
TB.SetLootFilter("bot", "alpha")
assert(table.getn(TB.GetFilteredLoot()) == 1, "filters combine")
TB.SetLootFilter("bot", "")
TB.SetLootFilter("rowType", "all")
TB.lootFrame.qualityStep.plus.scripts.OnClick(TB.lootFrame.qualityStep.plus)
assert(TB.GetLootFilters().quality == 0 and TB.lootFrame.qualityStep.label.text == "Poor",
    "the quality stepper cycles forward")
TB.lootFrame.qualityStep.minus.scripts.OnClick(TB.lootFrame.qualityStep.minus)
assert(TB.GetLootFilters().quality == -1 and TB.lootFrame.qualityStep.label.text == "Any",
    "the quality stepper cycles back")
TB.lootFrame.typeStep.plus.scripts.OnClick(TB.lootFrame.typeStep.plus)
assert(TB.GetLootFilters().rowType == "items" and TB.lootFrame.typeStep.label.text == "Items",
    "the row-type stepper cycles")
TB.lootFrame.typeStep.plus.scripts.OnClick(TB.lootFrame.typeStep.plus)
TB.lootFrame.typeStep.plus.scripts.OnClick(TB.lootFrame.typeStep.plus)
assert(TB.GetLootFilters().rowType == "all", "the row-type stepper wraps around")
-- The Clear button wipes this character's history.
assert(table.getn(TB.GetLootHistory()) == 3, "three rows are stored before the wipe")
TB.lootFrame.clearButton.scripts.OnClick(TB.lootFrame.clearButton)
assert(table.getn(TB.GetLootHistory()) == 0 and TB.GetLootCursor() == "", "Clear wipes rows and cursor")
assert(TB.lootFrame.emptyMsg:IsVisible(), "Clear shows the empty message")

-- Losing the capability hides the tab and sends nothing more.
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.tabLoot:IsVisible(), "losing the cap hides the Loot tab")
assert(TB.RequestLootPage() == false, "losing the cap stops the sends")

-- ── Guild orders (TBM#51): capability gate, permission, parsers ────────────
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.HasOrderCapability(), "no guild order controls without the capability")
assert(TB.RequestOrderList() == false, "order list is not sent without the capability")
assert(TB.SendOrderSearch("Goldie", "farm", "leather") == false, "order search is not sent without the capability")
assert(TB.SendOrderGive("Goldie", "farm", 2318, 10) == false, "order give is not sent without the capability")
assert(TB.SendOrderCancel("Goldie") == false, "order cancel is not sent without the capability")
assert(TB.OpenOrderWindow("Goldie") == false, "the order window stays closed without the capability")
TB.ShowTab("guild")
TB.RefreshGuildView()
assert(not TB.guildFrame.rows[1].ordBtn:IsVisible(), "no capability hides the Order button")
assert(not TB.guildFrame.rows[1].cancelBtn:IsVisible(), "no capability hides the Cancel button")

-- Permission gating: CanEditOfficerNote decides, re-checked every refresh.
canEditOfficerNote = false
function CanEditOfficerNote() return canEditOfficerNote end
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
assert(TB.HasOrderCapability(), "the guild-orders token enables orders")
TB.ShowTab("guild")
TB.RefreshGuildView()
local guildOrderRow = TB.guildFrame.rows[1]
assert(guildOrderRow.ordBtn:IsVisible() and not guildOrderRow.ordBtn.enabled,
    "without officer-note rights the Order button is greyed out")
canEditOfficerNote = true
TB.RefreshGuildView()
assert(guildOrderRow.ordBtn:IsVisible() and guildOrderRow.ordBtn.enabled,
    "with officer-note rights the Order button is enabled")
canEditOfficerNote = false
TB.RefreshGuildView()
assert(not guildOrderRow.ordBtn.enabled, "losing the right greys the button out again")
canEditOfficerNote = true

-- Guild tab open and poll ticks request the full list.
TB._lastOrderListAt = 0
now = now + 1
TB.ShowTab("guild")
assert(lastAddon() == "order list", "opening the Guild tab asks for the order list")
TB._lastOrderListAt = now - 31
now = now + 1
assert(TB.OrderPollTick() and lastAddon() == "order list", "the 30s tick re-asks for the order list")
assert(TB.OrderPollTick() == false, "no re-ask inside the 30s window")
TB.ShowTab("log")
TB._lastOrderListAt = now - 31
assert(TB.OrderPollTick() == false, "no re-ask while another tab is open")
TB.ShowTab("guild")

-- ORDER list parsing: full list replaces, live lines update one row.
local parsedOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale")
assert(parsedOrder and parsedOrder.bot == "Goldie" and parsedOrder.type == "farm"
    and parsedOrder.itemId == 2318 and parsedOrder.have == 4 and parsedOrder.want == 10
    and parsedOrder.state == "working" and parsedOrder.reason == nil
    and parsedOrder.zone == "Ashenvale", "order lines parse")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318") == nil, "a short order line is dropped")
local hoursOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3")
assert(hoursOrder and hoursOrder.hours == 3 and hoursOrder.difficulty == "easy", "an 11-field order line carries the farm hours")
assert(string.find(TB.OrderTooltipText(hoursOrder), "Farm time: 3 h", 1, true), "the order tooltip shows the farm hours")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy").hours == nil,
    "a 10-field order line has no hours")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|nope|Light Leather|4|10|working|-|Ashenvale") == nil,
    "a bad item id drops the order line")
now = now + 1
TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale")
TB.OnSystemMessage("TBM:ORDER|Silver|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
TB.OnSystemMessage("TBM:ORDER_END")
assert(table.getn(TB.GetOrders()) == 2, "the list holds both orders")
local goldieOrder = TB.GetBotOrder("Goldie")
assert(goldieOrder and goldieOrder.have == 4 and goldieOrder.zone == "Ashenvale",
    "the model keeps the full row")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|7|10|working|-|Ashenvale")
assert(TB.GetBotOrder("Goldie").have == 7 and table.getn(TB.GetOrders()) == 2,
    "a live line updates only that bot")
TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|7|10|working|-|Ashenvale")
TB.OnSystemMessage("TBM:ORDER_END")
assert(table.getn(TB.GetOrders()) == 1 and TB.GetBotOrder("Silver") == nil,
    "the next list replaces the whole set")

-- Row text and tooltips: progress, finished states, reason and zone.
assert(TB.OrderRowText(TB.GetBotOrder("Goldie")) == "Light Leather 7/10 (Ashenvale)",
    "working rows show item, progress and zone")
assert(TB.OrderRowText({ item = "Light Leather", have = 10, want = 10, state = "delivering", zone = "Ashenvale" })
    == "|cffffd200Delivering|r Light Leather", "delivering rows show the verb")
assert(TB.OrderRowText({ item = "Light Leather", have = 10, want = 10, state = "done" })
    == "Light Leather · |cff4ecb5aDone|r", "done rows show the state")
assert(TB.OrderRowText({ item = "Light Leather", have = 10, want = 10, state = "mailed" })
    == "Light Leather · |cffffd200Mailed to GM|r", "mailed rows name the guild master")
assert(TB.OrderRowText({ item = "Light Leather", have = 0, want = 10, state = "noskill" })
    == "Light Leather · |cffff5050No skill|r", "noskill rows use the plain label")
assert(TB.OrderRowText({ item = "Light Leather", have = 0, want = 10, state = "cant" })
    == "Light Leather · |cffff5050Can't|r", "cant rows use the plain label")
local tooltipOrder = TB.ParseOrderLine("TBM:ORDER|Silver|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
assert(TB.OrderTooltipText(tooltipOrder)
    == "Order: Buy Highland Spring Water 0/20\nState: Waiting (in a group)\nZone: Ironforge",
    "the tooltip carries type, progress, state, reason and zone")
assert(TB.OrderReasonLabel("-") == nil and TB.OrderSkillLabel("-") == nil,
    "dash fields mean none")
assert(TB.OrderReasonLabel("stuck") == "stuck, gave up", "known reasons get plain labels")
assert(TB.OrderSkillLabel("393:125") == "Skinning 125", "skill ids get their trade name")
assert(TB.OrderSkillLabel("999:12") == "Skill 999 12", "unknown skill ids stay readable")
assert(TB.OrderSourcesLabel({ "drop", "skin" }) == "drop, skin", "sources join with commas")
assert(TB.OrderSourcesLabel({ "ah" }) == "AH", "ah is capped")

-- Unknown state or reason tokens show raw, never crash.
local strangeOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|1|10|brewing|froth|-")
assert(strangeOrder and strangeOrder.state == "brewing" and strangeOrder.reason == "froth"
    and strangeOrder.zone == nil, "unknown tokens parse raw")
assert(TB.OrderRowText(strangeOrder) == "Light Leather 1/10 · brewing",
    "unknown states render raw")
assert(TB.OrderTooltipText(strangeOrder)
    == "Order: Farm Light Leather 1/10\nState: brewing (froth)",
    "unknown reasons render raw")
assert(TB.OrderStateLabel("brewing") == "brewing", "unknown state labels stay raw")
assert(TB.OrderReasonLabel("froth") == "froth", "unknown reason labels stay raw")

-- Keep in stock: the trailing keep field, stocked rows, keep markers.
local keepOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|keep")
assert(keepOrder and keepOrder.keep == true and keepOrder.hours == 3, "a 12-field order line carries keep")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|-").keep == false,
    "a dash keep parses as not keep")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3").keep == false,
    "an 11-field order line has no keep")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|keep|extra") == nil,
    "a 13-field order line is dropped")
assert(TB.OrderStateLabel("stocked") == "Stocked", "stocked gets the plain label")
assert(TB.OrderRowText({ item = "Light Leather", have = 10, want = 10, state = "stocked", keep = true })
    == "Light Leather · |cff4ecb5aStocked|r", "stocked rows show the state")
assert(TB.OrderRowText(keepOrder)
    == "Light Leather 4/10 (Ashenvale) · |cff4ecb5aKeep|r · |cff4ecb5aEasy|r",
    "keep rows mark the refill")
assert(string.find(TB.OrderTooltipText(keepOrder),
    "Keep in stock: the bot refills when the bank drops below 10", 1, true) ~= nil,
    "keep tooltips explain the refill")
local stockedOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|stocked|-|-|-|-|keep")
assert(string.find(TB.OrderTooltipText(stockedOrder),
    "Stocked: 10 in the bank, the bot refills when it drops below 10", 1, true) ~= nil,
    "stocked tooltips name the bank stock")

-- Estimates: amount ÷ chance, nodes for herb and ore, none for buy/craft.
assert(TB.OrderEstimate("farm", { "skin" }, 50, 10) == "about 20 kills", "a 50% chance doubles the kills")
assert(TB.OrderEstimate("farm", { "ore" }, 100, 10) == "about 10 nodes", "ore counts nodes")
assert(TB.OrderEstimate("farm", { "herb" }, 25, 10) == "about 40 nodes", "herb counts nodes")
assert(TB.OrderEstimate("farm", { "skin" }, 100, 1) == "about 1 kill", "one kill stays singular")
assert(TB.OrderEstimate("buy", { "ah" }, 100, 10) == nil, "buy shows no estimate")
assert(TB.OrderEstimate("craft", { "craft" }, 100, 10) == nil, "craft shows no estimate")
assert(TB.OrderEstimate("farm", { "skin" }, 0, 10) == nil, "a zero chance shows no estimate")

-- Search item parsing and verdict details.
local searchItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50")
assert(searchItem and searchItem.itemId == 2319 and searchItem.quality == 1
    and table.getn(searchItem.sources) == 2 and searchItem.minLevel == 16
    and searchItem.skill == "393:100" and searchItem.verdict == "ok"
    and searchItem.zone == "Ashenvale" and searchItem.chance == 50
    and searchItem.difficulty == nil, "search items parse (old 10-field lines have no difficulty)")
local searchItemHard = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50|hard")
assert(searchItemHard and searchItemHard.difficulty == "hard", "search items parse the new difficulty field")
local searchItemDash = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50|-")
assert(searchItemDash and searchItemDash.difficulty == nil, "a dash difficulty parses as none")
assert(TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319") == nil, "a short search line is dropped")
assert(TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop|16|-|ok|Ashenvale") == nil,
    "a short chance field drops the search line")
assert(TB.OrderItemDetail(searchItem, "farm", 10, 24) == "drop, skin · lvl 16+ · Skinning 100 · Ashenvale · about 20 kills · 50% drop",
    "a good result shows sources, level, skill, zone, estimate and drop rate")
assert(TB.OrderItemDetail(searchItemHard, "farm", 10, 24)
    == "drop, skin · lvl 16+ · Skinning 100 · Ashenvale · about 20 kills · 50% drop · |cffff5050Hard|r",
    "a good result shows the difficulty word")
assert(TB.OrderItemDetail(searchItem, "buy", 10, 24) == "drop, skin · lvl 16+ · Skinning 100 · Ashenvale",
    "buy results hide the kill estimate")
assert(TB.OrderDropRate("farm", { "skin" }, 50) == "50% drop", "kills show the drop rate")
assert(TB.OrderDropRate("farm", { "ore" }, 100) == nil, "nodes at 100% show no drop rate")
assert(TB.OrderDropRate("farm", { "skin" }, 0) == nil, "a zero chance shows no drop rate")
assert(TB.OrderDropRate("buy", { "ah" }, 50) == nil, "buy shows no drop rate")
assert(TB.OrderDifficultyLabel("easy") == "|cff4ecb5aEasy|r", "easy gets the plain word")
assert(TB.OrderDifficultyLabel("medium") == "|cffffd200Medium|r", "medium gets the plain word")
assert(TB.OrderDifficultyLabel("hard") == "|cffff5050Hard|r", "hard gets the plain word")
assert(TB.OrderDifficultyLabel("-") == nil and TB.OrderDifficultyLabel(nil) == nil,
    "a dash difficulty shows nothing")
assert(TB.OrderReasonLabel("elite") == "only from elite creatures", "elite gets a plain reason")
assert(TB.OrderReasonLabel("timeout") == "farm time ran out", "timeout gets a plain reason")
local searchItemCat = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50|hard|leather")
assert(searchItemCat and searchItemCat.difficulty == "hard" and searchItemCat.category == "leather",
    "search items parse the new category field")
local searchItemCatDash = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50|hard|-")
assert(searchItemCatDash and searchItemCatDash.category == nil, "a dash category parses as none")
assert(TB.OrderCatLabel("leather") == "Leather" and TB.OrderCatLabel("all") == "All"
    and TB.OrderCatLabel("-") == nil, "kind labels read plainly")
local skillItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|noskill|-|0")
assert(TB.OrderItemDetail(skillItem, "farm", 10, 12) == "needs Skinning",
    "a noskill verdict names the trade")
local lowItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|lowskill|-|0")
assert(TB.OrderItemDetail(lowItem, "farm", 10, 12) == "needs Skinning 100",
    "a lowskill verdict names the skill value")
local rangeItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|-|norange|-|0")
assert(TB.OrderItemDetail(rangeItem, "farm", 10, 12) == "no source near level 12",
    "a norange verdict names the bot level")
local herbItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|765|Silverleaf|1|herb|1|182:1|lowlevel|-|0")
assert(TB.OrderItemDetail(herbItem, "farm", 10, 8) == "needs level 10",
    "a lowlevel verdict names level 10")
local eliteItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|-|elite|-|0")
assert(TB.OrderItemDetail(eliteItem, "farm", 10, 12) == "Can't: only from elite creatures",
    "an elite verdict names the elite rule")
local strangeItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|-|soggy|-|0")
assert(TB.OrderItemDetail(strangeItem, "farm", 10, 12) == "Can't: soggy",
    "an unknown verdict renders raw")
assert(TB.OrderItemDetail(nil, "farm", 10, 12) == "", "a missing item has no detail")
assert(TB.OrderItemDetail(searchItemCat, "farm", 10, 24)
    == "drop, skin · Leather · lvl 16+ · Skinning 100 · Ashenvale · about 20 kills · 50% drop · |cffff5050Hard|r",
    "a good result shows the item kind")
assert(TB.OrderSourcesLabel({ "fish" }) == "fish", "fish sources read plainly")
assert(TB.OrderEstimate("farm", { "fish" }, 50, 10) == "about 20 casts", "fish counts casts")
assert(TB.OrderEstimate("farm", { "fish" }, 100, 1) == "about 1 cast", "one cast stays singular")
local lowZoneItem = TB.ParseOrderItemLine("TBM:ORDER_ITEM|6358|Raw Summer Bass|1|fish|1|356:150|lowskill|Ashenvale|30")
assert(TB.OrderItemDetail(lowZoneItem, "farm", 10, 20) == "needs Fishing 150 (Ashenvale)",
    "a lowskill verdict names the lower zone")

-- Order rows carry the difficulty, old 9-field lines still parse.
local orderWithDiff = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy")
assert(orderWithDiff and orderWithDiff.difficulty == "easy", "order lines parse the new difficulty field")
assert(TB.OrderRowText(orderWithDiff) == "Light Leather 4/10 (Ashenvale) · |cff4ecb5aEasy|r",
    "order rows show the difficulty word")
assert(TB.OrderRowText(parsedOrder) == "Light Leather 4/10 (Ashenvale)",
    "old order lines show no difficulty")
assert(string.find(TB.OrderTooltipText(orderWithDiff), "Difficulty: |cff4ecb5aEasy|r", 1, true) ~= nil
    and string.find(TB.OrderTooltipText(orderWithDiff),
        "Rough effort for this bot: how many kills, gathers or casts it needs", 1, true) ~= nil,
    "order tooltips explain the difficulty")
assert(TB.OrderTooltipText(parsedOrder)
    == "Order: Farm Light Leather 4/10\nState: Working\nZone: Ashenvale",
    "old order tooltips stay unchanged")

-- Farm time: hours clamp, the give carries them, an old server falls back.
assert(TB.ClampOrderHours(0) == 1 and TB.ClampOrderHours(99) == 24,
    "hours clamp to 1-24")

-- The order window: search debounce, results, kind, amount, send.
assert(TB.OpenOrderWindow("Goldie"), "the window opens for a guild bot")
assert(TB.orderWindow:IsVisible() and TB.GetOrderWindowBot() == "Goldie",
    "the window tracks its bot")
assert(TB.orderWindow.title:GetText() == "Order for Goldie", "the title names the bot")
assert(TB.orderWindow.statusLine:GetText() == "Current: Light Leather 7/10 (Ashenvale)",
    "the window shows the bot's current order")
assert(TB.orderWindow.amountBox:GetText() == "10", "a fresh window starts at 10")
assert(TB.orderWindow.hoursBox:GetText() == "1", "farm time starts at 1 hour")
assert(TB.orderWindow.farmNote ~= nil
    and string.find(TB.orderWindow.farmNote:GetText(), "Bots farm like players", 1, true) ~= nil,
    "the window warns that big or rare farms take very long")
local beforeSearch = table.getn(addonSent)
this = TB.orderWindow.searchBox
TB.orderWindow.searchBox.text = "le"
TB.orderWindow.searchBox.scripts.OnTextChanged(TB.orderWindow.searchBox)
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(table.getn(addonSent) == beforeSearch, "short text never goes out")
assert(TB.orderWindow.emptyMsg:IsVisible(), "short text explains the 3-letter rule")
TB.orderWindow.searchBox.text = "leather"
TB.orderWindow.searchBox.scripts.OnTextChanged(TB.orderWindow.searchBox)
now = now + 0.1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(table.getn(addonSent) == beforeSearch, "typing waits for the pause")
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(lastAddon() == "order search Goldie farm leather", "the pause sends one search")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|noskill|-|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
local found = TB.GetOrderSearch()
assert(table.getn(found.items) == 2 and found.bot == "Goldie",
    "the search lands on the window's bot")
local firstResult = TB.orderWindow.resultRows[1]
assert(firstResult:IsVisible() and string.find(firstResult.name:GetText(), "Light Leather", 1, true)
    and string.find(firstResult.detail:GetText(), "about 15 kills", 1, true),
    "a good result shows the estimate for the amount")
assert(string.find(firstResult.detail:GetText(), "70% drop", 1, true) ~= nil,
    "a good result shows the drop rate next to the estimate")
local secondResult = TB.orderWindow.resultRows[2]
assert(secondResult:IsVisible() and string.find(secondResult.detail:GetText(), "needs Skinning", 1, true),
    "an unusable result explains itself")
this = secondResult
secondResult.scripts.OnClick(secondResult)
assert(TB.GetOrderSelection() == nil and TB.GetOrderFeedback() ~= nil,
    "an unusable result cannot be picked")
this = firstResult
firstResult.scripts.OnClick(firstResult)
assert(TB.GetOrderSelection() == 2318, "a good result is picked")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 1", "Send gives the picked item, amount and farm time")
assert(string.find(TB.GetOrderFeedback().text, "sent, waiting"), "Send says it is waiting")
TB.SetOrderHours(3)
assert(TB.GetOrderHours() == 3 and TB.orderWindow.hoursBox:GetText() == "3",
    "the hours box follows the setter")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 3", "Send uses the farm time box")
-- An old server rejects the trailing hours: the addon retries without them.
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10", "an invalid-arg reply retries the give bare")
assert(string.find(TB.GetOrderFeedback().text, "retrying without farm time"), "the retry says so")
-- Keep in stock: the checkbox rides Send, and old servers shed it first.
assert(TB.GetOrderKeep() == false and not TB.orderWindow.keepBox:GetChecked(),
    "keep starts off")
this = TB.orderWindow.keepBox
TB.orderWindow.keepBox:SetChecked(true)
TB.orderWindow.keepBox.scripts.OnClick(TB.orderWindow.keepBox)
assert(TB.GetOrderKeep() == true, "ticking the box arms keep")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 3 keep", "Send carries keep when ticked")
assert(string.find(TB.GetOrderFeedback().text, "(3h, keep) sent, waiting", 1, true) ~= nil,
    "Send names keep while waiting")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10 3", "an invalid-arg reply drops keep first")
assert(string.find(TB.GetOrderFeedback().text, "retrying without keep in stock"), "the keep retry says so")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10", "a second invalid-arg reply drops the farm time")
TB.SetOrderKeep(false)
assert(TB.GetOrderKeep() == false and not TB.orderWindow.keepBox:GetChecked(),
    "the setter clears the box")
assert(TB.ClampOrderAmount(0) == 1 and TB.ClampOrderAmount(999) == 200,
    "amounts clamp to 1-200")
TB.SetOrderAmount(25)
assert(TB.GetOrderAmount() == 25 and TB.orderWindow.amountBox:GetText() == "25",
    "the amount box follows the setter")
assert(string.find(firstResult.detail:GetText(), "about 36 kills", 1, true),
    "the estimate follows the amount")

-- Kind filter: picking a kind browses it (empty text allowed); All restores.
now = now + 1
assert(TB.SetOrderCat("bogus") == false and TB.GetOrderCat() == nil, "an unknown kind is refused")
TB.orderWindow.searchBox.text = ""
now = now + 1
local beforeCat = table.getn(addonSent)
assert(TB.SetOrderCat("leather"), "the kind filter picks leather")
assert(TB.GetOrderCat() == "leather", "the filter tracks the kind")
assert(table.getn(addonSent) == beforeCat + 1 and lastAddon() == "order search Goldie farm cat=leather",
    "picking a kind browses it without text")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70|easy|leather")
TB.OnSystemMessage("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|noskill|-|0|-|leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
assert(table.getn(TB.GetOrderSearch().items) == 2 and TB.GetOrderSearch().cat == "leather",
    "the filtered search lands with its kind")
now = now + 1
TB.orderWindow.searchBox.text = "light"
TB.orderWindow.searchBox.scripts.OnTextChanged(TB.orderWindow.searchBox)
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(lastAddon() == "order search Goldie farm cat=leather light",
    "a filtered search keeps the kind with text")
-- An old server rejects cat=: the addon retries once without it.
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order search Goldie farm light", "an invalid-arg reply retries the search bare")
assert(string.find(TB.GetOrderFeedback().text, "retrying without the kind filter"),
    "the retry says the filter was dropped")
assert(TB.SetOrderCat("all") and TB.GetOrderCat() == nil, "All clears the filter")
assert(TB.OrderCatBrowsable("herb") and TB.OrderCatBrowsable("cloth")
    and not TB.OrderCatBrowsable("drop") and not TB.OrderCatBrowsable("other")
    and not TB.OrderCatBrowsable("-"), "only small kinds browse empty")

-- Big kinds need text: picking Drops empty sends nothing and hints instead.
TB.orderWindow.searchBox.text = ""
now = now + 1
local beforeBig = table.getn(addonSent)
assert(TB.SetOrderCat("drop"), "the kind filter picks drops")
assert(TB.GetOrderCat() == "drop", "the filter tracks the big kind")
assert(table.getn(addonSent) == beforeBig, "an empty big-kind browse sends nothing")
assert(string.find(TB.GetOrderFeedback().text, "Type at least 3 letters to search drops", 1, true),
    "an empty big-kind browse hints at text")
assert(TB.SendOrderSearch("Goldie", "farm", "", "drop") == false
    and TB.SendOrderSearch("Goldie", "farm", "", "other") == false,
    "empty big-kind searches are refused")
assert(TB.SendOrderSearch("Goldie", "farm", "dr", "drop") == false,
    "short text with a big kind still needs 3 letters")
now = now + 1
TB.orderWindow.searchBox.text = "dev"
TB.orderWindow.searchBox.scripts.OnTextChanged(TB.orderWindow.searchBox)
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(lastAddon() == "order search Goldie farm cat=drop dev",
    "text with a big kind sends the filtered search")
-- A with-text filtered search still retries bare on an old-server invalid.
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order search Goldie farm dev", "an invalid-arg reply retries the search bare")
assert(string.find(TB.GetOrderFeedback().text, "retrying without the kind filter"),
    "the retry says the filter was dropped")
assert(TB.SetOrderCat("all") and TB.GetOrderCat() == nil, "All clears the big kind")
now = now + 1
local beforeKind = table.getn(addonSent)
TB.SetOrderKind("buy")
assert(TB.GetOrderKind() == "buy", "the kind switches")
assert(table.getn(addonSent) == beforeKind + 1 and lastAddon() == "order search Goldie buy dev",
    "a kind switch re-runs a valid search")
assert(TB.SetOrderKind("steal") == false and TB.GetOrderKind() == "buy",
    "an unknown kind is refused")
TB.SetOrderKind("farm")
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|farm")
assert(not TB.orderWindow:IsVisible(), "a give ACK closes the window")
assert(TB.lastActionAck and TB.lastActionAck.intent == "order"
    and TB.lastActionAck.executor == "farm", "a give ACK is recorded")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|25|working|-|Ashenvale")
assert(guildOrderRow.orderLine:GetText() == "Light Leather 0/25 (Ashenvale)",
    "the live line repaints the guild row")
assert(guildOrderRow.cancelBtn:IsVisible() and guildOrderRow.cancelBtn.enabled,
    "an order shows an enabled Cancel")
now = now + 1
this = guildOrderRow.cancelBtn
local beforeCancel = table.getn(addonSent)
guildOrderRow.cancelBtn.scripts.OnClick(guildOrderRow.cancelBtn)
assert(table.getn(addonSent) == beforeCancel, "row Cancel sends nothing before the confirm")
assert(lastPopupShown == "TORTOISEBOTSMANAGER_CANCEL_ORDER", "row Cancel asks first")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"] ~= nil, "cancel dialog must exist")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].text
    == "Cancel Goldie's order for 25x Light Leather?\n\nCancelling also ends keep-in-stock and no-limit orders.",
    "the confirm names the bot and item")
StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
assert(lastAddon() == "order Goldie cancel", "confirming asks for the removal")
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
assert(TB.GetBotOrder("Goldie") == nil, "a cancel ACK drops the row at once")
assert(string.find(guildOrderRow.orderLine:GetText(), "No order", 1, true),
    "a cancelled row falls back to No order")
assert(not guildOrderRow.cancelBtn:IsVisible(), "no order hides Cancel")

-- Errors ride the window feedback plus the generic status line.
assert(TB.OpenOrderWindow("Goldie"), "the window reopens")
TB.OnSystemMessage("TBM:ACTION_ERR|order|forbidden|Your rank may not give orders.")
assert(string.find(TB.GetOrderFeedback().text, "Your rank may not give orders.", 1, true),
    "the window shows the refusal")
assert(TB.lastActionError and TB.lastActionError.intent == "order"
    and TB.lastActionError.code == "forbidden", "the order error is recorded")
TB.CloseOrderWindow()

-- A kind with no text still searches (browse that kind).
assert(TB.OpenOrderWindow("Silver"), "the window opens for another bot")
TB.orderWindow.searchBox.text = ""
now = now + 1
assert(TB.SetOrderCat("ore"), "a kind browses with empty text")
assert(lastAddon() == "order search Silver farm cat=ore", "an empty filtered search goes out")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
assert(table.getn(TB.GetOrderSearch().items) == 0, "an empty filtered search is a real answer")
assert(TB.SetOrderCat("all") and TB.GetOrderCat() == nil, "the filter clears again")
TB.orderWindow.searchBox.text = "leather"
-- An empty search answer clears the list instead of hanging.
now = now + 1
TB.SendOrderSearch("Silver", "farm", "leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
assert(table.getn(TB.GetOrderSearch().items) == 0, "an empty search is a real answer")
assert(TB.orderWindow.emptyMsg:IsVisible()
    and string.find(TB.orderWindow.emptyMsg:GetText(), "No matching items.", 1, true),
    "an empty search says so")
TB.CloseOrderWindow()
assert(TB.GetOrderWindowBot() == nil, "a closed window tracks no bot")

-- Orders survive a roster-agnostic CAPS refresh but not losing the token.
TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|1|10|working|-|Ashenvale")
TB.OnSystemMessage("TBM:ORDER_END")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,loot-log")
assert(TB.GetBotOrder("Goldie") ~= nil, "a CAPS line with the token keeps orders")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
assert(not TB.HasOrderCapability(), "CAPS is re-checked on every line")
assert(table.getn(TB.GetOrders()) == 0, "losing the cap drops the model")
assert(TB.RequestOrderList() == false and TB.SendOrderCancel("Goldie") == false,
    "losing the cap stops the sends")
TB.RefreshGuildView()
assert(not TB.guildFrame.rows[1].ordBtn:IsVisible(), "losing the cap hides the buttons again")
assert(TB.OrderPollTick() == false, "losing the cap stops the poll tick")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
canEditOfficerNote = true

-- Round 2: the amount box commits while typing, Send reads the box, and a
-- refresh never wipes a valid typed number.
assert(TB.OpenOrderWindow("Goldie"), "round 2 reopens the window")
local amountBox = TB.orderWindow.amountBox
amountBox.text = "50"
this = amountBox
amountBox.scripts.OnTextChanged(amountBox)
assert(TB.GetOrderAmount() == 50, "typing commits the amount at once")
assert(amountBox:GetText() == "50", "committing keeps the typed text")
TB.RefreshOrderWindow()
assert(amountBox:GetText() == "50" and TB.GetOrderAmount() == 50,
    "a refresh keeps a valid typed number")
TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|2|10|working|-|Ashenvale")
assert(amountBox:GetText() == "50", "a live update keeps the typed number")
amountBox.text = "abc"
amountBox.scripts.OnTextChanged(amountBox)
assert(TB.GetOrderAmount() == 50, "non-numeric text does not commit")
TB.RefreshOrderWindow()
assert(amountBox:GetText() == "abc", "a refresh keeps a half-typed edit")
this = amountBox
amountBox.scripts.OnEditFocusLost(amountBox)
assert(amountBox:GetText() == "50", "focus loss restores the committed amount")
amountBox.text = "25"
amountBox.scripts.OnTextChanged(amountBox)
assert(TB.GetOrderAmount() == 25, "typing again commits the new number")
TB.SetOrderAmount(10)
amountBox.text = "25"
-- No OnTextChanged here: Send must read the box itself.
now = now + 1
TB.orderWindow.searchBox.text = "leather"
TB.SendOrderSearch("Goldie", "farm", "leather")
TB.orderWindow.resultRows[1].item = nil
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|noskill|-|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
this = TB.orderWindow.resultRows[1]
TB.orderWindow.resultRows[1].scripts.OnClick(TB.orderWindow.resultRows[1])
assert(TB.GetOrderSelection() == 2318, "round 2 picks the item")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(TB.GetOrderAmount() == 25, "Send commits the box number")
assert(lastAddon() == "order Goldie farm 2318 25 1", "Send sends the box number, not the stale amount")
local hoursBox = TB.orderWindow.hoursBox
hoursBox.text = "4"
this = hoursBox
hoursBox.scripts.OnTextChanged(hoursBox)
assert(TB.GetOrderHours() == 4, "typing commits the hours at once")
hoursBox.text = "abc"
hoursBox.scripts.OnTextChanged(hoursBox)
assert(TB.GetOrderHours() == 4, "non-numeric hours do not commit")
TB.RefreshOrderWindow()
assert(hoursBox:GetText() == "abc", "a refresh keeps a half-typed hours edit")
this = hoursBox
hoursBox.scripts.OnEditFocusLost(hoursBox)
assert(hoursBox:GetText() == "4", "hours focus loss restores the committed hours")
assert(TB.ClampOrderHours("0") == 1 and TB.ClampOrderHours("30") == 24 and TB.ClampOrderHours("abc") == 1,
    "hours clamp text to 1-24")

-- Round 2: unusable results carry no quality escape, so the grey sticks.
TB.orderWindow.searchBox.text = "leather"
now = now + 1
TB.SendOrderSearch("Goldie", "farm", "leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|noskill|-|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
local goodRow, badRow = TB.orderWindow.resultRows[1], TB.orderWindow.resultRows[2]
assert(string.find(goodRow.name:GetText(), "|cff", 1, true) ~= nil,
    "a usable result keeps its quality colour")
assert(badRow.name:GetText() == "Medium Leather", "an unusable result has no colour escape")
assert(badRow.name.textColor[1] == 0.45, "an unusable result is greyed")

-- Round 2: the order window and the other satellites exclude each other.
assert(TB.orderWindow:IsVisible(), "the order window is open")
TB.OpenBotPanel("Goldie")
assert(not TB.orderWindow:IsVisible() and TB.botPanel:IsVisible(),
    "the bot panel closes the order window")
now = now + 1
assert(TB.OpenOrderWindow("Goldie"), "the order window reopens")
assert(TB.orderWindow:IsVisible() and not TB.botPanel:IsVisible(),
    "the order window closes the bot panel")
TB.OpenServerInfo()
assert(not TB.orderWindow:IsVisible() and TB.infoWindow:IsVisible(),
    "the info window closes the order window")
assert(TB.OpenOrderWindow("Goldie"), "the order window reopens again")
assert(TB.orderWindow:IsVisible() and not TB.infoWindow:IsVisible(),
    "the order window closes the info window")
TB.CloseOrderWindow()
TB.CloseServerInfo()

-- No time limit: parse inf, show "no limit", send inf; a refused inf
-- retries once as 24 hours. Old numeric rows still parse.
local infOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|inf")
assert(infOrder and infOrder.hours == "inf", "an inf order line parses")
assert(string.find(TB.OrderRowText(infOrder), "No limit", 1, true) ~= nil,
    "inf rows show no limit")
assert(string.find(TB.OrderTooltipText(infOrder), "Farm time: no limit", 1, true) ~= nil,
    "inf tooltips show no limit")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|INF").hours == "inf",
    "INF parses in any case")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3").hours == 3,
    "numeric hours still parse")
assert(TB.OpenOrderWindow("Goldie"), "the window reopens for no-limit")
assert(TB.GetOrderNoLimit() == false and not TB.orderWindow.noLimitBox:GetChecked(),
    "no limit starts off")
TB.orderWindow.noLimitBox:SetChecked(true)
this = TB.orderWindow.noLimitBox
TB.orderWindow.noLimitBox.scripts.OnClick(TB.orderWindow.noLimitBox)
assert(TB.GetOrderNoLimit() == true, "ticking the box arms no limit")
assert(TB.orderWindow.hoursBox.mouseEnabled == false
    and TB.orderWindow.hoursBox.textColor[1] == 0.5,
    "no limit greys the hours box")
TB.SetOrderNoLimit(false)
assert(TB.GetOrderNoLimit() == false and not TB.orderWindow.noLimitBox:GetChecked(),
    "the setter clears no limit")
assert(TB.orderWindow.hoursBox.mouseEnabled ~= false
    and TB.orderWindow.hoursBox.textColor[1] == 1,
    "clearing no limit restores the hours box")
TB.orderWindow.searchBox.text = "leather"
now = now + 1
TB.SendOrderSearch("Goldie", "farm", "leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
this = TB.orderWindow.resultRows[1]
TB.orderWindow.resultRows[1].scripts.OnClick(TB.orderWindow.resultRows[1])
assert(TB.GetOrderSelection() == 2318, "no-limit picks the item")
TB.SetOrderAmount(10)
TB.SetOrderKeep(false)
TB.orderWindow.noLimitBox:SetChecked(true)
this = TB.orderWindow.noLimitBox
TB.orderWindow.noLimitBox.scripts.OnClick(TB.orderWindow.noLimitBox)
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 inf", "Send carries inf when ticked")
assert(string.find(TB.GetOrderFeedback().text, "(no limit) sent, waiting", 1, true) ~= nil,
    "Send names no limit while waiting")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|bad hours")
assert(lastAddon() == "order Goldie farm 2318 10 24", "a refused inf retries once as 24 hours")
assert(string.find(TB.GetOrderFeedback().text, "retrying with 24 hours", 1, true) ~= nil,
    "the inf retry says so")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10", "a second invalid reply drops the farm time")
TB.SetOrderNoLimit(true)
TB.SetOrderKeep(true)
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 inf keep", "Send carries inf with keep after it")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10 inf", "keep still sheds first on an inf give")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|bad hours")
assert(lastAddon() == "order Goldie farm 2318 10 24", "then a refused inf retries as 24")
TB.SetOrderNoLimit(false)
TB.SetOrderKeep(false)

-- Cancel stays reachable on every long-lived order, from the window and
-- the Guild tab row. Both ask first; only Yes sends.
local states = { "working", "waiting", "delivering" }
for _, state in ipairs(states) do
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|" .. state .. "|-|Ashenvale|easy|3")
    TB.RefreshGuildView()
    TB.RefreshOrderWindow()
    assert(guildOrderRow.cancelBtn:IsVisible() and guildOrderRow.cancelBtn.enabled,
        "row Cancel stays enabled while " .. state)
    assert(TB.orderWindow:IsVisible() and TB.orderWindow.cancelBtn.enabled,
        "window Cancel stays enabled while " .. state)
end
local longLived = {
    "TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|inf",
    "TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|stocked|-|-|-|-|keep",
}
for _, line in ipairs(longLived) do
    TB.OnSystemMessage(line)
    TB.RefreshGuildView()
    TB.RefreshOrderWindow()
    local order = TB.GetBotOrder("Goldie")
    assert(order ~= nil, "the long-lived order lands")
    assert(guildOrderRow.cancelBtn:IsVisible() and guildOrderRow.cancelBtn.enabled,
        "row Cancel stays enabled for a long-lived order")
    assert(TB.orderWindow:IsVisible() and TB.orderWindow.cancelBtn.enabled,
        "window Cancel stays enabled for a long-lived order")
    this = TB.orderWindow.cancelBtn
    local beforeWindowCancel = table.getn(addonSent)
    TB.orderWindow.cancelBtn.scripts.OnClick(TB.orderWindow.cancelBtn)
    assert(table.getn(addonSent) == beforeWindowCancel,
        "window Cancel sends nothing before the confirm")
    assert(lastPopupShown == "TORTOISEBOTSMANAGER_CANCEL_ORDER",
        "window Cancel asks first")
    now = now + 1
    StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
    assert(lastAddon() == "order Goldie cancel", "confirming the window Cancel sends")
    this = guildOrderRow.cancelBtn
    local beforeRowCancel = table.getn(addonSent)
    guildOrderRow.cancelBtn.scripts.OnClick(guildOrderRow.cancelBtn)
    assert(table.getn(addonSent) == beforeRowCancel,
        "row Cancel sends nothing before the confirm")
    now = now + 1
    StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
    assert(lastAddon() == "order Goldie cancel", "confirming the row Cancel sends")
end
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
assert(TB.GetBotOrder("Goldie") == nil, "the last confirm clears the row")
TB.CloseOrderWindow()
dofile(root .. "/tests/wire_cases.lua")({
    sent = sent,
    addonSent = addonSent,
    frames = frames,
    getNow = function() return now end,
    setNow = function(v) now = v end,
    advanceTime = function(dt) now = now + (dt or 1) end,
    setTarget = function(exists, name) targetExists = exists; targetNameValue = name end,
    setParty = function(members, className) partyMembers = members or {}; partyClassName = className or "Priest" end,
    setDead = function(unit, dead) deadUnits[unit] = dead end,
    setGhost = function(unit, ghost) ghostUnits[unit] = ghost end,
    seedItem = function(id, item) itemCache[id] = item end,
})

dofile(root .. "/tests/geometry_tests.lua")()

dofile(root .. "/tests/phase0_tests.lua")()

print("PASS: TortoiseBotsManager regression checks")

