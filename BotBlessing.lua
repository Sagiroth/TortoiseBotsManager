-- TortoiseBotsManager/BotBlessing.lua
-- Paladin blessing grid for the group: one row per paladin bot, one column
-- per class present, each cell the blessing that paladin gives that class.
-- Needs the `blessing` capability; opened from the Party tab.
--
--   .bot blessing <bot|party|raid> status       -> TBM:BLESSING|<bot>|warrior=<b>,...,druid=<b>,known=<b>+<b>
--   .bot blessing <bot> <class> <blessing|auto> one cell
-- <b> is auto or might, wisdom, kings, salvation, sanctuary, light.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}

local CAP = "blessing"
local NAME_W = 92
local CELL_W = 36
local CELL_H = 30
local ROW_STEP = 34
local MAX_ROWS = 8
local ROWS_TOP = 62
local PAD = 12
local WIN_W_MAX = PAD * 2 + NAME_W + 9 * CELL_W

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── model ───────────────────────────────────────────────────────────────────
-- [paladin] = { classes = { warrior = "kings", ... }, known = { "might", ... } }
local blessings = {}
local pendingCell = {} -- [paladin] = true while a cell order waits for its reply
local win

function TB.HasBlessingCapability()
    return TB.HasServerCapability and TB.HasServerCapability(CAP) or false
end

function TB.GetBlessings(name)
    name = norm(name)
    return name and blessings[name] or nil
end

function TB.SetBlessings(name, snapshot)
    name = norm(name)
    if not name or type(snapshot) ~= "table" then return end
    blessings[name] = snapshot
    pendingCell[name] = nil
    if TB.RefreshBlessings then TB.RefreshBlessings() end
end

local function validBlessing(value)
    if value == "auto" then return true end
    for _, b in ipairs(C.BLESSINGS) do
        if b == value then return true end
    end
    return false
end

-- TBM:BLESSING|<paladin>|warrior=<b>,paladin=<b>,...,druid=<b>,known=<b>+<b>.
-- Every class must carry a valid value; `known` may be empty and, when
-- missing, reads as nil (every blessing is then offered).
function TB.ParseBlessingLine(msg)
    if string.sub(msg or "", 1, 13) ~= "TBM:BLESSING|" then return nil end
    local text = string.sub(msg, 14)
    local bar = string.find(text, "|", 1, true)
    if not bar then return nil end
    local name = norm(string.sub(text, 1, bar - 1))
    if not name or name == "" then return nil end
    local rest = string.sub(text, bar + 1)
    local extra = string.find(rest, "|", 1, true)
    if extra then rest = string.sub(rest, 1, extra - 1) end
    local classes, known = {}, nil
    for pair in string.gfind(rest, "[^,]+") do
        local _, _, key, value = string.find(pair, "^%s*(%a+)%s*=%s*(.-)%s*$")
        if key then
            key = string.lower(key)
            value = string.lower(value)
            if key == "known" then
                known = {}
                for item in string.gfind(value, "[^+]+") do
                    item = TB.Trim(item)
                    if validBlessing(item) and item ~= "auto" then table.insert(known, item) end
                end
            else
                for _, cls in ipairs(C.BLESSING_CLASSES) do
                    if cls.word == key then
                        if not validBlessing(value) then return nil end
                        classes[key] = value
                    end
                end
            end
        end
    end
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if not classes[cls.word] then return nil end
    end
    return { name = name, classes = classes, known = known }
end

function TB.ConsumeBlessingLine(msg)
    local snapshot = TB.ParseBlessingLine(msg)
    if not snapshot then return false end
    TB.SetBlessings(snapshot.name, { classes = snapshot.classes, known = snapshot.known })
    return true
end

-- Auto first, then the blessings that paladin has trained in the usual order.
function TB.BlessingOptions(known)
    local out = { "auto" }
    for _, b in ipairs(C.BLESSINGS) do
        local keep = known == nil
        for _, k in ipairs(known or {}) do
            if k == b then keep = true end
        end
        if keep then table.insert(out, b) end
    end
    return out
end

-- The next (step 1) or previous (step -1) blessing in the cycle; a value
-- the paladin cannot cast any more starts from Auto.
function TB.NextBlessing(current, known, step)
    local options = TB.BlessingOptions(known)
    local count = table.getn(options)
    local at = 1
    for i, b in ipairs(options) do
        if b == current then at = i end
    end
    return options[math.mod(at - 1 + step + count, count) + 1]
end

function TB.BlessingLabel(value)
    if value == "auto" then return "Auto" end
    return value and C.BLESSING_LABELS[value] or "?"
end

-- ── commands ────────────────────────────────────────────────────────────────
function TB.BuildBlessingCommand(bot, word, value)
    bot = norm(bot)
    if not bot or not validBlessing(value) then return nil end
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if cls.word == word then return "blessing " .. bot .. " " .. word .. " " .. value end
    end
    return nil
end

local function groupUnits()
    local out = {}
    local raid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do table.insert(out, "raid" .. i) end
    else
        table.insert(out, "player")
        local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, party do table.insert(out, "party" .. i) end
    end
    return out
end

function TB.BlessingScope()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "raid" end
    return "party"
end

-- The paladin bots of the group (sorted) and the class ids present in it.
function TB.GetBlessingGroup()
    local paladins, present = {}, {}
    local ids = C.CLASS_NAME_TO_ID or {}
    for _, unit in ipairs(groupUnits()) do
        local name = UnitName and norm(UnitName(unit))
        if name and UnitClass then
            local className, classFile = UnitClass(unit)
            local classId = ids[classFile or ""] or ids[className or ""]
            if classId then
                present[classId] = true
                if classId == 2 and TB.GetBotState and TB.GetBotState(name) then
                    table.insert(paladins, name)
                end
            end
        end
    end
    table.sort(paladins)
    return paladins, present
end

function TB.BlessingAvailable()
    if not TB.HasBlessingCapability() then return false end
    return table.getn((TB.GetBlessingGroup())) > 0
end

function TB.RequestBlessings()
    return TB.SendBotCommand("blessing " .. TB.BlessingScope() .. " status")
end

function TB.SendBlessing(bot, word, value)
    local cmd = TB.BuildBlessingCommand(bot, word, value)
    if not cmd then return false end
    pendingCell[norm(bot)] = true
    if TB.RefreshBlessings then TB.RefreshBlessings() end
    return TB.SendBotCommand(cmd)
end

-- Left-click moves to the next blessing, right-click to the previous one.
function TB.CycleBlessing(bot, word, step)
    local snapshot = TB.GetBlessings(bot)
    if not snapshot or pendingCell[norm(bot)] then return false end
    return TB.SendBlessing(bot, word, TB.NextBlessing(snapshot.classes[word], snapshot.known, step))
end

-- ACK routing from Comms. Returns true when handled.
function TB.OnBlessingAck(packet)
    local intent = packet.intent or ""
    if intent == "blessing status" then
        if TB.SetStatus then TB.SetStatus("Blessings · " .. (packet.count or 0) .. " paladin(s)", "ok") end
        return true
    end
    if intent ~= "blessing" then return false end
    local _, _, bot = string.find(packet.scope or "", "^bot:(.+)$")
    bot = norm(bot)
    if bot then pendingCell[bot] = nil end
    local _, _, word, value = string.find(packet.executor or "", "^(%a+)=(%a+)$")
    if TB.SetStatus then
        local text = "Blessing set"
        if bot and word and value then
            text = bot .. ": " .. string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
                .. " → " .. TB.BlessingLabel(value)
        end
        TB.SetStatus(text, "ok")
    end
    if TB.RefreshBlessings then TB.RefreshBlessings() end
    return true
end

function TB.OnBlessingError(packet)
    if packet.intent ~= "blessing" then return end
    for bot in pairs(pendingCell) do pendingCell[bot] = nil end
    if TB.RefreshBlessings then TB.RefreshBlessings() end
end

-- ── window ──────────────────────────────────────────────────────────────────
local function createCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetWidth(CELL_W - 4); cell:SetHeight(CELL_H)
    cell:EnableMouse(true)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.border:SetAllPoints(cell)
    cell.border:SetTexture(0.25, 0.25, 0.25, 0.9)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetWidth(CELL_H - 6); cell.icon:SetHeight(CELL_H - 6)
    cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.label:SetPoint("CENTER", cell, "CENTER", 0, 0)
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(cell)
    hl:SetTexture(1, 1, 1, 0.15)
    cell:SetScript("OnEnter", function()
        local snapshot = TB.GetBlessings(this.bot)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText((this.bot or "") .. " → " .. (this.className or ""))
        GameTooltip:AddLine("Now: " .. TB.BlessingLabel(snapshot and snapshot.classes[this.word]), 0.9, 0.9, 0.9, 1)
        GameTooltip:AddLine("Left-click: next blessing. Right-click: previous.", 0.62, 0.60, 0.56, 1)
        GameTooltip:AddLine("Auto lets the paladin choose.", 0.62, 0.60, 0.56, 1)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell:SetScript("OnClick", function()
        if this.bot and this.word then
            TB.CycleBlessing(this.bot, this.word, arg1 == "RightButton" and -1 or 1)
        end
    end)
    return cell
end

local function createWindow()
    win = CreateFrame("Frame", "TortoiseBotsManagerBlessings", TB.frame or UIParent)
    win:SetWidth(300); win:SetHeight(120)
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerBlessings") end
    TB.ApplySurface(win, "window")
    TB.AddWindowHeader(win, 30)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -9)
    title:SetText("Blessings")
    TB.StyleTitle(title, 14)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    TB.StyleCloseButton(close, -7, -6)
    close:SetScript("OnClick", function() TB.CloseBlessings() end)

    win.heads = {}
    for i = 1, table.getn(C.BLESSING_CLASSES) do
        local head = CreateFrame("Button", nil, win)
        head:SetWidth(22); head:SetHeight(22)
        head.icon = head:CreateTexture(nil, "ARTWORK")
        head.icon:SetAllPoints(head)
        head:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.className or "")
            GameTooltip:Show()
        end)
        head:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win.heads[i] = head
    end
    win.rows = {}
    for r = 1, MAX_ROWS do
        local row = { cells = {} }
        row.name = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetWidth(NAME_W - 4); row.name:SetJustifyH("LEFT")
        for c = 1, table.getn(C.BLESSING_CLASSES) do
            row.cells[c] = createCell(win)
        end
        win.rows[r] = row
    end
    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.hint:SetJustifyH("LEFT")
    win.hint:SetText("Left-click: next blessing · Right-click: previous · Auto: the paladin chooses")
    TB.SetTextColor(win.hint, color("muted"))
    win:Hide()
    TB.blessingsWindow = win
end

function TB.RefreshBlessings()
    if not win or not win:IsVisible() then return end
    local paladins, present = TB.GetBlessingGroup()
    if not TB.HasBlessingCapability() or table.getn(paladins) == 0 then
        TB.CloseBlessings()
        return
    end
    local columns = {}
    for _, cls in ipairs(C.BLESSING_CLASSES) do
        if present[cls.id] then table.insert(columns, cls) end
    end
    local rowCount = math.min(table.getn(paladins), MAX_ROWS)
    local width = math.max(PAD * 2 + NAME_W + table.getn(columns) * CELL_W, 260)
    win:SetWidth(width)
    win:SetHeight(ROWS_TOP + rowCount * ROW_STEP + 30)
    for i, head in ipairs(win.heads) do
        local cls = columns[i]
        if cls then
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + (i - 1) * CELL_W + 5, -36)
            TB.SetClassIcon(head.icon, cls.id)
            head.className = C.CLASS_NAMES[cls.id]
            head:Show()
        else
            head:Hide()
        end
    end
    for r, row in ipairs(win.rows) do
        local name = paladins[r]
        if r <= rowCount and name then
            local snapshot = TB.GetBlessings(name)
            local top = -ROWS_TOP - (r - 1) * ROW_STEP
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, top - 9)
            row.name:SetText(name)
            local pal = C.CLASS_COLORS[2]
            row.name:SetTextColor(pal[1], pal[2], pal[3])
            row.name:Show()
            for c, cell in ipairs(row.cells) do
                local cls = columns[c]
                if cls then
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + NAME_W + (c - 1) * CELL_W + 2, top)
                    cell.bot, cell.word, cell.className = name, cls.word, C.CLASS_NAMES[cls.id]
                    local value = snapshot and snapshot.classes[cls.word]
                    if value and value ~= "auto" and C.BLESSING_ICONS[value] then
                        cell.icon:SetTexture(C.BLESSING_ICONS[value])
                        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        cell.icon:Show()
                        cell.label:SetText("")
                    else
                        cell.icon:Hide()
                        cell.label:SetText(value and "Auto" or "…")
                    end
                    if snapshot and not pendingCell[name] then cell:Enable() else cell:Disable() end
                    cell:Show()
                else
                    cell:Hide()
                end
            end
        else
            row.name:Hide()
            for _, cell in ipairs(row.cells) do cell:Hide() end
        end
    end
    win.hint:ClearAllPoints()
    win.hint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(ROWS_TOP + rowCount * ROW_STEP + 4))
    win.hint:SetWidth(width - PAD * 2)
end

function TB.OpenBlessings()
    if not TB.BlessingAvailable() then return false end
    if not win then createWindow() end
    if TB.CloseBotPanel then TB.CloseBotPanel() end
    if TB.CloseVault then TB.CloseVault() end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.CloseServerInfo then TB.CloseServerInfo() end
    if TB.CloseOrderWindow then TB.CloseOrderWindow() end
    if TB.CloseActiveOrders then TB.CloseActiveOrders() end
    win:ClearAllPoints()
    local frame = TB.frame
    local right = frame and frame.GetRight and frame:GetRight()
    local screen = GetScreenWidth and GetScreenWidth()
    local scale = (frame and frame.GetScale and frame:GetScale()) or 1
    if frame and right and screen and (right + WIN_W_MAX + 4) * scale > screen then
        win:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
    elseif frame then
        win:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    win:Show()
    TB.RefreshBlessings()
    TB.RequestBlessings()
    return true
end

function TB.CloseBlessings()
    if win then win:Hide() end
end

function TB.ToggleBlessings()
    if win and win:IsVisible() then TB.CloseBlessings() else TB.OpenBlessings() end
end

-- Capability gone mid-session (server swapped): close, like the other views.
function TB.NoteBlessingCaps()
    if not TB.HasBlessingCapability() then
        for key in pairs(blessings) do blessings[key] = nil end
        TB.CloseBlessings()
    end
    if TB.UpdateBlessingButton then TB.UpdateBlessingButton() end
end

-- The Party tab's entry point: shown when the group has a paladin bot and
-- the server has the command.
function TB.UpdateBlessingButton()
    local button = TB.partyFrame and TB.partyFrame.blessingBtn
    if not button then return end
    if TB.BlessingAvailable() then button:Show() else button:Hide() end
end

-- A changed group re-asks once things settle, while the window is open.
local dueAt
local watcher = CreateFrame("Frame", "TortoiseBotsManagerBlessingWatcher")
watcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
watcher:RegisterEvent("RAID_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
    if win and win:IsVisible() then dueAt = now() + 1 end
    if TB.UpdateBlessingButton then TB.UpdateBlessingButton() end
end)
watcher:SetScript("OnUpdate", function()
    if not dueAt or now() < dueAt then return end
    dueAt = nil
    if win and win:IsVisible() then
        TB.RefreshBlessings()
        if win:IsVisible() then TB.RequestBlessings() end
    end
end)
