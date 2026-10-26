-- TortoiseBotsManager/MiniBar.lua
-- Minimal mode: a small, draggable bar instead of the full window.
--   [turtle] [category icons] | [favourites ...] [+]
-- A category icon opens a flyout above the bar with that category's actions
-- (the same ones as the Fight and Camp tabs). Right-click an action there to
-- add it to the favourites, or a favourite on the bar to drop it. Every
-- action runs through TB.RunActionIntent, as the full window's buttons do,
-- and follows the same enable rules (enemy-target actions grey out without
-- an enemy target).
--
-- TortoiseBotsDB.mode = "full" | "mini"; the bar stays on screen in "mini".
-- TortoiseBotsDB.miniFavorites = { intent, ... } (empty at first: the bar says
-- how to pin one).

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local ICON = 28
local STEP = 30
local MAX_FAVORITES = 12
local FLY_COLS = 3
local FLY_W = 132
local FLY_ROWS = 4

local CATEGORIES = {
    { key = "engage", label = "Engage", sections = { "engage" } },
    { key = "pull", label = "Pull & Focus", sections = { "pull" } },
    { key = "move", label = "Move", sections = { "move", "stance" } },
    { key = "switch", label = "Party switches", sections = { "switch" } },
    { key = "tactic", label = "Tactics", sections = { "tactic" } },
    { key = "camp", label = "Camp", sections = { "rest", "quests" } },
}

local STANCE_ICON = "Interface\\Icons\\Ability_Warrior_DefensiveStance"

local function color(name) return COL[name] or { 1, 1, 1 } end

local function defsOf(category)
    local out = {}
    for _, section in ipairs(category.sections) do
        for _, def in ipairs((C and C.ACTION_DEFINITIONS) or {}) do
            if def.section == section and def.intent then table.insert(out, def) end
        end
    end
    return out
end

local function defByIntent(intent)
    for _, def in ipairs((C and C.ACTION_DEFINITIONS) or {}) do
        if def.intent == intent then return def end
    end
    return nil
end

-- The old bar's icons, in its order: the favourites a 1.2 addon saved for
-- every player. They are cleared once, so the bar starts empty.
local function oldDefaultFavorites()
    local items = {}
    for _, def in ipairs((C and C.ACTION_DEFINITIONS) or {}) do
        if def.mini then table.insert(items, def) end
    end
    table.sort(items, function(a, b)
        local orderA = type(a.mini) == "number" and a.mini or 999
        local orderB = type(b.mini) == "number" and b.mini or 999
        return orderA < orderB
    end)
    local out = {}
    for _, def in ipairs(items) do table.insert(out, def.intent) end
    return out
end

function TB.GetMiniFavorites()
    TortoiseBotsDB = TortoiseBotsDB or {}
    local favs = TortoiseBotsDB.miniFavorites
    if favs and not TortoiseBotsDB.miniFavoritesOwn then
        local old = oldDefaultFavorites()
        local same = table.getn(favs) == table.getn(old)
        for i = 1, table.getn(old) do
            if favs[i] ~= old[i] then same = false end
        end
        if same then favs = nil end
    end
    TortoiseBotsDB.miniFavoritesOwn = true
    if not favs then favs = {} end
    TortoiseBotsDB.miniFavorites = favs
    return favs
end

local function isFavorite(intent)
    for _, fav in ipairs(TB.GetMiniFavorites()) do
        if fav == intent then return true end
    end
    return false
end

local bar, flyout

local function setIcon(texture, def)
    if def.raidIcon then
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. def.raidIcon)
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetTexture(def.icon or (def.section == "stance" and STANCE_ICON)
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function tooltipFor(def)
    local title = def.label or def.intent
    local text = def.tip or (TB.ActionTooltip and TB.ActionTooltip(def.intent)) or ""
    if def.pull then
        local db = TortoiseBotsDB or {}
        local seconds = def.intent == "pullback" and db.pullbackDelay or db.pullDelay
        text = text .. " Timer: " .. TB.ClampPullSeconds(seconds) .. " s (set it in the full window)."
    end
    return title, text
end

local function showTooltip(owner, def, hint)
    local title, text = tooltipFor(def)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    if text ~= "" then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, 1) end
    if TB.GetActionScopeHint then GameTooltip:AddLine(TB.GetActionScopeHint(), 0.62, 0.60, 0.56) end
    if hint then GameTooltip:AddLine(hint, 0.95, 0.72, 0.28) end
    GameTooltip:Show()
end

local function usable(def)
    if def.needsEnemy and not (TB.HasEnemyTarget and TB.HasEnemyTarget()) then return false end
    if def.cap and not (TB.HasServerCapability and TB.HasServerCapability(def.cap)) then return false end
    if def.toggle and TB.togglePending and TB.togglePending[def.toggle] then return false end
    return true
end

local function paintLamp(lamp, def)
    if not lamp then return end
    if not def.toggle then lamp:Hide(); return end
    local state = TB.GetPartyToggleState and TB.GetPartyToggleState(def.toggle)
    if state == "on" then lamp:SetTexture(0.30, 0.90, 0.45, 1)
    elseif state == "off" then lamp:SetTexture(0.45, 0.45, 0.45, 1)
    else lamp:SetTexture(0.95, 0.72, 0.28, 1) end
    lamp:Show()
end

-- An unusable action greys out but stays clickable: a right-click still
-- pins or drops it; its left-click checks usable() again and does nothing.
local function setUsable(b, on)
    b.usable = on and true or false
    if b.icon.SetVertexColor then
        if on then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(0.35, 0.35, 0.35) end
    end
end

function TB.ToggleMiniFavorite(intent)
    local favs = TB.GetMiniFavorites()
    local def = defByIntent(intent)
    local name = def and def.label or intent
    for i, fav in ipairs(favs) do
        if fav == intent then
            table.remove(favs, i)
            if TB.LayoutMiniBar then TB.LayoutMiniBar() end
            if TB.SetStatus then TB.SetStatus(name .. " dropped from the mini bar.", "ok") end
            return false
        end
    end
    if table.getn(favs) >= MAX_FAVORITES then
        if TB.SetStatus then TB.SetStatus("The mini bar holds " .. MAX_FAVORITES .. " favourites: drop one first.", "warn") end
        return false
    end
    table.insert(favs, intent)
    if TB.LayoutMiniBar then TB.LayoutMiniBar() end
    if TB.SetStatus then TB.SetStatus(name .. " pinned to the mini bar.", "ok") end
    return true
end

-- ── icon buttons ─────────────────────────────────────────────────────────
local function iconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(size); b:SetHeight(size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.18)
    b.lamp = b:CreateTexture(nil, "OVERLAY")
    b.lamp:SetWidth(8); b.lamp:SetHeight(8)
    b.lamp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.lamp:Hide()
    return b
end

-- ── flyout ───────────────────────────────────────────────────────────────
local openCategory = nil

local function createFlyout()
    flyout = CreateFrame("Frame", "TortoiseBotsManagerMiniFlyout", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetWidth(FLY_COLS * FLY_W + 16)
    flyout:EnableMouse(true)
    TB.ApplyBackdrop(flyout, 0.95, 0.95)
    flyout.title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    flyout.title:SetPoint("TOPLEFT", flyout, "TOPLEFT", 10, -8)
    TB.SetTextColor(flyout.title, color("gold"))
    local close = CreateFrame("Button", nil, flyout, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() TB.OpenMiniCategory(nil) end)
    flyout.hint = flyout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flyout.hint:SetPoint("BOTTOMLEFT", flyout, "BOTTOMLEFT", 10, 7)
    flyout.hint:SetText("Right-click: add to or drop from the favourites.")
    TB.SetTextColor(flyout.hint, color("muted"))
    flyout.entries = {}
    for i = 1, FLY_COLS * FLY_ROWS do
        local e = CreateFrame("Button", nil, flyout)
        e:SetWidth(FLY_W - 4); e:SetHeight(22)
        local col = math.mod(i - 1, FLY_COLS)
        local row = math.floor((i - 1) / FLY_COLS)
        e:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8 + col * FLY_W, -30 - row * 26)
        e:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        e.icon = e:CreateTexture(nil, "ARTWORK")
        e.icon:SetWidth(20); e.icon:SetHeight(20)
        e.icon:SetPoint("LEFT", e, "LEFT", 0, 0)
        e.lamp = e:CreateTexture(nil, "OVERLAY")
        e.lamp:SetWidth(7); e.lamp:SetHeight(7)
        e.lamp:SetPoint("BOTTOMRIGHT", e.icon, "BOTTOMRIGHT", 0, 0)
        e.lamp:Hide()
        e.label = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        e.label:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
        e.label:SetWidth(FLY_W - 32); e.label:SetJustifyH("LEFT")
        local hl = e:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(e)
        hl:SetTexture(1, 1, 1, 0.10)
        e:SetScript("OnClick", function()
            local def = this.def
            if not def then return end
            if arg1 == "RightButton" then
                TB.ToggleMiniFavorite(def.intent)
            elseif usable(def) then
                TB.RunActionIntent(def.intent)
            end
            TB.RefreshMiniBar()
        end)
        e:SetScript("OnEnter", function()
            if this.def then
                showTooltip(this, this.def, isFavorite(this.def.intent)
                    and "In your favourites (right-click drops it)." or "Right-click: add to your favourites.")
            end
        end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        e:Hide()
        table.insert(flyout.entries, e)
    end
    flyout:Hide()
    TB.miniFlyout = flyout
end

local function renderFlyout()
    if not flyout or not openCategory then return end
    local defs = defsOf(openCategory)
    flyout.title:SetText(openCategory.label)
    for i, e in ipairs(flyout.entries) do
        local def = defs[i]
        e.def = def
        if def then
            setIcon(e.icon, def)
            e.label:SetText(def.label or def.intent)
            if isFavorite(def.intent) then TB.SetTextColor(e.label, color("gold"))
            else e.label:SetTextColor(0.92, 0.92, 0.92) end
            paintLamp(e.lamp, def)
            setUsable(e, usable(def))
            e:Show()
        else
            e:Hide()
        end
    end
    local rows = math.ceil(table.getn(defs) / FLY_COLS)
    if rows > FLY_ROWS then rows = FLY_ROWS end
    flyout:SetHeight(30 + rows * 26 + 22)
end

-- Opens a category's flyout above the bar; the same category (or nil) closes it.
function TB.OpenMiniCategory(key)
    if not flyout then createFlyout() end
    local wanted = nil
    for _, cat in ipairs(CATEGORIES) do
        if cat.key == key then wanted = cat end
    end
    if not wanted or wanted == openCategory then
        openCategory = nil
        flyout:Hide()
    else
        openCategory = wanted
        flyout:ClearAllPoints()
        flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
        flyout:Show()
        renderFlyout()
    end
    if TB.RefreshMiniBar then TB.RefreshMiniBar() end
end

function TB.GetMiniCategory()
    return openCategory and openCategory.key or nil
end

-- ── bar ──────────────────────────────────────────────────────────────────
local function savePosition()
    local left, top = bar:GetLeft(), bar:GetTop()
    if not left or not top then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.miniBar = { x = left, y = top }
end

local function categoryIcon(category)
    for _, def in ipairs(defsOf(category)) do
        if def.icon then return def.icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Places the favourites after the categories and sizes the bar to fit.
function TB.LayoutMiniBar()
    if not bar then return end
    local favs = TB.GetMiniFavorites()
    local x0 = 34 + table.getn(CATEGORIES) * STEP + 12
    bar.divider:ClearAllPoints()
    bar.divider:SetPoint("LEFT", bar, "LEFT", x0 - 7, 0)
    bar.icons = {}
    local shown = 0
    for i, b in ipairs(bar.favButtons) do
        local def = favs[i] and defByIntent(favs[i])
        b.def = def
        if def then
            shown = shown + 1
            setIcon(b.icon, def)
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", x0 + (shown - 1) * STEP, 0)
            b:Show()
            bar.icons[def.intent] = b
        else
            b:Hide()
        end
    end
    bar.empty:ClearAllPoints()
    bar.empty:SetPoint("LEFT", bar, "LEFT", x0, 0)
    if shown == 0 then bar.empty:Show() else bar.empty:Hide() end
    local favW = shown > 0 and shown * STEP or 180
    bar:SetWidth(x0 + favW + 6 + 28)
    if TB.RefreshMiniBar then TB.RefreshMiniBar() end
    renderFlyout()
end

local function createBar()
    bar = CreateFrame("Frame", "TortoiseBotsManagerMiniBar", UIParent)
    bar:SetHeight(ICON + 10)
    bar:SetFrameStrata("DIALOG")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    TB.ApplyBackdrop(bar, 0.9, 0.9)
    local pos = TortoiseBotsDB and TortoiseBotsDB.miniBar
    if pos and pos.x and pos.y then
        bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end
    -- The turtle is the drag handle; the bar background drags too.
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() bar:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        savePosition()
    end)
    local handle = CreateFrame("Button", nil, bar)
    handle:SetWidth(22); handle:SetHeight(22)
    handle:SetPoint("LEFT", bar, "LEFT", 7, 0)
    handle:RegisterForDrag("LeftButton")
    local turtle = handle:CreateTexture(nil, "ARTWORK")
    turtle:SetAllPoints(handle)
    turtle:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Turtle")
    turtle:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    handle:SetScript("OnDragStart", function() bar:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        savePosition()
    end)
    handle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("TortoiseBots - mini mode")
        GameTooltip:AddLine("Drag to move. Category icons open their actions; right-click one to keep it on the bar. The + button opens the full window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.categories = {}
    for i, cat in ipairs(CATEGORIES) do
        local b = iconButton(bar, ICON)
        b:SetPoint("LEFT", bar, "LEFT", 34 + (i - 1) * STEP, 0)
        b.icon:SetTexture(categoryIcon(cat))
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.arrow:SetPoint("TOP", b, "TOP", 0, 9)
        b.arrow:SetText("^")
        b.category = cat
        b:SetScript("OnClick", function() TB.OpenMiniCategory(this.category.key) end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(this.category.label)
            GameTooltip:AddLine("Click: show its actions.", 0.9, 0.9, 0.9, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.categories[cat.key] = b
    end

    bar.divider = bar:CreateTexture(nil, "ARTWORK")
    bar.divider:SetWidth(1); bar.divider:SetHeight(ICON)
    bar.divider:SetTexture(0.48, 0.36, 0.15, 0.8)

    bar.favButtons = {}
    for i = 1, MAX_FAVORITES do
        local b = iconButton(bar, ICON)
        b:SetScript("OnClick", function()
            local def = this.def
            if not def then return end
            if arg1 == "RightButton" then
                TB.ToggleMiniFavorite(def.intent)
            elseif usable(def) then
                TB.RunActionIntent(def.intent)
            end
        end)
        b:SetScript("OnEnter", function()
            if this.def then showTooltip(this, this.def, "Right-click: drop it from the bar.") end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        bar.favButtons[i] = b
    end
    bar.empty = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.empty:SetWidth(180); bar.empty:SetJustifyH("LEFT")
    bar.empty:SetText("No favourites yet: right-click an action to pin it here.")
    TB.SetTextColor(bar.empty, color("muted"))

    local expand = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"))
    expand:SetWidth(22); expand:SetHeight(22)
    expand:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    -- A drawn plus: the font's "+" glyph sits off the button's centre.
    for _, size in ipairs({ { 10, 2 }, { 2, 10 } }) do
        local line = expand:CreateTexture(nil, "OVERLAY")
        line:SetWidth(size[1]); line:SetHeight(size[2])
        line:SetPoint("CENTER", expand, "CENTER", 0, 0)
        line:SetTexture(1, 0.82, 0.2, 1)
    end
    expand:SetScript("OnClick", function() TB.SetMode("full") end)
    expand:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Full window")
        GameTooltip:AddLine("Switch back to the full TortoiseBots window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    expand:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.expand = expand
    bar:Hide()
    TB.miniBar = bar
    TB.LayoutMiniBar()
end

function TB.RefreshMiniBar()
    if not bar or not bar:IsVisible() then return end
    for _, b in ipairs(bar.favButtons) do
        if b.def then
            paintLamp(b.lamp, b.def)
            setUsable(b, usable(b.def))
        end
    end
    for key, b in pairs(bar.categories) do
        if openCategory and openCategory.key == key then TB.SetTextColor(b.arrow, color("gold"))
        else b.arrow:SetTextColor(0.6, 0.6, 0.6) end
    end
    renderFlyout()
end

-- "mini": hide the window, show the bar. "full": the other way round.
function TB.SetMode(mode)
    if mode ~= "mini" then mode = "full" end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.mode = mode
    if not bar then createBar() end
    if mode == "mini" then
        if TB.CloseBotPanel then TB.CloseBotPanel() end
        if TB.CloseVault then TB.CloseVault() end
        if TB.CloseNpc then TB.CloseNpc() end
        if TB.CloseRunWindow then TB.CloseRunWindow() end
        if TB.CloseServerInfo then TB.CloseServerInfo() end
        if TB.frame then TB.frame:Hide() end
        bar:Show()
        TB.RefreshMiniBar()
    else
        if openCategory then TB.OpenMiniCategory(nil) end
        bar:Hide()
        if TB.frame and not TB.frame:IsVisible() then
            TB.frame:Show()
            if TB.Refresh then TB.Refresh() end
            if TB.PollList then TB.PollList(true) end
        end
    end
end

function TB.GetMode()
    return (TortoiseBotsDB and TortoiseBotsDB.mode == "mini") and "mini" or "full"
end

-- Minimap button and /tbm: show or hide whichever view the mode uses.
function TB.ToggleMiniBar()
    if not bar then createBar() end
    if bar:IsVisible() then
        if openCategory then TB.OpenMiniCategory(nil) end
        bar:Hide()
    else
        bar:Show(); TB.RefreshMiniBar()
    end
end

-- Target changes decide which icons are usable.
local watcher = CreateFrame("Frame", "TortoiseBotsManagerMiniBarWatcher")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        -- Mini mode survives a reload: bring the bar back. No TB.uiReady
        -- guard: this event fires before InitUI runs on login.
        if TB.GetMode() == "mini" then
            if not bar then createBar() end
            bar:Show()
        end
    end
    TB.RefreshMiniBar()
end)
