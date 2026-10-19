-- tests/phase1_tests.lua
-- Unit and regression tests for Phase 1:
--   1. MiniBar icon picker and options popup
--   2. Roster guild filter and actions preservation
--   3. Unified Actions tab (Fight + Camp merged)
--   4. Modern flat look components and styling

return function()
    local TB = TortoiseBots
    local C = TB.C or {}

    -- ──────────────────────────────────────────────────────────────────────────
    -- 1. MiniBar icon picker
    -- ──────────────────────────────────────────────────────────────────────────
    assert(type(TB.GetDefaultMiniBarIcons) == "function", "TB.GetDefaultMiniBarIcons must be exported")
    assert(type(TB.IsMiniBarIconActive) == "function", "TB.IsMiniBarIconActive must be exported")
    assert(type(TB.SetMiniBarIconActive) == "function", "TB.SetMiniBarIconActive must be exported")
    assert(type(TB.ResetMiniBarIcons) == "function", "TB.ResetMiniBarIcons must be exported")
    assert(type(TB.ToggleMiniBarOptions) == "function", "TB.ToggleMiniBarOptions must be exported")
    assert(type(TB.RebuildMiniBar) == "function", "TB.RebuildMiniBar must be exported")

    -- Test defaults
    local defaultIcons = TB.GetDefaultMiniBarIcons()
    assert(table.getn(defaultIcons) == 11, "Default mini bar must contain 11 icons")
    assert(defaultIcons[1] == "attack", "First default icon must be attack")
    assert(TB.IsMiniBarIconActive("attack") == true, "Attack must be active by default")
    assert(TB.IsMiniBarIconActive("stop") == true, "Stop must be active by default")
    assert(TB.IsMiniBarIconActive("sell") == false, "Sell must be inactive by default")

    -- Ensure bar is created
    if not TB.miniBar then
        if TB.ToggleMiniBar then TB.ToggleMiniBar() end
    end
    assert(TB.miniBar ~= nil, "TB.miniBar must exist")
    assert(TB.miniBar.icons["attack"] ~= nil, "attack icon must exist on mini bar")

    -- Test customizing icons via SetMiniBarIconActive
    TB.SetMiniBarIconActive("sell", true)
    assert(TB.IsMiniBarIconActive("sell") == true, "Sell must be active after enabling")
    assert(TortoiseBotsDB.miniBarIcons ~= nil, "TortoiseBotsDB.miniBarIcons must be stored")
    assert(TB.miniBar.icons["sell"] ~= nil, "Sell icon must be rendered on mini bar after rebuild")

    TB.SetMiniBarIconActive("attack", false)
    assert(TB.IsMiniBarIconActive("attack") == false, "Attack must be inactive after disabling")
    assert(TB.miniBar.icons["attack"] == nil, "Attack icon must be removed from mini bar after rebuild")

    -- Test options popup
    TB.ToggleMiniBarOptions()
    local optFrame = TB.miniBarOptions
    assert(optFrame and optFrame:IsVisible(), "MiniBar options popup must be visible after ToggleMiniBarOptions")
    assert(table.getn(optFrame.rows) >= 11, "Options popup must have row items")
    assert(optFrame.resetBtn ~= nil, "Options popup must have Reset button")
    assert(optFrame.closeBtn ~= nil, "Options popup must have Close button")

    -- Test ResetMiniBarIcons
    TB.ResetMiniBarIcons()
    assert(TortoiseBotsDB.miniBarIcons == nil, "ResetMiniBarIcons must clear TortoiseBotsDB.miniBarIcons")
    assert(TB.IsMiniBarIconActive("attack") == true, "Attack must be active after reset")
    assert(TB.IsMiniBarIconActive("sell") == false, "Sell must be inactive after reset")
    assert(TB.miniBar.icons["attack"] ~= nil, "Attack icon must be restored on mini bar")
    assert(TB.miniBar.icons["sell"] == nil, "Sell icon must be removed from mini bar on reset")

    -- Close options popup
    TB.ToggleMiniBarOptions()
    assert(not optFrame:IsVisible(), "MiniBar options popup must hide after toggle")

    print("PASS: Phase 1 mini bar icon picker checks")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 2. Roster guild filter and actions preservation
    -- ──────────────────────────────────────────────────────────────────────────
    assert(type(TB.SetRosterFilter) == "function", "TB.SetRosterFilter must be exported")
    assert(type(TB.GetRosterFilter) == "function", "TB.GetRosterFilter must be exported")

    TB.ShowTab("roster")
    assert(TB.rosterFrame:IsVisible(), "Roster frame must be visible when on roster tab")
    assert(not TB.guildFrame:IsVisible(), "Guild frame must be hidden when on owned filter")
    assert(TB.GetRosterFilter() == "owned", "Default roster filter must be owned")

    -- Toggle to claimed/guild filter
    TB.SetRosterFilter("guild")
    assert(TB.GetRosterFilter() == "guild", "Roster filter must be guild after SetRosterFilter('guild')")
    assert(TB.guildFrame:IsVisible(), "Guild frame must become visible after switching to guild filter")
    assert(not TB.rosterFrame:IsVisible(), "Roster frame must be hidden when on guild filter")

    -- Verify filter pills state
    assert(TB.rosterPills and TB.rosterPills.owned and TB.rosterPills.guild, "Roster filter pills must exist")
    for _, p in ipairs(TB.rosterPills.guild) do
        assert(p:IsActive() == true, "Claimed pill must be active when on guild filter")
    end
    for _, p in ipairs(TB.rosterPills.owned) do
        assert(p:IsActive() == false, "Owned pill must be inactive when on guild filter")
    end

    -- Verify all Guild controls preserved
    local gf = TB.guildFrame
    assert(gf.inviteBtn ~= nil, "Guild frame must preserve inviteBtn (Invite to Raid)")
    assert(gf.summonBtn ~= nil, "Guild frame must preserve summonBtn (Summon to Raid)")
    assert(gf.syncBtn ~= nil, "Guild frame must preserve syncBtn (Sync)")
    assert(gf.checkAll ~= nil, "Guild frame must preserve checkAll")
    assert(gf.scroll ~= nil, "Guild frame must preserve scroll")
    assert(gf.rows and table.getn(gf.rows) == 7, "Guild frame must have 7 rows")
    local grow1 = gf.rows[1]
    assert(grow1.check ~= nil, "Guild row must preserve check")
    assert(grow1.bagBtn ~= nil, "Guild row must preserve bagBtn (gear & bags)")
    assert(grow1.roleBtn ~= nil, "Guild row must preserve roleBtn (cycle combat role)")
    assert(grow1.relBtn ~= nil, "Guild row must preserve relBtn (release claimed bot)")

    -- Toggle back to owned
    TB.SetRosterFilter("owned")
    assert(TB.GetRosterFilter() == "owned", "Roster filter must be owned after SetRosterFilter('owned')")
    assert(TB.rosterFrame:IsVisible(), "Roster frame must be visible")
    assert(not TB.guildFrame:IsVisible(), "Guild frame must be hidden")
    for _, p in ipairs(TB.rosterPills.owned) do
        assert(p:IsActive() == true, "Owned pill must be active when on owned filter")
    end
    for _, p in ipairs(TB.rosterPills.guild) do
        assert(p:IsActive() == false, "Claimed pill must be inactive when on owned filter")
    end

    -- ──────────────────────────────────────────────────────────────────────────
    -- 3. 5-tab structure and Actions tab unification
    -- ──────────────────────────────────────────────────────────────────────────
    assert(TB.tabActions and TB.tabParty and TB.tabRoster and TB.tabRaid and TB.tabLog,
        "All 5 primary tabs must exist")
    assert(TB.tabActions.text.text == "Actions", "tabActions label must be 'Actions'")
    assert(TB.tabParty.text.text == "Party", "tabParty label must be 'Party'")
    assert(TB.tabRoster.text.text == "Roster", "tabRoster label must be 'Roster'")
    assert(TB.tabRaid.text.text == "Raid", "tabRaid label must be 'Raid'")
    assert(TB.tabLog.text.text == "Log", "tabLog label must be 'Log'")

    TB.ShowTab("actions")
    assert(TB.actionsFrame:IsVisible(), "actionsFrame must be visible")
    -- Combat controls on Actions
    assert(TB.actionButtons.attack ~= nil, "attack button must exist on Actions")
    assert(TB.actionButtons.stop ~= nil, "stop button must exist on Actions")
    assert(TB.actionButtons.flee ~= nil, "flee button must exist on Actions")
    assert(TB.actionButtons.hold ~= nil and TB.actionButtons.hold.text == "Hold", "hold button must have label 'Hold'")
    assert(TB.actionButtons.come ~= nil and TB.actionButtons.come.text == "Come", "come button must have label 'Come'")
    local holdDef = TB.GetActionDefinition("hold")
    local comeDef = TB.GetActionDefinition("come")
    assert(holdDef and holdDef.label == "Hold", "hold definition must have label 'Hold'")
    assert(comeDef and comeDef.label == "Come", "come definition must have label 'Come'")
    assert(holdDef and string.find(holdDef.tip, "stop where they are and hold position", 1, true),
        "hold tooltip must describe stopping and holding position")
    assert(comeDef and string.find(comeDef.tip, "come to you and hold there", 1, true),
        "come tooltip must describe coming to you and holding there")
    -- Camp chores on Actions
    assert(TB.actionButtons.rest ~= nil, "rest button must exist on Actions")
    assert(TB.actionButtons.ready ~= nil, "ready button must exist on Actions")
    assert(TB.actionButtons.repair ~= nil, "repair button must exist on Actions")
    assert(TB.actionButtons.sell ~= nil, "sell button must exist on Actions")
    assert(TB.actionButtons.learn ~= nil, "learn button must exist on Actions")
    assert(TB.actionButtons.release ~= nil, "release button must exist on Actions")
    -- Switches and formations on Actions
    assert(TB.actionButtons.aoe ~= nil and TB.toggleButtons.aoe ~= nil, "aoe switch must exist on Actions")
    assert(TB.actionButtons["auto cc"] ~= nil and TB.toggleButtons.autocc ~= nil, "autocc switch must exist on Actions")
    assert(TB.actionButtons.loot ~= nil and TB.toggleButtons.loot ~= nil, "loot switch must exist on Actions")
    assert(TB.formationPills ~= nil, "formation pills must exist on Actions")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 4. Modern flat styling
    -- ──────────────────────────────────────────────────────────────────────────
    assert(TB.C.COLOR.border ~= nil, "Flat border color must be defined in TB.C.COLOR")
    assert(TB.C.COLOR.accent ~= nil, "Accent color must be defined in TB.C.COLOR")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 5. Phase 1 Polish checks
    -- ──────────────────────────────────────────────────────────────────────────
    -- Flat button kit methods and state handling
    local dummyParent = CreateFrame("Frame", nil, UIParent)
    local flatBtn = TB.UI.CreateButton(dummyParent, "TestFlat", 90, 22)
    assert(type(flatBtn.UpdateVisual) == "function", "CreateButton must expose UpdateVisual")
    assert(flatBtn.enabled == true, "Flat button starts enabled")
    flatBtn:Disable()
    assert(flatBtn.enabled == false, "Disable() must set enabled false")
    flatBtn:Enable()
    assert(flatBtn.enabled == true, "Enable() must set enabled true")

    -- Toggle pills and tabs remain enabled when active
    assert(TB.formationPills.shield.enabled == true, "Shield formation pill must remain enabled when active")
    assert(TB.formationPills.shield:IsActive() == true, "Shield formation pill must be active")
    assert(TB.formationPills.near.enabled == true, "Near formation pill must be enabled when inactive")
    assert(TB.formationPills.near:IsActive() == false, "Near formation pill must be inactive")

    TB.ShowTab("actions")
    assert(TB.tabActions.isActive == true and TB.tabActions.enabled == true,
        "tabActions must be active and enabled when selected")
    TB.ShowTab("party")
    assert(TB.tabParty.isActive == true and TB.tabParty.enabled == true,
        "tabParty must be active and enabled when selected")
    assert(TB.tabActions.isActive == false and TB.tabActions.enabled == true,
        "tabActions must remain enabled when deselected")
    TB.ShowTab("actions")

    -- MiniBar flat + and * buttons
    assert(TB.miniBar and TB.miniBar.expand and TB.miniBar.optBtn,
        "Mini bar expand and optBtn must exist")
    assert(TB.miniBar.expand.width == 22 and TB.miniBar.expand.height == 22,
        "expand (+) button must have size 22x22")
    assert(TB.miniBar.optBtn.width == 20 and TB.miniBar.optBtn.height == 22,
        "optBtn (*) button must have size 20x22")
    assert(TB.miniBar.expand:GetText() == "+", "expand button label must be '+'")
    assert(TB.miniBar.optBtn:GetText() == "*", "optBtn button label must be '*'")

    -- Roster empty / offline hint
    assert(TB.rosterEmptyMsg ~= nil, "TB.rosterEmptyMsg must exist")
    assert(string.find(TB.rosterEmptyMsg:GetText(), "No bots online", 1, true) ~= nil,
        "rosterEmptyMsg must contain 'No bots online'")
    assert(string.find(TB.rosterEmptyMsg:GetText(), "Login", 1, true) ~= nil,
        "rosterEmptyMsg must mention Login")

    -- Verify rosterEmptyMsg show/hide logic
    TB.RefreshRows({})
    assert(TB.rosterEmptyMsg:IsVisible() == true,
        "rosterEmptyMsg must be visible when rows list is empty")
    TB.RefreshRows({ { name = "OfflineBot", st = { online = false, serverState = "offline" } } })
    assert(TB.rosterEmptyMsg:IsVisible() == true,
        "rosterEmptyMsg must be visible when all bots in rows are offline")
    TB.RefreshRows({ { name = "OnlineBot", st = { online = true, serverState = "online" } } })
    assert(TB.rosterEmptyMsg:IsVisible() == false,
        "rosterEmptyMsg must be hidden when an online bot is displayed")

    -- Restore roster view
    TB.Refresh()

    print("PASS: Phase 1 roster filter, 5-tab structure, and flat styling checks")
end
