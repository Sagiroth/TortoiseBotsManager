-- Wire command parity table and regression checks.
-- Verifies byte-for-byte exact .bot wire output for all controls.

return function(env)
local sent = env.sent
local addonSent = env.addonSent
local frames = env.frames
local advanceTime = env.advanceTime
local setTarget = env.setTarget
local setParty = env.setParty
local setDead = env.setDead
local setGhost = env.setGhost

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

local function updateGroup(members, className)
    setParty(members or {}, className or "Warrior")
    local gw = frames["TortoiseBotsManagerGroupWatcher"]
    if gw and gw.scripts and gw.scripts.OnEvent then
        event, this = "PARTY_MEMBERS_CHANGED", gw
        gw.scripts.OnEvent(gw)
    end
end



local function executeTrigger(triggerFn)
    TB.SetAddonTransport("none")
    local before = table.getn(sent)
    advanceTime(1)
    triggerFn()
    drainQueue()
    local cmds = {}
    for i = before + 1, table.getn(sent) do
        table.insert(cmds, sent[i])
    end
    return cmds
end

-- Clear any leftover queued commands and batches from earlier test suites
drainQueue()
local rbf = frames["TortoiseBotsManagerRosterBatchFrame"]
local safety = 0
while TB.IsRosterBatchActive and TB.IsRosterBatchActive() and safety < 10 do
    safety = safety + 1
    advanceTime(30)
    if rbf and rbf.scripts and rbf.scripts.OnUpdate then
        this = rbf
        rbf.scripts.OnUpdate(rbf)
    end
    drainQueue()
end


-- Table of test cases: each entry has id, trigger, and expected list of commands.


local cases = {
    -- ── Fight Tab (Actions) ────────────────────────────────────────────────
    {
        id = "fight.attack",
        expected = { ".bot action attack" },
        trigger = function()
            setTarget(true, "Enemy")
            TB.Refresh()
            this = TB.actionButtons.attack
            TB.actionButtons.attack.scripts.OnClick(TB.actionButtons.attack)
        end,
    },
    {
        id = "fight.stop",
        expected = { ".bot action stop" },
        trigger = function()
            this = TB.actionButtons.stop
            TB.actionButtons.stop.scripts.OnClick(TB.actionButtons.stop)
        end,
    },
    {
        id = "fight.interrupt",
        expected = { ".bot action interrupt" },
        trigger = function()
            this = TB.actionButtons.interrupt
            TB.actionButtons.interrupt.scripts.OnClick(TB.actionButtons.interrupt)
        end,
    },
    {
        id = "fight.flee",
        expected = { ".bot action flee" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|flee,pull-seconds,inventory,behavior,claimed-roster")
            this = TB.actionButtons.flee
            TB.actionButtons.flee.scripts.OnClick(TB.actionButtons.flee)
        end,
    },
    {
        id = "fight.pull.plain",
        expected = { ".bot action pull" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|flee,inventory,behavior,claimed-roster")
            setTarget(true, "Enemy")
            TB.Refresh()
            this = TB.actionButtons.pull
            TB.actionButtons.pull.scripts.OnClick(TB.actionButtons.pull)
        end,
    },
    {
        id = "fight.pull.timed",
        expected = { ".bot action pull 10" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            TortoiseBotsDB.pullDelay = 10
            setTarget(true, "Enemy")
            TB.Refresh()
            this = TB.actionButtons.pull
            TB.actionButtons.pull.scripts.OnClick(TB.actionButtons.pull)
        end,
    },
    {
        id = "fight.pullback.plain",
        expected = { ".bot action pullback" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|flee,inventory,behavior,claimed-roster")
            setTarget(true, "Enemy")
            TB.Refresh()
            this = TB.actionButtons.pullback
            TB.actionButtons.pullback.scripts.OnClick(TB.actionButtons.pullback)
        end,
    },
    {
        id = "fight.pullback.timed",
        expected = { ".bot action pullback 3" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            TortoiseBotsDB.pullbackDelay = 3
            setTarget(true, "Enemy")
            TB.Refresh()
            this = TB.actionButtons.pullback
            TB.actionButtons.pullback.scripts.OnClick(TB.actionButtons.pullback)
        end,
    },
    {
        id = "fight.focusSkull",
        expected = { ".bot action focus skull" },
        trigger = function()
            this = TB.actionButtons.focusSkull
            TB.actionButtons.focusSkull.scripts.OnClick(TB.actionButtons.focusSkull)
        end,
    },
    {
        id = "fight.follow",
        expected = { ".bot action follow" },
        trigger = function()
            this = TB.actionButtons.follow
            TB.actionButtons.follow.scripts.OnClick(TB.actionButtons.follow)
        end,
    },
    {
        id = "fight.stay",
        expected = { ".bot action stay" },
        trigger = function()
            this = TB.actionButtons.stay
            TB.actionButtons.stay.scripts.OnClick(TB.actionButtons.stay)
        end,
    },
    {
        id = "fight.come",
        expected = { ".bot action come" },
        trigger = function()
            this = TB.actionButtons.come
            TB.actionButtons.come.scripts.OnClick(TB.actionButtons.come)
        end,
    },
    {
        id = "fight.hold",
        expected = { ".bot action come" },
        trigger = function()
            this = TB.actionButtons.hold
            TB.actionButtons.hold.scripts.OnClick(TB.actionButtons.hold)
        end,
    },
    {
        id = "fight.aoe.on",
        expected = { ".bot action aoe on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|aoe=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.aoe
            TB.toggleButtons.aoe.scripts.OnClick(TB.toggleButtons.aoe)
        end,
    },
    {
        id = "fight.aoe.off",
        expected = { ".bot action aoe off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|aoe=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.aoe
            TB.toggleButtons.aoe.scripts.OnClick(TB.toggleButtons.aoe)
        end,
    },
    {
        id = "fight.autocc.on",
        expected = { ".bot action auto cc on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|autocc=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.autocc
            TB.toggleButtons.autocc.scripts.OnClick(TB.toggleButtons.autocc)
        end,
    },
    {
        id = "fight.autocc.off",
        expected = { ".bot action auto cc off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|autocc=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.autocc
            TB.toggleButtons.autocc.scripts.OnClick(TB.toggleButtons.autocc)
        end,
    },
    {
        id = "fight.loot.on",
        expected = { ".bot action loot on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|loot=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.loot
            TB.toggleButtons.loot.scripts.OnClick(TB.toggleButtons.loot)
        end,
    },
    {
        id = "fight.loot.off",
        expected = { ".bot action loot off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|loot=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.loot
            TB.toggleButtons.loot.scripts.OnClick(TB.toggleButtons.loot)
        end,
    },

    -- ── P2: sap/spread switches, end pull, combat tactics ───────────────
    {
        id = "fight.sap.on",
        expected = { ".bot action sap on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|sap=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.sap
            TB.toggleButtons.sap.scripts.OnClick(TB.toggleButtons.sap)
        end,
    },
    {
        id = "fight.sap.off",
        expected = { ".bot action sap off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|sap=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.sap
            TB.toggleButtons.sap.scripts.OnClick(TB.toggleButtons.sap)
        end,
    },
    {
        id = "fight.spread.on",
        expected = { ".bot behavior party spread on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|spread=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.spread
            TB.toggleButtons.spread.scripts.OnClick(TB.toggleButtons.spread)
        end,
    },
    {
        id = "fight.spread.off",
        expected = { ".bot behavior party spread off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|spread=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            this = TB.toggleButtons.spread
            TB.toggleButtons.spread.scripts.OnClick(TB.toggleButtons.spread)
        end,
    },
    {
        id = "fight.endPull",
        expected = { ".bot action end pull" },
        trigger = function()
            this = TB.actionButtons.endPull
            TB.actionButtons.endPull.scripts.OnClick(TB.actionButtons.endPull)
        end,
    },
    {
        id = "fight.tactic.kite",
        expected = { ".bot strategy ~kite" },
        trigger = function()
            this = TB.actionButtons.tacticKite
            TB.actionButtons.tacticKite.scripts.OnClick(TB.actionButtons.tacticKite)
        end,
    },
    {
        id = "fight.tactic.mark",
        expected = { ".bot strategy ~mark rti" },
        trigger = function()
            this = TB.actionButtons.tacticMark
            TB.actionButtons.tacticMark.scripts.OnClick(TB.actionButtons.tacticMark)
        end,
    },
    {
        id = "fight.tactic.focus",
        expected = { ".bot strategy ~focus" },
        trigger = function()
            this = TB.actionButtons.tacticFocus
            TB.actionButtons.tacticFocus.scripts.OnClick(TB.actionButtons.tacticFocus)
        end,
    },
    {
        id = "fight.tactic.aoeFear",
        expected = { ".bot strategy ~aoe fear" },
        trigger = function()
            this = TB.actionButtons.tacticAoeFear
            TB.actionButtons.tacticAoeFear.scripts.OnClick(TB.actionButtons.tacticAoeFear)
        end,
    },

    -- ── CC Menu ────────────────────────────────────────────────────────────
    {
        id = "cc.cycle.moon",
        expected = { ".bot action cc moon Alpha" },
        trigger = function()
            this = TB.ccMenu.rows.moon.cycle
            TB.ccMenu.rows.moon.cycle.scripts.OnClick(TB.ccMenu.rows.moon.cycle)
        end,
    },
    {
        id = "cc.clear.owner",
        expected = { ".bot action cc clear Alpha" },
        trigger = function()
            TB.SetCcAssignment("Alpha", "moon")
            this = TB.ccMenu.rows.moon.clear
            TB.ccMenu.rows.moon.clear.scripts.OnClick(TB.ccMenu.rows.moon.clear)
        end,
    },
    {
        id = "cc.clearAll",
        expected = { ".bot action cc clear" },
        trigger = function()
            this = TB.ccMenu.clearAll
            TB.ccMenu.clearAll.scripts.OnClick(TB.ccMenu.clearAll)
        end,
    },

    -- ── Camp Tab ───────────────────────────────────────────────────────────
    {
        id = "camp.rest",
        expected = { ".bot action rest" },
        trigger = function()
            this = TB.actionButtons.rest
            TB.actionButtons.rest.scripts.OnClick(TB.actionButtons.rest)
        end,
    },
    {
        id = "camp.ready",
        expected = { ".bot action ready" },
        trigger = function()
            this = TB.actionButtons.ready
            TB.actionButtons.ready.scripts.OnClick(TB.actionButtons.ready)
        end,
    },
    {
        id = "camp.repair",
        expected = { ".bot action repair" },
        trigger = function()
            this = TB.actionButtons.repair
            TB.actionButtons.repair.scripts.OnClick(TB.actionButtons.repair)
        end,
    },
    {
        id = "camp.sell",
        expected = { ".bot action sell" },
        trigger = function()
            this = TB.actionButtons.sell
            TB.actionButtons.sell.scripts.OnClick(TB.actionButtons.sell)
        end,
    },
    {
        id = "camp.learn",
        expected = { ".bot action learn" },
        trigger = function()
            this = TB.actionButtons.learn
            TB.actionButtons.learn.scripts.OnClick(TB.actionButtons.learn)
        end,
    },
    {
        id = "camp.release.alive",
        expected = { ".bot action release" },
        trigger = function()
            setDead("party1", false)
            setGhost("party1", false)
            this = TB.actionButtons.release
            TB.actionButtons.release.scripts.OnClick(TB.actionButtons.release)
        end,
    },
    {
        id = "camp.release.ghost",
        expected = { ".bot action corpse run" },
        trigger = function()
            setParty({ "Alpha" }, "Warrior")
            setGhost("party1", true)
            this = TB.actionButtons.release
            TB.actionButtons.release.scripts.OnClick(TB.actionButtons.release)
            setGhost("party1", false)
            setParty({}, "Warrior")
        end,
    },
    -- -- P4 ---------------------------------------------------------------
    {
        id = "camp.rebuff",
        expected = { ".bot action rebuff" },
        trigger = function()
            this = TB.actionButtons.rebuff
            TB.actionButtons.rebuff.scripts.OnClick(TB.actionButtons.rebuff)
        end,
    },
    {
        id = "camp.resetTactics",
        expected = { ".bot strategy reset" },
        trigger = function()
            this = TB.actionButtons.resetTactics
            TB.actionButtons.resetTactics.scripts.OnClick(TB.actionButtons.resetTactics)
        end,
    },
    {
        id = "camp.totem",
        expected = { ".bot totem party drop" },
        trigger = function()
            this = TB.actionButtons.totem
            TB.actionButtons.totem.scripts.OnClick(TB.actionButtons.totem)
        end,
    },
    {
        id = "camp.grind.on",
        expected = { ".bot strategy +grind" },
        trigger = function()
            TB.grindState = nil
            if TB.RefreshCampControls then TB.RefreshCampControls() end
            this = TB.actionButtons.grind
            TB.actionButtons.grind.scripts.OnClick(TB.actionButtons.grind)
        end,
    },
    {
        id = "camp.grind.off",
        expected = { ".bot strategy -grind" },
        trigger = function()
            TB.NoteStrategyChange("+grind")
            this = TB.actionButtons.grind
            TB.actionButtons.grind.scripts.OnClick(TB.actionButtons.grind)
            TB.grindState = nil
            if TB.RefreshCampControls then TB.RefreshCampControls() end
        end,
    },
    {
        id = "camp.grind.parse",
        expected = { ".bot strategy +grind" },
        trigger = function()
            TB.grindState = nil
            TB.OnSystemMessage("Strategy change '+grind' applied to 2 bot(s).")
            assert(TB.GetGrindState() == "on", "grind reply must set grind state")
            assert(TB.actionButtons.grind.isActive, "grind button must show On")
            TB.OnSystemMessage("Strategy change '-grind' applied to 2 bot(s).")
            assert(TB.GetGrindState() == "off", "grind off reply must clear grind state")
            TB.grindState = nil
            if TB.RefreshCampControls then TB.RefreshCampControls() end
            this = TB.actionButtons.grind
            TB.actionButtons.grind.scripts.OnClick(TB.actionButtons.grind)
        end,
    },
    {
        id = "camp.quest.accept",
        expected = { ".bot command Alpha accept", ".bot command Gamma accept" },
        trigger = function()
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|2")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
            TB.OnSystemMessage("TBM:ROSTER|102|Gamma|11|online|0|map:4,zone:5,area:6")
            TB.OnSystemMessage("TBM:ROSTER_END")
            updateGroup({ "Alpha", "Gamma" }, "Warrior")
            this = TB.actionButtons.acceptQuest
            TB.actionButtons.acceptQuest.scripts.OnClick(TB.actionButtons.acceptQuest)
        end,
    },
    {
        id = "camp.quest.share",
        expected = { ".bot command Alpha share", ".bot command Gamma share" },
        trigger = function()
            this = TB.actionButtons.shareQuest
            TB.actionButtons.shareQuest.scripts.OnClick(TB.actionButtons.shareQuest)
            updateGroup({}, "Warrior")
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|2")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER_END")
        end,
    },
    {
        id = "camp.quest.empty",
        expected = { },
        trigger = function()
            updateGroup({}, "Warrior")
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|2")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER_END")
            this = TB.actionButtons.acceptQuest
            TB.actionButtons.acceptQuest.scripts.OnClick(TB.actionButtons.acceptQuest)
            updateGroup({ "Alpha" }, "Priest")
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|2")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
            TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER_END")
        end,
    },
    {
        id = "camp.formation.far.party",
        expected = { ".bot formation far" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.far
            TB.formationPills.far.scripts.OnClick(TB.formationPills.far)
        end,
    },
    {
        id = "camp.formation.melee.party",
        expected = { ".bot formation melee" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.melee
            TB.formationPills.melee.scripts.OnClick(TB.formationPills.melee)
        end,
    },
    {
        id = "camp.formation.chaos.party",
        expected = { ".bot formation chaos" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.chaos
            TB.formationPills.chaos.scripts.OnClick(TB.formationPills.chaos)
        end,
    },
    {
        id = "camp.formation.default.party",
        expected = { ".bot formation default" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.default
            TB.formationPills.default.scripts.OnClick(TB.formationPills.default)
        end,
    },
    {
        id = "camp.formation.shield.party",
        expected = { ".bot formation shield" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.shield
            TB.formationPills.shield.scripts.OnClick(TB.formationPills.shield)
        end,
    },
    {
        id = "camp.formation.near.party",
        expected = { ".bot formation near" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.near
            TB.formationPills.near.scripts.OnClick(TB.formationPills.near)
        end,
    },
    {
        id = "camp.formation.queue.party",
        expected = { ".bot formation queue" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.queue
            TB.formationPills.queue.scripts.OnClick(TB.formationPills.queue)
        end,
    },
    {
        id = "camp.formation.arrow.party",
        expected = { ".bot formation arrow" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.arrow
            TB.formationPills.arrow.scripts.OnClick(TB.formationPills.arrow)
        end,
    },
    {
        id = "camp.formation.circle.party",
        expected = { ".bot formation circle" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.circle
            TB.formationPills.circle.scripts.OnClick(TB.formationPills.circle)
        end,
    },
    {
        id = "camp.formation.line.party",
        expected = { ".bot formation line" },
        trigger = function()
            setTarget(false, nil)
            this = TB.formationPills.line
            TB.formationPills.line.scripts.OnClick(TB.formationPills.line)
        end,
    },
    {
        id = "camp.formation.target.shield",
        expected = { ".bot formation Alpha shield" },
        trigger = function()
            setTarget(true, "Alpha")
            this = TB.formationPills.shield
            TB.formationPills.shield.scripts.OnClick(TB.formationPills.shield)
            setTarget(false, nil)
        end,
    },
    -- -- P10 --------------------------------------------------------------
    {
        id = "npc.talk",
        expected = { ".bot inv Alpha", ".bot command Alpha talk" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.talk
            TB.botNpc.talk.scripts.OnClick(TB.botNpc.talk)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.home",
        expected = { ".bot inv Alpha", ".bot command Alpha home" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.home
            TB.botNpc.home.scripts.OnClick(TB.botNpc.home)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.trainer",
        expected = { ".bot inv Alpha", ".bot command Alpha trainer learn" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.trainer
            TB.botNpc.trainer.scripts.OnClick(TB.botNpc.trainer)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.leader",
        expected = { ".bot inv Alpha", ".bot command Alpha give leader" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.leader
            TB.botNpc.leader.scripts.OnClick(TB.botNpc.leader)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.list",
        expected = { ".bot inv Alpha", ".bot command Alpha taxi ?" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            assert(not TB.IsOperationPending("Alpha", "command"),
                "a taxi query must not leave a command op that times out")
            TB.SetNpcPending("Alpha", false)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.parse",
        expected = { ".bot inv Alpha", ".bot command Alpha taxi ?" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
            assert(not TB.botNpc.rows[1].visible,
                "flight lines before the header must not seed the list")
            TB.OnWhisperMessage("=== Taxi ===", "Alpha")
            TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
            TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
            local flights = TB.GetNpcErrands("Alpha").flights
            assert(flights and table.getn(flights) == 1, "same route stays one row")
            assert(flights[1].n == 1 and flights[1].name == "Stormwind, Elwynn",
                "flight number and name must parse")
            assert(TB.ParseFlightLine("bogus") == nil, "non-route whispers must not parse")
            TB.SetNpcPending("Alpha", false)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.gate",
        expected = { ".bot inv Gamma", ".bot command Gamma taxi ?" },
        trigger = function()
            TB.OpenBotPanel("Gamma")
            TB.OpenNpc("Gamma")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
            assert(table.getn(TB.GetNpcErrands("Gamma").flights) == 0,
                "another bot's whispers must not enter the flight list")
            TB.OnWhisperMessage("some other whisper", "Gamma")
            assert(table.getn(TB.GetNpcErrands("Gamma").flights) == 0,
                "unparseable whispers before the header seed nothing")
            TB.OnWhisperMessage("=== Taxi ===", "Gamma")
            TB.OnWhisperMessage("some other whisper", "Gamma")
            assert(table.getn(TB.GetNpcErrands("Gamma").flights) == 0,
                "non-route lines after the header seed nothing")
            TB.SetNpcPending("Gamma", false)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.fly",
        expected = { ".bot inv Alpha", ".bot command Alpha taxi ?", ".bot command Alpha taxi 2" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            TB.OnWhisperMessage("=== Taxi ===", "Alpha")
            TB.OnWhisperMessage("1: Stormwind, Elwynn", "Alpha")
            TB.OnWhisperMessage("2: Ironforge, Dun Morogh", "Alpha")
            this = TB.botNpc.rows[2]
            TB.botNpc.rows[2].scripts.OnClick(TB.botNpc.rows[2])
            TB.SetNpcPending("Alpha", false)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.page",
        expected = { ".bot inv Alpha", ".bot command Alpha taxi ?", ".bot command Alpha taxi 10" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            TB.OnWhisperMessage("=== Taxi ===", "Alpha")
            for i = 1, 10 do TB.OnWhisperMessage(i .. ": Stop " .. i, "Alpha") end
            assert(TB.botNpc.pageText.text == "1 / 2", "ten routes need two pages")
            this = TB.botNpc.nextPage
            TB.botNpc.nextPage.scripts.OnClick(TB.botNpc.nextPage)
            this = TB.botNpc.rows[4]
            TB.botNpc.rows[4].scripts.OnClick(TB.botNpc.rows[4])
            TB.SetNpcPending("Alpha", false)
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "npc.taxi.stale",
        expected = { ".bot inv Alpha", ".bot command Alpha taxi ?" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            TB.OpenNpc("Alpha")
            this = TB.botNpc.ask
            TB.botNpc.ask.scripts.OnClick(TB.botNpc.ask)
            advanceTime(30)
            assert(TB.ConsumeTaxiReply("Alpha", "1: Stormwind, Elwynn") == false,
                "a quiet flight list closes: late lines return to the gate")
            TB.OnWhisperMessage("I can't fly with you", "Alpha")
            local st = TB.GetState("Alpha")
            assert(not (st and st.pendingAI), "late flight replies complete the command op")
            TB.CloseNpc()
            TB.CloseBotPanel()
        end,
    },
    {
        id = "minibar.attack",
        expected = { ".bot action attack" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.attack
            bar.icons.attack.scripts.OnClick(bar.icons.attack)
        end,
    },
    {
        id = "minibar.stop",
        expected = { ".bot action stop" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.stop
            bar.icons.stop.scripts.OnClick(bar.icons.stop)
        end,
    },
    {
        id = "minibar.interrupt",
        expected = { ".bot action interrupt" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.interrupt
            bar.icons.interrupt.scripts.OnClick(bar.icons.interrupt)
        end,
    },
    {
        id = "minibar.flee",
        expected = { ".bot action flee" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.flee
            bar.icons.flee.scripts.OnClick(bar.icons.flee)
        end,
    },
    {
        id = "minibar.pull",
        expected = { ".bot action pull 10" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            TortoiseBotsDB.pullDelay = 10
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.pull
            bar.icons.pull.scripts.OnClick(bar.icons.pull)
        end,
    },
    {
        id = "minibar.pullback",
        expected = { ".bot action pullback 3" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,claimed-roster")
            TortoiseBotsDB.pullbackDelay = 3
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.pullback
            bar.icons.pullback.scripts.OnClick(bar.icons.pullback)
        end,
    },
    {
        id = "minibar.focusSkull",
        expected = { ".bot action focus skull" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons["focus skull"]
            bar.icons["focus skull"].scripts.OnClick(bar.icons["focus skull"])
        end,
    },
    {
        id = "minibar.follow",
        expected = { ".bot action follow" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.follow
            bar.icons.follow.scripts.OnClick(bar.icons.follow)
        end,
    },
    {
        id = "minibar.stay",
        expected = { ".bot action stay" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.stay
            bar.icons.stay.scripts.OnClick(bar.icons.stay)
        end,
    },
    {
        id = "minibar.come",
        expected = { ".bot action come" },
        trigger = function()
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.come
            bar.icons.come.scripts.OnClick(bar.icons.come)
        end,
    },
    {
        id = "minibar.aoe.on",
        expected = { ".bot action aoe on" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|aoe=off")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.aoe
            bar.icons.aoe.scripts.OnClick(bar.icons.aoe)
        end,
    },
    {
        id = "minibar.aoe.off",
        expected = { ".bot action aoe off" },
        trigger = function()
            TB.togglePending = {}
            TB.OnSystemMessage("TBM:BOTSTATE_BEGIN|1")
            TB.OnSystemMessage("TBM:BOTSTATE|Alpha|aoe=on")
            TB.OnSystemMessage("TBM:BOTSTATE_END")
            setTarget(true, "Enemy")
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.aoe
            bar.icons.aoe.scripts.OnClick(bar.icons.aoe)
        end,
    },

    -- ── Party Tab ──────────────────────────────────────────────────────────
    {
        id = "party.player.warrior.tank",
        expected = { ".bot role self tank" },
        trigger = function()
            setParty({ "Alpha" }, "Warrior")
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[1].roleButtons[1]
            TB.partyFrame.rows[1].roleButtons[1].scripts.OnClick()
        end,
    },
    {
        id = "party.player.warrior.dps",
        expected = { ".bot role self dps" },
        trigger = function()
            setParty({ "Alpha" }, "Warrior")
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[1].roleButtons[3]
            TB.partyFrame.rows[1].roleButtons[3].scripts.OnClick()
        end,
    },
    {
        id = "party.bot.tank",
        expected = { ".bot role Tankbot tank" },
        trigger = function()
            setParty({ "Tankbot" }, "Warrior")
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[1]
            TB.partyFrame.rows[2].roleButtons[1].scripts.OnClick()
        end,
    },
    {
        id = "party.bot.demote_to_dps",
        expected = { ".bot role Tankbot clear", ".bot strategy +arms,-protection Tankbot" },
        trigger = function()
            setParty({ "Tankbot" }, "Warrior")
            TortoiseBotsDB.botRoles["Tankbot"] = "tank"
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[2]
            TB.partyFrame.rows[2].roleButtons[2].scripts.OnClick()
        end,
    },
    {
        id = "party.bot.priest.shadow",
        expected = { ".bot strategy +shadow,-holy,-discipline Priestbot" },
        trigger = function()
            setParty({ "Priestbot" }, "Priest")
            TortoiseBotsDB.botRoles["Priestbot"] = "heal"
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[3]
            TB.partyFrame.rows[2].roleButtons[3].scripts.OnClick()
        end,
    },
    {
        id = "party.bot.bagButton",
        expected = { ".bot inv Alpha" },
        trigger = function()
            setParty({ "Alpha" }, "Warrior")
            TB.ShowTab("party")
            TB.RefreshPartyView()
            local alphaRow = TB.partyFrame.rows[2]
            this = alphaRow.bagButton
            alphaRow.bagButton.scripts.OnClick(alphaRow.bagButton)
            TB.CloseBotPanel()
        end,
    },

    -- ── Roster Tab ─────────────────────────────────────────────────────────
    {
        id = "roster.login",
        expected = { ".bot add Bravo" },
        trigger = function()
            TB.ShowTab("roster")
            if TB.GetState("Bravo") then TB.GetState("Bravo").operation = nil end
            TB.ClearRosterSelection()
            TB.ToggleRosterSelection("Bravo", true)
            TB.Refresh()
            this = TB.lifecycleButtons.login
            TB.lifecycleButtons.login.scripts.OnClick(TB.lifecycleButtons.login)
            if TB.GetState("Bravo") then TB.GetState("Bravo").operation = nil end
            TB.ClearRosterSelection()
        end,
    },
    {
        id = "roster.logout",
        expected = { ".bot logout Alpha" },
        trigger = function()
            TB.ShowTab("roster")
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
            TB.ToggleRosterSelection("Alpha", true)
            TB.Refresh()
            this = TB.lifecycleButtons.logout
            TB.lifecycleButtons.logout.scripts.OnClick(TB.lifecycleButtons.logout)
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
        end,
    },
    {
        id = "roster.invite",
        expected = { ".bot invite Alpha" },
        trigger = function()
            TB.ShowTab("roster")
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
            updateGroup({}, "Priest")
            TB.SetState("Alpha", { group = false })
            TB.ToggleRosterSelection("Alpha", true)
            this = TB.lifecycleButtons.invite
            TB.lifecycleButtons.invite.scripts.OnClick(TB.lifecycleButtons.invite)
            if TB.OnRosterBatchResult then TB.OnRosterBatchResult("Alpha", "invite", true) end
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
        end,
    },
    {
        id = "roster.kick",
        expected = { ".bot uninvite Gamma" },
        trigger = function()
            TB.ShowTab("roster")
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|0|map:1,zone:2,area:3")
            TB.OnSystemMessage("TBM:ROSTER|102|Bravo|8|offline|0|-")
            TB.OnSystemMessage("TBM:ROSTER|103|Gamma|11|online|1|map:4,zone:5,area:6")
            TB.OnSystemMessage("TBM:ROSTER_END")
            if TB.GetState("Gamma") then TB.GetState("Gamma").operation = nil end
            TB.ClearRosterSelection()
            updateGroup({ "Gamma" }, "Druid")
            TB.ToggleRosterSelection("Gamma", true)
            TB.Refresh()
            this = TB.lifecycleButtons.kick
            TB.lifecycleButtons.kick.scripts.OnClick(TB.lifecycleButtons.kick)
            if TB.GetState("Gamma") then TB.GetState("Gamma").operation = nil end
            TB.ClearRosterSelection()
        end,
    },

    {
        id = "roster.summon",
        expected = { ".bot summon Alpha" },
        trigger = function()
            TB.ShowTab("roster")
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
            TB.ToggleRosterSelection("Alpha", true)
            this = TB.lifecycleButtons.summon
            TB.lifecycleButtons.summon.scripts.OnClick(TB.lifecycleButtons.summon)
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            TB.ClearRosterSelection()
        end,
    },


    -- ── Guild Tab ──────────────────────────────────────────────────────────
    {
        id = "guild.invite",
        expected = { ".bot invite Goldie" },
        trigger = function()
            TB.ShowTab("guild")
            TB.ClearClaimedSelection()
            TB.ToggleClaimedSelection("Goldie", true)
            this = TB.guildFrame.inviteBtn
            TB.guildFrame.inviteBtn.scripts.OnClick(TB.guildFrame.inviteBtn)
            if TB.OnRosterBatchResult then TB.OnRosterBatchResult("Goldie", "invite", true) end
            TB.ClearClaimedSelection()
        end,
    },

    {
        id = "guild.summon",
        expected = { ".bot summon Goldie" },
        trigger = function()
            TB.ShowTab("guild")
            TB.ClearClaimedSelection()
            TB.ToggleClaimedSelection("Goldie", true)
            this = TB.guildFrame.summonBtn
            TB.guildFrame.summonBtn.scripts.OnClick(TB.guildFrame.summonBtn)
            TB.ClearClaimedSelection()
        end,
    },
    {
        id = "guild.role.demote",
        expected = { ".bot role Goldie clear", ".bot strategy +arms,-protection Goldie" },
        trigger = function()
            TB.ShowTab("guild")
            TortoiseBotsDB.botRoles["Goldie"] = "tank"
            local row1 = TB.guildFrame.rows[1]
            this = row1.roleBtn
            row1.roleBtn.scripts.OnClick(row1.roleBtn)
        end,
    },
    {
        id = "guild.role.promote_tank",
        expected = { ".bot role Goldie tank" },
        trigger = function()
            TB.ShowTab("guild")
            TortoiseBotsDB.botRoles["Goldie"] = "dps"
            local row1 = TB.guildFrame.rows[1]
            this = row1.roleBtn
            row1.roleBtn.scripts.OnClick(row1.roleBtn)
        end,
    },

    -- ── Raid Tab ───────────────────────────────────────────────────────────
    {
        id = "raid.tankface",
        expected = { ".bot action raid tankface" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            this = TB.raidFrame.tankface
            TB.raidFrame.tankface.scripts.OnClick(TB.raidFrame.tankface)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },
    {
        id = "raid.douse",
        expected = { ".bot action raid douse" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            this = TB.raidFrame.douse
            TB.raidFrame.douse.scripts.OnClick(TB.raidFrame.douse)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },
    {
        id = "raid.custom.on",
        expected = { ".bot action raid custom on" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            TB.OnSystemMessage("TBM:ACTION_ACK|raid custom off|party|2|-")
            this = TB.raidFrame.customToggle
            TB.raidFrame.customToggle.scripts.OnClick(TB.raidFrame.customToggle)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },
    {
        id = "raid.custom.off",
        expected = { ".bot action raid custom off" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            TB.OnSystemMessage("TBM:ACTION_ACK|raid custom on|party|2|-")
            this = TB.raidFrame.customToggle
            TB.raidFrame.customToggle.scripts.OnClick(TB.raidFrame.customToggle)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },
    {
        id = "raid.check",
        expected = { ".bot action raid custom status" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            this = TB.raidFrame.customCheck
            TB.raidFrame.customCheck.scripts.OnClick(TB.raidFrame.customCheck)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },

    {
        id = "raid.status",
        expected = { ".bot action raid status" },
        trigger = function()
            local realRaid = GetNumRaidMembers
            GetNumRaidMembers = function() return 10 end
            TB.UpdateRaidTab()
            this = TB.raidFrame.statusButton
            TB.raidFrame.statusButton.scripts.OnClick(TB.raidFrame.statusButton)
            GetNumRaidMembers = realRaid
            TB.UpdateRaidTab()
        end,
    },

    -- ── Bot Panel ──────────────────────────────────────────────────────────
    {
        id = "botpanel.open",
        expected = { ".bot inv Alpha" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
        end,
    },
    {
        id = "botpanel.trade",
        expected = { ".bot item Alpha trade" },
        trigger = function()
            this = TB.botPanel.tradeButton
            TB.botPanel.tradeButton.scripts.OnClick(TB.botPanel.tradeButton)
        end,
    },
    {
        id = "botpanel.refresh",
        expected = { ".bot inv Alpha", ".bot roster" },
        trigger = function()
            TB._pollPending = false; TB._pollQueued = false
            this = TB.botPanel.refreshButton
            TB.botPanel.refreshButton.scripts.OnClick(TB.botPanel.refreshButton)
        end,
    },
    {
        id = "botpanel.unequip",
        expected = { ".bot item Alpha unequip 255 4" },
        trigger = function()
            TB.botPanel.tabGear.scripts.OnClick(TB.botPanel.tabGear)
            local chest = TB.botPanel.gearButtons[4]
            this = chest
            chest.scripts.OnClick(chest)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            this = menu.first
            menu.first.scripts.OnClick(menu.first)
        end,
    },
    {
        id = "botpanel.equip",
        expected = { ".bot item Alpha equip 20 3" },
        trigger = function()
            TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
            local upgrade = TB.botPanel.bagButtons[2]
            this = upgrade
            upgrade.scripts.OnClick(upgrade)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            this = menu.first
            menu.first.scripts.OnClick(menu.first)
        end,
    },
    {
        id = "botpanel.give",
        expected = { ".bot item Alpha give 20 4" },
        trigger = function()
            TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
            local junk = TB.botPanel.bagButtons[3]
            this = junk
            junk.scripts.OnClick(junk)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            this = menu.second
            menu.second.scripts.OnClick(menu.second)
        end,
    },
    {
        id = "botpanel.behavior.loot.on",
        expected = { ".bot behavior Alpha loot on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").loot = "off"
            local chip = TB.botPanel.behaviorChips.loot
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior loot|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.loot.off",
        expected = { ".bot behavior Alpha loot off" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").loot = "on"
            local chip = TB.botPanel.behaviorChips.loot
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior loot|bot:Alpha|1|off")
        end,
    },
    {
        id = "botpanel.behavior.aoe.on",
        expected = { ".bot behavior Alpha aoe on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").aoe = "off"
            local chip = TB.botPanel.behaviorChips.aoe
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior aoe|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.autocc.on",
        expected = { ".bot behavior Alpha autocc on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").autocc = "off"
            local chip = TB.botPanel.behaviorChips.autocc
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior autocc|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.savemana.on",
        expected = { ".bot behavior Alpha savemana on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").savemana = "off"
            local chip = TB.botPanel.behaviorChips.savemana
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior savemana|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.boost.on",
        expected = { ".bot behavior Alpha boost on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").boost = "off"
            local chip = TB.botPanel.behaviorChips.boost
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior boost|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.threat.on",
        expected = { ".bot behavior Alpha threat on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").threat = "off"
            local chip = TB.botPanel.behaviorChips.threat
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior threat|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.potions.on",
        expected = { ".bot behavior Alpha potions on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").potions = "off"
            local chip = TB.botPanel.behaviorChips.potions
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior potions|bot:Alpha|1|on")
            TB.CloseBotPanel()
        end,
    },
    {
        id = "botpanel.behavior.mimic.on",
        expected = { ".bot behavior Alpha mimic on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").mimic = "off"
            local chip = TB.botPanel.behaviorChips.mimic
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior mimic|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.behavior.spread.on",
        expected = { ".bot behavior Alpha spread on" },
        trigger = function()
            TB.botPanel.tabBehavior.scripts.OnClick(TB.botPanel.tabBehavior)
            TB.GetBotState("Alpha").spread = "off"
            local chip = TB.botPanel.behaviorChips.spread
            this = chip
            chip.scripts.OnClick(chip)
            TB.OnSystemMessage("TBM:ACTION_ACK|behavior spread|bot:Alpha|1|on")
        end,
    },
    {
        id = "botpanel.use",
        expected = { ".bot command Alpha u |Hitem:159:0:0:0|h[Refreshing Spring Water]|h" },
        trigger = function()
            if env.seedItem then env.seedItem(159, { name = "Refreshing Spring Water", quality = 1, texture = "Interface\\Icons\\INV_Drink_07" }) end
            TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
            local water = TB.botPanel.bagButtons[3]
            this = water
            water.scripts.OnClick(water)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            this = menu.third
            menu.third.scripts.OnClick(menu.third)
        end,
    },
    {
        id = "botpanel.sweep",
        expected = { ".bot command Alpha d equip upgrades" },
        trigger = function()
            TB.botPanel.tabBags.scripts.OnClick(TB.botPanel.tabBags)
            this = TB.botPanel.sweepButton
            TB.botPanel.sweepButton.scripts.OnClick(TB.botPanel.sweepButton)
        end,
    },
    {
        id = "botpanel.upkeep",
        expected = { ".bot maintenance Alpha", ".bot roster" },
        trigger = function()
            TB._pollPending = false; TB._pollQueued = false
            this = TB.botPanel.upkeepButton
            TB.botPanel.upkeepButton.scripts.OnClick(TB.botPanel.upkeepButton)
            TB.CloseBotPanel()
        end,
    },
    -- ── P6: BotPanel spellbook ─────────────────────────────────────────────
    {
        id = "p6.spells.ask",
        expected = { ".bot inv Alpha", ".bot command Alpha spells" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            this = TB.botPanel.tabSpells
            TB.botPanel.tabSpells.scripts.OnClick(TB.botPanel.tabSpells)
            this = TB.botPanel.spellAsk
            TB.botPanel.spellAsk.scripts.OnClick(TB.botPanel.spellAsk)
        end,
    },
    {
        id = "p6.spells.parse",
        expected = { ".bot inv Alpha", ".bot command Alpha spells" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:168|h[Frost Armor]|h|r - |cffffff00yellow|r", "Alpha")
            local entry = TB.GetSpellList("Alpha")
            assert(entry and table.getn(entry.spells) == 2, "two spellbook lines must parse")
            assert(entry.spells[1].id == 133 and entry.spells[1].name == "Fireball", "spell id and name must parse")
            assert(entry.spells[2].id == 168 and entry.spells[2].name == "Frost Armor", "trailing skill text must not leak into the name")
            assert(TB.ParseSpellLine("nothing here") == nil, "non-spell whispers must not parse")
            assert(TB.botPanel.spellRows[1].spellName == "Fireball", "first row must show the first spell")
            assert(not (TB.GetState("Alpha") and TB.GetState("Alpha").operation),
                "consumed spell lines clear the command op")
            advanceTime(30)
            assert(TB.ConsumeSpellReply("Alpha", "|cffffffff|Hspell:116|h[Frostbolt]|h|r") == false,
                "late lines after the query must not enter the list")
            assert(table.getn(TB.GetSpellList("Alpha").spells) == 2, "late lines must not grow the list")
        end,
    },
    {
        id = "p6.spells.gate",
        expected = { ".bot inv Gamma", ".bot command Gamma spells" },
        trigger = function()
            TB.OpenBotPanel("Gamma", "spells")
            TB.RequestSpells("Gamma")
            drainQueue()
            TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            assert(table.getn(TB.GetSpellList("Gamma").spells) == 0,
                "another bot's whispers must not enter the panel list")
            TB.OnWhisperMessage("some other whisper", "Gamma")
            local st = TB.GetState("Gamma")
            assert(not (st and st.operation) and not (st and st.pendingAI),
                "non-spell whispers complete the command op")
            assert(table.getn(TB.GetSpellList("Gamma").spells) == 0, "non-spell whispers must not parse")
            TB.SetSpellPending("Gamma", false)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "botpanel.gearup",
        expected = { ".bot inv Alpha", ".bot autogear Alpha", ".bot inv Alpha" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            drainQueue()
            this = TB.botPanel.gearUpButton
            TB.botPanel.gearUpButton.scripts.OnClick(TB.botPanel.gearUpButton)
        end,
    },
    -- P9: advanced item-menu rows (destroy asks first, rest send on click).
    {
        id = "botpanel.disenchant",
        expected = { ".bot inv Alpha", ".bot command Alpha cast Disenchant |Hitem:1201:0:0:0|h[Shadowgem]|h" },
        trigger = function()
            if env.seedItem then env.seedItem(1201, { name = "Shadowgem", quality = 2, texture = "Interface\\Icons\\INV_Misc_Gem_Amethyst_01" }) end
            TB.OpenBotPanel("Alpha", "bags")
            local gem = nil
            for _, b in ipairs(TB.botPanel.bagButtons) do
                if b.visible and b.entry and b.entry.id == 1201 then gem = b break end
            end
            assert(gem, "P9: disenchant fixture must be visible")
            this = gem
            gem.scripts.OnClick(gem)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            assert(menu.fourth.visible and menu.fourth.text == "Disenchant", "P9: Disenchant row must show")
            this = menu.fourth
            menu.fourth.scripts.OnClick(menu.fourth)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "botpanel.sendmail",
        expected = { ".bot inv Alpha", ".bot command Alpha sendmail |Hitem:1201:0:0:0|h[Shadowgem]|h" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "bags")
            local gem = nil
            for _, b in ipairs(TB.botPanel.bagButtons) do
                if b.visible and b.entry and b.entry.id == 1201 then gem = b break end
            end
            assert(gem, "P9: sendmail fixture must be visible")
            this = gem
            gem.scripts.OnClick(gem)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            assert(menu.fifth.visible and menu.fifth.text == "Send by mail", "P9: Send by mail row must show")
            this = menu.fifth
            menu.fifth.scripts.OnClick(menu.fifth)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "botpanel.bank",
        expected = { ".bot inv Alpha", ".bot command Alpha bank |Hitem:1201:0:0:0|h[Shadowgem]|h" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "bags")
            local gem = nil
            for _, b in ipairs(TB.botPanel.bagButtons) do
                if b.visible and b.entry and b.entry.id == 1201 then gem = b break end
            end
            assert(gem, "P9: bank fixture must be visible")
            this = gem
            gem.scripts.OnClick(gem)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            assert(menu.sixth.visible and menu.sixth.text == "Put to bank", "P9: Put to bank row must show")
            this = menu.sixth
            menu.sixth.scripts.OnClick(menu.sixth)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "botpanel.destroy",
        expected = { ".bot inv Alpha", ".bot command Alpha destroy |Hitem:6948:0:0:0|h[Hearthstone]|h", ".bot inv Alpha" },
        trigger = function()
            if env.seedItem then env.seedItem(6948, { name = "Hearthstone", quality = 1, texture = "Interface\\Icons\\INV_Misc_Rune_01" }) end
            TB.OpenBotPanel("Alpha", "bags")
            local stone = nil
            for _, b in ipairs(TB.botPanel.bagButtons) do
                if b.visible and b.entry and b.entry.id == 6948 then stone = b break end
            end
            assert(stone, "P9: destroy fixture must be visible")
            this = stone
            stone.scripts.OnClick(stone)
            local menu = frames["TortoiseBotsManagerItemMenu"]
            assert(menu.seventh.visible and menu.seventh.text == "|cffff5555Destroy|r", "P9: Destroy row must show (red)")
            this = menu.seventh
            menu.seventh.scripts.OnClick(menu.seventh)
            StaticPopupDialogs["TORTOISEBOTSMANAGER_DESTROY_ITEM"].OnAccept()
            TB.CloseBotPanel()
        end,
    },

    -- ── P3: guard/free + combat stances (R17/R19) ──────────────────────────
    {
        id = "fight.guard",
        expected = { ".bot action guard" },
        trigger = function()
            this = TB.actionButtons.guard
            TB.actionButtons.guard.scripts.OnClick(TB.actionButtons.guard)
        end,
    },
    {
        id = "fight.free",
        expected = { ".bot action free" },
        trigger = function()
            this = TB.actionButtons.free
            TB.actionButtons.free.scripts.OnClick(TB.actionButtons.free)
        end,
    },
    {
        id = "fight.stance.near",
        expected = { ".bot action stance near" },
        trigger = function()
            this = TB.stancePills.near
            TB.stancePills.near.scripts.OnClick(TB.stancePills.near)
        end,
    },
    {
        id = "fight.stance.tank",
        expected = { ".bot action stance tank" },
        trigger = function()
            this = TB.stancePills.tank
            TB.stancePills.tank.scripts.OnClick(TB.stancePills.tank)
        end,
    },
    {
        id = "fight.stance.turnback",
        expected = { ".bot action stance turnback" },
        trigger = function()
            this = TB.stancePills.turnback
            TB.stancePills.turnback.scripts.OnClick(TB.stancePills.turnback)
        end,
    },
    {
        id = "fight.stance.behind",
        expected = { ".bot action stance behind" },
        trigger = function()
            this = TB.stancePills.behind
            TB.stancePills.behind.scripts.OnClick(TB.stancePills.behind)
        end,
    },

    -- ── P7 (roster + shell): fill batches reuse the plain invite verb ──────
    {
        id = "roster.fill.party",
        expected = { ".bot invite Alpha", ".bot invite Gamma" },
        trigger = function()
            TB.ShowTab("roster")
            TB.ClearRosterSelection()
            updateGroup({}, "Priest")
            TB.SetState("Alpha", { group = false })
            TB.SetState("Gamma", { group = false })
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            if TB.GetState("Gamma") then TB.GetState("Gamma").operation = nil end
            this = TB.lifecycleButtons.fill
            TB.lifecycleButtons.fill.scripts.OnClick(TB.lifecycleButtons.fill)
            drainQueue()
            if TB.OnRosterBatchResult then
                TB.OnRosterBatchResult("Alpha", "invite", true)
                drainQueue()
                TB.OnRosterBatchResult("Gamma", "invite", true)
            end
            if TB.GetState("Alpha") then TB.GetState("Alpha").operation = nil end
            if TB.GetState("Gamma") then TB.GetState("Gamma").operation = nil end
            TB.ClearRosterSelection()
        end,
    },
    {
        id = "guild.fill.raid",
        expected = { ".bot invite Goldie" },
        trigger = function()
            TB.ShowTab("guild")
            TB.ClearClaimedSelection()
            updateGroup({}, "Priest")
            local goldie = TB.GetClaimedEntry and TB.GetClaimedEntry("Goldie")
            if goldie then
                goldie.online = true
                goldie.enteredWorld = true
                goldie.group = false
            end
            local silver = TB.GetClaimedEntry and TB.GetClaimedEntry("Silver")
            local silverWas = silver and silver.group
            if silver then silver.group = true end
            this = TB.guildFrame.fillBtn
            TB.guildFrame.fillBtn.scripts.OnClick(TB.guildFrame.fillBtn)
            if TB.OnRosterBatchResult then TB.OnRosterBatchResult("Goldie", "invite", true) end
            if silver then silver.group = silverWas end
            TB.ClearClaimedSelection()
        end,
    },


    -- ── P1: role-wire correctness ────────────────────────────────────
    {
        id = "p1.role.warrior.dps",
        expected = { ".bot strategy +arms,-protection Warrspec" },
        trigger = function()
            setParty({ "Warrspec" }, "Warrior")
            TortoiseBotsDB.botRoles["Warrspec"] = nil
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[2]
            TB.partyFrame.rows[2].roleButtons[2].scripts.OnClick()
        end,
    },
    {
        id = "p1.role.paladin.heal",
        expected = { ".bot strategy +holy,-protection,-retribution Pallyspec" },
        trigger = function()
            setParty({ "Pallyspec" }, "Paladin")
            TortoiseBotsDB.botRoles["Pallyspec"] = "dps"
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[2]
            TB.partyFrame.rows[2].roleButtons[2].scripts.OnClick()
        end,
    },
    {
        id = "p1.role.priest.shadow",
        expected = { ".bot strategy +shadow,-holy,-discipline Prispec" },
        trigger = function()
            setParty({ "Prispec" }, "Priest")
            TortoiseBotsDB.botRoles["Prispec"] = "heal"
            TB.ShowTab("party")
            TB.RefreshPartyView()
            this = TB.partyFrame.rows[2].roleButtons[3]
            TB.partyFrame.rows[2].roleButtons[3].scripts.OnClick()
        end,
    },

    {
        id = "p6.spells.cast",
        expected = { ".bot inv Alpha", ".bot command Alpha spells", ".bot command Alpha cast Fireball" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            this = TB.botPanel.spellRows[1]
            TB.botPanel.spellRows[1].scripts.OnClick(TB.botPanel.spellRows[1])
            TB.SetSpellPending("Alpha", false)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "p6.spells.empty",
        expected = { ".bot inv Gamma", ".bot command Gamma spells" },
        trigger = function()
            TB.OpenBotPanel("Gamma", "spells")
            TB.RequestSpells("Gamma")
            assert(TB.ConsumeSpellReply("Gamma", "=== Spells ===") == "header",
                "header alone starts an empty spellbook")
            assert(table.getn(TB.GetSpellList("Gamma").spells) == 0, "no lines means no spells")
            assert(not TB.botPanel.spellAsk.enabled, "Ask waits while more lines may arrive")
            assert(TB.ConsumeSpellReply("Gamma", "|cffffffff|Hspell:133|h[Fireball]|h|r") == 1,
                "duplicate id still counts but must not grow the list")
            assert(TB.ConsumeSpellReply("Gamma", "|cffffffff|Hspell:133|h[Fireball]|h|r") == 1,
                "a repeated line must not duplicate the row")
            assert(table.getn(TB.GetSpellList("Gamma").spells) == 1, "same spell id stays one row")
            TB.SetSpellPending("Gamma", false)
            TB.CloseBotPanel()
        end,
    },
    {
        id = "p6.spells.stale",
        expected = { ".bot inv Alpha", ".bot command Alpha spells" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            advanceTime(30)
            assert(TB.ConsumeSpellReply("Alpha", "|cffffffff|Hspell:133|h[Fireball]|h|r") == false,
                "a quiet spellbook closes: late lines return to the gate")
            TB.OnWhisperMessage("Casting |cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            local st = TB.GetState("Alpha")
            assert(not (st and st.pendingAI), "late cast replies complete the command op")
            TB.CloseBotPanel()
        end,
    },
    {
        id = "p6.spells.no_timeout",
        expected = { ".bot inv Alpha", ".bot command Alpha spells" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            drainQueue()
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            local st = TB.GetState("Alpha")
            assert(not (st and st.operation), "answered spellbook clears the command op")
            assert(not (st and st.pendingAI), "answered spellbook clears the AI reply flag")
            advanceTime(30)
            TB.UpdateStateTimers()
            st = TB.GetState("Alpha")
            assert(not (st and st.lastError), "no timeout error after a consumed spell list")
            TB.CloseBotPanel()
        end,
    },
    {
        id = "p6.spells.cast_reply",
        expected = { ".bot inv Alpha", ".bot command Alpha spells", ".bot command Alpha cast Fireball" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            drainQueue()
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            this = TB.botPanel.spellRows[1]
            TB.botPanel.spellRows[1].scripts.OnClick(TB.botPanel.spellRows[1])
            drainQueue()
            TB.OnWhisperMessage("Casting |cffffffff|Hspell:133|h[Fireball]|h|r", "Alpha")
            assert(table.getn(TB.GetSpellList("Alpha").spells) == 1, "cast reply must not join the spellbook")
            local st = TB.GetState("Alpha")
            assert(not (st and st.pendingAI), "cast reply completes the cast command op")
            assert(not (st and st.operation), "cast reply clears the cast command op")
            TB.CloseBotPanel()
        end,
    },
    {
        id = "p6.spells.paging",
        expected = { ".bot inv Alpha", ".bot command Alpha spells", ".bot command Alpha cast Spell 30", ".bot command Alpha spells" },
        trigger = function()
            TB.OpenBotPanel("Alpha", "spells")
            TB.RequestSpells("Alpha")
            drainQueue()
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            for i = 1, 45 do
                TB.OnWhisperMessage("|cffffffff|Hspell:" .. (100 + i) .. "|h[Spell " .. i .. "]|h|r", "Alpha")
            end
            assert(table.getn(TB.GetSpellList("Alpha").spells) == 45, "all 45 spell lines must land in the list")
            assert(TB.botPanel.spellPageText:GetText() == "1 / 4", "45 spells over 12 rows is 4 pages")
            assert(TB.botPanel.spellRows[1].spellName == "Spell 1", "page 1 starts at the first spell")
            this = TB.botPanel.spellNext
            TB.botPanel.spellNext.scripts.OnClick(TB.botPanel.spellNext)
            TB.botPanel.spellNext.scripts.OnClick(TB.botPanel.spellNext)
            assert(TB.botPanel.spellPageText:GetText() == "3 / 4", "two next clicks reach page 3")
            assert(TB.botPanel.spellRows[1].spellName == "Spell 25", "page 3 starts at spell 25")
            this = TB.botPanel.spellRows[6]
            TB.botPanel.spellRows[6].scripts.OnClick(TB.botPanel.spellRows[6])
            drainQueue()
            this = TB.botPanel.spellNext
            TB.botPanel.spellNext.scripts.OnClick(TB.botPanel.spellNext)
            assert(TB.botPanel.spellPageText:GetText() == "4 / 4", "last page holds the final spells")
            assert(TB.botPanel.spellRows[1].spellName == "Spell 37", "page 4 starts at spell 37")
            assert(TB.botPanel.spellRows[9].visible, "page 4 shows its 9 rows")
            assert(not TB.botPanel.spellRows[10].visible, "empty rows stay hidden on the last page")
            TB.RequestSpells("Alpha")
            drainQueue()
            TB.OnWhisperMessage("=== Spells ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hspell:201|h[Spell 1]|h|r", "Alpha")
            assert(TB.botPanel.spellPageText:GetText() == "1 / 1", "a new list resets to page 1")
            TB.CloseBotPanel()
        end,
    },
    -- ── P8: BotPanel vault (bank + mailbox) ──────────────────────────────
    {
        id = "p8.vault.open",
        expected = { ".bot command Alpha bank" },
        trigger = function()
            TB.OpenVault("Alpha")
            assert(TB.botVault and TB.botVault.visible, "the vault opens")
            assert(TB.GetVaultBot() == "Alpha", "the vault tracks the open bot")
            assert(TB.botVault.tabBank.text == "Bank" and TB.botVault.tabMail.text == "Mailbox",
                "the vault has bank and mailbox tabs")
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.parse",
        expected = { ".bot command Alpha bank" },
        trigger = function()
            TB.OpenVault("Alpha")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3", "Alpha")
            assert(table.getn(TB.GetVault("Alpha").bank) == 0,
                "item lines before the header must not seed the list")
            TB.OnWhisperMessage("=== Bank ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3", "Alpha")
            local vault = TB.GetVault("Alpha")
            assert(vault and table.getn(vault.bank) == 1, "same bank item stays one row")
            assert(vault.bank[1].id == 1234 and vault.bank[1].name == "Linen Cloth" and vault.bank[1].count == 3,
                "bank id, name and count must parse")
            assert(TB.botVault.rows[1].itemId == 1234, "the first row offers the parsed item")
            assert(TB.ParseVaultLine("nothing here") == nil, "non-item whispers must not parse")
            TB.SetVaultPending("Alpha", false)
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.gate",
        expected = { ".bot command Gamma bank" },
        trigger = function()
            advanceTime(30)
            TB.OpenVault("Gamma")
            assert(not TB.IsOperationPending("Gamma", "command"),
                "a vault query must not leave a command op that times out")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r", "Alpha")
            assert(table.getn(TB.GetVault("Gamma").bank) == 0,
                "another bot's whispers must not enter the vault list")
            TB.OnWhisperMessage("some other whisper", "Gamma")
            assert(table.getn(TB.GetVault("Gamma").bank) == 0,
                "unparseable whispers before the header seed nothing")
            TB.OnWhisperMessage("=== Bank ===", "Gamma")
            TB.OnWhisperMessage("some other whisper", "Gamma")
            TB.OnWhisperMessage("#1 |cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r", "Gamma")
            assert(table.getn(TB.GetVault("Gamma").bank) == 0,
                "bank headers must not accept letter lines")
            assert(table.getn(TB.GetVault("Gamma").mail) == 0,
                "bank headers must not leak letter lines into mail")
            TB.SetVaultPending("Gamma", false)
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.withdraw",
        expected = { ".bot command Alpha bank", ".bot command Alpha bank -|Hitem:1234:0:0:0|h[Linen Cloth]|h" },
        trigger = function()
            TB.OpenVault("Alpha")
            TB.OnWhisperMessage("=== Bank ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r", "Alpha")
            this = TB.botVault.rows[1]
            TB.botVault.rows[1].scripts.OnClick(TB.botVault.rows[1])
            TB.SetVaultPending("Alpha", false)
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.mail",
        expected = { ".bot command Alpha mail ?", ".bot command Alpha mail take 1" },
        trigger = function()
            TB.OpenVault("Alpha", "mail")
            assert(not TB.botVault.tabMail.enabled, "the mailbox tab shows while active")
            TB.OnWhisperMessage("=== Mailbox ===", "Alpha")
            TB.OnWhisperMessage("#1 |cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r, |cff00ff000 day(s)", "Alpha")
            assert(table.getn(TB.GetVault("Alpha").mail) == 1, "one letter line parses")
            assert(TB.GetVault("Alpha").mail[1].n == 1, "the letter index parses")
            this = TB.botVault.rows[1]
            TB.botVault.rows[1].scripts.OnClick(TB.botVault.rows[1])
            TB.SetVaultPending("Alpha", false)
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.mailgate",
        expected = { ".bot command Alpha mail ?" },
        trigger = function()
            TB.OpenVault("Alpha", "mail")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r", "Alpha")
            assert(table.getn(TB.GetVault("Alpha").mail) == 0,
                "item lines before the mailbox header must not seed the mail list")
            TB.OnWhisperMessage("=== Mailbox ===", "Alpha")
            TB.OnWhisperMessage("|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r", "Alpha")
            assert(table.getn(TB.GetVault("Alpha").mail) == 0,
                "mail headers must not accept bank lines")
            TB.OnWhisperMessage("#1 thing", "Alpha")
            assert(table.getn(TB.GetVault("Alpha").mail) == 1, "letter lines parse under the mailbox header")
            TB.SetVaultPending("Alpha", false)
        end,
    },
    {
        id = "p8.vault.anchor",
        expected = { ".bot inv Alpha", ".bot command Alpha bank", ".bot command Alpha bank" },
        trigger = function()
            TB.OpenBotPanel("Alpha")
            assert(TB.botPanel and TB.botPanel:IsVisible(), "the panel must be open")
            TB.OpenVault("Alpha")
            assert(TB.botVault.point and TB.botVault.point[2] == TB.botPanel,
                "the vault anchors to the open panel, not over it")
            TB.SetVaultPending("Alpha", false)
            TB.CloseVault()
            TB.CloseBotPanel()
            TB.OpenVault("Alpha")
            assert(TB.botVault.point and TB.botVault.point[2] == TB.frame,
                "the vault falls back to the main window without the panel")
            TB.SetVaultPending("Alpha", false)
            TB.CloseVault()
        end,
    },
    {
        id = "p8.vault.stale",
        expected = { ".bot command Alpha bank" },
        trigger = function()
            TB.OpenVault("Alpha")
            advanceTime(30)
            assert(TB.ConsumeVaultReply("Alpha", "|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r") == false,
                "a quiet vault closes: late lines return to the gate")
            TB.OnWhisperMessage("got |cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|r from bank", "Alpha")
            local st = TB.GetState("Alpha")
            assert(not (st and st.pendingAI), "late withdraw replies complete the command op")
            TB.CloseVault()
        end,
    },
    -- -- P11: dungeon run (Preview) -------------------------------------
    {
        id = "run.gate.off",
        expected = {},
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
            assert(TB.OpenRunWindow() == false, "no window without the capability")
            assert(TB.runWindow == nil or not TB.runWindow:IsVisible(), "no window without the capability")
            assert(TB.SendRunList() == false, "no sends without the capability")
            assert(TB.SendRunStatus() == false, "no sends without the capability")
            assert(TB.SendRunStart("uldaman") == false, "no sends without the capability")
            assert(TB.SendRunPause() == false, "no sends without the capability")
            assert(TB.SendRunResume() == false, "no sends without the capability")
            assert(TB.SendRunSkip() == false, "no sends without the capability")
            assert(TB.SendRunStop() == false, "no sends without the capability")
            assert(TB.SendRunBind() == false, "no sends without the capability")
            assert(TB.SendRunUnbind() == false, "no sends without the capability")
            assert(TB.SendRunEnter() == false, "no sends without the capability")
        end,
    },
    {
        id = "run.open",
        expected = { ".bot run list", ".bot run status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior,dungeon-run")
            assert(TB.tabDungeon:IsVisible(), "the Dungeon tab shows")
            assert(TB.OpenRunWindow() == true, "the window opens with the capability")
            assert(TB.runWindow and TB.runWindow:IsVisible(), "the window is visible")
            TB.CloseRunWindow()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
            assert(not TB.tabDungeon:IsVisible(), "losing the cap hides the tab")
        end,
    },
    {
        id = "run.bind",
        expected = { ".bot run list", ".bot run status", ".bot commander bind Alpha inparty" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            setTarget(true, "Alpha")
            TB.OpenRunWindow()
            this = TB.runWindow.bind
            TB.runWindow.bind.scripts.OnClick(TB.runWindow.bind)
            TB.CloseRunWindow()
            setTarget(false, nil)
        end,
    },
    {
        id = "run.bind.group",
        expected = { ".bot run list", ".bot run status", ".bot commander bind Alpha Delta Gamma inparty" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OnSystemMessage("TBM:ROSTER_BEGIN|3")
            TB.OnSystemMessage("TBM:ROSTER|101|Alpha|1|online|1|map:1,zone:2,area:3")
            TB.OnSystemMessage("TBM:ROSTER|102|Gamma|11|online|1|map:4,zone:5,area:6")
            TB.OnSystemMessage("TBM:ROSTER|103|Delta|5|online|1|map:4,zone:5,area:6")
            TB.OnSystemMessage("TBM:ROSTER_END")
            setParty({ "Alpha", "Gamma", "Delta" }, "Warrior")
            local gw = frames["TortoiseBotsManagerGroupWatcher"]
            if gw and gw.scripts and gw.scripts.OnEvent then
                event, this = "PARTY_MEMBERS_CHANGED", gw
                gw.scripts.OnEvent(gw)
            end
            setTarget(true, "Alpha")
            TB.Refresh()
            assert(TB.OpenRunWindow() == true, "the window opens with the capability")
            this = TB.runWindow.bind
            TB.runWindow.bind.scripts.OnClick(TB.runWindow.bind)
            TB.CloseRunWindow()
            setTarget(false, nil)
            setParty({}, "Priest")
            if gw and gw.scripts and gw.scripts.OnEvent then
                event, this = "PARTY_MEMBERS_CHANGED", gw
                gw.scripts.OnEvent(gw)
            end
        end,
    },
    {
        id = "run.unbind",
        expected = { ".bot run list", ".bot run status", ".bot commander unbind" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            this = TB.runWindow.unbind
            TB.runWindow.unbind.scripts.OnClick(TB.runWindow.unbind)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.enter",
        expected = { ".bot run list", ".bot run status", ".bot cmd enter near" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            this = TB.runWindow.enter
            TB.runWindow.enter.scripts.OnClick(TB.runWindow.enter)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.cmdstatus",
        expected = { ".bot run list", ".bot run status", ".bot commander status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            this = TB.runWindow.cmdStatus
            TB.runWindow.cmdStatus.scripts.OnClick(TB.runWindow.cmdStatus)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.list",
        expected = { ".bot run list", ".bot run status", ".bot run list" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            this = TB.runWindow.plans
            TB.runWindow.plans.scripts.OnClick(TB.runWindow.plans)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.plans.parse",
        expected = { ".bot run list", ".bot run status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("Dungeon plans: uldaman (map 70, 41 steps), ragefire_chasm (map 389, 120 steps, 3 not supported yet)")
            local list = TB.GetRunPlans()
            assert(table.getn(list) == 2, "both plan entries must parse")
            assert(list[1].name == "uldaman" and list[1].map == 70 and list[1].steps == 41
                and list[1].unsupported == 0, "first plan fields must parse")
            assert(list[2].name == "ragefire_chasm" and list[2].unsupported == 3,
                "the unsupported tail must parse")
            TB.SetRunPlanPicker(true)
            assert(TB.runWindow.planRows[1].visible, "plan rows render")
            TB.SetRunPlanPicker(false)
            assert(TB.ParseRunPlanList("Dungeon plans: none loaded") ~= nil
                and table.getn(TB.ParseRunPlanList("Dungeon plans: none loaded")) == 0,
                "an empty plan list parses")
            assert(TB.ParseRunPlanList("someone: hello") == nil, "chat never parses as plans")
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.bind.hire",
        expected = { ".bot run list", ".bot run status", ".bot commander bind Alpha Hirey inparty" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            setParty({ "Hirey" })
            TB.OnSystemMessage("TBM:BOTSTATE|Hirey|move=follow")
            setTarget(true, "Alpha")
            TB.OpenRunWindow()
            this, arg1 = TB.runWindow.bind, "LeftButton"
            TB.runWindow.bind.scripts.OnClick(TB.runWindow.bind)
            TB.CloseRunWindow()
            setTarget(false, nil)
            setParty({})
            arg1 = nil
        end,
    },
    {
        id = "run.start.none",
        expected = { ".bot run list", ".bot run status", ".bot run start" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.SetRunSelectedPlan(nil)
            this = TB.runWindow.start
            TB.runWindow.start.scripts.OnClick(TB.runWindow.start)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.start.player",
        expected = { ".bot run list", ".bot run status", ".bot run start uldaman player" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            this = TB.runWindow.modeYou
            TB.runWindow.modeYou.scripts.OnClick(TB.runWindow.modeYou)
            assert(TB.GetRunMode() == "player", "I lead picks the player-led mode")
            assert(not TB.runWindow.bind.enabled, "player-led needs no Bind")
            TB.SetRunSelectedPlan("uldaman")
            this = TB.runWindow.start
            TB.runWindow.start.scripts.OnClick(TB.runWindow.start)
            TB.OnSystemMessage("TBM:RUN|uldaman|running|1/41|baelog|move|walk|walking")
            assert(TB.WarnRunPause() == false, "player-led orders never pause the run")
            TB.OnSystemMessage("TBM:RUN|-|none|0/0|-|-|-|no run")
            TB.SetRunMode("bot")
            TB.SetRunSelectedPlan(nil)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.start.player.tank",
        expected = { ".bot run list", ".bot run status", ".bot run start player tank Alpha" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            setTarget(true, "Alpha")
            TB.OpenRunWindow()
            TB.SetRunMode("player")
            this = TB.runWindow.start
            TB.runWindow.start.scripts.OnClick(TB.runWindow.start)
            TB.SetRunMode("bot")
            TB.CloseRunWindow()
            setTarget(false, nil)
        end,
    },
    {
        id = "run.start.plan",
        expected = { ".bot run list", ".bot run status", ".bot run start uldaman" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("Dungeon plans: uldaman (map 70, 41 steps)")
            TB.SetRunPlanPicker(true)
            this = TB.runWindow.planRows[1]
            TB.runWindow.planRows[1].scripts.OnClick(TB.runWindow.planRows[1])
            assert(TB.GetRunSelectedPlan() == "uldaman", "clicking a plan picks it")
            this = TB.runWindow.start
            TB.runWindow.start.scripts.OnClick(TB.runWindow.start)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.start.from",
        expected = {},
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|pull-seconds")
            assert(TB.SendRunStart("uldaman", "leg", "baelog") == false,
                "from-starts stay gated on the capability too")
        end,
    },
    {
        id = "run.pause",
        expected = { ".bot run list", ".bot run status", ".bot run pause" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851")
            this = TB.runWindow.pause
            TB.runWindow.pause.scripts.OnClick(TB.runWindow.pause)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.resume",
        expected = { ".bot run list", ".bot run status", ".bot run resume" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|paused|7/41|baelog|pull|pull|paused by .bot run pause")
            this = TB.runWindow.resume
            TB.runWindow.resume.scripts.OnClick(TB.runWindow.resume)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.skip",
        expected = { ".bot run list", ".bot run status", ".bot run skip" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|paused|7/41|baelog|pull|pull|paused by .bot run pause")
            this = TB.runWindow.skip
            TB.runWindow.skip.scripts.OnClick(TB.runWindow.skip)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.stop",
        expected = { ".bot run list", ".bot run status", ".bot run stop" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851")
            TB.SetRunStopReason("")
            this = TB.runWindow.stop
            TB.runWindow.stop.scripts.OnClick(TB.runWindow.stop)
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.stop.reason",
        expected = { ".bot run list", ".bot run status", ".bot run stop time limit reached (3h)" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851")
            TB.SetRunStopReason("time limit reached (3h)")
            this = TB.runWindow.stop
            TB.runWindow.stop.scripts.OnClick(TB.runWindow.stop)
            TB.SetRunStopReason("")
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.status",
        expected = { ".bot run list", ".bot run status", ".bot run status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.CloseRunWindow()
            advanceTime(1)
            assert(TB.SendRunStatus() == true, "status sends with the capability")
        end,
    },
    {
        id = "run.parse",
        expected = { ".bot run list", ".bot run status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|-|none|0/0|-|-|-|no run")
            assert(TB.GetRun().state == "none", "'no run' parses")
            assert(TB.runWindow.runState.text == "- · No run", "no run renders")
            assert(not TB.runWindow.pause:IsVisible() and TB.runWindow.resume:IsVisible(),
                "Resume shows, Pause hides with no run")
            assert(not TB.runWindow.resume.enabled, "Resume waits with no run")
            TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851")
            local r = TB.GetRun()
            assert(r.plan == "uldaman" and r.state == "running" and r.step == 7 and r.steps == 41
                and r.leg == "baelog" and r.kind == "pull" and r.phase == "pull"
                and r.note == "pulling 4851", "the 8-field line parses")
            assert(TB.runWindow.runStep.text == "Step 7 of 41", "step x/y renders")
            assert(TB.runWindow.pause:IsVisible() and not TB.runWindow.resume:IsVisible(),
                "Pause shows while running")
            assert(not TB.runWindow.start.enabled, "Start waits while a run goes")
            TB.OnSystemMessage("TBM:RUN|uldaman|running|178/204|keepers|hold|fight 1/4 down|event: fighting (1 of 4 down, 1 awake)|left 2|speed 1x (test)")
            r = TB.GetRun()
            assert(r.phase == "fight 1/4 down", "event phases with spaces parse")
            assert(r.note == "event: fighting (1 of 4 down, 1 awake)", "notes with spaces parse")
            assert(r.left == 2, "'left K' parses")
            assert(r.speed == "1x (test)", "speed extras parse")
            assert(string.find(TB.runWindow.runPhase.text, "Left: 2", 1, true), "'left K' renders")
            TB.OnSystemMessage("TBM:RUN|uldaman|paused|12/41|baelog|boss|begin|3 dead: regroup")
            assert(TB.GetRun().state == "paused", "pause parses")
            assert(not TB.runWindow.pause:IsVisible() and TB.runWindow.resume.enabled,
                "Resume enables on pause")
            assert(TB.ParseRunLine("TBM:RUN|short") == nil, "short lines never parse")
            assert(TB.ParseRunLine("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|") ~= nil,
                "an empty note parses as '-'")
            TB.CloseRunWindow()
        end,
    },
    {
        id = "run.pausewarn",
        expected = { ".bot run list", ".bot run status", ".bot action stop" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenRunWindow()
            TB.OnSystemMessage("TBM:RUN|uldaman|running|7/41|baelog|pull|pull|pulling 4851")
            TB.CloseRunWindow()
            assert(TB.WarnRunPause() == true, "a running run warns")
            local warned = nil
            local realSetStatus = TB.SetStatus
            TB.SetStatus = function(msg) warned = msg end
            TB.SendActionIntent("stop")
            TB.SetStatus = realSetStatus
            assert(warned == "That order pauses the dungeon run (Resume to go on).",
                "gameplay clicks warn while a run is running")
            TB.OnSystemMessage("TBM:RUN|uldaman|paused|7/41|baelog|pull|pull|paused by .bot run pause")
            assert(TB.WarnRunPause() == false, "a paused run stays quiet")
        end,
    },
    {
        id = "run.exclusive",
        expected = { ".bot inv Alpha", ".bot command Alpha bank", ".bot run list", ".bot run status", ".bot run list", ".bot run status" },
        trigger = function()
            TB.OnSystemMessage("TBM:CAPS|dungeon-run")
            TB.OpenBotPanel("Alpha")
            TB.OpenVault("Alpha")
            assert(TB.botVault:IsVisible(), "the vault opens first")
            TB.OpenRunWindow()
            assert(TB.runWindow:IsVisible() and not TB.botVault:IsVisible(),
                "the run window closes the vault")
            TB.OpenNpc("Alpha")
            assert(TB.botNpc:IsVisible() and not TB.runWindow:IsVisible(),
                "NPC closes the run window")
            TB.OpenRunWindow()
            TB.CloseBotPanel()
            assert(not TB.runWindow:IsVisible(), "the run window closes with its parent")
            TB.SetVaultPending("Alpha", false)
            TB.OnSystemMessage("TBM:CAPS|pull-seconds,flee,inventory,behavior")
        end,
    },
}

for _, tc in ipairs(cases) do
    local actual = executeTrigger(tc.trigger)
    if table.getn(actual) ~= table.getn(tc.expected) then
        print("MISMATCH FOR " .. tc.id .. ": got " .. table.getn(actual) .. " (" .. table.concat(actual, " , ") .. ")")
    end
    assert(table.getn(actual) == table.getn(tc.expected),
        string.format("Case %s: expected %d commands, got %d", tc.id, table.getn(tc.expected), table.getn(actual)))
    for idx, exp in ipairs(tc.expected) do

        assert(actual[idx] == exp,
            string.format("Case %s [%d]: expected '%s', got '%s'", tc.id, idx, exp, tostring(actual[idx])))
    end
end

print(string.format("PASS: %d controls verified byte-for-byte on the wire", table.getn(cases)))
end
