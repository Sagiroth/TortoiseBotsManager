-- TortoiseBotsManager/BotChoice.lua
-- Class choices in the bot panel's Behaviour view (paladin aura, hunter
-- aspect, warlock curse), data-driven from the server: one control per kind
-- with Auto plus the `known` values, same UX as the totem slot picker.
-- Shown only with the `choice` capability and a record for that bot.
--
--   .bot choice <bot> <kind> <value|auto>     one kind
--   .bot choice <bot|party> status            everything
--   TBM:CHOICE|<bot>|<kind>=<value|auto>,known=<v>+<v>+...   (one line per kind)
--   TBM:ACTION_ACK|choice|<scope>|<n>|<kind>=<value> / TBM:ACTION_ACK|choice status|<scope>|<n>|-
--   TBM:ACTION_ERR|choice|invalid|<usage> | choice|unknown-spell|<msg> | choice|no-bot|<msg>
--
-- The UI is generic over kinds (label = capitalised kind, values
-- capitalised), so a new kind from the server needs no addon change. The
-- control shows what the server reports (the fresh record arrives before
-- the ACK), like the totem picker.

local TB = TortoiseBots
local C = TB.C or {}

local CAP = "choice"

local function norm(name) return name and TB.NormalizeName(name) or nil end

-- ── model ───────────────────────────────────────────────────────────────────
-- [bot] = { [kind] = { value = "auto", known = { "devotion aura", ... } or nil } }
local choices = {}
local refreshAfterAck = {} -- [bot] = true while a choice order waits for its fresh line

function TB.HasChoiceCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

function TB.GetChoices(name)
    name = norm(name)
    return name and choices[name] or nil
end

function TB.GetChoice(name, kind)
    name, kind = norm(name), kind and string.lower(TB.Trim(kind)) or nil
    local entry = name and kind and choices[name] or nil
    return entry and entry[kind] or nil
end

function TB.SetChoices(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    choices[name] = snapshot
    refreshAfterAck[name] = nil
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    if TB.RefreshBots then TB.RefreshBots() end
end

function TB.ClearChoices(name)
    name = norm(name)
    if name then choices[name] = nil end
end

-- TBM:CHOICE|<bot>|<kind>=<value|auto>,known=<v>+<v>+...  Values are
-- lowercase words and may contain spaces ("shadow resistance"); known may
-- be empty, and is nil when the server omits it.
function TB.ParseChoiceLine(msg)
    if string.sub(msg or "", 1, 11) ~= "TBM:CHOICE|" then return nil end
    local text = string.sub(msg, 12)
    local bar = string.find(text, "|", 1, true)
    if not bar then return nil end
    local name = norm(string.sub(text, 1, bar - 1))
    if not name or name == "" then return nil end
    local rest = string.sub(text, bar + 1)
    local extra = string.find(rest, "|", 1, true)
    if extra then rest = string.sub(rest, 1, extra - 1) end
    local kind, value, known = nil, nil, nil
    for pair in string.gfind(rest, "[^,]+") do
        local _, _, key, item = string.find(pair, "^%s*([%a_]+)%s*=%s*(.-)%s*$")
        if key then
            key = string.lower(key)
            item = string.lower(item or "")
            if key == "known" then
                known = {}
                for entry in string.gfind(item, "[^+]+") do
                    entry = TB.Trim(entry)
                    if entry ~= "" then table.insert(known, entry) end
                end
            elseif not kind and item ~= "" then
                kind, value = key, item
            end
        end
    end
    if not kind or not value then return nil end
    return { name = name, kind = kind, value = value, known = known }
end

function TB.ConsumeChoiceLine(msg)
    local snapshot = TB.ParseChoiceLine(msg)
    if not snapshot then return false end
    local entry = choices[snapshot.name] or {}
    entry[snapshot.kind] = { value = snapshot.value, known = snapshot.known }
    TB.SetChoices(snapshot.name, entry)
    return true
end

-- Capitalised for display: "shadow resistance" -> "Shadow Resistance".
function TB.ChoiceLabel(kind, value)
    if not kind then return "?" end
    if not value or value == "" then return "?" end
    if value == "auto" then return "Auto" end
    if kind ~= string.lower(kind) then kind = string.lower(kind) end
    local words = {}
    for word in string.gfind(value, "%S+") do
        if word ~= "of" then
            word = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
        end
        table.insert(words, word)
    end
    return table.concat(words, " ")
end

-- Display label of a kind: capitalised ("aura" -> "Aura").
function TB.ChoiceKindLabel(kind)
    if not kind or kind == "" then return "?" end
    kind = string.lower(kind)
    return string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2)
end

-- Sorted kinds a bot has records for (the server only sends what applies).
function TB.ChoiceKinds(name)
    local entry = TB.GetChoices(name)
    if not entry then return {} end
    local kinds = {}
    for kind in pairs(entry) do table.insert(kinds, kind) end
    table.sort(kinds)
    return kinds
end

-- Auto, then the values the bot has trained (all offered when the server
-- does not say which).
function TB.ChoiceOptions(kind, known)
    local out = { "auto" }
    if known == nil then return out end
    for _, value in ipairs(known) do
        table.insert(out, value)
    end
    return out
end

-- ── commands ────────────────────────────────────────────────────────────────
local function scopeWord(scope)
    local lower = string.lower(scope or "")
    if lower == "party" or lower == "raid" then return lower end
    return norm(scope)
end

function TB.BuildChoiceCommand(scope, kind, value)
    scope = scopeWord(scope)
    kind = kind and string.lower(TB.Trim(kind)) or nil
    value = value and string.lower(TB.Trim(value)) or nil
    if not scope or not kind or kind == "" or not value or value == "" then return nil end
    if string.find(kind, "%s") or string.find(kind, "=") then return nil end
    return "choice " .. scope .. " " .. kind .. " " .. value
end

function TB.RequestChoices(scope)
    scope = scopeWord(scope)
    if not scope then return false end
    return TB.SendBotCommand("choice " .. scope .. " status")
end

function TB.SendChoice(name, kind, value)
    local cmd = TB.BuildChoiceCommand(name, kind, value)
    if not cmd then return false end
    name = norm(name)
    if name then refreshAfterAck[name] = true end
    return TB.SendBotCommand(cmd)
end

-- ACK routing from TB.OnBotPanelAck. Returns true when handled.
function TB.OnChoiceAck(packet)
    local intent = packet.intent or ""
    if intent ~= "choice" and intent ~= "choice status" then return false end
    local _, _, bot = string.find(packet.scope or "", "^bot:(.+)$")
    bot = norm(bot)
    if bot and refreshAfterAck[bot] then
        refreshAfterAck[bot] = nil
        TB.RequestChoices(bot)
    end
    if TB.SetStatus then
        if intent == "choice status" then
            TB.SetStatus("Choices · " .. (packet.count or 0) .. " bot(s)", "ok")
        else
            local _, _, kind, value = string.find(packet.executor or "", "^([^=]+)=(.+)$")
            local text = "Choice set"
            if bot and kind and value then
                text = bot .. ": " .. TB.ChoiceKindLabel(kind) .. " → "
                    .. TB.ChoiceLabel(kind, string.lower(value))
            end
            TB.SetStatus(text, "ok")
        end
    end
    return true
end

function TB.OnChoiceError(packet)
    if string.find(packet.intent or "", "^choice") then
        for bot in pairs(refreshAfterAck) do refreshAfterAck[bot] = nil end
    end
end

-- ── kind menu ───────────────────────────────────────────────────────────────
-- One dropdown row per value; the builder stays testable without the
-- DropDownList frames, like the totem slot and portal menus.
function TB.BuildChoiceMenu(name, kind, addButton)
    local snapshot = TB.GetChoice(name, kind)
    if not snapshot then return 0 end
    name = norm(name)
    local count = 0
    for _, value in ipairs(TB.ChoiceOptions(kind, snapshot.known)) do
        local choice = value
        count = count + 1
        addButton({ text = TB.ChoiceLabel(kind, choice),
            checked = (snapshot.value == choice) and 1 or nil,
            func = function() TB.SendChoice(name, kind, choice) end })
    end
    return count
end

local choiceMenu
function TB.OpenChoiceMenu(name, kind)
    name, kind = norm(name), kind and string.lower(TB.Trim(kind)) or nil
    if not name or not kind then return false end
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if not TB.GetChoice(name, kind) then return false end
    if not choiceMenu then
        choiceMenu = CreateFrame("Frame", "TortoiseBotsManagerChoiceMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(choiceMenu, function()
        TB.BuildChoiceMenu(name, kind, UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, choiceMenu, "cursor")
    return true
end

-- ── panel block ─────────────────────────────────────────────────────────────
local ROW_H = 20
local ROW_STEP = 22
local PANEL_W = 330
local MAX_CHOICES = 4
local block

local function currentBot() return TB.GetBotPanelBot and TB.GetBotPanelBot() or nil end

local function makeButton(parent, x, width)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(ROW_H)
    b.x = x
    return b
end

-- Built once with the panel; RenderChoiceBlock places and shows it.
function TB.CreateChoiceBlock(panel, parent)
    block = { kinds = {} }
    for i = 1, MAX_CHOICES do
        local b = makeButton(parent, 12, PANEL_W - 24)
        b.slot = i
        b:SetScript("OnClick", function()
            local bot = currentBot()
            if bot and this.choiceKind then TB.OpenChoiceMenu(bot, this.choiceKind) end
        end)
        block.kinds[i] = b
    end
    panel.choiceBlock = block
end

local function setEnabled(button, on)
    if on then button:Enable() else button:Disable() end
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

-- `top` is the y offset (negative, from the panel's top) of the first row.
-- Returns the y offset just below the block (for stacking callers).
function TB.RenderChoiceBlock(bot, classId, top)
    if not block then return top end
    local show = bot and TB.HasChoiceCapability()
    local kinds = show and TB.ChoiceKinds(bot) or {}
    if table.getn(kinds) > MAX_CHOICES then
        local trimmed = {}
        for i = 1, MAX_CHOICES do table.insert(trimmed, kinds[i]) end
        kinds = trimmed
    end
    for i, b in ipairs(block.kinds) do
        local kind = kinds[i]
        if show and kind then
            local snapshot = TB.GetChoice(bot, kind)
            b.choiceKind = kind
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", b.x, top - (i - 1) * ROW_STEP)
            b:SetText(TB.ChoiceKindLabel(kind) .. ": " .. TB.ChoiceLabel(kind, snapshot and snapshot.value or nil))
            setTooltip(b, TB.ChoiceKindLabel(kind), {
                "Click to pick the " .. string.lower(TB.ChoiceKindLabel(kind)) .. " this bot uses.",
                "Auto lets the bot decide.",
            })
            setEnabled(b, snapshot)
            if TB.ChoiceKindWanted and not TB.ChoiceKindWanted(kind, classId) then b:Hide() else b:Show() end
        else
            b:Hide()
        end
    end
    if not show or table.getn(kinds) == 0 then return top end
    return top - table.getn(kinds) * ROW_STEP - 4
end

-- Whether a kind's control shows for a bot: a known kind only for its
-- class (aura for paladins, aspect for hunters, curse for warlocks); an
-- unknown kind (a future server addition) shows for every class, so no
-- addon change is needed.
local KIND_CLASS = { aura = 2, aspect = 3, curse = 9 }

function TB.ChoiceKindWanted(kind, classId)
    kind = kind and string.lower(kind) or nil
    if not kind then return false end
    local want = KIND_CLASS[kind]
    if not want then return true end
    if not classId then return true end
    return classId == want
end

function TB.NoteChoiceBlockCaps()
    if not TB.HasChoiceCapability() then
        for key in pairs(choices) do choices[key] = nil end
        for bot in pairs(refreshAfterAck) do refreshAfterAck[bot] = nil end
    end
end
