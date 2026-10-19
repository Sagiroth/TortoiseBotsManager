-- tests/phase0_tests.lua
-- Unit and regression tests for Phase 0 refactoring:
--   1. Role policy (TB.Roles)
--   2. Action definitions table (TB.C.ACTION_DEFINITIONS, TB.GetActionDefinition)
--   3. Component kit & layout grid (TB.UI)
--   4. Per-card builders (TB.UI.Build*Card)

return function()
    local TB = TortoiseBots
    local C = TB.C or {}

    -- ──────────────────────────────────────────────────────────────────────────
    -- 1. TB.Roles
    -- ──────────────────────────────────────────────────────────────────────────
    assert(TB.Roles, "TB.Roles must exist")
    assert(type(TB.Roles.GetClassRoles) == "function", "TB.Roles.GetClassRoles must be a function")
    assert(type(TB.Roles.FindRole) == "function", "TB.Roles.FindRole must be a function")
    assert(type(TB.Roles.GetRoleLabel) == "function", "TB.Roles.GetRoleLabel must be a function")

    -- Verify class roles
    local warRoles = TB.Roles.GetClassRoles("WARRIOR")
    assert(table.getn(warRoles) == 2 and warRoles[1].id == "tank" and warRoles[2].id == "dps",
        "Warrior must offer tank and dps")

    local priestRoles = TB.Roles.GetClassRoles("PRIEST")
    assert(table.getn(priestRoles) == 3 and priestRoles[1].id == "heal" and priestRoles[2].id == "hybrid" and priestRoles[3].id == "dps",
        "Priest must offer heal, hybrid and dps")

    local palRoles = TB.Roles.GetClassRoles("PALADIN")
    assert(table.getn(palRoles) == 3 and palRoles[1].id == "tank" and palRoles[2].id == "heal" and palRoles[3].id == "dps",
        "Paladin must offer tank, healer and dps")

    local mageRoles = TB.Roles.GetClassRoles("MAGE")
    assert(table.getn(mageRoles) == 3 and mageRoles[1].id == "frost",
        "Mage must offer frost, fire and arcane")

    -- Numeric class ID support
    local warById = TB.Roles.GetClassRoles(1)
    assert(table.getn(warById) == 2 and warById[1].id == "tank",
        "Class ID 1 (Warrior) must return warrior roles")

    -- FindRole and labels
    local tankRole = TB.Roles.FindRole("tank")
    assert(tankRole and tankRole.id == "tank" and tankRole.label == "Tank",
        "FindRole must find tank by id")
    local dpsRole = TB.Roles.FindRole("DPS")
    assert(dpsRole and dpsRole.id == "dps" and dpsRole.label == "DPS",
        "FindRole must find dps case-insensitively by label")
    assert(TB.Roles.FindRole("nonexistent") == nil,
        "FindRole on invalid role must return nil")
    assert(TB.Roles.GetRoleLabel("heal") == "Healer",
        "GetRoleLabel('heal') must return 'Healer'")
    assert(TB.Roles.GetRoleLabel("custom") == "custom",
        "GetRoleLabel fallback must return token string")

    -- Player role state
    TB.Roles.SetPlayerRole("heal", 5)
    assert(TB.Roles.GetPlayerRole(5) == "heal", "SetPlayerRole must update player role")
    TB.Roles.SetPlayerRole("dps", 1)
    assert(TB.Roles.GetPlayerRole(1) == "dps", "SetPlayerRole must update to dps")

    -- Bot role state and cycling
    TB.Roles.SetBotRole("TestBot", "tank", 1)
    assert(TB.Roles.GetBotRole("TestBot", 1) == "tank", "SetBotRole must store bot role")
    local cycled1 = TB.Roles.CycleBotRole("TestBot", "WARRIOR")
    assert(cycled1 and cycled1.id == "dps" and TB.Roles.GetBotRole("TestBot", 1) == "dps",
        "Warrior bot role must cycle from tank to dps")
    local cycled2 = TB.Roles.CycleBotRole("TestBot", "WARRIOR")
    assert(cycled2 and cycled2.id == "tank" and TB.Roles.GetBotRole("TestBot", 1) == "tank",
        "Warrior bot role must cycle from dps back to tank")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 2. TB.C.ACTION_DEFINITIONS
    -- ──────────────────────────────────────────────────────────────────────────
    assert(TB.C.ACTION_DEFINITIONS and table.getn(TB.C.ACTION_DEFINITIONS) >= 16,
        "ACTION_DEFINITIONS must contain all core actions")
    assert(TB.C.ACTIONS_BY_ID and TB.C.ACTIONS_BY_INTENT,
        "Lookup index tables must be populated")

    local attackDef = TB.GetActionDefinition("attack")
    assert(attackDef and attackDef.id == "attack" and attackDef.section == "engage",
        "TB.GetActionDefinition('attack') must return engage definition")

    local pullDef = TB.GetActionDefinition("pull")
    assert(pullDef and pullDef.id == "pull" and pullDef.pull == true and pullDef.section == "pull",
        "pull action definition must have pull = true and section = pull")

    local skullDef = TB.GetActionDefinition("focus skull")
    assert(skullDef and skullDef.id == "focusSkull" and skullDef.raidIcon == 8,
        "focus skull definition must have raidIcon = 8")

    local aoeDef = TB.GetActionDefinition("aoe")
    assert(aoeDef and aoeDef.id == "aoe" and aoeDef.toggle == "aoe" and aoeDef.section == "switch",
        "aoe definition must specify toggle = 'aoe'")

    local restDef = TB.GetActionDefinition("rest")
    assert(restDef and restDef.id == "rest" and restDef.section == "rest",
        "rest definition must specify section = 'rest'")

    local releaseDef = TB.GetActionDefinition("release")
    assert(releaseDef and releaseDef.id == "release" and releaseDef.death == true,
        "release definition must specify death = true")

    -- Verify that every definition in ACTION_DEFINITIONS has required fields
    for _, def in ipairs(TB.C.ACTION_DEFINITIONS) do
        assert(def.id and def.intent and def.label and def.section and def.tip,
            "Action definition " .. tostring(def.id) .. " must have id, intent, label, section, and tip")
        assert(TB.C.ACTIONS_BY_ID[def.id] == def,
            "ACTIONS_BY_ID must index " .. def.id)
        assert(TB.C.ACTIONS_BY_INTENT[def.intent] == def,
            "ACTIONS_BY_INTENT must index " .. def.intent)
    end

    -- Verify table cleanups and derivations
    assert(TB.C.ACTIONS == nil, "C.ACTIONS must be deleted")
    assert(TB.Roles.CLASS_ROLES and TB.C.CLASS_ROLES == TB.Roles.CLASS_ROLES,
        "TB.Roles must be the single source of truth for CLASS_ROLES")
    assert(TB.C.PARTY_TOGGLES and table.getn(TB.C.PARTY_TOGGLES) == 3,
        "PARTY_TOGGLES must be derived from ACTION_DEFINITIONS")
    assert(TB.C.ACTION_ICONS and TB.C.ACTION_ICONS.attack,
        "ACTION_ICONS must be derived from ACTION_DEFINITIONS")
    assert(TB.C.ACTION_LABELS and TB.C.ACTION_LABELS.attack == "Attack",
        "ACTION_LABELS must be derived from ACTION_DEFINITIONS")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 3. TB.UI.Grid
    -- ──────────────────────────────────────────────────────────────────────────
    assert(TB.UI and TB.UI.Grid, "TB.UI.Grid must exist")
    assert(TB.UI.Grid.CONTENT_W and TB.UI.Grid.CONTENT_W > 0, "CONTENT_W must be positive")
    assert(TB.UI.Grid.BTN_H == 26, "Default button height must be 26")
    assert(TB.UI.Grid.BTN_H_SM == 22, "Small button height must be 22")
    assert(TB.UI.Grid.ROW_H == 28, "Row height must be 28")
    assert(TB.UI.Grid.CARD_ENGAGE_H == 58, "Card engage height must be 58")
    assert(TB.UI.Grid.CARD_PULL_H == 76, "Card pull height must be 76")
    assert(TB.UI.Grid.CARD_MOVE_H == 58, "Card move height must be 58")
    assert(TB.UI.Grid.CARD_SWITCH_H == 58, "Card switch height must be 58")
    assert(TB.UI.Grid.CARD_REST_H == 88, "Card rest height must be 88")
    assert(TB.UI.Grid.CARD_FORM_H == 76, "Card form height must be 76")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 4. TB.UI component factories
    -- ──────────────────────────────────────────────────────────────────────────
    local parent = CreateFrame("Frame", "TestComponentParent", UIParent)

    -- CreateCard
    local testCard = TB.UI.CreateCard(parent, "TEST CARD", 200, 60, { x = 10, y = -10, line = true })
    assert(testCard and testCard.title and testCard.title:GetText() == "TEST CARD",
        "CreateCard must set title text")
    assert(testCard.line ~= nil, "CreateCard with line = true must create line texture")
    assert(testCard.width == 200 and testCard.height == 60,
        "CreateCard must apply dimensions")

    -- CreateButton
    local clicked = false
    local testBtn = TB.UI.CreateButton(testCard, "ClickMe", 80, 24, {
        x = 5, y = -5,
        onClick = function() clicked = true end,
        tip = "Button tip",
        tipTitle = "Button Title",
        lamp = true,
        raidIcon = 8,
    })
    assert(testBtn:GetText() == "ClickMe", "CreateButton must set label")
    assert(testBtn.width == 80 and testBtn.height == 24, "CreateButton dimensions")
    assert(testBtn.lamp ~= nil, "CreateButton lamp option must create lamp texture")
    assert(testBtn.raidIcon ~= nil, "CreateButton raidIcon option must create raid icon")
    testBtn.scripts.OnClick(testBtn)
    assert(clicked == true, "CreateButton onClick handler must fire")

    -- CreateTogglePill
    local pillClicked = false
    local testPill = TB.UI.CreateTogglePill(testCard, "Pill", 60, 20, {
        onClick = function() pillClicked = true end,
    })
    assert(testPill:GetText() == "Pill", "CreateTogglePill label")
    assert(testPill.enabled == true, "Pill starts enabled")
    testPill:SetActive(true)
    assert(testPill.isActive == true and testPill.enabled == true,
        "SetActive(true) must mark active and keep button enabled")
    testPill:SetActive(false)
    assert(testPill.isActive == false and testPill.enabled == true,
        "SetActive(false) must mark inactive and keep button enabled")

    -- CreateStepper
    local stepVal = 10
    local testStepper = TB.UI.CreateStepper(testCard, {
        get = function() return stepVal end,
        set = function(v) stepVal = v end,
        format = function(v) return v .. " s" end,
        step = 1,
        shiftStep = 5,
    })
    assert(testStepper.label and testStepper.label:GetText() == "10 s",
        "CreateStepper initial label must format current value")
    testStepper.bump(1)
    assert(stepVal == 11 and testStepper.label:GetText() == "11 s",
        "CreateStepper bump must update value and label")
    testStepper.bump(-5)
    assert(stepVal == 6 and testStepper.label:GetText() == "6 s",
        "CreateStepper bump negative must decrement value and repaint")

    -- CreateRow
    local testRow = TB.UI.CreateRow(testCard, 180, 22, { x = 0, y = 0 })
    assert(testRow.width == 180 and testRow.height == 22,
        "CreateRow must set dimensions")

    -- CreateIconButton
    local iconClicked = false
    local testIconBtn = TB.UI.CreateIconButton(testCard, 24, {
        icon = "Interface\\Buttons\\Button-Backpack-Up",
        onClick = function() iconClicked = true end,
        tip = "Icon tip",
    })
    assert(testIconBtn.width == 24 and testIconBtn.height == 24,
        "CreateIconButton dimensions")
    assert(testIconBtn.icon ~= nil, "CreateIconButton must create icon texture")
    assert(testIconBtn.highlight ~= nil, "CreateIconButton must create highlight texture")
    testIconBtn.scripts.OnClick(testIconBtn)
    assert(iconClicked == true, "CreateIconButton onClick must fire")

    -- ──────────────────────────────────────────────────────────────────────────
    -- 5. Per-card builders
    -- ──────────────────────────────────────────────────────────────────────────
    assert(type(TB.UI.BuildScopeCard) == "function", "BuildScopeCard must be exported")
    assert(type(TB.UI.BuildCcMenu) == "function", "BuildCcMenu must be exported")
    assert(type(TB.UI.BuildEngageCard) == "function", "BuildEngageCard must be exported")
    assert(type(TB.UI.BuildPullCard) == "function", "BuildPullCard must be exported")
    assert(type(TB.UI.BuildMoveCard) == "function", "BuildMoveCard must be exported")
    assert(type(TB.UI.BuildSwitchesCard) == "function", "BuildSwitchesCard must be exported")
    assert(type(TB.UI.BuildRestCard) == "function", "BuildRestCard must be exported")
    assert(type(TB.UI.BuildFormationCard) == "function", "BuildFormationCard must be exported")

    print("PASS: Phase 0 component kit and definition table checks")
end
