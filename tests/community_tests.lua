-- Behaviour chips added from community feedback: Hold position, No dungeon Blink.
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

setParty(savedMembers, savedClass)

print("PASS: community feedback checks")
end
