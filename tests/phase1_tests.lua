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
end
