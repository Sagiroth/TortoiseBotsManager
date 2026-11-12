-- Features added from community feedback: behaviour chips (Hold position, No
-- dungeon Blink) and the shaman totem picker.
-- Run from tests/regression.lua, same shape as tests/wire_cases.lua.

return function(env)
local sent = env.sent
local frames = env.frames
local advanceTime = env.advanceTime
local setParty = env.setParty
local getParty = env.getParty

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
        and TB.TotemLabel("auto") == "Auto" and TB.TotemLabel("none") == "None" and TB.TotemLabel(nil) == "?",
        "totem names read capitalised without the word totem")
    local full = TB.TotemOptions("earth", nil)
    assert(table.getn(full) == 7 and full[1] == "auto" and full[2] == "none" and full[6] == "strength of earth totem",
        "without a known list every earth totem is offered after Auto and None")
    local some = TB.TotemOptions("earth", { "stoneskin totem", "windfury totem" })
    assert(table.getn(some) == 3 and some[3] == "stoneskin totem", "known filters the slot list")
    assert(table.getn(TB.TotemOptions("air", {})) == 2, "no trained totems leaves Auto and None")
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
    setParty({ "Thrallbot" }, "Shaman")
    expectCommands("shaman open", commands(function() TB.OpenBotPanel("Thrallbot", "behavior") end), { ".bot inv Thrallbot", ".bot totem Thrallbot status" })
    local block = TB.botPanel.totemBlock
    assert(block.slots.earth.visible and block.mode.visible and block.apply.visible, "a shaman shows the totem block")
    assert(not block.slots.earth.enabled and block.slots.earth.text == "Earth: ?", "slots wait for the reply")
    TB.OnSystemMessage("TBM:TOTEM|Thrallbot|earth=strength of earth totem,fire=searing totem,water=auto,air=none,"
        .. "mode=auto,known=stoneskin totem+strength of earth totem+searing totem+mana spring totem+windfury totem")
    assert(block.slots.earth.text == "Earth: Strength of Earth" and block.slots.fire.text == "Fire: Searing"
        and block.slots.water.text == "Water: Auto" and block.slots.air.text == "Air: None"
        and block.mode.text == "Drop: Auto" and block.slots.earth.enabled, "the reply fills the controls")
    assert(block.preset.text == "Melee group" and block.apply.enabled, "the first preset shows")

    local rows = {}
    assert(TB.BuildTotemSlotMenu("Thrallbot", "earth", function(info) table.insert(rows, info) end) == 4
        and rows[1].text == "Auto" and rows[2].text == "None" and rows[3].text == "Stoneskin"
        and rows[4].text == "Strength of Earth" and rows[4].checked == 1 and rows[3].checked == nil,
        "the earth menu offers Auto, None and the trained earth totems, marking the current one")
    expectCommands("pick earth", commands(function() rows[3].func() end), { ".bot totem Thrallbot earth stoneskin totem" })
    expectCommands("ack without line", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem earth|bot:Thrallbot|1|stoneskin totem")
    end), { ".bot totem Thrallbot status" })
    expectCommands("no repeat ask", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem earth|bot:Thrallbot|1|stoneskin totem")
    end), {})
    expectCommands("pick air none", commands(function()
        local menu = {}
        TB.BuildTotemSlotMenu("Thrallbot", "air", function(info) table.insert(menu, info) end)
        menu[2].func()
    end), { ".bot totem Thrallbot air none" })
    expectCommands("fresh line first", commands(function()
        TB.OnSystemMessage("TBM:TOTEM|Thrallbot|earth=stoneskin totem,fire=searing totem,water=auto,air=none,mode=auto")
        TB.OnSystemMessage("TBM:ACTION_ACK|totem air|bot:Thrallbot|1|none")
    end), {})
    assert(block.slots.earth.text == "Earth: Stoneskin", "a fresh line repaints the picker")
    assert(TB.BuildTotemSlotMenu("Thrallbot", "air", function() end) == 8, "no known list offers the whole air list")

    expectCommands("mode", commands(function() click(block.mode) end), { ".bot totem Thrallbot mode prepull" })
    expectCommands("apply", commands(function() click(block.apply) end),
        { ".bot totem Thrallbot set strength of earth totem,searing totem,mana spring totem,windfury totem" })
    expectCommands("apply all", commands(function() click(block.applyAll) end),
        { ".bot totem party set strength of earth totem,searing totem,mana spring totem,windfury totem" })
    expectCommands("set needs no extra ask", commands(function()
        TB.OnSystemMessage("TBM:ACTION_ACK|totem set|party|2|-")
    end), {})
    click(block.preset)
    assert(block.preset.text == "Caster group", "the preset button picks the next preset")
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
    assert(block.preset.text == "My totems", "the saved preset shows")
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

setParty(savedMembers, savedClass)

print("PASS: community feedback checks")
end
