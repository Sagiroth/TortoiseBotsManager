-- TortoiseBotsManager/BotTotem.lua
-- Shaman totem picker in the bot panel's Behaviour view: one control per
-- totem slot, the drop mode, and named presets kept in the saved variables.
--
--   .bot totem <bot> status                      -> TBM:TOTEM|<bot>|earth=<v>,fire=<v>,water=<v>,air=<v>,mode=<m>,known=<t>+<t>
--   .bot totem <bot> <slot> <totem|auto|none>    one slot
--   .bot totem <bot|party> set <e>,<f>,<w>,<a>   all four at once
--   .bot totem <bot> mode <auto|prepull|manual>
-- <v> is auto, none or a full lowercase totem name; `known` is absent on
-- older servers (then every totem of the slot is offered).

local TB = TortoiseBots
local C = TB.C or {}

local ROW_H = 20
local ROW_STEP = 22
local PANEL_W = 330
local NAME_MAX = 20

local function norm(name) return name and TB.NormalizeName(name) or nil end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── model ───────────────────────────────────────────────────────────────────
-- [bot] = { slots = { earth, fire, water, air }, mode, known = { names } or nil }
local totems = {}
local refreshAfterAck = {} -- [bot] = true while a single-slot or mode order waits for its fresh line

function TB.GetTotems(name)
    name = norm(name)
    return name and totems[name] or nil
end

function TB.SetTotems(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    totems[name] = snapshot
    refreshAfterAck[name] = nil
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

-- TBM:TOTEM|<bot>|earth=<v>,fire=<v>,water=<v>,air=<v>,mode=<m>[,known=<t>+<t>].
-- Needs all four slots; a missing or unknown mode reads as nil, a missing
-- `known` as nil (older server), an empty one as an empty list.
function TB.ParseTotemLine(msg)
    if string.sub(msg or "", 1, 10) ~= "TBM:TOTEM|" then return nil end
    local text = string.sub(msg, 11)
    local bar = string.find(text, "|", 1, true)
    if not bar then return nil end
    local name = norm(string.sub(text, 1, bar - 1))
    if not name or name == "" then return nil end
    local rest = string.sub(text, bar + 1)
    local extra = string.find(rest, "|", 1, true)
    if extra then rest = string.sub(rest, 1, extra - 1) end
    local slots, mode, known = {}, nil, nil
    for pair in string.gfind(rest, "[^,]+") do
        local _, _, key, value = string.find(pair, "^%s*(%a+)%s*=%s*(.-)%s*$")
        if key then
            key = string.lower(key)
            value = string.lower(value)
            if key == "mode" then
                for _, m in ipairs(C.TOTEM_MODES) do
                    if m == value then mode = value end
                end
            elseif key == "known" then
                known = {}
                for item in string.gfind(value, "[^+]+") do
                    item = TB.Trim(item)
                    if item ~= "" then table.insert(known, item) end
                end
            else
                for _, slot in ipairs(C.TOTEM_SLOTS) do
                    if slot == key and value ~= "" then slots[slot] = value end
                end
            end
        end
    end
    for _, slot in ipairs(C.TOTEM_SLOTS) do
        if not slots[slot] then return nil end
    end
    return { name = name, slots = slots, mode = mode, known = known }
end

function TB.ConsumeTotemLine(msg)
    local snapshot = TB.ParseTotemLine(msg)
    if not snapshot then return false end
    TB.SetTotems(snapshot.name, { slots = snapshot.slots, mode = snapshot.mode, known = snapshot.known })
    return true
end

-- Capitalised for display: "strength of earth totem" -> "Strength of Earth".
function TB.TotemLabel(value)
    if value == "auto" then return "Auto" end
    if value == "none" then return "None" end
    if not value or value == "" then return "?" end
    local words = {}
    for word in string.gfind(string.gsub(value, "%s+totem$", ""), "%S+") do
        if word ~= "of" then
            word = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
        end
        table.insert(words, word)
    end
    return table.concat(words, " ")
end

function TB.TotemSlotValueValid(slot, value)
    if value == "auto" or value == "none" then return true end
    for _, name in ipairs(C.TOTEMS[slot] or {}) do
        if name == value then return true end
    end
    return false
end

-- Auto, None, then the slot's totems the bot has trained (all of them while
-- the server does not say which).
function TB.TotemOptions(slot, known)
    local out = { "auto", "none" }
    for _, name in ipairs(C.TOTEMS[slot] or {}) do
        local keep = known == nil
        for _, k in ipairs(known or {}) do
            if k == name then keep = true end
        end
        if keep then table.insert(out, name) end
    end
    return out
end

function TB.NextTotemMode(mode)
    local modes = C.TOTEM_MODES
    for i, m in ipairs(modes) do
        if m == mode then return modes[math.mod(i, table.getn(modes)) + 1] end
    end
    return modes[1]
end

-- ── commands ────────────────────────────────────────────────────────────────
local function scopeWord(scope)
    local lower = string.lower(scope or "")
    if lower == "party" or lower == "raid" then return lower end
    return norm(scope)
end

function TB.BuildTotemSlotCommand(scope, slot, value)
    scope = scopeWord(scope)
    if not scope or not C.TOTEMS[slot] or not TB.TotemSlotValueValid(slot, value) then return nil end
    return "totem " .. scope .. " " .. slot .. " " .. value
end

function TB.BuildTotemSetCommand(scope, slots)
    scope = scopeWord(scope)
    if not scope or type(slots) ~= "table" then return nil end
    local parts = {}
    for _, slot in ipairs(C.TOTEM_SLOTS) do
        if not TB.TotemSlotValueValid(slot, slots[slot]) then return nil end
        table.insert(parts, slots[slot])
    end
    return "totem " .. scope .. " set " .. table.concat(parts, ",")
end

function TB.BuildTotemModeCommand(scope, mode)
    scope = scopeWord(scope)
    if not scope or not C.TOTEM_MODE_LABELS[mode] then return nil end
    return "totem " .. scope .. " mode " .. mode
end

function TB.RequestTotems(name)
    name = norm(name)
    if not name then return false end
    return TB.SendBotCommand("totem " .. name .. " status")
end

-- A slot or mode order is answered by a fresh TOTEM line; if only the ACK
-- arrives, the ACK handler asks for the status itself.
local function sendOne(name, cmd)
    if not cmd then return false end
    name = norm(name)
    if name then refreshAfterAck[name] = true end
    return TB.SendBotCommand(cmd)
end

function TB.SendTotemSlot(name, slot, value)
    return sendOne(name, TB.BuildTotemSlotCommand(name, slot, value))
end

function TB.SendTotemMode(name, mode)
    return sendOne(name, TB.BuildTotemModeCommand(name, mode))
end

-- Only a shaman answers the totem commands.
function TB.TotemWanted(name)
    return TB.BotClassId and TB.BotClassId(name) == 7
end

-- ACK routing from TB.OnBotPanelAck. Returns true when handled; the Drop
-- totems order keeps its generic text.
function TB.OnTotemAck(packet)
    local _, _, what = string.find(packet.intent or "", "^totem%s+(%S+)")
    if not what or what == "drop" then return false end
    local count = packet.count or 0
    local plural = count == 1 and "" or "s"
    if what == "status" then
        if TB.SetStatus then TB.SetStatus("Totems · " .. count .. " shaman" .. plural, "ok") end
        return true
    end
    if what == "set" then
        if TB.SetStatus then TB.SetStatus("Totems set · " .. count .. " shaman" .. plural, "ok") end
        return true
    end
    local _, _, bot = string.find(packet.scope or "", "^bot:(.+)$")
    bot = norm(bot)
    if bot and refreshAfterAck[bot] then
        refreshAfterAck[bot] = nil
        TB.RequestTotems(bot)
    end
    if TB.SetStatus then TB.SetStatus("Totems updated" .. (bot and (" · " .. bot) or ""), "ok") end
    return true
end

function TB.OnTotemError(packet)
    if string.find(packet.intent or "", "^totem%s") then
        for bot in pairs(refreshAfterAck) do refreshAfterAck[bot] = nil end
    end
end

-- ── presets (saved variables) ───────────────────────────────────────────────
local selectedPreset = nil

local function copyPresets(list)
    local out = {}
    for _, p in ipairs(list) do
        table.insert(out, { name = p.name, earth = p.earth, fire = p.fire, water = p.water, air = p.air })
    end
    return out
end

-- The player's presets in order; a fresh profile starts with the defaults,
-- and an emptied list stays empty.
function TB.GetTotemPresets()
    TortoiseBotsDB = TortoiseBotsDB or {}
    if type(TortoiseBotsDB.totemPresets) ~= "table" then
        TortoiseBotsDB.totemPresets = copyPresets(C.TOTEM_PRESETS_DEFAULT)
    end
    return TortoiseBotsDB.totemPresets
end

function TB.FindTotemPreset(name)
    name = string.lower(TB.Trim(name or ""))
    for i, p in ipairs(TB.GetTotemPresets()) do
        if string.lower(p.name or "") == name then return p, i end
    end
    return nil
end

-- The preset the selector shows: the chosen one, else the first.
function TB.GetSelectedTotemPreset()
    local list = TB.GetTotemPresets()
    local p = selectedPreset and TB.FindTotemPreset(selectedPreset)
    return p or list[1]
end

function TB.SelectTotemPreset(name)
    selectedPreset = name
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

function TB.CycleTotemPreset()
    local list = TB.GetTotemPresets()
    local count = table.getn(list)
    if count == 0 then return nil end
    local _, at = TB.FindTotemPreset((TB.GetSelectedTotemPreset() or {}).name)
    local nextPreset = list[math.mod(at or 0, count) + 1]
    TB.SelectTotemPreset(nextPreset.name)
    return nextPreset
end

-- Stores (or overwrites) a preset with exactly the four slot values.
function TB.SaveTotemPreset(name, slots)
    name = TB.Trim(name or "")
    if string.len(name) > NAME_MAX then name = TB.Trim(string.sub(name, 1, NAME_MAX)) end
    if name == "" or type(slots) ~= "table" then return false end
    for _, slot in ipairs(C.TOTEM_SLOTS) do
        if not TB.TotemSlotValueValid(slot, slots[slot]) then return false end
    end
    local preset = TB.FindTotemPreset(name)
    if not preset then
        preset = {}
        table.insert(TB.GetTotemPresets(), preset)
    end
    preset.name = name
    for _, slot in ipairs(C.TOTEM_SLOTS) do preset[slot] = slots[slot] end
    TB.SelectTotemPreset(name)
    return true
end

function TB.DeleteTotemPreset(name)
    local preset, at = TB.FindTotemPreset(name)
    if not preset then return false end
    table.remove(TB.GetTotemPresets(), at)
    if selectedPreset and string.lower(selectedPreset) == string.lower(preset.name) then selectedPreset = nil end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    return true
end

-- Applies the selected preset with one `set` order: to one shaman, or to
-- every shaman in the party.
function TB.ApplyTotemPreset(scope)
    local preset = TB.GetSelectedTotemPreset()
    if not preset then return false end
    local cmd = TB.BuildTotemSetCommand(scope, preset)
    if not cmd then
        if TB.SetStatus then TB.SetStatus("Preset " .. preset.name .. " has an unknown totem.", "warn") end
        return false
    end
    if TB.SetStatus then TB.SetStatus("Totems: " .. preset.name .. " → " .. scope .. "…", "pending") end
    return TB.SendBotCommand(cmd)
end

-- Saves the shaman's current four slots; Auto and None count as values.
function TB.SaveCurrentTotemPreset(bot, name)
    local snapshot = TB.GetTotems(bot)
    if not snapshot then
        if TB.SetStatus then TB.SetStatus("Totems not loaded yet; try Refresh.", "warn") end
        return false
    end
    if not TB.SaveTotemPreset(name, snapshot.slots) then
        if TB.SetStatus then TB.SetStatus("Type a name for the preset.", "warn") end
        return false
    end
    if TB.SetStatus then TB.SetStatus("Totem preset saved · " .. TB.Trim(name), "ok") end
    return true
end

function TB.ConfirmSaveTotemPreset(bot)
    bot = norm(bot)
    if not bot then return false end
    if not (StaticPopupDialogs and StaticPopup_Show) then return false end
    local current = TB.GetSelectedTotemPreset()
    StaticPopupDialogs["TORTOISEBOTSMANAGER_TOTEM_PRESET"] = {
        text = "Save " .. bot .. "'s totems as a preset.\nA name that exists is overwritten.",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = 1,
        maxLetters = NAME_MAX,
        OnShow = function()
            local box = getglobal(this:GetName() .. "EditBox")
            if box then
                box:SetText(current and current.name or "")
                box:SetFocus()
            end
        end,
        OnAccept = function()
            local box = getglobal(this:GetParent():GetName() .. "EditBox")
            TB.SaveCurrentTotemPreset(bot, box and box:GetText() or "")
        end,
        EditBoxOnEnterPressed = function()
            local parent = this:GetParent()
            TB.SaveCurrentTotemPreset(bot, this:GetText())
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
    StaticPopup_Show("TORTOISEBOTSMANAGER_TOTEM_PRESET")
    return true
end

-- ── slot menu ───────────────────────────────────────────────────────────────
-- One dropdown row per choice; the builder stays testable without the
-- DropDownList frames, like the portal menu.
function TB.BuildTotemSlotMenu(name, slot, addButton)
    local snapshot = TB.GetTotems(name)
    if not snapshot then return 0 end
    local options = TB.TotemOptions(slot, snapshot.known)
    local bot = norm(name)
    for _, value in ipairs(options) do
        local choice = value
        addButton({ text = TB.TotemLabel(choice), checked = (snapshot.slots[slot] == choice) and 1 or nil,
            func = function() TB.SendTotemSlot(bot, slot, choice) end })
    end
    return table.getn(options)
end

local slotMenu
function TB.OpenTotemSlotMenu(name, slot)
    name = norm(name)
    if not name or not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return false end
    if not TB.GetTotems(name) then return false end
    if not slotMenu then
        slotMenu = CreateFrame("Frame", "TortoiseBotsManagerTotemMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(slotMenu, function()
        TB.BuildTotemSlotMenu(name, slot, UIDropDownMenu_AddButton)
    end, "MENU")
    ToggleDropDownMenu(1, nil, slotMenu, "cursor")
    return true
end

-- ── panel block ─────────────────────────────────────────────────────────────
local block
local function currentBot() return TB.GetBotPanelBot and TB.GetBotPanelBot() or nil end

local function makeButton(parent, x, width)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(ROW_H)
    b.x = x
    return b
end

-- Built once with the panel; RenderTotemBlock places and shows it.
function TB.CreateTotemBlock(panel, parent)
    block = { slots = {} }
    for _, slot in ipairs(C.TOTEM_SLOTS) do
        local b = makeButton(parent, 12, PANEL_W - 24)
        b.slot = slot
        setTooltip(b, C.TOTEM_SLOT_LABELS[slot] .. " totem", {
            "Click to pick the totem this shaman drops in this slot.",
            "Auto lets the bot decide; None drops nothing here.",
        })
        b:SetScript("OnClick", function()
            local bot = currentBot()
            if bot then TB.OpenTotemSlotMenu(bot, this.slot) end
        end)
        block.slots[slot] = b
    end

    block.mode = makeButton(parent, 12, 150)
    setTooltip(block.mode, "Drop mode", {
        "Click to switch.",
        "Auto: the bot decides when to drop totems.",
        "Before the pull: totems go down ahead of a pull.",
        "Only on order: totems drop when you press Drop totems.",
    })
    block.mode:SetScript("OnClick", function()
        local bot = currentBot()
        local snapshot = bot and TB.GetTotems(bot)
        if snapshot then TB.SendTotemMode(bot, TB.NextTotemMode(snapshot.mode)) end
    end)

    block.preset = makeButton(parent, 168, 150)
    setTooltip(block.preset, "Totem preset", {
        "Click to pick the next preset.",
        "Apply sends it to this shaman, Apply to all to every shaman in the party.",
    })
    block.preset:SetScript("OnClick", function() TB.CycleTotemPreset() end)

    block.apply = makeButton(parent, 12, 72)
    block.apply:SetText("Apply")
    setTooltip(block.apply, "Apply preset", { "Sets all four totems of this shaman to the preset." })
    block.apply:SetScript("OnClick", function()
        local bot = currentBot()
        if bot then TB.ApplyTotemPreset(bot) end
    end)

    block.applyAll = makeButton(parent, 90, 72)
    block.applyAll:SetText("Apply all")
    setTooltip(block.applyAll, "Apply to all", { "Sets all four totems of every shaman in your party to the preset." })
    block.applyAll:SetScript("OnClick", function() TB.ApplyTotemPreset("party") end)

    block.save = makeButton(parent, 168, 72)
    block.save:SetText("Save")
    setTooltip(block.save, "Save preset", {
        "Stores this shaman's four totems under a name you type.",
        "A name that exists is overwritten.",
    })
    block.save:SetScript("OnClick", function()
        local bot = currentBot()
        if bot then TB.ConfirmSaveTotemPreset(bot) end
    end)

    block.delete = makeButton(parent, 246, 72)
    block.delete:SetText("Delete")
    setTooltip(block.delete, "Delete preset", { "Removes the shown preset from this list." })
    block.delete:SetScript("OnClick", function()
        local preset = TB.GetSelectedTotemPreset()
        if preset then TB.DeleteTotemPreset(preset.name) end
    end)

    panel.totemBlock = block
end

local function setEnabled(button, on)
    if on then button:Enable() else button:Disable() end
end

local function place(button, top, row)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", button.x, top - row * ROW_STEP)
end

-- `top` is the y offset (negative, from the panel's top) of the first row.
function TB.RenderTotemBlock(bot, classId, top)
    if not block then return end
    local show = bot and classId == 7
    local snapshot = show and TB.GetTotems(bot) or nil
    for row, slot in ipairs(C.TOTEM_SLOTS) do
        local b = block.slots[slot]
        if show then
            place(b, top, row - 1)
            b:SetText(C.TOTEM_SLOT_LABELS[slot] .. ": " .. TB.TotemLabel(snapshot and snapshot.slots[slot] or nil))
            setEnabled(b, snapshot)
            b:Show()
        else
            b:Hide()
        end
    end
    if not show then
        block.mode:Hide(); block.preset:Hide(); block.apply:Hide()
        block.applyAll:Hide(); block.save:Hide(); block.delete:Hide()
        return
    end
    local preset = TB.GetSelectedTotemPreset()
    place(block.mode, top, 4)
    block.mode:SetText("Drop: " .. (snapshot and snapshot.mode and C.TOTEM_MODE_LABELS[snapshot.mode] or "?"))
    setEnabled(block.mode, snapshot and snapshot.mode)
    place(block.preset, top, 4)
    block.preset:SetText(preset and preset.name or "No presets")
    setEnabled(block.preset, preset)
    place(block.apply, top, 5)
    place(block.applyAll, top, 5)
    place(block.save, top, 5)
    place(block.delete, top, 5)
    setEnabled(block.apply, preset and snapshot)
    setEnabled(block.applyAll, preset)
    setEnabled(block.save, snapshot)
    setEnabled(block.delete, preset)
    block.mode:Show(); block.preset:Show(); block.apply:Show()
    block.applyAll:Show(); block.save:Show(); block.delete:Show()
end
