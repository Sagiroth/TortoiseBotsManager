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

-- Horizontal or vertical stacking of the icons. Only these two values are
-- kept in TortoiseBotsDB.miniLayout; anything else reads back horizontal.
local function isVertical()
    return TortoiseBotsDB and TortoiseBotsDB.miniLayout == "vertical"
end

function TB.GetMiniLayout()
    if isVertical() then return "vertical" end
    return "horizontal"
end

function TB.SetMiniLayout(layout)
    TortoiseBotsDB = TortoiseBotsDB or {}
    if layout == "vertical" then TortoiseBotsDB.miniLayout = "vertical"
    else TortoiseBotsDB.miniLayout = "horizontal" end
    if TB.LayoutMiniBar then TB.LayoutMiniBar() end
    if TB.SetStatus then
        if TortoiseBotsDB.miniLayout == "vertical" then TB.SetStatus("Mini bar is vertical.", "ok")
        else TB.SetStatus("Mini bar is horizontal.", "ok") end
    end
end

function TB.ToggleMiniLayout()
    if isVertical() then TB.SetMiniLayout("horizontal")
    else TB.SetMiniLayout("vertical") end
end

-- Favourite slot keys: the player binds TBM_FAV1..TBM_FAV12 in the key
-- bindings menu; the slot runs whatever favourite sits in that position.
-- Missing API (or no key bound) reads back nil; never errors.
local function keyForSlot(slot)
    if GetBindingKey and type(GetBindingKey) == "function" then
        local ok, key = pcall(GetBindingKey, "TBM_FAV" .. slot)
        if ok then return key end
    end
    return nil
end

function TB.GetMiniFavoriteKey(slot)
    return keyForSlot(slot)
end

-- " (SHIFT-1)": appended to a favourite's tooltip when the slot has a key.
local function keyHint(slot)
    local key = keyForSlot(slot)
    if key and key ~= "" then return " (" .. key .. ")" end
    return ""
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
    local binding = def.intent and TB.BindingText and TB.BindingText(def.intent) or nil
    if def.pull then
        local db = TortoiseBotsDB or {}
        local seconds = def.intent == "pullback" and db.pullbackDelay or db.pullDelay
        text = text .. " Timer: " .. TB.ClampPullSeconds(seconds) .. " s (set it in the full window)."
    end
    if def.toggle then
        local state = TB.GetPartyToggleState and TB.GetPartyToggleState(def.toggle)
        local word = state == "on" and "On" or (state == "mixed" and "Mixed" or (state == "off" and "Off" or "?"))
        text = text .. (text ~= "" and " " or "") .. "State: " .. word .. "."
    end
    return title, text
end

local function showTooltip(owner, def, hint, slot)
    local title, text = tooltipFor(def)
    if slot and slot >= 1 and slot <= MAX_FAVORITES then title = title .. keyHint(slot) end
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

local function toggleWord(def)
    if not def or not def.toggle then return nil end
    local state = TB.GetPartyToggleState and TB.GetPartyToggleState(def.toggle)
    if state == "on" then return "On"
    elseif state == "mixed" then return "Mixed"
    elseif state == "off" then return "Off" end
    return "?"
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

-- A bound key runs the favourite in that slot: slot 1 is TBM_FAV1 and so on.
-- Anything unbound, empty or unusable does nothing and reports false.
function TB.RunMiniFavorite(slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > MAX_FAVORITES then return false end
    local intent = TB.GetMiniFavorites()[slot]
    local def = intent and defByIntent(intent)
    if not def then return false end
    if not (TB.RunActionIntent and usable(def)) then return false end
    TB.RunActionIntent(def.intent)
    return true
end

local function paintKey(key, slot)
    if not key then return end
    local text = (slot and slot >= 1 and slot <= MAX_FAVORITES) and keyForSlot(slot) or nil
    if text and text ~= "" then key:SetText(text); key:Show()
    else key:Hide() end
end

-- ── icon buttons ─────────────────────────────────────────────────────────
-- An action slot: the icon inset 1px in a dark frame, a soft white wash on
-- hover. Same look as the item slots of the bot panel.
local function iconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(size); b:SetHeight(size)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local frame = b:CreateTexture(nil, "BACKGROUND")
    frame:SetAllPoints(b)
    frame:SetTexture(0, 0, 0, 0.9)
    b.frame = frame
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    hl:SetTexture(1, 1, 1, 0.16)
    b.lamp = b:CreateTexture(nil, "OVERLAY")
    b.lamp:SetWidth(8); b.lamp:SetHeight(8)
    b.lamp:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.lamp:Hide()
    b.key = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.key:SetPoint("TOPLEFT", b, "TOPLEFT", 1, 1)
    b.key:Hide()
    return b
end

-- ── flyout ───────────────────────────────────────────────────────────────
local openCategory = nil

local function createFlyout()
    flyout = CreateFrame("Frame", "TortoiseBotsManagerMiniFlyout", UIParent)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetWidth(FLY_COLS * FLY_W + 16)
    flyout:EnableMouse(true)
    if TB.ApplySurface then TB.ApplySurface(flyout, "window") else TB.ApplyBackdrop(flyout, 0.95, 0.95) end
    if TB.AddWindowHeader then TB.AddWindowHeader(flyout, 24) end
    flyout.title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    flyout.title:SetPoint("TOPLEFT", flyout, "TOPLEFT", 10, -7)
    TB.SetTextColor(flyout.title, color("title"))
    local close = CreateFrame("Button", nil, flyout, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", 0, 0)
    if TB.StyleCloseButton then TB.StyleCloseButton(close, -4, -4, 16) end
    close:SetScript("OnClick", function() TB.OpenMiniCategory(nil) end)
    flyout.hint = flyout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flyout.hint:SetPoint("BOTTOMLEFT", flyout, "BOTTOMLEFT", 10, 7)
    flyout.hint:SetText("Right-click: add to or drop from the favourites.")
    TB.SetTextColor(flyout.hint, color("faint"))
    flyout.entries = {}
    for i = 1, FLY_COLS * FLY_ROWS do
        local e = CreateFrame("Button", nil, flyout)
        e:SetWidth(FLY_W - 4); e:SetHeight(22)
        local col = math.mod(i - 1, FLY_COLS)
        local row = math.floor((i - 1) / FLY_COLS)
        e:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8 + col * FLY_W, -30 - row * 26)
        e:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local slot = e:CreateTexture(nil, "BACKGROUND")
        slot:SetWidth(22); slot:SetHeight(22)
        slot:SetPoint("LEFT", e, "LEFT", 0, 0)
        slot:SetTexture(0, 0, 0, 0.9)
        e.icon = e:CreateTexture(nil, "ARTWORK")
        e.icon:SetWidth(20); e.icon:SetHeight(20)
        e.icon:SetPoint("LEFT", e, "LEFT", 1, 0)
        e.lamp = e:CreateTexture(nil, "OVERLAY")
        e.lamp:SetWidth(7); e.lamp:SetHeight(7)
        e.lamp:SetPoint("BOTTOMRIGHT", e.icon, "BOTTOMRIGHT", 0, 0)
        e.lamp:Hide()
        e.label = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        e.label:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
        e.label:SetWidth(FLY_W - 32); e.label:SetJustifyH("LEFT")
        local hl = e:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(e)
        hl:SetTexture(1, 1, 1, 0.06)
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
            local word = toggleWord(def)
            e.label:SetText((def.label or def.intent) .. (word and (" (" .. word .. ")") or ""))
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

-- Opens a category's flyout next to the bar (above it when horizontal,
-- beside it when vertical); the same category (or nil) closes it.
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
        if isVertical() then flyout:SetPoint("TOPLEFT", bar, "TOPRIGHT", 4, 0)
        else flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4) end
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
-- Anchors the chrome that never moves with the favourites: the turtle, the
-- category icons and the + button. Only LayoutMiniBar calls it.
local function layoutChrome(vertical)
    bar.handle:ClearAllPoints()
    if vertical then bar.handle:SetPoint("TOP", bar, "TOP", 0, -7)
    else bar.handle:SetPoint("LEFT", bar, "LEFT", 7, 0) end
    for _, b in pairs(bar.categories) do
        b:ClearAllPoints()
        if vertical then b:SetPoint("TOP", bar, "TOP", 0, -(34 + (b.categoryIndex - 1) * STEP))
        else b:SetPoint("LEFT", bar, "LEFT", 34 + (b.categoryIndex - 1) * STEP, 0) end
    end
    bar.expand:ClearAllPoints()
    if vertical then bar.expand:SetPoint("BOTTOM", bar, "BOTTOM", 0, 6)
    else bar.expand:SetPoint("RIGHT", bar, "RIGHT", -6, 0) end
end

-- Places the favourites after the categories and sizes the bar to fit.
-- Horizontal: icons run left to right. Vertical: they run top to bottom.
function TB.LayoutMiniBar()
    if not bar then return end
    local favs = TB.GetMiniFavorites()
    local vertical = isVertical()
    local x0 = 34 + table.getn(CATEGORIES) * STEP + 12
    local y0 = 34 + table.getn(CATEGORIES) * STEP + 12
    if bar.handle and bar.expand then layoutChrome(vertical) end
    bar.divider:ClearAllPoints()
    if vertical then
        bar.divider:SetPoint("TOP", bar, "TOP", 0, -(y0 - 7))
        bar.divider:SetWidth(ICON - 4); bar.divider:SetHeight(1)
    else
        bar.divider:SetPoint("LEFT", bar, "LEFT", x0 - 7, 0)
        bar.divider:SetWidth(1); bar.divider:SetHeight(ICON - 4)
    end
    bar.icons = {}
    local shown = 0
    for i, b in ipairs(bar.favButtons) do
        local def = favs[i] and defByIntent(favs[i])
        b.def = def
        b.slot = def and i or nil
        if def then
            shown = shown + 1
            setIcon(b.icon, def)
            b:ClearAllPoints()
            if vertical then
                b:SetPoint("TOP", bar, "TOP", 0, -(y0 + (shown - 1) * STEP))
            else
                b:SetPoint("LEFT", bar, "LEFT", x0 + (shown - 1) * STEP, 0)
            end
            b:Show()
            bar.icons[def.intent] = b
        else
            b:Hide()
        end
    end
    bar.empty:ClearAllPoints()
    if vertical then
        bar.empty:SetPoint("TOP", bar, "TOP", 0, -y0)
        bar.empty:SetWidth(ICON + 8); bar.empty:SetJustifyH("CENTER")
    else
        bar.empty:SetPoint("LEFT", bar, "LEFT", x0, 0)
        bar.empty:SetWidth(180); bar.empty:SetJustifyH("LEFT")
    end
    if shown == 0 then bar.empty:Show() else bar.empty:Hide() end
    if vertical then
        local favH = shown > 0 and shown * STEP or 30
        bar:SetWidth(ICON + 12)
        bar:SetHeight(y0 + favH + 28)
    else
        local favW = shown > 0 and shown * STEP or 180
        bar:SetWidth(x0 + favW + 6 + 28)
        bar:SetHeight(ICON + 12)
    end
    if TB.RefreshMiniBar then TB.RefreshMiniBar() end
    renderFlyout()
end

local function createBar()
    bar = CreateFrame("Frame", "TortoiseBotsManagerMiniBar", UIParent)
    bar:SetHeight(ICON + 12)
    bar:SetFrameStrata("DIALOG")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    if TB.ApplySurface then TB.ApplySurface(bar, "window") else TB.ApplyBackdrop(bar, 0.9, 0.9) end
    -- The same thin gold rule as the windows, so the bar reads as one of them.
    local rule = bar:CreateTexture(nil, "BORDER")
    rule:SetTexture(COL.accent[1], COL.accent[2], COL.accent[3], 0.85)
    rule:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    rule:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
    rule:SetHeight(1)
    local pos = TortoiseBotsDB and TortoiseBotsDB.miniBar
    if pos and pos.x and pos.y then
        bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    end
    -- The turtle is the drag handle; the bar background drags too.
    -- Locked (Settings): the bar stays where it is.
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if TortoiseBotsDB and TortoiseBotsDB.miniLocked then return end
        bar:StartMoving()
    end)
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
    handle:SetScript("OnDragStart", function()
        if TortoiseBotsDB and TortoiseBotsDB.miniLocked then return end
        bar:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        savePosition()
    end)
    -- The turtle drags on a left-click and flips the bar's direction on a
    -- right-click; the same flip is on /tbm minilayout for key users.
    bar.handle = handle
    handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    handle:SetScript("OnClick", function()
        if arg1 == "RightButton" then TB.ToggleMiniLayout() end
    end)
    handle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("TortoiseBots - mini mode")
        GameTooltip:AddLine("Drag to move. Category icons open their actions; right-click one to keep it on the bar. The + button opens the full window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Right-click: horizontal or vertical bar.", 0.95, 0.72, 0.28)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.categories = {}
    for i, cat in ipairs(CATEGORIES) do
        local b = iconButton(bar, ICON)
        b.categoryIndex = i
        b.icon:SetTexture(categoryIcon(cat))
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Open-category marker: a short bar under the icon, gold while its
        -- flyout is open, faint otherwise (it says "this opens a menu").
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 4, -2)
        b.arrow:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -4, -2)
        b.arrow:SetHeight(2)
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
    bar.divider:SetWidth(1); bar.divider:SetHeight(ICON - 4)
    bar.divider:SetTexture(1, 1, 1, 0.12)

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
            if this.def then showTooltip(this, this.def, "Right-click: drop it from the bar.", this.slot) end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        bar.favButtons[i] = b
    end
    bar.empty = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.empty:SetWidth(180); bar.empty:SetJustifyH("LEFT")
    bar.empty:SetJustifyV("TOP")
    bar.empty:SetText("No favourites yet: right-click an action to pin it here.")
    TB.SetTextColor(bar.empty, color("muted"))

    local expand = TB.StyleButton(CreateFrame("Button", nil, bar, "UIPanelButtonTemplate"), "mode")
    expand:SetWidth(22); expand:SetHeight(22)
    bar.expand = expand
    -- A drawn plus: the font's "+" glyph sits off the button's centre.
    for _, size in ipairs({ { 10, 2 }, { 2, 10 } }) do
        local line = expand:CreateTexture(nil, "OVERLAY")
        line:SetWidth(size[1]); line:SetHeight(size[2])
        line:SetPoint("CENTER", expand, "CENTER", 0, 0)
        line:SetTexture(0.95, 0.72, 0.28, 1)
    end
    expand:SetScript("OnClick", function() TB.SetMode("full") end)
    expand:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Full window")
        GameTooltip:AddLine("Switch back to the full TortoiseBots window.", 0.9, 0.9, 0.9, 1)
        GameTooltip:Show()
    end)
    expand:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
            paintKey(b.key, b.slot)
        elseif b.key then
            b.key:Hide()
        end
    end
    for key, b in pairs(bar.categories) do
        if openCategory and openCategory.key == key then
            b.arrow:SetTexture(COL.accentHi[1], COL.accentHi[2], COL.accentHi[3], 1)
        else
            b.arrow:SetTexture(1, 1, 1, 0.18)
        end
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
