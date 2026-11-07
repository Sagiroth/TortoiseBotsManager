-- tools/preview/mock.lua
-- A recording mock of the Vanilla 1.12 widget API, rich enough to draw.
-- Every widget keeps what the real client would use to paint it: size,
-- anchors, backdrop, textures, font objects, text colour and visibility.
-- tools/preview/scenes.lua loads the addon on top of this and dumps each
-- window to JSON; tools/preview/render.js turns that JSON into PNGs.

if not table.getn then table.getn = function(t) return t and #t or 0 end end
if not unpack then unpack = table.unpack end
if not math.mod then math.mod = math.fmod end
if not string.gfind then string.gfind = string.gmatch end

Mock = { objects = {}, nextId = 0, frames = {}, now = 100 }

local objects = Mock.objects

local function register(o)
    Mock.nextId = Mock.nextId + 1
    o.id = Mock.nextId
    table.insert(objects, o)
    return o
end

local W = {}
W.__index = W

local function new(kind, parent, extra)
    local o = setmetatable({
        kind = kind, parent = parent, scripts = {}, shown = true,
        points = {}, enabled = true, checked = false, alpha = 1,
    }, W)
    if extra then for k, v in pairs(extra) do o[k] = v end end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, o)
    end
    return register(o)
end
Mock.new = new

-- Only methods the 1.12 client has: a call to a newer one (SetSize,
-- HookScript, SetFormattedText ...) fails here as it does in game.

-- geometry ---------------------------------------------------------------
function W:SetWidth(v) self.width = v end
function W:SetHeight(v) self.height = v end
function W:GetWidth() return self.width or 0 end
function W:GetHeight() return self.height or 0 end
function W:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
    if type(rel) == "string" then rel = Mock.frames[rel] end
    -- 1.12: a second SetPoint with the same anchor point replaces it.
    for i, p in ipairs(self.points) do
        if p.point == point then table.remove(self.points, i) break end
    end
    table.insert(self.points, { point = point, rel = rel or self.parent,
        relPoint = relPoint or point, x = x or 0, y = y or 0 })
end
function W:ClearAllPoints() self.points = {} end
function W:SetAllPoints(other)
    other = other or self.parent
    self.points = {}
    self:SetPoint("TOPLEFT", other, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", other, "BOTTOMRIGHT", 0, 0)
end
function W:GetNumPoints() return table.getn(self.points) end
function W:GetPoint(i)
    local p = self.points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
end
function W:GetLeft() return 100 end
function W:GetRight() return 100 + (self.width or 0) end
function W:GetTop() return 700 end
function W:GetBottom() return 700 - (self.height or 0) end
function W:GetCenter() return 400, 400 end
function W:GetEffectiveScale() return self.scale or 1 end
function W:GetScale() return self.scale or 1 end
function W:SetScale(s) self.scale = s end

-- frame state ------------------------------------------------------------
function W:Show() self.shown = true end
function W:Hide() self.shown = false end
function W:IsShown() return self.shown end
function W:IsVisible()
    local o = self
    while o do
        if not o.shown then return false end
        o = o.parent
    end
    return true
end
function W:SetAlpha(a) self.alpha = a end
function W:GetAlpha() return self.alpha end
function W:GetParent() return self.parent end
function W:SetParent(p) self.parent = p end
function W:GetName() return self.name end
function W:SetFrameStrata(s) self.strata = s end
function W:GetFrameStrata() return self.strata or "MEDIUM" end
function W:SetFrameLevel(l) self.level = l end
function W:GetFrameLevel()
    if self.level then return self.level end
    local n, o = 0, self.parent
    while o do n = n + 1; o = o.parent end
    return n
end
function W:SetToplevel() end
function W:SetMovable(v) self.movable = v end
function W:SetResizable() end
function W:SetClampedToScreen() end
function W:EnableMouse(v) self.mouse = v end
function W:EnableMouseWheel() end
function W:EnableKeyboard() end
function W:RegisterForDrag() end
function W:RegisterEvent(e)
    self.events = self.events or {}
    self.events[e] = true
end
function W:UnregisterEvent() end
function W:RegisterAllEvents() end
function W:RegisterForClicks() end
function W:StartMoving() end
function W:StopMovingOrSizing() end
function W:SetScript(name, fn) self.scripts[name] = fn end
function W:GetScript(name) return self.scripts[name] end
function W:SetID(i) self.wid = i end
function W:GetID() return self.wid or 0 end
function W:IsMouseOver() return false end
function W:SetHitRectInsets() end

-- backdrop ---------------------------------------------------------------
function W:SetBackdrop(b)
    self.backdrop = b
    if b then self.bdColor = self.bdColor or { 1, 1, 1, 1 }; self.bdBorder = self.bdBorder or { 1, 1, 1, 1 } end
end
function W:GetBackdrop() return self.backdrop end
function W:SetBackdropColor(r, g, b, a) self.bdColor = { r, g, b, a or 1 } end
function W:SetBackdropBorderColor(r, g, b, a) self.bdBorder = { r, g, b, a or 1 } end
function W:GetBackdropColor() local c = self.bdColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function W:GetBackdropBorderColor() local c = self.bdBorder or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end

-- regions ----------------------------------------------------------------
function W:CreateTexture(name, layer)
    local t = new("Texture", self, { name = name, layer = layer or "ARTWORK" })
    if name then Mock.frames[name] = t end
    return t
end
function W:CreateFontString(name, layer, template)
    local f = new("FontString", self, { name = name, layer = layer or "ARTWORK",
        font = template, text = "", justifyH = "CENTER", justifyV = "MIDDLE" })
    if name then Mock.frames[name] = f end
    return f
end
function W:GetRegions()
    local out = {}
    for _, c in ipairs(self.children or {}) do
        if c.kind == "Texture" or c.kind == "FontString" then table.insert(out, c) end
    end
    return unpack(out)
end
function W:GetObjectType() return self.kind end
function W:GetChildren() return end

-- textures ---------------------------------------------------------------
function W:SetTexture(a, g, b, al)
    if type(a) == "number" then
        self.file = nil; self.color = { a, g, b, al or 1 }
    else
        self.file = a; self.color = nil
    end
    return 1
end
function W:GetTexture() return self.file end
function W:SetTexCoord(...)
    local n = table.getn(arg)
    if n == 4 then self.texCoord = { arg[1], arg[2], arg[3], arg[4] }
    elseif n == 8 then self.texCoord = { arg[1], arg[5], arg[2], arg[4] } end
end
function W:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function W:SetBlendMode(m) self.blend = m end
function W:SetDesaturated(v) self.desat = v end
function W:SetDrawLayer(l) self.layer = l end
function W:SetGradient() end
function W:SetGradientAlpha() end

-- font strings -----------------------------------------------------------
function W:SetText(t)
    if self.kind == "Button" or self.kind == "CheckButton" then
        local fs = self:GetFontString()
        fs.text = t and tostring(t) or ""
        return
    end
    self.text = t and tostring(t) or ""
end
function W:GetText()
    if self.kind == "Button" or self.kind == "CheckButton" then
        return self.fontString and self.fontString.text or ""
    end
    return self.text
end
function W:SetTextColor(r, g, b, a)
    if self.kind == "Button" then self:GetFontString().textColor = { r, g, b, a or 1 } return end
    self.textColor = { r, g, b, a or 1 }
end
function W:GetTextColor() local c = self.textColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function W:SetJustifyH(j) self.justifyH = j end
function W:SetJustifyV(j) self.justifyV = j end
function W:SetFont(path, size, flags) self.fontFile = path; self.fontSize = size; self.fontFlags = flags end
function W:GetFont() return self.fontFile or "Fonts\\FRIZQT__.TTF", self.fontSize or 12 end
function W:SetFontObject(o) self.font = type(o) == "string" and o or (o and o.name) end
function W:SetTextFontObject(o) self.normalFont = type(o) == "string" and o or (o and o.name); self:GetFontString().font = self.normalFont end
function W:SetShadowColor() end
function W:SetShadowOffset() end
function W:SetNonSpaceWrap() end
function W:SetSpacing() end
function W:GetStringWidth()
    local s = string.gsub(self.text or "", "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    return string.len(s) * 6
end
function W:GetStringHeight() return 12 end

-- buttons ----------------------------------------------------------------
function W:GetFontString()
    if not self.fontString then
        self.fontString = new("FontString", self, { layer = "OVERLAY",
            font = self.normalFont or "GameFontNormal", text = "", justifyH = "CENTER", justifyV = "MIDDLE",
            isButtonText = true })
        self.fontString:SetPoint("CENTER", self, "CENTER", 0, 0)
    end
    return self.fontString
end
function W:SetFontString(fs) self.fontString = fs end
local function stateTexture(self, key, layer)
    if not self[key] then
        self[key] = new("Texture", self, { layer = layer or "ARTWORK", stateKey = key })
        self[key]:SetAllPoints(self)
    end
    return self[key]
end
local function setStateTexture(key, layer)
    return function(self, file)
        if type(file) == "table" then self[key] = file; file.stateKey = key; return end
        local t = stateTexture(self, key, layer)
        t:SetTexture(file)
    end
end
W.SetNormalTexture = setStateTexture("normalTex", "ARTWORK")
W.SetPushedTexture = setStateTexture("pushedTex", "ARTWORK")
W.SetDisabledTexture = setStateTexture("disabledTex", "ARTWORK")
W.SetHighlightTexture = setStateTexture("highlightTex", "HIGHLIGHT")
W.SetCheckedTexture = setStateTexture("checkedTex", "OVERLAY")
W.SetDisabledCheckedTexture = setStateTexture("disabledCheckedTex", "OVERLAY")
function W:GetNormalTexture() return self.normalTex end
function W:GetPushedTexture() return self.pushedTex end
function W:GetDisabledTexture() return self.disabledTex end
function W:GetHighlightTexture() return self.highlightTex end
function W:GetCheckedTexture() return self.checkedTex end
function W:SetDisabledTextColor(r, g, b) self.disabledTextColor = { r, g, b, 1 } end
function W:SetHighlightTextColor(r, g, b) self.highlightTextColor = { r, g, b, 1 } end
function W:SetDisabledFontObject(o) self.disabledFont = type(o) == "string" and o or (o and o.name) end
function W:SetHighlightFontObject() end
function W:SetNormalFontObject() end
function W:Enable() self.enabled = true end
function W:Disable() self.enabled = false end
function W:IsEnabled() return self.enabled and 1 or nil end
function W:SetButtonState(s) self.buttonState = s end
function W:LockHighlight() self.lockHighlight = true end
function W:UnlockHighlight() self.lockHighlight = false end
function W:Click() if self.scripts.OnClick then this = self; self.scripts.OnClick(self) end end
function W:SetChecked(v) self.checked = v and true or false end
function W:GetChecked() return self.checked and 1 or nil end

-- edit boxes -------------------------------------------------------------
function W:SetAutoFocus() end
function W:SetFocus() end
function W:ClearFocus() end
function W:SetMaxLetters() end
function W:SetNumeric() end
function W:SetMultiLine() end
function W:HighlightText() end
function W:SetTextInsets() end
function W:GetNumber() return tonumber(self.text) or 0 end
function W:SetNumber(n) self.text = tostring(n) end
function W:Insert(t) self.text = (self.text or "") .. t end

-- scroll / model / tooltip / misc ---------------------------------------
function W:SetScrollChild(c) self.scrollChild = c end
function W:SetVerticalScroll() end
function W:GetVerticalScroll() return 0 end
function W:UpdateScrollChildRect() end
function W:SetUnit(u) self.unit = u end
function W:SetModelScale() end
function W:SetPosition() end
function W:SetFacing() end
function W:SetCamera() end
function W:RefreshUnit() end
function W:ClearModel() end
function W:SetMinMaxValues(a, b) self.min = a; self.max = b end
function W:SetValue(v) self.value = v end
function W:GetValue() return self.value or 0 end
function W:SetStatusBarTexture(f) self.barFile = f end
function W:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a or 1 } end
function W:SetOrientation() end
function W:SetValueStep() end
function W:SetOwner(o) self.owner = o end
function W:IsOwned(o) return self.owner == o end
function W:AddLine() end
function W:AddDoubleLine() end
function W:SetHyperlink() end
function W:ClearLines() end
function W:NumLines() return 0 end
function W:AddMessage() end

-- templates --------------------------------------------------------------
local function tex(parent, layer, file, coords, points)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(file)
    if coords then t.texCoord = coords end
    for _, p in ipairs(points or {}) do t:SetPoint(p[1], p[2] or parent, p[3], p[4], p[5]) end
    return t
end

local TEMPLATES = {}
TEMPLATES.UIPanelButtonTemplate = function(b)
    b.normalFont = "GameFontNormal"
    b:SetWidth(40); b:SetHeight(22)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b.normalTex.texCoord = { 0, 0.625, 0, 0.6875 }
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    b.pushedTex.texCoord = { 0, 0.625, 0, 0.6875 }
    b:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
    b.disabledTex.texCoord = { 0, 0.625, 0, 0.6875 }
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b.highlightTex.texCoord = { 0, 0.625, 0, 0.6875 }
    b.highlightTex.blend = "ADD"
    b.disabledTextColor = { 0.5, 0.5, 0.5, 1 }
end
TEMPLATES.UIPanelCloseButton = function(b)
    b:SetWidth(32); b:SetHeight(32)
    b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    b.highlightTex.blend = "ADD"
end
TEMPLATES.UICheckButtonTemplate = function(b)
    b:SetWidth(32); b:SetHeight(32)
    b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    b.highlightTex.blend = "ADD"
    b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
end
TEMPLATES.OptionsCheckButtonTemplate = TEMPLATES.UICheckButtonTemplate
TEMPLATES.InputBoxTemplate = function(e)
    e.font = "ChatFontNormal"
    e.text = ""
    e.isInput = true
    local file = "Interface\\Common\\Common-Input-Border"
    local left = tex(e, "BACKGROUND", file, { 0, 0.0625, 0, 0.625 }, { { "LEFT", e, "LEFT", -5, 0 } })
    left.width = 8; left.height = 20
    local right = tex(e, "BACKGROUND", file, { 0.9375, 1, 0, 0.625 }, { { "RIGHT", e, "RIGHT", 0, 0 } })
    right.width = 8; right.height = 20
    local mid = tex(e, "BACKGROUND", file, { 0.0625, 0.9375, 0, 0.625 },
        { { "LEFT", e, "LEFT", 3, 0 }, { "RIGHT", e, "RIGHT", -8, 0 } })
    mid.height = 20
    if e.name then _G[e.name .. "Left"] = left; _G[e.name .. "Right"] = right; _G[e.name .. "Middle"] = mid end
end
TEMPLATES.FauxScrollFrameTemplate = function(s)
    local bar = new("Slider", s, { name = s.name and (s.name .. "ScrollBar"), isScrollBar = true })
    bar.width = 16
    bar:SetPoint("TOPLEFT", s, "TOPRIGHT", 6, -16)
    bar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 6, 16)
    if bar.name then Mock.frames[bar.name] = bar end
    s.scrollBar = bar
    local up = new("Button", bar, {})
    up.width, up.height = 16, 16
    up:SetPoint("BOTTOM", bar, "TOP", 0, 0)
    up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    up.normalTex.texCoord = { 0.2, 0.8, 0.25, 0.75 }
    local down = new("Button", bar, {})
    down.width, down.height = 16, 16
    down:SetPoint("TOP", bar, "BOTTOM", 0, 0)
    down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    down.normalTex.texCoord = { 0.2, 0.8, 0.25, 0.75 }
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    thumb.texCoord = { 0.2, 0.8, 0.125, 0.875 }
    thumb.width, thumb.height = 16, 24
    thumb:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.shown = false
end
TEMPLATES.GameTooltipTemplate = function(t) t.shown = false; t.isTooltip = true end

function CreateFrame(kind, name, parent, template)
    local o = new(kind, parent, { name = name, template = template })
    if name then Mock.frames[name] = o; _G[name] = o end
    if template then
        for t in string.gfind(template, "[^, ]+") do
            if TEMPLATES[t] then TEMPLATES[t](o) end
        end
    end
    if kind == "Button" and not template then o.normalFont = nil end
    return o
end

function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end

-- font objects the addon passes around by name.
for _, n in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall", "GameFontGreen", "GameFontRed",
    "GameFontWhite", "NumberFontNormal", "NumberFontNormalSmall", "ChatFontNormal", "GameFontNormalHuge",
    "GameFontHighlightLarge", "GameFontHighlightSmallOutline", "NumberFontNormalLarge", "GameTooltipText" }) do
    _G[n] = { name = n, GetFont = function() return "Fonts\\FRIZQT__.TTF", 12 end }
end

-- ── world state the scenes can steer ─────────────────────────────────────
Mock.world = {
    target = nil,          -- { name=, player=bool, dead=bool, class= }
    party = {},            -- { { name=, class="Priest", level=60 } }
    raid = 0,
    dead = {}, ghost = {},
}

UIParent = new("Frame", nil, { name = "UIParent", width = 1280, height = 800 })
UIParent.points = {}
Mock.frames.UIParent = UIParent
WorldFrame = UIParent
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap.width, Minimap.height = 140, 140
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
ItemRefTooltip = GameTooltip
DropDownList1 = CreateFrame("Frame", "DropDownList1", UIParent)
DropDownList1.shown = false
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
ChatFrame1 = DEFAULT_CHAT_FRAME
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_OnEvent() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_CreateInfo() return {} end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end
function PlaySound() end
function GetTime() return Mock.now end
function time() return 1700000000 end
function date(f) return "12:34" end
function GetCursorPosition() return 640, 400 end
function GetScreenWidth() return 1280 end
function GetScreenHeight() return 900 end
function IsShiftKeyDown() return nil end
function IsControlKeyDown() return nil end
function IsAltKeyDown() return nil end
function SendChatMessage() end
function SendAddonMessage() end
function GetRealZoneText() return "Elwynn Forest" end
function GetZoneText() return "Elwynn Forest" end
function GetMinimapZoneText() return "Goldshire" end
function IsInInstance() return nil end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetGuildInfo() return "Tortoise Raiders", "Officer", 1 end
function IsInGuild() return 1 end
function CanEditOfficerNote() return 1 end
function GuildControlGetNumRanks() return 5 end
function GuildControlGetRankName(i) return ({ "Guild Master", "Officer", "Veteran", "Raider", "Initiate" })[i] end
function GuildUninvite() end
function GetNumGuildMembers() return 0 end
function GetContainerNumSlots() return 16 end
function GetContainerItemInfo() return nil end
function GetContainerItemLink() return nil end
function PickupContainerItem() end
function SplitContainerItem() end
function CursorHasItem() return nil end
function ClearCursor() end
function ClickSendMailItemButton() end
function GetSendMailItem() return nil end
function GetMoney() return 1234567 end
function GetItemQualityColor(q)
    local c = ({ [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
        [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } })[q or 1] or { 1, 1, 1 }
    return c[1], c[2], c[3]
end
ITEM_QUALITY_COLORS = {}
for q = 0, 5 do local r, g, b = GetItemQualityColor(q); ITEM_QUALITY_COLORS[q] = { r = r, g = g, b = b } end
RAID_CLASS_COLORS = {}
function TargetUnit() end
function TargetByName() end
function DoReadyCheck() end
function InviteByName() end
function UninviteByName() end
function FauxScrollFrame_Update(frame, count, shown)
    frame.itemCount = count
    if frame.scrollBar then frame.scrollBar.shown = (count or 0) > (shown or 0) end
end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_OnVerticalScroll() end

local ITEMS = {
    [2586] = { "Gamemaster's Robe", 4, "Interface\\Icons\\INV_Chest_Cloth_17", "Armor", "Cloth" },
    [6948] = { "Hearthstone", 1, "Interface\\Icons\\INV_Misc_Rune_01", "Miscellaneous", "Junk" },
    [1201] = { "Dull Heater Shield", 0, "Interface\\Icons\\INV_Shield_09", "Armor", "Shields" },
    [2318] = { "Light Leather", 1, "Interface\\Icons\\INV_Misc_LeatherScrap_03", "Trade Goods", "Trade Goods" },
    [2319] = { "Medium Leather", 1, "Interface\\Icons\\INV_Misc_LeatherScrap_05", "Trade Goods", "Trade Goods" },
    [3860] = { "Mithril Casing", 1, "Interface\\Icons\\INV_Gizmo_MithrilCasing_01", "Trade Goods", "Parts" },
    [2589] = { "Linen Cloth", 1, "Interface\\Icons\\INV_Fabric_Linen_01", "Trade Goods", "Trade Goods" },
    [4306] = { "Silk Cloth", 1, "Interface\\Icons\\INV_Fabric_Silk_01", "Trade Goods", "Trade Goods" },
    [858]  = { "Lesser Healing Potion", 1, "Interface\\Icons\\INV_Potion_52", "Consumable", "Consumable" },
    [19019] = { "Thunderfury, Blessed Blade of the Windseeker", 5, "Interface\\Icons\\INV_Sword_39", "Weapon", "Swords" },
    [12640] = { "Lionheart Helm", 4, "Interface\\Icons\\INV_Helmet_36", "Armor", "Plate" },
    [13340] = { "Cape of the Black Baron", 3, "Interface\\Icons\\INV_Misc_Cape_20", "Armor", "Cloth" },
    [11815] = { "Hand of Justice", 3, "Interface\\Icons\\INV_Jewelry_Talisman_01", "Armor", "Misc" },
    [765]  = { "Silverleaf", 1, "Interface\\Icons\\INV_Misc_Herb_10", "Trade Goods", "Herb" },
    [118]  = { "Minor Healing Potion", 1, "Interface\\Icons\\INV_Potion_49", "Consumable", "Consumable" },
    [2453] = { "Bruiseweed", 1, "Interface\\Icons\\INV_Misc_Herb_01", "Trade Goods", "Herb" },
}
function GetItemInfo(id)
    if type(id) == "string" then id = tonumber(string.match(id, "item:(%d+)") or id) end
    local it = ITEMS[id]
    if not it then return "Item " .. tostring(id), "item:" .. tostring(id) .. ":0:0:0", 2, 40, it and it[4] or "Armor", "Misc", 1, "", "Interface\\Icons\\INV_Misc_QuestionMark" end
    return it[1], "item:" .. id .. ":0:0:0", it[2], 60, it[4], it[5], 20, "", it[3]
end
function GetSpellInfo() return nil end

-- units ------------------------------------------------------------------
local function partyIndex(unit)
    local _, _, i = string.find(unit or "", "^party(%d+)$")
    return i and tonumber(i)
end
function UnitExists(u)
    if u == "player" then return 1 end
    if u == "target" then return Mock.world.target and 1 or nil end
    local i = partyIndex(u)
    return i and Mock.world.party[i] and 1 or nil
end
function UnitName(u)
    if u == "player" then return "Valguard" end
    if u == "target" then return Mock.world.target and Mock.world.target.name end
    if u == "NPC" then return nil end
    local i = partyIndex(u)
    return i and Mock.world.party[i] and Mock.world.party[i].name
end
function UnitClass(u)
    local c = "Warrior"
    if u == "target" and Mock.world.target then c = Mock.world.target.class or "Warrior" end
    local i = partyIndex(u)
    if i and Mock.world.party[i] then c = Mock.world.party[i].class end
    return c, string.upper(c)
end
function UnitLevel(u)
    local i = partyIndex(u)
    if i and Mock.world.party[i] then return Mock.world.party[i].level or 60 end
    return 60
end
function UnitIsPlayer(u)
    if u == "target" then return Mock.world.target and Mock.world.target.player and 1 or nil end
    return 1
end
function UnitIsDead(u)
    if u == "target" then return Mock.world.target and Mock.world.target.dead and 1 or nil end
    return Mock.world.dead[u] and 1 or nil
end
function UnitIsGhost(u) return Mock.world.ghost[u] and 1 or nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsFriend() return 1 end
function UnitCanAttack(a, b) return b == "target" and Mock.world.target and not Mock.world.target.player end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitMana() return 100 end
function UnitManaMax() return 100 end
function UnitInParty(u) return 1 end
function UnitInRaid() return nil end
function UnitAffectingCombat() return nil end
function GetNumPartyMembers() return table.getn(Mock.world.party) end
function GetNumRaidMembers() return Mock.world.raid end
function IsPartyLeader() return 1 end
function GetPartyMember(i) return Mock.world.party[i] and i end
function GetRaidRosterInfo() return nil end
function GetRaidTargetIndex() return nil end
function SetRaidTargetIcon() end
function GetInventoryItemLink() return nil end
function GetInventoryItemTexture() return nil end
function GetInventorySlotInfo(name) return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. string.gsub(name, "Slot$", "") end
