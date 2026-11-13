-- tools/preview/scenes.lua
-- Loads the addon on the recording mock, fills it with a believable party,
-- roster and guild, and writes one JSON scene per window and tab.
--
--   lua5.1 tools/preview/scenes.lua <repo root> <out dir>
--   node tools/preview/render.js <out dir>
--
-- Scenes are layout previews, not game screenshots: icons and textures come
-- from the render step, fonts and colours from the font objects below.

local root = arg[1] or "."
-- Out dir "-" is the smoke-test mode (tests/ui_smoke.sh): nothing is
-- written, every registered event is fired once, and any Lua error in a
-- scene, script or event handler makes the run exit 1.
local out = arg[2] or "preview-out"
local smoke = out == "-"
local failures = {}
dofile(root .. "/tools/preview/mock.lua")

-- ── load the addon in .toc order ─────────────────────────────────────────
local toc = io.open(root .. "/TortoiseBotsManager.toc"):read("*a")
for line in string.gfind(toc, "[^\r\n]+") do
    if not string.find(line, "^##") and string.find(line, "%.lua%s*$") then
        local file = string.gsub(line, "%s+$", "")
        dofile(root .. "/" .. file)
    end
end

local TB = TortoiseBots
TortoiseBotsDB = TortoiseBotsDB or {}
event, arg1 = "ADDON_LOADED", "TortoiseBotsManager"
local core = Mock.frames["TortoiseBotsManagerCoreFrame"]
this = core
core.scripts.OnEvent(core)

local function sys(msg) TB.OnSystemMessage(msg) end
local function feed(lines) for _, l in ipairs(lines) do sys(l) end end

local function tick(n)
    for _ = 1, n or 3 do
        Mock.now = Mock.now + 1
        for _, o in ipairs(Mock.objects) do
            if o.scripts and o.scripts.OnUpdate and o.kind ~= "Texture" then
                this, arg1 = o, 1
                local ok, err = pcall(o.scripts.OnUpdate, o)
                if not ok then table.insert(failures, "OnUpdate: " .. tostring(err)) end
            end
        end
    end
end

-- ── world: a five-man party of your bots, a roster, a guild ─────────────
feed({
    "TBM:VERSION|1.12.0",
    "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service",
})
Mock.world.party = {
    { name = "Thalgrim", class = "Warrior", level = 60 },
    { name = "Seraphine", class = "Priest", level = 60 },
    { name = "Vexmora", class = "Mage", level = 59 },
    { name = "Bramblewood", class = "Druid", level = 60 },
}
local gw = Mock.frames["TortoiseBotsManagerGroupWatcher"]
if gw and gw.scripts.OnEvent then event = "PARTY_MEMBERS_CHANGED"; this = gw; pcall(gw.scripts.OnEvent, gw) end
feed({
    "TBM:ROSTER_BEGIN|9",
    "TBM:ROSTER|101|Thalgrim|1|online|1|Elwynn Forest",
    "TBM:ROSTER|102|Seraphine|5|online|1|Elwynn Forest",
    "TBM:ROSTER|103|Vexmora|8|online|1|Elwynn Forest",
    "TBM:ROSTER|104|Bramblewood|11|online|1|Elwynn Forest",
    "TBM:ROSTER|105|Kaelthor|2|online|0|Ironforge",
    "TBM:ROSTER|106|Nightwhisper|4|offline|0|Stormwind City",
    "TBM:ROSTER|107|Grimtotem|7|offline|0|Orgrimmar",
    "TBM:ROSTER|108|Felbrand|9|online|0|Duskwood",
    "TBM:ROSTER|109|Arrowind|3|offline|0|Westfall",
    "TBM:ROSTER_END",
    "TBM:ALTBOTS|Felbrand",
    "TBM:BOTSTATE_BEGIN|4",
    "TBM:BOTSTATE|Thalgrim|move=follow,loot=on,aoe=on,autocc=off,savemana=off,boost=on,threat=on,potions=on,hold=off,specs=protection",
    "TBM:BOTSTATE|Seraphine|move=follow,loot=on,aoe=on,autocc=off,savemana=on,boost=on,threat=on,potions=on,hold=on,specs=holy",
    "TBM:BOTSTATE|Vexmora|move=follow,loot=on,aoe=on,autocc=on,savemana=off,boost=on,threat=on,potions=on,hold=off,noblink=on,specs=frost",
    "TBM:BOTSTATE|Bramblewood|move=follow,loot=off,aoe=on,autocc=off,savemana=off,boost=on,threat=on,potions=on,hold=off,specs=restoration",
    "TBM:BOTSTATE_END",
    "TBM:CC_ASSIGN_BEGIN|1",
    "TBM:CC_ASSIGN|Vexmora|moon",
    "TBM:CC_ASSIGN_END",
    "TBM:CLAIMED_BEGIN|6",
    "TBM:CLAIMED|201|Goldie|1|60|online|0|Ironforge|1",
    "TBM:CLAIMED|202|Silverleaf|5|45|online|1|Duskwood|0",
    "TBM:CLAIMED|203|Ironhide|2|60|online|0|Blackrock Mountain|1",
    "TBM:CLAIMED|204|Mistral|7|52|offline|0|Tanaris|0",
    "TBM:CLAIMED|205|Stitchwork|9|60|online|0|Stormwind City|1",
    "TBM:CLAIMED|206|Fenwick|3|38|offline|0|Stranglethorn Vale|0",
    "TBM:CLAIMED_END",
    "TBM:ORDER_ACCESS|2|Raider|1,2|-|1|1",
    "TBM:ORDER_BEGIN|2",
    "TBM:ORDER|Goldie|farm|2318|Light Leather|4|10|working|-|Ashenvale",
    "TBM:ORDER|Ironhide|craft|3860|Mithril Casing|1|2|waiting|-|Ironforge",
    "TBM:ORDER_END",
})
for _, l in ipairs({
    "Thalgrim: Following you in shield formation.",
    "Seraphine: Drinking — 62% mana.",
    "Vexmora queued for login (following Valguard)",
    "Bramblewood: Rebuffed Mark of the Wild on 4 party members.",
    "Strategy change: +aoe on 4 bots",
    "Kaelthor logout requested",
}) do if TB.LogMessage then pcall(TB.LogMessage, l) end end

-- ── JSON ────────────────────────────────────────────────────────────────
local function esc(s)
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "")
    s = string.gsub(s, "\t", " ")
    s = string.gsub(s, "[%z\1-\31]", "")
    return s
end
local function enc(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return string.format("%.4f", v)
    end
    if t == "string" then return '"' .. esc(v) .. '"' end
    if t == "table" then
        if v.id and v.kind then return tostring(v.id) end
        local n = table.getn(v)
        local parts = {}
        if n > 0 then
            for i = 1, n do parts[i] = enc(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, x in pairs(v) do
            if type(x) ~= "function" then table.insert(parts, '"' .. esc(tostring(k)) .. '":' .. enc(x)) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local FIELDS = { "kind", "name", "template", "width", "height", "shown", "strata", "level", "alpha",
    "backdrop", "bdColor", "bdBorder", "layer", "file", "color", "texCoord", "vertex", "blend", "font",
    "text", "textColor", "justifyH", "justifyV", "enabled", "checked", "disabledTextColor",
    "highlightTextColor", "isButtonText", "stateKey", "isInput", "isScrollBar", "scale", "fontSize",
    "lockHighlight", "isActive", "flatKind", "barColor", "value", "min", "max", "disabledFont" }

local function dump(name, roots, note)
    local parts = {}
    for _, o in ipairs(Mock.objects) do
        local rec = { '"id":' .. o.id }
        if o.parent then table.insert(rec, '"parent":' .. o.parent.id) end
        for _, f in ipairs(FIELDS) do
            local v = o[f]
            if v ~= nil and type(v) ~= "function" then table.insert(rec, '"' .. f .. '":' .. enc(v)) end
        end
        if o.normalTex then table.insert(rec, '"normalTex":' .. o.normalTex.id) end
        if o.pushedTex then table.insert(rec, '"pushedTex":' .. o.pushedTex.id) end
        if o.disabledTex then table.insert(rec, '"disabledTex":' .. o.disabledTex.id) end
        if o.highlightTex then table.insert(rec, '"highlightTex":' .. o.highlightTex.id) end
        if o.checkedTex then table.insert(rec, '"checkedTex":' .. o.checkedTex.id) end
        if o.fontString then table.insert(rec, '"fontString":' .. o.fontString.id) end
        local pts = {}
        for _, p in ipairs(o.points or {}) do
            table.insert(pts, string.format('{"point":"%s","rel":%s,"relPoint":"%s","x":%s,"y":%s}',
                p.point, p.rel and p.rel.id or "null", p.relPoint or p.point, enc(p.x or 0), enc(p.y or 0)))
        end
        table.insert(rec, '"points":[' .. table.concat(pts, ",") .. "]")
        table.insert(parts, "{" .. table.concat(rec, ",") .. "}")
    end
    local rootIds = {}
    for _, r in ipairs(roots) do if r then table.insert(rootIds, tostring(r.id)) end end
    if smoke then io.write("scene " .. name .. "\n") return end
    local f = io.open(out .. "/" .. name .. ".json", "w")
    f:write('{"name":"' .. name .. '","note":"' .. esc(note or "") .. '","uiparent":' .. UIParent.id
        .. ',"roots":[' .. table.concat(rootIds, ",") .. '],"objects":[' .. table.concat(parts, ",") .. "]}")
    f:close()
    io.write("scene " .. name .. "\n")
end

local function scene(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        io.write("scene " .. name .. " FAILED: " .. tostring(err) .. "\n")
        table.insert(failures, name .. ": " .. tostring(err))
    end
end

local function hideSatellites()
    for _, n in ipairs({ "CloseBotPanel", "CloseRunWindow", "CloseOrderWindow", "CloseServerInfo", "CloseSettings", "CloseNpc", "CloseVault", "CloseBlessings" }) do
        if TB[n] then pcall(TB[n]) end
    end
    if TB.ccMenu then TB.ccMenu:Hide() end
end

local main = TB.frame
main:ClearAllPoints()
main:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -40)
main:Show()
TB.Refresh()

local function tab(name, target)
    hideSatellites()
    if TB.SetMode then TB.SetMode("full") end
    main:Show()
    Mock.world.target = target
    TB.ShowTab(name)
    TB.Refresh()
    tick(2)
end

scene("fight", function() tab("actions", nil); dump("fight", { main }, "Fight tab, no target") end)
scene("fight-engage", function()
    feed({ "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service,engage" })
    tab("actions", nil)
    dump("fight-engage", { main }, "Fight tab on a server with the Engage hold")
    feed({ "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service" })
end)
scene("fight-target", function()
    tab("actions", { name = "Defias Pillager", player = false, class = "Rogue" })
    dump("fight-target", { main }, "Fight tab with an enemy target")
end)
scene("fight-bot", function()
    tab("actions", { name = "Seraphine", player = true, class = "Priest" })
    dump("fight-bot", { main }, "Fight tab with one of your bots targeted")
end)
scene("ccmenu", function()
    tab("actions", nil)
    TB.ToggleCcMenu()
    dump("ccmenu", { main, TB.ccMenu }, "CC marks panel")
end)
scene("camp", function() tab("camp", nil); dump("camp", { main }, "Camp tab") end)
scene("party", function() tab("party", nil); dump("party", { main }, "Party tab") end)
scene("roster", function()
    tab("roster", nil)
    if TB.ToggleRosterSelection then TB.ToggleRosterSelection("Kaelthor", true); TB.ToggleRosterSelection("Nightwhisper", true) end
    TB.Refresh()
    dump("roster", { main }, "Roster tab, two bots selected")
end)
scene("guild", function()
    tab("guild", nil)
    if TB.ToggleClaimedSelection then TB.ToggleClaimedSelection("Goldie", true) end
    if TB.RefreshGuildView then TB.RefreshGuildView() end
    dump("guild", { main }, "Guild tab with orders")
end)
scene("log", function() tab("log", nil); dump("log", { main }, "Log tab") end)
scene("loot", function()
    feed({
        "TBM:LOOT_BEGIN|4|",
        "TBM:LOOT|2026-10-27 12:00:01|Thalgrim|StoreLootAction|12640|Lionheart Helm|corpse|General Drakkisath|4",
        "TBM:LOOT|2026-10-27 12:00:02|Vexmora|LootMoney|812|1550|corpse|Kobold Vermin|",
        "TBM:LOOT|2026-10-27 12:00:05|Seraphine|StoreLootAction|13340|Cape of the Black Baron|corpse|Baron Rivendare|3",
        "TBM:LOOT|2026-10-27 12:01:11|Bramblewood|StoreLootAction|2589|Linen Cloth|corpse|Defias Thug|1",
        "TBM:LOOT_END|",
    })
    tab("loot", nil)
    dump("loot", { main }, "Loot tab")
end)
scene("dungeon", function()
    tab("dungeon", nil)
    dump("dungeon", { main, TB.runWindow }, "Dungeon tab and run window")
end)
scene("raid", function()
    Mock.world.raid = 12
    tab("raid", nil)
    dump("raid", { main }, "Raid tab")
    Mock.world.raid = 0
    if TB.UpdateRaidTab then TB.UpdateRaidTab() end
end)

-- Bot panel
feed({
    "TBM:INV_BEGIN|Seraphine|1234567",
    "TBM:INV_EQ|1|12640|90|100",
    "TBM:INV_EQ|5|2586|40|50",
    "TBM:INV_EQ|15|13340|0|0",
    "TBM:INV_EQ|13|11815|0|0",
    "TBM:INV_EQ|16|19019|100|125",
    "TBM:INV_ITEM|255|1|6948|1|b",
    "TBM:INV_ITEM|255|2|858|5|u",
    "TBM:INV_ITEM|255|3|2589|20|",
    "TBM:INV_ITEM|255|4|1201|1|eu",
    "TBM:INV_ITEM|20|1|4306|12|",
    "TBM:INV_ITEM|20|2|13340|1|e",
    "TBM:INV_END|Seraphine|30|46",
    "TBM:PROF_BEGIN|Seraphine",
    "TBM:PROF|186|245|300",
    "TBM:PROF|182|230|300",
    "TBM:RECIPE|186|2651|3860|1|25|50|100|ok",
    "TBM:RECIPE|182|1972|765|1|25|50|100|bound",
    "TBM:RECIPE_MISSING|182|1973|118|50|0",
    "TBM:RECIPE_MISSING|182|6259|2453|60|1710",
    "TBM:PROF_END|Seraphine|2|2",
})
for _, view in ipairs({ "gear", "bags", "behavior", "spells", "profs" }) do
    scene("panel-" .. view, function()
        tab("party", nil)
        TB.OpenBotPanel("Seraphine", view)
        tick(1)
        if TB.RefreshBotPanel then TB.RefreshBotPanel() end
        dump("panel-" .. view, { main, TB.botPanel }, "Bot panel: " .. view)
    end)
end
scene("panel-totems", function()
    tab("party", nil)
    feed({
        "TBM:BOTSTATE|Grimtotem|move=follow,loot=on,aoe=on,hold=off",
        "TBM:TOTEM|Grimtotem|earth=strength of earth totem,fire=searing totem,water=mana spring totem,air=windfury totem,"
            .. "mode=auto,known=stoneskin totem+strength of earth totem+searing totem+mana spring totem+windfury totem",
    })
    TB.OpenBotPanel("Grimtotem", "behavior")
    tick(1)
    dump("panel-totems", { main, TB.botPanel }, "Bot panel: behaviour of a shaman with the totem picker")
end)
scene("panel-choices", function()
    tab("party", nil)
    feed({
        "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service,choice",
        "TBM:BOTSTATE|Kaelthor|move=follow,loot=on,hold=on",
        "TBM:CHOICE|Kaelthor|aura=devotion aura,known=devotion aura+retribution aura+shadow resistance",
    })
    table.insert(Mock.world.party, { name = "Kaelthor", class = "Paladin", level = 60 })
    TB.OpenBotPanel("Kaelthor", "behavior")
    tick(1)
    dump("panel-choices", { main, TB.botPanel }, "Bot panel: behaviour of a paladin with the class picker")
    table.remove(Mock.world.party)
end)
scene("bots", function()
    tab("party", nil)
    TB.OpenBots()
    tick(1)
    dump("bots", { main, TB.botsWindow }, "Party tab with the Bots overview")
end)
scene("blessings", function()
    table.insert(Mock.world.party, { name = "Kaelthor", class = "Paladin", level = 60 })
    feed({
        "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service,blessing,choice,blessing-player",
        "TBM:BOTSTATE|Kaelthor|move=follow,loot=on",
        "TBM:CHOICE|Kaelthor|aura=devotion aura,known=devotion aura+retribution aura+concentration aura+shadow resistance aura",
        "TBM:BLESSING|Kaelthor|warrior=kings,paladin=kings,hunter=might,rogue=might,priest=wisdom,shaman=wisdom,"
            .. "mage=wisdom,warlock=auto,druid=light,known=might+wisdom+kings+light,players=Valguard:might",
    })
    local gw = Mock.frames["TortoiseBotsManagerGroupWatcher"]
    event = "PARTY_MEMBERS_CHANGED"; this = gw; gw.scripts.OnEvent(gw)
    tab("party", nil)
    TB.OpenBlessings()
    tick(1)
    dump("blessings", { main, TB.blessingsWindow }, "Party tab with the blessing board (1 paladin)")
    TB.CloseBlessings()
    table.remove(Mock.world.party)
    event = "PARTY_MEMBERS_CHANGED"; this = gw; gw.scripts.OnEvent(gw)
end)
scene("blessings-raid", function()
    local raidRoster = {
        { name = "Valguard", class = "Warrior" },
        { name = "Kaelthor", class = "Paladin" },
        { name = "Sunblade", class = "Paladin" },
        { name = "Lightward", class = "Paladin" },
        { name = "Swiftarrow", class = "Hunter" },
        { name = "Shadeblade", class = "Rogue" },
        { name = "Seraphine", class = "Priest" },
        { name = "Grimtotem", class = "Shaman" },
        { name = "Vexmora", class = "Mage" },
        { name = "Dreadcoil", class = "Warlock" },
        { name = "Bramblewood", class = "Druid" },
    }
    local realName, realClass = UnitName, UnitClass
    Mock.world.raid = table.getn(raidRoster)
    UnitName = function(u)
        local _, _, idx = string.find(u or "", "^raid(%d+)$")
        local r = idx and raidRoster[tonumber(idx)]
        return r and r.name or realName(u)
    end
    UnitClass = function(u)
        local _, _, idx = string.find(u or "", "^raid(%d+)$")
        local r = idx and raidRoster[tonumber(idx)]
        if r then return r.class, string.upper(r.class) end
        return realClass(u)
    end
    feed({
        "TBM:CAPS|pull-seconds,flee,inventory,behavior,downtime,claimed-roster,guild-orders,professions,dungeon-run,loot-log,service,blessing,choice,blessing-player",
        "TBM:BOTSTATE|Kaelthor|move=follow,loot=on",
        "TBM:BOTSTATE|Sunblade|move=follow,loot=on",
        "TBM:BOTSTATE|Lightward|move=follow,loot=on",
        "TBM:CHOICE|Kaelthor|aura=devotion aura,known=devotion aura+retribution aura+concentration aura",
        "TBM:CHOICE|Sunblade|aura=concentration aura,known=devotion aura+concentration aura+shadow resistance aura",
        "TBM:CHOICE|Lightward|aura=auto,known=devotion aura+retribution aura",
        "TBM:BLESSING|Kaelthor|warrior=might,paladin=wisdom,hunter=might,rogue=might,priest=wisdom,shaman=wisdom,"
            .. "mage=wisdom,warlock=wisdom,druid=wisdom,known=might+wisdom+kings+salvation+sanctuary+light,players=Valguard:sanctuary",
        "TBM:BLESSING|Sunblade|warrior=kings,paladin=kings,hunter=kings,rogue=kings,priest=kings,shaman=kings,"
            .. "mage=kings,warlock=kings,druid=kings,known=might+wisdom+kings+salvation+light",
        "TBM:BLESSING|Lightward|warrior=auto,paladin=might,hunter=salvation,rogue=salvation,priest=salvation,shaman=might,"
            .. "mage=salvation,warlock=salvation,druid=might,known=might+wisdom+salvation+light",
    })
    tab("party", nil)
    TB.OpenBlessings()
    tick(1)
    dump("blessings-raid", { main, TB.blessingsWindow }, "Blessing board in a 9-class raid (3 paladins)")
    TB.CloseBlessings()
    Mock.world.raid = 0
    UnitName, UnitClass = realName, realClass
end)
scene("npc", function()
    tab("party", nil)
    TB.OpenBotPanel("Seraphine", "gear")
    TB.OpenNpc("Seraphine")
    dump("npc", { main, TB.botPanel, TB.npcFrame or TB.npcWindow }, "NPC errands")
end)
scene("vault", function()
    tab("party", nil)
    TB.OpenBotPanel("Seraphine", "gear")
    TB.OpenVault("Seraphine", "bank")
    dump("vault", { main, TB.botPanel, TB.vaultFrame or TB.vaultWindow }, "Bank and mail")
end)
scene("order", function()
    tab("guild", nil)
    feed({
        "TBM:ORDER_ITEMS_BEGIN|2",
        "TBM:ORDER_ITEM|2318|Light Leather|1|drop,skin|5|393:1|ok|Ashenvale|70",
        "TBM:ORDER_ITEM|2319|Medium Leather|1|skin|16|393:100|ok|Ashenvale|50",
        "TBM:ORDER_ITEMS_END",
    })
    TB.OpenOrderWindow("Goldie")
    tick(1)
    dump("order", { main, TB.orderWindow }, "Order window for one bot")
end)
scene("guild-order", function()
    tab("guild", nil)
    TB.OpenGuildOrderWindow()
    feed({
        "TBM:ORDER_WHO_BEGIN|1",
        "TBM:ORDER_WHO|craft|3860|Mithril Casing|2|-|165|Goldie:165:3:3:0;Ironhide:140:1:3:1",
        "TBM:ORDER_WHO_END",
    })
    tick(1)
    dump("guild-order", { main, TB.orderWindow }, "Guild order window")
end)
scene("info", function()
    tab("actions", nil)
    feed({ "TBM:FEATURE|dungeon-run|on|Dungeon runs", "TBM:FEATURE|hire-max|4|Hires per player",
        "TBM:FEATURE|world-buffs|off|World buffs", "TBM:FEATURE|loot-log|on|Loot history" })
    TB.OpenServerInfo()
    dump("info", { main, TB.serverInfo or TB.infoFrame or TB.serverInfoFrame }, "Server info")
end)
scene("settings", function()
    tab("actions", nil)
    TB.OpenSettings()
    dump("settings", { main, TB.settingsWindow }, "Settings window")
end)
scene("mini", function()
    hideSatellites()
    TortoiseBotsDB.miniFavorites = { "attack", "stop", "pull", "focus skull", "follow", "aoe" }
    TortoiseBotsDB.miniFavoritesOwn = true
    TB.SetMode("mini")
    if TB.LayoutMiniBar then TB.LayoutMiniBar() end
    Mock.world.target = { name = "Defias Pillager", player = false }
    TB.Refresh()
    if TB.OpenMiniCategory then pcall(TB.OpenMiniCategory, "engage") end
    dump("mini", { TB.miniBar, TB.miniFlyout }, "Mini bar with the Engage flyout open")
    TB.SetMode("full")
end)

-- Smoke mode: every frame's registered events, once each, with string args
-- as the client passes them; then report.
if smoke then
    local EVENT_ARGS = {
        UNIT_HEALTH = { "party1" }, UNIT_MANA = { "party1" }, UNIT_AURA = { "party1" },
        ADDON_LOADED = { "SomeOtherAddon" },
        CHAT_MSG_ADDON = { "TBM", "TBM:VERSION|1.12.0", "PARTY", "Valguard" },
        CHAT_MSG_SYSTEM = { "Unrelated system message" },
        CHAT_MSG_WHISPER = { "hello", "Seraphine" },
    }
    TB.SetMode("full")
    for _, o in ipairs(Mock.objects) do
        if o.events and o.scripts.OnEvent then
            for e in pairs(o.events) do
                local a = EVENT_ARGS[e] or { "", "", "" }
                this, event = o, e
                arg1, arg2, arg3, arg4 = a[1], a[2], a[3], a[4]
                local ok, err = pcall(o.scripts.OnEvent, o)
                if not ok then table.insert(failures, "event " .. e .. ": " .. tostring(err)) end
            end
        end
    end
    tick(3)
    if table.getn(failures) > 0 then
        for _, f in ipairs(failures) do print("FAIL: " .. f) end
        print("FAIL: UI smoke test, " .. table.getn(failures) .. " error(s)")
        os.exit(1)
    end
    print("PASS: UI smoke test, every window and tab built, every event handler ran without a Lua error")
end
