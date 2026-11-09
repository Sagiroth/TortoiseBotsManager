-- TortoiseBotsManager/Utils.lua — pure, testable helpers. No frame creation.
local TB = TortoiseBots
local C = TB.C

-- strings
function TB.Trim(s)
    s = s or ""
    s = string.gsub(s, "^%s+", "")
    return string.gsub(s, "%s+$", "")
end

function TB.NormalizeName(s)
    s = TB.Trim(s)
    if s == "" then return nil end
    s = string.lower(s)
    s = string.gsub(s, "^%l", string.upper) -- capitalize
    return s
end

-- colors / ui helpers (no side effects beyond frame)
function TB.SetTextColor(fs, rgb)
    if fs and rgb then fs:SetTextColor(rgb[1], rgb[2], rgb[3]) end
end

-- ── Theme ──────────────────────────────────────────────────────────────────
-- One flat look for every window: a 1px frame on a solid fill (WHITE8X8),
-- a lighter step per depth, gold kept for what is picked or important.
local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
TB.FLAT_BACKDROP = FLAT_BACKDROP
local SHEEN_ALPHA = 0.07

-- The shipped Media textures load only after a full client restart (not
-- /reload). SetTexture returns nil when the file is missing, so each use has
-- a fallback: stock art, or nothing for pure decoration.
function TB.SetMediaTexture(tex, name, fallback)
    if not tex then return false end
    if tex:SetTexture((C.MEDIA or "") .. name) then return true end
    if fallback then tex:SetTexture(fallback) end
    return false
end

local function theme(key)
    return (C.THEME and C.THEME[key]) or { 0.08, 0.08, 0.09, 1 }
end
TB.Theme = theme

local function setColors(frame, fill, edge, fillA, edgeA)
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fillA or fill[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edgeA or edge[4] or 1)
end

-- Surfaces by depth: "window" (top level), "card" (a group inside a
-- window), "row" (a list line), "input" (an edit box well).
function TB.ApplySurface(frame, kind)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop(FLAT_BACKDROP)
    kind = kind or "card"
    if kind == "window" then setColors(frame, theme("window"), theme("windowEdge"))
    elseif kind == "row" then setColors(frame, theme("row"), theme("rowEdge"))
    elseif kind == "input" then setColors(frame, theme("input"), theme("inputEdge"))
    else setColors(frame, theme("card"), theme("cardEdge")) end
    frame.surface = kind
    return frame
end

-- Older call sites pass an alpha pair: near-opaque means a window, the
-- rest are cards and rows inside one.
function TB.ApplyBackdrop(frame, alpha, borderA)
    if (alpha or 0.96) >= 0.9 then
        return TB.ApplySurface(frame, "window")
    end
    return TB.ApplySurface(frame, "card")
end

-- Window chrome: a lighter header band with a hairline under it and a thin
-- gold rule along the top edge. Height covers title (and subtitle) rows.
function TB.AddWindowHeader(frame, height)
    if not frame or frame.headerBand then return end
    local band = frame:CreateTexture(nil, "BACKGROUND")
    local h = theme("header")
    band:SetTexture(h[1], h[2], h[3], h[4] or 1)
    band:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    band:SetHeight(height or 30)
    frame.headerBand = band
    local rule = frame:CreateTexture(nil, "BORDER")
    local a = C.COLOR.accent
    rule:SetTexture(a[1], a[2], a[3], 0.85)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    rule:SetHeight(1)
    frame.headerRule = rule
    local line = frame:CreateTexture(nil, "BORDER")
    local hl = theme("hairline")
    line:SetTexture(0, 0, 0, 0.55)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    frame.headerLine = line
    local lite = frame:CreateTexture(nil, "BORDER")
    lite:SetTexture(hl[1], hl[2], hl[3], hl[4])
    lite:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
    lite:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, 0)
    lite:SetHeight(1)
end

-- A 1px divider line across a frame at y (from its top), inset x.
function TB.AddHairline(frame, y, inset, alpha)
    local line = frame:CreateTexture(nil, "ARTWORK")
    local hl = theme("hairline")
    line:SetTexture(hl[1], hl[2], hl[3], alpha or hl[4])
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", inset or 0, y or 0)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(inset or 0), y or 0)
    line:SetHeight(1)
    return line
end

-- Window titles: the client's large font is 16px and crowds the header;
-- 14px reads as a title without shouting. Font strings take SetFont.
function TB.StyleTitle(fs, size)
    if not fs then return fs end
    if fs.SetFont then fs:SetFont("Fonts\\FRIZQT__.TTF", size or 14) end
    return fs
end

-- Flat buttons: the panel template keeps its behaviour (text, clicks,
-- enable/disable); its red art gives way to a solid fill with a 1 px frame
-- and a soft top sheen. Labels are light, not gold: gold marks what is
-- picked (filled) or primary (outlined), so it still means something.
local BUTTON_FILL = { 0.135, 0.14, 0.155, 1 }
local BUTTON_EDGE = { 0.27, 0.27, 0.29, 1 }
local ACTIVE_FILL = { 0.62, 0.45, 0.13, 1 }
local ACTIVE_EDGE = { 0.98, 0.78, 0.36, 1 }
-- Modes (formations, stances, filters) are outlined; actions are solid.
local MODE_FILL = { 0.075, 0.078, 0.088, 0.95 }
local MODE_EDGE = { 0.22, 0.22, 0.235, 1 }
local PRIMARY_FILL = { 0.21, 0.16, 0.065, 1 }
local PRIMARY_EDGE = { 0.72, 0.54, 0.20, 1 }
local DANGER_FILL = { 0.14, 0.105, 0.10, 1 }
local DANGER_EDGE = { 0.40, 0.19, 0.17, 1 }
local DISABLED_FILL = { 0.07, 0.072, 0.08, 0.9 }
local DISABLED_EDGE = { 0.15, 0.15, 0.16, 1 }

local function paint(button, fill, edge)
    button:SetBackdropColor(fill[1], fill[2], fill[3], fill[4])
    button:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
end

-- Picked (gold), disabled (grey), else the kind's own look.
function TB.PaintButton(button)
    if not button or not button.SetBackdropColor then return end
    if button.isTab then
        -- A tab: no box, a faint wash and a gold underline when open.
        local open = button.isActive or button.flatDisabled
        local a = C.COLOR.accent
        button:SetBackdropColor(a[1], a[2], a[3], open and 0.10 or 0)
        button:SetBackdropBorderColor(0, 0, 0, 0)
        if button.underline then if open then button.underline:Show() else button.underline:Hide() end end
        if button.sheen then button.sheen:SetVertexColor(1, 1, 1, 0) end
        if button.SetTextColor and not button.flatDisabled then
            if button.isActive then button:SetTextColor(1, 0.94, 0.80) else button:SetTextColor(0.62, 0.60, 0.56) end
        end
        return
    end
    if button.isActive then paint(button, ACTIVE_FILL, ACTIVE_EDGE)
    elseif button.flatDisabled then paint(button, DISABLED_FILL, DISABLED_EDGE)
    elseif button.flatKind == "mode" then paint(button, MODE_FILL, MODE_EDGE)
    elseif button.flatKind == "primary" then paint(button, PRIMARY_FILL, PRIMARY_EDGE)
    elseif button.flatKind == "danger" then paint(button, DANGER_FILL, DANGER_EDGE)
    else paint(button, BUTTON_FILL, BUTTON_EDGE) end
    -- On 1.12 a texture's SetAlpha replaces its vertex alpha, so the sheen
    -- strength is set here only, never through SetAlpha.
    if button.sheen then
        button.sheen:SetVertexColor(1, 1, 1, (button.flatDisabled and not button.isActive) and 0.02 or SHEEN_ALPHA)
    end
end

-- Label size follows the button: 12px on regular buttons, 10px on compact
-- ones (under 20px tall), the same size in every state so hover never
-- makes the text jump. The font-object setters are guarded: a client
-- without them keeps the template's font.
local function fontObject(name)
    return getglobal and getglobal(name) or nil
end
function TB.SetButtonFont(button)
    if not button then return end
    local small = button.smallLabel
        or (button.height or (button.GetHeight and button:GetHeight()) or 22) < 20
    local normal = fontObject(small and "GameFontHighlightSmall" or "GameFontHighlight")
    local disabled = fontObject(small and "GameFontDisableSmall" or "GameFontDisable")
    if normal then
        if button.SetTextFontObject then button:SetTextFontObject(normal) end
        if button.SetHighlightFontObject then button:SetHighlightFontObject(normal) end
    end
    if disabled and button.SetDisabledFontObject then button:SetDisabledFontObject(disabled) end
    if button.isTab then
        -- The open tab is the disabled one: it reads bright, the rest muted.
        if normal and button.SetDisabledFontObject then button:SetDisabledFontObject(normal) end
        if button.SetTextColor then button:SetTextColor(0.62, 0.60, 0.56) end
        if button.SetDisabledTextColor then button:SetDisabledTextColor(1, 0.94, 0.80) end
        if button.SetHighlightTextColor then button:SetHighlightTextColor(1, 1, 1) end
        return
    end
    if button.SetTextColor then button:SetTextColor(0.93, 0.91, 0.86) end
    if button.SetDisabledTextColor then button:SetDisabledTextColor(0.40, 0.40, 0.40) end
    if button.SetHighlightTextColor then button:SetHighlightTextColor(1, 1, 1) end
end

function TB.StyleButton(button, kind)
    if not button or not button.GetNormalTexture then return button end
    local c = C.COLOR
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local tex = button[get](button)
        if tex then tex:SetTexture(nil) end
    end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetTexture(0, 0, 0, 0.35) end
    local hl = button:GetHighlightTexture()
    if hl then
        hl:SetTexture(c.accent[1], c.accent[2], c.accent[3], 0.16)
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end
    button:SetBackdrop(FLAT_BACKDROP)
    button.flatKind = kind or button.flatKind or "action"
    if not button.sheen and button.CreateTexture then
        local sheen = button:CreateTexture(nil, "BACKGROUND")
        if not TB.SetMediaTexture(sheen, "gradient") then sheen:SetTexture(1, 1, 1, 0) end
        sheen:SetVertexColor(1, 1, 1, SHEEN_ALPHA)
        sheen:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        sheen:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.sheen = sheen
    end
    -- Enable/Disable repaint, so a disabled action greys out its frame too.
    local enable, disable = button.Enable, button.Disable
    button.Enable = function(self) enable(self); self.flatDisabled = false; TB.PaintButton(self) end
    button.Disable = function(self) disable(self); self.flatDisabled = true; TB.PaintButton(self) end
    -- The label size follows the height, which callers set after styling.
    local setHeight = button.SetHeight
    if setHeight then
        button.SetHeight = function(self, h) setHeight(self, h); TB.SetButtonFont(self); TB.PaintButton(self) end
    end
    TB.SetButtonFont(button)
    TB.PaintButton(button)
    return button
end

-- ── Action button feedback ──────────────────────────────────────────────────
-- A click on an action button shows a short "waiting" look, then a green
-- flash on the ACK or a red flash on ACTION_ERR. A missing answer clears
-- the waiting look after ACTION_TIMEOUT seconds. One small table drives
-- both sets of buttons: the Fight/Camp buttons by intent, the mini bar
-- icons by the same intent.
TB.actionFeedback = TB.actionFeedback or {}

-- Normalises a command tail to the button intent it came from. Strategy,
-- command, formation and roster verbs never start an "action" command, so
-- only action replies clear the state below.
function TB.ActionFeedbackKey(text)
    if not text then return nil end
    local rest = TB.Trim(string.gsub(text, "^%s*action%s+", ""))
    rest = TB.Trim(rest)
    if rest == "" then return nil end
    if TB.PartyToggleKey then
        -- Toggle switches answer under their key ("auto cc" -> "autocc",
        -- "aoe on" -> "aoe", "behavior party spread on" -> "spread").
        if TB.PartyToggleKey(rest) then return TB.PartyToggleKey(rest) end
        local bare = string.gsub(rest, "%s+(on|off|mixed)$", "")
        if bare ~= rest and TB.PartyToggleKey(bare) then return TB.PartyToggleKey(bare) end
        local _, _, last = string.find(bare, "(%S+)%s*$")
        if last and last ~= bare and TB.PartyToggleKey(last) then return TB.PartyToggleKey(last) end
        local verb = string.lower(string.gsub(rest, "%s+.*", ""))
        if verb ~= rest and TB.PartyToggleKey(verb) then return TB.PartyToggleKey(verb) end
    end
    -- Timed pulls send seconds after the intent ("pull 10").
    local verb = string.lower(string.gsub(rest, "%s+.*", ""))
    if verb == "pull" or verb == "pullback" then return verb end
    -- The release button sends "corpse run" once the party are ghosts.
    if verb == "corpse" then return "release" end
    return rest
end

function TB.NoteActionFeedback(intent, state)
    intent = TB.Trim(intent or "")
    if intent == "" then return end
    local now = (GetTime and GetTime()) or 0
    local timeout = (TB.C and TB.C.ACTION_TIMEOUT) or 8
    if state == "clear" then
        TB.actionFeedback[intent] = nil
    elseif state == "ok" or state == "error" then
        TB.actionFeedback[intent] = { state = state, untilAt = now + ((TB.C and TB.C.ACTION_FLASH) or 1.2) }
    else
        TB.actionFeedback[intent] = { state = "waiting", untilAt = now + timeout }
    end
    if TB.PaintActionFeedback then TB.PaintActionFeedback(intent) end
end

-- True while the waiting / flash look still applies; expired entries read
-- as cleared so a missed answer cannot stick a button.
function TB.ActionFeedbackState(intent)
    local entry = intent and TB.actionFeedback[intent] or nil
    if not entry then return nil end
    local now = (GetTime and GetTime()) or 0
    if (entry.untilAt or 0) <= now then
        TB.actionFeedback[intent] = nil
        return nil
    end
    return entry.state
end

-- Paints the waiting / answer state onto one Fight/Camp button.
function TB.SetButtonFeedback(button, state)
    if not button or not button.SetBackdropColor then return end
    button.feedbackState = state
    if state == "waiting" then
        button:SetBackdropColor(0.21, 0.16, 0.065, 1)
        button:SetBackdropBorderColor(0.72, 0.54, 0.20, 1)
    elseif state == "ok" then
        button:SetBackdropColor(0.07, 0.20, 0.10, 1)
        button:SetBackdropBorderColor(0.30, 0.90, 0.45, 1)
    elseif state == "error" then
        button:SetBackdropColor(0.22, 0.08, 0.07, 1)
        button:SetBackdropBorderColor(1.00, 0.34, 0.28, 1)
    else
        button.feedbackState = nil
        TB.PaintButton(button)
    end
end

-- A panel button as a tab: the window code keeps opening tabs with
-- Disable() (the open tab cannot be clicked again), so the disabled state
-- is drawn as "open": bright label and a gold underline, never grey.
function TB.StyleTab(button)
    if not button then return button end
    button.isTab = true
    button.smallLabel = true
    TB.StyleButton(button)
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then hl:SetTexture(1, 1, 1, 0.05) end
    if not button.underline and button.CreateTexture then
        local u = button:CreateTexture(nil, "OVERLAY")
        local a = C.COLOR.accentHi
        u:SetTexture(a[1], a[2], a[3], 1)
        u:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 4, 0)
        u:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 0)
        u:SetHeight(2)
        u:Hide()
        button.underline = u
    end
    TB.SetButtonFont(button)
    TB.PaintButton(button)
    return button
end

-- A flat button's picked look (a mode switch): filled gold, bright frame.
function TB.SetButtonActive(button, active)
    if not button or not button.SetBackdropColor then return end
    button.isActive = active and true or false
    TB.PaintButton(button)
    if button.actionIntent and button.feedbackState and TB.SetButtonFeedback then
        TB.SetButtonFeedback(button, button.feedbackState)
    end
end

-- The close button keeps UIPanelCloseButton's behaviour (hide the parent);
-- its red art becomes a small square with a drawn X that warms on hover.
function TB.StyleCloseButton(button, x, y, size)
    if not button then return button end
    size = size or 18
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = button[get] and button[get](button)
        if tex then tex:SetTexture(nil) end
    end
    button:SetWidth(size); button:SetHeight(size)
    if x or y then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", button:GetParent(), "TOPRIGHT", x or -6, y or -6)
    end
    if button.SetBackdrop then
        button:SetBackdrop(FLAT_BACKDROP)
        button:SetBackdropColor(0.11, 0.115, 0.13, 1)
        button:SetBackdropBorderColor(0.25, 0.25, 0.27, 1)
    end
    local glyph = button:CreateTexture(nil, "ARTWORK")
    glyph:SetWidth(size - 2); glyph:SetHeight(size - 2)
    -- Without the Media file, the stock close art (it ships with 1.12).
    if TB.SetMediaTexture(glyph, "close", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up") then
        glyph:SetVertexColor(0.78, 0.76, 0.72, 1)
    else
        glyph:SetWidth(size + 6); glyph:SetHeight(size + 6)
    end
    glyph:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.glyph = glyph
    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then
        hl:SetTexture(0.85, 0.25, 0.18, 0.45)
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end
    return button
end

-- InputBoxTemplate's three-piece art becomes one flat well with an inner
-- text margin. With a placeholder, a muted hint shows while it is empty.
function TB.StyleEditBox(box, placeholder)
    if not box then return box end
    local name = box.GetName and box:GetName()
    if name and getglobal then
        for _, part in ipairs({ "Left", "Middle", "Right", "Mid" }) do
            local tex = getglobal(name .. part)
            if tex and tex.Hide then tex:Hide() end
        end
    end
    if box.GetRegions then
        local regions = { box:GetRegions() }
        for _, r in ipairs(regions) do
            if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.Hide then r:Hide() end
        end
    end
    if box.SetBackdrop then
        TB.ApplySurface(box, "input")
    end
    if box.SetTextInsets then box:SetTextInsets(placeholder and 18 or 6, 6, 0, 0) end
    if box.SetTextColor then box:SetTextColor(0.93, 0.91, 0.86) end
    if placeholder and box.CreateFontString then
        local icon = box:CreateTexture(nil, "ARTWORK")
        if not TB.SetMediaTexture(icon, "search") then icon:Hide() end
        icon:SetWidth(12); icon:SetHeight(12)
        icon:SetPoint("LEFT", box, "LEFT", 4, 0)
        icon:SetVertexColor(0.55, 0.54, 0.52, 1)
        local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("LEFT", box, "LEFT", 19, 0)
        hint:SetText(placeholder)
        hint:SetJustifyH("LEFT")
        box.placeholder = hint
        local function update()
            local text = box.GetText and box:GetText() or ""
            if text == nil or text == "" then hint:Show() else hint:Hide() end
        end
        box.UpdatePlaceholder = update
        -- The hint follows the text whichever OnTextChanged the window sets,
        -- before or after this call: wrap the current one and any later one.
        if box.SetScript then
            local setScript = box.SetScript
            local function wrapped(fn)
                return function()
                    update()
                    if fn then fn() end
                end
            end
            local changed = box.GetScript and box:GetScript("OnTextChanged") or nil
            setScript(box, "OnTextChanged", wrapped(changed))
            box.SetScript = function(self, name, fn)
                if name == "OnTextChanged" then return setScript(self, name, wrapped(fn)) end
                return setScript(self, name, fn)
            end
        end
        update()
    end
    return box
end

-- UICheckButtonTemplate's yellow box becomes a 14px flat square with a
-- drawn gold check, centred in the template's hit area.
function TB.StyleCheckButton(check)
    if not check then return check end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = check[get] and check[get](check)
        if tex then tex:SetTexture(nil) end
    end
    local edge = check:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture(0.30, 0.30, 0.32, 1)
    edge:SetWidth(14); edge:SetHeight(14)
    edge:SetPoint("CENTER", check, "CENTER", 0, 0)
    local well = check:CreateTexture(nil, "BORDER")
    well:SetTexture(0.04, 0.042, 0.05, 1)
    well:SetWidth(12); well:SetHeight(12)
    well:SetPoint("CENTER", check, "CENTER", 0, 0)
    check.box, check.well = edge, well
    local mark = check.GetCheckedTexture and check:GetCheckedTexture()
    if mark then
        TB.SetMediaTexture(mark, "check", "Interface\\Buttons\\UI-CheckBox-Check")
        mark:SetVertexColor(C.COLOR.accentHi[1], C.COLOR.accentHi[2], C.COLOR.accentHi[3], 1)
        mark:ClearAllPoints()
        mark:SetWidth(16); mark:SetHeight(16)
        mark:SetPoint("CENTER", check, "CENTER", 0, 0)
    end
    local hl = check.GetHighlightTexture and check:GetHighlightTexture()
    if hl then
        hl:SetTexture(C.COLOR.accent[1], C.COLOR.accent[2], C.COLOR.accent[3], 0.35)
        hl:ClearAllPoints()
        hl:SetWidth(12); hl:SetHeight(12)
        hl:SetPoint("CENTER", check, "CENTER", 0, 0)
    end
    return check
end

function TB.StatusColor(st)
    local c = C.COLOR
    if not st then return c.muted end
    if st.status == C.STATUS.FAILED then return c.red end
    if st.status == C.STATUS.UNKNOWN then return c.red end
    if st.status == C.STATUS.ONLINE then return c.green end
    if st.status == C.STATUS.QUEUED or st.status == C.STATUS.COMMANDING
        or st.status == C.STATUS.STARTING or st.status == C.STATUS.SUMMONING
        or st.status == C.STATUS.INVITING or st.status == C.STATUS.KICKING
        or st.status == C.STATUS.REMOVING then
        return c.yellow
    end
    return c.muted
end

function TB.StatusText(st, inGroup)
    local S = C.STATUS
    if not st then return "Offline" end
    if st.operation and st.operation.verb == "status" then return "Checking…" end
    if st.status == S.FAILED then return "Failed" end
    if st.status == S.UNKNOWN then return "Unknown" end
    if st.status == S.QUEUED then return "Queued" end
    if st.status == S.SUMMONING then return "Summoning…" end
    if st.status == S.INVITING then return "Inviting…" end
    if st.status == S.KICKING then return "Kicking…" end
    if st.status == S.REMOVING then return "Removing…" end
    if st.status == S.COMMANDING then return "Working…" end
    if not st or not st.online then
        if st and st.status == S.STARTING  then return "Starting" end
        if st and st.status == S.OFFLINE_PENDING then return "Checking…" end
        return "Offline"
    end
    if st.enteredWorld == false then return "Starting" end
    if st.altBot then return "Alt-bot · Playing alone" end
    if st.movement and st.movement ~= "" and st.movement ~= "custom" then
        local movement = string.gsub(st.movement, "^%l", string.upper)
        if inGroup then return "Online · Group · " .. movement end
        return "Online · " .. movement
    end
    if inGroup then return "Online · Group" end
    return "Online"
end

function TB.GetClassColor(classId)
    local colors = (C and C.CLASS_COLORS) or {}
    if classId and colors[classId] then
        return colors[classId]
    end
    return { 0.92, 0.90, 0.84, hex = "ffebe6d6" }
end

-- Point a texture at a class's icon; false when the class has none.
function TB.SetClassIcon(tex, classId)
    local coords = C.CLASS_ICON_TCOORDS and C.CLASS_ICON_TCOORDS[classId]
    if not tex or not coords then
        if tex then tex:Hide() end
        return false
    end
    tex:SetTexture(C.CLASS_ICON_FILE)
    -- Trim the art's soft rim so the square icon has crisp edges.
    local w, h = coords[2] - coords[1], coords[4] - coords[3]
    tex:SetTexCoord(coords[1] + w * 0.06, coords[2] - w * 0.06, coords[3] + h * 0.06, coords[4] - h * 0.06)
    tex:Show()
    return true
end

function TB.StatusBadge(st, inGroup)
    local S = C.STATUS
    if not st then return "|cff757575○ Offline|r" end
    if st.operation and st.operation.verb == "status" then return "|cffffb300● Checking…|r" end
    if st.status == S.FAILED then return "|cffff5555● Failed|r" end
    if st.status == S.UNKNOWN then return "|cffff5555● Unknown|r" end
    if st.status == S.QUEUED then return "|cffffb300● Queued|r" end
    if st.status == S.SUMMONING then return "|cffffb300● Summoning…|r" end
    if st.status == S.INVITING then return "|cffffb300● Inviting…|r" end
    if st.status == S.KICKING then return "|cffffb300● Kicking…|r" end
    if st.status == S.REMOVING then return "|cffffb300● Removing…|r" end
    if st.status == S.COMMANDING then return "|cffffb300● Working…|r" end
    if not st.online then
        if st.status == S.STARTING then return "|cffffb300● Starting|r" end
        if st.status == S.OFFLINE_PENDING then return "|cffffb300● Checking…|r" end
        return "|cff757575○ Offline|r"
    end
    if st.enteredWorld == false then return "|cffffb300● Starting|r" end
    if st.altBot then return "|cffb388ff● Alt-bot|r · Playing alone" end
    if inGroup then
        if st.movement and st.movement ~= "" and st.movement ~= "custom" then
            local mv = string.gsub(st.movement, "^%l", string.upper)
            return "|cff42a5f5● Group|r · " .. mv
        end
        return "|cff42a5f5● Group|r"
    end
    if st.movement and st.movement ~= "" and st.movement ~= "custom" then
        local mv = string.gsub(st.movement, "^%l", string.upper)
        return "|cff4ecb5a● Online|r · " .. mv
    end
    return "|cff4ecb5a● Online|r"
end

-- table
function TB.CountKeys(t)
    local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n
end

-- ── Unified Role Policy ─────────────────────────────────────────────────────
TB.Roles = {}

TB.Roles.CLASS_ROLES = {
    [1] = { -- Warrior
        { id = "tank", label = "Protection", strat = "+protection,-arms,-fury" },
        { id = "dps", label = "Arms", strat = "+arms,-protection,-fury" },
        { id = "fury", label = "Fury", strat = "+fury,-protection,-arms" },
    },
    [2] = { -- Paladin
        { id = "tank", label = "Protection", strat = "+protection,-holy,-retribution" },
        { id = "heal", label = "Holy", strat = "+holy,-protection,-retribution" },
        { id = "dps", label = "Retribution", strat = "+retribution,-protection,-holy" },
    },
    [3] = { -- Hunter
        { id = "bm", label = "Beastmaster", strat = "+beast mastery,-marksmanship,-survival" },
        { id = "mm", label = "Marksman", strat = "+marksmanship,-beast mastery,-survival" },
        { id = "survival", label = "Survival", strat = "+survival,-beast mastery,-marksmanship" },
    },
    [4] = { -- Rogue
        { id = "combat", label = "Combat", strat = "+combat,-assassination,-subtlety" },
        { id = "assa", label = "Assassination", strat = "+assassination,-combat,-subtlety" },
        { id = "subtlety", label = "Subtlety", strat = "+subtlety,-combat,-assassination" },
    },
    [5] = { -- Priest
        { id = "heal", label = "Holy", strat = "+holy,-discipline,-shadow" },
        { id = "disc", label = "Discipline", strat = "+discipline,-holy,-shadow" },
        { id = "dps", label = "Shadow", strat = "+shadow,-holy,-discipline,-offdps" },
    },
    [7] = { -- Shaman
        { id = "heal", label = "Restoration", strat = "+restoration,-elemental,-enhancement" },
        { id = "ele", label = "Elemental", strat = "+elemental,-restoration,-enhancement" },
        { id = "enh", label = "Enhancement", strat = "+enhancement,-restoration,-elemental" },
        { id = "tank", label = "Enh Tank", strat = "+tank shaman,-restoration,-elemental,-enhancement" },
    },
    [8] = { -- Mage
        { id = "frost", label = "Frost", strat = "+frost,-fire,-arcane" },
        { id = "fire", label = "Fire", strat = "+fire,-frost,-arcane" },
        { id = "arcane", label = "Arcane", strat = "+arcane,-frost,-fire" },
    },
    [9] = { -- Warlock
        { id = "affliction", label = "Affliction", strat = "+affliction,-demonology,-destruction" },
        { id = "demonology", label = "Demonology", strat = "+demonology,-affliction,-destruction" },
        { id = "destruction", label = "Destruction", strat = "+destruction,-affliction,-demonology" },
    },
    [11] = { -- Druid
        { id = "tank", label = "Feral Bear", strat = "+tank feral,-dps feral,-restoration,-balance" },
        { id = "cat", label = "Feral Cat", strat = "+dps feral,-tank feral,-restoration,-balance" },
        { id = "heal", label = "Restoration", strat = "+restoration,-tank feral,-dps feral,-balance" },
        { id = "boomkin", label = "Balance", strat = "+balance,-tank feral,-dps feral,-restoration" },
    },
}

TB.C = TB.C or {}
TB.C.CLASS_ROLES = TB.Roles.CLASS_ROLES

function TB.Roles.GetClassRoles(classId)
    if type(classId) == "string" and TB.C and TB.C.CLASS_NAME_TO_ID then
        classId = TB.C.CLASS_NAME_TO_ID[classId] or classId
    end
    return (TB.Roles.CLASS_ROLES and TB.Roles.CLASS_ROLES[classId]) or {}
end

function TB.Roles.FindRole(classId, roleId)
    if not roleId and type(classId) == "string" then
        roleId = classId
        classId = nil
    end
    if not roleId then return nil end
    local lowerRole = type(roleId) == "string" and string.lower(roleId) or nil
    if classId then
        local roles = TB.Roles.GetClassRoles(classId)
        for _, r in ipairs(roles) do
            if r.id == roleId or (lowerRole and r.label and string.lower(r.label) == lowerRole) then
                return r
            end
        end
        return nil
    end
    if TB.Roles.CLASS_ROLES then
        for _, roles in pairs(TB.Roles.CLASS_ROLES) do
            for _, r in ipairs(roles) do
                if r.id == roleId or (lowerRole and r.label and string.lower(r.label) == lowerRole) then
                    return r
                end
            end
        end
    end
    return nil
end

-- The role whose strategies match the bot's live specs (BOTSTATE specs=):
-- every "+" strategy present and no "-" one; failing that, the first role
-- none of whose "-" strategies is present (a fury warrior is DPS).
local function roleFromSpecs(roles, specs)
    local have = {}
    for spec in string.gfind(specs, "[^+]+") do have[spec] = true end
    for pass = 1, 2 do
        for _, role in ipairs(roles) do
            local matches = true
            for sign, strat in string.gfind(role.strat or "", "([+-])([^,]+)") do
                if (sign == "-" or pass == 1) and (sign == "+") ~= (have[strat] == true) then
                    matches = false
                    break
                end
            end
            if matches then return role.id end
        end
    end
    return nil
end

function TB.Roles.GetBotRole(botName, classId)
    local roles = TB.Roles.GetClassRoles(classId)
    local state = TB.GetBotState and TB.GetBotState(botName)
    local currentId = state and state.specs and roleFromSpecs(roles, state.specs)
    if not currentId then
        local dbRoles = (TortoiseBotsDB and TortoiseBotsDB.botRoles) or {}
        currentId = dbRoles[botName]
    end
    if not currentId and roles[1] then
        currentId = roles[1].id
    end
    return currentId, TB.Roles.FindRole(classId, currentId)
end

-- The player's spec is theirs; bots only need to know which role they fill.
TB.Roles.PLAYER_ROLES = {
    { id = "tank", label = "Tank" },
    { id = "heal", label = "Healer" },
    { id = "dps", label = "DPS" },
}

local function findPlayerRole(roleId)
    for _, r in ipairs(TB.Roles.PLAYER_ROLES) do
        if r.id == roleId then return r end
    end
    return nil
end

function TB.Roles.GetPlayerRole()
    local roleId = TortoiseBotsDB and TortoiseBotsDB.playerRole
    -- Older saves stored a class spec id (e.g. "boomkin").
    if roleId and not findPlayerRole(roleId) then
        roleId = TB.Roles.GetPlayerRoleToken(roleId) == "healer" and "heal" or TB.Roles.GetPlayerRoleToken(roleId)
    end
    return roleId, findPlayerRole(roleId)
end

function TB.Roles.GetRoleLabel(classId, roleId, fallback)
    if not roleId and type(classId) == "string" then
        roleId = classId
        classId = nil
    end
    local role = TB.Roles.FindRole(classId, roleId)
    if role then return role.label end
    return fallback or roleId or "Default"
end

-- Display-only short tokens for narrow role buttons (Party/Guild rows).
-- Full labels stay in Constants and tooltips; only overlong labels map.
local SHORT_ROLE_LABELS = {
    ["Assassination"] = "Assassin",
    ["Beastmaster"] = "BM",
    ["Destruction"] = "Destro",
    ["Protection"] = "Prot",
    ["Retribution"] = "Ret",
    ["Restoration"] = "Resto",
    ["Discipline"] = "Disc",
    ["Elemental"] = "Ele",
    ["Enhancement"] = "Enh",
    ["Feral Bear"] = "Bear",
    ["Feral Cat"] = "Cat",
}
function TB.Roles.ShortLabel(label)
    return SHORT_ROLE_LABELS[label] or label
end

function TB.Roles.GetPlayerRoleToken(roleId)
    if roleId == "tank" then return "tank" end
    if roleId == "heal" then return "healer" end
    return "dps"
end

function TB.Roles.SetPlayerRole(role)
    local roleDef = type(role) == "table" and role or findPlayerRole(role)
    if not roleDef then return false end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.playerRole = roleDef.id
    local token = TB.Roles.GetPlayerRoleToken(roleDef.id)
    TB.SendBotCommand("role self " .. token)
    if TB.Print then TB.Print("Your role set to " .. roleDef.label) end
    return true
end

function TB.Roles.SetBotRole(botName, role, classId)
    local roleDef = type(role) == "table" and role or TB.Roles.FindRole(classId, role)
    if not roleDef or not botName then return false end
    TortoiseBotsDB = TortoiseBotsDB or {}
    TortoiseBotsDB.botRoles = TortoiseBotsDB.botRoles or {}
    local state = TB.GetBotState and TB.GetBotState(botName)
    local previousRole = (state and state.specs and roleFromSpecs(TB.Roles.GetClassRoles(classId), state.specs))
        or TortoiseBotsDB.botRoles[botName]
    TortoiseBotsDB.botRoles[botName] = roleDef.id
    -- Show the pick until the next roster snapshot reports the new specs.
    if state then state.specs = nil end

    if roleDef.id == "tank" then
        TB.SendBotCommand("role " .. botName .. " tank")
    else
        if previousRole == "tank" then
            TB.SendBotCommand("role " .. botName .. " clear")
        end
        if roleDef.strat and roleDef.strat ~= "" then
            TB.SendBotCommand("strategy " .. roleDef.strat .. " " .. botName)
        end
    end
    if TB.Print then TB.Print(botName .. " role set to " .. roleDef.label) end
    return true
end

function TB.Roles.CycleBotRole(botName, classId)
    local roles = TB.Roles.GetClassRoles(classId)
    local roleCount = table.getn(roles)
    if roleCount == 0 then return nil end
    local currentId = (TortoiseBotsDB and TortoiseBotsDB.botRoles and TortoiseBotsDB.botRoles[botName])
    local nextIndex = 1
    for idx, r in ipairs(roles) do
        if r.id == currentId then
            nextIndex = math.mod(idx, roleCount) + 1
            break
        end
    end
    local newRole = roles[nextIndex]
    TB.Roles.SetBotRole(botName, newRole, classId)
    return newRole
end

