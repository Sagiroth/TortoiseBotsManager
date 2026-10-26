-- TortoiseBotsManager/BotVault.lua
-- Read-only bank and mailbox lists for one bot, plus withdraw/take orders.
--
-- The bank and the mailbox need a nearby NPC/object mature-side, so the bot
-- answers with whisper lines instead of the structured TBM:INV_* snapshot:
--   "=== Bank ===" then one "|c…|Hitem:<id>:…|h[<name>]|h|r[xN]" line per item
--   "=== Mailbox ===" then one "#<n> <item links/money>" line per letter
-- (server: BankAction.cpp ListItems/InventoryTellItems, MailAction.cpp
-- TellMailProcessor). Clicking a bank row sends "command <bot> bank -<link>";
-- clicking Take sends "command <bot> mail take <n>". Withdraw/take replies
-- arrive as ordinary whispers on the command-op gate.

local TB = TortoiseBots
local C = TB.C or {}
local COL = C.COLOR or {}
local VW = 300
local VH = 290
local ROWS = 8

local function norm(name) return name and TB.NormalizeName(name) or nil end
local function color(name) return COL[name] or { 1, 1, 1 } end
local function now() return (GetTime and GetTime()) or 0 end

-- ── model ─────────────────────────────────────────────────────────────────
-- [bot] = { at, pending, header, bank = { { id, name, count } }, mail = { { n, text } } }
local vaults = {}

function TB.GetVault(name)
    name = norm(name)
    return name and vaults[name] or nil
end

local function entry(name)
    name = norm(name)
    if not name then return nil end
    local v = vaults[name]
    if not v then v = { bank = {}, mail = {} }; vaults[name] = v end
    return v
end

function TB.SetVaultPending(name, pending)
    name = norm(name)
    if not name then return end
    local v = entry(name)
    v.pending = pending and true or false
    v.header = false
    v.at = now()
end

-- Parses "|cffffffff|Hitem:1234:0:0:0|h[Linen Cloth]|h|rx3" (count optional).
-- Trailing skill text ("…|h|r - |cffffff00yellow|r") stays outside the name.
local function parseVaultLine(msg)
    if not msg then return nil end
    local _, _, id, label = string.find(msg, "Hitem:(%d+):.-|h%[([^%]]+)%]")
    id = tonumber(id)
    if not id or not label then return nil end
    label = TB.Trim(label)
    if label == "" then return nil end
    local _, _, count = string.find(msg, "|h|rx(%d+)")
    count = tonumber(count) or 1
    return id, label, count
end
TB.ParseVaultLine = parseVaultLine

-- Returns "header" / item count / "mail" / false. Only lines of an open
-- "=== Bank ===" / "=== Mailbox ===" reply reach the lists: item and letter
-- lines before the header are not consumed, so a stale or foreign whisper
-- can never seed the wrong list. Anything unconsumed stays on the
-- command-op gate so AI replies and take/withdraw confirmations keep working.
function TB.ConsumeVaultReply(name, msg)
    name = norm(name)
    if not name or not msg or msg == "" then return false end
    if name ~= TB.GetVaultBot() then return false end
    local v = vaults[name]
    if not v or not v.pending then return false end
    -- One whisper per line, no end marker: the burst ends when the bot goes
    -- quiet, then later whispers return to the command-op gate.
    if now() - (v.at or 0) > (C.ACTION_TIMEOUT or 8) then
        v.pending = false
        v.header = false
        return false
    end
    if string.find(msg, "=== Bank ===") then
        v.bank = {}
        v.header = "bank"
        v.at = now()
        if TB.RefreshVault then TB.RefreshVault() end
        return "header"
    end
    if string.find(msg, "=== Mailbox ===") then
        v.mail = {}
        v.header = "mail"
        v.at = now()
        if TB.RefreshVault then TB.RefreshVault() end
        return "header"
    end
    if v.header == "mail" then
        if not string.find(msg, "^#%d+ ") then return false end
        local _, _, n = string.find(msg, "^#(%d+) ")
        v.mail = v.mail or {}
        table.insert(v.mail, { n = tonumber(n) or 0, text = msg })
        v.at = now()
        if TB.RefreshVault then TB.RefreshVault() end
        return table.getn(v.mail)
    end
    if v.header ~= "bank" then return false end
    if string.find(msg, "^#%d+ ") then return false end
    local id, label, count = parseVaultLine(msg)
    if not id then return false end
    v.bank = v.bank or {}
    for _, known in ipairs(v.bank) do
        if known.id == id then return table.getn(v.bank) end
    end
    table.insert(v.bank, { id = id, name = label, count = count })
    v.at = now()
    if TB.RefreshVault then TB.RefreshVault() end
    return table.getn(v.bank)
end
function TB.RequestBank(name)
    name = norm(name)
    if not name then return false end
    local v = entry(name)
    v.bank = {}
    v.pending = true
    v.header = false
    v.at = now()
    local sent = TB.SendBotCommand("command " .. name .. " bank")
    -- The proxy acks with "Forwarded command" but no completion line ever
    -- follows a list query, so the command op is completed on send: leaving
    -- it would show a working state until it times out.
    if TB.CompleteOperation then TB.CompleteOperation(name, "command", true, "Bank query sent.") end
    local st = TB.GetState and TB.GetState(name) or nil
    if st then st.pendingAI = nil; st.pendingAIUntil = nil end
    if TB.SetStatus then TB.SetStatus("Asking " .. name .. " to open its bank…", "pending") end
    if TB.RefreshVault then TB.RefreshVault() end
    return sent
end

function TB.RequestMailbox(name)
    name = norm(name)
    if not name then return false end
    local v = entry(name)
    v.mail = {}
    v.pending = true
    v.header = false
    v.at = now()
    -- Same as above: no completion line follows the "Forwarded" ack.
    local sent = TB.SendBotCommand("command " .. name .. " mail ?")
    if TB.CompleteOperation then TB.CompleteOperation(name, "command", true, "Mailbox query sent.") end
    local st = TB.GetState and TB.GetState(name) or nil
    if st then st.pendingAI = nil; st.pendingAIUntil = nil end
    if TB.SetStatus then TB.SetStatus("Asking " .. name .. " to check its mail…", "pending") end
    if TB.RefreshVault then TB.RefreshVault() end
    return sent
end

-- Withdraw form: a leading "-" selects bank stock (BankAction::ExecuteCommand:
-- "-" withdraws via ITERATE_ITEMS_IN_BANK, without it deposits from bags).
function TB.SendBankWithdraw(name, id, label)
    name = norm(name)
    id = tonumber(id)
    if not name or not id then return false end
    if TB.SetStatus then TB.SetStatus(name .. " takes " .. (label or ("item " .. id)) .. " from its bank…", "pending") end
    return TB.SendBotCommand("command " .. name .. " bank -|Hitem:" .. id .. ":0:0:0|h[" .. (label or ("item " .. id)) .. "]|h")
end

function TB.SendMailTake(name, n)
    name = norm(name)
    n = tonumber(n)
    if not name or not n then return false end
    if TB.SetStatus then TB.SetStatus(name .. " takes letter #" .. n .. "…", "pending") end
    return TB.SendBotCommand("command " .. name .. " mail take " .. n)
end

-- ── window ────────────────────────────────────────────────────────────────
local vault
local currentBot
local currentView = "bank" -- or "mail"
local page = 1

function TB.GetVaultBot()
    return vault and vault:IsVisible() and currentBot or nil
end

local function setTooltip(button, title, lines)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function makeTab(parent, label, x, width, view)
    local b = TB.StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetWidth(width); b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -36)
    b:SetText(label)
    b:SetScript("OnClick", function()
        currentView = view
        page = 1
        TB.RefreshVault()
    end)
    return b
end

local function createVault()
    vault = CreateFrame("Frame", "TortoiseBotsManagerBotVault", TB.frame or UIParent)
    vault:SetWidth(VW); vault:SetHeight(VH)
    vault:SetFrameStrata("DIALOG")
    vault:EnableMouse(true)
    vault:SetMovable(true)
    vault:SetClampedToScreen(true)
    vault:RegisterForDrag("LeftButton")
    vault:SetScript("OnDragStart", function() vault:StartMoving() end)
    vault:SetScript("OnDragStop", function()
        vault:StopMovingOrSizing()
        -- 1.12-safe: StopMovingOrSizing detaches the anchor from the
        -- logical parent (see UI.lua drag header), so re-anchor with
        -- GetLeft/GetTop instead of ever calling GetPoint() after a drag.
        local left, top = vault:GetLeft(), vault:GetTop()
        if left and top then
            vault:ClearAllPoints()
            vault:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TortoiseBotsManagerBotVault") end
    TB.ApplyBackdrop(vault, 0.98, 1.0)

    local name = vault:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", vault, "TOPLEFT", 12, -10)
    name:SetWidth(VW - 50); name:SetJustifyH("LEFT")
    vault.nameText = name

    local close = CreateFrame("Button", nil, vault, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", vault, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() TB.CloseVault() end)

    vault.tabBank = makeTab(vault, "Bank", 10, 68, "bank")
    setTooltip(vault.tabBank, "Bank", { "What this bot keeps in its bank." })
    vault.tabMail = makeTab(vault, "Mailbox", 82, 76, "mail")
    setTooltip(vault.tabMail, "Mailbox", { "Letters waiting for this bot." })

    local summary = vault:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", vault, "TOPLEFT", 12, -62)
    summary:SetWidth(134); summary:SetJustifyH("LEFT")
    TB.SetTextColor(summary, color("muted"))
    vault.summary = summary

    vault.rows = {}
    for i = 1, ROWS do
        local row = TB.StyleButton(CreateFrame("Button", nil, vault, "UIPanelButtonTemplate"))
        row:SetWidth(VW - 24); row:SetHeight(20)
        row:SetPoint("TOPLEFT", vault, "TOPLEFT", 12, -80 - (i - 1) * 22)
        row:SetScript("OnClick", function()
            if currentView == "bank" then
                if currentBot and this.itemId then TB.SendBankWithdraw(currentBot, this.itemId, this.itemName) end
            else
                if currentBot and this.mailN then TB.SendMailTake(currentBot, this.mailN) end
            end
        end)
        table.insert(vault.rows, row)
    end

    local ask = TB.StyleButton(CreateFrame("Button", nil, vault, "UIPanelButtonTemplate"))
    ask:SetWidth(134); ask:SetHeight(22)
    ask:SetPoint("TOPLEFT", vault, "TOPLEFT", 12, -80 - ROWS * 22)
    ask:SetText("Ask again")
    ask:SetScript("OnClick", function()
        if not currentBot then return end
        if currentView == "mail" then TB.RequestMailbox(currentBot) else TB.RequestBank(currentBot) end
    end)
    setTooltip(ask, "Ask again", { "Reloads this list from the bot." })
    vault.ask = ask

    local prev = TB.StyleButton(CreateFrame("Button", nil, vault, "UIPanelButtonTemplate"))
    prev:SetWidth(26); prev:SetHeight(22)
    prev:SetPoint("TOPLEFT", vault, "TOPLEFT", 154, -80 - ROWS * 22)
    prev:SetText("<")
    prev:SetScript("OnClick", function() page = page - 1; TB.RefreshVault() end)
    vault.prevPage = prev
    local nextBtn = TB.StyleButton(CreateFrame("Button", nil, vault, "UIPanelButtonTemplate"))
    nextBtn:SetWidth(26); nextBtn:SetHeight(22)
    nextBtn:SetPoint("TOPLEFT", vault, "TOPLEFT", 262, -80 - ROWS * 22)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function() page = page + 1; TB.RefreshVault() end)
    vault.nextPage = nextBtn
    local pageText = vault:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("TOPLEFT", vault, "TOPLEFT", 182, -84 - ROWS * 22)
    pageText:SetWidth(78); pageText:SetJustifyH("CENTER")
    TB.SetTextColor(pageText, color("muted"))
    vault.pageText = pageText

    local hint = vault:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", vault, "TOPLEFT", 150, -62)
    hint:SetWidth(VW - 162); hint:SetJustifyH("RIGHT")
    hint:SetText("Click a row to take it.")
    TB.SetTextColor(hint, color("muted"))
    vault.hint = hint

    vault:Hide()
    TB.botVault = vault
end

local function renderRows()
    local v = currentBot and vaults[currentBot] or nil
    local list = {}
    if currentView == "mail" then
        list = (v and v.mail) or {}
    else
        list = (v and v.bank) or {}
    end
    local pages = math.max(1, math.ceil(table.getn(list) / ROWS))
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    for i, row in ipairs(vault.rows) do
        local item = list[(page - 1) * ROWS + i]
        if item then
            row.itemId, row.itemName, row.mailN = item.id, item.name, item.n
            if currentView == "mail" then
                row:SetText(item.text)
                setTooltip(row, "Letter #" .. item.n, { item.text, "Click: take this letter." })
            else
                row:SetText((item.count and item.count > 1 and (item.name .. " x" .. item.count)) or item.name)
                setTooltip(row, item.name, { "Click: the bot takes this from its bank." })
            end
            row:Show()
            row:Enable()
        else
            row.itemId, row.itemName, row.mailN = nil, nil, nil
            row:SetText("")
            row:Hide()
        end
    end
    vault.pageText:SetText(page .. " / " .. pages)
    if page > 1 then vault.prevPage:Enable() else vault.prevPage:Disable() end
    if page < pages then vault.nextPage:Enable() else vault.nextPage:Disable() end
    if v and v.pending and table.getn(list) == 0 then
        vault.ask:SetText("Asking…")
        vault.ask:Disable()
    else
        vault.ask:SetText("Ask again")
        vault.ask:Enable()
    end
    return list
end

function TB.RefreshVault()
    if not vault or not vault:IsVisible() or not currentBot then return end
    local entry = (TB.GetRosterEntry and TB.GetRosterEntry(currentBot))
        or (TB.GetClaimedEntry and TB.GetClaimedEntry(currentBot)) or nil
    local classId = entry and entry.classId
    local col = (classId and C.CLASS_COLORS and C.CLASS_COLORS[classId]) or color("gold")
    vault.nameText:SetText(currentBot or "")
    vault.nameText:SetTextColor(col[1], col[2], col[3])
    local v = vaults[currentBot]
    local list = renderRows()
    if currentView == "mail" then
        vault.summary:SetText((v and table.getn(list) .. " letter(s)") or "Loading…")
    else
        vault.summary:SetText((v and table.getn(list) .. " item(s) in bank") or "Loading…")
    end
    vault.tabBank:Enable(); vault.tabMail:Enable()
    if currentView == "mail" then vault.tabMail:Disable() else vault.tabBank:Disable() end
end

function TB.OpenVault(name, view)
    name = norm(name)
    if not name then return false end
    if not vault then createVault() end
    if currentBot and currentBot ~= name then TB.SetVaultPending(currentBot, false) end
    if TB.CloseNpc then TB.CloseNpc() end
    if TB.CloseRunWindow then TB.CloseRunWindow() end
    if TB.SetMode then TB.SetMode("full") end
    if currentBot ~= name then page = 1 end
    currentBot = name
    currentView = view or "bank"
    vault:ClearAllPoints()
    local anchor = (TB.botPanel and TB.botPanel.IsVisible and TB.botPanel:IsVisible()) and TB.botPanel or TB.frame
    if anchor and anchor ~= TB.frame then
        local aRight = anchor.GetRight and anchor:GetRight()
        local fLeft = TB.frame and TB.frame.GetLeft and TB.frame:GetLeft()
        local aLeft = anchor.GetLeft and anchor:GetLeft()
        if aRight and fLeft and aRight <= fLeft then
            -- The panel sits LEFT of main: anchor right of the panel would
            -- land on main, so dock left of the panel (or right of main
            -- when the panel hugs the left screen edge).
            if aLeft and aLeft - VW - 4 >= 0 then
                vault:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
            elseif TB.frame then
                vault:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
            else
                vault:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        else
            local right = anchor.GetRight and anchor:GetRight()
            local screen = GetScreenWidth and GetScreenWidth()
            local scale = (anchor.GetScale and anchor:GetScale()) or 1
            if right and screen and (right + VW + 4) * scale > screen then
                -- The panel sits right of main: anchoring left of the panel
                -- would land on top of main, so dock left of main instead.
                vault:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
            else
                vault:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
            end
        end
    elseif TB.frame then
        local right = TB.frame.GetRight and TB.frame:GetRight()
        local screen = GetScreenWidth and GetScreenWidth()
        local scale = (TB.frame.GetScale and TB.frame:GetScale()) or 1
        if right and screen and (right + VW + 4) * scale > screen then
            vault:SetPoint("TOPRIGHT", TB.frame, "TOPLEFT", -4, 0)
        else
            vault:SetPoint("TOPLEFT", TB.frame, "TOPRIGHT", 4, 0)
        end
    else
        vault:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    vault:Show()
    TB.RefreshVault()
    if currentView == "mail" then TB.RequestMailbox(name) else TB.RequestBank(name) end
    return true
end

function TB.CloseVault()
    if currentBot then TB.SetVaultPending(currentBot, false) end
    if vault then vault:Hide() end
end
