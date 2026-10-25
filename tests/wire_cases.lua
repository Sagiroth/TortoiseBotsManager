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

    -- ── MiniBar Icons ──────────────────────────────────────────────────────
    {
        id = "minibar.attack",
        expected = { ".bot action attack" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.attack
            bar.icons.attack.scripts.OnClick(bar.icons.attack)
        end,
    },
    {
        id = "minibar.stop",
        expected = { ".bot action stop" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.stop
            bar.icons.stop.scripts.OnClick(bar.icons.stop)
        end,
    },
    {
        id = "minibar.interrupt",
        expected = { ".bot action interrupt" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.interrupt
            bar.icons.interrupt.scripts.OnClick(bar.icons.interrupt)
        end,
    },
    {
        id = "minibar.flee",
        expected = { ".bot action flee" },
        trigger = function()
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
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.pullback
            bar.icons.pullback.scripts.OnClick(bar.icons.pullback)
        end,
    },
    {
        id = "minibar.focusSkull",
        expected = { ".bot action focus skull" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons["focus skull"]
            bar.icons["focus skull"].scripts.OnClick(bar.icons["focus skull"])
        end,
    },
    {
        id = "minibar.follow",
        expected = { ".bot action follow" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.follow
            bar.icons.follow.scripts.OnClick(bar.icons.follow)
        end,
    },
    {
        id = "minibar.stay",
        expected = { ".bot action stay" },
        trigger = function()
            local bar = TB.miniBar or frames["TortoiseBotsManagerMiniBar"]
            this = bar.icons.stay
            bar.icons.stay.scripts.OnClick(bar.icons.stay)
        end,
    },
    {
        id = "minibar.come",
        expected = { ".bot action come" },
        trigger = function()
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
            this = TB.partyFrame.rows[1].roleButtons[2]
            TB.partyFrame.rows[1].roleButtons[2].scripts.OnClick()
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
        expected = { ".bot role Tankbot clear", ".bot command Tankbot +arms,-protection" },
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
        expected = { ".bot command Priestbot +shadow,-holy,-discipline,-offdps" },
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
            if TB.GetState("Gamma") then TB.GetState("Gamma").operation = nil end
            TB.ClearRosterSelection()
            updateGroup({ "Gamma" }, "Druid")
            TB.SetState("Gamma", { group = true })
            TB.ToggleRosterSelection("Gamma", true)
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
        expected = { ".bot role Goldie clear", ".bot command Goldie +arms,-protection" },
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


}

-- Execute each case and verify byte-for-byte wire text
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
