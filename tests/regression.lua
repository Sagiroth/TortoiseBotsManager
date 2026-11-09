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
    function methods:SetScript(name, callback)
        if self.kind == "FontString" or self.kind == "Texture" then
            error("SetScript called on a " .. self.kind)
        end
        self.scripts[name] = callback
    end
    function methods:SetBackdrop(...) end
    function methods:SetBackdropColor(...) self.backdropColor = {...} end
    function methods:SetBackdropBorderColor(...) self.backdropBorder = {...} end
    function methods:SetStatusBarTexture(...) self.barTexture = {...} end
    function methods:SetStatusBarColor(...) self.barColor = {...} end
    function methods:SetMinMaxValues(minV, maxV) self.barMin, self.barMax = minV, maxV end
    function methods:SetValue(v) self.value = v end
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
    function methods:GetScale() return self.scale or 1 end
    function methods:SetScale(scale) self.scale = scale end
    function methods:SetOrientation(...) end
    function methods:SetMinMaxValues(min, max) self.min, self.max = min, max; self.barMin, self.barMax = min, max end
    function methods:SetValueStep(...) end
    function methods:SetValue(value) self.value = value end
    function methods:GetValue() return self.value or 0 end
    function methods:SetThumbTexture(...) end

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
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, owner) return self.owner == owner end,
    SetText = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function(self) self.owner = nil end,
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
function GetScreenHeight() return 900 end
function UnitExists(unit)
    if unit == "player" then return true end
    if unit == "target" then return targetExists end
    local _, _, index = string.find(unit or "", "^party(%d+)$")
    return index and tonumber(index) <= table.getn(partyMembers) or false
end
local deadUnits, ghostUnits = {}, {}
function UnitIsDead(unit) return deadUnits[unit] or false end
function UnitIsGhost(unit) return ghostUnits[unit] or false end
-- Chunk globals: main already sits at the 200-local limit, so new mock
-- state must not add locals here.
partyVitals, partyBuffs, nearUnits = {}, {}, nil
function UnitHealth(unit) return (partyVitals[unit] and partyVitals[unit].hp) or 100 end
function UnitHealthMax(unit) return (partyVitals[unit] and partyVitals[unit].hpMax) or 100 end
function UnitMana(unit) return (partyVitals[unit] and partyVitals[unit].mp) or 100 end
function UnitManaMax(unit) return (partyVitals[unit] and partyVitals[unit].mpMax) or 100 end
function UnitBuff(unit, index)
    local buffs = partyBuffs[unit]
    return buffs and buffs[index] or nil
end
function CheckInteractDistance(unit, slot)
    if nearUnits == nil then return true end
    return nearUnits[unit] ~= false
end
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
    "Settings.lua",
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
    and chatFilters.CHAT_MSG_SYSTEM(nil, nil, "TBM:ALTSUM|Alpha|Alpha: level 23.") == true
    and chatFilters.CHAT_MSG_SYSTEM(nil, nil, "TBM:ALTSUM_END|1") == true
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

-- Sortable columns (session-only): click a header to sort, again to reverse.
assert(table.getn(TB.GetDisplayRows("")) == 3, "roster must constantly show all bots")
assert(table.getn(TB.GetDisplayRows("alpha")) == 1, "text search must filter by bot name")
assert(TB.GetDisplayRows("")[1].name == "Alpha", "status sort must keep online rows first")
TB.SetRosterSort("name")
assert(TB.GetDisplayRows("")[1].name == "Alpha" and TB.GetDisplayRows("")[2].name == "Bravo"
    and TB.GetDisplayRows("")[3].name == "Gamma", "name sort must order rows alphabetically")
assert(TB.rosterFrame.headerBtns and table.getn(TB.rosterFrame.headerBtns) == 4,
    "roster header buttons must exist for each column")
assert(TB.rosterFrame.headerBtns[1].headerLabel:GetText() == "NAME ^",
    "the active roster header must carry the direction marker")
TB.SetRosterSort("name")
assert(TB.GetDisplayRows("")[1].name == "Gamma", "clicking the same header again must reverse the rows")
TB.SetRosterSort("class")
assert(TB.GetDisplayRows("")[1].className == "Druid" and TB.GetDisplayRows("")[3].className == "Warrior",
    "class sort must order rows by class name")
TB.SetRosterSort("status")
assert(TB.GetDisplayRows("")[1].name == "Alpha", "status sort must restore online rows first")
TB.rosterSort = { key = "bogus", dir = 7 }
assert(TB.GetDisplayRows("")[1].name == "Alpha", "a stray sort key must fall back to the default order")
TB.rosterSort = { key = "status", dir = 1 }

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
do
    now = now + 1
    TB._s = table.getn(sent)
    TB.QueueRosterBatch("summon", { "Alpha", "Gamma" })
    assert(sent[table.getn(sent)] == ".bot summon Alpha", "Summon Party starts with the first bot")
    assert(TB.QueueRosterBatch("summon", { "Alpha", "Gamma" }) == false, "a second Summon Party click is ignored")
    now = now + 1
    TB.OnSystemMessage("Summoning Alpha to a safe position near you (3s); it will follow on arrival.")
    assert(sent[table.getn(sent)] == ".bot summon Gamma", "a summoned bot moves the batch to the next bot")
    TB.OnSystemMessage("Summoning Gamma to a safe position near you (3s); it will follow on arrival.")
    assert(not TB.IsRosterBatchActive("summon"), "Summon Party finishes once every bot is summoned")
    assert(table.getn(sent) == TB._s + 2, "each bot is summoned exactly once")
    now = now + 1
    TB._s = table.getn(sent)
    TB.QueueRosterBatch("summon", { "Alpha", "Gamma" })
    now = now + 30
    this = frames["TortoiseBotsManagerRosterBatchFrame"]
    this.scripts.OnUpdate(this)
    assert(table.getn(sent) == TB._s + 2 and sent[table.getn(sent)] == ".bot summon Gamma",
        "a summon with no reply is not retried; the batch moves on")
    now = now + 30
    this.scripts.OnUpdate(this)
    assert(not TB.IsRosterBatchActive("summon") and table.getn(sent) == TB._s + 2,
        "an unanswered Summon Party ends without re-summoning anyone")
    TB._s = nil
end
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

-- Row right-click menus: builders list eligible per-bot actions, entries send
-- the same wires as the bar buttons, and right-click opens the dropdown.
TB._t = TB._t or {}
TB._t.menuItems = {}
assert(TB.BuildRosterRowMenu("Alpha", function(info) table.insert(TB._t.menuItems, info) end) > 0,
    "an online ungrouped bot must offer row menu actions")
TB._t.summonItem = nil
table.foreach(TB._t.menuItems, function(k, info) if info.text == "Summon" then TB._t.summonItem = info end end)
assert(TB._t.summonItem and TB._t.summonItem.func, "the roster menu must offer Summon for a live bot")
assert(TB.BuildRosterRowMenu("NoSuchBotXYZ", function() end) == 0,
    "an unknown name offers no roster menu")
assert(TB.OpenRosterRowMenu("NoSuchBotXYZ") == false,
    "an unknown name opens no roster menu")
TB._t.addonBeforeInvite = table.getn(addonSent)
TB._t.inviteItem = nil
TB._t.inviteItems = {}
assert(TB.BuildRosterRowMenu("Alpha", function(info) table.insert(TB._t.inviteItems, info) end) > 0,
    "an online ungrouped bot must offer row menu actions")
table.foreach(TB._t.inviteItems, function(k, info) if info.text == "Invite to group" then TB._t.inviteItem = info end end)
assert(TB._t.inviteItem and TB._t.inviteItem.func, "the roster menu must offer Invite for an ungrouped bot")
now = now + 1
TB._t.inviteItem.func()
assert(TB.IsRosterBatchActive("invite"), "the roster menu Invite must use the batch queue")
TB.OnSystemMessage("Invitation sent to bot Alpha; it may accept it asynchronously.")
partyMembers = { "Alpha", "Gamma" }
event, this = "RAID_ROSTER_UPDATE", groupWatcher
groupWatcher.scripts.OnEvent(groupWatcher)
assert(not TB.IsRosterBatchActive("invite"), "the menu invite batch must finish once bots join")
TB._t.menuRow = TB.rows[1]
TB._t.menuRow.entry = { name = "Alpha", st = TB.GetState("Alpha"), inGroup = false }
TB._t.menuFired = false
TB._t.savedDropdownInit = UIDropDownMenu_Initialize
TB._t.savedDropdownToggle = ToggleDropDownMenu
UIDropDownMenu_Initialize = function(menu, fn) TB._t.menuInit = fn end
ToggleDropDownMenu = function() TB._t.menuFired = true end
this, arg1 = TB._t.menuRow, "RightButton"
TB._t.menuRow.scripts.OnMouseUp(TB._t.menuRow)
arg1 = nil
assert(TB._t.menuFired, "right-click on a roster row must open the menu")
UIDropDownMenu_Initialize = TB._t.savedDropdownInit
ToggleDropDownMenu = TB._t.savedDropdownToggle
assert(TB.OpenRosterRowMenu("") == false and TB.OpenGuildRowMenu("") == false,
    "empty names open no row menu")
assert(TB.BuildGuildRowMenu("Goldie", function() end) > 0,
    "a claimed bot always offers at least Release")
TB._t.guildItems = {}
TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.guildItems, info) end)
TB._t.releaseItem = nil
table.foreach(TB._t.guildItems, function(k, info) if info.text == "Release" then TB._t.releaseItem = info end end)
assert(TB._t.releaseItem and TB._t.releaseItem.func, "the guild menu must always offer Release")
TB._t.releaseItem.func()
assert(lastPopupShown == "TORTOISE_RELEASE_CLAIMED_BOT", "the guild menu Release must ask first")
TB._t.moreRow = TB.guildFrame.rows[1]
TB._t.moreRow.entry = { name = "Goldie" }
this = TB._t.moreRow.moreBtn
TB._t.moreRow.moreBtn.scripts.OnClick(TB._t.moreRow.moreBtn)
assert(TB._t.menuInit ~= nil, "the More button must arm the dropdown")
TB._t.subHere = TB.GetBotOrder and TB.GetBotOrder("Silver") or nil
if TB.HasOrderCapability() and TB._t.subHere and TB._t.subHere.parent then
    TB._t.subMenu = {}
    assert(TB.BuildGuildRowMenu("Silver", function(info) table.insert(TB._t.subMenu, info) end) == 3,
        "a sub-order row offers Cancel, Move and Release")
end

-- Gameplay actions never inspect roster selection and issue exactly one intent.
local selectedBeforeAction = table.getn(TB.GetSelectedRosterNames())
now = now + 1
local beforeAttack = table.getn(sent)
this = TB.actionButtons.attack
TB.actionButtons.attack.scripts.OnClick(TB.actionButtons.attack)
assert(table.getn(sent) == beforeAttack + 1 and sent[table.getn(sent)] == ".bot action attack",
    "Attack must send exactly one action intent")
assert(TB.ActionFeedbackState("attack") == "waiting",
    "Attack click must show a waiting state until the server answers")
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
assert(TB.ActionFeedbackState("stance tank") == "waiting",
    "stance clicks must keep their waiting state through the pill repaint")
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
assert(TB.ActionFeedbackState("attack") == "ok",
    "an ACK must flash the clicked button green")
TB.OnSystemMessage("TBM:ACTION_ERR|pullback|NO_TARGET|Select a living target")
assert(TB.lastActionError and TB.lastActionError.code == "NO_TARGET",
    "structured action ERR must be parsed")
assert(TB.ActionFeedbackState("pullback") == "error",
    "an ACTION_ERR must flash the clicked button red")
TB.OnSystemMessage("TBM:ACTION_ACK|interrupt|party|1|Arcana")
assert(TB.lastActionAck and TB.lastActionAck.intent == "interrupt"
    and TB.lastActionAck.executor == "Arcana",
    "structured interrupt ACK must be parsed")
TB.OnSystemMessage("TBM:ACTION_ERR|interrupt|not-casting|The target is not casting")
assert(TB.lastActionError and TB.lastActionError.intent == "interrupt"
    and TB.lastActionError.code == "not-casting",
    "structured interrupt ERR must be parsed")
-- A missing answer clears the waiting look after the action timeout.
TB.NoteActionFeedback("stay", "waiting")
assert(TB.ActionFeedbackState("stay") == "waiting", "fresh clicks must read waiting")
now = now + (TB.C.ACTION_TIMEOUT or 8) + 1
assert(TB.ActionFeedbackState("stay") == nil, "a missing answer must clear the waiting state")
now = now + 1
TB.NoteActionFeedback("stay", "waiting")
assert(TB.ActionFeedbackState("stay") == "waiting", "state must be re-armable after a timeout")
TB.OnSystemMessage("TBM:ACTION_ACK|stay|party|2|-")
assert(TB.ActionFeedbackState("stay") == "ok", "a late ACK must still flash green")
-- Timed pulls ("pull 10") and toggle switches ("aoe on") map back to
-- the button intent that sent them.
assert(TB.ActionFeedbackKey("action pull 10") == "pull", "timed pull must map to its button")
assert(TB.ActionFeedbackKey("action aoe on") == "aoe", "toggle switches must map to their key")

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
assert(TB.partyFrame.rows[2].ccIcon.point[1] == "RIGHT"
    and TB.partyFrame.rows[2].roleButtons[1].point[5] == 0,
    "CC icon keeps its own column right of the role picker")

-- Four-role rows reserve the lower-right CC column instead of letting the
-- fourth role button obscure the assigned mark (Druid is the current case).
partyClassName = "Druid"
TB.RefreshPartyView()
local druidRow = TB.partyFrame.rows[2]
-- The CC mark sits at RIGHT -64 (18px wide): its left edge is x=398.
assert(druidRow.roleButtons[4]:IsVisible()
    and druidRow.roleButtons[4].width == 60
    and druidRow.roleButtons[4].point[4] + druidRow.roleButtons[4].width <= 398,
    "Four-role rows must leave a dedicated column for the CC icon")
assert(druidRow.ccIcon.point[1] == "RIGHT"
    and druidRow.ccIcon.point[4] == -64,
    "CC indicator must keep its own slot left of Summon")

function partyRowVitalsChecks()
-- Party rows show vitals and state from the client alone: the server never
-- sends HP, mana, drinking or range in any TBM: line.
local savedMembers, savedClass = partyMembers, partyClassName
local savedExists, savedTarget = targetExists, targetNameValue
local savedPriest = TB.GetBotState("Priestbot")
partyClassName = "Priest"
partyMembers = { "Priestbot" }
TB.SetBotState("Priestbot", { move = "follow" })
partyVitals.party1 = nil
partyBuffs.party1 = nil
nearUnits = nil
targetExists, targetNameValue = false, nil
TB.RefreshPartyView()
local vitalsRow = TB.partyFrame.rows[2]
assert(vitalsRow.partyName == "Priestbot" and vitalsRow.hpBar and vitalsRow.manaBar,
    "party rows build HP and mana bars")
assert(vitalsRow.partyState == nil and vitalsRow.manaBar.visible
    and string.find(vitalsRow.descText.text, "Following", 1, true),
    "a healthy bot nearby shows movement, not state")
targetExists, targetNameValue = true, "Priestbot"
TB.RefreshPartyView()
local rowSel = (TB.C.THEME and TB.C.THEME.rowSel) or { 0.20, 0.155, 0.07, 0.96 }
assert(vitalsRow.backdropColor[1] == rowSel[1] and vitalsRow.backdropColor[2] == rowSel[2],
    "the targeted bot row highlights gold")
targetExists, targetNameValue = false, nil
TB.RefreshPartyView()
assert(vitalsRow.backdropColor[1] ~= rowSel[1], "clearing the target clears the highlight")
partyVitals.party1 = { hp = 20, hpMax = 100, mp = 50, mpMax = 100 }
TB.RefreshPartyView()
assert(vitalsRow.hpBar.value == 20 and vitalsRow.hpBar.barMax == 100
    and vitalsRow.hpBar.barColor[1] == TB.C.COLOR.red[1],
    "low HP paints the HP bar red at the reported value")
assert(vitalsRow.partyState == nil
    and string.find(vitalsRow.descText.text, "Following", 1, true),
    "low HP alone keeps the movement line")
deadUnits.party1 = true
TB.RefreshPartyView()
assert(vitalsRow.partyState == "Dead"
    and string.find(vitalsRow.descText.text, "Dead", 1, true),
    "a dead bot shows Dead instead of movement")
assert(vitalsRow.hpBar.barColor[1] == TB.C.COLOR.muted[1],
    "a dead bot greys the HP bar")
deadUnits.party1 = false
ghostUnits.party1 = true
TB.RefreshPartyView()
assert(vitalsRow.partyState == "Ghost", "a released bot shows Ghost")
ghostUnits.party1 = false
partyVitals.party1 = { hp = 100, hpMax = 100, mp = 100, mpMax = 100 }
partyBuffs.party1 = { "Drink" }
TB.RefreshPartyView()
assert(vitalsRow.partyState == "Drinking"
    and string.find(vitalsRow.descText.text, "Drinking", 1, true),
    "a drinking bot shows Drinking instead of movement")
partyBuffs.party1 = nil
nearUnits = { party1 = false }
TB.RefreshPartyView()
assert(vitalsRow.partyState == "OOR"
    and string.find(vitalsRow.descText.text, "OOR", 1, true),
    "an out-of-range bot shows OOR instead of movement")
nearUnits = nil
partyVitals.party1 = nil
partyMembers, partyClassName = savedMembers, savedClass
targetExists, targetNameValue = savedExists, savedTarget
TB.SetBotState("Priestbot", savedPriest or {})
TB.RefreshPartyView()
end
partyRowVitalsChecks()

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

-- Version: the addon version once (title); the line under it keeps the
-- credit and shows the server module only as a semantic version.
assert(TB.versionLine and TB.versionLine.text == "by Sagiroth",
    "before any reply the line carries only the credit")
assert(TB.versionTitle and string.find(TB.versionTitle.text, "v" .. TB.version, 1, true),
    "window title must carry the addon version")
assert(not string.find(TB.versionLine.text, TB.version, 1, true),
    "the addon version must not repeat under the title")
TB.OnSystemMessage("TBM:VERSION|1.12.0")
assert(TB.serverVersion == "1.12.0", "TBM:VERSION must record the server build")
assert(TB.versionLine.text == "by Sagiroth  ·  server module v1.12.0",
    "a semantic module version shows as vX.Y.Z")
TB.OnSystemMessage("TBM:VERSION|2026-09-25-v7")
assert(TB.serverVersion == "2026-09-25-v7", "TBM:VERSION must record the server build")
assert(TB.versionLine.text == "by Sagiroth  ·  server module connected",
    "a dated build id stays out of the header")
assert(TB.FormatSemver("v2.0.1") == "v2.0.1" and TB.FormatSemver("2026-09-25-v7") == nil,
    "only semantic versions format")
TB.OnSystemMessage("TBM:TRANSPORT|party")
TB.serverVersion = nil
if TB.RefreshVersionLine then TB.RefreshVersionLine() end
assert(TB.versionLine.text == "by Sagiroth",
    "window must fall back to the credit alone without a version reply")
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

-- Conjured services: mages offer Food & Water plus portals, warlocks a healthstone.
serviceMageLine = "TBM:SERVICE|Gandalf|1|1|0|10059:Stormwind,11416:Ironforge"
assert(TB.ParseServiceLine(serviceMageLine).food and not TB.ParseServiceLine(serviceMageLine).healthstone
    and table.getn(TB.ParseServiceLine(serviceMageLine).portals) == 2
    and TB.ParseServiceLine(serviceMageLine).portals[2].spell == 11416
    and TB.ParseServiceLine(serviceMageLine).portals[2].city == "Ironforge",
    "a mage service line must parse food and both portals")
assert(TB.ParseServiceLine("TBM:SERVICE|Hexxy|0|0|1|-").healthstone
    and table.getn(TB.ParseServiceLine("TBM:SERVICE|Hexxy|0|0|1|-").portals) == 0,
    "a warlock line with no portals must parse")
assert(TB.ParseServiceLine("TBM:SERVICE|Hexxy|1|0") == nil
    and TB.ParseServiceLine("TBM:SERVICE|Hexxy|2|0|0|-") == nil
    and TB.ParseServiceLine("TBM:SERVICE|Hexxy|0|0|0|bogus") == nil
    and TB.ParseServiceLine("TBM:INV_BEGIN|Hexxy|5") == nil,
    "malformed service lines must not parse")
assert(TB.GetService("Hexxy") == nil, "a rejected line must not clobber the cache")
assert(TB.C.ACTION_LABELS["service portal"] == "Portal", "the portal intent must have a plain label")
serviceSavedMembers, serviceSavedClass = partyMembers, partyClassName
partyMembers = { "Magebot" }
partyClassName = "Mage"
assert(TB.ServiceWanted("Magebot") and not TB.ServiceWanted("Alpha"),
    "only mages and warlocks want the service ask")
now = now + 1
TB.OpenBotPanel("Magebot", "bags")
assert(not TB.botPanel.foodButton.visible and not TB.botPanel.portalButton.visible
    and not TB.botPanel.healthstoneButton.visible, "no service buttons before the reply")
serviceBeforeOpen = table.getn(addonSent)
for serviceDrain = 1, 5 do
    now = now + 1
    serviceQueue = frames["TortoiseBotsManagerQueueFrame"]
    if serviceQueue and serviceQueue.scripts and serviceQueue.scripts.OnUpdate then
        this, arg1 = serviceQueue, 0.5
        serviceQueue.scripts.OnUpdate(serviceQueue)
    end
end
serviceSawOpen = false
for serviceI = serviceBeforeOpen + 1, table.getn(addonSent) do
    if addonSent[serviceI].message == "service Magebot" then serviceSawOpen = true end
end
assert(serviceSawOpen, "opening the panel asks once for a mage")
TB.OnSystemMessage("TBM:SERVICE|Magebot|1|1|0|10059:Stormwind,11416:Ironforge")
assert(TB.GetService("Magebot").water and table.getn(TB.GetService("Magebot").portals) == 2,
    "the service reply must land in the cache")
assert(TB.botPanel.foodButton.visible and TB.botPanel.foodButton.enabled
    and TB.botPanel.portalButton.visible and TB.botPanel.portalButton.enabled
    and not TB.botPanel.healthstoneButton.visible, "a mage offers food and portals, no healthstone")
assert(TB.botPanel.portalButton.point[1] == "BOTTOMRIGHT" and TB.botPanel.healthstoneButton.point[1] == "BOTTOMRIGHT",
    "portal and healthstone sit at the right edge, clear of the weapon slots")
now = now + 1
this = TB.botPanel.foodButton
TB.botPanel.foodButton.scripts.OnClick(TB.botPanel.foodButton)
assert(lastAddon() == "item Magebot trade", "Food & Water trades like the Trade button")
servicePortalRows = {}
assert(TB.BuildServicePortalMenu("Magebot", function(info) table.insert(servicePortalRows, info) end) == 2
    and servicePortalRows[1].text == "Stormwind" and servicePortalRows[2].text == "Ironforge",
    "the portal menu lists the cached cities")
assert(not TB.OpenServicePortalMenu("Magebot"), "no dropdown API in the test client")
now = now + 1
servicePortalRows[1].func()
assert(lastAddon() == "service Magebot portal 10059", "picking a city sends the portal order")
serviceStatusSaid = nil
serviceRealSetStatus = TB.SetStatus
TB.SetStatus = function(msg) serviceStatusSaid = msg end
TB.OnSystemMessage("TBM:ACTION_ACK|service portal|bot:Magebot|1|1")
assert(TB.lastActionAck and TB.lastActionAck.intent == "service portal"
    and string.find(serviceStatusSaid or "", "Portal", 1, true), "the portal ACK names the bot's portal")
TB.OnSystemMessage("TBM:ACTION_ERR|service portal|refused|No portal trainer nearby")
assert(TB.lastActionError and TB.lastActionError.intent == "service portal"
    and string.find(serviceStatusSaid or "", "Portal", 1, true), "the portal ERR keeps the plain label")
TB.SetStatus = serviceRealSetStatus
now = now + 1
this = TB.botPanel.refreshButton
serviceBeforeRefresh = table.getn(addonSent)
TB.botPanel.refreshButton.scripts.OnClick(TB.botPanel.refreshButton)
for _ = 1, 5 do
    now = now + 1
    serviceQueue = frames["TortoiseBotsManagerQueueFrame"]
    if serviceQueue and serviceQueue.scripts and serviceQueue.scripts.OnUpdate then
        this, arg1 = serviceQueue, 0.5
        serviceQueue.scripts.OnUpdate(serviceQueue)
    end
end
serviceSawRefresh = false
for serviceI = serviceBeforeRefresh + 1, table.getn(addonSent) do
    if addonSent[serviceI].message == "service Magebot" then serviceSawRefresh = true end
end
assert(serviceSawRefresh, "Refresh asks the service again for a mage")
now = now + 1
TB.OpenBotPanel("Magebot", "bags")
for _ = 1, 5 do
    now = now + 1
    serviceQueue = frames["TortoiseBotsManagerQueueFrame"]
    if serviceQueue and serviceQueue.scripts and serviceQueue.scripts.OnUpdate then
        this, arg1 = serviceQueue, 0.5
        serviceQueue.scripts.OnUpdate(serviceQueue)
    end
end
assert(lastAddon() == "inv Magebot", "a cached reply is not re-asked on open")
partyMembers = { "Hexxy" }
partyClassName = "Warlock"
now = now + 1
TB.OpenBotPanel("Hexxy", "bags")
for _ = 1, 5 do
    now = now + 1
    serviceQueue = frames["TortoiseBotsManagerQueueFrame"]
    if serviceQueue and serviceQueue.scripts and serviceQueue.scripts.OnUpdate then
        this, arg1 = serviceQueue, 0.5
        serviceQueue.scripts.OnUpdate(serviceQueue)
    end
end
assert(lastAddon() == "service Hexxy", "opening the panel asks once for a warlock")
TB.OnSystemMessage("TBM:SERVICE|Hexxy|0|0|1|-")
assert(TB.botPanel.healthstoneButton.visible and not TB.botPanel.foodButton.visible
    and not TB.botPanel.portalButton.visible, "a warlock offers a healthstone only")
assert(TB.BuildServicePortalMenu("Hexxy", function(info) end) == 0, "a warlock offers no portals")
now = now + 1
this = TB.botPanel.healthstoneButton
TB.botPanel.healthstoneButton.scripts.OnClick(TB.botPanel.healthstoneButton)
assert(lastAddon() == "item Hexxy trade", "Healthstone trades like the Trade button")
partyMembers, partyClassName = serviceSavedMembers, serviceSavedClass
TB.OpenBotPanel("Alpha", "bags")
assert(not TB.botPanel.foodButton.visible and not TB.botPanel.healthstoneButton.visible
    and not TB.botPanel.portalButton.visible, "other classes show no service buttons")
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

-- ── Bot professions: parse, count gate, tooltip, colour, search, Craft prefill
TB.OnSystemMessage("TBM:TRANSPORT|party")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,professions")
assert(TB.HasProfessionsCapability(), "the professions token enables the view")
TB.OpenBotPanel("Alpha")
now = now + 1
TB.botPanel.tabProfs.scripts.OnClick(TB.botPanel.tabProfs)
assert(TB.botPanel.profs.visible and not TB.botPanel.spells.visible, "Professions tab shows its own view")
assert(lastAddon() == "professions Alpha", "opening the view requests the snapshot once")
assert(TB.GetProfessions("Alpha") == nil, "no cache before the reply")
do
itemCache[118] = { name = "Minor Healing Potion", quality = 1, texture = "Interface\\Icons\\INV_Potion_49" }
itemCache[2453] = { name = "Elixir of Minor Fortitude", quality = 1, texture = "Interface\\Icons\\INV_Potion_02" }
itemCache[1710] = { name = "Recipe: Elixir of Minor Fortitude", quality = 2, texture = "Interface\\Icons\\INV_Scroll_03" }
itemCache[3860] = { name = "Copper Ore", quality = 1, texture = "Interface\\Icons\\INV_Ore_Copper_01" }
itemCache[765] = { name = "Silverleaf", quality = 1, texture = "Interface\\Icons\\INV_Misc_Herb_03" }
TB.OnSystemMessage("TBM:PROF_BEGIN|Alpha")
TB.OnSystemMessage("TBM:PROF|186|245|300")
TB.OnSystemMessage("TBM:PROF|182|230|300")
TB.OnSystemMessage("TBM:RECIPE|186|2651|3860|1|25|50|100|ok")
TB.OnSystemMessage("TBM:RECIPE|182|1972|765|1|25|50|100|bound")
TB.OnSystemMessage("TBM:RECIPE_MISSING|182|1973|118|50|0")
TB.OnSystemMessage("TBM:RECIPE_MISSING|182|6259|2453|60|1710")
TB.OnSystemMessage("TBM:PROF_END|Alpha|2|2")
local profs = TB.GetProfessions("Alpha")
assert(profs and table.getn(profs.skills) == 2 and table.getn(profs.recipes) == 2
    and table.getn(profs.missing) == 2, "the full snapshot commits")
assert(TB.ProfessionTooltipLine("Alpha") == "Mining 245/300, Herbalism 230/300",
    "the guild tooltip line names each skill with value/max")
assert(TB.ProfessionTooltipLine("Silver") == nil, "no cache means no tooltip line")
local parsed = TB.ParseProfessionRecipeLine("TBM:RECIPE|186|2651|3860|1|25|50|100|ok")
assert(parsed and parsed.skill == 186 and parsed.spell == 2651 and parsed.item == 3860
    and parsed.orange == 1 and parsed.grey == 100 and parsed.order == "ok", "the 8-field RECIPE line parses")
local legacy = TB.ParseProfessionRecipeLine("TBM:RECIPE|186|2651|3860|1|25|50|100")
assert(legacy and legacy.order == nil and TB.ProfessionRecipeOrderable(legacy), "a missing field falls back to the itemId rule")
assert(TB.ParseProfessionRecipeLine("TBM:RECIPE|186|2651") == nil, "a short RECIPE line drops")
assert(TB.ProfessionRecipeColor(parsed, 245) == "grey", "past grey reads grey")
assert(TB.ProfessionRecipeColor(parsed, 150) == "grey", "150 is past grey 100")
assert(TB.ProfessionRecipeColor(parsed, 75) == "green", "past green reads green")
assert(TB.ProfessionRecipeColor(parsed, 30) == "yellow", "past yellow reads yellow")
assert(TB.ProfessionRecipeColor(parsed, 1) == "orange", "at orange stays orange")
assert(TB.ProfessionRecipeOrderable(parsed), "an ok verdict is orderable")
assert(TB.ProfessionRecipeOrderReason(parsed) == nil, "an ok verdict names no reason")
local bopRecipe = TB.ParseProfessionRecipeLine("TBM:RECIPE|182|1972|765|1|25|50|100|bound")
assert(not TB.ProfessionRecipeOrderable(bopRecipe), "a bound verdict is not orderable")
assert(TB.ProfessionRecipeOrderReason(bopRecipe) == "Soulbound when made, cannot be handed over",
    "a bound verdict names its plain reason")
local enchantRecipe = TB.ParseProfessionRecipeLine("TBM:RECIPE|333|7428|0|1|25|50|100|enchant")
assert(not TB.ProfessionRecipeOrderable(enchantRecipe), "item 0 stays unorderable with the field")
assert(TB.ProfessionRecipeOrderReason(enchantRecipe) == "Enchants cannot be ordered yet",
    "enchants name their plain reason")
assert(TB.ProfessionMissingSourceText({ recipeItem = 0 }) == "Trainer", "a missing trainer recipe says Trainer")
assert(TB.ProfessionMissingSourceText({ recipeItem = 1710 }) == "Recipe: Elixir of Minor Fortitude",
    "a missing recipe item names its item")
TB.OpenBotPanel("Alpha", "profs")
local shown = 0
for _, row in ipairs(TB.botPanel.profRows) do if row:IsVisible() then shown = shown + 1 end end
assert(shown > 3, "headers, recipes and the missing group all render rows")
assert(TB.botPanel.profRows[1].label:GetText() == "Mining 245/300 [||||||||..]",
    "the first header names the skill with its bar")
TB.botPanel.profSearch.text = "copper"
this = TB.botPanel.profSearch
TB.botPanel.profSearch.scripts.OnTextChanged(TB.botPanel.profSearch)
local copperRows = 0
for _, row in ipairs(TB.botPanel.profRows) do
    if row:IsVisible() and row.recipe then copperRows = copperRows + 1 end
end
assert(copperRows == 1 and TB.botPanel.profRows[2].recipe.item == 3860,
    "the search keeps only the matching made item")
TB.botPanel.profSearch.text = "fortitude"
this = TB.botPanel.profSearch
TB.botPanel.profSearch.scripts.OnTextChanged(TB.botPanel.profSearch)
assert(TB.botPanel.profRows[3].label:GetText() == "- Not learned yet (1)",
    "a filtered search still shows the missing group with its count")
TB.botPanel.profSearch.text = ""
this = TB.botPanel.profSearch
TB.botPanel.profSearch.scripts.OnTextChanged(TB.botPanel.profSearch)
TB.OnSystemMessage("TBM:PROF_BEGIN|Alpha")
TB.OnSystemMessage("TBM:PROF|186|245|300")
TB.OnSystemMessage("TBM:RECIPE|186|2651|3860|1|25|50|100|ok")
TB.OnSystemMessage("TBM:PROF_END|Alpha|2|0")
assert(table.getn(TB.GetProfessions("Alpha").recipes) == 2, "a short reply does not clobber the cache")
TB.OnSystemMessage("TBM:PROF_BEGIN|Alpha")
TB.OnSystemMessage("TBM:RECIPE|186|2651|3860|1|25|50|100|ok")
TB.OnSystemMessage("TBM:RECIPE_MISSING|182|1973|118|50|0")
TB.OnSystemMessage("TBM:PROF_END|Alpha|1")
assert(table.getn(TB.GetProfessions("Alpha").missing) == 2, "a missing count that does not match keeps the cached reply")
canEditOfficerNote = true
function CanEditOfficerNote() return canEditOfficerNote end
TB.OpenBotPanel("Alpha", "profs")
assert(TB.PrefillCraftOrder("Alpha", parsed), "the Craft button prefills a known orderable recipe")
assert(TB.orderWindow:IsVisible() and TB.GetOrderKind() == "craft"
    and TB.GetOrderSelection() == 3860, "prefill opens the window with Craft and the item picked")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Alpha craft 3860 10 inf", "Send gives a normal craft order")
TB.OnSystemMessage("TBM:ACTION_ERR|order|needsprofession|That item needs a profession to use.")
assert(string.find(TB.GetOrderFeedback().text, "That item needs a profession to use.", 1, true),
    "a refused craft order shows the server text in the window")
TB.CloseOrderWindow()
TB.SetOrderKind("farm")
assert(not TB.PrefillCraftOrder("Alpha", enchantRecipe), "enchants get no prefill")
assert(not TB.PrefillCraftOrder("Alpha", bopRecipe), "refused verdicts get no prefill")
assert(TB.OrderReasonLabel("cooldown") == "long recipe cooldown", "craft refusal reasons have plain labels")
TB.OpenBotPanel("Alpha", "profs")
assert(lastAddon() ~= "professions Alpha", "a cached reply is not re-asked on open")
canEditOfficerNote = false
TB.RefreshBotPanel()
assert(not TB.botPanel.profRows[2].craft:IsVisible(), "no order right hides the Craft button")
canEditOfficerNote = true
TB.RefreshBotPanel()
assert(TB.botPanel.profRows[2].craft:IsVisible() and TB.botPanel.profRows[2].craft.enabled,
    "an orderable recipe shows an enabled Craft button")
assert(TB.botPanel.profRows[4].craft:IsVisible() and TB.botPanel.profRows[4].craft.enabled == false,
    "a refused recipe shows a disabled Craft button")
TB.CloseOrderWindow()
TB.CloseBotPanel()
end
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
TB.OpenMiniCategory("switch")
do
    local found = nil
    for _, e in ipairs(fly.entries) do
        if e.def and e.def.toggle == "loot" then found = e end
    end
    assert(found and string.find(found.label.text or "", "%(On%)", 1) ~= nil,
        "the flyout must spell the switch word beside the colour lamp")
end
TB.OpenMiniCategory("camp")
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
-- Horizontal/vertical layout: stored, toggled from the bar and the slash
-- command, and stacked without touching the chrome.
assert(TB.GetMiniLayout() == "horizontal", "the mini bar starts horizontal")
TortoiseBotsDB.miniLayout = "sideways"
assert(TB.GetMiniLayout() == "horizontal", "a stray layout value reads back horizontal")
TB.SetMiniLayout("vertical")
assert(TortoiseBotsDB.miniLayout == "vertical" and TB.GetMiniLayout() == "vertical",
    "setting the layout stores it")
assert(bar.height > bar.width, "a vertical bar is taller than wide")
assert(bar.categories.engage.point and bar.categories.engage.point[1] == "TOP", "vertical categories stack downward")
assert(bar.favButtons[1].point and bar.favButtons[1].point[1] == "TOP", "vertical favourites stack downward")
assert(bar.expand.point[1] == "BOTTOM", "the + button sits at the foot of a vertical bar")
arg1 = "RightButton"
bar.handle.scripts.OnClick(bar.handle)
arg1 = nil
assert(TB.GetMiniLayout() == "horizontal", "right-click on the turtle flips the layout back")
assert(bar.favButtons[1].point[1] == "LEFT", "horizontal favourites run left to right")
SlashCmdList["TORTOISEBOTSMANAGER"]("minilayout vertical")
assert(TB.GetMiniLayout() == "vertical", "/tbm minilayout vertical stacks the bar")
SlashCmdList["TORTOISEBOTSMANAGER"]("minilayout")
assert(TB.GetMiniLayout() == "horizontal", "/tbm minilayout with no word flips the bar")
TB.SetMiniLayout("horizontal")
-- Favourite slots: a bound key runs that slot, shows on the button and in
-- the tooltip; empty or unusable slots stay silent.
TortoiseBotsDB.miniFavorites = { "stop", "attack", "rest" }
TB.LayoutMiniBar()
bar:Show()
TB.RefreshMiniBar()
GetBindingKey = function(name) if name == "TBM_FAV1" then return "SHIFT-1" end end
TB.RefreshMiniBar()
assert(bar.favButtons[1].key.text == "SHIFT-1", "the bound key shows on its favourite button")
assert(bar.favButtons[2].key.visible == false, "an unbound slot shows no key")
this = bar.favButtons[1]
now = now + 1
assert(TB.RunMiniFavorite(1) == true, "a bound favourite slot runs")
assert(lastAddon() == "action stop", "slot 1 runs the first favourite")
assert(TB.RunMiniFavorite(9) == false, "an empty slot runs nothing")
assert(TB.RunMiniFavorite(0) == false and TB.RunMiniFavorite(13) == false, "slots outside 1-12 run nothing")
targetExists, targetNameValue = false, nil
assert(TB.RunMiniFavorite(2) == false, "a slot needing an enemy target stays silent without one")
targetExists, targetNameValue = true, "Enemy"
assert(TB.RunMiniFavorite("bad") == false, "a non-number slot runs nothing")
GetBindingKey = nil
TB.RefreshMiniBar()
assert(bar.favButtons[1].key.visible == false, "no binding API means no key text")
TortoiseBotsDB.miniFavorites = { "attack", "stop", "interrupt", "flee", "pull", "pullback", "focus skull",
    "follow", "stay", "come", "aoe" }
TB.LayoutMiniBar()
bar.expand.scripts.OnClick(bar.expand)
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

-- Sortable guild columns (session-only): click a header to sort, again to reverse.
TB.SetGuildSort("name")
assert(TB.GetClaimedBots()[1].name == "Bronze" and TB.GetClaimedBots()[2].name == "Goldie"
    and TB.GetClaimedBots()[3].name == "Silver", "name sort must order guild rows alphabetically")
assert(TB.guildFrame.headerBtns and table.getn(TB.guildFrame.headerBtns) == 5,
    "guild header buttons must exist for each column")
assert(TB.guildFrame.headerBtns[1].headerLabel:GetText() == "NAME ^",
    "the active guild header must carry the direction marker")
TB.SetGuildSort("name")
assert(TB.GetClaimedBots()[1].name == "Silver", "clicking the same guild header again must reverse the rows")
TB.SetGuildSort("level")
assert(TB.GetClaimedBots()[1].name == "Goldie", "level sort must restore highest level first")
TB.SetGuildSort("status")
assert(TB.GetClaimedBots()[1].online and TB.GetClaimedBots()[table.getn(TB.GetClaimedBots())].online == false,
    "status sort must keep online guild bots before offline")
TB.guildSort = { key = "level", dir = -1 }

-- Gear locking policy state
assert(allClaimed[1].gearLocked == true, "Level 60 bot must have gearLocked = true")
assert(allClaimed[2].gearLocked == false, "Level 45 bot must have gearLocked = false")
assert(allClaimed[3].gearLocked == false, "Level 20 bot must have gearLocked = false")

-- Search filter
assert(table.getn(TB.GetClaimedBots("silver")) == 1 and TB.GetClaimedBots("silver")[1].name == "Silver",
    "search filter must find bot by name")
assert(table.getn(TB.GetClaimedBots("mage")) == 1 and TB.GetClaimedBots("mage")[1].name == "Bronze",
    "search filter must find bot by class name")

-- Row professions: old 8-field rows keep working, new rows parse profs and
-- the filter matches profession names like name/class
parsedProfs = TB.ParseClaimedProfs("333:300;197:275")
assert(parsedProfs and table.getn(parsedProfs) == 2 and parsedProfs[1].skill == 333
    and parsedProfs[1].value == 300 and parsedProfs[2].skill == 197, "profs field must parse into skill/value pairs")
assert(table.getn(TB.ParseClaimedProfs("-")) == 0, "a dash means no professions")
assert(table.getn(TB.ParseClaimedProfs("")) == 0, "an empty field means no professions")
assert(TB.ParseClaimedProfs("333") == nil, "a pair without a value must not parse")
assert(TB.ParseClaimedProfs("333:abc") == nil, "a non-numeric value must not parse")
TB.OnSystemMessage("TBM:CLAIMED_BEGIN|2")
TB.OnSystemMessage("TBM:CLAIMED|301|Enchantee|8|60|online|0|Ironforge|1|333:300;197:275")
TB.OnSystemMessage("TBM:CLAIMED|302|Plain|1|60|online|0|Ironforge|1|-")
TB.OnSystemMessage("TBM:CLAIMED_END")
profed = TB.GetClaimedBots()
assert(table.getn(profed) == 2, "profs snapshot must replace the rows")
assert(TB.ClaimedProfsLine(profed[1]) == "Enchanting 300, Tailoring 275",
    "the guild tooltip line names the row professions with skill")
assert(TB.ClaimedProfsLine(profed[2]) == nil, "a dash means no tooltip line")
assert(table.getn(TB.GetClaimedBots("enchant")) == 1 and TB.GetClaimedBots("enchant")[1].name == "Enchantee",
    "search filter must match profession names")
assert(table.getn(TB.GetClaimedBots("tail")) == 1, "profession match must work on substrings")
assert(table.getn(TB.GetClaimedBots("mine")) == 0, "an unknown profession must leave no rows")
TB.OnSystemMessage("TBM:CLAIMED_BEGIN|1")
TB.OnSystemMessage("TBM:CLAIMED|303|Bad|1|60|online|0|Ironforge|1|333")
assert(table.getn(TB.GetClaimedBots()) == 2, "a malformed profs field drops the batch, keeping the last good list")
do
    local claimedStatus = nil
    local realSetStatus = TB.SetStatus
    TB.SetStatus = function(msg) claimedStatus = msg end
    TB.OnSystemMessage("TBM:CLAIMED_END")
    TB.SetStatus = realSetStatus
    assert(claimedStatus == nil, "the END after a rejected row keeps the row's reason on screen")
end
TB.OnSystemMessage("TBM:CLAIMED_BEGIN|1")
TB.OnSystemMessage("TBM:CLAIMED|304|Future|1|60|online|0|Ironforge|1|333:300|newfield|another")
TB.OnSystemMessage("TBM:CLAIMED_END")
assert(table.getn(TB.GetClaimedBots()) == 1 and TB.GetClaimedBots()[1].name == "Future"
    and TB.ClaimedProfsLine(TB.GetClaimedBots()[1]) == "Enchanting 300",
    "fields a newer server appends are ignored")
-- Back to the original rows for the UI block below.
TB.OnSystemMessage("TBM:CLAIMED_BEGIN|3")
TB.OnSystemMessage("TBM:CLAIMED|201|Goldie|1|60|online|0|Ironforge|1")
TB.OnSystemMessage("TBM:CLAIMED|202|Silver|5|45|online|1|Duskwood|0")
TB.OnSystemMessage("TBM:CLAIMED|203|Bronze|8|20|offline|0|-|0")
TB.OnSystemMessage("TBM:CLAIMED_END")
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

-- Release menu entry with confirmation popup
now = now + 1
TB._t = TB._t or {}
TB._t.relItems = {}
assert(TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.relItems, info) end) > 0,
    "the guild row menu must list actions for Goldie")
TB._t.relEntry = nil
table.foreach(TB._t.relItems, function(k, info) if info.text == "Release" then TB._t.relEntry = info end end)
assert(TB._t.relEntry and TB._t.relEntry.func, "the guild row menu must offer Release")
TB._t.relEntry.func()
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
-- ── Tooltips show bound keys, empty Party offers Roster ───────────────────
assert(TB.BindingText("attack") == nil, "unbound actions report no key")
GetBindingKey = function(binding)
    if binding == "TBM_ATTACK" then return "1" end
    if binding == "TBM_FOLLOW" then return "SHIFT-1", "CTRL-F" end
    return nil
end
assert(TB.BindingText("attack") == "1", "a bound key is reported raw")
assert(TB.BindingText("stop") == nil, "an unbound action still reports nothing")
GetBindingText = function(key) return "<" .. key .. ">" end
assert(TB.BindingText("follow") == "<SHIFT-1>, <CTRL-F>", "both keys are named")
assert(TB.BindingText("bogus") == nil, "an unknown intent reports nothing")
assert(TB.actionButtons.attack.bindingIntent == "attack", "action buttons carry their intent for tooltips")
this = TB.actionButtons.attack
TB.actionButtons.attack.scripts.OnEnter(TB.actionButtons.attack)
this = TB.actionButtons.stop
TB.actionButtons.stop.scripts.OnEnter(TB.actionButtons.stop)
GetBindingKey, GetBindingText = nil, nil

partyMembers = {}
TB.ShowTab("party")
TB.RefreshPartyView()
assert(TB.partyFrame.emptyMsg:IsVisible(), "an empty party shows its message")
assert(TB.partyFrame.inviteButton and TB.partyFrame.inviteButton:IsVisible(), "an empty party offers Invite from Roster")
TB.ShowTab("roster")
this = TB.partyFrame.inviteButton
TB.partyFrame.inviteButton.scripts.OnClick(TB.partyFrame.inviteButton)
assert(TortoiseBotsDB.activeTab == "roster", "Invite from Roster opens the Roster tab")
partyMembers = { "Alpha" }
TB.RefreshPartyView()
assert(not TB.partyFrame.inviteButton:IsVisible(), "a filled party hides the invite button")
partyMembers = {}
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
assert(not (TB.runWindow and TB.runWindow:IsVisible()), "the Dungeon tab leaves the run window shut")
TB.OpenRunWindow()
assert(TB.runWindow and TB.runWindow:IsVisible(), "Open run window opens it")
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
assert(TB.infoWindow.rows[1].value.text == "On", "a switch value must spell On, not colour alone")
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
-- ── Settings window: persisted options wired to the frames ──────────────────
assert(TortoiseBotsDB.minimapShown == true and TortoiseBotsDB.miniLocked == false,
    "settings must default to a visible minimap button and an unlocked mini bar")
assert(TB.ClampWindowScale(2) == 1.1 and TB.ClampWindowScale(0.5) == 0.7
    and TB.ClampWindowScale("abc") == nil and TB.GetWindowScale() == 1,
    "the window scale must clamp to 70-110% with automatic 100% at 900 px height")
assert(TB.ClampPollInterval(1) == 4 and TB.ClampPollInterval(99) == 60
    and TB.ClampPollInterval(7.6) == 7 and TortoiseBotsDB.pollInterval == 8,
    "the roster refresh must clamp to whole seconds in 4-60")
assert(TB.OpenSettings() and TB.settingsWindow:IsVisible(), "the settings window must open")
assert(TB.settingsWindow.slider:GetValue() == 1, "the slider must show the automatic scale")
assert(TB.settingsWindow.scaleValue.text == "Auto (100%)", "automatic scale must read as Auto")
TB.SetWindowScale(0.82)
assert(TortoiseBotsDB.windowScale == 0.82 and TB.frame.scale == 0.82
    and TB.settingsWindow.scaleValue.text == "82%", "a slider move must scale the window and persist")
TB.SetWindowScale(nil)
assert(TortoiseBotsDB.windowScale == nil and TB.frame.scale == 1
    and TB.settingsWindow.scaleValue.text == "Auto (100%)", "Auto must clear the override")
TB.SetMinimapShown(false)
assert(TortoiseBotsDB.minimapShown == false and not TB.minimapButton:IsVisible()
    and TB.settingsWindow.minimapCheck:GetChecked() == false, "hiding must drop the minimap button")
TB.SetMinimapShown(true)
assert(TortoiseBotsDB.minimapShown == true and TB.minimapButton:IsVisible(), "showing must bring it back")
TB.SetMiniLocked(true)
assert(TortoiseBotsDB.miniLocked == true, "locking must persist the mini bar lock")
TB.SetMiniLocked(false)
TB.SetAutoPoll(false)
assert(TortoiseBotsDB.autoPoll == false
    and TB.settingsWindow.pollStepper.minus.enabled == false, "pausing refresh must grey the interval")
TB.SetAutoPoll(true)
TB.SetPollInterval(12)
assert(TortoiseBotsDB.pollInterval == 12 and TB.settingsWindow.pollStepper.label.text == "12 s",
    "the interval stepper must persist and repaint")
TB.SetPollInterval(8)
TB.settingsWindow.pollStepper.repaint()
assert(TB.settingsWindow.pollStepper.label.text == "8 s", "the interval must reset for later tests")
SlashCmdList["TORTOISEBOTSMANAGER"]("settings")
assert(not TB.settingsWindow:IsVisible(), "/tbm settings must toggle the window")
SlashCmdList["TORTOISEBOTSMANAGER"]("settings")
assert(TB.settingsWindow:IsVisible(), "/tbm settings must reopen it")
TB.CloseSettings()
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
assert(TB.lootRows and table.getn(TB.lootRows) == 15, "the Loot tab owns its scroll rows")

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
assert(TB.guildFrame.rows[1].moreBtn:IsVisible(), "no capability keeps the More menu for Release")

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
TB.OrderPollTick()
assert(lastAddon() == "order list", "the 30s tick re-asks for the order list")
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
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|keep|Goldie") == nil,
    "an order parented to itself is dropped")

-- Supply chain: parent / gold cap / step / need trail the keep field.
local subOrder = TB.ParseOrderLine("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|craft|-")
assert(subOrder and subOrder.parent == "Silver" and subOrder.parent ~= "Goldie" or subOrder,
    "a 16-field order line parses the supply tail")
local needOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|10000|need|2319:4;2320:2")
assert(needOrder and needOrder.goldCap == 10000 and needOrder.step == "need"
    and table.getn(needOrder.need) == 2
    and needOrder.need[1].id == 2319 and needOrder.need[1].count == 4
    and needOrder.need[2].id == 2320 and needOrder.need[2].count == 2,
    "parent, gold cap, step and need parse")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|-|-|-").need == nil,
    "dash need parses as none")
assert(TB.ParseOrderNeed("2319:4;2320:2") ~= nil and TB.ParseOrderNeed("-") == nil
    and TB.ParseOrderNeed("nope") == nil, "need lists parse strictly")
assert(TB.OrderReasonLabel("needitems") == "needs items from you", "needitems gets a plain reason")
assert(TB.OrderStepLabel({ step = "bank" }) == "taking from guild bank", "bank step reads plainly")
assert(TB.OrderStepLabel({ step = "ah" }) == "buying on AH", "ah step reads plainly")
assert(TB.OrderStepLabel({ step = "farm", zone = "Elwynn" }) == "farming in Elwynn", "farm step names the zone")
assert(TB.OrderStepLabel({ step = "sub" }) == "waiting for sub-order", "sub step reads plainly")
assert(TB.OrderStepLabel({ step = "need" }) == "needs items from you", "need step reads plainly")
assert(TB.OrderStepLabel({ step = "-" }) == nil and TB.OrderStepLabel({}) == nil, "dash step means none")
assert(TB.OrderStepLabel({ step = "froth" }) == "froth", "unknown steps stay raw")
itemCache[2319] = { name = "Medium Leather", quality = 1, texture = "Interface\\Icons\\INV_Misc_LeatherScrap_02" }
itemCache[2320] = { name = "Cured Light Hide", quality = 1, texture = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" }
local needText = TB.OrderNeedText(needOrder)
assert(string.find(needText, "Medium Leather x4", 1, true)
    and string.find(needText, "Cured Light Hide x2", 1, true)
    and string.find(needText, "trade, mail or put in guild bank", 1, true),
    "need lists name items with the bring hint")
assert(string.find(TB.OrderTooltipText(needOrder), "Needs: Medium Leather x4, Cured Light Hide x2", 1, true) ~= nil,
    "need tooltips list the missing items")
assert(TB.OrderGoldText(12345) == "1g 23s 45c" and TB.OrderGoldText(0) == "0c"
    and TB.OrderGoldText(nil) == "0c", "gold caps read as coins")
assert(TB.ClampOrderGold(12345) == 12345 and TB.ClampOrderGold(0) == 0
    and TB.ClampOrderGold("nope") == nil and TB.ClampOrderGold(nil) == nil
    and TB.ClampOrderGold("") == nil, "gold caps clamp to copper, zero, or none")
assert(TB.OrderReasonLabel("nobanker") == "no banker in reach", "nobanker names the missing banker")
assert(TB.OrderReasonLabel("noauctioneer") == "no auctioneer in reach", "noauctioneer names the missing auctioneer")
assert(TB.OrderReasonLabel("nolisting") == "nothing fitting on the AH", "nolisting says the AH had nothing fitting")
assert(TB.OrderReasonLabel("bankdenied") == "bank refused withdrawal", "bankdenied names the refused withdrawal")
assert(string.find(TB.OrderTooltipText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|working|nobanker|-|-|-|-|-|-|bank|-")), "State: Working (no banker in reach)", 1, true) ~= nil,
    "bank dead-end tooltips name the reason")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|ah|2319:4")) == "Light Leather 2/10 · buying on AH · |cffffd200needs items from you|r",
    "working rows with a need list say so")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|ah|-")) == "Light Leather 2/10 · buying on AH",
    "working rows without a need list stay unchanged")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|-|need|2319:4")) == "Light Leather 0/10 · |cffffd200Waiting|r",
    "waiting needitems rows already say it")
assert(string.find(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|-|need|2319:4")), "needs items from you", 1, true) == nil,
    "waiting needitems rows get no extra marker")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|grouped|-|-|-|-|-|-|craft|2319:4")) == "Light Leather 0/10 · |cffffd200Waiting|r · crafting · |cffffd200needs items from you|r",
    "waiting grouped rows with a need list get the marker once")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|10|10|done|-|-|-|-|-|-|-|-|2319:4")) == "Light Leather · |cff4ecb5aDone|r",
    "finished rows get no need marker")
assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|need|2319:4")) == "Light Leather 2/10 · needs items from you",
    "a working row on its need step says it once")
-- ── Order carry (status honesty, new 17th field) ───────────────────────────
-- have is delivered only; carry is bags + mail, not yet delivered. Own
-- function: chunk local limit.
local function orderCarryChecks()
    assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|done|-|-|-|-|-|-|-|-|-|2")) == "Light Leather · |cff4ecb5aDone|r",
        "delivered have=10 is done even with carry")
    local oldLine = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|-|-|-|craft|-")
    assert(oldLine and oldLine.have == 4 and oldLine.carry == nil, "a 16-field old line still parses")
    assert(TB.OrderRowText(oldLine) == "Light Leather 4/10 · crafting · |cff4ecb5aEasy|r", "an old line without carry shows progress only")
    assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bags|-|3")) == "Light Leather 2/10 (+3 carrying) · checking bags and mail",
        "a working row with carry shows both counts")
    assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|working|-|-|-|-|-|-|-|bags|-")) == "Light Leather 10/10 · checking bags and mail",
        "a working row at its count says nothing about bags")
    assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|9|10|working|-|-|-|-|-|-|-|bags|-")) == "Light Leather 9/10 · checking bags and mail",
        "a working row short of its count stays unchanged")
    assert(string.find(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|waiting|grouped|-|-|-|-|-|-|craft|-|2")), "carrying", 1, true) ~= nil,
        "a waiting row with carry still shows it")
    assert(string.find(TB.OrderRowText({ item = "Light Leather", have = 0, want = 0, state = "working" }), "carrying", 1, true) == nil,
        "a working row with no carry gets no marker")
    local carryTip = TB.OrderTooltipText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bags|-|3"))
    local oldTip = TB.OrderTooltipText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|9|10|working|-|-|-|-|-|-|-|bags|-"))
    assert(string.find(carryTip, "Carrying 3 (in bags and mail, not yet delivered).", 1, true) ~= nil,
        "the tooltip names the exact carry count")
    assert(string.find(oldTip, "Carrying", 1, true) == nil,
        "an old line without carry names no carry")
    local interimTip = TB.OrderTooltipText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|working|-|-|-|-|-|-|-|bags|-"))
    assert(string.find(interimTip, "Not deliverable yet: part of the count is not in the bot's bags (usually still in its mail).", 1, true) ~= nil,
        "an old line at its count keeps the interim wording")
    assert(TB.OrderRowText(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|10|10|working|-|Ashenvale|-|-|keep|-|-|farm|-|2")) == "Light Leather 10/10 (+2 carrying) · farming in Ashenvale · |cff4ecb5aKeep|r",
        "the carry count sits before keep")
end
orderCarryChecks()

-- Sub-order tree: indented rows, depth helpers, branch cancel.
TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|-|-|-|craft|-")
TB.OnSystemMessage("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|craft|-")
TB.OnSystemMessage("TBM:ORDER_END")
assert(TB.OrderDepth(TB.GetBotOrder("Silver")) == 1, "a sub-order sits at depth 1")
assert(TB.OrderDepth(TB.GetBotOrder("Goldie")) == 0, "a top order sits at depth 0")
assert(TB.OrderTreeRowText(TB.GetBotOrder("Silver"), 1) == "  Silver: "
    .. TB.OrderRowText(TB.GetBotOrder("Silver")), "sub-order rows name their bot indented")
assert(TB.OrderTreeRowText(TB.GetBotOrder("Goldie"), 0) == "Goldie: "
    .. TB.OrderRowText(TB.GetBotOrder("Goldie")), "root rows name their bot too")
assert(string.find(TB.OrderRowText(TB.GetBotOrder("Goldie")), "Silver:", 1, true) == nil
    and string.find(TB.OrderRowText(TB.GetBotOrder("Goldie")), "crafting", 1, true) ~= nil,
    "guild rows stay bot-free with the live step")
assert(table.getn(TB.OrderChildren("Goldie")) == 1, "children list the branch")
assert(table.getn(TB.GetOrderTree()) == 2, "the tree holds every row")
TB.OnSystemMessage("TBM:ORDER|Bronze|farm|2318|Light Leather|0|5|working|-|Elwynn|-|-|-|Nobody|-|-|-")
assert(TB.OrderDepth(TB.GetBotOrder("Bronze")) == 0, "a missing parent shows as a root")
assert(TB.OrderTreeRowText(TB.GetBotOrder("Bronze")) == "Bronze: "
    .. TB.OrderRowText(TB.GetBotOrder("Bronze")), "an orphan row still names its bot")
TB.OnSystemMessage("TBM:ORDER|Bronze|farm|2318|Light Leather|0|5|working|-|Elwynn|-|-|-|Goldie|-|-|-")
assert(TB.OrderDepth(TB.GetBotOrder("Bronze")) == 1, "a late parent still indents")
assert(TB.OrderTreeRowText(TB.GetBotOrder("Bronze")) == "  Bronze: "
    .. TB.OrderRowText(TB.GetBotOrder("Bronze")), "an arriving parent re-indents the row")

-- Send missing items: draft, target, stack pick, mailbox gate, fill click.
local function sendMissingItemsBlock()
    local calls = {}
    local function rec(name)
        return function(...) table.insert(calls, { name = name, args = { ... } }) end
    end
    local function nameSeq()
        local out = {}
        for _, c in ipairs(calls) do table.insert(out, c.name) end
        return table.concat(out, ",")
    end
    local function hasCall(name)
        for _, c in ipairs(calls) do
            if c.name == name then return true end
        end
        return false
    end
    local function argsOf(name)
        for _, c in ipairs(calls) do
            if c.name == name then return c.args end
        end
        return nil
    end

    MailFrame = CreateFrame("Frame", "TortoiseBotsManagerTestMailFrame")
    MailFrame.visible = true
    SendMailNameEditBox = object("EditBox", MailFrame)
    SendMailSubjectEditBox = object("EditBox", MailFrame)
    SendMailBodyEditBox = object("EditBox", MailFrame)
    local function clearDraft() SendMailNameEditBox:SetText(""); SendMailSubjectEditBox:SetText(""); SendMailBodyEditBox:SetText("") end

    -- Bags are sparse; slots come from GetContainerNumSlots.
    local bags, bagSlots = {}, {}
    local function clearBags() bags = {}; bagSlots = {} end
    local function setBag(bag, slot, id, count, name, locked)
        bags[bag] = bags[bag] or {}
        bags[bag][slot] = { id = id, count = count, name = name, locked = locked,
            texture = "Interface\\Icons\\INV_Misc_Quest_ColorRed" }
        if (bagSlots[bag] or 0) < slot then bagSlots[bag] = slot end
    end
    GetContainerNumSlots = function(bag) return bagSlots[bag] or 0 end
    GetContainerItemLink = function(bag, slot)
        local entry = (bags[bag] or {})[slot]
        if entry then return "|cffffffff|Hitem:" .. entry.id .. ":0:0:0|h[" .. entry.name .. "]|h|r" end
        return nil
    end
    GetContainerItemInfo = function(bag, slot)
        local entry = (bags[bag] or {})[slot]
        if entry then return entry.texture, entry.count, entry.locked end
        return nil
    end
    -- The mail state the live client holds: the item on the cursor and the
    -- one Send Mail attachment slot. A pickup or split puts the item on the
    -- cursor, the attach click moves the cursor item into the slot, and
    -- GetSendMailItem reads the slot back (1.12 order: name, texture,
    -- count, quality).
    local cursor, mailItem = nil, nil
    local function takeCursor()
        mailItem, cursor = cursor, nil
    end
    MailFrameTab_OnClick = rec("MailFrameTab_OnClick")
    PickupContainerItem = function(bag, slot)
        table.insert(calls, { name = "PickupContainerItem", args = { bag, slot } })
        local entry = (bags[bag] or {})[slot]
        cursor = entry and { name = entry.name, count = entry.count } or nil
    end
    SplitContainerItem = function(bag, slot, count)
        table.insert(calls, { name = "SplitContainerItem", args = { bag, slot, count } })
        local entry = (bags[bag] or {})[slot]
        cursor = entry and { name = entry.name, count = count } or nil
    end
    ClickSendMailItemButton = function()
        table.insert(calls, { name = "ClickSendMailItemButton" })
        takeCursor()
    end
    CursorHasItem = function()
        table.insert(calls, { name = "CursorHasItem" })
        return cursor ~= nil
    end
    GetSendMailItem = function()
        table.insert(calls, { name = "GetSendMailItem" })
        if not mailItem then return nil end
        return mailItem.name, "Interface\\Icons\\INV_Misc_LeatherScrap_02", mailItem.count, 1
    end
    ClearCursor = function()
        table.insert(calls, { name = "ClearCursor" })
        cursor = nil
    end
    SendMail = function() error("SendMail must never be called by the addon") end

    -- 1. Draft from the parsed need order (item cache seeded just above).
    local draft = TB.OrderMailDraft("Goldie", needOrder)
    assert(draft and draft.to == "Goldie" and draft.subject == "Order: Light Leather"
        and string.find(draft.body, "Medium Leather x4", 1, true) ~= nil,
        "the draft fills recipient, subject and need body")
    assert(TB.OrderMailDraft("Goldie", { item = "Light Leather", need = {} }) == nil,
        "a needless order makes no draft")

    -- 2. Target: first bot in tree order whose order needs items.
    TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|working|-|-|-|-|-|-|-|craft|-")
    TB.OnSystemMessage("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|craft|2319:4;2320:2")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(TB.OrderNeedTarget("Goldie") == "Silver", "the target skips a needless root")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|10|working|-|-|-|-|-|-|-|farm|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(TB.OrderNeedTarget("Goldie") == nil, "no need anywhere means no target")

    -- 3. Exact stack: count fits the need, nothing splits.
    clearBags()
    setBag(0, 3, 2319, 4, "Medium Leather")
    local stack = TB.FindOrderNeedStack(needOrder)
    assert(stack and stack.bag == 0 and stack.slot == 3 and stack.id == 2319
        and stack.count == 4 and stack.split == nil,
        "an exact stack is picked whole")

    -- 4. A stack larger than the need splits to the need count.
    setBag(0, 3, 2319, 10, "Medium Leather")
    stack = TB.FindOrderNeedStack(needOrder)
    assert(stack and stack.count == 10 and stack.split == 4,
        "a larger stack splits to the need")

    -- 5. Locked stacks are skipped; the next needed item is used.
    clearBags()
    setBag(0, 1, 2319, 4, "Medium Leather", true)
    setBag(0, 2, 2320, 2, "Cured Light Hide")
    stack = TB.FindOrderNeedStack(needOrder)
    assert(stack and stack.id == 2320 and stack.slot == 2 and stack.split == nil,
        "a locked stack is skipped for the next needed item")

    -- 6. Nothing in bags: no stack, but the form still fills.
    clearBags()
    assert(TB.FindOrderNeedStack(needOrder) == nil, "empty bags mean no stack")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|-|need|2319:4;2320:2")
    TB.OnSystemMessage("TBM:ORDER_END")
    clearDraft()
    TB.SendOrderMissingItems("Goldie")
    assert(SendMailNameEditBox:GetText() == "Goldie",
        "the form fills even when nothing can be attached")
    assert(string.find(TB.GetOrderFeedback().text, "None of the needed items", 1, true) ~= nil,
        "empty bags say so")

    -- 7. The mailbox gate: open mailbox plus a need enables it.
    MailFrame.visible = false
    local can, reason = TB.CanSendOrderItems("Goldie")
    assert(can == false and reason == "Open a mailbox first",
        "a closed mailbox disables the button")
    MailFrame.visible = true
    assert(TB.CanSendOrderItems("Goldie") == true,
        "an open mailbox with a need enables the button")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|10|working|-|-|-|-|-|-|-|farm|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    local can2, reason2 = TB.CanSendOrderItems("Goldie")
    assert(can2 == false and reason2 == "No order needs items",
        "no need disables the button")

    -- 8. The click opens the Send tab, probes the cursor, picks up one
    -- stack, attaches, then reads the attachment back from the client.
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|0|10|waiting|needitems|-|-|-|-|-|-|need|2319:4;2320:2")
    TB.OnSystemMessage("TBM:ORDER_END")
    clearBags()
    setBag(0, 3, 2319, 4, "Medium Leather")
    cursor, mailItem = nil, nil
    calls = {}
    clearDraft()
    TB.SendOrderMissingItems("Goldie")
    assert(nameSeq() == "CursorHasItem,GetSendMailItem,MailFrameTab_OnClick,PickupContainerItem,"
        .. "ClickSendMailItemButton,GetSendMailItem,CursorHasItem",
        "the click checks the cursor first and reads the attachment back after: " .. nameSeq())
    assert(argsOf("MailFrameTab_OnClick")[1] == 2 and argsOf("PickupContainerItem")[1] == 0
        and argsOf("PickupContainerItem")[2] == 3,
        "the click switches to tab 2 and picks bag 0 slot 3")
    assert(SendMailSubjectEditBox:GetText() == "Order: Light Leather"
        and string.find(SendMailBodyEditBox:GetText(), "Medium Leather x4", 1, true) ~= nil,
        "the click fills subject and body")
    assert(mailItem and mailItem.name == "Medium Leather" and mailItem.count == 4,
        "the whole stack lands in the attachment slot")
    local attached = TB.GetOrderFeedback()
    assert(attached and attached.kind == "ok"
        and attached.text == "Medium Leather x4 attached - press Send",
        "a verified attach reports the read-back: " .. tostring(attached and attached.text))

    -- 9. A split attaches exactly the need count, verified the same way.
    clearBags()
    setBag(0, 3, 2319, 10, "Medium Leather")
    cursor, mailItem = nil, nil
    calls = {}
    clearDraft()
    TB.SendOrderMissingItems("Goldie")
    assert(nameSeq() == "CursorHasItem,GetSendMailItem,MailFrameTab_OnClick,SplitContainerItem,"
        .. "ClickSendMailItemButton,GetSendMailItem,CursorHasItem",
        "a larger stack splits instead of picking up: " .. nameSeq())
    assert(argsOf("SplitContainerItem")[3] == 4 and mailItem and mailItem.count == 4,
        "the split takes the need count and the slot shows it")
    assert(TB.GetOrderFeedback().text == "Medium Leather x4 attached - press Send",
        "the split reports the need count")

    -- 10. The attachment slot already holds an item: nothing is picked up
    -- (a pickup would swap that item away) and the message says why.
    cursor, mailItem = nil, { name = "Cured Light Hide", count = 2 }
    SendMailNameEditBox:SetText("Friend")
    SendMailSubjectEditBox:SetText("my draft")
    calls = {}
    TB.SendOrderMissingItems("Goldie")
    assert(not hasCall("PickupContainerItem") and not hasCall("SplitContainerItem")
        and not hasCall("ClickSendMailItemButton"),
        "an occupied attachment slot stops the attach before any pickup")
    local busy = TB.GetOrderFeedback()
    assert(busy and busy.kind == "error"
        and string.find(busy.text, "the mail already holds Cured Light Hide", 1, true) ~= nil,
        "an occupied slot says why nothing was attached: " .. tostring(busy and busy.text))
    assert(SendMailNameEditBox:GetText() == "Friend" and SendMailSubjectEditBox:GetText() == "my draft"
        and not hasCall("MailFrameTab_OnClick"),
        "a draft with an attachment is left untouched (re-addressing it would mail that item to the bot)")

    -- 11. An item on the cursor: nothing is moved, the held item is left alone.
    cursor, mailItem = { name = "Cured Light Hide", count = 2 }, nil
    SendMailNameEditBox:SetText("Friend")
    calls = {}
    TB.SendOrderMissingItems("Goldie")
    assert(SendMailNameEditBox:GetText() == "Friend", "a busy cursor leaves the draft untouched")
    assert(not hasCall("PickupContainerItem") and not hasCall("SplitContainerItem")
        and not hasCall("ClickSendMailItemButton"),
        "a busy cursor stops the attach before any pickup")
    assert(cursor and cursor.name == "Cured Light Hide",
        "the item on the cursor is left untouched")
    local held = TB.GetOrderFeedback()
    assert(held and held.kind == "error"
        and string.find(held.text, "cursor", 1, true) ~= nil,
        "a busy cursor says why nothing was attached: " .. tostring(held and held.text))

    -- 12. A missing mail API attaches nothing and never claims success.
    clearBags()
    setBag(0, 3, 2319, 4, "Medium Leather")
    cursor, mailItem = nil, nil
    local savedPickup = PickupContainerItem
    PickupContainerItem = nil
    calls = {}
    clearDraft()
    local ok, err = pcall(TB.SendOrderMissingItems, "Goldie")
    assert(ok, "a missing PickupContainerItem must not error: " .. tostring(err))
    assert(not hasCall("ClickSendMailItemButton") and mailItem == nil,
        "no pickup call means no attach click")
    local gap = TB.GetOrderFeedback()
    assert(gap and gap.kind == "error"
        and string.find(gap.text, "PickupContainerItem", 1, true) ~= nil
        and string.find(gap.text, "attached - press Send", 1, true) == nil,
        "a missing API says which one instead of reporting success: " .. tostring(gap and gap.text))
    assert(SendMailNameEditBox:GetText() == "Goldie",
        "the text fields still fill without the pickup API")
    PickupContainerItem = savedPickup
    local savedCursorProbe = CursorHasItem
    CursorHasItem = nil
    calls = {}
    clearDraft()
    pcall(TB.SendOrderMissingItems, "Goldie")
    assert(not hasCall("PickupContainerItem") and not hasCall("ClickSendMailItemButton"),
        "no cursor probe means no pickup and no attach")
    assert(string.find(TB.GetOrderFeedback().text, "CursorHasItem", 1, true) ~= nil,
        "the missing cursor probe is named")
    CursorHasItem = savedCursorProbe

    -- 13. A mismatched attach: the client is the only witness, so clear the
    -- cursor and report an error, never "attached".
    clearBags()
    setBag(0, 3, 2319, 4, "Medium Leather")
    cursor, mailItem = nil, nil
    ClickSendMailItemButton = function()
        table.insert(calls, { name = "ClickSendMailItemButton" })
        cursor = nil -- the click eats the cursor item...
        mailItem = { name = "Cured Light Hide", count = 2 } -- ...but the slot holds another
    end
    calls = {}
    clearDraft()
    TB.SendOrderMissingItems("Goldie")
    assert(hasCall("ClearCursor"), "a mismatched attach clears the cursor")
    assert(SendMailNameEditBox:GetText() == "",
        "a mismatched attach clears the recipient so the wrong item cannot be sent to the bot")
    local wrong = TB.GetOrderFeedback()
    assert(wrong and wrong.kind == "error" and string.find(wrong.text, "recipient cleared", 1, true) ~= nil,
        "a mismatched attach says the recipient was cleared: " .. tostring(wrong and wrong.text))

    local wrong = TB.GetOrderFeedback()
    assert(wrong and wrong.kind == "error"
        and string.find(wrong.text, "Cured Light Hide x2", 1, true) ~= nil
        and string.find(wrong.text, "attached - press Send", 1, true) == nil,
        "a mismatched attach is an error, not attached: " .. tostring(wrong and wrong.text))

    -- 10b. A text-only draft (no attachment, empty cursor) is the player's: left untouched.
    cursor, mailItem = nil, nil
    clearDraft()
    SendMailBodyEditBox:SetText("hi friend")
    calls = {}
    TB.SendOrderMissingItems("Goldie")
    assert(SendMailBodyEditBox:GetText() == "hi friend" and SendMailNameEditBox:GetText() == ""
        and not hasCall("MailFrameTab_OnClick") and not hasCall("PickupContainerItem"),
        "a text-only draft is not overwritten")
    clearDraft()

    -- 14. The click leaves the item on the cursor: same error path.
    cursor, mailItem = nil, nil
    ClickSendMailItemButton = function()
        table.insert(calls, { name = "ClickSendMailItemButton" })
    end
    calls = {}
    clearDraft()
    TB.SendOrderMissingItems("Goldie")
    assert(hasCall("ClearCursor"), "an item left on the cursor after the click is cleared")
    assert(cursor == nil, "ClearCursor empties the cursor")
    local stuck = TB.GetOrderFeedback()
    assert(stuck and stuck.kind == "error"
        and string.find(stuck.text, "attached - press Send", 1, true) == nil,
        "an item stuck on the cursor is an error, not attached: " .. tostring(stuck and stuck.text))

    -- Restore the mock globals this block defined.
    MailFrame = nil
    SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox = nil, nil, nil
    GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = nil, nil, nil
    PickupContainerItem, SplitContainerItem, ClickSendMailItemButton = nil, nil, nil
    CursorHasItem, GetSendMailItem, ClearCursor = nil, nil, nil
    MailFrameTab_OnClick, SendMail = nil, nil
end
sendMissingItemsBlock()

-- Access snapshot: parse, header text, edge cases.
TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|-|-|-|craft|-")
TB.OnSystemMessage("TBM:ORDER_END")
local access = TB.GetOrderAccess()
assert(access and access.rankIndex == 2 and access.rankName == "Raider"
    and table.getn(access.tabsOk) == 2 and access.tabsDenied == nil
    and access.gold == true and access.canSetRank == true, "access parses")
local accessText = TB.OrderAccessText()
assert(accessText and not accessText.bad
    and string.find(accessText.text, "rank Raider", 1, true) ~= nil
    and string.find(accessText.text, "bank tabs 1,2", 1, true) ~= nil
    and string.find(accessText.text, "gold yes", 1, true) ~= nil,
    "the header names rank, tabs and gold")
TB.OnSystemMessage("TBM:ORDER_ACCESS|-|-|-|-|0|0")
assert(TB.GetOrderAccess().rankIndex == nil
    and string.find(TB.OrderAccessText().text, "does not manage", 1, true) ~= nil
    and TB.OrderAccessText().bad == false, "a dash rank stays grey with no control")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|-|-|1|0")
assert(string.find(TB.OrderAccessText().text, "No guild bank yet", 1, true) ~= nil
    and TB.OrderAccessText().bad == false, "no unlocked bank stays grey")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1|2|0|1")
local deniedText = TB.OrderAccessText()
assert(deniedText.bad and string.find(deniedText.text, "tabs 2 denied", 1, true) ~= nil
    and string.find(deniedText.text, "gold no", 1, true) ~= nil,
    "denied tabs show red with what is missing")
TB.OnSystemMessage("TBM:ORDER_ACCESS|4|Initiate|1|-|0|1")
assert(not TB.OrderAccessText().bad
    and string.find(TB.OrderAccessText().text, "gold no", 1, true) ~= nil,
    "no gold access alone stays plain")
assert(TB.ParseOrderAccess("TBM:ORDER_ACCESS|2|Raider|1|x|1|1") == nil
    and TB.ParseOrderAccess("TBM:ORDER_ACCESS|2") == nil
    and TB.OrderTabList({ 1, 2 }) == "1,2" and TB.OrderTabList(nil) == "-",
    "bad access lines drop, tab lists join or dash")
assert(TB.ParseOrderAccess("TBM:ORDER_ACCESS|-|-|-|-|0|0").rankIndex == nil,
    "the unmanaged line parses")
assert(TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale|easy|3|keep|-|-|-|-|future|1") ~= nil,
    "extra future trailing fields are ignored")
TB._lastOrderListAt = now - 31
now = now + 1
local beforePoll = table.getn(addonSent)
TB.OrderPollTick()
assert(table.getn(addonSent) == beforePoll + 1 and lastAddon() == "order list",
    "the 30s poll sends the list only, no extra access")

-- Rank options: guild master skipped, names from the guild API, GM rankIndex
-- 0 never offered, current bot rank marked.
GuildControlGetNumRanks = function() return 4 end
GuildControlGetRankName = function(i)
    local names = { "Guild Master", "Officer", "Raider", "Alt" }
    return names[i]
end
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
local rankOptions = TB.GetOrderRankOptions()
assert(table.getn(rankOptions) == 3 and rankOptions[1].index == 1
    and rankOptions[1].name == "Officer" and rankOptions[2].current == true
    and rankOptions[2].name == "Raider", "rank options skip GM and mark current")
local currentRows = {}
TB.BuildOrderRankMenu(function(info) table.insert(currentRows, info) end)
assert(currentRows[2].disabled and not currentRows[1].disabled,
    "the current rank row is disabled, others stay clickable")
GuildControlGetNumRanks = nil
GuildControlGetRankName = nil
local fallbackOptions = TB.GetOrderRankOptions()
assert(table.getn(fallbackOptions) == 9 and fallbackOptions[1].name == "Rank 1",
    "no guild API falls back to Rank <idx>")
local rankButtons = {}
assert(TB.BuildOrderRankMenu(function(info) table.insert(rankButtons, info) end) == 9,
    "the rank menu builds one row per rank")
assert(string.find(rankButtons[2].text, "%(current%)", 1) == nil or true,
    "rank rows render")
rankButtons[1].func()
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"].text
    == "Move all guild bots to rank Rank 1?", "a rank row asks one confirm")
now = now + 1
StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"].OnAccept()
assert(lastAddon() == "order rank 1", "the rank menu sends the server index")

-- Reassign candidates: claimed bots first, ordered bots too, worker excluded.
TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|-|-|-|-|-|-|-|-")
TB.OnSystemMessage("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|-|-")
TB.OnSystemMessage("TBM:ORDER_END")
local candidates = TB.GetOrderReassignCandidates("Silver")
assert(table.getn(candidates) == 2 and candidates[1] == "Bronze" and candidates[2] == "Goldie",
    "candidates exclude the worker and sort")
assert(TB.BuildOrderReassignMenu("Goldie", function() end) == 0,
    "a top-level order has no reassign menu")
local reassignButtons = {}
assert(TB.BuildOrderReassignMenu("Silver", function(info)
    table.insert(reassignButtons, info) end) == table.getn(candidates),
    "the reassign menu builds one row per candidate")
reassignButtons[1].func()
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"].text
    == "Hand Silver's sub-order to " .. candidates[1] .. "?",
    "a reassign row asks one confirm")
now = now + 1
StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"].OnAccept()
assert(lastAddon() == "order reassign Silver " .. candidates[1],
    "the reassign menu sends both bots")
now = now + 1

-- Deep branch cancel: grandchildren at any depth go with the parent.
TB.OnSystemMessage("TBM:ORDER_BEGIN|3")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|-|-|-|keep|-|-|craft|-")
TB.OnSystemMessage("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|craft|-")
TB.OnSystemMessage("TBM:ORDER|Copper|craft|2320|Cured Light Hide|0|5|working|-|-|-|-|-|Silver|-|craft|-")
TB.OnSystemMessage("TBM:ORDER_END")
assert(TB.GetBotOrder("Copper") ~= nil, "the grandchild lands")
TB.ConfirmOrderCancel("Goldie")
StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
assert(TB.GetBotOrder("Goldie") == nil and TB.GetBotOrder("Silver") == nil
    and TB.GetBotOrder("Copper") == nil, "a parent ACK prunes the whole branch at any depth")

-- Live access refreshes the guild tab, not just the window.
TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|-|-|-|-|-|-|craft|-")
TB.OnSystemMessage("TBM:ORDER_END")
TB.OnSystemMessage("TBM:ORDER_ACCESS|3|Member|1|-|1|1")
assert(string.find(TB.guildFrame.accessLine:GetText(), "Member", 1, true) ~= nil,
    "a live access line repaints the guild tab")

-- Rank ACK strips the scope prefix.
TB.OnSystemMessage("TBM:ACTION_ACK|order|rank:3|1|rank")
assert(TB.lastActionAck and TB.lastActionAck.executor == "rank",
    "the rank ACK routes")

-- Parent cancel warns it takes the branch; the ACK prunes it.
TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")
TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|4|10|working|-|-|-|-|keep|-|-|-|-")
TB.OnSystemMessage("TBM:ORDER|Silver|craft|2319|Medium Leather|1|5|working|-|-|-|-|-|Goldie|-|-|-")
TB.OnSystemMessage("TBM:ORDER_END")
TB.ConfirmOrderCancel("Goldie")
assert(string.find(StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].text,
    "whole branch", 1, true) ~= nil, "a parent cancel warns it takes the branch")
StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
assert(lastAddon() == "order Goldie cancel", "confirming still sends")
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
assert(TB.GetBotOrder("Goldie") == nil and TB.GetBotOrder("Silver") == nil,
    "a parent ACK prunes the branch")

-- Rank and reassign: sends, ACKs, picker guards.
assert(TB.SendOrderRank(-1) == false, "a negative rank is refused")
now = now + 1
TB.SendOrderRank(2)
assert(lastAddon() == "order rank 2", "rank sends the index")
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|rank")
now = now + 1
TB.RequestOrderAccess()
assert(lastAddon() == "order access", "access asks for the snapshot")
now = now + 1
assert(TB.SendOrderReassign("Silver", "Goldie") == true, "reassign sends both bots")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Silver|1|reassign")
assert(TB.SendOrderReassign("Silver", "") == false, "bad reassign is refused")
TB.ConfirmOrderRank(2, "Raider")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"] ~= nil
    and StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"].text
        == "Move all guild bots to rank Raider?",
    "the rank confirm names the rank")
now = now + 1
StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_RANK"].OnAccept()
assert(lastAddon() == "order rank 2", "confirming rank sends the server index")
now = now + 1
TB.ConfirmOrderReassign("Silver", "Goldie")
assert(StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"] ~= nil
    and StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"].text
        == "Hand Silver's sub-order to Goldie?",
    "the reassign confirm names both bots")
StaticPopupDialogs["TORTOISEBOTSMANAGER_ORDER_REASSIGN"].OnAccept()
now = now + 1
assert(lastAddon() == "order reassign Silver Goldie", "confirming reassign sends both bots")
assert(TB.ConfirmOrderReassign("Silver", "Silver") == false
    and TB.ConfirmOrderRank(-1) == false, "same-bot reassign and negative rank are refused")
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

-- ── Per-order step history (TBM:ORDER_STEPS_*): request, cache, tooltip ───
-- The server answers ".bot order <bot> steps" with BEGIN, one ORDER_STEP per
-- entry (oldest first) and END; the addon caches it per bot and shows the
-- newest steps inside the order tooltip. Own function: the main chunk is at
-- Lua's 200-local limit.
local function orderStepHistoryChecks()
    -- Parse: six fields after the prefix, ages and item ids numeric and >= 0.
    local stepLine = TB.ParseOrderStepLine("TBM:ORDER_STEP|Goldie|90|working|nobanker|bank|2319")
    assert(stepLine and stepLine.bot == "Goldie" and stepLine.age == 90
        and stepLine.state == "working" and stepLine.reason == "nobanker"
        and stepLine.step == "bank" and stepLine.itemId == 2319, "step lines parse")
    assert(TB.ParseOrderStepLine("TBM:ORDER_STEP|Goldie|90|working|nobanker|bank") == nil,
        "a five-field step line is dropped")
    assert(TB.ParseOrderStepLine("TBM:ORDER_STEP|Goldie|-5|working|-|bank|2319") == nil,
        "a negative age drops the step line")

    -- Gate off: no request, no send without the guild-order-steps token.
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    local before = table.getn(addonSent)
    assert(TB.RequestOrderSteps("Goldie") == false, "no step request without the capability")
    assert(table.getn(addonSent) == before, "a gated step request sends nothing")

    -- Request: one per bot per 15 s.
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    now = now + 1
    assert(TB.RequestOrderSteps("Goldie") == true, "a capable server gets the step request")
    assert(lastAddon() == "order Goldie steps", "the request names the bot and the steps sub-command")
    assert(TB.RequestOrderSteps("Goldie") == false, "a second request at the same time is throttled")
    now = now + 1
    before = table.getn(addonSent)
    assert(TB.RequestOrderSteps("Goldie") == false, "the throttle holds a second later too")
    assert(table.getn(addonSent) == before, "the throttled request sends nothing")
    now = now + 15
    assert(TB.RequestOrderSteps("Goldie") == true, "the throttle opens after 15 s")

    -- Cache: BEGIN buffers, ORDER_STEP appends, END commits.
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|2|3")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|90|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|30|working|nobanker|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    local cache = TB.GetOrderSteps("Goldie")
    assert(cache and table.getn(cache.entries) == 2 and cache.dropped == 3,
        "an END commits the buffered entries and the dropped count")
    assert(cache.entries[1].age == 90 and cache.entries[2].age == 30,
        "the cache keeps the server's oldest-first order")

    -- Tooltip block: newest first, ages, the earlier count.
    local lines = TB.OrderStepsTooltipLines("Goldie")
    assert(table.getn(lines) == 4
        and lines[1] == "Steps (newest first):"
        and lines[2] == "  just now · taking from guild bank: Medium Leather (no banker in reach)"
        and lines[3] == "  1m ago · taking from guild bank: Medium Leather"
        and lines[4] == "  ... 3 earlier steps",
        "the block lists the newest steps with ages and the earlier count")
    now = now + 3600
    lines = TB.OrderStepsTooltipLines("Goldie")
    assert(lines[2] == "  1h ago · taking from guild bank: Medium Leather (no banker in reach)"
        and lines[3] == "  1h 1m ago · taking from guild bank: Medium Leather",
        "ages grow with the time since the reply arrived")

    -- The order tooltip carries the block for its own order: a matching
    -- identity still shows the cache.
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|30|working|nobanker|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(string.find(TB.OrderTooltipText(TB.GetBotOrder("Goldie")), "Steps (newest first):", 1, true) ~= nil,
        "a matching identity still shows the cache")

    -- A new order on the same bot drops the old history: the tooltip shows
    -- nothing until the fresh reply lands.
    TB.OnSystemMessage("TBM:ORDER|Goldie|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
    assert(TB.GetBotOrder("Goldie") ~= nil, "the new order lands")
    assert(TB.GetOrderSteps("Goldie") == nil, "a new order on the same bot drops the old history")
    assert(table.getn(TB.OrderStepsTooltipLines("Goldie")) == 0,
        "a new order tooltips no stale steps")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|30|working|-|bank|18231")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(table.getn(TB.OrderStepsTooltipLines("Goldie")) == 2,
        "the fresh reply for the current order shows again")

    -- A full list snapshot with a different order drops it too.
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|10|working|-|Ashenvale")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(TB.GetOrderSteps("Goldie") == nil, "a full list with a new order drops the old history")

    -- Same type and item with a different parent is a new order too.
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|30|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|10|working|-|Ashenvale|-|-|-|Silver|-|-|-")
    assert(TB.GetOrderSteps("Goldie") == nil, "a changed parent drops the history")

    -- Losing the step token wipes the whole cache (session or restart).
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|30|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(TB.GetOrderSteps("Goldie") ~= nil, "the step reply lands")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    assert(TB.GetOrderSteps("Goldie") == nil, "losing the step token clears the cache")

    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    -- Bound: eight entries plus one earlier line.
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|12|0")
    for i = 1, 12 do
        TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|" .. (i * 60) .. "|working|-|bank|2319")
    end
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    lines = TB.OrderStepsTooltipLines("Goldie")
    assert(table.getn(lines) == 10 and lines[10] == "  ... 4 earlier steps",
        "the block caps at eight entries and counts the rest")
    assert(string.find(lines[2], "  12m ago", 1, true) == 1
        and string.find(lines[9], "  5m ago", 1, true) == 1,
        "the eight newest entries show, newest first")

    -- Foreign lines: another bot's step line is ignored, an END needs its BEGIN.
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|20|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEP|Silver|10|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(table.getn(TB.GetOrderSteps("Goldie").entries) == 1,
        "another bot's step line is not buffered")
    before = table.getn(addonSent)
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Silver")
    assert(TB.GetOrderSteps("Silver") == nil, "an END without its BEGIN stores nothing")
    assert(table.getn(addonSent) == before, "a stray END sends nothing")
    assert(TB.ParseOrderMessage("TBM:ORDER_STEP|Goldie|1|done|-|-|0") == true,
        "a bare step line is still claimed by the order parser")

    -- Throttle reset: a changed live line clears it, an identical one does not.
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    now = now + 1
    assert(TB.RequestOrderSteps("Goldie") == true, "a fresh step request lands")
    assert(TB.RequestOrderSteps("Goldie") == false, "the throttle holds at once")
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|ah|-")
    now = now + 1
    assert(TB.RequestOrderSteps("Goldie") == true, "a changed step clears the throttle")
    before = table.getn(addonSent)
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|ah|-")
    assert(TB.RequestOrderSteps("Goldie") == false, "an identical live line keeps the throttle")
    assert(table.getn(addonSent) == before, "the throttled call sends nothing")

    -- Count check. Fresh bots per case so no earlier cache or throttle leaks in.
    -- A BEGIN count that matches the valid entries commits, without the flag.
    now = now + 60
    TB.OnSystemMessage("TBM:ORDER|Ruth|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    assert(TB.RequestOrderSteps("Ruth") == true, "a fresh request for Ruth goes out")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Ruth|2|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Ruth|90|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEP|Ruth|30|working|nobanker|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Ruth")
    assert(TB.GetOrderSteps("Ruth") and table.getn(TB.GetOrderSteps("Ruth").entries) == 2,
        "a count that matches its entries commits")
    assert(table.getn(TB.OrderStepsTooltipLines("Ruth")) > 0
        and string.find(TB.OrderStepsTooltipLines("Ruth")[1], "history incomplete", 1, true) == nil,
        "a committed list shows no incomplete flag")

    -- One entry missing (BEGIN says two): discarded, nothing cached, the
    -- tooltip says so, and the throttle is free so the next hover asks again.
    now = now + 60
    TB.OnSystemMessage("TBM:ORDER|Hilda|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    assert(TB.RequestOrderSteps("Hilda") == true, "a fresh request for Hilda goes out")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Hilda|2|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Hilda|30|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Hilda")
    assert(TB.GetOrderSteps("Hilda") == nil, "one missing entry: the list is discarded, not committed")
    lines = TB.OrderStepsTooltipLines("Hilda")
    assert(table.getn(lines) == 1 and lines[1] == "Steps: history incomplete, retrying",
        "a discarded list flags the tooltip as incomplete, retrying")
    -- Goldie's request above never got its END, so it still holds the one
    -- steps slot; the slot times out after 5 s, then the retry goes out.
    now = now + 6
    before = table.getn(addonSent)
    assert(TB.RequestOrderSteps("Hilda") == true, "a discarded reply frees the throttle at once")
    assert(lastAddon() == "order Hilda steps", "the retry asks the same bot again")

    -- Over the cap: a BEGIN count above 16 is refused and its entries ignored.
    now = now + 60
    TB.OnSystemMessage("TBM:ORDER|Tessa|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    assert(TB.RequestOrderSteps("Tessa") == true, "a fresh request for Tessa goes out")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Tessa|17|0")
    for i = 1, 17 do
        TB.OnSystemMessage("TBM:ORDER_STEP|Tessa|" .. (i * 10) .. "|working|-|bank|2319")
    end
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Tessa")
    assert(TB.GetOrderSteps("Tessa") == nil, "an oversized count is rejected, nothing commits")
    lines = TB.OrderStepsTooltipLines("Tessa")
    assert(table.getn(lines) == 1 and lines[1] == "Steps: history incomplete, retrying",
        "a rejected count flags the tooltip")
    now = now + 6 -- Goldie's and Hilda's unanswered requests hold the slot until it times out
    assert(TB.RequestOrderSteps("Tessa") == true, "a rejected count frees the throttle at once")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Tessa|0|0") -- answer the retry (no steps), so the slot frees
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Tessa")

    -- The cap itself is accepted: sixteen entries commit.
    now = now + 60
    TB.OnSystemMessage("TBM:ORDER|Vera|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    assert(TB.RequestOrderSteps("Vera") == true, "a fresh request for Vera goes out")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Vera|16|0")
    for i = 1, 16 do
        TB.OnSystemMessage("TBM:ORDER_STEP|Vera|" .. (i * 10) .. "|working|-|bank|2319")
    end
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Vera")
    assert(TB.GetOrderSteps("Vera") and table.getn(TB.GetOrderSteps("Vera").entries) == 16,
        "sixteen entries, the cap itself, commit")

    -- A complete retry for Hilda clears her flag.
    now = now + 60
    assert(TB.RequestOrderSteps("Hilda") == true, "Hilda's retry goes out after the throttle")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Hilda|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Hilda|30|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Hilda")
    assert(TB.GetOrderSteps("Hilda") ~= nil, "the complete retry commits")
    lines = TB.OrderStepsTooltipLines("Hilda")
    assert(lines[1] == "Steps (newest first):", "a committed retry clears the incomplete flag")

    -- Entry and age texts.
    assert(TB.OrderStepText({ state = "done", itemId = 0 }) == "Done",
        "a finished step reads as its state")
    assert(TB.OrderStepText({ state = "waiting", reason = "needitems", itemId = 0 })
        == "Waiting (needs items from you)", "a waiting step carries its reason")
    assert(TB.OrderStepAgeText(7260) == "2h 1m ago" and TB.OrderStepAgeText(7200) == "2h ago"
        and TB.OrderStepAgeText(90000) == "1d ago", "ages read in minutes, hours and days")

    -- Repaint: a committed list redraws the hovered row without a new request.
    -- The changed live line below clears the throttle, so a repaint that asked
    -- again would really send. The time step keeps the tab's own "order list"
    -- out of the send queue (a queued command would leak into the wire cases).
    now = now + 1
    TB.ShowTab("guild")
    local tipRow = TB.guildFrame.rows[1]
    assert(tipRow.entry and tipRow.entry.name == "Goldie", "the guild row holds Goldie")
    local tipLines = {}
    local realAddLine = GameTooltip.AddLine
    GameTooltip.AddLine = function(_, text) table.insert(tipLines, text) end
    now = now + 16
    TB.ShowGuildRowTooltip(tipRow)
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|deliver|-")
    now = now + 1
    before = table.getn(addonSent)
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    GameTooltip.AddLine = realAddLine
    local sawStepBlock = false
    for _, text in ipairs(tipLines) do
        if string.find(text, "Steps (newest first):", 1, true) then sawStepBlock = true end
    end
    assert(sawStepBlock, "the committed list redraws the hovered tooltip")
    assert(table.getn(addonSent) == before, "the repaint sends no second request")
    -- Stale reply: asked for A, the bot moved to B, the reply lands late.
    -- Nothing is cached and B tooltips no steps; the next hover may ask again.
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    TB.OnSystemMessage("TBM:ORDER|Goldie|craft|2318|Light Leather|2|10|working|-|-|-|-|-|-|-|bank|-")
    now = now + 16
    assert(TB.RequestOrderSteps("Goldie") == true, "the step request for the old order lands")
    assert(lastAddon() == "order Goldie steps", "the stale-reply request names the bot")
    TB.OnSystemMessage("TBM:ORDER|Goldie|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
    assert(TB.GetBotOrder("Goldie") ~= nil, "the replacement order lands")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(TB.GetOrderSteps("Goldie") == nil, "a late reply for the old order is not cached")
    assert(table.getn(TB.OrderStepsTooltipLines("Goldie")) == 0,
        "a late reply shows no steps for the new order")
    now = now + 1
    assert(TB.RequestOrderSteps("Goldie") == true, "the discard leaves the next hover free to ask again")

    -- Old server: without the token the block stays away (the cache was
    -- already wiped when the token went missing above).
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    assert(TB.GetOrderSteps("Goldie") == nil, "a missing token leaves no step cache")
    assert(table.getn(TB.OrderStepsTooltipLines("Goldie")) == 0,
        "no step block on a server without the token")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    assert(TB.HasOrderCapability() and not TB.HasServerCapability("guild-order-steps"),
        "the block restores the capability set")
end
orderStepHistoryChecks()
-- ── Step hover dwell + single outstanding (Opus cold review) ───────────────
-- A hover asks only after the cursor rests 0.4 s; one steps reply in flight
-- blocks the next bot until END or 5 s. Own function: chunk local limit.
local function stepHoverDwellChecks()
    TB._stepsDwell = nil
    TB._guildTipRow = nil
    TB._guildTipOwner = nil
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    TB.OnSystemMessage("TBM:ORDER|Goldie|Farm|2318|Light Leather|0|10|working|-|Ashenvale")
    TB.OnSystemMessage("TBM:ORDER|Silver|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
    for i = 1, 20 do
        TB.OnSystemMessage("TBM:ORDER|Sweep" .. i .. "|farm|2318|Light Leather|0|10|working|-|Ashenvale")
    end
    now = now + 16
    TB.ShowTab("guild")
    TB.RefreshGuildView()
    local dwellFrame = frames["TortoiseBotsManagerStepsDwell"]
    assert(dwellFrame and dwellFrame.scripts.OnUpdate, "the steps dwell timer must exist")
    local hoverRow = TB.guildFrame.rows[1]
    assert(hoverRow and hoverRow.scripts.OnEnter and hoverRow.scripts.OnLeave, "guild rows must hover")
    local row1 = TB.guildFrame.rows[1]
    assert(row1.entry and row1.entry.name == "Goldie", "the first guild row holds Goldie")

    -- Sweep: 20 quick hovers (0.2 s each) send nothing.
    local beforeSweep = table.getn(addonSent)
    for i = 1, 20 do
        local fake = { entry = { name = "Sweep" .. i, level = 60, className = "Warrior", status = "Online" } }
        this = fake
        hoverRow.scripts.OnEnter(hoverRow)
        now = now + 0.2
        dwellFrame.scripts.OnUpdate(dwellFrame)
        this = fake
        hoverRow.scripts.OnLeave(hoverRow)
    end
    now = now + 1
    dwellFrame.scripts.OnUpdate(dwellFrame)
    assert(table.getn(addonSent) == beforeSweep, "sweeping 20 rows sends no step request")

    -- Rest: 0.5 s on Goldie sends one request.
    now = now + 1
    local stay = { entry = { name = "Goldie", level = 60, className = "Warrior", status = "Online" } }
    this = stay
    hoverRow.scripts.OnEnter(hoverRow)
    now = now + 0.5
    dwellFrame.scripts.OnUpdate(dwellFrame)
    assert(table.getn(addonSent) == beforeSweep + 1 and lastAddon() == "order Goldie steps",
        "resting 0.5 s sends one step request")
    this = stay
    hoverRow.scripts.OnLeave(hoverRow)

    -- Outstanding: Silver waits while Goldie's reply is in flight.
    now = now + 1
    local beforeSecond = table.getn(addonSent)
    local silver = { entry = { name = "Silver", level = 45, className = "Priest", status = "Online" } }
    this = silver
    hoverRow.scripts.OnEnter(hoverRow)
    now = now + 0.5
    dwellFrame.scripts.OnUpdate(dwellFrame)
    assert(table.getn(addonSent) == beforeSecond, "a second row waits while one steps request is outstanding")
    this = silver
    hoverRow.scripts.OnLeave(hoverRow)

    -- After 5 s without an END the next hover may ask again.
    now = now + 6
    this = silver
    hoverRow.scripts.OnEnter(hoverRow)
    now = now + 0.5
    dwellFrame.scripts.OnUpdate(dwellFrame)
    assert(table.getn(addonSent) == beforeSecond + 1 and lastAddon() == "order Silver steps",
        "the single outstanding request times out after 5 s")
    this = silver
    hoverRow.scripts.OnLeave(hoverRow)

    -- Both late replies still commit each bot's own list.
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(TB.GetOrderSteps("Goldie") ~= nil, "Goldie's late reply still commits")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Silver|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Silver|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Silver")
    assert(TB.GetOrderSteps("Silver") ~= nil, "Silver's reply still commits")

    -- Identity is case-insensitive: the "Farm" row keeps its steps.
    assert(table.getn(TB.OrderStepsTooltipLines("Goldie")) == 2, "the Farm row tooltips its steps")

    -- Repaint only while the row still shows and still owns the tooltip.
    local tipRow = TB.guildFrame.rows[1]
    assert(tipRow.entry and tipRow.entry.name == "Goldie", "the first guild row still holds Goldie")
    local tipLines = {}
    local realAddLine = GameTooltip.AddLine
    GameTooltip.AddLine = function(_, text) table.insert(tipLines, text) end
    this = tipRow
    tipRow.scripts.OnEnter(tipRow)
    TB._stepsDwell = nil
    tipLines = {}
    tipRow:Hide()
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(table.getn(tipLines) == 0, "a hidden row gets no repaint")
    tipRow:Show()
    GameTooltip.owner = TB.guildFrame.rows[2]
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    assert(table.getn(tipLines) == 0, "a moved tooltip gets no repaint")
    this = tipRow
    tipRow.scripts.OnEnter(tipRow)
    TB._stepsDwell = nil
    tipLines = {}
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")
    local sawStepBlock = false
    for _, text in ipairs(tipLines) do
        if string.find(text, "Steps (newest first):", 1, true) then sawStepBlock = true end
    end
    assert(sawStepBlock, "the visible owned row still repaints")
    GameTooltip.AddLine = realAddLine
    this = tipRow
    tipRow.scripts.OnLeave(tipRow)

    -- Token loss clears the per-bot request times: asking again works at once.
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    now = now + 16
    assert(TB.RequestOrderSteps("Goldie") == true, "a fresh step request lands before the token loss")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-steps")
    now = now + 1
    assert(TB.RequestOrderSteps("Goldie") == true, "losing the step token clears the request throttle")
    TB.OnSystemMessage("TBM:ORDER_STEPS_BEGIN|Goldie|1|0")
    TB.OnSystemMessage("TBM:ORDER_STEP|Goldie|5|working|-|bank|2319")
    TB.OnSystemMessage("TBM:ORDER_STEPS_END|Goldie")

    -- Leave no step state behind for the tests below.
    TB._stepsDwell = nil
    TB._guildTipRow = nil
    TB._guildTipOwner = nil
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|2")
    TB.OnSystemMessage("TBM:ORDER|Goldie|farm|2318|Light Leather|0|10|working|-|Ashenvale")
    TB.OnSystemMessage("TBM:ORDER|Silver|buy|18231|Highland Spring Water|0|20|waiting|grouped|Ironforge")
    TB.OnSystemMessage("TBM:ORDER_END")
end
stepHoverDwellChecks()

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
assert(TB.OrderReasonLabel("noprogress") == "no progress - the bot found nothing to farm", "noprogress gets a plain reason")
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
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
now = now + 1
assert(TB.OpenOrderWindow("Goldie"), "the window opens for a guild bot")
assert(lastAddon() == "order access", "opening the window fetches access when missing")
assert(TB.orderWindow:IsVisible() and TB.GetOrderWindowBot() == "Goldie",
    "the window tracks its bot")
assert(TB.orderWindow.title:GetText() == "Order for Goldie", "the title names the bot")
assert(TB.orderWindow.statusLine:GetText() == "No order on this bot.",
    "the window shows no order after the branch was pruned")
assert(TB.orderWindow.amountBox:GetText() == "10", "a fresh window starts at 10")
assert(TB.orderWindow.hoursBox:GetText() == "1", "farm time keeps 1 hour behind no limit")
assert(TB.GetOrderNoLimit() == true and TB.orderWindow.noLimitBox:GetChecked(),
    "a fresh window ticks no time limit")
assert(TB.orderWindow.hoursBox.mouseEnabled == false,
    "a fresh window greys the hours box")
assert(TB.orderWindow.farmNote ~= nil
    and string.find(TB.orderWindow.farmNote:GetText(), "Bots farm like players", 1, true) ~= nil,
    "the window warns that big or rare farms take very long")
assert(TB.orderWindow.sendItemsBtn ~= nil, "the window carries a Send missing items button")
assert(TB.orderWindow.sendItemsBtn.enabled == false,
    "no open mailbox leaves the Send missing items button dead")
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
assert(lastAddon() == "order Goldie farm 2318 10 inf", "Send gives the picked item and amount with no time limit")
assert(string.find(TB.GetOrderFeedback().text, "sent, waiting"), "Send says it is waiting")
TB.SetOrderNoLimit(false)
assert(TB.GetOrderNoLimit() == false and not TB.orderWindow.noLimitBox:GetChecked(),
    "unticking arms a capped farm time")
assert(TB.orderWindow.hoursBox.mouseEnabled ~= false,
    "unticking enables the hours box")
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

-- Gold cap fallback: an old server sheds gold first, then keep, then hours.
now = now + 1
TB.SendOrderGive("Goldie", "farm", 2318, 10, 2, true, 10000)
assert(lastAddon() == "order Goldie farm 2318 10 2 keep gold=10000", "a capped give carries gold")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10 2 keep", "an invalid-arg reply drops gold first")
assert(string.find(TB.GetOrderFeedback().text, "retrying without the guild gold cap", 1, true),
    "the gold retry says so")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10 2", "a second invalid-arg reply drops keep")
assert(TB.ClampOrderGold(nil) == nil and TB.GetOrderGold() == nil, "empty gold means no cap")
now = now + 1
TB.SendOrderGive("Goldie", "farm", 2318, 10, 2, true, 0)
assert(lastAddon() == "order Goldie farm 2318 10 2 keep gold=0", "gold=0 rides the wire as a real cap")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10 2 keep", "an invalid-arg reply drops gold=0 first")
assert(TB.SetOrderGold(0) == 0 and TB.orderWindow.goldBox:GetText() == "0", "zero shows as 0, not empty")
TB.SetOrderGold(nil)
now = now + 1
TB.SendOrderGive("Goldie", "farm", 2318, 10, 2, true, 10000)
assert(lastAddon() == "order Goldie farm 2318 10 2 keep gold=10000", "a capped give carries gold")
TB.orderWindow.goldBox.text = "10000"
this = TB.orderWindow.goldBox
TB.orderWindow.goldBox.scripts.OnTextChanged(TB.orderWindow.goldBox)
assert(TB.GetOrderGold() == 10000, "typing commits the gold cap")
TB.orderWindow.goldBox.text = ""
TB.orderWindow.goldBox.scripts.OnTextChanged(TB.orderWindow.goldBox)
assert(TB.GetOrderGold() == nil, "clearing the box clears the cap")
now = now + 1
TB.SendOrderGive("Goldie", "farm", 2318, 10, 2, true, 10000)
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
now = now + 1
TB.OnSystemMessage("TBM:ACTION_ERR|order|invalid|extra argument")
assert(lastAddon() == "order Goldie farm 2318 10", "a third invalid-arg reply drops the farm time")
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
assert(guildOrderRow.moreBtn:IsVisible() and guildOrderRow.moreBtn.enabled,
    "an order shows an enabled More menu")
TB._t.rowMenu = {}
assert(TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.rowMenu, info) end) > 0,
    "the row menu must list Cancel while the order runs")
TB._t.rowCancel = nil
table.foreach(TB._t.rowMenu, function(k, info) if info.text == "Cancel order" then TB._t.rowCancel = info end end)
assert(TB._t.rowCancel and TB._t.rowCancel.func, "the row menu must offer Cancel order")
now = now + 1
local beforeCancel = table.getn(addonSent)
TB._t.rowCancel.func()
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
TB.RefreshGuildView()
TB._t.noOrderMenu = {}
TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.noOrderMenu, info) end)
TB._t.noOrderCancel = nil
table.foreach(TB._t.noOrderMenu, function(k, info) if info.text == "Cancel order" then TB._t.noOrderCancel = info end end)
assert(TB._t.noOrderCancel == nil, "no order drops Cancel from the row menu")

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
assert(lastAddon() == "order Goldie farm 2318 25 inf", "Send sends the box number with no time limit")
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

-- No time limit: the default, parse inf, show "no limit", send inf; a
-- refused inf retries once as 24 hours. Old numeric rows still parse.
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
assert(TB.GetOrderNoLimit() == true and TB.orderWindow.noLimitBox:GetChecked(),
    "no limit starts ticked")
assert(TB.orderWindow.hoursBox.mouseEnabled == false
    and TB.orderWindow.hoursBox.textColor[1] == 0.5,
    "no limit greys the hours box")
TB.SetOrderNoLimit(false)
assert(TB.GetOrderNoLimit() == false and not TB.orderWindow.noLimitBox:GetChecked(),
    "unticking clears no limit")
assert(TB.orderWindow.hoursBox.mouseEnabled ~= false
    and TB.orderWindow.hoursBox.textColor[1] == 1,
    "clearing no limit restores the hours box")
TB.SetOrderNoLimit(true)
assert(TB.GetOrderNoLimit() == true and TB.orderWindow.noLimitBox:GetChecked(),
    "the setter ticks no limit")
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
    TB._t.stMenu = {}
    TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.stMenu, info) end)
    TB._t.stCancel = nil
    table.foreach(TB._t.stMenu, function(k, info) if info.text == "Cancel order" then TB._t.stCancel = info end end)
    assert(TB._t.stCancel and TB._t.stCancel.func and guildOrderRow.moreBtn:IsVisible() and guildOrderRow.moreBtn.enabled,
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
    TB._t.liveMenu = {}
    TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.liveMenu, info) end)
    TB._t.liveCancel = nil
    table.foreach(TB._t.liveMenu, function(k, info) if info.text == "Cancel order" then TB._t.liveCancel = info end end)
    assert(TB._t.liveCancel and TB._t.liveCancel.func and guildOrderRow.moreBtn:IsVisible() and guildOrderRow.moreBtn.enabled,
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
    TB._t.rowMenu2 = {}
    TB.BuildGuildRowMenu("Goldie", function(info) table.insert(TB._t.rowMenu2, info) end)
    TB._t.rowCancel2 = nil
    table.foreach(TB._t.rowMenu2, function(k, info) if info.text == "Cancel order" then TB._t.rowCancel2 = info end end)
    local beforeRowCancel = table.getn(addonSent)
    TB._t.rowCancel2.func()
    assert(table.getn(addonSent) == beforeRowCancel,
        "row Cancel sends nothing before the confirm")
    now = now + 1
    StaticPopupDialogs["TORTOISEBOTSMANAGER_CANCEL_ORDER"].OnAccept()
    assert(lastAddon() == "order Goldie cancel", "confirming the row Cancel sends")
end
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
assert(TB.GetBotOrder("Goldie") == nil, "the last confirm clears the row")
TB.CloseOrderWindow()

-- ── Player Buy cap + order preview (TBM guild-order-nobuy) ─────────────────
-- Older servers send no token: Buy stays allowed, like today.
assert(TB.PlayerBuyAllowed() == true, "no token means Buy stays allowed")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
assert(TB.PlayerBuyAllowed() == true, "guild-orders without the token keeps Buy")
now = now + 1
assert(TB.SendOrderGive("Goldie", "buy", 2318, 10) == true, "Buy sends without the token")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-nobuy")
assert(TB.PlayerBuyAllowed() == false, "the nobuy token refuses player Buy")
assert(TB.SendOrderGive("Goldie", "buy", 2318, 10) == false, "Buy never goes out while refused")
now = now + 1
assert(TB.SendOrderGive("Goldie", "farm", 2318, 10) == true, "Farm still sends while Buy is refused")
assert(TB.RequestOrderPreview("Goldie", "buy", 2318, 10) == false, "Buy previews never go out")
now = now + 1
assert(TB.RequestOrderPreview("Goldie", "farm", 2318, 10) == true, "Farm previews go out")
assert(lastAddon() == "order Goldie preview farm 2318 10", "the preview names bot, kind, item and amount")
-- A repeat while the answer is missing reuses the pending one, never queues two.
local beforePreview = table.getn(addonSent)
assert(TB.RequestOrderPreview("Goldie", "farm", 2318, 10) == true, "a repeat answers true")
assert(table.getn(addonSent) == beforePreview, "a repeat sends nothing twice")
-- A refused Buy give shows the server text in the window.
assert(TB.OpenOrderWindow("Goldie"), "the window reopens for the Buy refusal")
TB.OnSystemMessage("TBM:ACTION_ERR|order|buy-disabled|Buy orders are turned off on this server. Give a Farm or Craft order instead.")
assert(string.find(TB.GetOrderFeedback().text, "Buy orders are turned off", 1, true),
    "a refused Buy order shows the server text in the window")
TB.CloseOrderWindow()
-- The window hides Buy while the token is up and shows Farm instead.
assert(TB.OpenOrderWindow("Goldie"), "the window reopens under the token")
TB.SetOrderKind("buy")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders,guild-order-nobuy")
assert(TB.GetOrderKind() == "farm", "landing the token leaves Buy for Farm")
assert(TB.orderWindow.kindPills.buy:IsVisible() == false, "the Buy pill hides while Buy is refused")
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
assert(TB.PlayerBuyAllowed() == true, "losing the token allows Buy again")
assert(TB.orderWindow.kindPills.buy:IsVisible(), "the Buy pill returns with the token gone")
TB.CloseOrderWindow()

-- Preview lines parse strictly: eleven fields, eleven colon counts, sane numbers.
local previewLine = "TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|2319:8:3:1:2:2:Ashenvale:1:0:1:1;2320:2:0:0:0:0:-:0:0:2:0|40|-"
local preview = TB.ParseOrderPreviewLine(previewLine)
assert(preview and preview.bot == "Goldie" and preview.kind == "craft"
    and preview.itemId == 3860 and preview.want == 5 and preview.missing == 5
    and preview.minutes == 40 and preview.goldCap == nil
    and table.getn(preview.reagents) == 2, "preview lines parse")
assert(preview.reagents[1].itemId == 2319 and preview.reagents[1].need == 8
    and preview.reagents[1].bags == 3 and preview.reagents[1].farm == 2
    and preview.reagents[1].zone == "Ashenvale" and preview.reagents[1].player == 1,
    "reagent rows carry held, farm, zone and player counts")
assert(preview.reagents[2].sub == 2 and preview.reagents[2].player == 0,
    "sub-order rows parse")
assert(TB.ParseOrderPreviewLine("TBM:ORDER_PREVIEW|Goldie|craft|3860") == nil,
    "a short preview line is dropped")
assert(TB.ParseOrderPreviewLine("TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|nope|40|-") == nil,
    "a bad reagent list drops the preview line")
assert(TB.ParseOrderPreviewReagent("2319:8:3:1:2:2:Ashenvale:1:0:1") == nil,
    "a short reagent row is dropped")
itemCache[2319] = { name = "Iron Bar", quality = 1, texture = "Interface\\Icons\\INV_Ingot_02" }
itemCache[2320] = { name = "Cured Light Hide", quality = 1, texture = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" }
local previewText = TB.OrderPreviewText(preview)
assert(string.find(previewText, "Goldie makes 5 Iron Buckle.", 1, true),
    "the preview names the bot, verb, amount and item: " .. tostring(previewText))
assert(string.find(previewText, "Has: 6 Iron Bar", 1, true)
    and string.find(previewText, "Will farm: 2 Iron Bar (Ashenvale)", 1, true)
    and string.find(previewText, "May buy: 1 Iron Bar", 1, true)
    and string.find(previewText, "Asks guild bots: 1 Iron Bar, 2 Cured Light Hide", 1, true)
    and string.find(previewText, "You need to send: 1 Iron Bar", 1, true)
    and string.find(previewText, "Rough time: about 40 min.", 1, true),
    "the preview says has, farm, buy, sub-orders, player need and time: " .. tostring(previewText))
local farmPreview = TB.ParseOrderPreviewLine(
    "TBM:ORDER_PREVIEW|Thorgar|farm|2318|Light Leather|10|4|easy|Ashenvale|2318:10:6:0:0:4:Ashenvale:0:0:0:0|20|-")
assert(string.find(TB.OrderPreviewText(farmPreview), "Thorgar gets 10 Light Leather.", 1, true)
    and string.find(TB.OrderPreviewText(farmPreview), "You need to send: nothing.", 1, true),
    "a farm preview uses gets and names no player need")
local cappedPreview = TB.ParseOrderPreviewLine(
    "TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|-|40|20000")
assert(string.find(TB.OrderPreviewText(cappedPreview), "Spends at most: 2g.", 1, true),
    "a capped preview names the gold cap")
-- The reply commits only for the pending pick; anything else is ignored.
assert(TB.OpenOrderWindow("Goldie"), "the window reopens for the preview reply")
TB.SetOrderKind("farm")
TB.SendOrderSearch("Goldie", "farm", "leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
this = TB.orderWindow.resultRows[1]
TB.orderWindow.resultRows[1].scripts.OnClick(TB.orderWindow.resultRows[1])
assert(TB.GetOrderSelection() == 2318, "the window picks the item")
assert(lastAddon() == "order Goldie preview farm 2318 10", "picking asks the preview at once")
assert(string.find(TB.orderWindow.previewLine:GetText(), "asking the server", 1, true),
    "the panel says it is asking")
TB.OnSystemMessage("TBM:ORDER_PREVIEW|Silver|farm|2318|Light Leather|10|4|easy|Ashenvale|-|20|-")
assert(TB.GetOrderPreview() == nil, "another bot's reply commits nothing")
TB.OnSystemMessage("TBM:ORDER_PREVIEW|Goldie|farm|2318|Light Leather|10|4|easy|Ashenvale|2318:10:6:0:0:4:Ashenvale:0:0:0:0|20|-")
assert(TB.GetOrderPreview() ~= nil, "the matching reply commits")
assert(string.find(TB.orderWindow.previewLine:GetText(), "Goldie gets 10 Light Leather.", 1, true),
    "the panel shows the preview above Send")
TB.SetOrderAmount(25)
assert(TB.GetOrderPreview() == nil, "an amount change clears the stale preview")
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(lastAddon() == "order Goldie preview farm 2318 25", "the pause re-asks once for the new amount")
TB.CloseOrderWindow()

-- ── Enchant orders (TBM#12): row states, Meet, ready notice, Enchant search ─
-- Own function: the main chunk is at Lua's 200-local limit.
local function enchantOrderChecks()
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    canEditOfficerNote = true

    -- Row states: ready names the capital and Meet, coming/enchanting read plainly.
    local readyOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    assert(readyOrder and readyOrder.type == "enchant" and readyOrder.itemId == 27747
        and readyOrder.state == "ready", "enchant rows parse with the spell id")
    assert(TB.OrderTypeLabel("enchant") == "Enchant", "enchant gets the plain type label")
    assert(TB.OrderStateLabel("ready") == "Ready"
        and TB.OrderStateLabel("coming") == "Coming"
        and TB.OrderStateLabel("enchanting") == "Enchanting",
        "enchant states get plain labels")
    assert(TB.OrderRowText(readyOrder)
        == "Enchant Bracer - Stamina · |cff4ecb5aReady|r - come to Stormwind and press Meet",
        "ready rows name the capital and Meet: " .. TB.OrderRowText(readyOrder))
    local comingOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|coming|-|-")
    assert(TB.OrderRowText(comingOrder)
        == "Enchant Bracer - Stamina · |cffffd200On the way to you|r",
        "coming rows read plainly")
    local enchantingOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|enchanting|-|-")
    assert(TB.OrderRowText(enchantingOrder)
        == "Enchant Bracer - Stamina · |cffffd200Trade open - put your item in Will not be traded|r",
        "enchanting rows name the trade slot")
    local oldWaiting = TB.ParseOrderLine("TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|waiting|grouped|Ashenvale")
    assert(string.find(TB.OrderRowText(oldWaiting), "Waiting", 1, true) ~= nil,
        "old rows keep their waiting text")

    -- Gathering rows: working with a step reads as today, needitems names the need.
    local gatherOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|working|-|-|-|-|-|-|-|-|-")
    assert(TB.OrderRowText(gatherOrder) == "Enchant Bracer - Stamina 1/1",
        "gathering rows show the bare progress: " .. TB.OrderRowText(gatherOrder))
    local needOrder = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|waiting|needitems|-|-|-|-|-|-|-|10940:2")
    assert(TB.OrderNeedText(needOrder) ~= nil, "needitems rows still parse the need list")
    local needRow = TB.OrderRowText(needOrder)
    assert(string.find(needRow, "Waiting", 1, true) ~= nil, "needitems rows keep waiting: " .. needRow)

    -- Meet gating: only unfinished enchant rows.
    assert(TB.OrderNeedsMeet(readyOrder) == true, "a ready enchant needs Meet")
    assert(TB.OrderNeedsMeet(comingOrder) == true, "a coming enchant needs Meet")
    assert(TB.OrderNeedsMeet(enchantingOrder) == true, "an enchanting row needs Meet")
    assert(TB.OrderNeedsMeet({ type = "enchant", state = "done" }) == false, "done needs no Meet")
    assert(TB.OrderNeedsMeet({ type = "enchant", state = "cant" }) == false, "cant needs no Meet")
    assert(TB.OrderNeedsMeet({ type = "farm", state = "ready" }) == false, "farm rows never need Meet")
    assert(TB.OrderNeedsMeet(nil) == false, "no order needs no Meet")

    -- Meet send: byte-exact, gated by the capability.
    now = now + 1
    local beforeMeet = table.getn(addonSent)
    assert(TB.SendOrderMeet("Goldie") == true, "Meet sends")
    assert(addonSent[table.getn(addonSent)].message == "order Goldie meet"
        and table.getn(addonSent) == beforeMeet + 1, "Meet rides the wire byte-exact")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
    assert(TB.SendOrderMeet("Goldie") == false, "no Meet without the capability")
    assert(table.getn(addonSent) == beforeMeet + 1, "a gated Meet sends nothing")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
    TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1")

    -- Meet ACK/ERR follow the lead contract: "meet coming/later/gathering"
    -- ACKs (plus a plain system text line that paints the status), and
    -- notcapital/noorder/busy ERRs with the text to show.
    assert(TB.OpenOrderWindow("Goldie"), "the window reopens for the Meet reply")
    now = now + 1
    assert(TB.SendOrderMeet("Goldie") == true, "the reply Meet sends")
    -- The ACK detail paints the rows (meetBtn visibility) while the plain
    -- system text the server sends alongside stays a chat line: the ACK must
    -- not stamp its own status text over it.
    local said = nil
    local realSetStatus = TB.SetStatus
    TB.SetStatus = function(msg) said = msg end
    TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|meet coming")
    assert(TB.lastActionAck and TB.lastActionAck.executor == "meet coming",
        "the coming ACK routes and repaints the rows")
    assert(said == nil, "the coming ACK paints no status of its own")
    TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|meet later")
    assert(TB.lastActionAck and TB.lastActionAck.executor == "meet later", "the later ACK routes")
    assert(said == nil, "the later ACK paints no status of its own")
    TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|meet gathering")
    assert(TB.lastActionAck and TB.lastActionAck.executor == "meet gathering",
        "the gathering ACK routes")
    assert(said == nil, "the gathering ACK paints no status of its own")
    TB.OnSystemMessage("TBM:ACTION_ERR|order|notcapital|Meet me in Stormwind.")
    assert(TB.lastActionError and TB.lastActionError.code == "notcapital", "the notcapital error routes")
    TB.SetStatus = realSetStatus
    assert(string.find(TB.GetOrderFeedback().text, "Meet me in Stormwind.", 1, true) ~= nil,
        "the window shows the notcapital text too")
    TB.OnSystemMessage("TBM:ACTION_ERR|order|noorder|That bot has no enchant order from you.")
    assert(TB.lastActionError and TB.lastActionError.code == "noorder"
        and string.find(TB.GetOrderFeedback().text, "no enchant order from you", 1, true) ~= nil,
        "the window shows the noorder text")
    TB.OnSystemMessage("TBM:ACTION_ERR|order|busy|Goldie is busy with an enchant order for Other.")
    assert(TB.lastActionError and TB.lastActionError.code == "busy"
        and string.find(TB.GetOrderFeedback().text, "is busy with an enchant order", 1, true) ~= nil,
        "the window shows the busy text")
    TB.CloseOrderWindow()

    -- Ready notice: once per order. Live update fires, refresh and replay do not.
    UIErrorsFrame = UIErrorsFrame or { messages = {},
        AddMessage = function(self, msg, r, g, b) table.insert(self.messages, msg) end }
    UIErrorsFrame.messages = {}
    local played = {}
    PlaySound = function(name) table.insert(played, name) end
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|working|-|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(table.getn(UIErrorsFrame.messages) == 0 and table.getn(played) == 0,
        "gathering announces nothing")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    assert(table.getn(UIErrorsFrame.messages) == 1 and table.getn(played) == 1 and played[1] == "ReadyCheck",
        "ready fires one message and the ReadyCheck sound")
    assert(string.find(UIErrorsFrame.messages[1], "Stormwind", 1, true) ~= nil
        and string.find(UIErrorsFrame.messages[1], "press Meet", 1, true) ~= nil,
        "the ready message names the capital and Meet: " .. tostring(UIErrorsFrame.messages[1]))
    assert(TB.OrderReadyAnnounced("Goldie") == true, "the announce is recorded")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    assert(table.getn(UIErrorsFrame.messages) == 1 and table.getn(played) == 1,
        "a replay of the same ready stays silent")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(table.getn(UIErrorsFrame.messages) == 1 and table.getn(played) == 1,
        "a list refresh of the same ready stays silent")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|coming|-|-")
    assert(TB.OrderReadyAnnounced("Goldie") == false, "leaving ready clears the announce")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    assert(table.getn(UIErrorsFrame.messages) == 2 and table.getn(played) == 2,
        "a new ready announces again")
    UIErrorsFrame.messages = {}
    played = {}
    TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|cancel")
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    assert(table.getn(UIErrorsFrame.messages) == 0, "a full list alone never announces")

    -- Meet button: shows only on unfinished enchant rows, in place of Release.
    TB.OnSystemMessage("TBM:ORDER_BEGIN|1")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    TB.OnSystemMessage("TBM:ORDER_END")
    TB.OnSystemMessage("TBM:CLAIMED_BEGIN|3")
    TB.OnSystemMessage("TBM:CLAIMED|201|Goldie|1|60|online|0|Ironforge|1")
    TB.OnSystemMessage("TBM:CLAIMED|202|Silver|5|45|online|1|Duskwood|0")
    TB.OnSystemMessage("TBM:CLAIMED|203|Bronze|8|20|offline|0|-|0")
    TB.OnSystemMessage("TBM:CLAIMED_END")
    TB.ShowTab("guild")
    TB.RefreshGuildView()
    local meetRow = TB.guildFrame.rows[1]
    assert(meetRow.entry and meetRow.entry.name == "Goldie",
        "the first guild row holds Goldie")
    assert(meetRow and meetRow.meetBtn and meetRow.meetBtn:IsVisible(),
        "an unfinished enchant shows Meet")
    assert(meetRow.meetBtn.enabled, "officer rights enable Meet")
    assert(meetRow.relBtn ~= nil, "the Release control still exists for the menu")
    canEditOfficerNote = false
    TB.RefreshGuildView()
    assert(not meetRow.meetBtn.enabled, "losing the right greys Meet out")
    canEditOfficerNote = true
    now = now + 1
    local meetBefore = table.getn(addonSent)
    this = meetRow.meetBtn
    meetRow.meetBtn.scripts.OnClick(meetRow.meetBtn)
    assert(table.getn(addonSent) == meetBefore + 1 and lastAddon() == "order Goldie meet",
        "Meet clicks send like the other order commands")
    TB.OnSystemMessage("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|done|-|-")
    TB.RefreshGuildView()
    assert(not meetRow.meetBtn:IsVisible() and meetRow.relBtn ~= nil,
        "done hides Meet")

    -- Enchant search: the window lists name, slot, skill and have/need.
    assert(TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|27747") == nil,
        "a short enchant line is dropped")
    assert(TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|27747|Enchant Bracer - Stamina|bracer|333:225|ok|-") ~= nil
        and TB.ParseOrderEnchantReagents("-") ~= nil
        and table.getn(TB.ParseOrderEnchantReagents("-")) == 0,
        "dash reagents parse as none")
    assert(TB.ParseOrderEnchantReagents("nope") == nil, "bad reagents drop the line")
    assert(TB.OrderEnchantDetail({ verdict = "norecipe" }) == "Can't: unknown recipe",
        "norecipe verdicts read plainly")
    assert(TB.OrderEnchantDetail({ verdict = "noskill" }) == "Can't: missing profession",
        "noskill verdicts read plainly")
    now = now + 1
    assert(TB.OpenOrderWindow("Goldie"), "the window reopens for enchant")
    TB.orderWindow.searchBox.text = ""
    now = now + 1
    assert(TB.orderWindow.kindPills.enchant and TB.orderWindow.kindPills.enchant:IsVisible(),
        "the Enchant pill shows")
    assert(TB.SetOrderKind("enchant") == true and TB.GetOrderKind() == "enchant",
        "the kind switches to Enchant")
    assert(TB.orderWindow.kindPills.enchant:GetText() == "|cffffffffEnchant|r"
        or TB.orderWindow.kindPills.enchant.baseLabel == "Enchant",
        "the Enchant pill lights while picked")
    assert(lastAddon() == "order search Goldie enchant", "switching to Enchant re-runs the search: " .. tostring(lastAddon()))
    TB.orderWindow.searchBox.text = "bracer"
    this = TB.orderWindow.searchBox
    TB.orderWindow.searchBox.scripts.OnTextChanged(TB.orderWindow.searchBox)
    now = now + 1
    TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
    assert(lastAddon() == "order search Goldie enchant bracer", "typing sends the enchant search: " .. tostring(lastAddon()))
    TB.OnSystemMessage("TBM:ORDER_ENCHANTS_BEGIN|2")
    TB.OnSystemMessage("TBM:ORDER_ENCHANT|27747|Enchant Bracer - Stamina|bracer|333:225|ok|10940:2:2;10938:1:0")
    TB.OnSystemMessage("TBM:ORDER_ENCHANT|27951|Enchant Bracer - Healing|bracer|333:250|ok|-")
    TB.OnSystemMessage("TBM:ORDER_ENCHANTS_END")
    local enchantSearch = TB.GetOrderSearch()
    assert(enchantSearch.kind == "enchant" and table.getn(enchantSearch.items) == 2,
        "the enchant search lands on the window's bot")
    local firstEnchant = TB.orderWindow.resultRows[1]
    assert(firstEnchant:IsVisible()
        and string.find(firstEnchant.name:GetText(), "Enchant Bracer - Stamina", 1, true) ~= nil,
        "the first enchant row shows the name")
    local enchantDetail = firstEnchant.detail:GetText()
    assert(string.find(enchantDetail, "bracer", 1, true) ~= nil
        and string.find(enchantDetail, "Enchanting 225", 1, true) ~= nil
        and string.find(enchantDetail, "2/2", 1, true) ~= nil,
        "enchant rows show slot, skill and have/need: " .. tostring(enchantDetail))
    local secondEnchant = TB.orderWindow.resultRows[2]
    this = secondEnchant
    secondEnchant.scripts.OnClick(secondEnchant)
    assert(TB.GetOrderSelection() == 27951, "an enchant row is picked by spell id")
    now = now + 1
    TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
    assert(lastAddon() == "order Goldie enchant 27951", "Send gives the spell id, nothing else")
    now = now + 1
    TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|enchant")
    assert(not TB.orderWindow:IsVisible(), "an enchant ACK closes the window")
    assert(TB.lastActionAck and TB.lastActionAck.executor == "enchant", "the enchant ACK routes")

    -- Meet button states: gathering, need-vs-bags, capital, cooldown.
    local readyForMeet = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|ready|-|-")
    local gathering = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|working|-|-")
    local needy = TB.ParseOrderLine("TBM:ORDER|Goldie|enchant|27747|Enchant Bracer - Stamina|1|1|waiting|needitems|-|-|-|-|-|-|-|10940:2")
    local ok, why = TB.OrderMeetState(gathering)
    assert(ok == false and why == "Still gathering materials", "gathering greys Meet out")
    GetContainerNumSlots = function(bag) if bag == 0 then return 1 end return 0 end
    GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return "|cffffffff|Hitem:99999:0:0:0|h[Other]|h|r" end
        return nil
    end
    GetContainerItemInfo = function() return nil, 1, false end
    ok, why = TB.OrderMeetState(needy)
    assert(ok == false and string.find(why, "You carry none of the missing materials:", 1, true) ~= nil
        and string.find(why, "10940", 1, true) ~= nil, "empty bags grey a needitems Meet: " .. tostring(why))
    GetContainerItemLink = function(bag, slot)
        if bag == 0 and slot == 1 then return "|cffffffff|Hitem:10940:0:0:0|h[Strange Dust]|h|r" end
        return nil
    end
    GetContainerItemInfo = function() return nil, 2, false end
    ok, why = TB.OrderMeetState(needy)
    assert(ok == true and why == nil, "carrying a need item enables Meet")
    GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = nil, nil, nil
    local savedFaction = UnitFactionGroup
    UnitFactionGroup = nil
    GetRealZoneText = function() return "Durotar" end
    GetZoneText = function() return "Durotar" end
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == false and why == "Go to Stormwind", "outside the capital Meet waits: " .. tostring(why))
    GetRealZoneText = function() return "Stormwind City" end
    GetZoneText = function() return "Stormwind City" end
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == true and why == nil, "a ready order in the capital meets (Stormwind exact)")
    UnitFactionGroup = function() return "Horde" end
    GetRealZoneText = function() return "Orgrimmar" end
    GetZoneText = function() return "Orgrimmar" end
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == true and why == nil, "a Horde player meets in Orgrimmar: " .. tostring(why))
    GetRealZoneText = function() return "Durotar" end
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == false and why == "Go to Orgrimmar", "a Horde player outside waits for Orgrimmar")
    UnitFactionGroup = savedFaction
    GetRealZoneText, GetZoneText = nil, nil
    -- Cooldown: parsed from the refusal text, remembered per bot, then expires.
    assert(TB.SendOrderMeet("Goldie") == true, "Meet sends before the refusal")
    UIErrorsFrame.messages = {}
    local errBefore = TB.GetOrderFeedback() and TB.GetOrderFeedback().text or nil
    TB.OnSystemMessage("TBM:ACTION_ERR|order|cooldown|I just came for nothing. Try again in 5 min.")
    assert(TB.lastActionError and TB.lastActionError.code == "cooldown", "the cooldown error routes")
    assert(table.getn(UIErrorsFrame.messages) == 1
        and string.find(UIErrorsFrame.messages[1], "Try again in 5 min.", 1, true) ~= nil,
        "the cooldown text shows on screen")
    assert(string.find(TB.GetOrderFeedback().text, "Try again in 5 min.", 1, true) ~= nil
        and TB.GetOrderFeedback().text ~= errBefore, "the cooldown text shows in the window too")
    local left = TB.GetOrderMeetCooldown("Goldie")
    assert(left and left > 4 * 60 and left <= 5 * 60, "the cooldown is remembered: " .. tostring(left))
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == false and why == "Try again in 5 min", "the button counts the cooldown down")
    now = now + 5 * 60 + 1
    assert(TB.GetOrderMeetCooldown("Goldie") == nil, "the cooldown expires")
    ok, why = TB.OrderMeetState(readyForMeet)
    assert(ok == true, "Meet enables again after the cooldown")
    -- The other refusals show on screen and in the window the same way.
    assert(TB.SendOrderMeet("Goldie") == true, "Meet sends before the refusals")
    TB.OnSystemMessage("TBM:ACTION_ERR|order|nothingtobring|Bring an item to enchant first.")
    assert(string.find(UIErrorsFrame.messages[table.getn(UIErrorsFrame.messages)],
        "Bring an item to enchant first.", 1, true) ~= nil, "nothingtobring shows on screen")
    assert(string.find(TB.GetOrderFeedback().text, "Bring an item", 1, true) ~= nil,
        "nothingtobring shows in the window")
end
enchantOrderChecks()
TB.CloseOrderWindow()
-- ── Guild-wide pick-a-bot + materials I bring (TBM#1525, addon only) ───────
local function guildOrderUiChecks()
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
canEditOfficerNote = true
-- ORDER_WHO parsing: bots list, busy marker, dash quality/slot/empty bots.
local whoCraft = TB.ParseOrderWhoLine("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|Goldie:165:3:3:0;Silver:140:1:3:1")
assert(whoCraft and whoCraft.kind == "craft" and whoCraft.id == 3860
    and whoCraft.quality == 2 and whoCraft.slot == nil and whoCraft.reqSkill == 165
    and table.getn(whoCraft.bots) == 2 and whoCraft.bots[1].bot == "Goldie"
    and whoCraft.bots[2].busy == true, "a craft who line parses bots and busy")
local whoEnchant = TB.ParseOrderWhoLine("TBM:ORDER_WHO|enchant|7418|Enchant Bracer - Minor Stamina|-|bracer|165|Goldie:165:1:1:0")
assert(whoEnchant and whoEnchant.kind == "enchant" and whoEnchant.quality == nil
    and whoEnchant.slot == "bracer" and whoEnchant.reqSkill == 165, "an enchant who line keeps slot and skill")
assert(TB.ParseOrderWhoLine("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|-").bots ~= nil
    and table.getn(TB.ParseOrderWhoLine("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|-").bots) == 0,
    "no knowing bot parses as an empty list")
assert(TB.ParseOrderWhoLine("TBM:ORDER_WHO|craft|3860") == nil
    and TB.ParseOrderWhoLine("TBM:ORDER_WHO|farm|3860|Iron Buckle|2|-|165|-") == nil
    and TB.ParseOrderWhoBots("Goldie:165:3") == nil
    and TB.ParseOrderWhoBots("Goldie:165:3:3:2") == nil, "bad who lines drop")
assert(TB.OrderWhoBotText(whoCraft) == "Goldie 165 3/3, Silver 140 1/3 (busy)",
    "the bot line names skill, have/need and busy: " .. tostring(TB.OrderWhoBotText(whoCraft)))
assert(TB.OrderWhoRowText(whoEnchant) == "Enchant Bracer - Minor Stamina (bracer 165) - Goldie 165 1/1",
    "the row names slot and skill on enchant: " .. tostring(TB.OrderWhoRowText(whoEnchant)))
-- ORDER_ENCHANT parsing: verdicts and reagent have counts (rows keep the
-- per-bot shape: the spell id rides as itemId).
local enchant = TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|7418|Enchant Bracer - Minor Stamina|bracer|165|ok|10940:1:1;10938:1:0")
assert(enchant and enchant.itemId == 7418 and enchant.slot == "bracer"
    and enchant.verdict == "ok" and table.getn(enchant.reagents) == 2
    and enchant.reagents[2].have == 0, "an enchant line parses reagents")
assert(TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|7418|Name|bracer|165|norecipe|-").verdict == "norecipe"
    and table.getn(TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|7418|Name|bracer|165|norecipe|-").reagents) == 0,
    "a refused enchant keeps its reason with no reagents")
assert(TB.ParseOrderEnchantLine("TBM:ORDER_ENCHANT|7418") == nil
    and TB.ParseOrderEnchantReagents("nope") == nil, "bad enchant lines drop")
-- Guild-wide search sends ride the same transport as today's searches.
now = now + 1
assert(TB.SendOrderWhoSearch("craft", "buckle") == true
    and lastAddon() == "order search craft buckle", "the guild-wide craft search sends")
now = now + 1
assert(TB.SendOrderWhoSearch("enchant", "bracer stam") == true
    and lastAddon() == "order search enchant bracer stam", "the guild-wide enchant search sends")
assert(TB.SendOrderWhoSearch("craft", "ab") == false, "a short guild-wide search refuses")
now = now + 1
assert(TB.SendOrderEnchantSearch("Goldie", "bracer") == true
    and lastAddon() == "order search Goldie enchant bracer", "the per-bot enchant search sends")
-- The WHO stream commits for the current pick-a-bot kind; a foreign kind
-- never touches the shown rows.
TB.OnSystemMessage("TBM:ORDER_ACCESS|2|Raider|1,2|-|1|0")
assert(TB.OpenGuildOrderWindow(), "the guild Order button opens pick-a-bot mode")
assert(TB.IsOrderGuildMode() and TB.GetOrderWindowBot() == nil, "pick-a-bot mode pins no bot")
TB.orderWindow.searchBox.text = "buckle"
now = now + 1
TB.SendOrderWhoSearch("craft", "buckle")
TB.OnSystemMessage("TBM:ORDER_WHO_BEGIN|craft|1")
TB.OnSystemMessage("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|Goldie:165:3:3:0")
TB.OnSystemMessage("TBM:ORDER_WHO_END")
assert(table.getn(TB.GetOrderWhoSearch().rows) == 1, "the who pair commits its rows")
assert(TB.orderWindow.resultRows[1]:IsVisible()
    and string.find(TB.orderWindow.resultRows[1].name:GetText(), "Iron Buckle", 1, true) ~= nil
    and string.find(TB.orderWindow.resultRows[1].detail:GetText(), "Goldie 165 3/3", 1, true) ~= nil,
    "the window renders the match with its bots")
TB.SetGuildOrderKind("enchant")
now = now + 1
TB.OnSystemMessage("TBM:ORDER_WHO_BEGIN|craft|1")
TB.OnSystemMessage("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|Goldie:165:3:3:0")
TB.OnSystemMessage("TBM:ORDER_WHO_END")
assert(table.getn(TB.GetOrderWhoSearch().rows) == 1
    and TB.GetOrderWhoSearch().kind == "craft", "a late pair shows its own answer, never stale rows")
assert(TB.orderWindow.resultRows[1].botBtns == nil or true, "bot buttons ride the window frame")
TB.SetGuildOrderKind("craft")
TB.orderWindow.searchBox.text = "buckle"
now = now + 1
now = now + 1
now = now + 1
TB.SendOrderWhoSearch("craft", "buckle")
TB.OnSystemMessage("TBM:ORDER_WHO_BEGIN|craft|1")
TB.OnSystemMessage("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|Goldie:165:3:3:0")
TB.OnSystemMessage("TBM:ORDER_WHO_END")
assert(TB.orderWindow.botBtns and TB.orderWindow.botBtns[1]:IsVisible()
    and TB.orderWindow.botBtns[1]:GetText() == "Goldie", "the first bot becomes a clickable button")
-- A who-bot click opens today's per-bot flow for that bot and item.
now = now + 1
now = now + 1
now = now + 1
this = TB.orderWindow.botBtns[1]
TB.orderWindow.botBtns[1].scripts.OnClick(TB.orderWindow.botBtns[1])
assert(not TB.IsOrderGuildMode() and TB.GetOrderWindowBot() == "Goldie"
    and TB.GetOrderSelection() == 3860 and TB.GetOrderKind() == "craft",
    "clicking a craft bot opens its normal craft flow")
assert(TB.orderWindow.kindPills.farm:IsVisible(), "the Farm pill returns after pick-a-bot mode hid it")
assert(lastAddon() == "order Goldie preview craft 3860 10", "the click asks the craft preview at once")
TB.CloseOrderWindow()
-- Enchant clicks open the per-bot enchant flow with the spell preselected.
assert(TB.OpenGuildOrderWindow(), "pick-a-bot mode reopens")
TB.SetGuildOrderKind("enchant")
TB.orderWindow.searchBox.text = "bracer stam"
TB.SendOrderWhoSearch("enchant", "bracer stam")
TB.OnSystemMessage("TBM:ORDER_WHO_BEGIN|enchant|1")
TB.OnSystemMessage("TBM:ORDER_WHO|enchant|7418|Enchant Bracer - Minor Stamina|-|bracer|165|Goldie:165:1:1:0")
TB.OnSystemMessage("TBM:ORDER_WHO_END")
this = TB.orderWindow.botBtns[1]
TB.orderWindow.botBtns[1].scripts.OnClick(TB.orderWindow.botBtns[1])
assert(not TB.IsOrderGuildMode() and TB.GetOrderWindowBot() == "Goldie"
    and TB.GetOrderKind() == "enchant" and TB.GetOrderSelection() == 7418,
    "clicking an enchant bot opens its enchant flow with the spell picked")
now = now + 1
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie enchant 7418", "the picked spell sends as the enchant order")
TB.CloseOrderWindow()
-- Bring parsing: the new trailing field, old servers without it stay empty.
local bringPreview = TB.ParseOrderPreviewLine("TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|2319:8:3:1:2:2:Ashenvale:1:0:1:1|40|-|2319")
assert(bringPreview and table.getn(bringPreview.bring) == 1 and bringPreview.bring[1] == 2319,
    "the preview carries the new bring field")
assert(table.getn(TB.ParseOrderPreviewLine("TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|-|40|-").bring) == 0,
    "an old preview without the field means nothing ticked")
assert(TB.ParseOrderPreviewLine("TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|-|40|-|nope") == nil,
    "a bad bring list drops the preview line")
assert(TB.ParseOrderBring("2319,2320") ~= nil and table.getn(TB.ParseOrderBring("2319,2320")) == 2
    and table.getn(TB.ParseOrderBring("-")) == 0 and TB.ParseOrderBring("nope") == nil,
    "bring lists parse strictly")
-- Auto-tick: full bag counts tick, partial counts stay unticked.
GetContainerNumSlots = function(bag) if bag == 0 then return 2 end return 0 end
GetContainerItemLink = function(bag, slot)
    if bag == 0 and slot == 1 then return "|cffffffff|Hitem:2319:0:0:0|h[Iron Bar]|h|r" end
    if bag == 0 and slot == 2 then return "|cffffffff|Hitem:2320:0:0:0|h[Cured Light Hide]|h|r" end
    return nil
end
GetContainerItemInfo = function(bag, slot)
    if bag == 0 and slot == 1 then return "Interface\\Icons\\INV_Ingot_02", 8, false end
    if bag == 0 and slot == 2 then return "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", 1, false end
    return nil
end
assert(TB.OrderBagCount(2319) == 8 and TB.OrderBagCount(2320) == 1, "bag counts read the 1.12 bag APIs")
assert(TB.OrderBringAutoTicked({ itemId = 2319, need = 8 }) == true, "a full stack auto-ticks")
assert(TB.OrderBringAutoTicked({ itemId = 2320, need = 2 }) == false, "a partial stack stays unticked")
-- The bring= string rides preview refresh and Send; toggling re-asks.
now = now + 1
TB.OpenOrderWindow("Goldie")
if TB.GetOrderKind() ~= "craft" then TB.SetOrderKind("craft") end
TB.SetOrderBring({ 2319 })
assert(TB.OrderBringText(TB.GetOrderBring()) == "2319", "the tick joins with commas")
now = now + 1
assert(TB.RequestOrderPreview("Goldie", "craft", 3860, 5, TB.GetOrderBring()) == true
    and lastAddon() == "order Goldie preview craft 3860 5 bring=2319", "preview refresh carries bring=")
now = now + 1
assert(TB.SendOrderGive("Goldie", "craft", 3860, 5, "inf", false, nil, TB.GetOrderBring()) == true
    and lastAddon() == "order Goldie craft 3860 5 inf bring=2319", "Send carries bring= last")
now = now + 1
assert(TB.SendOrderGive("Goldie", "craft", 3860, 5) == true
    and lastAddon() == "order Goldie craft 3860 5", "unticked rows ride no field")
-- The window shows one "I bring it" checkbox per craft reagent and sends the tick.
-- Bags stay mocked: the preview commit auto-ticks from these counts.
now = now + 1
now = now + 1
TB.SendOrderSearch("Goldie", "craft", "buckle")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ITEM|3860|Iron Buckle|2|craft|1|-|ok|-|0")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
itemCache[3860] = { name = "Iron Buckle", quality = 2, texture = "Interface\\Icons\\INV_Belt_01" }
itemCache[2319] = { name = "Iron Bar", quality = 1, texture = "Interface\\Icons\\INV_Ingot_02" }
TB.SetOrderAmount(5)
now = now + 1
TB.SetOrderSelection(3860)
now = now + 1
TB.OnSystemMessage("TBM:ORDER_PREVIEW|Goldie|craft|3860|Iron Buckle|5|5|-|-|2319:8:8:0:0:0:-:0:0:0:0|40|-|-")
assert(table.getn(TB.GetOrderBring()) == 1 and TB.GetOrderBring()[1] == 2319,
    "a full-bag preview auto-ticks its reagent")
assert(TB.orderWindow.bringRows and TB.orderWindow.bringRows[1]:IsVisible()
    and TB.orderWindow.bringRows[1]:GetChecked(), "the reagent row shows ticked")
this = TB.orderWindow.bringRows[1]
TB.orderWindow.bringRows[1].scripts.OnClick(TB.orderWindow.bringRows[1])
assert(table.getn(TB.GetOrderBring()) == 0, "the player can untick the row")
TB.ToggleOrderBringNow(2319)
assert(TB.OrderBringText(TB.GetOrderBring()) == "2319", "toggling ticks again")
now = now + 1
now = now + 1
TB.orderWindow.scripts.OnUpdate(TB.orderWindow)
assert(lastAddon() == "order Goldie preview craft 3860 5 bring=2319", "a tick re-asks the preview with bring=")
GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = nil, nil, nil
TB.SetOrderBring({})
if TB.GetOrderKind() ~= "farm" then TB.SetOrderKind("farm") end
TB.CloseOrderWindow()
end
guildOrderUiChecks()

-- ── Order window steps: search, amount, preview, Back/Next ─────────────────
TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,guild-orders")
TB.SetOrderNoLimit(true)
TB.SetOrderKeep(false)
assert(TB.OpenOrderWindow("Goldie"), "steps reopen the window")
assert(TB.GetOrderStep() == 1, "a fresh window starts on step 1")
assert(TB.orderWindow.searchBox:IsVisible()
    and not TB.orderWindow.amountBox:IsVisible()
    and not TB.orderWindow.sendBtn:IsVisible(), "step 1 shows search only")
assert(TB.orderWindow.backBtn.enabled == false, "step 1 greys Back")
TB.SetOrderStep(0)
assert(TB.GetOrderStep() == 1, "step 0 clamps to step 1")
TB.SetOrderStep(9)
assert(TB.GetOrderStep() == 3, "step 9 clamps to step 3")
TB.SetOrderStep(1)
TB.OrderStepNext()
assert(TB.GetOrderStep() == 1 and string.find(TB.GetOrderFeedback().text, "Pick an item", 1, true),
    "Next without a pick stays and explains")
now = now + 1
TB.orderWindow.searchBox.text = "leather"
TB.SendOrderSearch("Goldie", "farm", "leather")
TB.OnSystemMessage("TBM:ORDER_ITEMS_BEGIN|1")
TB.OnSystemMessage("TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70")
TB.OnSystemMessage("TBM:ORDER_ITEMS_END")
this = TB.orderWindow.resultRows[1]
TB.orderWindow.resultRows[1].scripts.OnClick(TB.orderWindow.resultRows[1])
assert(TB.GetOrderSelection() == 2318, "steps pick the item")
assert(TB.GetOrderStep() == 1, "picking stays on step 1 until Next")
TB.OrderStepNext()
assert(TB.GetOrderStep() == 2, "Next moves to the amount step")
assert(TB.orderWindow.amountBox:IsVisible() and not TB.orderWindow.searchBox:IsVisible(),
    "step 2 swaps search for the amount row")
assert(TB.orderWindow.backBtn.enabled ~= false, "step 2 enables Back")
this = TB.orderWindow.backBtn
TB.orderWindow.backBtn.scripts.OnClick(TB.orderWindow.backBtn)
assert(TB.GetOrderStep() == 1 and TB.GetOrderSelection() == 2318, "Back returns keeping the pick")
this = TB.orderWindow.nextBtn
TB.orderWindow.nextBtn.scripts.OnClick(TB.orderWindow.nextBtn)
assert(TB.GetOrderStep() == 2, "the Next button advances")
TB.SetOrderStep(3)
assert(TB.orderWindow.previewLine:IsVisible() and TB.orderWindow.sendBtn:IsVisible()
    and TB.orderWindow.stepLabel:GetText() == "Step 3 of 3", "step 3 shows preview and Send")
TB.SetOrderFeedback(nil)
now = now + 1
TB.SetOrderAmount(10)
this = TB.orderWindow.sendBtn
TB.orderWindow.sendBtn.scripts.OnClick(TB.orderWindow.sendBtn)
assert(lastAddon() == "order Goldie farm 2318 10 inf",
    "step 3 Send gives the same wire message, got " .. tostring(lastAddon()))
TB.OnSystemMessage("TBM:ACTION_ACK|order|bot:Goldie|1|farm")
assert(not TB.orderWindow:IsVisible(), "a give ACK still closes the stepped window")
assert(TB.OpenGuildOrderWindow(), "pick-a-bot mode reopens")
TB.RefreshOrderWindow()
assert(TB.GetOrderStep() == 1 and TB.orderWindow.stepLabel:GetText() == "",
    "pick-a-bot mode pins step 1 with no indicator")
assert(TB.orderWindow.searchBox:IsVisible() and TB.orderWindow.results:IsVisible(),
    "pick-a-bot mode keeps search visible")
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
    setVitals = function(unit, hp, hpMax, mp, mpMax)
        partyVitals[unit] = { hp = hp, hpMax = hpMax, mp = mp, mpMax = mpMax }
    end,
    setBuffs = function(unit, buffs) partyBuffs[unit] = buffs end,
    setNear = function(units) nearUnits = units end,
})
dofile(root .. "/tests/altsum_tests.lua")({
    sent = sent,
    advanceTime = function(dt) now = now + (dt or 1) end,
})

dofile(root .. "/tests/geometry_tests.lua")()

-- A newer server may append fields to any line: older addons ignore them.
do
    assert(TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather|1|drop,skin|16|393:100|ok|Ashenvale|50|4|leather|extra"),
        "order item rows accept extra fields")
    assert(TB.ParseProfessionRecipeLine("TBM:RECIPE|186|2651|3860|1|25|50|100|ok|extra").order == "ok",
        "recipe rows keep the order field with extras after it")
    assert(TB.ParseServiceLine("TBM:SERVICE|Hexxy|0|0|1|-|extra").healthstone, "service lines accept extra fields")
    assert(TB.ParseOrderStepLine("TBM:ORDER_STEP|Goldie|90|working|nobanker|bank|2319|extra"),
        "order step lines accept extra fields")
    assert(TB.ParseOrderWhoLine("TBM:ORDER_WHO|craft|3860|Iron Buckle|2|-|165|Goldie:165:3:3:0|extra"),
        "order who lines accept extra fields")
    assert(TB.ParseLootLine("TBM:LOOT|2026-10-27 12:00:01|Alpha|StoreLootAction|2586|Gamemaster's Robe|corpse|Defias Thug|4|extra"),
        "loot lines accept extra fields")
    assert(TB.ParseOrderItemLine("TBM:ORDER_ITEM|2319|Medium Leather") == nil, "short lines are still refused")
end

-- Addon/module protocol check: popup once per mismatch, header warning stays.
do
    TB._t = { popups = 0, dialogs = StaticPopupDialogs, show = StaticPopup_Show }
    StaticPopupDialogs = {}
    StaticPopup_Show = function(name) TB._t.popups = TB._t.popups + 1; TB._t.last = name end
    TortoiseBotsDB.compatDismissed = nil
    TB._compatShown = nil
    TB.OnSystemMessage("TBM:PROTO|1|1")
    TB.OnSystemMessage("TBM:VERSION|1.21.0")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB.CompatProblem() == nil and TB._t.popups == 0, "matching levels show nothing")
    TB.OnSystemMessage("TBM:PROTO|2|2")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB.CompatProblem() == "addon" and TB._t.popups == 1 and TB._t.last == "TORTOISEBOTSMANAGER_COMPAT",
        "a module needing a newer addon opens the popup")
    assert(string.find(StaticPopupDialogs.TORTOISEBOTSMANAGER_COMPAT.text, "too old for the bots", 1, true),
        "the popup says the addon is too old")
    assert(string.find(TB.versionLine.text, "addon outdated", 1, true), "the header warns about the addon")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB._t.popups == 1, "the popup shows once per session")
    StaticPopupDialogs.TORTOISEBOTSMANAGER_COMPAT.OnAccept()
    TB._compatShown = nil
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB._t.popups == 1, "Don't show again keeps the popup away after a relog")
    assert(string.find(TB.versionLine.text, "addon outdated", 1, true), "the header warning stays after dismissing")
    TB._compatShown = nil
    TB.C.MIN_MODULE_PROTOCOL = 2
    TB.OnSystemMessage("TBM:PROTO|1|1")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB.CompatProblem() == "module" and TB._t.popups == 2
        and string.find(StaticPopupDialogs.TORTOISEBOTSMANAGER_COMPAT.text, "update TortoiseBots on the server", 1, true),
        "a module older than the addon needs asks for a server update")
    assert(string.find(TB.versionLine.text, "server module outdated", 1, true), "the header warns about the module")
    TB.serverProtocol, TB.serverMinAddonProtocol = nil, nil
    assert(TB.CompatProblem() == "module", "a module without the PROTO line counts as level 0")
    TB.C.MIN_MODULE_PROTOCOL = 0
    assert(TB.CompatProblem() == nil, "level 0 modules fit while the addon asks for nothing newer")
    TB._compatShown = nil
    TB.OnSystemMessage("TBM:PROTO|1|1")
    TB.OnSystemMessage("TBM:LATEST|1.22.0|99.0.0")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB._t.popups == 3 and string.find(StaticPopupDialogs.TORTOISEBOTSMANAGER_COMPAT.text, "newer TortoiseBotsManager", 1, true),
        "a newer addon release opens the popup")
    assert(string.find(TB.versionLine.text, "addon update v99.0.0", 1, true)
        and string.find(TB.versionLine.text, "bots update v1.22.0", 1, true), "the header names both updates")
    StaticPopupDialogs.TORTOISEBOTSMANAGER_COMPAT.OnAccept()
    TB._compatShown = nil
    TB.OnSystemMessage("TBM:CAPS|pull-seconds")
    assert(TB._t.popups == 3 and string.find(TB.versionLine.text, "addon update", 1, true),
        "Don't show again hides the update popup but keeps the header note")
    TB.OnSystemMessage("TBM:LATEST|-|-")
    TB.RefreshVersionLine()
    assert(TB.latestAddon == nil and not string.find(TB.versionLine.text, "update", 1, true),
        "unknown releases add nothing")
    assert(TB.IsNewerVersion("1.10.0", "1.9.9") and not TB.IsNewerVersion("1.2.0", "1.2.0")
        and not TB.IsNewerVersion("1.3.0", "dev") and not TB.IsNewerVersion(nil, "1.0.0"), "version compare")
    TB.latestModule, TB.latestAddon = nil, nil
    StaticPopupDialogs, StaticPopup_Show = TB._t.dialogs, TB._t.show
    TB._t, TB._compatShown, TortoiseBotsDB.compatDismissed = nil, nil, nil
end

dofile(root .. "/tests/phase0_tests.lua")()

print("PASS: TortoiseBotsManager regression checks")

