-- TortoiseBotsManager/BotPanel.lua
-- Per-bot state and the bot panel (gear, bags, behaviour).
--
-- Everything shown here comes from the server:
--   TBM:BOTSTATE  → movement mode and behaviour toggles of each live bot
--                   (roster trailer; also the reply to ".bot behavior")
--   TBM:INV_*     → one bot's equipped gear, bag items and money
-- Each click sends exactly one request (`inv`, `item`, `behavior`) and the
-- server answers with fresh state, so the panel never guesses what happened.
-- Items are addressed by the server's own bag/slot pair.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local PW = 330
local PH = 470 -- taller than the main window: paper doll + footer
local SLOT = 34
local STEP = 38
local BAG_COLS, BAG_ROWS = 8, 7
local EQUIPPED_BAG = 255 -- INVENTORY_SLOT_BAG_0: equipment and backpack

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── bot state model ─────────────────────────────────────────────────────────
local botStates = {}

function TB.RefreshBotViews()
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
    if TB.partyFrame and TB.partyFrame:IsVisible() and TB.RefreshPartyView then TB.RefreshPartyView() end
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

-- A full snapshot replaces the set: bots that left the party disappear.
function TB.SetBotStates(rows)
    for key in pairs(botStates) do botStates[key] = nil end
    for _, row in ipairs(rows or {}) do
        if row.name then botStates[norm(row.name)] = row.state or {} end
    end
    TB.RefreshBotViews()
end

function TB.SetBotState(name, state)
    name = norm(name)
    if not name then return end
    botStates[name] = state or {}
    TB.RefreshBotViews()
end

function TB.GetBotState(name)
    name = norm(name)
    return name and botStates[name] or nil
end

function TB.GetBotStates()
    return botStates
end

function TB.MovementLabel(name)
    local st = TB.GetBotState(name)
    local move = st and st.move
    return move and C.MOVEMENT_LABELS and C.MOVEMENT_LABELS[move] or nil
end

-- ── party toggles (Actions tab: AoE, Auto CC, Loot) ─────────────────────────
TB.togglePending = TB.togglePending or {}
-- Used only when the server sends no BOTSTATE (older module): the last ACK.
TB.toggleFallback = TB.toggleFallback or {}

local toggleByIntent = {}
for _, toggle in ipairs(C.PARTY_TOGGLES or {}) do toggleByIntent[toggle.intent] = toggle.key end

function TB.PartyToggleKey(intent)
    return intent and toggleByIntent[intent] or nil
end

-- "on" / "off" when every live bot agrees, "mixed" otherwise, nil = unknown.
function TB.GetPartyToggleState(key)
    local on, off = false, false
    for _, st in pairs(botStates) do
        if st[key] == "on" then on = true elseif st[key] == "off" then off = true end
    end
    if not on and not off then return TB.toggleFallback[key] end
    if on and off then return "mixed" end
    return on and "on" or "off"
end

function TB.SendPartyToggle(key)
    local toggle
    for _, t in ipairs(C.PARTY_TOGGLES or {}) do
        if t.key == key then toggle = t end
    end
    if not toggle or TB.togglePending[key] then return false end
    local nextState = TB.GetPartyToggleState(key) == "on" and "off" or "on"
    TB.togglePending[key] = true
    if key == "aoe" then TB.aoePending = true end
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
    return TB.SendActionIntent(toggle.intent .. " " .. nextState)
end

-- value nil = the request failed: only the pending flag is cleared.
function TB.OnPartyToggleResult(key, scope, value)
    TB.togglePending[key] = nil
    if value == "on" or value == "off" then
        local _, _, botName = string.find(scope or "", "^bot:(.+)$")
        local st = botName and botStates[norm(botName)]
        if st then
            st[key] = value
        else
            for _, other in pairs(botStates) do other[key] = value end
            TB.toggleFallback[key] = value
        end
    elseif value == "mixed" then
        TB.toggleFallback[key] = "mixed"
    end
    if key == "aoe" then
        TB.aoePending = false
        TB.aoeEnabled = TB.GetPartyToggleState("aoe") == "on"
    end
    if TB.RefreshToggleButtons then TB.RefreshToggleButtons() end
end

-- ── inventory model ─────────────────────────────────────────────────────────
local inventories = {}

function TB.SetInventory(name, inventory)
    name = norm(name)
    if not name or type(inventory) ~= "table" then return end
    inventory.at = now()
    inventories[name] = inventory
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
end

function TB.GetInventory(name)
    name = norm(name)
    return name and inventories[name] or nil
end

function TB.RequestInventory(name)
    name = norm(name)
    if not name then return false end
    return TB.SendBotCommand("inv " .. name)
end

-- ── item helpers ────────────────────────────────────────────────────────────
-- Vanilla GetItemInfo: name, link ("item:id:0:0:0"), quality, level, type,
-- subtype, stack, equipLoc, texture. Nil until the client cached the item.
local function itemInfo(id)
    if not id or not GetItemInfo then return nil end
    local name, link, quality, _, _, _, _, _, texture = GetItemInfo(id)
    return name, link, quality, texture
end

local function qualityColor(quality)
    if quality and GetItemQualityColor then
        local r, g, b, hex = GetItemQualityColor(quality)
        if r then return r, g, b, hex end
    end
    return 0.35, 0.35, 0.35, "|cffffffff"
end

local function itemLabel(id)
    local name, _, quality = itemInfo(id)
    if not name then return "item #" .. tostring(id) end
    local _, _, _, hex = qualityColor(quality)
    return (hex or "") .. "[" .. name .. "]|r"
end

local scanTip
local uncachedAt = nil
-- Ask the server for an uncached item: a hidden tooltip query caches it,
-- and the panel re-renders a moment later.
local function requestItem(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TortoiseBotsManagerScanTip", UIParent, "GameTooltipTemplate")
    end
    if scanTip.SetOwner and scanTip.SetHyperlink then
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:SetHyperlink("item:" .. id .. ":0:0:0")
    end
    uncachedAt = uncachedAt or now()
end

local function chatLink(id)
    local name, link, quality = itemInfo(id)
    if not name or not link then return nil end
    local _, _, _, hex = qualityColor(quality)
    return (hex or "|cffffffff") .. "|H" .. link .. "|h[" .. name .. "]|h|r"
end

local function formatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local text = ""
    if g > 0 then text = text .. "|cffffd700" .. g .. "g|r " end
    if g > 0 or s > 0 then text = text .. "|cffc7c7cf" .. s .. "s|r " end
    return text .. "|cffeda55f" .. c .. "c|r"
end
TB.FormatMoney = formatMoney

-- The unit id of a grouped bot, for its class and 3D model.
local function botUnit(name)
    name = norm(name)
    if not name or not UnitName then return nil end
    local raid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            if norm(UnitName(unit)) == name then return unit end
        end
    end
    local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        if norm(UnitName(unit)) == name then return unit end
    end
    return nil
end

local function botClassId(name)
    local unit = botUnit(name)
    if unit and UnitClass then
        local className, classFile = UnitClass(unit)
        local ids = C.CLASS_NAME_TO_ID or {}
        return ids[classFile or ""] or ids[className or ""]
    end
    local entry = TB.GetRosterEntry and TB.GetRosterEntry(name)
    return entry and entry.classId or nil
end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── panel state ─────────────────────────────────────────────────────────────
local panel
local currentBot
local currentView = "gear"
local bagPage = 1
local pendingGive = nil       -- { bot, bag, slot } awaiting the trade window
local behaviorPending = {}    -- [bot .. "|" .. key] = true

function TB.GetBotPanelBot()
    return panel and panel:IsVisible() and currentBot or nil
end

-- ── item orders ─────────────────────────────────────────────────────────────
function TB.SendItemOrder(op, bag, slot)
    if not currentBot then return false end
    if op == "give" then pendingGive = { bot = currentBot, bag = bag, slot = slot } end
    local cmd = "item " .. currentBot .. " " .. op
    if bag and slot then cmd = cmd .. " " .. bag .. " " .. slot end
    if TB.SetStatus then TB.SetStatus((C.ACTION_LABELS["item " .. op] or op) .. " → " .. currentBot .. "…", "pending") end
    return TB.SendBotCommand(cmd)
end

function TB.SendBehavior(name, key)
    name = norm(name)
    if not name or not key then return false end
    local pendingKey = name .. "|" .. key
    if behaviorPending[pendingKey] then return false end
    local st = TB.GetBotState(name) or {}
    local nextState = st[key] == "on" and "off" or "on"
    behaviorPending[pendingKey] = true
    if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    return TB.SendBotCommand("behavior " .. name .. " " .. key .. " " .. nextState)
end

-- ACK routing from Comms.ParseActionMessage. Returns true when handled.
function TB.OnBotPanelAck(packet)
    local intent = packet.intent or ""
    local botName = string.gsub(packet.scope or "", "^bot:", "")
    local _, _, op = string.find(intent, "^item%s+(%a+)$")
    if op then
        local _, _, id, detail = string.find(packet.executor or "", "^(%d+)%s*(%a*)$")
        id = tonumber(id)
        local text
        if op == "trade" then
            text = "Trade open with " .. botName .. ". Put your items in and accept - the bot accepts on its own."
        elseif op == "give" and detail == "pending" then
            text = "Opening trade with " .. botName .. "; " .. itemLabel(id) .. " goes in when the window opens."
        elseif op == "give" then
            pendingGive = nil
            text = itemLabel(id) .. " is in the trade window. Accept the trade to take it."
        elseif op == "equip" then
            text = botName .. " equipped " .. itemLabel(id) .. "."
        elseif op == "unequip" then
            text = botName .. " put " .. itemLabel(id) .. " in its bags."
        else
            text = intent .. " accepted"
        end
        if TB.SetStatus then TB.SetStatus(text, "ok") end
        return true
    end
    local _, _, key = string.find(intent, "^behavior%s+(%S+)$")
    if key then
        behaviorPending[norm(botName) .. "|" .. key] = nil
        local label = key
        for _, b in ipairs(C.BEHAVIORS or {}) do if b.key == key then label = b.label end end
        if TB.SetStatus then TB.SetStatus(botName .. ": " .. label .. " " .. (packet.executor == "on" and "on" or "off"), "ok") end
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
        return true
    end
    return false
end

function TB.OnBotPanelError(packet)
    local intent = packet.intent or ""
    if intent == "item give" then pendingGive = nil end
    local _, _, key = string.find(intent, "^behavior%s+(%S+)$")
    if key then
        for pendingKey in pairs(behaviorPending) do
            if string.find(pendingKey, "|" .. key .. "$") then behaviorPending[pendingKey] = nil end
        end
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
    end
end

-- ── panel construction ──────────────────────────────────────────────────────
local itemMenu

local function hideMenu()
    if itemMenu then itemMenu:Hide(); itemMenu.owner = nil end
end

local function createItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(SLOT); b:SetHeight(SLOT)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints(b)
    b.border:SetTexture(0.25, 0.25, 0.25, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count:SetJustifyH("RIGHT")
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.badge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
    b.badge:SetText("|cff40ff40+|r")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function()
        local entry = this.entry
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if entry and entry.id then
            if GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. entry.id .. ":0:0:0")
            else
                GameTooltip:SetText(itemLabel(entry.id))
            end
            if entry.upgrade then GameTooltip:AddLine("Upgrade for " .. (currentBot or "this bot"), 0.25, 1, 0.25) end
            if entry.equipped then
                GameTooltip:AddLine("Click: unequip", 0.62, 0.60, 0.56)
            else
                local hint = entry.equippable and "Click: equip or give to you" or "Click: give to you"
                if entry.noTrade and entry.equippable then hint = "Click: equip (cannot be traded)" end
                if entry.noTrade and not entry.equippable then hint = "Soulbound - stays with the bot" end
                GameTooltip:AddLine(hint, 0.62, 0.60, 0.56)
            end
            GameTooltip:AddLine("Shift-click: link in chat", 0.62, 0.60, 0.56)
        else
            GameTooltip:SetText(this.slotLabel or "Empty")
            GameTooltip:AddLine("Nothing equipped", 0.62, 0.60, 0.56)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        local entry = this.entry
        if not entry or not entry.id then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            local link = chatLink(entry.id)
            if link and ChatFrameEditBox and ChatFrameEditBox.IsVisible and ChatFrameEditBox:IsVisible() then
                ChatFrameEditBox:Insert(link)
            end
            return
        end
        if itemMenu.owner == this and itemMenu:IsVisible() then hideMenu() return end
        itemMenu:Open(this, entry)
    end)
    return b
end

local function paintItemButton(b, entry, emptyTexture)
    b.entry = entry
    if entry and entry.id then
        local _, _, quality, texture = itemInfo(entry.id)
        if not texture then requestItem(entry.id) end
        b.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local r, g, bl = qualityColor(quality)
        if entry.maxDurability and entry.maxDurability > 0
            and (entry.durability or 0) / entry.maxDurability < 0.25 then
            r, g, bl = 1, 0.15, 0.1 -- nearly broken: red frame
        end
        b.border:SetTexture(r, g, bl, 0.95)
        b.count:SetText((entry.count and entry.count > 1) and tostring(entry.count) or "")
        if entry.upgrade then b.badge:Show() else b.badge:Hide() end
        if b.icon.SetVertexColor then
            if entry.noTrade and not entry.equippable and not entry.equipped then
                b.icon:SetVertexColor(0.7, 0.7, 0.7)
            else
                b.icon:SetVertexColor(1, 1, 1)
            end
        end
    else
        b.icon:SetTexture(emptyTexture or nil)
        b.icon:SetTexCoord(0, 1, 0, 1)
        if b.icon.SetVertexColor then b.icon:SetVertexColor(1, 1, 1) end
        b.border:SetTexture(0.12, 0.12, 0.12, 0.9)
        b.count:SetText("")
        b.badge:Hide()
    end
    b:Show()
end

local function createMenu(parent)
    local menu = CreateFrame("Frame", "TortoiseBotsManagerItemMenu", parent)
    menu:SetWidth(118); menu:SetHeight(58)
    menu:SetFrameStrata("TOOLTIP")
    menu:EnableMouse(true)
    TB.ApplyBackdrop(menu, 0.98, 1.0)
    local function button(label, y, tip)
        local btn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        btn:SetWidth(106); btn:SetHeight(22)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, y)
        btn:SetText(label)
        setTooltip(btn, label, { tip })
        return btn
    end
    menu.first = button("Equip", -6, "The bot equips this item.")
    menu.second = button("Give to me", -30, "Opens a trade with the bot and puts this item in. Accept the trade to take it.")
    function menu:Open(owner, entry)
        self.owner = owner
        self.entry = entry
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", -8, 8)
        if entry.equipped then
            self.first:SetText("Unequip")
            self.first:Enable()
            self.first.op = "unequip"
            self.second:Hide()
            self:SetHeight(34)
        else
            self.first:SetText("Equip")
            self.first.op = "equip"
            if entry.equippable then self.first:Enable() else self.first:Disable() end
            self.second:Show()
            if entry.noTrade then self.second:Disable() else self.second:Enable() end
            self:SetHeight(58)
        end
        self:Show()
    end
    menu.first:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.SendItemOrder(menu.first.op, entry.bag, entry.slot) end
    end)
    menu.second:SetScript("OnClick", function()
        local entry = menu.entry
        hideMenu()
        if entry then TB.SendItemOrder("give", entry.bag, entry.slot) end
    end)
    menu:Hide()
    return menu
end

local function makeTab(parent, label, x, width, view)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -46)
    b:SetText(label)
    b:SetScript("OnClick", function()
        currentView = view
        hideMenu()
        TB.RefreshBotPanel()
    end)
    return b
end

local function createPanel()
    panel = CreateFrame("Frame", "TortoiseBotsManagerBotPanel", TB.frame or UIParent)
    panel:SetWidth(PW); panel:SetHeight(PH)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    TB.ApplyBackdrop(panel, 0.98, 1.0)

    local name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    name:SetWidth(170); name:SetJustifyH("LEFT")
    panel.nameText = name

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -28)
    sub:SetWidth(200); sub:SetJustifyH("LEFT")
    TB.SetTextColor(sub, color("muted"))
    panel.subText = sub

    local money = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    money:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -14)
    money:SetWidth(110); money:SetJustifyH("RIGHT")
    panel.moneyText = money

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseBotPanel() end)

    panel.tabGear = makeTab(panel, "Gear", 10, 96, "gear")
    panel.tabBags = makeTab(panel, "Bags", 110, 104, "bags")
    panel.tabBehavior = makeTab(panel, "Behaviour", 218, 102, "behavior")
    setTooltip(panel.tabGear, "Gear", { "What the bot wears. Click a slot to unequip." })
    setTooltip(panel.tabBags, "Bags", { "Everything in the bot's bags. Click an item to equip it or take it." })
    setTooltip(panel.tabBehavior, "Behaviour", { "Per-bot combat habits, stored on the server." })

    -- Gear view: paper doll around the bot's 3D model.
    local gear = CreateFrame("Frame", nil, panel)
    gear:SetAllPoints(panel)
    panel.gear = gear
    local model = CreateFrame("PlayerModel", nil, gear)
    model:SetPoint("TOPLEFT", panel, "TOPLEFT", 52, -74)
    model:SetWidth(PW - 104); model:SetHeight(262)
    panel.model = model
    -- Below the model (a model frame draws over its parent's text).
    local durability = gear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    durability:SetPoint("TOP", panel, "TOP", 0, -342)
    durability:SetWidth(PW - 110)
    panel.durabilityText = durability
    panel.gearButtons = {}
    local function placeColumn(list, x)
        for i, def in ipairs(list) do
            local b = createItemButton(gear)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -74 - (i - 1) * STEP)
            b.slotId = def.slot
            b.slotLabel = def.label
            b.emptyTexture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. def.empty
            panel.gearButtons[def.slot] = b
        end
    end
    placeColumn(C.GEAR_LEFT or {}, 10)
    placeColumn(C.GEAR_RIGHT or {}, PW - 10 - SLOT)
    for i, def in ipairs(C.GEAR_BOTTOM or {}) do
        local b = createItemButton(gear)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", math.floor(PW / 2 - STEP * 1.5 + 2) + (i - 1) * STEP, -380)
        b.slotId = def.slot
        b.slotLabel = def.label
        b.emptyTexture = "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. def.empty
        panel.gearButtons[def.slot] = b
    end

    -- Bags view: occupied slots only, paged.
    local bags = CreateFrame("Frame", nil, panel)
    bags:SetAllPoints(panel)
    panel.bags = bags
    local bagSummary = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagSummary:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -76)
    bagSummary:SetWidth(PW - 24); bagSummary:SetJustifyH("LEFT")
    TB.SetTextColor(bagSummary, color("muted"))
    panel.bagSummary = bagSummary
    panel.bagButtons = {}
    local x0 = math.floor((PW - (BAG_COLS * STEP - 4)) / 2)
    for r = 1, BAG_ROWS do
        for c = 1, BAG_COLS do
            local b = createItemButton(bags)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", x0 + (c - 1) * STEP, -94 - (r - 1) * STEP)
            table.insert(panel.bagButtons, b)
        end
    end
    local prev = CreateFrame("Button", nil, bags, "UIPanelButtonTemplate")
    prev:SetWidth(26); prev:SetHeight(20)
    prev:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -366)
    prev:SetText("<")
    prev:SetScript("OnClick", function() bagPage = bagPage - 1; hideMenu(); TB.RefreshBotPanel() end)
    local nextBtn = CreateFrame("Button", nil, bags, "UIPanelButtonTemplate")
    nextBtn:SetWidth(26); nextBtn:SetHeight(20)
    nextBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 100, -366)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function() bagPage = bagPage + 1; hideMenu(); TB.RefreshBotPanel() end)
    local pageText = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("TOPLEFT", panel, "TOPLEFT", 40, -370)
    pageText:SetWidth(58); pageText:SetJustifyH("CENTER")
    panel.prevPage, panel.nextPage, panel.pageText = prev, nextBtn, pageText
    local legend = bags:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("TOPLEFT", panel, "TOPLEFT", 136, -370)
    legend:SetWidth(PW - 148); legend:SetJustifyH("RIGHT")
    legend:SetText("|cff40ff40+|r upgrade · grey = soulbound")
    TB.SetTextColor(legend, color("muted"))

    -- Behaviour view: two columns of toggle chips.
    local behavior = CreateFrame("Frame", nil, panel)
    behavior:SetAllPoints(panel)
    panel.behavior = behavior
    local bhTitle = behavior:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bhTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -78)
    bhTitle:SetText("Combat habits of this bot (saved on the server)")
    TB.SetTextColor(bhTitle, color("gold"))
    panel.behaviorChips = {}
    for i, def in ipairs(C.BEHAVIORS or {}) do
        local chip = CreateFrame("Button", nil, behavior, "UIPanelButtonTemplate")
        chip:SetWidth(150); chip:SetHeight(24)
        chip.def = def
        chip.lamp = chip:CreateTexture(nil, "OVERLAY")
        chip.lamp:SetWidth(8); chip.lamp:SetHeight(8)
        chip.lamp:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
        setTooltip(chip, def.label, { def.tip, "Click to switch on/off." })
        chip:SetScript("OnClick", function()
            if currentBot then TB.SendBehavior(currentBot, this.def.key) end
        end)
        panel.behaviorChips[def.key] = chip
    end
    local bhHint = behavior:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bhHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -228)
    bhHint:SetWidth(PW - 24); bhHint:SetJustifyH("LEFT")
    bhHint:SetText("Party-wide AoE, Auto CC and Loot switches live on the Actions tab; these override one bot.")
    TB.SetTextColor(bhHint, color("muted"))

    -- Footer: trade + refresh for every view.
    local trade = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    trade:SetWidth(100); trade:SetHeight(22)
    trade:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 28)
    trade:SetText("Trade")
    setTooltip(trade, "Trade", {
        "Opens a trade window with this bot.",
        "Put your items or gold in and accept - the bot accepts on its own.",
        "To take an item from the bot, click it in Bags → Give to me.",
    })
    trade:SetScript("OnClick", function() TB.SendItemOrder("trade") end)
    panel.tradeButton = trade

    local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refresh:SetWidth(80); refresh:SetHeight(22)
    refresh:SetPoint("LEFT", trade, "RIGHT", 6, 0)
    refresh:SetText("Refresh")
    setTooltip(refresh, "Refresh", { "Reload gear, bags and behaviour from the server." })
    refresh:SetScript("OnClick", function()
        if currentBot then TB.RequestInventory(currentBot) end
        if TB.PollList then TB.PollList(true) end
    end)
    panel.refreshButton = refresh

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
    hint:SetWidth(PW - 24); hint:SetJustifyH("LEFT")
    hint:SetText("Click an item for options. Shift-click links it in chat.")
    TB.SetTextColor(hint, color("muted"))

    itemMenu = createMenu(panel)

    -- Uncached items re-render once the client has them.
    panel:SetScript("OnUpdate", function()
        if uncachedAt and now() - uncachedAt > 1 then
            uncachedAt = nil
            TB.RefreshBotPanel()
        end
    end)
    panel:Hide()
    TB.botPanel = panel
end

-- ── rendering ───────────────────────────────────────────────────────────────
local function renderHeader(inv)
    local classId = botClassId(currentBot)
    local col = classId and C.CLASS_COLORS and C.CLASS_COLORS[classId] or color("gold")
    panel.nameText:SetText(currentBot or "")
    panel.nameText:SetTextColor(col[1], col[2], col[3])
    local parts = {}
    local unit = botUnit(currentBot)
    local claimed = TB.GetClaimedEntry and TB.GetClaimedEntry(currentBot)
    if unit and UnitLevel then
        table.insert(parts, "Lvl " .. (UnitLevel(unit) or "?"))
    elseif claimed and claimed.level then
        table.insert(parts, "Lvl " .. claimed.level)
    end
    if classId and C.CLASS_NAMES then table.insert(parts, C.CLASS_NAMES[classId]) end
    if claimed then
        if claimed.gearLocked then
            table.insert(parts, "|cffffd200Gear Locked|r")
        else
            table.insert(parts, "|cff4ecb5aLeveling|r")
        end
    end
    local move = TB.MovementLabel(currentBot)
    if move then table.insert(parts, move) end
    panel.subText:SetText(table.concat(parts, " · "))
    panel.moneyText:SetText(inv and formatMoney(inv.money) or "")
    local bagCount = inv and table.getn(inv.items) or 0
    panel.tabBags:SetText(inv and ("Bags (" .. bagCount .. ")") or "Bags")
end

local function renderGear(inv)
    local equipped = inv and inv.equipped or {}
    local lowest, upgrades = nil, 0
    for slot, b in pairs(panel.gearButtons) do
        local item = equipped[slot]
        local entry = item and {
            id = item.id, bag = EQUIPPED_BAG, slot = slot, equipped = true,
            durability = item.durability, maxDurability = item.maxDurability,
        } or nil
        paintItemButton(b, entry, b.emptyTexture)
        if item and item.maxDurability and item.maxDurability > 0 then
            local pct = item.durability / item.maxDurability
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    for _, item in ipairs(inv and inv.items or {}) do
        if item.upgrade then upgrades = upgrades + 1 end
    end
    local text = inv and "" or "Loading…"
    if lowest then
        local pct = math.floor(lowest * 100 + 0.5)
        local hex = pct < 25 and "|cffff4030" or (pct < 60 and "|cffffd200" or "|cff9d9d9d")
        text = hex .. "Lowest durability " .. pct .. "%|r"
    end
    if upgrades > 0 then
        text = text .. (text ~= "" and "\n" or "") .. "|cff40ff40" .. upgrades .. " upgrade(s) in bags|r"
    end
    panel.durabilityText:SetText(text)
    if panel.model then
        local unit = botUnit(currentBot)
        if unit and panel.model.SetUnit then
            panel.model:SetUnit(unit)
            panel.model:Show()
        else
            panel.model:Hide()
        end
    end
end

local function renderBags(inv)
    local items = inv and inv.items or {}
    local perPage = BAG_COLS * BAG_ROWS
    local pages = math.max(1, math.ceil(table.getn(items) / perPage))
    if bagPage > pages then bagPage = pages end
    if bagPage < 1 then bagPage = 1 end
    for i, b in ipairs(panel.bagButtons) do
        local item = items[(bagPage - 1) * perPage + i]
        if item then paintItemButton(b, item) else b.entry = nil; b:Hide() end
    end
    if inv then
        panel.bagSummary:SetText(table.getn(items) .. " items · " .. (inv.free or 0) .. " of "
            .. (inv.total or 0) .. " slots free")
    else
        panel.bagSummary:SetText("Loading…")
    end
    panel.pageText:SetText(bagPage .. " / " .. pages)
    if bagPage > 1 then panel.prevPage:Enable() else panel.prevPage:Disable() end
    if bagPage < pages then panel.nextPage:Enable() else panel.nextPage:Disable() end
end

local function renderBehavior()
    local st = TB.GetBotState(currentBot)
    local classId = botClassId(currentBot)
    local noMana = classId and C.NO_MANA_CLASSES and C.NO_MANA_CLASSES[classId]
    local shown = 0
    for _, def in ipairs(C.BEHAVIORS or {}) do
        local key = def.key
        local chip = panel.behaviorChips[key]
        local value = st and st[key]
        local pending = currentBot and behaviorPending[norm(currentBot) .. "|" .. key]
        if chip.def.mana and noMana then
            chip:Hide()
        else
            -- Two columns, reflowed so a hidden chip leaves no hole.
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + math.mod(shown, 2) * 156,
                -98 - math.floor(shown / 2) * 30)
            shown = shown + 1
            chip:Show()
            local stateText = value == "on" and "On" or (value == "off" and "Off" or "?")
            chip:SetText(chip.def.label .. ": " .. stateText)
            if value == "on" then chip.lamp:SetTexture(0.30, 0.90, 0.45, 1)
            elseif value == "off" then chip.lamp:SetTexture(0.45, 0.45, 0.45, 1)
            else chip.lamp:SetTexture(0.95, 0.72, 0.28, 1) end
            if st and not pending then chip:Enable() else chip:Disable() end
        end
    end
end

function TB.RefreshBotPanel()
    if not panel or not panel:IsVisible() or not currentBot then return end
    local inv = TB.GetInventory(currentBot)
    renderHeader(inv)
    panel.gear:Hide(); panel.bags:Hide(); panel.behavior:Hide()
    panel.tabGear:Enable(); panel.tabBags:Enable(); panel.tabBehavior:Enable()
    if currentView == "bags" then
        panel.bags:Show(); panel.tabBags:Disable()
        renderBags(inv)
    elseif currentView == "behavior" then
        panel.behavior:Show(); panel.tabBehavior:Disable()
        renderBehavior()
    else
        panel.gear:Show(); panel.tabGear:Disable()
        renderGear(inv)
    end
    local online = TB.GetBotState(currentBot) ~= nil or botUnit(currentBot) ~= nil
    if online then panel.tradeButton:Enable() else panel.tradeButton:Disable() end
end

function TB.OpenBotPanel(name, view)
    name = norm(name)
    if not name then return false end
    if not panel then createPanel() end
    if TB.SetMode then TB.SetMode("full") end
    if currentBot ~= name then bagPage = 1 end
    currentBot = name
    if view then currentView = view end
    hideMenu()
    panel:ClearAllPoints()
    if TB.frame then
        -- Open on the side of the main window that has room.
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + PW + 4) * scale > screen then
            panel:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            panel:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    panel:Show()
    TB.RefreshBotPanel()
    TB.RequestInventory(name)
    return true
end

function TB.CloseBotPanel()
    hideMenu()
    if panel then panel:Hide() end
end

-- ── trade window follow-up ──────────────────────────────────────────────────
-- "Give to me" without an open trade makes the bot open one first; once the
-- window shows, the same order is sent again and the item goes in.
local tradeFrame = CreateFrame("Frame", "TortoiseBotsManagerTradeWatcher")
tradeFrame:RegisterEvent("TRADE_SHOW")
tradeFrame:RegisterEvent("TRADE_CLOSED")
tradeFrame:SetScript("OnEvent", function()
    if event == "TRADE_SHOW" then
        local partner = UnitName and norm(UnitName("NPC")) or nil
        local give = pendingGive
        if give and partner == give.bot then
            pendingGive = nil
            TB.SendBotCommand("item " .. give.bot .. " give " .. give.bag .. " " .. give.slot)
        end
    elseif event == "TRADE_CLOSED" then
        pendingGive = nil
        -- Traded items change the bags: reload what the panel shows.
        if TB.GetBotPanelBot() then
            TB.inventoryRefreshBot = TB.GetBotPanelBot()
            TB.RequestInventorySoon()
        end
    end
end)

local refreshFrame
function TB.RequestInventorySoon()
    if not refreshFrame then
        refreshFrame = CreateFrame("Frame", "TortoiseBotsManagerInventoryRefresh")
        refreshFrame:SetScript("OnUpdate", function()
            this.elapsed = (this.elapsed or 0) + (arg1 or 0)
            if this.elapsed < 1 then return end
            this:Hide()
            local bot = TB.inventoryRefreshBot
            TB.inventoryRefreshBot = nil
            if bot and TB.GetBotPanelBot() == bot then TB.RequestInventory(bot) end
        end)
    end
    refreshFrame.elapsed = 0
    refreshFrame:Show()
end
