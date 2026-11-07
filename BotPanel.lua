-- TortoiseBotsManager/BotPanel.lua
-- Per-bot state and the bot panel (gear, bags, behaviour).
--
-- Everything shown here comes from the server:
--   TBM:BOTSTATE  → movement mode and behaviour toggles of each live bot
--                   (roster trailer; also the reply to ".bot behavior")
--   TBM:INV_*     → one bot's equipped gear, bag items and money
-- Each click sends exactly one request (`inv`, `item`, `behavior`) and the
-- server answers with fresh state, so the panel never guesses what happened.
-- Items are addressed by the server's own bag/slot pair.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local PW = 330
local PH = 470 -- taller than the main window: paper doll + footer
local SLOT = 34
local STEP = 38
local BAG_COLS, BAG_ROWS = 8, 7
local SPELL_ROWS = 12
local EQUIPPED_BAG = 255 -- INVENTORY_SLOT_BAG_0: equipment and backpack

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end

-- Spell list page; the spellbook reply resets it, so declared above that.
local spellPage = 1
local function now() return (GetTime and GetTime()) or 0 end

-- ── bot state model ─────────────────────────────────────────────────────────
local botStates = {}

function TB.RefreshBotViews()
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
    if TB.partyFrame and TB.partyFrame:IsVisible() and TB.RefreshPartyView then TB.RefreshPartyView() end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

-- A full snapshot replaces the set: bots that left the party disappear.
function TB.SetBotStates(rows)
    for key in pairs(botStates) do botStates[key] = nil end
    for _, row in ipairs(rows or {}) do
        if row.name then botStates[norm(row.name)] = row.state or {} end
    end
    TB.RefreshBotViews()
end

function TB.SetBotState(name, state)
    name = norm(name)
    if not name then return end
    botStates[name] = state or {}
    TB.RefreshBotViews()
end

function TB.GetBotState(name)
    name = norm(name)
    return name and botStates[name] or nil
end

function TB.GetBotStates()
    return botStates
end

function TB.MovementLabel(name)
    local st = TB.GetBotState(name)
    local move = st and st.move
    return move and C.MOVEMENT_LABELS and C.MOVEMENT_LABELS[move] or nil
end

-- ── movement modes (Actions tab MOVE card) ──────────────────────────────────
local MOVE_MODES = { follow = true, stay = true, guard = true, free = true }

-- The mode every live bot shares, "mixed" when they differ, nil = unknown.
function TB.GetPartyMoveMode()
    local mode
    for _, st in pairs(botStates) do
        if st.move then
            if mode and mode ~= st.move then return "mixed" end
            mode = st.move
        end
    end
    return mode
end

-- A confirmed order shows at once; Come ends in stay or follow, so it
-- waits for the next roster snapshot.
function TB.OnMoveModeAck(packet)
    if not packet or (packet.count or 0) == 0 then return end
    if packet.intent == "come" then
        if TB.RequestPollSoon then TB.RequestPollSoon() end
        return
    end
    if not MOVE_MODES[packet.intent] then return end
    local _, _, botName = string.find(packet.scope or "", "^bot:(.+)$")
    local st = botName and botStates[norm(botName)]
    if st then
        st.move = packet.intent
    elseif not botName then
        for _, other in pairs(botStates) do other.move = packet.intent end
    end
    TB.RefreshBotViews()
end

-- ── party toggles (Actions tab: AoE, Auto CC, Loot) ─────────────────────────
-- Autonomous grind reply state for the Camp quests card.
TB.grindState = TB.grindState or nil

function TB.GetGrindState()
    return TB.grindState
end

function TB.NoteStrategyChange(change)
    change = TB.Trim(change or "")
    if change == "+grind" then
        TB.grindState = "on"
    elseif change == "-grind" then
        TB.grindState = "off"
    elseif change == "reset" then
        TB.grindState = "off"
    else
        return false
    end
    if TB.RefreshCampControls then TB.RefreshCampControls() end
    return true
end

TB.togglePending = TB.togglePending or {}
-- Used only when the server sends no BOTSTATE (older module): the last ACK.
TB.toggleFallback = TB.toggleFallback or {}

local toggleByIntent = {}
for _, def in ipairs((C and C.ACTION_DEFINITIONS) or {}) do
    if def.toggle then
        toggleByIntent[def.intent] = def.toggle
        if def.send == "behavior" then
            toggleByIntent["behavior " .. def.toggle] = def.toggle
        end
    end
end

function TB.PartyToggleKey(intent)
    return intent and toggleByIntent[intent] or nil
end

-- "on" / "off" when every live bot agrees, "mixed" otherwise, nil = unknown.
function TB.GetPartyToggleState(key)
    local on, off = false, false
    for _, st in pairs(botStates) do
        if st[key] == "on" then on = true elseif st[key] == "off" then off = true end
    end
    if not on and not off then return TB.toggleFallback[key] end
    if on and off then return "mixed" end
    return on and "on" or "off"
end

function TB.SendPartyToggle(key)
    local toggle
    for _, def in ipairs((C and C.ACTION_DEFINITIONS) or {}) do
        if def.toggle == key then toggle = def break end
    end
    if not toggle or TB.togglePending[key] then return false end
    local nextState = TB.GetPartyToggleState(key) == "on" and "off" or "on"
    TB.togglePending[key] = true
    if key == "aoe" then TB.aoePending = true end
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
    if toggle.send == "behavior" then
        return TB.SendBotCommand("behavior party " .. key .. " " .. nextState)
    end
    return TB.SendActionIntent(toggle.intent .. " " .. nextState)
end

function TB.SendStrategy(change)
    change = TB.Trim(change or "")
    if change == "" then return false end
    return TB.SendBotCommand("strategy " .. change)
end

-- value nil = the request failed: only the pending flag is cleared.
function TB.OnPartyToggleResult(key, scope, value)
    TB.togglePending[key] = nil
    if value == "on" or value == "off" then
        local _, _, botName = string.find(scope or "", "^bot:(.+)$")
        local st = botName and botStates[norm(botName)]
        if st then
            st[key] = value
        else
            for _, other in pairs(botStates) do other[key] = value end
            TB.toggleFallback[key] = value
        end
    elseif value == "mixed" then
        TB.toggleFallback[key] = "mixed"
    end
    if key == "aoe" then
        TB.aoePending = false
        TB.aoeEnabled = TB.GetPartyToggleState("aoe") == "on"
    end
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
end

-- ── inventory model ─────────────────────────────────────────────────────────
local inventories = {}

function TB.SetInventory(name, inventory)
    name = norm(name)
    if not name or type(inventory) ~= "table" then return end
    inventory.at = now()
    inventories[name] = inventory
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

function TB.GetInventory(name)
    name = norm(name)
    return name and inventories[name] or nil
end

function TB.RequestInventory(name)
    name = norm(name)
    if not name then return false end
    return TB.SendBotCommand("inv " .. name)
end

-- ── spellbook model ─────────────────────────────────────────────────────────
-- Whisper replies to ".bot command <bot> spells": one "=== Spells ===" header
-- line, then one "|cffffffff|Hspell:<id>|h[<name>]|h|r ..." line per spell
-- (server: ListSpellsAction.cpp; Hspell shape: ChatHelper::formatSpell).
-- Clicking a row asks the bot to cast by exact name
-- (".bot command <bot> cast <name>").
local spellLists = {} -- [bot] = { at, pending, spells = { { id, name } } }

function TB.SetSpellPending(name, pending)
    name = norm(name)
    if not name then return end
    local entry = spellLists[name] or { spells = {} }
    entry.pending = pending and true or false
    entry.at = now()
    spellLists[name] = entry
end

function TB.GetSpellList(name)
    name = norm(name)
    return name and spellLists[name] or nil
end

local function parseSpellLine(msg)
    -- List lines start with the color escape; cast confirmations ("Casting ...")
    -- carry a link too but must reach the command-op gate, so never parse them.
    if not msg or string.find(msg, "^Casting") then return nil end
    local _, _, id, label = string.find(msg, "^|c%x+|Hspell:(%d+)|h%[([^%]]+)%]")
    id = tonumber(id)
    if not id or not label then return nil end
    label = TB.Trim(label)
    if label == "" then return nil end
    return id, label
end
TB.ParseSpellLine = parseSpellLine

-- Returns "header" / spell count / false. Only lines from the panel bot
-- while its spell query is pending reach the list; anything else stays on
-- the legacy AI-reply path so the command-op gate keeps working.
function TB.ConsumeSpellReply(name, msg)
    name = norm(name)
    if not name or not msg or msg == "" then return false end
    if name ~= TB.GetBotPanelBot() then return false end
    local entry = spellLists[name]
    if not entry or not entry.pending then return false end
    -- No end-of-list marker on the wire (one whisper per line): the burst
    -- ends when the bot goes quiet, then later whispers (cast replies, AI
    -- answers) flow back to the command-op gate.
    if now() - (entry.at or 0) > (C.ACTION_TIMEOUT or 8) then
        entry.pending = false
        return false
    end
    if string.find(msg, "=== Spells ===") then
        entry.spells = {}
        entry.at = now()
        spellPage = 1
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
        return "header"
    end
    local id, label = parseSpellLine(msg)
    if not id then return false end
    entry.spells = entry.spells or {}
    for _, known in ipairs(entry.spells) do
        if known.id == id then return table.getn(entry.spells) end
    end
    table.insert(entry.spells, { id = id, name = label })
    entry.at = now()
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    return table.getn(entry.spells)
end

function TB.RequestSpells(name)
    name = norm(name)
    if not name then return false end
    local entry = spellLists[name] or { spells = {} }
    entry.pending = true
    entry.at = now()
    spellLists[name] = entry
    if TB.SetStatus then TB.SetStatus("Asking " .. name .. " for its spellbook…", "pending") end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    return TB.SendBotCommand("command " .. name .. " spells")
end

function TB.SendBotCast(name, spellName)
    name = norm(name)
    spellName = TB.Trim(spellName or "")
    if not name or spellName == "" then return false end
    if TB.SetStatus then TB.SetStatus(name .. " casts " .. spellName .. "…", "pending") end
    return TB.SendBotCommand("command " .. name .. " cast " .. spellName)
end

-- ── professions model ─────────────────────────────────────────────────────────
-- Structured reply to ".bot professions": skills with value/max, known
-- recipes with the 1.12 difficulty steps, and missing (learnable but
-- unknown) recipes. Cached per bot for the session; hovering a guild row
-- never sends, only the Professions view and Refresh ask.
local PROF_CAP = "professions"
local professions = {} -- [bot] = { at, skills = { { skill, value, max } },
--   recipes = { { skill, spell, item, orange, yellow, green, grey, order } },
--   missing = { { skill, spell, item, reqSkill, recipeItem } } }

function TB.HasProfessionsCapability()
    return TB.HasServerCapability and TB.HasServerCapability(PROF_CAP) or false
end

function TB.SetProfessions(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    snapshot.at = now()
    professions[name] = snapshot
    if TB.RepaintGuildRowTooltip then TB.RepaintGuildRowTooltip(name) end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

function TB.GetProfessions(name)
    name = norm(name)
    return name and professions[name] or nil
end

function TB.RequestProfessions(name)
    if not TB.HasProfessionsCapability() then return false end
    name = norm(name)
    if not name then return false end
    return TB.SendBotCommand("professions " .. name)
end

-- ── conjured services model ─────────────────────────────────────────────────
-- Reply to ".bot service <bot>" (mages: food, water, portals; warlocks:
-- healthstones). Cached per bot for the session; the panel asks once on
-- open for a mage or warlock, Refresh asks again.
local services = {} -- [bot] = { at, food, water, healthstone, portals = { { spell, city } } }

function TB.SetService(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    snapshot.at = now()
    services[name] = snapshot
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

function TB.GetService(name)
    name = norm(name)
    return name and services[name] or nil
end

function TB.RequestService(name)
    name = norm(name)
    if not name then return false end
    return TB.SendBotCommand("service " .. name)
end

-- TBM:SERVICE|<bot>|<food 0/1>|<water 0/1>|<healthstone 0/1>|<portals>.
-- <portals> is "-" or comma-separated "<spellId>:<city>" pairs.
-- A malformed line returns nil and never clobbers the cache; a malformed
-- portal entry is skipped while the rest of the line still parses.
function TB.ParseServiceLine(msg)
    if string.sub(msg or "", 1, 12) ~= "TBM:SERVICE|" then return nil end
    local text = string.sub(msg, 13)
    local fields = {}
    local start = 1
    while true do
        local at = string.find(text, "|", start, true)
        if at then
            table.insert(fields, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(fields, string.sub(text, start))
            break
        end
    end
    if table.getn(fields) ~= 5 then return nil end
    local name = norm(fields[1])
    if not name or name == "" then return nil end
    for i = 2, 4 do
        if not string.find(fields[i] or "", "^[01]$") then return nil end
    end
    local portals = {}
    local tail = TB.Trim(fields[5] or "")
    if tail ~= "" and tail ~= "-" then
        local pos = 1
        while true do
            local comma = string.find(tail, ",", pos, true)
            local entry = TB.Trim(string.sub(tail, pos, (comma and comma - 1) or string.len(tail)))
            local _, _, spell, city = string.find(entry, "^(%d+):(.+)$")
            city = city and TB.Trim(city) or ""
            if spell and city ~= "" then
                table.insert(portals, { spell = tonumber(spell), city = city })
            end
            if not comma then break end
            pos = comma + 1
        end
        if table.getn(portals) == 0 then return nil end
    end
    return {
        name = name,
        food = fields[2] == "1",
        water = fields[3] == "1",
        healthstone = fields[4] == "1",
        portals = portals,
    }
end

function TB.ConsumeServiceLine(msg)
    local snapshot = TB.ParseServiceLine(msg)
    if not snapshot then return false end
    TB.SetService(snapshot.name, {
        food = snapshot.food, water = snapshot.water,
        healthstone = snapshot.healthstone, portals = snapshot.portals,
    })
    return true
end

-- Portal menu: one dropdown row per city the cached service reply lists.
-- The builder stays testable without the DropDownList frames; the opener
-- needs the 1.12 dropdown API. Picking a city sends the portal order.
function TB.GetServicePortalOptions(name)
    local snapshot = TB.GetService(norm(name))
    return snapshot and snapshot.portals or {}
end

function TB.BuildServicePortalMenu(name, addButton)
    local options = TB.GetServicePortalOptions(name)
    for _, option in ipairs(options) do
        local spell, city = option.spell, option.city
        addButton({ text = city, notCheckable = 1,
            func = function()
                if TB.SendBotCommand then
                    TB.SendBotCommand("service " .. norm(name) .. " portal " .. tostring(spell))
                end
            end })
    end
    return table.getn(options)
end

function TB.OpenServicePortalMenu(name)
    name = norm(name)
    if not name then return false end
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if table.getn(TB.GetServicePortalOptions(name)) == 0 then return false end
    if not TB._servicePortalMenu then
        TB._servicePortalMenu = CreateFrame("Frame", "TortoiseBotsManagerServicePortalMenu",
            UIParent, "UIDropDownMenuTemplate")
    end
    local menu = TB._servicePortalMenu
    local bot = name
    UIDropDownMenu_Initialize(menu, function()
        TB.BuildServicePortalMenu(bot, UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, menu, "cursor")
    return true
end

-- Drop the cache when the token vanishes mid-session (server swapped),
-- like the run/loot/order views do.
function TB.NoteProfessionsCaps()
    if TB.HasProfessionsCapability() then
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
        return
    end
    for key in pairs(professions) do professions[key] = nil end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

-- TBM:RECIPE|<skillId>|<spellId>|<itemId or 0>|<orange>|<yellow>|<green>|<grey>[|<order>].
-- The order field is the server's craft-order verdict (ok or a reason
-- token); a missing field (older server) falls back to the itemId rule.
function TB.ParseProfessionRecipeLine(msg)
    if string.sub(msg or "", 1, 11) ~= "TBM:RECIPE|" then return nil end
    local text = string.sub(msg, 12)
    local fields = {}
    local start = 1
    while true do
        local at = string.find(text, "|", start, true)
        if at then
            table.insert(fields, string.sub(text, start, at - 1))
            start = at + 1
        else
            table.insert(fields, string.sub(text, start))
            break
        end
    end
    local count = table.getn(fields)
    if count ~= 7 and count ~= 8 then return nil end
    for i = 1, 7 do
        if not fields[i] or not string.find(fields[i], "^%d+$") then return nil end
    end
    local order = nil
    if count == 8 then
        order = TB.Trim(fields[8] or "")
        if order == "" then return nil end
        order = string.lower(order)
    end
    return {
        skill = tonumber(fields[1]), spell = tonumber(fields[2]),
        item = tonumber(fields[3]),
        orange = tonumber(fields[4]), yellow = tonumber(fields[5]),
        green = tonumber(fields[6]), grey = tonumber(fields[7]),
        order = order,
    }
end

-- Trade-skill difficulty for the bot's current skill: a recipe turns yellow
-- once skill passes orange (no longer orange), green once it passes yellow,
-- grey once it passes green. Below or at orange it stays orange.
function TB.ProfessionRecipeColor(recipe, skillValue)
    if not recipe then return nil end
    skillValue = tonumber(skillValue)
    if not skillValue then return nil end
    if skillValue >= (tonumber(recipe.grey) or 0) then return "grey" end
    if skillValue >= (tonumber(recipe.green) or 0) then return "green" end
    if skillValue >= (tonumber(recipe.yellow) or 0) then return "yellow" end
    return "orange"
end

-- The server's verdict decides the Craft button. A missing
-- field (older server) falls back to today's itemId rule.
local RECIPE_ORDER_REASON = {
    ok = nil,
    norecipe = "The bot does not know this recipe",
    enchant = "Enchants cannot be ordered yet",
    bound = "Soulbound when made, cannot be handed over",
    needsprofession = "Needs a profession to use",
    cooldown = "Long cooldown, cannot be ordered",
}

function TB.ProfessionRecipeOrderable(recipe)
    if not recipe then return false end
    if recipe.order then return recipe.order == "ok" end
    return (tonumber(recipe.item) or 0) > 0
end

function TB.ProfessionRecipeOrderReason(recipe)
    if not recipe then return nil end
    if recipe.order then
        if recipe.order == "ok" then return nil end
        return RECIPE_ORDER_REASON[recipe.order] or recipe.order
    end
    if (tonumber(recipe.item) or 0) <= 0 then
        return RECIPE_ORDER_REASON.enchant
    end
    return nil
end

-- Trade-skill names, mirroring the order search's SKILL_NAMES (BotOrder.lua).
local PROFESSION_NAMES = {
    ["129"] = "First Aid", ["164"] = "Blacksmithing", ["165"] = "Leatherworking",
    ["171"] = "Alchemy", ["182"] = "Herbalism", ["185"] = "Cooking",
    ["186"] = "Mining", ["197"] = "Tailoring", ["202"] = "Engineering",
    ["333"] = "Enchanting", ["356"] = "Fishing", ["393"] = "Skinning",
}

function TB.ProfessionSkillName(skillId)
    return PROFESSION_NAMES[tostring(skillId or "")] or ("Skill " .. tostring(skillId or "?"))
end

-- Guild row tooltip line: "Mining 245/300, Blacksmithing 230/300". Skills
-- only (no recipe counts); nil without a cached reply.
function TB.ProfessionTooltipLine(name)
    local snapshot = TB.GetProfessions and TB.GetProfessions(name) or nil
    if not snapshot or not snapshot.skills or table.getn(snapshot.skills) == 0 then return nil end
    local parts = {}
    for _, skill in ipairs(snapshot.skills) do
        table.insert(parts, TB.ProfessionSkillName(skill.skill)
            .. " " .. tostring(skill.value) .. "/" .. tostring(skill.max))
    end
    return table.concat(parts, ", ")
end

-- Missing row source: "Trainer" when taught only by a trainer
-- (recipeItem 0), else the recipe item name (client cache or the id).
function TB.ProfessionMissingSourceText(missing)
    if not missing or (tonumber(missing.recipeItem) or 0) <= 0 then return "Trainer" end
    if GetItemInfo then
        local name = GetItemInfo(missing.recipeItem)
        if name then return name end
    end
    return "item #" .. tostring(missing.recipeItem)
end

-- ── item helpers ────────────────────────────────────────────────────────────
-- Vanilla GetItemInfo: name, link ("item:id:0:0:0"), quality, level, type,
-- subtype, stack, equipLoc, texture. Nil until the client cached the item.
local function itemInfo(id)
    if not id or not GetItemInfo then return nil end
    local name, link, quality, _, _, _, _, _, texture = GetItemInfo(id)
    return name, link, quality, texture
end

local function qualityColor(quality)
    if quality and GetItemQualityColor then
        local r, g, b, hex = GetItemQualityColor(quality)
        if r then return r, g, b, hex end
    end
    return 0.35, 0.35, 0.35, "|cffffffff"
end

local function itemLabel(id)
    local name, _, quality = itemInfo(id)
    if not name then return "item #" .. tostring(id) end
    local _, _, _, hex = qualityColor(quality)
    return (hex or "") .. "[" .. name .. "]|r"
end

local scanTip
local uncachedAt = nil
-- Ask the server for an uncached item: a hidden tooltip query caches it,
-- and the panel re-renders a moment later.
local function requestItem(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TortoiseBotsManagerScanTip", UIParent, "GameTooltipTemplate")
    end
    if scanTip.SetOwner and scanTip.SetHyperlink then
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:SetHyperlink("item:" .. id .. ":0:0:0")
    end
    uncachedAt = uncachedAt or now()
end

local function chatLink(id)
    local name, link, quality = itemInfo(id)
    if not name or not link then return nil end
    local _, _, _, hex = qualityColor(quality)
    return (hex or "|cffffffff") .. "|H" .. link .. "|h[" .. name .. "]|h|r"
end

local function formatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local text = ""
    if g > 0 then text = text .. "|cffffd700" .. g .. "g|r " end
    if g > 0 or s > 0 then text = text .. "|cffc7c7cf" .. s .. "s|r " end
    return text .. "|cffeda55f" .. c .. "c|r"
end
TB.FormatMoney = formatMoney

-- The unit id of a grouped bot, for its class and 3D model.
local function botUnit(name)
    name = norm(name)
    if not name or not UnitName then return nil end
    local raid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            if norm(UnitName(unit)) == name then return unit end
        end
    end
    local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        if norm(UnitName(unit)) == name then return unit end
    end
    return nil
end

local function botClassId(name)
    local unit = botUnit(name)
    if unit and UnitClass then
        local className, classFile = UnitClass(unit)
        local ids = C.CLASS_NAME_TO_ID or {}
        return ids[classFile or ""] or ids[className or ""]
    end
    local entry = (TB.GetRosterEntry and TB.GetRosterEntry(name))
        or (TB.GetClaimedEntry and TB.GetClaimedEntry(name))
    return entry and entry.classId or nil
end

-- Only mages (8) and warlocks (9) answer ".bot service".
function TB.ServiceWanted(name)
    local classId = botClassId(name)
    return classId == 8 or classId == 9
end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── panel state ─────────────────────────────────────────────────────────────
local panel
local currentBot
local currentView = "gear"
local bagPage = 1
local profPage = 1
local profSearch = ""
local profCollapsed = {} -- [skillId] = true while its "Not learned yet" group stays shut
local pendingGive = nil       -- { bot, bag, slot } awaiting the trade window
local behaviorPending = {}    -- [bot .. "|" .. key] = true
local pendingLink = nil       -- { bot, verb, id, label } awaiting the client item cache
local retryingLink = false    -- true while the OnUpdate retry sends, so a miss does not requeue

function TB.GetBotPanelBot()
    return panel and panel:IsVisible() and currentBot or nil
end

-- ── item orders ─────────────────────────────────────────────────────────────
function TB.SendItemOrder(op, bag, slot)
    if not currentBot then return false end
    if op == "give" then pendingGive = { bot = currentBot, bag = bag, slot = slot } end
    local cmd = "item " .. currentBot .. " " .. op
    if bag and slot then cmd = cmd .. " " .. bag .. " " .. slot end
    if TB.SetStatus then TB.SetStatus((C.ACTION_LABELS["item " .. op] or op) .. " → " .. currentBot .. "…", "pending") end
    return TB.SendBotCommand(cmd)
end

-- Link orders (`destroy`, `cast Disenchant`, `sendmail`, `bank`) carry the full
-- item hyperlink, so the module can match the exact stack without a bag/slot.
-- An uncached item queues a tooltip lookup and retries once cached; the click
-- is never silently dropped ("Loading…" shows while the client is fetching).
local function linkText(id)
    if not id or not GetItemInfo then return nil end
    local name, link = GetItemInfo(id)
    if not name or not link then return nil end
    return "|H" .. link .. "|h[" .. name .. "]|h", name
end

local function sendLinkOrder(verb, id)
    if not currentBot or not id then return false end
    local link = linkText(id)
    if not link then
        requestItem(id)
        pendingLink = { bot = currentBot, verb = verb, id = id,
            label = (C.ACTION_LABELS and C.ACTION_LABELS[verb]) or verb }
        if TB.SetStatus then TB.SetStatus("Loading item #" .. id .. "…", "pending") end
        return false
    end
    pendingLink = nil
    if TB.SetStatus then TB.SetStatus(((C.ACTION_LABELS and C.ACTION_LABELS[verb]) or verb) .. " → " .. currentBot .. "…", "pending") end
    return TB.SendBotCommand("command " .. currentBot .. " " .. verb .. " " .. link)
end
TB.SendLinkOrder = sendLinkOrder
-- Destroy asks first: a StaticPopup names the item, and the order only
-- sends on Accept. No global hooks; the menu closes on open like elsewhere.
function TB.ConfirmDestroyItem(id)
    if not currentBot or not id then return false end
    local link = linkText(id)
    local what = link or ("item #" .. id)
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs["TORTOISEBOTSMANAGER_DESTROY_ITEM"] = {
            text = "Destroy " .. what .. " on " .. currentBot .. "?\n\nThis cannot be undone.",
            button1 = "Destroy",
            button2 = "Cancel",
            OnAccept = function()
                sendLinkOrder("destroy", id)
                if TB.RequestInventory then TB.RequestInventory(currentBot) end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
        }
        StaticPopup_Show("TORTOISEBOTSMANAGER_DESTROY_ITEM")
    else
        sendLinkOrder("destroy", id)
    end
    return true
end

-- The `u` order takes a full item hyperlink (`command <bot> u <link>`),
-- unlike SendItemOrder which addresses bag/slot. Returns false when the
-- item is not cached yet (and queues a tooltip lookup instead).
function TB.SendItemUse(id)
    if not currentBot or not id then return false end
    local link = linkText(id)
    if not link then
        requestItem(id)
        pendingLink = { bot = currentBot, verb = "u", id = id, label = "Use" }
        if TB.SetStatus then TB.SetStatus("Loading item…", "pending") end
        return false
    end
    pendingLink = nil
    if TB.SetStatus then TB.SetStatus(("Use → " .. currentBot .. "…"), "pending") end
    return TB.SendBotCommand("command " .. currentBot .. " u " .. link)
end

function TB.SendBehavior(name, key)
    name = norm(name)
    if not name or not key then return false end
    local pendingKey = name .. "|" .. key
    if behaviorPending[pendingKey] then return false end
    local st = TB.GetBotState(name) or {}
    local nextState = st[key] == "on" and "off" or "on"
    behaviorPending[pendingKey] = true
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    return TB.SendBotCommand("behavior " .. name .. " " .. key .. " " .. nextState)
end

-- ACK routing from Comms.ParseActionMessage. Returns true when handled.
function TB.OnBotPanelAck(packet)
    local intent = packet.intent or ""
    local botName = string.gsub(packet.scope or "", "^bot:", "")
    local _, _, op = string.find(intent, "^item%s+(%a+)$")
    if op then
        local _, _, id, detail = string.find(packet.executor or "", "^(%d+)%s*(%a*)$")
        id = tonumber(id)
        local text
        if op == "trade" then
            text = "Trade open with " .. botName .. ". Put your items in and accept - the bot accepts on its own."
        elseif op == "give" and detail == "pending" then
            text = "Opening trade with " .. botName .. "; " .. itemLabel(id) .. " goes in when the window opens."
        elseif op == "give" then
            pendingGive = nil
            text = itemLabel(id) .. " is in the trade window. Accept the trade to take it."
        elseif op == "equip" then
            text = botName .. " equipped " .. itemLabel(id) .. "."
        elseif op == "unequip" then
            text = botName .. " put " .. itemLabel(id) .. " in its bags."
        else
            text = intent .. " accepted"
        end
        if TB.SetStatus then TB.SetStatus(text, "ok") end
        return true
    end
    if intent == "service portal" then
        if TB.SetStatus then TB.SetStatus("Portal open by " .. botName .. ".", "ok") end
        return true
    end
    local _, _, key = string.find(intent, "^behavior%s+(%S+)$")
    if key then
        behaviorPending[norm(botName) .. "|" .. key] = nil
        local label = key
        for _, b in ipairs(C.BEHAVIORS or {}) do if b.key == key then label = b.label end end
        if TB.SetStatus then TB.SetStatus(botName .. ": " .. label .. " " .. (packet.executor == "on" and "on" or "off"), "ok") end
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
        return true
    end
    return false
end

function TB.OnBotPanelError(packet)
    local intent = packet.intent or ""
    if intent == "item give" then pendingGive = nil end
    local _, _, key = string.find(intent, "^behavior%s+(%S+)$")
    if key then
        for pendingKey in pairs(behaviorPending) do
            if string.find(pendingKey, "|" .. key .. "$") then behaviorPending[pendingKey] = nil end
        end
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    end
end

-- ── panel construction ──────────────────────────────────────────────────────
local itemMenu

local function hideMenu()
    if itemMenu then itemMenu:Hide(); if itemMenu.catcher then itemMenu.catcher:Hide() end; itemMenu.owner = nil end
end

local function createItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(SLOT); b:SetHeight(SLOT)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints(b)
    b.border:SetTexture(0.25, 0.25, 0.25, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count:SetJustifyH("RIGHT")
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.badge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
    b.badge:SetText("|cff40ff40+|r")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function()
        local entry = this.entry
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if entry and entry.id then
            if GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. entry.id .. ":0:0:0")
            else
                GameTooltip:SetText(itemLabel(entry.id))
            end
            if entry.upgrade then GameTooltip:AddLine("Upgrade for " .. (currentBot or "this bot"), 0.25, 1, 0.25) end
            if entry.equipped then
                GameTooltip:AddLine("Click: unequip", 0.62, 0.60, 0.56)
            else
                local hint = entry.equippable and "Click: equip or give to you" or "Click: give to you"
                if entry.noTrade and entry.equippable then hint = "Click: equip (cannot be traded)" end
                if entry.noTrade and not entry.equippable then hint = "Soulbound - stays with the bot" end
                GameTooltip:AddLine(hint, 0.62, 0.60, 0.56)
            end
            GameTooltip:AddLine("Shift-click: link in chat", 0.62, 0.60, 0.56)
        else
            GameTooltip:SetText(this.slotLabel or "Empty")
            GameTooltip:AddLine("Nothing equipped", 0.62, 0.60, 0.56)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        local entry = this.entry
        if not entry or not entry.id then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            local link = chatLink(entry.id)
            if link and ChatFrameEditBox and ChatFrameEditBox.IsVisible and ChatFrameEditBox:IsVisible() then
                ChatFrameEditBox:Insert(link)
            end
            return
        end
        if itemMenu.owner == this and itemMenu:IsVisible() then hideMenu() return end
        itemMenu:Open(this, entry)
    end)
    return b
end

local function paintItemButton(b, entry, emptyTexture)
    b.entry = entry
    if entry and entry.id then
        local _, _, quality, texture = itemInfo(entry.id)
        if not texture then requestItem(entry.id) end
        b.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local r, g, bl = qualityColor(quality)
        if entry.maxDurability and entry.maxDurability > 0
            and (entry.durability or 0) / entry.maxDurability < 0.25 then
            r, g, bl = 1, 0.15, 0.1 -- nearly broken: red frame
        end
        b.border:SetTexture(r, g, bl, 0.95)
        b.count:SetText((entry.count and entry.count > 1) and tostring(entry.count) or "")
        if entry.upgrade then b.badge:Show() else b.badge:Hide() end
        if b.icon.SetVertexColor then
            if entry.noTrade and not entry.equippable and not entry.equipped then
                b.icon:SetVertexColor(0.7, 0.7, 0.7)
            else
                b.icon:SetVertexColor(1, 1, 1)
            end
        end
    else
        b.icon:SetTexture(emptyTexture or nil)
        b.icon:SetTexCoord(0, 1, 0, 1)
        if b.icon.SetVertexColor then b.icon:SetVertexColor(1, 1, 1) end
        b.border:SetTexture(0.12, 0.12, 0.12, 0.9)
        b.count:SetText("")
        b.badge:Hide()
    end
    b:Show()
end

local function createMenu(parent)
    local menu = CreateFrame("Frame", "TortoiseBotsManagerItemMenu", parent)
    menu:SetWidth(118); menu:SetHeight(178)
    menu:SetFrameStrata("TOOLTIP")
    menu:EnableMouse(true)
    TB.ApplyBackdrop(menu, 0.98, 1.0)
    local function button(label, y, tip)
        local btn = TB.StyleButton(CreateFrame("Button", nil, menu, "UIPanelButtonTemplate"))
        btn:SetWidth(106); btn:SetHeight(22)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, y)
        btn:SetText(label)
        setTooltip(btn, label, { tip })
        return btn
    end
    menu.first = button("Equip", -6, "The bot equips this item.")
    menu.second = button("Give to me", -30, "Opens a trade with the bot and puts this item in. Accept the trade to take it.")
    menu.third = button("Use", -54, "The bot uses this item (food, drink, potion).")
    menu.fourth = button("Disenchant", -78, "The bot disenchants this item into dust or shards.")
    menu.fifth = button("Send by mail", -102, "The bot mails this item to you.")
    menu.sixth = button("Put to bank", -126, "The bot stores this item in its bank.")
    menu.seventh = button("|cffff5555Destroy|r", -150, "The bot destroys this item. Cannot be undone.")
    -- A panel-sized catcher closes the menu on a click outside it. It is a
    -- plain panel child (no global mouse hook), shown only with the menu, so
    -- other addons never see it.
    menu.catcher = CreateFrame("Button", nil, parent)
    menu.catcher:SetAllPoints(parent)
    menu.catcher:EnableMouse(true)
    menu.catcher:SetScript("OnClick", function() hideMenu() end)
    function menu:Open(owner, entry)
        self.owner = owner
        self.entry = entry
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", -8, 8)
        -- Stay inside the screen: opening left of the slot when the right
        -- side has no room (right-edge bag columns, panel at screen edge),
        -- and above the slot when the bottom has no room (lower bag rows).
        -- Both flips combine: a bottom-right slot opens above AND left.
        local right = self.GetRight and self:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local bottom = self.GetBottom and self:GetBottom()
        local flipX = right and screen and right > screen
        local flipY = bottom and bottom < 0
        if flipX or flipY then
            self:ClearAllPoints()
            local myPt = (flipY and "BOTTOM" or "TOP") .. (flipX and "RIGHT" or "LEFT")
            local relPt = (flipY and "TOP" or "BOTTOM") .. (flipX and "LEFT" or "RIGHT")
            self:SetPoint(myPt, owner, relPt, flipX and 8 or -8, flipY and -8 or 8)
        end
        if entry.equipped then
            self.first:SetText("Unequip")
            self.first:Enable()
            self.first.op = "unequip"
            self.second:Hide()
            self.third:Hide()
            self.fourth:Hide()
            self.fifth:Hide()
            self.sixth:Hide()
            self.seventh:Hide()
            self:SetHeight(34)
        else
            self.first:SetText("Equip")
            self.first.op = "equip"
            if entry.equippable then self.first:Enable() else self.first:Disable() end
            self.second:Show()
            if entry.noTrade then self.second:Disable() else self.second:Enable() end
            self.third:Show()
            -- Only Give and Send by mail move the item off the bot, so only
            -- those disable for soulbound items. Disenchanting and banking
            -- soulbound gear are normal profession/bank uses.
            self.fourth:Show()
            self.fourth:Enable()
            self.fifth:Show()
            if entry.noTrade then self.fifth:Disable() else self.fifth:Enable() end
            self.sixth:Show()
            self.sixth:Enable()
            self.seventh:Show()
            self:SetHeight(178)
        end
        self.catcher:Show()
        self:Show()
    end
    menu.first:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.SendItemOrder(menu.first.op, entry.bag, entry.slot) end
    end)
    menu.second:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.SendItemOrder("give", entry.bag, entry.slot) end
    end)
    menu.third:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.SendItemUse(entry.id) end
    end)
    menu.fourth:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then sendLinkOrder("cast Disenchant", entry.id) end
    end)
    menu.fifth:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then sendLinkOrder("sendmail", entry.id) end
    end)
    menu.sixth:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then sendLinkOrder("bank", entry.id) end
    end)
    menu.seventh:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.ConfirmDestroyItem(entry.id) end
    end)
    menu:Hide()
    menu.catcher:Hide()
    return menu
end

local function makeTab(parent, label, x, width, view)
    local b = TB.StyleTab(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -46)
    b:SetText(label)
    b:SetScript("OnClick", function()
        currentView = view
        hideMenu()
        TB.RefreshBotPanel()
    end)
    return b
end

local function createPanel()
    panel = CreateFrame("Frame", "TortoiseBotsManagerBotPanel", TB.frame or UIParent)
    panel:SetWidth(PW); panel:SetHeight(PH)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    TB.ApplySurface(panel, "window")
    TB.AddWindowHeader(panel, 42)
    -- A hairline under the tab row separates navigation from the view.
    TB.AddHairline(panel, -66, 1)

    local name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -9)
    name:SetWidth(170); name:SetJustifyH("LEFT")
    TB.StyleTitle(name, 14)
    panel.nameText = name

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -26)
    sub:SetWidth(PW - 44); sub:SetJustifyH("LEFT")
    TB.SetTextColor(sub, color("muted"))
    panel.subText = sub

    local money = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    money:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -11)
    money:SetWidth(110); money:SetJustifyH("RIGHT")
    panel.moneyText = money

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -7)
    close:SetScript("OnClick", function() TB.CloseBotPanel() end)

    panel.tabGear = makeTab(panel, "Gear", 10, 58, "gear")
    panel.tabBags = makeTab(panel, "Bags", 72, 58, "bags")
    panel.tabBehavior = makeTab(panel, "Behaviour", 134, 62, "behavior")
    panel.tabSpells = makeTab(panel, "Spells", 200, 56, "spells")
    panel.tabProfs = makeTab(panel, "Professions", 260, 60, "profs")
    setTooltip(panel.tabGear, "Gear", { "What the bot wears. Click a slot to unequip." })
    setTooltip(panel.tabBags, "Bags", { "Everything in the bot's bags. Click an item to equip it or take it." })
    setTooltip(panel.tabBehavior, "Behaviour", { "Per-bot combat habits, stored on the server." })
    setTooltip(panel.tabSpells, "Spells", { "What this bot can cast. Click a spell to cast it." })
    setTooltip(panel.tabProfs, "Professions", { "Trade skills, recipes and what the bot could still learn.", "Asks the server once; Refresh asks again." })

    -- Gear view: paper doll around the bot's 3D model.
    local gear = CreateFrame("Frame", nil, panel)
    gear:SetAllPoints(panel)
    panel.gear = gear
    local model = CreateFrame("PlayerModel", nil, gear)
    model:SetPoint("TOPLEFT", panel, "TOPLEFT", 52, -74)
    model:SetWidth(PW - 104); model:SetHeight(262)
    panel.model = model
    -- Below the model (a model frame draws over its parent's text).
    local durability = gear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    durability:SetPoint("TOP", panel, "TOP", 0, -342)
    durability:SetWidth(PW - 110)
    panel.durabilityText = durability
    panel.gearButtons = {}
    local function placeColumn(list, x)
        for i, def in ipairs(list) do
            local b = createItemButton(gear)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -74 - (i - 1) * STEP)
            b.slotId = def.slot
            b.slotLabel = def.label
            b.emptyTexture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. def.empty
            panel.gearButtons[def.slot] = b
        end
    end
    placeColumn(C.GEAR_LEFT or {}, 10)
    placeColumn(C.GEAR_RIGHT or {}, PW - 10 - SLOT)
    for i, def in ipairs(C.GEAR_BOTTOM or {}) do
        local b = createItemButton(gear)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", math.floor(PW / 2 - STEP * 1.5 + 2) + (i - 1) * STEP, -380)
        b.slotId = def.slot
        b.slotLabel = def.label
        b.emptyTexture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. def.empty
        panel.gearButtons[def.slot] = b
    end

    -- Bags view: occupied slots only, paged.
    local bags = CreateFrame("Frame", nil, panel)
    bags:SetAllPoints(panel)
    panel.bags = bags
    local bagSummary = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagSummary:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -76)
    bagSummary:SetWidth(196); bagSummary:SetJustifyH("LEFT")
    TB.SetTextColor(bagSummary, color("muted"))
    panel.bagSummary = bagSummary
    local sweep = TB.StyleButton(CreateFrame("Button", nil, bags, "UIPanelButtonTemplate"))
    sweep:SetWidth(110); sweep:SetHeight(20)
    sweep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -72)
    sweep:SetText("Equip upgrades")
    setTooltip(sweep, "Equip upgrades (new loot)", { "The bot scans its bags and equips everything better.", "Footer → Auto-gear does a full re-gear from bags instead." })
    sweep:SetScript("OnClick", function()
        if currentBot then TB.SendBotCommand("command " .. currentBot .. " d equip upgrades") end
    end)
    panel.sweepButton = sweep
    panel.bagButtons = {}
    local x0 = math.floor((PW - (BAG_COLS * STEP - 4)) / 2)
    for r = 1, BAG_ROWS do
        for c = 1, BAG_COLS do
            local b = createItemButton(bags)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + (c - 1) * STEP, -94 - (r - 1) * STEP)
            table.insert(panel.bagButtons, b)
        end
    end
    local prev = TB.StyleButton(CreateFrame("Button", nil, bags, "UIPanelButtonTemplate"))
    prev:SetWidth(26); prev:SetHeight(20)
    prev:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -366)
    prev:SetText("<")
    prev:SetScript("OnClick", function() bagPage = bagPage - 1; hideMenu(); TB.RefreshBotPanel() end)
    local nextBtn = TB.StyleButton(CreateFrame("Button", nil, bags, "UIPanelButtonTemplate"))
    nextBtn:SetWidth(26); nextBtn:SetHeight(20)
    nextBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 100, -366)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function() bagPage = bagPage + 1; hideMenu(); TB.RefreshBotPanel() end)
    local pageText = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("TOPLEFT", panel, "TOPLEFT", 40, -370)
    pageText:SetWidth(58); pageText:SetJustifyH("CENTER")
    panel.prevPage, panel.nextPage, panel.pageText = prev, nextBtn, pageText
    local legend = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("TOPLEFT", panel, "TOPLEFT", 136, -370)
    legend:SetWidth(PW - 148); legend:SetJustifyH("RIGHT")
    legend:SetText("|cff40ff40+|r upgrade · grey = soulbound")
    TB.SetTextColor(legend, color("muted"))

    -- Behaviour view: two columns of toggle chips.
    local behavior = CreateFrame("Frame", nil, panel)
    behavior:SetAllPoints(panel)
    panel.behavior = behavior
    local bhTitle = behavior:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bhTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -78)
    bhTitle:SetText("Combat habits of this bot (saved on the server)")
    TB.SetTextColor(bhTitle, color("title"))
    panel.behaviorChips = {}
    for i, def in ipairs(C.BEHAVIORS or {}) do
        local chip = TB.StyleButton(CreateFrame("Button", nil, behavior, "UIPanelButtonTemplate"))
        chip:SetWidth(150); chip:SetHeight(24)
        chip.def = def
        chip.lamp = chip:CreateTexture(nil, "OVERLAY")
        chip.lamp:SetWidth(8); chip.lamp:SetHeight(8)
        chip.lamp:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
        setTooltip(chip, def.label, { def.tip, "Click to switch on/off." })
        chip:SetScript("OnClick", function()
            if currentBot then TB.SendBehavior(currentBot, this.def.key) end
        end)
        panel.behaviorChips[def.key] = chip
    end
    local bhHint = behavior:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bhHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -258)
    bhHint:SetWidth(PW - 24); bhHint:SetJustifyH("LEFT")
    bhHint:SetText("Party-wide switches live on the Fight tab; these override one bot.")
    TB.SetTextColor(bhHint, color("muted"))

    -- Spells view: the bot's spellbook, one row per known spell.
    local spellsView = CreateFrame("Frame", nil, panel)
    spellsView:SetAllPoints(panel)
    panel.spells = spellsView
    local spTitle = spellsView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -78)
    spTitle:SetText("What this bot can cast (from the server)")
    TB.SetTextColor(spTitle, color("title"))
    panel.spellRows = {}
    for i = 1, SPELL_ROWS do
        local row = TB.StyleButton(CreateFrame("Button", nil, spellsView, "UIPanelButtonTemplate"))
        row:SetWidth(PW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -98 - (i - 1) * 22)
        row.spellId = 0
        row.spellName = nil
        setTooltip(row, "Spell", { "Click: ask the bot to cast it." })
        row:SetScript("OnClick", function()
            if currentBot and this.spellName then TB.SendBotCast(currentBot, this.spellName) end
        end)
        table.insert(panel.spellRows, row)
    end
    local spellEmpty = spellsView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellEmpty:SetPoint("TOPLEFT", spellsView, "TOPLEFT", 12, -195)
    spellEmpty:SetWidth(260); spellEmpty:SetJustifyH("CENTER")
    spellEmpty:SetText("Click 'Ask for spellbook' below to list this bot's spells.")
    TB.SetTextColor(spellEmpty, color("muted"))
    panel.spellEmpty = spellEmpty

    local ask = TB.StyleButton(CreateFrame("Button", nil, spellsView, "UIPanelButtonTemplate"))
    ask:SetWidth(150); ask:SetHeight(22)
    ask:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -366)
    ask:SetText("Ask for spellbook")
    setTooltip(ask, "Ask for spellbook", { "Lists what this bot can cast.", "Click a row to cast it." })
    ask:SetScript("OnClick", function()
        if currentBot then TB.RequestSpells(currentBot) end
    end)
    panel.spellAsk = ask
    local prev = TB.StyleButton(CreateFrame("Button", nil, spellsView, "UIPanelButtonTemplate"))
    prev:SetWidth(26); prev:SetHeight(20)
    prev:SetPoint("LEFT", ask, "RIGHT", 6, 0)
    prev:SetText("<")
    prev:SetScript("OnClick", function() spellPage = spellPage - 1; TB.RefreshBotPanel() end)
    panel.spellPrev = prev
    local pageText = spellsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    pageText:SetWidth(52); pageText:SetJustifyH("CENTER")
    panel.spellPageText = pageText
    local nextBtn = TB.StyleButton(CreateFrame("Button", nil, spellsView, "UIPanelButtonTemplate"))
    nextBtn:SetWidth(26); nextBtn:SetHeight(20)
    nextBtn:SetPoint("LEFT", pageText, "RIGHT", 2, 0)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function() spellPage = spellPage + 1; TB.RefreshBotPanel() end)
    panel.spellNext = nextBtn

    -- Professions view: skills with value/max, known recipes under each,
    -- and a collapsed "Not learned yet" group per skill. One text search
    -- filters both. Footer Refresh re-asks the server; the view itself
    -- asks once when it has no cache yet.
    local PROF_ROWS = 9
    local profsView = CreateFrame("Frame", nil, panel)
    profsView:SetAllPoints(panel)
    panel.profs = profsView
    local profTitle = profsView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -78)
    profTitle:SetText("Trade skills and recipes (from the server)")
    TB.SetTextColor(profTitle, color("title"))
    local search = CreateFrame("EditBox", "TortoiseBotsManagerProfessionsSearch", profsView, "InputBoxTemplate")
    TB.StyleEditBox(search, "Search recipes")
    search:SetWidth(PW - 24); search:SetHeight(20)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -96)
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        profSearch = TB.Trim(this:GetText() or "")
        profPage = 1
        TB.RefreshBotPanel()
    end)
    panel.profSearch = search
    panel.profRows = {}
    for i = 1, PROF_ROWS do
        local row = CreateFrame("Button", nil, profsView)
        row:SetWidth(PW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -120 - (i - 1) * 22)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16); row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 22, 0)
        row.label:SetWidth(196); row.label:SetJustifyH("LEFT")
        row.craft = TB.StyleButton(CreateFrame("Button", nil, row, "UIPanelButtonTemplate"))
        row.craft:SetWidth(44); row.craft:SetHeight(16)
        row.craft:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.craft:SetText("Craft")
        row:SetScript("OnClick", function()
            if this.group and this.groupSkill then
                profCollapsed[this.groupSkill] = not profCollapsed[this.groupSkill]
                TB.RefreshBotPanel()
            end
        end)
        row.craft:SetScript("OnClick", function()
            local recipe = this:GetParent().recipe
            if recipe and currentBot and TB.PrefillCraftOrder then
                TB.PrefillCraftOrder(currentBot, recipe)
            end
        end)
        row.craft:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local recipe = this:GetParent().recipe
            if recipe and not TB.ProfessionRecipeOrderable(recipe) then
                GameTooltip:SetText(TB.ProfessionRecipeOrderReason(recipe) or "Cannot order")
            else
                GameTooltip:SetText("Craft order")
                GameTooltip:AddLine("Opens the order window with Craft and this item picked.", 0.9, 0.9, 0.9, 1)
            end
            GameTooltip:Show()
        end)
        row.craft:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(panel.profRows, row)
    end
    local profEmpty = profsView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profEmpty:SetPoint("TOPLEFT", profsView, "TOPLEFT", 12, -195)
    profEmpty:SetWidth(260); profEmpty:SetJustifyH("CENTER")
    profEmpty:SetText("Open this view to ask the bot for its professions.")
    TB.SetTextColor(profEmpty, color("muted"))
    panel.profEmpty = profEmpty
    local profAsk = TB.StyleButton(CreateFrame("Button", nil, profsView, "UIPanelButtonTemplate"))
    profAsk:SetWidth(150); profAsk:SetHeight(22)
    profAsk:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -366)
    profAsk:SetText("Refresh professions")
    setTooltip(profAsk, "Refresh professions", { "Asks the bot for its skills and recipes again." })
    profAsk:SetScript("OnClick", function()
        if currentBot then TB.RequestProfessions(currentBot) end
    end)
    panel.profAsk = profAsk
    local profPrev = TB.StyleButton(CreateFrame("Button", nil, profsView, "UIPanelButtonTemplate"))
    profPrev:SetWidth(26); profPrev:SetHeight(20)
    profPrev:SetPoint("LEFT", profAsk, "RIGHT", 6, 0)
    profPrev:SetText("<")
    profPrev:SetScript("OnClick", function() profPage = profPage - 1; TB.RefreshBotPanel() end)
    panel.profPrev = profPrev
    local profPageText = profsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profPageText:SetPoint("LEFT", profPrev, "RIGHT", 2, 0)
    profPageText:SetWidth(52); profPageText:SetJustifyH("CENTER")
    panel.profPageText = profPageText
    local profNext = TB.StyleButton(CreateFrame("Button", nil, profsView, "UIPanelButtonTemplate"))
    profNext:SetWidth(26); profNext:SetHeight(20)
    profNext:SetPoint("LEFT", profPageText, "RIGHT", 2, 0)
    profNext:SetText(">")
    profNext:SetScript("OnClick", function() profPage = profPage + 1; TB.RefreshBotPanel() end)
    panel.profNext = profNext
    -- Service row: conjured goods for mages and warlocks, above the footer.
    local food = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    food:SetWidth(88); food:SetHeight(20)
    food:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 54)
    food:SetText("Food & Water")
    setTooltip(food, "Food & Water", {
        "The bot opens a trade with conjured food and water in it.",
        "Accept the trade to take it.",
    })
    food:SetScript("OnClick", function() TB.SendItemOrder("trade") end)
    panel.foodButton = food

    local stone = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    stone:SetWidth(80); stone:SetHeight(20)
    -- Right edge: the weapon slots sit in the middle of this row.
    stone:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 54)
    stone:SetText("Healthstone")
    setTooltip(stone, "Healthstone", {
        "The bot opens a trade with a healthstone in it.",
        "Accept the trade to take it.",
    })
    stone:SetScript("OnClick", function() TB.SendItemOrder("trade") end)
    panel.healthstoneButton = stone

    local portal = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    portal:SetWidth(56); portal:SetHeight(20)
    portal:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 54)
    portal:SetText("Portal")
    setTooltip(portal, "Portal", {
        "The bot opens a portal. Pick where it goes.",
    })
    portal:SetScript("OnClick", function()
        if currentBot then TB.OpenServicePortalMenu(currentBot) end
    end)
    panel.portalButton = portal
    -- Footer: trade, refresh, NPC errands, vault, upkeep, gear-up, every view.
    local trade = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    trade:SetWidth(44); trade:SetHeight(22)
    trade:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 28)
    trade:SetText("Trade")
    setTooltip(trade, "Trade", {
        "Opens a trade window with this bot.",
        "Put your items or gold in and accept - the bot accepts on its own.",
        "To take an item from the bot, click it in Bags → Give to me.",
    })
    trade:SetScript("OnClick", function() TB.SendItemOrder("trade") end)
    panel.tradeButton = trade

    local refresh = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    refresh:SetWidth(56); refresh:SetHeight(22)
    refresh:SetPoint("LEFT", trade, "RIGHT", 3, 0)
    refresh:SetText("Refresh")
    setTooltip(refresh, "Refresh", { "Reload gear, bags, behaviour, conjured goods and professions from the server." })
    refresh:SetScript("OnClick", function()
        if currentBot then TB.RequestInventory(currentBot) end
        if currentBot then TB.RequestProfessions(currentBot) end
        if currentBot and TB.ServiceWanted(currentBot) then TB.RequestService(currentBot) end
        if TB.PollList then TB.PollList(true) end
    end)
    panel.refreshButton = refresh

    local npcLink = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    npcLink:SetWidth(38); npcLink:SetHeight(22)
    npcLink:SetPoint("LEFT", refresh, "RIGHT", 3, 0)
    npcLink:SetText("NPC")
    setTooltip(npcLink, "NPC errands", { "Talk, bind, learn and flights for this bot." })
    npcLink:SetScript("OnClick", function()
        if currentBot and TB.OpenNpc then TB.OpenNpc(currentBot) end
    end)
    panel.npcButton = npcLink

    local vaultLink = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    vaultLink:SetWidth(44); vaultLink:SetHeight(22)
    vaultLink:SetPoint("LEFT", npcLink, "RIGHT", 3, 0)
    vaultLink:SetText("Bank")
    setTooltip(vaultLink, "Bank and mail", { "Lists what this bot keeps in its bank and mailbox." })
    vaultLink:SetScript("OnClick", function()
        if currentBot and TB.OpenVault then TB.OpenVault(currentBot) end
    end)
    panel.vaultButton = vaultLink

    local upkeep = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    upkeep:SetWidth(50); upkeep:SetHeight(22)
    upkeep:SetPoint("LEFT", vaultLink, "RIGHT", 3, 0)
    upkeep:SetText("Upkeep")
    setTooltip(upkeep, "Upkeep", { "Restock this bot: food, drink, reagents, ammo and repairs.", "Only while the bot is online." })
    upkeep:SetScript("OnClick", function()
        if currentBot then TB.SendBotCommand("maintenance " .. currentBot) end
        if TB.PollList then TB.PollList(true) end
    end)
    panel.upkeepButton = upkeep

    local gearup = TB.StyleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    gearup:SetWidth(63); gearup:SetHeight(22)
    gearup:SetPoint("LEFT", upkeep, "RIGHT", 3, 0)
    gearup:SetText("AutoGear")
    setTooltip(gearup, "Auto-gear (bags)", { "The bot equips the best gear it already owns in its bags.", "Bags → Equip upgrades re-scans and equips new loot instead.", "Only while the bot is online." })
    gearup:SetScript("OnClick", function()
        if currentBot then TB.SendBotCommand("autogear " .. currentBot) end
        if currentBot then TB.RequestInventory(currentBot) end
    end)
    panel.gearUpButton = gearup

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
    hint:SetWidth(PW - 24); hint:SetJustifyH("LEFT")
    hint:SetText("Click an item for options. Shift-click links it in chat.")
    TB.SetTextColor(hint, color("muted"))

    itemMenu = createMenu(panel)
    panel.itemMenu = itemMenu

    -- Uncached items re-render once the client has them; a pending link
    -- order retries then, so the first click sends once cached.
    panel:SetScript("OnUpdate", function()
        if uncachedAt and now() - uncachedAt > 1 then
            uncachedAt = nil
            TB.RefreshBotPanel()
        end
        if pendingLink and not retryingLink and pendingLink.bot == currentBot then
            local name = GetItemInfo and GetItemInfo(pendingLink.id)
            if name then
                retryingLink = true
                local verb, id = pendingLink.verb, pendingLink.id
                pendingLink = nil
                if verb == "u" then TB.SendItemUse(id) else sendLinkOrder(verb, id) end
                retryingLink = false
            end
        end
    end)
    panel:Hide()
    TB.botPanel = panel
end

-- ── rendering ───────────────────────────────────────────────────────────────
local function renderHeader(inv)
    local classId = botClassId(currentBot)
    local col = classId and C.CLASS_COLORS and C.CLASS_COLORS[classId] or color("gold")
    panel.nameText:SetText(currentBot or "")
    panel.nameText:SetTextColor(col[1], col[2], col[3])
    local parts = {}
    local unit = botUnit(currentBot)
    local claimed = TB.GetClaimedEntry and TB.GetClaimedEntry(currentBot)
    if unit and UnitLevel then
        table.insert(parts, "Lvl " .. (UnitLevel(unit) or "?"))
    elseif claimed and claimed.level then
        table.insert(parts, "Lvl " .. claimed.level)
    end
    if classId and C.CLASS_NAMES then table.insert(parts, C.CLASS_NAMES[classId]) end
    if claimed then
        if claimed.gearLocked then
            table.insert(parts, "|cffffd200Gear Locked|r")
        else
            table.insert(parts, "|cff4ecb5aLeveling|r")
        end
    end
    local move = TB.MovementLabel(currentBot)
    if move then table.insert(parts, move) end
    panel.subText:SetText(table.concat(parts, " · "))
    panel.moneyText:SetText(inv and formatMoney(inv.money) or "")
    local bagCount = inv and table.getn(inv.items) or 0
    panel.tabBags:SetText(inv and ("Bags (" .. bagCount .. ")") or "Bags")
end

-- Service row: mage food/water and portals, warlock healthstones. Hidden
-- unless the cached reply says the bot can do it; asked once on open.
local function renderService()
    local snapshot = currentBot and services[currentBot] or nil
    local classId = currentBot and botClassId(currentBot) or nil
    local online = TB.GetBotState(currentBot) ~= nil or botUnit(currentBot) ~= nil
    local showFood = classId == 8 and snapshot and (snapshot.food or snapshot.water)
    local showStone = classId == 9 and snapshot and snapshot.healthstone
    local showPortal = classId == 8 and snapshot and table.getn(snapshot.portals or {}) > 0
    if panel.foodButton then
        if showFood then panel.foodButton:Show() else panel.foodButton:Hide() end
        if online then panel.foodButton:Enable() else panel.foodButton:Disable() end
    end
    if panel.healthstoneButton then
        if showStone then panel.healthstoneButton:Show() else panel.healthstoneButton:Hide() end
        if online then panel.healthstoneButton:Enable() else panel.healthstoneButton:Disable() end
    end
    if panel.portalButton then
        if showPortal then panel.portalButton:Show() else panel.portalButton:Hide() end
        if online then panel.portalButton:Enable() else panel.portalButton:Disable() end
    end
end

local function renderGear(inv)
    local equipped = inv and inv.equipped or {}
    local lowest, upgrades = nil, 0
    for slot, b in pairs(panel.gearButtons) do
        local item = equipped[slot]
        local entry = item and {
            id = item.id, bag = EQUIPPED_BAG, slot = slot, equipped = true,
            durability = item.durability, maxDurability = item.maxDurability,
        } or nil
        paintItemButton(b, entry, b.emptyTexture)
        if item and item.maxDurability and item.maxDurability > 0 then
            local pct = item.durability / item.maxDurability
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    for _, item in ipairs(inv and inv.items or {}) do
        if item.upgrade then upgrades = upgrades + 1 end
    end
    local text = inv and "" or "Loading…"
    if lowest then
        local pct = math.floor(lowest * 100 + 0.5)
        local hex = pct < 25 and "|cffff4030" or (pct < 60 and "|cffffd200" or "|cff9d9d9d")
        text = hex .. "Lowest durability " .. pct .. "%|r"
    end
    if upgrades > 0 then
        text = text .. (text ~= "" and "\n" or "") .. "|cff40ff40" .. upgrades .. " upgrade(s) in bags|r"
    end
    panel.durabilityText:SetText(text)
    if panel.model then
        local unit = botUnit(currentBot)
        if unit and panel.model.SetUnit then
            panel.model:SetUnit(unit)
            panel.model:Show()
        else
            panel.model:Hide()
        end
    end
end

local function renderBags(inv)
    local items = inv and inv.items or {}
    local perPage = BAG_COLS * BAG_ROWS
    local pages = math.max(1, math.ceil(table.getn(items) / perPage))
    if bagPage > pages then bagPage = pages end
    if bagPage < 1 then bagPage = 1 end
    for i, b in ipairs(panel.bagButtons) do
        local item = items[(bagPage - 1) * perPage + i]
        if item then paintItemButton(b, item) else b.entry = nil; b:Hide() end
    end
    if inv then
        panel.bagSummary:SetText(table.getn(items) .. " items · " .. (inv.free or 0) .. " of "
            .. (inv.total or 0) .. " slots free")
    else
        panel.bagSummary:SetText("Loading…")
    end
    panel.pageText:SetText(bagPage .. " / " .. pages)
    if bagPage > 1 then panel.prevPage:Enable() else panel.prevPage:Disable() end
    if bagPage < pages then panel.nextPage:Enable() else panel.nextPage:Disable() end
end

local function renderBehavior()
    local st = TB.GetBotState(currentBot)
    local classId = botClassId(currentBot)
    local noMana = classId and C.NO_MANA_CLASSES and C.NO_MANA_CLASSES[classId]
    local shown = 0
    for _, def in ipairs(C.BEHAVIORS or {}) do
        local key = def.key
        local chip = panel.behaviorChips[key]
        local value = st and st[key]
        local pending = currentBot and behaviorPending[norm(currentBot) .. "|" .. key]
        if chip.def.mana and noMana then
            chip:Hide()
        else
            -- Two columns, reflowed so a hidden chip leaves no hole.
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + math.mod(shown, 2) * 156,
                -98 - math.floor(shown / 2) * 30)
            shown = shown + 1
            chip:Show()
            local stateText = value == "on" and "On" or (value == "off" and "Off" or "?")
            chip:SetText(chip.def.label .. ": " .. stateText)
            if value == "on" then chip.lamp:SetTexture(0.30, 0.90, 0.45, 1)
            elseif value == "off" then chip.lamp:SetTexture(0.45, 0.45, 0.45, 1)
            else chip.lamp:SetTexture(0.95, 0.72, 0.28, 1) end
            if st and not pending then chip:Enable() else chip:Disable() end
        end
    end
end

local function renderSpells()
    local entry = currentBot and spellLists[currentBot] or nil
    local list = (entry and entry.spells) or {}
    local pages = math.max(1, math.ceil(table.getn(list) / SPELL_ROWS))
    if spellPage > pages then spellPage = pages end
    if spellPage < 1 then spellPage = 1 end
    for i, row in ipairs(panel.spellRows) do
        local spell = list[(spellPage - 1) * SPELL_ROWS + i]
        if spell then
            row.spellId = spell.id
            row.spellName = spell.name
            row:SetText(spell.name)
            row:Show()
            row:Enable()
        else
            row.spellId = 0
            row.spellName = nil
            row:SetText("")
            row:Hide()
        end
    end
    if entry and entry.pending and table.getn(list) == 0 then
        panel.spellAsk:SetText("Asking…")
        panel.spellAsk:Disable()
    else
        panel.spellAsk:SetText(table.getn(list) == 0 and "Ask for spellbook" or "Ask again")
        panel.spellAsk:Enable()
    end
    panel.spellPageText:SetText(spellPage .. " / " .. pages)
    if spellPage > 1 then panel.spellPrev:Enable() else panel.spellPrev:Disable() end
    if spellPage < pages then panel.spellNext:Enable() else panel.spellNext:Disable() end
    if panel.spellEmpty then
        if table.getn(list) == 0 then panel.spellEmpty:Show() else panel.spellEmpty:Hide() end
    end
end

-- One filter for known and missing rows: the made item name for known
-- recipes, the made item and the recipe item for missing ones.
-- Spell/enchant names are not searchable in 1.12 (no spell-name lookup
-- exists on the client).
local function profMatches(recipe, missing, query)
    if not query or query == "" then return true end
    query = string.lower(query)
    if recipe then
        local id = tonumber(recipe.item) or 0
        if id > 0 and GetItemInfo then
            local name = GetItemInfo(id)
            if name and string.find(string.lower(name), query, 1, true) then return true end
        end
        return false
    end
    if missing then
        -- Both the made item and the recipe item identify the row: the
        -- label names the product, the source names what to hand over.
        for _, id in ipairs({ tonumber(missing.item) or 0, tonumber(missing.recipeItem) or 0 }) do
            if id > 0 and GetItemInfo then
                local name = GetItemInfo(id)
                if name and string.find(string.lower(name), query, 1, true) then return true end
            end
        end
        return false
    end
    return true
end

-- Flat row list behind the pager: one header row per skill with a text
-- skill bar, known recipes under it, then the collapsed "Not learned
-- yet (N)" group when the skill has missing recipes.
local function profFlatRows()
    local flat = {}
    local snapshot = currentBot and professions[currentBot] or nil
    if not snapshot then return flat end
    local knownBySkill, missingBySkill = {}, {}
    for _, recipe in ipairs(snapshot.recipes or {}) do
        local list = knownBySkill[recipe.skill]
        if not list then list = {}; knownBySkill[recipe.skill] = list end
        if profMatches(recipe, nil, profSearch) then table.insert(list, recipe) end
    end
    for _, entry in ipairs(snapshot.missing or {}) do
        local list = missingBySkill[entry.skill]
        if not list then list = {}; missingBySkill[entry.skill] = list end
        if profMatches(nil, entry, profSearch) then table.insert(list, entry) end
    end
    for _, skill in ipairs(snapshot.skills or {}) do
        table.insert(flat, { kind = "skill", skill = skill })
        for _, recipe in ipairs(knownBySkill[skill.skill] or {}) do
            table.insert(flat, { kind = "recipe", skill = skill, recipe = recipe })
        end
        local missing = missingBySkill[skill.skill] or {}
        if table.getn(missing) > 0 then
            table.insert(flat, { kind = "group", skill = skill, count = table.getn(missing) })
            if not profCollapsed[skill.skill] then
                for _, entry in ipairs(missing) do
                    table.insert(flat, { kind = "missing", skill = skill, missing = entry })
                end
            end
        end
    end
    return flat
end

local function renderProfs()
    local snapshot = currentBot and professions[currentBot] or nil
    local flat = (snapshot and profFlatRows()) or {}
    local perPage = table.getn(panel.profRows)
    local pages = math.max(1, math.ceil(table.getn(flat) / perPage))
    if profPage > pages then profPage = pages end
    if profPage < 1 then profPage = 1 end
    for i, row in ipairs(panel.profRows) do
        local entry = flat[(profPage - 1) * perPage + i]
        row.group = nil
        row.groupSkill = nil
        row.recipe = nil
        if not entry then
            row:Hide()
        elseif entry.kind == "skill" then
            local skill = entry.skill
            local max = tonumber(skill.max) or 0
            local filled = max > 0 and math.floor((tonumber(skill.value) or 0) / max * 10 + 0.5) or 0
            row.icon:SetTexture(nil)
            row.label:SetText(TB.ProfessionSkillName(skill.skill) .. " " .. tostring(skill.value)
                .. "/" .. tostring(skill.max) .. " [" .. string.rep("|", filled)
                .. string.rep(".", 10 - filled) .. "]")
            row.label:SetTextColor(0.95, 0.72, 0.28)
            row.craft:Hide()
            row:Show()
            row:Enable()
        elseif entry.kind == "group" then
            row.icon:SetTexture(nil)
            local open = not profCollapsed[entry.skill.skill]
            row.label:SetText((open and "- " or "+ ") .. "Not learned yet (" .. entry.count .. ")")
            row.label:SetTextColor(0.62, 0.60, 0.56)
            row.group = true
            row.groupSkill = entry.skill.skill
            row.craft:Hide()
            row:Show()
            row:Enable()
        else
            local recipe = entry.recipe
            local missing = entry.missing
            local skillValue = tonumber(entry.skill.value) or 0
            -- Missing rows name the made item (what the recipe teaches);
            -- the source suffix says Trainer or names the recipe item.
            local id = (recipe and (tonumber(recipe.item) or 0))
                or (missing and (tonumber(missing.item) or 0)) or 0
            local name, texture = nil, nil
            if id > 0 then
                local itemName, _, _, itemTexture = itemInfo(id)
                name, texture = itemName, itemTexture
                if not texture then requestItem(id) end
                if not name then name = "item #" .. tostring(id) end
                texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
            else
                name = (missing and "spell #") or "enchant #"
                name = name .. tostring((recipe and recipe.spell) or (missing and missing.spell) or 0)
                texture = "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            row.icon:SetTexture(texture)
            if recipe then
                local colorName = TB.ProfessionRecipeColor(recipe, skillValue) or "orange"
                row.label:SetText(name or "")
                if colorName == "orange" then row.label:SetTextColor(1, 0.5, 0)
                elseif colorName == "yellow" then row.label:SetTextColor(1, 0.82, 0.1)
                elseif colorName == "green" then row.label:SetTextColor(0.30, 0.90, 0.45)
                else row.label:SetTextColor(0.62, 0.60, 0.56) end
            else
                row.label:SetText(name or "")
                row.label:SetTextColor(0.45, 0.45, 0.45)
            end
            row.recipe = recipe
            if missing then
                row.label:SetText((name or "") .. " (" .. tostring(missing.reqSkill)
                    .. ", " .. TB.ProfessionMissingSourceText(missing) .. ")")
            end
            -- Without the order feature or the right to give orders the
            -- button hides instead; per the server verdict a
            -- refused recipe shows the button disabled with the plain
            -- reason in its tooltip.
            local canFeature = TB.HasOrderCapability and TB.HasOrderCapability()
                and TB.CanGiveOrders and TB.CanGiveOrders()
            if recipe and canFeature and TB.ProfessionRecipeOrderable(recipe) then
                row.craft:Show()
                row.craft:Enable()
            elseif recipe and canFeature then
                row.craft:Show()
                row.craft:Disable()
            else
                row.craft:Hide()
            end
            row:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                if recipe and (tonumber(recipe.item) or 0) > 0 then
                    if GameTooltip.SetHyperlink then
                        GameTooltip:SetHyperlink("item:" .. recipe.item .. ":0:0:0")
                    else
                        GameTooltip:SetText(name or "")
                    end
                elseif recipe then
                    if GameTooltip.SetHyperlink then
                        GameTooltip:SetHyperlink("enchant:" .. recipe.spell)
                    else
                        GameTooltip:SetText(name or "")
                    end
                elseif missing and (tonumber(missing.recipeItem) or 0) > 0 then
                    if GameTooltip.SetHyperlink then
                        GameTooltip:SetHyperlink("item:" .. missing.recipeItem .. ":0:0:0")
                    else
                        GameTooltip:SetText(name or "")
                    end
                else
                    GameTooltip:SetText(name or "")
                end
                if recipe and not TB.ProfessionRecipeOrderable(recipe) then
                    local reason = TB.ProfessionRecipeOrderReason(recipe)
                    if reason then GameTooltip:AddLine(reason, 0.9, 0.9, 0.9, 1) end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:Show()
            row:Enable()
        end
    end
    if not snapshot then
        if TB.HasProfessionsCapability() then
            panel.profEmpty:SetText("Open this view to ask the bot for its professions.")
        else
            panel.profEmpty:SetText("The server does not list professions (no capability).")
        end
        panel.profEmpty:Show()
    elseif table.getn(flat) == 0 then
        panel.profEmpty:SetText(profSearch ~= "" and "No recipes match the search." or "No professions.")
        panel.profEmpty:Show()
    else
        panel.profEmpty:Hide()
    end
    panel.profPageText:SetText(profPage .. " / " .. pages)
    if profPage > 1 then panel.profPrev:Enable() else panel.profPrev:Disable() end
    if profPage < pages then panel.profNext:Enable() else panel.profNext:Disable() end
end

function TB.RefreshBotPanel()
    if not panel or not panel:IsVisible() or not currentBot then return end
    local inv = TB.GetInventory(currentBot)
    renderHeader(inv)
    panel.gear:Hide(); panel.bags:Hide(); panel.behavior:Hide(); panel.spells:Hide(); panel.profs:Hide()
    panel.tabGear:Enable(); panel.tabBags:Enable(); panel.tabBehavior:Enable(); panel.tabSpells:Enable(); panel.tabProfs:Enable()
    if currentView == "bags" then
        panel.bags:Show(); panel.tabBags:Disable()
        renderBags(inv)
    elseif currentView == "behavior" then
        panel.behavior:Show(); panel.tabBehavior:Disable()
        renderBehavior()
    elseif currentView == "spells" then
        panel.spells:Show(); panel.tabSpells:Disable()
        renderSpells()
    elseif currentView == "profs" then
        panel.profs:Show(); panel.tabProfs:Disable()
        -- Ask once on open (no cache yet); Refresh and the view's own
        -- button re-ask. Never on a timer, never on hover.
        if not professions[currentBot] then TB.RequestProfessions(currentBot) end
        renderProfs()
    else
        panel.gear:Show(); panel.tabGear:Disable()
        renderGear(inv)
    end
    renderService()
    local online = TB.GetBotState(currentBot) ~= nil or botUnit(currentBot) ~= nil
    if online then panel.tradeButton:Enable() else panel.tradeButton:Disable() end
    if online then panel.upkeepButton:Enable() else panel.upkeepButton:Disable() end
    if online then panel.gearUpButton:Enable() else panel.gearUpButton:Disable() end
    if panel.npcButton then if online then panel.npcButton:Enable() else panel.npcButton:Disable() end end
    if panel.vaultButton then if online then panel.vaultButton:Enable() else panel.vaultButton:Disable() end end
    if panel.sweepButton then
        if inv then panel.sweepButton:Enable() else panel.sweepButton:Disable() end
    end
end

function TB.OpenBotPanel(name, view)
    name = norm(name)
    if not name then return false end
    if not panel then createPanel() end
    if currentBot and currentBot ~= name then TB.SetSpellPending(currentBot, false) end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if TB.SetMode then TB.SetMode("full") end
    if currentBot ~= name then bagPage = 1; spellPage = 1; profPage = 1; profSearch = "" end
    currentBot = name
    if view then currentView = view end
    hideMenu()
    panel:ClearAllPoints()
    if TB.frame then
        -- Open on the side of the main window that has room.
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + PW + 4) * scale > screen then
            panel:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            panel:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    panel:Show()
    TB.RefreshBotPanel()
    TB.RequestInventory(name)
    -- Ask once for a mage or warlock with no cached reply; Refresh asks
    -- again. Never on a timer, never on hover. The ask travels with the
    -- inventory request, so one open is one extra line at most.
    if TB.ServiceWanted(name) and not services[name] then TB.RequestService(name) end
    return true
end

function TB.CloseBotPanel()
    hideMenu()
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if panel then panel:Hide() end
end

-- ── trade window follow-up ──────────────────────────────────────────────────
-- "Give to me" without an open trade makes the bot open one first; once the
-- window shows, the same order is sent again and the item goes in.
local tradeFrame = CreateFrame("Frame", "TortoiseBotsManagerTradeWatcher")
tradeFrame:RegisterEvent("TRADE_SHOW")
tradeFrame:RegisterEvent("TRADE_CLOSED")
tradeFrame:SetScript("OnEvent", function()
    if event == "TRADE_SHOW" then
        local partner = UnitName and norm(UnitName("NPC")) or nil
        local give = pendingGive
        if give and partner == give.bot then
            pendingGive = nil
            TB.SendBotCommand("item " .. give.bot .. " give " .. give.bag .. " " .. give.slot)
        end
    elseif event == "TRADE_CLOSED" then
        pendingGive = nil
        -- Traded items change the bags: reload what the panel shows.
        if TB.GetBotPanelBot() then
            TB.inventoryRefreshBot = TB.GetBotPanelBot()
            TB.RequestInventorySoon()
        end
    end
end)

local refreshFrame
function TB.RequestInventorySoon()
    if not refreshFrame then
        refreshFrame = CreateFrame("Frame", "TortoiseBotsManagerInventoryRefresh")
        refreshFrame:SetScript("OnUpdate", function()
            this.elapsed = (this.elapsed or 0) + (arg1 or 0)
            if this.elapsed < 1 then return end
            this:Hide()
            local bot = TB.inventoryRefreshBot
            TB.inventoryRefreshBot = nil
            if bot and TB.GetBotPanelBot() == bot then TB.RequestInventory(bot) end
        end)
    end
    refreshFrame.elapsed = 0
    refreshFrame:Show()
end
