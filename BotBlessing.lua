-- TortoiseBotsManager/BotBlessing.lua
-- Paladin blessing assignment board: one row per paladin bot, one column per
-- class present (plus an Aura column when `choice` is available), Auto assign /
-- Clear / Refresh actions, missing-blessing hint, and per-player exceptions
-- when `blessing-player` is available.
--
--   .bot blessing <bot|party|raid> status
--     -> TBM:BLESSING|<bot>|warrior=<b>,...,druid=<b>,known=<b>+<b>[,players=<Name>:<b>+...]
--   .bot blessing <bot> <class> <blessing|auto>
--   .bot blessing <bot|party|raid> player <name> <blessing|auto>
-- <b> is auto or might, wisdom, kings, salvation, sanctuary, light.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local CAP = "blessing"
local PLAYER_CAP = "blessing-player"
local NAME_W = 84
local CELL_W = 54
local CELL_H = 34
local AURA_W = 88
local ROW_STEP = 38
local MAX_ROWS = 8
local MAX_EXCEPTIONS = 6
local EXC_ROW_H = 18
local TOOLBAR_TOP = 32
local HEAD_TOP = 58
local ROWS_TOP = 94
local PAD = 12
local WIN_W_MAX = PAD * 2 + NAME_W + 9 * CELL_W + AURA_W

local SHORT_BLESSING = {
    might = "Might",
    wisdom = "Wisdom",
    kings = "Kings",
    salvation = "Salv",
    sanctuary = "Sanc",
    light = "Light",
}

local FULL_BLESSING = {
    auto = "Auto (paladin chooses)",
    might = "Blessing of Might",
    wisdom = "Blessing of Wisdom",
    kings = "Blessing of Kings",
    salvation = "Blessing of Salvation",
    sanctuary = "Blessing of Sanctuary",
    light = "Blessing of Light",
}

local CLASS_PRIORITY = {
    warrior = { "might", "kings", "sanctuary", "light" },
    rogue   = { "might", "kings", "salvation", "light", "sanctuary" },
    hunter  = { "might", "kings", "salvation", "wisdom", "light", "sanctuary" },
    mage    = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    warlock = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    priest  = { "wisdom", "kings", "salvation", "light", "sanctuary" },
    paladin = { "wisdom", "kings", "might", "salvation", "light", "sanctuary" },
    druid   = { "wisdom", "kings", "might", "salvation", "light", "sanctuary" },
    shaman  = { "wisdom", "kings", "might", "salvation", "light", "sanctuary" },
}

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── model ───────────────────────────────────────────────────────────────────
-- [paladin] = { classes = { warrior = "kings", ... }, known = { "might", ... }, players = { [name] = "kings" } }
local blessings = {}
local pendingCell = {} -- [paladin] = true while a cell order waits for its reply
local cachedMissingText = ""
local win
local excMenu

function TB.HasBlessingCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

function TB.HasBlessingPlayerCapability()
    return TB.HasServerCapability and TB.HasServerCapability(PLAYER_CAP) or false
end

function TB.GetBlessings(name)
    name = norm(name)
    return name and blessings[name] or nil
end

function TB.SetBlessings(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    blessings[name] = snapshot
    pendingCell[name] = nil
    if TB.RefreshBlessings then TB.RefreshBlessings() end
end

local function validBlessing(value)
    if value == "auto" then return true end
    for _, b in ipairs(C.BLESSINGS) do
        if b == value then return true end
    end
    return false
end

-- TBM:BLESSING|<paladin>|warrior=<b>,...,druid=<b>,known=<b>+<b>[,players=<Name>:<b>+...].
-- Every class must carry a valid value; `known` may be empty and, when
-- missing, reads as nil (every blessing is then offered).
function TB.ParseBlessingLine(msg)
    if string.sub(msg or "", 1, 13) ~= "TBM:BLESSING|" then return nil end
    local text = string.sub(msg, 14)
    local bar = string.find(text, "|", 1, true)
    if not bar then return nil end
    local name = norm(string.sub(text, 1, bar - 1))
    if not name or name == "" then return nil end
    local rest = string.sub(text, bar + 1)
    local extra = string.find(rest, "|", 1, true)
    if extra then rest = string.sub(rest, 1, extra - 1) end
    local classes, known, players = {}, nil, {}
    for pair in string.gfind(rest, "[^,]+") do
        local _, _, key, rawVal = string.find(pair, "^%s*(%a+)%s*=%s*(.-)%s*$")
        if key then
            key = string.lower(key)
            local value = string.lower(rawVal)
            if key == "known" then
                known = {}
                for item in string.gfind(value, "[^+]+") do
                    item = TB.Trim(item)
                    if validBlessing(item) and item ~= "auto" then table.insert(known, item) end
                end
            elseif key == "players" then
                for item in string.gfind(rawVal, "[^+]+") do
                    local _, _, pname, pbless = string.find(item, "^%s*([^:]+):(%a+)%s*$")
                    if pname and pbless then
                        pname = norm(TB.Trim(pname))
                        pbless = string.lower(pbless)
                        if pname and pname ~= "" and validBlessing(pbless) and pbless ~= "auto" then
                            players[pname] = pbless
                        end
                    end
                end
            else
                for _, cls in ipairs(C.BLESSING_CLASSES) do
                    if cls.word == key then
                        if not validBlessing(value) then return nil end
                        classes[key] = value
                    end
                end
            end
        end
    end
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if not classes[cls.word] then return nil end
    end
    return { name = name, classes = classes, known = known, players = players }
end

function TB.ConsumeBlessingLine(msg)
    local snapshot = TB.ParseBlessingLine(msg)
    if not snapshot then return false end
    TB.SetBlessings(snapshot.name, {
        classes = snapshot.classes,
        known = snapshot.known,
        players = snapshot.players or {},
    })
    return true
end

-- Auto first, then the blessings that paladin has trained in the usual order.
function TB.BlessingOptions(known)
    local out = { "auto" }
    for _, b in ipairs(C.BLESSINGS) do
        local keep = known == nil
        for _, k in ipairs(known or {}) do
            if k == b then keep = true end
        end
        if keep then table.insert(out, b) end
    end
    return out
end

-- The next (step 1) or previous (step -1) blessing in the cycle; a value
-- the paladin cannot cast any more starts from Auto.
function TB.NextBlessing(current, known, step)
    local options = TB.BlessingOptions(known)
    local count = table.getn(options)
    local at = 1
    for i, b in ipairs(options) do
        if b == current then at = i end
    end
    return options[math.mod(at - 1 + step + count, count) + 1]
end

function TB.BlessingLabel(value)
    if value == "auto" then return "Auto" end
    return value and C.BLESSING_LABELS[value] or "?"
end

-- Pure auto-assignment planner: spreads trained blessings across paladins so
-- each present class gets as many distinct useful blessings as possible.
-- `snapshots` maps paladin name -> { known = { ... } or nil }.
-- `present` maps classId -> true (nil assigns all classes).
function TB.ComputeAutoBlessings(paladins, snapshots, present)
    local plan, knows, knownCount = {}, {}, {}
    for _, p in ipairs(paladins or {}) do
        plan[p] = {}
        knows[p] = {}
        local snap = snapshots and snapshots[p]
        local klist = snap and snap.known
        local count = 0
        if klist == nil then
            for _, b in ipairs(C.BLESSINGS) do
                knows[p][b] = true
                count = count + 1
            end
        else
            for _, b in ipairs(klist) do
                if validBlessing(b) and b ~= "auto" and not knows[p][b] then
                    knows[p][b] = true
                    count = count + 1
                end
            end
        end
        knownCount[p] = count
        for _, cls in ipairs(C.BLESSING_CLASSES) do
            plan[p][cls.word] = "auto"
        end
    end
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if present == nil or present[cls.id] then
            local taken = {}
            local prio = CLASS_PRIORITY[cls.word] or {}
            for _, b in ipairs(prio) do
                local bestP, bestCount
                for _, p in ipairs(paladins or {}) do
                    if not taken[p] and knows[p][b] then
                        local c = knownCount[p]
                        if not bestP or c < bestCount then
                            bestP, bestCount = p, c
                        end
                    end
                end
                if bestP then
                    plan[bestP][cls.word] = b
                    taken[bestP] = true
                end
            end
        end
    end
    return plan
end

-- ── commands ────────────────────────────────────────────────────────────────
function TB.BuildBlessingCommand(bot, word, value)
    bot = norm(bot)
    if not bot or not validBlessing(value) then return nil end
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if cls.word == word then return "blessing " .. bot .. " " .. word .. " " .. value end
    end
    return nil
end

function TB.BuildBlessingPlayerCommand(bot, targetName, value)
    local scope = string.lower(bot or "")
    if scope ~= "party" and scope ~= "raid" then scope = norm(bot) end
    targetName = norm(targetName)
    if not scope or scope == "" or not targetName or targetName == "" then return nil end
    if string.find(targetName, "%s") or not validBlessing(value) then return nil end
    return "blessing " .. scope .. " player " .. targetName .. " " .. value
end

local function groupUnits()
    local out = {}
    local raid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do table.insert(out, "raid" .. i) end
    else
        table.insert(out, "player")
        local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, party do table.insert(out, "party" .. i) end
    end
    return out
end

function TB.BlessingScope()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "raid" end
    return "party"
end

-- The paladin bots of the group (sorted) and the class ids present in it.
function TB.GetBlessingGroup()
    local paladins, present = {}, {}
    local ids = C.CLASS_NAME_TO_ID or {}
    for _, unit in ipairs(groupUnits()) do
        local name = UnitName and norm(UnitName(unit))
        if name and UnitClass then
            local className, classFile = UnitClass(unit)
            local classId = ids[classFile or ""] or ids[className or ""]
            if classId then
                present[classId] = true
                if classId == 2 and TB.GetBotState and TB.GetBotState(name) then
                    table.insert(paladins, name)
                end
            end
        end
    end
    table.sort(paladins)
    return paladins, present
end

local function groupMembers()
    local out, seen = {}, {}
    local ids = C.CLASS_NAME_TO_ID or {}
    local wordById = {}
    for _, cls in ipairs(C.BLESSING_CLASSES) do wordById[cls.id] = cls.word end
    for _, unit in ipairs(groupUnits()) do
        local name = UnitName and norm(UnitName(unit))
        if name and not seen[name] and UnitClass then
            local className, classFile = UnitClass(unit)
            local classId = ids[classFile or ""] or ids[className or ""]
            local word = classId and wordById[classId]
            if word then
                seen[name] = true
                table.insert(out, { unit = unit, name = name, classId = classId, word = word })
            end
        end
    end
    return out
end

function TB.BlessingAvailable()
    if not TB.HasBlessingCapability() then return false end
    return table.getn((TB.GetBlessingGroup())) > 0
end

function TB.RequestBlessings()
    local ok = TB.SendBotCommand("blessing " .. TB.BlessingScope() .. " status")
    if TB.HasChoiceCapability and TB.HasChoiceCapability() and TB.RequestChoices then
        TB.RequestChoices(TB.BlessingScope())
    end
    return ok
end

function TB.SendBlessing(bot, word, value)
    local cmd = TB.BuildBlessingCommand(bot, word, value)
    if not cmd then return false end
    pendingCell[norm(bot)] = true
    if TB.RefreshBlessings then TB.RefreshBlessings() end
    return TB.SendBotCommand(cmd)
end

function TB.SendBlessingPlayer(bot, targetName, value)
    local cmd = TB.BuildBlessingPlayerCommand(bot, targetName, value)
    if not cmd then return false end
    local lower = string.lower(bot or "")
    if lower ~= "party" and lower ~= "raid" then
        pendingCell[norm(bot)] = true
        if TB.RefreshBlessings then TB.RefreshBlessings() end
    end
    return TB.SendBotCommand(cmd)
end

-- Left-click moves to the next blessing, right-click to the previous one.
function TB.CycleBlessing(bot, word, step)
    local snapshot = TB.GetBlessings(bot)
    if not snapshot or pendingCell[norm(bot)] then return false end
    return TB.SendBlessing(bot, word, TB.NextBlessing(snapshot.classes[word], snapshot.known, step))
end

local function cycleAura(bot, step)
    if not TB.GetChoice or not TB.ChoiceOptions or not TB.SendChoice then return false end
    local snap = TB.GetChoice(bot, "aura")
    if not snap then return false end
    local options = TB.ChoiceOptions("aura", snap.known)
    local count = table.getn(options)
    if count == 0 then return false end
    local at = 1
    for i, v in ipairs(options) do
        if v == snap.value then at = i end
    end
    local nextVal = options[math.mod(at - 1 + step + count, count) + 1]
    return TB.SendChoice(bot, "aura", nextVal)
end

function TB.ApplyAutoBlessings()
    local paladins, present = TB.GetBlessingGroup()
    if table.getn(paladins) == 0 then return 0 end
    local snapshots = {}
    for _, p in ipairs(paladins) do snapshots[p] = TB.GetBlessings(p) end
    local plan = TB.ComputeAutoBlessings(paladins, snapshots, present)
    local sent = 0
    for _, p in ipairs(paladins) do
        local cur = snapshots[p]
        if cur then
            for _, cls in ipairs(C.BLESSING_CLASSES) do
                if present[cls.id] then
                    local target = plan[p] and plan[p][cls.word]
                    if target and cur.classes[cls.word] ~= target then
                        if TB.SendBlessing(p, cls.word, target) then sent = sent + 1 end
                    end
                end
            end
        end
    end
    return sent
end

function TB.ClearBlessings()
    local paladins = TB.GetBlessingGroup()
    local sent = 0
    for _, p in ipairs(paladins) do
        local cur = TB.GetBlessings(p)
        if cur then
            for _, cls in ipairs(C.BLESSING_CLASSES) do
                if cur.classes[cls.word] and cur.classes[cls.word] ~= "auto" then
                    if TB.SendBlessing(p, cls.word, "auto") then sent = sent + 1 end
                end
            end
        end
    end
    return sent
end

-- ── missing-blessing check ──────────────────────────────────────────────────
local function unitHasBlessing(unit, blessing)
    if not UnitBuff then return false end
    local normalTex = C.BLESSING_ICONS[blessing] and string.lower(C.BLESSING_ICONS[blessing])
    local greaterPat = "greaterblessingof" .. blessing
    for b = 1, 32 do
        local tex = UnitBuff(unit, b)
        if not tex then break end
        local lower = string.lower(tex)
        if (normalTex and lower == normalTex) or string.find(lower, greaterPat, 1, true) then
            return true
        end
    end
    return false
end

function TB.ComputeMissingBlessings()
    local paladins = TB.GetBlessingGroup()
    local hasOrders, missing = false, {}
    local allowPlayer = TB.HasBlessingPlayerCapability()
    for _, m in ipairs(groupMembers()) do
        local dead = (UnitIsDead and UnitIsDead(m.unit)) or (UnitIsGhost and UnitIsGhost(m.unit))
        if not dead then
            local wanted, list = {}, {}
            for _, p in ipairs(paladins) do
                local snap = TB.GetBlessings(p)
                if snap then
                    local val = (allowPlayer and snap.players and snap.players[m.name]) or snap.classes[m.word]
                    if val and val ~= "auto" and not wanted[val] then
                        wanted[val] = true
                        hasOrders = true
                        table.insert(list, val)
                    end
                end
            end
            local lacking = {}
            for _, b in ipairs(list) do
                if not unitHasBlessing(m.unit, b) then
                    table.insert(lacking, SHORT_BLESSING[b] or TB.BlessingLabel(b))
                end
            end
            if table.getn(lacking) > 0 then
                table.insert(missing, m.name .. " (" .. table.concat(lacking, ", ") .. ")")
            end
        end
    end
    if not hasOrders then return "" end
    if table.getn(missing) == 0 then return "All ordered blessings active." end
    if table.getn(missing) > 3 then
        local shown = {}
        for i = 1, 3 do table.insert(shown, missing[i]) end
        return "Missing: " .. table.concat(shown, ", ") .. " +" .. (table.getn(missing) - 3) .. " more"
    end
    return "Missing: " .. table.concat(missing, ", ")
end

function TB.RefreshMissingBlessings()
    cachedMissingText = TB.ComputeMissingBlessings()
    if TB.RefreshBlessings then TB.RefreshBlessings() end
end

function TB.CollectBlessingExceptions()
    local paladins = TB.GetBlessingGroup()
    local out = {}
    for _, p in ipairs(paladins) do
        local snap = TB.GetBlessings(p)
        if snap and snap.players then
            for pname, b in pairs(snap.players) do
                if b and b ~= "auto" then
                    table.insert(out, { player = pname, paladin = p, blessing = b })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.player ~= b.player then return a.player < b.player end
        return a.paladin < b.paladin
    end)
    return out
end

-- ACK routing from Comms. Returns true when handled.
function TB.OnBlessingAck(packet)
    local intent = packet.intent or ""
    if intent == "blessing status" then
        if TB.SetStatus then TB.SetStatus("Blessings · " .. (packet.count or 0) .. " paladin(s)", "ok") end
        return true
    end
    if intent ~= "blessing" then return false end
    local _, _, bot = string.find(packet.scope or "", "^bot:(.+)$")
    bot = norm(bot)
    if bot then pendingCell[bot] = nil end
    local _, _, word, value = string.find(packet.executor or "", "^(%a+)=(%a+)$")
    if TB.SetStatus then
        local text = "Blessing set"
        if bot and word and value then
            text = bot .. ": " .. string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
                .. " → " .. TB.BlessingLabel(value)
        end
        TB.SetStatus(text, "ok")
    end
    if TB.RefreshBlessings then TB.RefreshBlessings() end
    return true
end

function TB.OnBlessingError(packet)
    if packet.intent ~= "blessing" then return end
    for bot in pairs(pendingCell) do pendingCell[bot] = nil end
    if TB.RefreshBlessings then TB.RefreshBlessings() end
end

-- ── exception menu ──────────────────────────────────────────────────────────
local function addBlessingMenuButtons(paladin, targetName, level)
    local snap = TB.GetBlessings(paladin)
    local opts = TB.BlessingOptions(snap and snap.known)
    for _, b in ipairs(opts) do
        local blessing = b
        if blessing ~= "auto" then
            UIDropDownMenu_AddButton({
                text = SHORT_BLESSING[blessing] or TB.BlessingLabel(blessing),
                checked = (snap and snap.players and snap.players[targetName] == blessing) and 1 or nil,
                func = function() TB.SendBlessingPlayer(paladin, targetName, blessing) end,
            }, level or 1)
        end
    end
end

local function openExceptionMenu(anchor)
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return end
    local paladins = TB.GetBlessingGroup()
    if table.getn(paladins) == 0 then return end
    local targetName = UnitExists and UnitExists("target") and UnitName and norm(UnitName("target"))
    local inGroup = false
    if targetName then
        for _, m in ipairs(groupMembers()) do
            if m.name == targetName then inGroup = true break end
        end
    end
    if not inGroup then targetName = nil end
    if not excMenu then
        excMenu = CreateFrame("Frame", "TortoiseBotsManagerBlessingExcMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(excMenu, function()
        local level = (getglobal and getglobal("UIDROPDOWNMENU_MENU_LEVEL")) or 1
        local val = getglobal and getglobal("UIDROPDOWNMENU_MENU_VALUE")
        if targetName then
            if level == 1 then
                if table.getn(paladins) == 1 then
                    addBlessingMenuButtons(paladins[1], targetName, 1)
                else
                    for _, p in ipairs(paladins) do
                        local pal = p
                        UIDropDownMenu_AddButton({ text = pal, hasArrow = 1, value = pal }, 1)
                    end
                end
            elseif level == 2 and val then
                addBlessingMenuButtons(val, targetName, 2)
            end
        else
            if level == 1 then
                for _, m in ipairs(groupMembers()) do
                    local member = m.name
                    UIDropDownMenu_AddButton({ text = member, hasArrow = 1, value = member }, 1)
                end
            elseif level == 2 and val then
                if table.getn(paladins) == 1 then
                    addBlessingMenuButtons(paladins[1], val, 2)
                else
                    for _, p in ipairs(paladins) do
                        local pal = p
                        UIDropDownMenu_AddButton({ text = pal, hasArrow = 1, value = val .. "|" .. pal }, 2)
                    end
                end
            elseif level == 3 and val then
                local _, _, mname, pal = string.find(val, "^([^|]+)|(.+)$")
                if mname and pal then addBlessingMenuButtons(pal, mname, 3) end
            end
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, excMenu, anchor or "cursor", 0, 0)
end

-- ── window ──────────────────────────────────────────────────────────────────
local function shortAuraLabel(value)
    if not value or value == "" then return "…" end
    if value == "auto" then return "Auto" end
    local label = TB.ChoiceLabel and TB.ChoiceLabel("aura", value) or value
    label = string.gsub(label, " Aura$", "")
    label = string.gsub(label, " Resistance$", " Res")
    return label
end

local function createCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetWidth(CELL_W - 4); cell:SetHeight(CELL_H)
    cell:EnableMouse(true)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.border:SetAllPoints(cell)
    cell.border:SetTexture(0.13, 0.13, 0.15, 0.85)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetWidth(16); cell.icon:SetHeight(16)
    cell.icon:SetPoint("TOP", cell, "TOP", 0, -3)
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.label:SetPoint("BOTTOM", cell, "BOTTOM", 0, 3)
    cell.label:SetWidth(CELL_W - 6)
    cell.label:SetJustifyH("CENTER")
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(cell)
    hl:SetTexture(1, 1, 1, 0.15)
    cell:SetScript("OnEnter", function()
        local snapshot = TB.GetBlessings(this.bot)
        local val = snapshot and snapshot.classes[this.word]
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText((this.bot or "") .. " → " .. (this.className or ""))
        GameTooltip:AddLine("Now: " .. (FULL_BLESSING[val] or TB.BlessingLabel(val)), 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Left-click: next · Right-click: previous", 0.62, 0.60, 0.56, 1)
        GameTooltip:AddLine("Auto lets the paladin choose.", 0.62, 0.60, 0.56, 1)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell:SetScript("OnClick", function()
        if this.bot and this.word then
            TB.CycleBlessing(this.bot, this.word, arg1 == "RightButton" and -1 or 1)
        end
    end)
    return cell
end

local function createAuraCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetWidth(AURA_W - 4); cell:SetHeight(CELL_H)
    cell:EnableMouse(true)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.border:SetAllPoints(cell)
    cell.border:SetTexture(0.13, 0.13, 0.15, 0.85)
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.label:SetPoint("CENTER", cell, "CENTER", 0, 0)
    cell.label:SetWidth(AURA_W - 10)
    cell.label:SetJustifyH("CENTER")
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(cell)
    hl:SetTexture(1, 1, 1, 0.15)
    cell:SetScript("OnEnter", function()
        local snap = TB.GetChoice and TB.GetChoice(this.bot, "aura")
        local val = snap and snap.value
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText((this.bot or "") .. " → Aura")
        GameTooltip:AddLine("Now: " .. (TB.ChoiceLabel and TB.ChoiceLabel("aura", val) or "?"), 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Left-click: next · Right-click: previous", 0.62, 0.60, 0.56, 1)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell:SetScript("OnClick", function()
        if this.bot then cycleAura(this.bot, arg1 == "RightButton" and -1 or 1) end
    end)
    return cell
end

local function setBtnTooltip(btn, title, line)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeToolbarButton(parent, label, width, x, tip)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -TOOLBAR_TOP)
    b:SetText(label)
    if tip then setBtnTooltip(b, label, tip) end
    return b
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerBlessings", TB.frame or UIParent)
    win:SetWidth(340); win:SetHeight(180)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerBlessings") end
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -9)
    title:SetText("Blessings")
    TB.StyleTitle(title, 14)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseBlessings() end)

    win.autoBtn = makeToolbarButton(win, "Auto assign", 86, PAD,
        "Spreads trained blessings across paladins for each class.")
    win.autoBtn:SetScript("OnClick", function() TB.ApplyAutoBlessings() end)
    win.clearBtn = makeToolbarButton(win, "Clear", 54, PAD + 92,
        "Resets every class cell back to Auto.")
    win.clearBtn:SetScript("OnClick", function() TB.ClearBlessings() end)
    win.refreshBtn = makeToolbarButton(win, "Refresh", 66, PAD + 152,
        "Re-asks the server and checks who is missing a blessing.")
    win.refreshBtn:SetScript("OnClick", function()
        TB.RequestBlessings()
        TB.RefreshMissingBlessings()
    end)

    win.heads = {}
    for i = 1, table.getn(C.BLESSING_CLASSES) do
        local head = CreateFrame("Button", nil, win)
        head:SetWidth(CELL_W - 4); head:SetHeight(32)
        head.icon = head:CreateTexture(nil, "ARTWORK")
        head.icon:SetWidth(18); head.icon:SetHeight(18)
        head.icon:SetPoint("TOP", head, "TOP", 0, 0)
        head.label = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head.label:SetPoint("BOTTOM", head, "BOTTOM", 0, 0)
        head.label:SetWidth(CELL_W - 4)
        head.label:SetJustifyH("CENTER")
        head:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.className or "")
            GameTooltip:Show()
        end)
        head:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win.heads[i] = head
    end

    win.auraHead = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.auraHead:SetWidth(AURA_W - 4); win.auraHead:SetJustifyH("CENTER")
    win.auraHead:SetText("Aura")
    TB.SetTextColor(win.auraHead, color("gold"))

    win.rows = {}
    for r = 1, MAX_ROWS do
        local row = { cells = {} }
        row.name = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetWidth(NAME_W - 4); row.name:SetJustifyH("LEFT")
        for c = 1, table.getn(C.BLESSING_CLASSES) do
            row.cells[c] = createCell(win)
        end
        row.aura = createAuraCell(win)
        win.rows[r] = row
    end

    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.hint:SetJustifyH("LEFT")
    win.hint:SetText("Left-click: next · Right-click: previous · Auto: paladin chooses")
    TB.SetTextColor(win.hint, color("muted"))

    win.missingHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.missingHint:SetJustifyH("LEFT")
    TB.SetTextColor(win.missingHint, color("warn"))

    win.excTitle = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.excTitle:SetText("Exceptions")
    TB.SetTextColor(win.excTitle, color("gold"))

    win.excAddBtn = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    win.excAddBtn:SetWidth(132); win.excAddBtn:SetHeight(18)
    win.excAddBtn:SetText("Exception for target")
    setBtnTooltip(win.excAddBtn, "Exception for target",
        "Override one player's blessing (uses your target, or lets you pick a group member).")
    win.excAddBtn:SetScript("OnClick", function() openExceptionMenu(this) end)

    win.excEmpty = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.excEmpty:SetText("None — target a player and click Exception for target.")
    TB.SetTextColor(win.excEmpty, color("muted"))

    win.excRows = {}
    for i = 1, MAX_EXCEPTIONS do
        local erow = {}
        erow.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        erow.text:SetJustifyH("LEFT")
        erow.remove = TB.StyleButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
        erow.remove:SetWidth(18); erow.remove:SetHeight(16)
        erow.remove:SetText("x")
        erow.remove:SetScript("OnClick", function()
            if this.paladin and this.player then
                TB.SendBlessingPlayer(this.paladin, this.player, "auto")
            end
        end)
        win.excRows[i] = erow
    end

    win:Hide()
    TB.blessingsWindow = win
end

local function renderCell(cell, value, enabled)
    if value and value ~= "auto" and C.BLESSING_ICONS[value] then
        cell.border:SetTexture(0.24, 0.22, 0.18, 0.95)
        cell.icon:SetTexture(C.BLESSING_ICONS[value])
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.icon:Show()
        cell.label:ClearAllPoints()
        cell.label:SetPoint("BOTTOM", cell, "BOTTOM", 0, 3)
        cell.label:SetText(SHORT_BLESSING[value] or TB.BlessingLabel(value))
        cell.label:SetTextColor(0.95, 0.92, 0.84)
    else
        cell.border:SetTexture(0.13, 0.13, 0.15, 0.85)
        cell.icon:Hide()
        cell.label:ClearAllPoints()
        cell.label:SetPoint("CENTER", cell, "CENTER", 0, 0)
        cell.label:SetText(value and "Auto" or "…")
        cell.label:SetTextColor(0.50, 0.49, 0.46)
    end
    if enabled then cell:Enable() else cell:Disable() end
end

local function renderAuraCell(cell, bot)
    local snap = TB.GetChoice and TB.GetChoice(bot, "aura")
    local val = snap and snap.value
    if val and val ~= "auto" then
        cell.border:SetTexture(0.24, 0.22, 0.18, 0.95)
        cell.label:SetText(shortAuraLabel(val))
        cell.label:SetTextColor(0.95, 0.92, 0.84)
    else
        cell.border:SetTexture(0.13, 0.13, 0.15, 0.85)
        cell.label:SetText(val and "Auto" or "…")
        cell.label:SetTextColor(0.50, 0.49, 0.46)
    end
    if snap then cell:Enable() else cell:Disable() end
end

function TB.RefreshBlessings()
    if not win or not win:IsVisible() then return end
    local paladins, present = TB.GetBlessingGroup()
    if not TB.HasBlessingCapability() or table.getn(paladins) == 0 then
        TB.CloseBlessings()
        return
    end
    local showAura = TB.HasChoiceCapability and TB.HasChoiceCapability() or false
    local showPlayers = TB.HasBlessingPlayerCapability()
    local columns = {}
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if present[cls.id] then table.insert(columns, cls) end
    end
    local colCount = table.getn(columns)
    local rowCount = math.min(table.getn(paladins), MAX_ROWS)
    local auraSpace = showAura and AURA_W or 0
    local width = math.max(PAD * 2 + NAME_W + colCount * CELL_W + auraSpace, 320)
    win:SetWidth(width)

    for i, head in ipairs(win.heads) do
        local cls = columns[i]
        if cls then
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + (i - 1) * CELL_W + 2, -HEAD_TOP)
            TB.SetClassIcon(head.icon, cls.id)
            local cc = C.CLASS_COLORS[cls.id] or { 1, 1, 1 }
            head.label:SetText(C.CLASS_NAMES[cls.id] or cls.word)
            head.label:SetTextColor(cc[1], cc[2], cc[3])
            head.className = C.CLASS_NAMES[cls.id]
            head:Show()
        else
            head:Hide()
        end
    end
    if showAura then
        win.auraHead:ClearAllPoints()
        win.auraHead:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + colCount * CELL_W + 2, -(HEAD_TOP + 16))
        win.auraHead:Show()
    else
        win.auraHead:Hide()
    end

    for r, row in ipairs(win.rows) do
        local name = paladins[r]
        if r <= rowCount and name then
            local snapshot = TB.GetBlessings(name)
            local top = -ROWS_TOP - (r - 1) * ROW_STEP
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, top - 11)
            row.name:SetText(name)
            local pal = C.CLASS_COLORS[2]
            row.name:SetTextColor(pal[1], pal[2], pal[3])
            row.name:Show()
            for c, cell in ipairs(row.cells) do
                local cls = columns[c]
                if cls then
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + (c - 1) * CELL_W + 2, top)
                    cell.bot, cell.word, cell.className = name, cls.word, C.CLASS_NAMES[cls.id]
                    local value = snapshot and snapshot.classes[cls.word]
                    renderCell(cell, value, snapshot and not pendingCell[name])
                    cell:Show()
                else
                    cell:Hide()
                end
            end
            if showAura then
                row.aura:ClearAllPoints()
                row.aura:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + colCount * CELL_W + 2, top)
                row.aura.bot = name
                renderAuraCell(row.aura, name)
                row.aura:Show()
            else
                row.aura:Hide()
            end
        else
            row.name:Hide()
            for _, cell in ipairs(row.cells) do cell:Hide() end
            row.aura:Hide()
        end
    end

    local y = ROWS_TOP + rowCount * ROW_STEP + 6
    win.hint:ClearAllPoints()
    win.hint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
    win.hint:SetWidth(width - PAD * 2)
    y = y + 16

    if cachedMissingText ~= "" then
        win.missingHint:ClearAllPoints()
        win.missingHint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
        win.missingHint:SetWidth(width - PAD * 2)
        win.missingHint:SetText(cachedMissingText)
        if string.sub(cachedMissingText, 1, 8) == "Missing:" then
            TB.SetTextColor(win.missingHint, color("warn"))
        else
            TB.SetTextColor(win.missingHint, color("muted"))
        end
        win.missingHint:Show()
        y = y + 16
    else
        win.missingHint:Hide()
    end

    if showPlayers then
        y = y + 4
        win.excTitle:ClearAllPoints()
        win.excTitle:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(y + 3))
        win.excTitle:Show()
        win.excAddBtn:ClearAllPoints()
        win.excAddBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 74, -y)
        win.excAddBtn:Show()
        y = y + 22
        local excs = TB.CollectBlessingExceptions()
        local excCount = math.min(table.getn(excs), MAX_EXCEPTIONS)
        if excCount == 0 then
            win.excEmpty:ClearAllPoints()
            win.excEmpty:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
            win.excEmpty:SetWidth(width - PAD * 2)
            win.excEmpty:Show()
            y = y + 16
        else
            win.excEmpty:Hide()
        end
        for i, erow in ipairs(win.excRows) do
            local ex = excs[i]
            if i <= excCount and ex then
                erow.text:ClearAllPoints()
                erow.text:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(y + 2))
                erow.text:SetWidth(width - PAD * 2 - 24)
                erow.text:SetText(ex.player .. " — " .. ex.paladin .. ": " .. (SHORT_BLESSING[ex.blessing] or TB.BlessingLabel(ex.blessing)))
                erow.text:Show()
                erow.remove:ClearAllPoints()
                erow.remove:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -y)
                erow.remove.paladin = ex.paladin
                erow.remove.player = ex.player
                erow.remove:Show()
                y = y + EXC_ROW_H
            else
                erow.text:Hide()
                erow.remove:Hide()
            end
        end
    else
        win.excTitle:Hide()
        win.excAddBtn:Hide()
        win.excEmpty:Hide()
        for _, erow in ipairs(win.excRows) do
            erow.text:Hide()
            erow.remove:Hide()
        end
    end

    win:SetHeight(y + PAD)
end

function TB.OpenBlessings()
    if not TB.BlessingAvailable() then return false end
    if not win then createWindow() end
    if TB.CloseBotPanel then TB.CloseBotPanel() end
    if TB.CloseBots then TB.CloseBots() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if TB.CloseActiveOrders then TB.CloseActiveOrders() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + WIN_W_MAX + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    cachedMissingText = TB.ComputeMissingBlessings()
    win:Show()
    TB.RefreshBlessings()
    TB.RequestBlessings()
    return true
end

function TB.CloseBlessings()
    if win then win:Hide() end
end

function TB.ToggleBlessings()
    if win and win:IsVisible() then TB.CloseBlessings() else TB.OpenBlessings() end
end

-- Capability gone mid-session (server swapped): close, like the other views.
function TB.NoteBlessingCaps()
    if not TB.HasBlessingCapability() then
        for key in pairs(blessings) do blessings[key] = nil end
        TB.CloseBlessings()
    elseif win and win:IsVisible() then
        TB.RefreshBlessings()
    end
    if TB.UpdateBlessingButton then TB.UpdateBlessingButton() end
end

-- The Party tab's entry point: shown when the group has a paladin bot and
-- the server has the command.
function TB.UpdateBlessingButton()
    local button = TB.partyFrame and TB.partyFrame.blessingBtn
    if not button then return end
    if TB.BlessingAvailable() then button:Show() else button:Hide() end
end

-- A changed group re-asks once things settle, while the window is open.
local dueAt
local watcher = CreateFrame("Frame", "TortoiseBotsManagerBlessingWatcher")
watcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
watcher:RegisterEvent("RAID_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
    if win and win:IsVisible() then dueAt = now() + 1 end
    if TB.UpdateBlessingButton then TB.UpdateBlessingButton() end
end)
watcher:SetScript("OnUpdate", function()
    if not dueAt or now() < dueAt then return end
    dueAt = nil
    if win and win:IsVisible() then
        TB.RefreshBlessings()
        if win:IsVisible() then TB.RequestBlessings() end
    end
end)
