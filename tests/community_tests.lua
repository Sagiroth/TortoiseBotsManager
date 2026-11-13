-- Features added from community feedback: behaviour chips (Hold position, No
-- dungeon Blink) and the shaman totem picker.
-- Run from tests/regression.lua, same shape as tests/wire_cases.lua.

return function(env)
local sent = env.sent
local frames = env.frames
local advanceTime = env.advanceTime
local setParty = env.setParty
local getParty = env.getParty
local setTarget = env.setTarget

local TB = TortoiseBots
local C = TB.C or {}

local function drainQueue()
    local qf = frames["TortoiseBotsManagerQueueFrame"]
    if qf and qf.scripts and qf.scripts.OnUpdate then
        for _ = 1, 5 do
            advanceTime(1)
            this, arg1 = qf, 0.5
            qf.scripts.OnUpdate(qf)
        end
    end
end

for _ = 1, 10 do drainQueue() end

-- Runs fn and returns the chat commands it sent.
local function commands(fn)
    TB.SetAddonTransport("none")
    local before = table.getn(sent)
    advanceTime(1)
    fn()
    drainQueue()
    local out = {}
    for i = before + 1, table.getn(sent) do table.insert(out, sent[i]) end
    return out
end

local function click(button)
    this = button
    button.scripts.OnClick(button)
end

local function expectCommands(label, got, want)
    assert(table.getn(got) == table.getn(want),
        label .. ": expected " .. table.getn(want) .. " commands, got " .. table.concat(got, " , "))
    for i, text in ipairs(want) do
        assert(got[i] == text, label .. ": expected '" .. text .. "', got '" .. tostring(got[i]) .. "'")
    end
end

local savedMembers, savedClass = getParty()

-- ── behaviour chips: Hold position (optional) and No dungeon Blink (mage) ──
do
    local hold, noblink
    for _, def in ipairs(C.BEHAVIORS) do
        if def.key == "hold" then hold = def end
        if def.key == "noblink" then noblink = def end
    end
    assert(hold and hold.label == "Hold position" and hold.optional and not hold.class,
        "Hold position is an optional chip for every class")
    assert(noblink and noblink.optional and noblink.class == 8, "No dungeon Blink is an optional mage chip")

    assert(TB.BehaviorChipShown(hold, { loot = "on" }, 5) == false, "hold hides while the server omits the key")
    assert(TB.BehaviorChipShown(hold, { hold = "off" }, 5), "hold shows once the server reports it")
    assert(TB.BehaviorChipShown(hold, nil, 5), "hold shows (disabled) before any state arrived")
    assert(TB.BehaviorChipShown(noblink, { noblink = "off" }, 8), "noblink shows for a mage that reports it")
    assert(TB.BehaviorChipShown(noblink, { noblink = "off" }, 5) == false, "noblink never shows for a priest")
    assert(TB.BehaviorChipShown(noblink, { hold = "on" }, 8) == false, "noblink hides on a server without it")
    assert(TB.BehaviorChipShown(noblink, nil, nil) == false, "noblink hides when the class is unknown")
    local loot, mana
    for _, def in ipairs(C.BEHAVIORS) do
        if def.key == "loot" then loot = def end
        if def.key == "savemana" then mana = def end
    end
    assert(TB.BehaviorChipShown(loot, { loot = nil }, 5), "the older keys keep their '?' chip")
    assert(TB.BehaviorChipShown(mana, {}, 1) == false and TB.BehaviorChipShown(mana, {}, 8), "mana chips still follow the class")

    setParty({ "Magebot" }, "Mage")
    TB.OpenBotPanel("Magebot", "behavior")
    drainQueue()
    local chips = TB.botPanel.behaviorChips
    assert(chips.hold.visible and not chips.hold.enabled, "Hold position shows disabled before the state arrives")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,aoe=on")
    assert(not chips.hold.visible and not chips.noblink.visible, "an older server's state hides both chips")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,hold=off,noblink=on")
    assert(chips.hold.visible and chips.noblink.visible, "a newer server's state shows both chips")
    assert(chips.hold.text == "Hold position: Off" and chips.noblink.text == "No dungeon Blink: On",
        "the chips read the reported state")
    expectCommands("hold on", commands(function() click(chips.hold) end), { ".bot behavior Magebot hold on" })
    TB.OnSystemMessage("TBM:ACTION_ACK|behavior hold|bot:Magebot|1|on")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,hold=on,noblink=on")
    expectCommands("hold off", commands(function() click(chips.hold) end), { ".bot behavior Magebot hold off" })
    TB.OnSystemMessage("TBM:ACTION_ACK|behavior hold|bot:Magebot|1|off")
    expectCommands("noblink off", commands(function() click(chips.noblink) end), { ".bot behavior Magebot noblink off" })
    TB.OnSystemMessage("TBM:ACTION_ACK|behavior noblink|bot:Magebot|1|off")

    setParty({ "Priestbot" }, "Priest")
    TB.OpenBotPanel("Priestbot", "behavior")
    drainQueue()
    TB.OnSystemMessage("TBM:BOTSTATE|Priestbot|move=follow,loot=on,hold=off,noblink=off")
    assert(chips.hold.visible and not chips.noblink.visible, "a priest gets Hold position but never the Blink chip")
    TB.CloseBotPanel()
end

-- ── shaman totems: parser, builders, presets ──
do
    local line = "TBM:TOTEM|Thrallbot|earth=strength of earth totem,fire=searing totem,water=none,air=auto,"
        .. "mode=prepull,known=stoneskin totem+strength of earth totem+searing totem+windfury totem"
    local t = TB.ParseTotemLine(line)
    assert(t and t.name == "Thrallbot" and t.mode == "prepull", "a full totem line parses")
    assert(t.slots.earth == "strength of earth totem" and t.slots.fire == "searing totem"
        and t.slots.water == "none" and t.slots.air == "auto", "slot values keep their spaces")
    assert(table.getn(t.known) == 4 and t.known[2] == "strength of earth totem", "known splits on +")
    local older = TB.ParseTotemLine("TBM:TOTEM|Thrallbot|earth=auto,fire=auto,water=auto,air=auto,mode=auto")
    assert(older and older.known == nil and older.mode == "auto", "an older server sends no known list")
    local empty = TB.ParseTotemLine("TBM:TOTEM|Thrallbot|earth=auto,fire=auto,water=auto,air=auto,mode=manual,known=")
    assert(empty and empty.known and table.getn(empty.known) == 0, "an empty known list stays an empty list")
    assert(TB.ParseTotemLine("TBM:TOTEM|Thrallbot|earth=auto,fire=auto,water=auto,mode=auto") == nil,
        "a line missing a slot is refused")
    assert(TB.ParseTotemLine("TBM:TOTEM|Thrallbot|earth=auto,fire=auto,water=auto,air=auto,mode=weird").mode == nil,
        "an unknown mode reads as nil")
    assert(TB.ParseTotemLine("TBM:TOTEM|Thrallbot|earth=auto,fire=auto,water=auto,air=auto,mode=auto|extra").mode == "auto",
        "extra fields after the state are ignored")
    assert(TB.ParseTotemLine("TBM:TOTEM|") == nil and TB.ParseTotemLine("TBM:SERVICE|a|b") == nil
        and TB.ParseTotemLine("TBM:TOTEM|Thrallbot") == nil, "other or short lines are refused")
    assert(TB.GetTotems("Thrallbot") == nil, "a rejected line must not reach the cache")

    assert(TB.TotemLabel("strength of earth totem") == "Strength of Earth" and TB.TotemLabel("windfury totem") == "Windfury"
        and TB.TotemLabel("auto") == "Auto" and TB.TotemLabel("none") == "Auto" and TB.TotemLabel(nil) == "?",
        "totem names read capitalised without the word totem")
    local full = TB.TotemOptions("earth", nil)
    assert(table.getn(full) == 6 and full[1] == "auto" and full[5] == "strength of earth totem",
        "without a known list every earth totem is offered after Auto")
    local some = TB.TotemOptions("earth", { "stoneskin totem", "windfury totem" })
    assert(table.getn(some) == 2 and some[2] == "stoneskin totem", "known filters the slot list")
    assert(table.getn(TB.TotemOptions("air", {})) == 1, "no trained totems leaves Auto")
    assert(TB.NextTotemMode("auto") == "prepull" and TB.NextTotemMode("prepull") == "manual"
        and TB.NextTotemMode("manual") == "auto" and TB.NextTotemMode(nil) == "auto", "the drop mode cycles")

    assert(TB.BuildTotemSlotCommand("Thrallbot", "earth", "strength of earth totem") == "totem Thrallbot earth strength of earth totem")
    assert(TB.BuildTotemSlotCommand("Thrallbot", "fire", "none") == "totem Thrallbot fire none")
    assert(TB.BuildTotemSlotCommand("Thrallbot", "earth", "searing totem") == nil, "a totem of another slot is refused")
    assert(TB.BuildTotemSlotCommand("Thrallbot", "wood", "auto") == nil, "an unknown slot is refused")
    local set = TB.BuildTotemSetCommand("Thrallbot", { earth = "strength of earth totem", fire = "searing totem",
        water = "mana spring totem", air = "windfury totem" })
    assert(set == "totem Thrallbot set strength of earth totem,searing totem,mana spring totem,windfury totem",
        "the set command lists earth, fire, water, air: " .. tostring(set))
    assert(TB.BuildTotemSetCommand("party", { earth = "auto", fire = "none", water = "auto", air = "auto" })
        == "totem party set auto,none,auto,auto")
    assert(TB.BuildTotemSetCommand("party", { earth = "auto", fire = "none", water = "auto" }) == nil
        and TB.BuildTotemSetCommand("party", { earth = "auto", fire = "a,b", water = "auto", air = "auto" }) == nil,
        "an incomplete or comma-bearing preset is refused")
    assert(TB.BuildTotemModeCommand("Thrallbot", "manual") == "totem Thrallbot mode manual"
        and TB.BuildTotemModeCommand("Thrallbot", "never") == nil)

    TortoiseBotsDB.totemPresets = nil
    local presets = TB.GetTotemPresets()
    assert(table.getn(presets) == 2 and presets[1].name == "Melee group" and presets[2].name == "Caster group",
        "a fresh profile starts with both default presets")
    assert(presets[1].earth == "strength of earth totem" and presets[1].fire == "searing totem"
        and presets[1].water == "mana spring totem" and presets[1].air == "windfury totem", "Melee group")
    assert(presets[2].earth == "stoneskin totem" and presets[2].air == "grace of air totem", "Caster group")
    assert(TB.GetTotemPresets() == presets and presets ~= C.TOTEM_PRESETS_DEFAULT, "defaults are copied, not shared")
    local mine = { earth = "tremor totem", fire = "none", water = "auto", air = "grounding totem" }
    assert(TB.SaveTotemPreset("  Raid utility  ", mine), "a new preset saves")
    assert(table.getn(presets) == 3 and presets[3].name == "Raid utility" and presets[3].earth == "tremor totem"
        and presets[3].fire == "none" and presets[3].water == "auto", "the preset keeps exactly the four values")
    assert(TB.GetSelectedTotemPreset().name == "Raid utility", "a saved preset becomes the shown one")
    assert(TB.SaveTotemPreset("melee GROUP", mine) and table.getn(presets) == 3 and presets[1].name == "melee GROUP"
        and presets[1].earth == "tremor totem", "saving under an existing name overwrites it in place")
    assert(not TB.SaveTotemPreset("   ", mine) and not TB.SaveTotemPreset("x", { earth = "auto" })
        and not TB.SaveTotemPreset("x", { earth = "searing totem", fire = "auto", water = "auto", air = "auto" }),
        "an empty name or an invalid slot value saves nothing")
    assert(table.getn(presets) == 3, "a refused save leaves the list alone")
    assert(string.len(TB.GetTotemPresets()[3].name) <= 20 and TB.SaveTotemPreset("abcdefghijklmnopqrstuvwxyz", mine)
        and TB.FindTotemPreset("abcdefghijklmnopqrst"), "long names are cut to 20 characters")
    TB.SelectTotemPreset("Raid utility")
    assert(TB.CycleTotemPreset().name == "abcdefghijklmnopqrst" and TB.CycleTotemPreset().name == "melee GROUP",
        "cycling walks the list and wraps")
    assert(TB.DeleteTotemPreset("melee group") and not TB.FindTotemPreset("melee group"), "a preset deletes by name")
    assert(not TB.DeleteTotemPreset("nope"), "deleting an unknown preset does nothing")
    for _ = 1, 5 do
        local first = TB.GetTotemPresets()[1]
        if first then TB.DeleteTotemPreset(first.name) end
    end
    assert(table.getn(TB.GetTotemPresets()) == 0 and TB.GetSelectedTotemPreset() == nil, "every preset can go")
    assert(table.getn(TB.GetTotemPresets()) == 0, "an emptied list is not refilled with the defaults")
    TortoiseBotsDB.totemPresets = nil
end

-- ── shaman totems: panel, wire ──
do
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
    setParty({ "Thrallbot" }, "Shaman")
    expectCommands("shaman open", commands(function() TB.OpenBotPanel("Thrallbot", "behavior") end), { ".bot inv Thrallbot", ".bot totem Thrallbot status" })
    local block = TB.botPanel.totemBlock
    assert(block.slots.earth.visible and block.mode.visible and block.apply.visible, "a shaman shows the totem block")
    assert(not block.slots.earth.enabled and block.slots.earth.text == "Earth: ?", "slots wait for the reply")
    TB.OnSystemMessage("TBM:TOTEM|Thrallbot|earth=strength of earth totem,fire=searing totem,water=auto,air=none,"
        .. "mode=auto,known=stoneskin totem+strength of earth totem+searing totem+mana spring totem+windfury totem")
    assert(block.slots.earth.text == "Earth: Strength of Earth" and block.slots.fire.text == "Fire: Searing"
        and block.slots.water.text == "Water: Auto" and block.slots.air.text == "Air: Auto"
        and block.mode.text == "When: Auto" and block.slots.earth.enabled, "the reply fills the controls")
    assert(block.preset.text == "Preset: Melee group" and block.apply.enabled, "the first preset shows")

    local rows = {}
    assert(TB.BuildTotemSlotMenu("Thrallbot", "earth", function(info) table.insert(rows, info) end) == 3
        and rows[1].text == "Auto" and rows[2].text == "Stoneskin"
        and rows[3].text == "Strength of Earth" and rows[3].checked == 1 and rows[2].checked == nil,
        "the earth menu offers Auto and the trained earth totems, marking the current one")
    expectCommands("pick earth", commands(function() rows[2].func() end), { ".bot totem Thrallbot earth stoneskin totem" })
    expectCommands("ack without line", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem earth|bot:Thrallbot|1|stoneskin totem")
    end), { ".bot totem Thrallbot status" })
    expectCommands("no repeat ask", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem earth|bot:Thrallbot|1|stoneskin totem")
    end), {})
    expectCommands("pick air auto", commands(function()
        local menu = {}
        TB.BuildTotemSlotMenu("Thrallbot", "air", function(info) table.insert(menu, info) end)
        menu[1].func()
    end), { ".bot totem Thrallbot air auto" })
    expectCommands("fresh line first", commands(function()
        TB.OnSystemMessage("TBM:TOTEM|Thrallbot|earth=stoneskin totem,fire=searing totem,water=auto,air=none,mode=auto")
        TB.OnSystemMessage("TBM:ACTION_ACK|totem air|bot:Thrallbot|1|none")
    end), {})
    assert(block.slots.earth.text == "Earth: Stoneskin", "a fresh line repaints the picker")
    assert(TB.BuildTotemSlotMenu("Thrallbot", "air", function() end) == 7, "no known list offers the whole air list")

    expectCommands("mode", commands(function() click(block.mode) end), { ".bot totem Thrallbot mode prepull" })
    expectCommands("apply", commands(function() click(block.apply) end),
        { ".bot totem Thrallbot set strength of earth totem,searing totem,mana spring totem,windfury totem" })
    expectCommands("apply all", commands(function() click(block.applyAll) end),
        { ".bot totem party set strength of earth totem,searing totem,mana spring totem,windfury totem" })
    expectCommands("set needs no extra ask", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem set|party|2|-")
    end), {})
    click(block.preset)
    assert(block.preset.text == "Preset: Caster group", "the preset button picks the next preset")
    expectCommands("apply caster", commands(function() click(block.apply) end),
        { ".bot totem Thrallbot set stoneskin totem,searing totem,mana spring totem,grace of air totem" })
    TB.OnSystemMessage("TBM:ACTION_ERR|totem set|invalid|bad totem")
    assert(TB.lastActionError and TB.lastActionError.intent == "totem set", "a set error is reported")

    click(block.save)
    local dialog = StaticPopupDialogs["TORTOISEBOTSMANAGER_TOTEM_PRESET"]
    assert(dialog and dialog.hasEditBox and dialog.OnAccept and dialog.EditBoxOnEnterPressed, "Save asks for a name")
    local box = { text = "My totems", GetText = function(self) return self.text end }
    local realGetglobal = getglobal
    getglobal = function() return box end
    this = { GetParent = function() return { GetName = function() return "StaticPopup1" end } end }
    dialog.OnAccept()
    getglobal = realGetglobal
    local saved = TB.FindTotemPreset("My totems")
    assert(saved and saved.earth == "stoneskin totem" and saved.air == "none" and saved.water == "auto"
        and saved.fire == "searing totem", "Save stores the shaman's current four slots")
    assert(block.preset.text == "Preset: My totems", "the saved preset shows")
    click(block.delete)
    assert(not TB.FindTotemPreset("My totems"), "Delete removes the shown preset")

    expectCommands("refresh", commands(function() click(TB.botPanel.refreshButton) end),
        { ".bot inv Thrallbot", ".bot totem Thrallbot status", ".bot roster" })

    TB.OnSystemMessage("TBM:ACTION_ACK|totem drop|party|1|-")
    assert(TB.lastActionAck.intent == "totem drop" and not TB.OnTotemAck({ intent = "totem drop" }),
        "Drop totems keeps its own handling")

    setParty({ "Priestbot" }, "Priest")
    expectCommands("priest open", commands(function() TB.OpenBotPanel("Priestbot", "behavior") end),
        { ".bot inv Priestbot" })
    assert(not block.slots.earth.visible and not block.mode.visible and not block.save.visible,
        "other classes never show the totem block")
    TB.CloseBotPanel()
end

-- ── paladin blessings: parser, cycle, commands, window ──
do
    local line = "TBM:BLESSING|Pallybot|warrior=might,paladin=kings,hunter=might,rogue=might,priest=wisdom,"
        .. "shaman=wisdom,mage=wisdom,warlock=auto,druid=light,known=might+wisdom+kings+light"
    local b = TB.ParseBlessingLine(line)
    assert(b and b.name == "Pallybot" and b.classes.warrior == "might" and b.classes.paladin == "kings"
        and b.classes.warlock == "auto" and b.classes.druid == "light", "a full blessing line parses")
    assert(table.getn(b.known) == 4 and b.known[3] == "kings", "known splits on +")
    local noKnown = TB.ParseBlessingLine("TBM:BLESSING|Pallybot|warrior=auto,paladin=auto,hunter=auto,rogue=auto,"
        .. "priest=auto,shaman=auto,mage=auto,warlock=auto,druid=auto,known=")
    assert(noKnown and noKnown.known and table.getn(noKnown.known) == 0, "an empty known list stays empty")
    assert(TB.ParseBlessingLine("TBM:BLESSING|Pallybot|warrior=auto,paladin=auto") == nil, "missing classes are refused")
    assert(TB.ParseBlessingLine((string.gsub(line, "druid=light", "druid=protection"))) == nil,
        "an unknown blessing is refused")
    assert(TB.ParseBlessingLine("TBM:TOTEM|Pallybot|x") == nil and TB.ParseBlessingLine("TBM:BLESSING|") == nil)
    assert(TB.GetBlessings("Pallybot") == nil, "a rejected line must not reach the cache")

    local known = { "might", "kings", "light" }
    local opts = TB.BlessingOptions(known)
    assert(table.getn(opts) == 4 and opts[1] == "auto" and opts[2] == "might" and opts[3] == "kings" and opts[4] == "light",
        "auto plus the trained blessings in order")
    assert(table.getn(TB.BlessingOptions(nil)) == 7 and table.getn(TB.BlessingOptions({})) == 1,
        "no list offers all, an empty list only Auto")
    assert(TB.NextBlessing("auto", known, 1) == "might" and TB.NextBlessing("kings", known, 1) == "light"
        and TB.NextBlessing("light", known, 1) == "auto", "forward wraps back to Auto")
    assert(TB.NextBlessing("auto", known, -1) == "light" and TB.NextBlessing("might", known, -1) == "auto"
        and TB.NextBlessing("kings", known, -1) == "might", "backward wraps to the last blessing")
    assert(TB.NextBlessing("salvation", known, 1) == "might", "an untrained value starts from Auto")
    assert(TB.NextBlessing("auto", {}, 1) == "auto" and TB.NextBlessing("auto", {}, -1) == "auto",
        "a paladin with nothing trained stays on Auto")
    assert(TB.BuildBlessingCommand("Pallybot", "warrior", "kings") == "blessing Pallybot warrior kings"
        and TB.BuildBlessingCommand("Pallybot", "druid", "auto") == "blessing Pallybot druid auto"
        and TB.BuildBlessingCommand("Pallybot", "deathknight", "auto") == nil
        and TB.BuildBlessingCommand("Pallybot", "mage", "protection") == nil, "cell commands are validated")

    -- A group of paladin bot, mage, priest and you (a warrior).
    local classOf = { player = "Warrior", party1 = "Paladin", party2 = "Mage", party3 = "Priest" }
    local realUnitClass = UnitClass
    UnitClass = function(unit)
        local name = classOf[unit] or "Warrior"
        return name, string.upper(name)
    end
    setParty({ "Pallybot", "Magebot", "Priestbot" }, "Paladin")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
    TB.OnSystemMessage("TBM:BOTSTATE|Pallybot|move=follow,loot=on")
    drainQueue()
    TB.RefreshPartyView()
    local button = TB.partyFrame.blessingBtn
    assert(not button.visible, "no entry point without the blessing capability")
    assert(not TB.OpenBlessings(), "the grid will not open without the capability")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,blessing")
    TB.RefreshPartyView()
    assert(button.visible, "the Party tab offers Blessings with the capability and a paladin bot")
    local pallies, present = TB.GetBlessingGroup()
    assert(table.getn(pallies) == 1 and pallies[1] == "Pallybot" and present[1] and present[2] and present[5]
        and present[8] and not present[3], "the group has one paladin bot and four classes")

    expectCommands("open", commands(function() click(button) end), { ".bot blessing party status" })
    local win = TB.blessingsWindow
    assert(win and win.visible, "Blessings opens the grid")
    expectCommands("reply", commands(function()
        TB.OnSystemMessage(line)
        TB.OnSystemMessage("TBM:ACTION_ACK|blessing status|party|1|-")
    end), {})
    local cells = win.rows[1].cells
    -- Columns follow the class order: warrior, paladin, priest, mage.
    assert(cells[1].word == "warrior" and cells[2].word == "paladin" and cells[3].word == "priest"
        and cells[4].word == "mage" and not cells[5].visible, "one column per class present")
    assert(not win.rows[2].name.visible, "one row per paladin bot")
    assert(cells[1].icon.texture[1] == C.BLESSING_ICONS.might and cells[1].label.text == "",
        "a blessing shows its icon")
    assert(cells[3].icon.texture[1] == C.BLESSING_ICONS.wisdom, "priest gets wisdom")
    expectCommands("left click", commands(function() click(cells[1]) end), { ".bot blessing Pallybot warrior wisdom" })
    assert(not cells[1].enabled, "the cell waits for the reply")
    expectCommands("no double send", commands(function() click(cells[1]) end), {})
    expectCommands("fresh line", commands(function()
        TB.OnSystemMessage((string.gsub(line, "warrior=might", "warrior=wisdom")))
        TB.OnSystemMessage("TBM:ACTION_ACK|blessing|bot:Pallybot|1|warrior=wisdom")
    end), {})
    assert(cells[1].enabled and cells[1].icon.texture[1] == C.BLESSING_ICONS.wisdom, "the cell repaints from the reply")
    expectCommands("right click", commands(function()
        this, arg1 = cells[1], "RightButton"
        cells[1].scripts.OnClick(cells[1])
        arg1 = nil
    end), { ".bot blessing Pallybot warrior might" })
    expectCommands("error", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ERR|blessing|unknown-spell|Pallybot has not learned that")
    end), {})
    assert(cells[1].enabled, "an error frees the cell")
    expectCommands("mage forward", commands(function() click(cells[4]) end), { ".bot blessing Pallybot mage kings" })
    TB.OnSystemMessage((string.gsub(line, "mage=wisdom", "mage=light")))
    expectCommands("last blessing to auto", commands(function() click(cells[4]) end), { ".bot blessing Pallybot mage auto" })
    TB.OnSystemMessage(line)

    -- A roster change while open re-asks once; a party without the paladin closes it.
    local watcher = frames["TortoiseBotsManagerBlessingWatcher"]
    expectCommands("group change", commands(function()
        event, this = "PARTY_MEMBERS_CHANGED", watcher
        watcher.scripts.OnEvent(watcher)
        advanceTime(2)
        this, arg1 = watcher, 0.5
        watcher.scripts.OnUpdate(watcher)
    end), { ".bot blessing party status" })
    setParty({ "Magebot", "Priestbot" }, "Paladin")
    classOf.party1 = "Mage"; classOf.party2 = "Priest"
    event, this = "PARTY_MEMBERS_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    advanceTime(2)
    this, arg1 = watcher, 0.5
    watcher.scripts.OnUpdate(watcher)
    assert(not win.visible, "the grid closes when no paladin bot is left")
    TB.RefreshPartyView()
    assert(not button.visible, "the entry point goes with the paladin")

    -- In a raid the status ask goes to the raid.
    local realRaid, realUnitName = GetNumRaidMembers, UnitName
    GetNumRaidMembers = function() return 2 end
    UnitName = function(unit)
        if unit == "raid1" then return "Pallybot" elseif unit == "raid2" then return "Tester" end
        return realUnitName(unit)
    end
    classOf.raid1, classOf.raid2 = "Paladin", "Warrior"
    assert(TB.BlessingScope() == "raid", "a raid group asks as raid")
    TB.RefreshPartyView()
    assert(button.visible, "a paladin bot in a raid offers Blessings")
    expectCommands("raid open", commands(function() click(button) end), { ".bot blessing raid status" })
    TB.CloseBlessings()

    -- Layout: eight paladin bots and every class.
    local raidClasses = { "Paladin", "Paladin", "Paladin", "Paladin", "Paladin", "Paladin", "Paladin", "Paladin",
        "Warrior", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
    GetNumRaidMembers = function() return table.getn(raidClasses) end
    UnitName = function(unit)
        local _, _, index = string.find(unit, "^raid(%d+)$")
        index = tonumber(index)
        if index then return index <= 8 and ("Pal" .. index) or ("Other" .. index) end
        return realUnitName(unit)
    end
    for index, className in ipairs(raidClasses) do classOf["raid" .. index] = className end
    for index = 1, 8 do TB.OnSystemMessage("TBM:BOTSTATE|Pal" .. index .. "|move=follow") end
    assert(TB.OpenBlessings(), "the grid opens in a big raid")
    drainQueue()
    for index = 1, 8 do TB.OnSystemMessage((string.gsub(line, "Pallybot", "Pal" .. index))) end
    local shown = {}
    for r, row in ipairs(win.rows) do
        assert(row.name.visible, "row " .. r .. " shows its paladin")
        for c, cell in ipairs(row.cells) do
            assert(cell.visible, "cell " .. r .. "," .. c .. " shows")
            table.insert(shown, cell)
        end
    end
    assert(win.width >= 12 + 92 + 9 * 36 and win.height > 62 + 8 * 34, "the window grows to the rows and columns")
    TB.CloseBlessings()

    GetNumRaidMembers, UnitName, UnitClass = realRaid, realUnitName, realUnitClass
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
    for index = 1, 8 do TB.OnSystemMessage("TBM:BOTSTATE|Pal" .. index .. "|move=follow") end
end

-- ── target-a-bot shortcut: key binding target, button, setting ──
do
    setParty({ "Targetbot" }, "Priest")
    TB.OnSystemMessage("TBM:BOTSTATE|Targetbot|move=follow,loot=on")
    TB.InitTargetButton()
    local watcher
    for name, frame in pairs(frames) do
        if name == "TortoiseBotsManagerTargetButtonWatcher" then watcher = frame end
    end
    assert(watcher and watcher.events.PLAYER_TARGET_CHANGED, "the target watcher listens for target changes")
    local targetFrame = { name = "TargetFrame" }
    local realGetglobal = getglobal
    getglobal = function(name)
        if name == "TargetFrame" then return targetFrame end
        return realGetglobal(name)
    end
    TB.targetButton = nil
    assert(TB.CreateTargetButton(), "the target button anchors to the target frame")
    getglobal = realGetglobal
    local btn = TB.targetButton
    assert(btn, "the target button exists")

    -- Nobody targeted: closed and hidden, sends nothing.
    setTarget(false, nil)
    event, this = "PLAYER_TARGET_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    assert(TB.GetTargetBot() == nil, "no target is no bot")
    assert(not TB.OpenTargetBotPanel(), "opening with no target fails without sending")
    assert(not btn.visible, "the button hides with no target")

    -- An enemy target is not one of my bots.
    setTarget(true, "Training Dummy")
    event, this = "PLAYER_TARGET_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    assert(TB.GetTargetBot() == nil, "an enemy target is not a bot")
    assert(not TB.OpenTargetBotPanel(), "opening on an enemy fails without sending")
    assert(not btn.visible, "the button hides on an enemy target")

    -- Targeting my bot opens its panel, like the Party bag button.
    setTarget(true, "Targetbot")
    event, this = "PLAYER_TARGET_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    assert(TB.GetTargetBot() == "Targetbot", "the targeted bot resolves by name")
    assert(btn.visible, "the button shows on a targeted bot")
    expectCommands("target panel", commands(function() click(btn) end),
        { ".bot inv Targetbot" })
    assert(TB.botPanel and TB.botPanel.visible, "the button opens the bot panel")
    TB.CloseBotPanel()
    expectCommands("key binding", commands(function() TB.OpenTargetBotPanel() end),
        { ".bot inv Targetbot" })
    TB.CloseBotPanel()

    -- The setting hides the button; the binding still works.
    TortoiseBotsDB.targetButton = nil
    assert(TB.TargetButtonShown(), "the button shows by default")
    TB.SetTargetButtonShown(false)
    assert(not TB.TargetButtonShown() and not btn.visible, "the setting hides the button")
    expectCommands("hidden binding", commands(function() TB.OpenTargetBotPanel() end),
        { ".bot inv Targetbot" })
    TB.CloseBotPanel()
    TB.SetTargetButtonShown(true)
    event, this = "PLAYER_TARGET_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    assert(btn.visible, "showing the setting brings the button back")

    setTarget(true, "Enemy")
    TB.OnSystemMessage("TBM:BOTSTATE|Targetbot|move=follow,loot=on")
    setTarget(false, nil)
end

-- -- Bots overview: one row per party bot, fight chips, panel button -- --
do
    setParty({ "Holdbot", "Magebot" }, "Priest")
    TB.OnSystemMessage("TBM:BOTSTATE|Holdbot|move=follow,loot=on,hold=off")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,hold=on,noblink=off")
    TB.RefreshPartyView()
    local button = TB.partyFrame.botsBtn
    assert(button and button.visible, "the Party tab offers Bots with party bots")
    assert(TB.BotsAvailable(), "BotsAvailable with party bots")
    expectCommands("bots open", commands(function() click(button) end), {})
    local win = TB.botsWindow
    assert(win and win.visible, "Bots opens the overview")

    -- Rows: one per bot, sorted; role line; chips reuse the Behaviour defs.
    assert(win.rows[1].name.visible and win.rows[2].name.visible
        and not win.rows[3].name.visible, "two party bots give two rows")
    assert(win.rows[1].name.text == "Holdbot\nProtection"
        or string.find(win.rows[1].name.text, "Holdbot", 1, true),
        "row 1 names the first bot, got '" .. tostring(win.rows[1].name.text) .. "'")
    assert(win.rows[2].name.visible, "row 2 shows the second bot")
    local chips1 = {}
    for i, chip in ipairs(win.rows[1].chips) do
        if chip.visible then table.insert(chips1, chip) end
    end
    assert(table.getn(chips1) >= 2, "a row shows its fight chips")
    assert(chips1[1].def.key == "hold", "Hold position leads the row")
    assert(win.rows[1].open.visible, "each row opens the full panel")
    local defs = TB.OverviewChips("Holdbot", 1)
    assert(table.getn(defs) <= 4 and defs[1].key == "hold", "max four chips, Hold first")

    -- Chip clicks reuse the behaviour command path, no duplicated strings.
    expectCommands("overview hold", commands(function() click(win.rows[1].chips[1]) end),
        { ".bot behavior Holdbot hold on" })
    TB.OnSystemMessage("TBM:ACTION_ACK|behavior hold|bot:Holdbot|1|on")
    TB.OnSystemMessage("TBM:BOTSTATE|Holdbot|move=follow,loot=on,hold=on")
    TB.RefreshBots()
    assert(win.rows[1].chips[1].state == "on",
        "the row chip repaints from the reply")
    expectCommands("overview open", commands(function() click(win.rows[2].open) end),
        { ".bot inv Magebot" })
    assert(TB.botPanel and TB.botPanel.visible, "Controls opens the full panel")
    TB.CloseBotPanel()
    TB.RefreshBots()

    -- A mage row shows its class chip; a priest row never does.
    local mageChips = {}
    for _, chip in ipairs(win.rows[2].chips) do
        if chip.visible then table.insert(mageChips, chip.def.key) end
    end
    local sawBlink = false
    for _, key in ipairs(mageChips) do if key == "noblink" then sawBlink = true end end
    assert(not sawBlink, "a priest row has no Blink chip")
    setParty({ "Magebot" }, "Mage")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,hold=on,noblink=off")
    TB.RefreshPartyView()
    TB.RefreshBots()
    local only = {}
    for _, chip in ipairs(win.rows[1].chips) do
        if chip.visible then table.insert(only, chip.def.key) end
    end
    sawBlink = false
    for _, key in ipairs(only) do if key == "noblink" then sawBlink = true end end
    assert(sawBlink, "a mage that reports it shows No dungeon Blink")

    -- The window closes when the last party bot leaves.
    local watcher
    for name, frame in pairs(frames) do
        if name == "TortoiseBotsManagerBotsWatcher" then watcher = frame end
    end
    assert(watcher and watcher.events.PARTY_MEMBERS_CHANGED, "the Bots watcher listens for group changes")
    setParty({}, "Priest")
    event, this = "PARTY_MEMBERS_CHANGED", watcher
    watcher.scripts.OnEvent(watcher)
    advanceTime(2)
    this, arg1 = watcher, 0.5
    watcher.scripts.OnUpdate(watcher)
    assert(not TB.BotsAvailable(), "no party bots means no overview")
    assert(not TB.OpenBots(), "Bots will not open with no party bots")
    TB.RefreshPartyView()
    assert(not button.visible, "the entry point hides with no party bots")

    -- Layout estimate: the window fits rows, chips and hint.
    setParty({ "Holdbot", "Magebot" }, "Priest")
    TB.OnSystemMessage("TBM:BOTSTATE|Holdbot|move=follow,loot=on,hold=off")
    TB.OnSystemMessage("TBM:BOTSTATE|Magebot|move=follow,loot=on,hold=on,noblink=off")
    assert(TB.OpenBots(), "Bots reopens for layout")
    win = TB.botsWindow
    assert(win.width >= 12 + 92 + 4 * 128 + 5 * 4 + 76 - 4, "the window fits four chips and Controls")
    assert(win.height > 62 + 2 * 28, "the window grows with the rows")
    for r = 1, 2 do
        for _, chip in ipairs(win.rows[r].chips) do
            if chip.visible then
                assert(string.len(chip.text) * 6 + 14 <= chip.width,
                    "chip '" .. chip.text .. "' fits its button")
            end
        end
    end
    TB.CloseBots()
end

-- -- Class choices: parser, builders, panel, wire -- --
do
    local line = "TBM:CHOICE|Pallybot|aura=devotion aura,known=devotion aura+retribution aura+shadow resistance"
    local c = TB.ParseChoiceLine(line)
    assert(c and c.name == "Pallybot" and c.kind == "aura" and c.value == "devotion aura"
        and table.getn(c.known) == 3 and c.known[3] == "shadow resistance",
        "a choice line parses, spaces and all")
    local noKnown = TB.ParseChoiceLine("TBM:CHOICE|Hexbot|curse=curse of agony")
    assert(noKnown and noKnown.known == nil, "a line without known reads as nil")
    local empty = TB.ParseChoiceLine("TBM:CHOICE|Hexbot|curse=auto,known=")
    assert(empty and empty.value == "auto" and table.getn(empty.known) == 0,
        "an empty known list stays an empty list")
    assert(TB.ParseChoiceLine("TBM:CHOICE|Hexbot|curse=") == nil
        and TB.ParseChoiceLine("TBM:CHOICE||curse=auto") == nil
        and TB.ParseChoiceLine("TBM:CHOICE|Hexbot") == nil
        and TB.ParseChoiceLine("TBM:TOTEM|x|earth=auto") == nil, "short or foreign lines are refused")
    assert(TB.ChoiceKindLabel("aura") == "Aura" and TB.ChoiceKindLabel("aspect") == "Aspect"
        and TB.ChoiceKindLabel("curse") == "Curse", "kind labels capitalise")
    assert(TB.ChoiceLabel("aura", "auto") == "Auto"
        and TB.ChoiceLabel("aura", "devotion aura") == "Devotion Aura"
        and TB.ChoiceLabel("curse", "shadow resistance") == "Shadow Resistance"
        and TB.ChoiceLabel("aura", nil) == "?", "values read capitalised")
    assert(table.getn(TB.ChoiceKinds("Nobody")) == 0, "no records means no kinds")
    assert(table.getn(TB.ChoiceOptions("aura", nil)) == 1
        and table.getn(TB.ChoiceOptions("aura", {})) == 1
        and table.getn(TB.ChoiceOptions("aura", { "devotion aura" })) == 2,
        "Auto alone without known; known lists follow Auto")
    assert(TB.BuildChoiceCommand("Pallybot", "aura", "devotion aura")
            == "choice Pallybot aura devotion aura"
        and TB.BuildChoiceCommand("Hexbot", "curse", "auto") == "choice Hexbot curse auto"
        and TB.BuildChoiceCommand("party", "aura", "auto") == "choice party aura auto"
        and TB.BuildChoiceCommand("Pallybot", "", "auto") == nil
        and TB.BuildChoiceCommand("Pallybot", "aura", "") == nil
        and TB.BuildChoiceCommand(nil, "aura", "auto") == nil, "choice commands are validated")
    assert(TB.ChoiceKindWanted("aura", 2) and not TB.ChoiceKindWanted("aura", 3)
        and TB.ChoiceKindWanted("aspect", 3) and not TB.ChoiceKindWanted("aspect", 2)
        and TB.ChoiceKindWanted("curse", 9) and not TB.ChoiceKindWanted("curse", 5)
        and TB.ChoiceKindWanted("stance", 1), "known kinds gate on class, unknown kinds show")

    -- Wire: open asks, lines fill the picker, ACKs and errors behave.
    setParty({ "Pallybot" }, "Paladin")
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster,choice")
    assert(TB.HasChoiceCapability(), "the choice capability gates the section")
    local knownClasses = { Paladin = "Paladin" }
    local realUnitClass = UnitClass
    UnitClass = function(unit)
        if unit == "player" then return "Warrior", "WARRIOR" end
        return "Paladin", "PALADIN"
    end
    expectCommands("paladin open", commands(function() TB.OpenBotPanel("Pallybot", "behavior") end),
        { ".bot inv Pallybot", ".bot choice Pallybot status" })
    local block = TB.botPanel.choiceBlock
    assert(block.kinds[1] and not block.kinds[1].visible, "no records yet: no choice rows")
    expectCommands("record fills", commands(function()
        TB.OnSystemMessage("TBM:CHOICE|Pallybot|aura=devotion aura,known=devotion aura+retribution aura")
    end), {})
    assert(block.kinds[1].visible and block.kinds[1].text == "Aura: Devotion Aura",
        "the record fills the picker, got '" .. tostring(block.kinds[1].text) .. "'")
    assert(not block.kinds[2].visible, "only recorded kinds show")
    assert(TB.ChoiceKinds("Pallybot")[1] == "aura", "one record means one kind")

    local rows = {}
    assert(TB.BuildChoiceMenu("Pallybot", "aura", function(info) table.insert(rows, info) end) == 3
        and rows[1].text == "Auto" and rows[2].text == "Devotion Aura"
        and rows[3].text == "Retribution Aura" and rows[2].checked == 1 and rows[1].checked == nil,
        "the menu offers Auto plus the trained values, marking the current one")
    expectCommands("pick aura", commands(function() rows[3].func() end),
        { ".bot choice Pallybot aura retribution aura" })
    expectCommands("ack without line", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|choice|bot:Pallybot|1|aura=retribution aura")
    end), { ".bot choice Pallybot status" })
    expectCommands("no repeat ask", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|choice|bot:Pallybot|1|aura=retribution aura")
    end), {})
    expectCommands("fresh line first", commands(function()
        TB.OnSystemMessage("TBM:CHOICE|Pallybot|aura=retribution aura,known=devotion aura+retribution aura")
        TB.OnSystemMessage("TBM:ACTION_ACK|choice|bot:Pallybot|1|aura=retribution aura")
    end), {})
    assert(block.kinds[1].text == "Aura: Retribution Aura", "a fresh line repaints the picker")
    TB.OnSystemMessage("TBM:ACTION_ERR|choice|unknown-spell|Pallybot has not learned that")
    assert(TB.lastActionError and TB.lastActionError.intent == "choice", "a choice error is reported")
    TB.OnSystemMessage("TBM:ACTION_ERR|choice|invalid|usage")
    TB.OnSystemMessage("TBM:ACTION_ERR|choice|no-bot|no such bot")

    -- Status ask for the whole party; cancel the per-bot ask when the error
    -- for a stale order arrives first.
    expectCommands("status", commands(function() TB.RequestChoices("party") end),
        { ".bot choice party status" })
    TB.OnSystemMessage("TBM:CHOICE|Pallybot|aura=auto,known=devotion aura")
    UnitClass = realUnitClass
    expectCommands("party status", commands(function() TB.RequestChoices() end), {})

    -- Other classes: a hunter gets aspect, a priest gets nothing.
    local realBotClass = TB.BotClassId
    TB.BotClassId = function(name)
        if name == "Aspectbot" then return 3 end
        if name == "Cursebot" then return 9 end
        return 2
    end
    TB.BotClassId = realBotClass
    setParty({ "Aspectbot" }, "Hunter")
    expectCommands("hunter open", commands(function() TB.OpenBotPanel("Aspectbot", "behavior") end),
        { ".bot inv Aspectbot", ".bot choice Aspectbot status" })
    TB.OnSystemMessage("TBM:CHOICE|Aspectbot|aspect=hawk,known=hawk+monkey")
    assert(block.kinds[1].visible and block.kinds[1].text == "Aspect: Hawk",
        "a hunter shows its aspect")
    setParty({ "Cursebot" }, "Warlock")
    expectCommands("warlock open", commands(function() TB.OpenBotPanel("Cursebot", "behavior") end),
        { ".bot inv Cursebot", ".bot service Cursebot", ".bot choice Cursebot status" })
    TB.OnSystemMessage("TBM:CHOICE|Cursebot|curse=curse of agony,known=curse of agony+curse of doom")
    assert(block.kinds[1].visible and block.kinds[1].text == "Curse: Curse of Agony",
        "a warlock shows its curse")
    setParty({ "Healbot" }, "Priest")
    expectCommands("priest open", commands(function() TB.OpenBotPanel("Healbot", "behavior") end),
        { ".bot inv Healbot", ".bot choice Healbot status" })
    TB.OnSystemMessage("TBM:CHOICE|Healbot|aura=auto,known=devotion aura")
    assert(not block.kinds[1].visible, "aura never shows for a priest")

    -- No capability: no section, no ask.
    TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
    assert(not TB.HasChoiceCapability(), "the section hides without the capability")
    expectCommands("no cap open", commands(function() TB.OpenBotPanel("Pallybot", "behavior") end),
        { ".bot inv Pallybot" })
    assert(not block.kinds[1].visible, "no capability means no choice rows")
    TB.CloseBotPanel()
end

setParty(savedMembers, savedClass)

print("PASS: community feedback checks")
end
