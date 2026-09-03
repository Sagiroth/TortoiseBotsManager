-- TortoiseBotsManager/Constants.lua
-- Single source of truth for dimensions, colors, timings, and UX strings.
-- Vanilla 1.12 safe.

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
TB.C = TB.C or {}

TB.C.VERSION = "1.1.0"

-- Panel geometry — compact Vanilla-safe control plane.
TB.C.PANEL_W = 500
TB.C.PANEL_H = 395
TB.C.ROW_H   = 28
TB.C.ROW_N   = 7
TB.C.PAD     = 10  -- outer margin
TB.C.GAP_S   = 8   -- section gap
TB.C.GAP_BTN = 4   -- button gap

-- Column widths for the snapshot roster. The last-location column is allowed
-- to collapse in UI.lua when a server row has no location metadata.
TB.C.ROSTER_NAME_W = 118
TB.C.ROSTER_CLASS_W = 70
TB.C.ROSTER_STATUS_W = 145

TB.C.CLASS_NAMES = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [6] = "Death Knight",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
    [11] = "Druid",
}

TB.C.CLASS_COLORS = {
    [1]  = { 0.78, 0.61, 0.43, hex = "ffc79c6e" }, -- Warrior (Tan)
    [2]  = { 0.96, 0.55, 0.73, hex = "fff58cba" }, -- Paladin (Pink)
    [3]  = { 0.67, 0.83, 0.45, hex = "ffabd473" }, -- Hunter (Green)
    [4]  = { 1.00, 0.96, 0.41, hex = "fffff569" }, -- Rogue (Yellow)
    [5]  = { 1.00, 1.00, 1.00, hex = "ffffffff" }, -- Priest (White)
    [6]  = { 0.77, 0.12, 0.23, hex = "ffc41f3b" }, -- Death Knight (Red)
    [7]  = { 0.00, 0.44, 0.87, hex = "ff0070de" }, -- Shaman (Blue)
    [8]  = { 0.41, 0.80, 0.94, hex = "ff69ccf0" }, -- Mage (Light Blue)
    [9]  = { 0.58, 0.51, 0.79, hex = "ff9482c9" }, -- Warlock (Purple)
    [11] = { 1.00, 0.49, 0.04, hex = "ffff7d0a" }, -- Druid (Orange)
}

TB.C.ACTIONS = {
    "attack", "stop", "pull", "pullback", "come", "stay", "follow",
    "focus skull", "cc moon", "aoe",
}

TB.C.ACTION_ICONS = {
    attack          = "Interface\\Icons\\Ability_SteelMelee",
    stop            = "Interface\\Icons\\Ability_Defend",
    pull            = "Interface\\Icons\\Ability_TrueShot",
    pullback        = "Interface\\Icons\\Ability_Hunter_AimedShot",
    come            = "Interface\\Icons\\Spell_Arcane_PortalIronForge",
    stay            = "Interface\\Icons\\Spell_Nature_TimeStop",
    follow          = "Interface\\Icons\\Ability_Tracking",
    ["focus skull"] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    ["cc moon"]     = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    aoe             = "Interface\\Icons\\Spell_Fire_FlameBlades",
}

TB.C.ACTION_LABELS = {
    attack = "Attack",
    stop = "Stop",
    pullback = "Pullback",
    pull = "Pull",
    come = "Come",
    stay = "Stay",
    follow = "Follow",
    ["focus skull"] = "Focus Skull",
    ["cc moon"] = "CC Moon",
    aoe = "AoE",
}

-- Throttle / poll
TB.C.SEND_DELAY      = 0.35  -- min seconds between SendChatMessage(".bot …")
TB.C.LIST_THROTTLE   = 5     -- hard throttle for .bot roster
TB.C.ROSTER_THROTTLE = TB.C.LIST_THROTTLE
TB.C.POLL_PANEL_IV   = 8     -- poll every N sec while panel open
TB.C.POLL_HIDDEN_IV  = 20    -- while hidden, if autoPoll
TB.C.POLL_AFTER_CMD  = 1.4   -- poll soon after any lifecycle command
TB.C.POLL_AFTER_ADD  = 2.0
TB.C.ADD_TIMEOUT     = 30    -- seconds without login confirmation
TB.C.REMOVE_TIMEOUT  = 15    -- seconds without removal confirmation
TB.C.ACTION_TIMEOUT  = 8     -- seconds for a named action acknowledgement
TB.C.SUMMON_SETTLE   = 15    -- accepted summon stays visibly pending while teleport completes
TB.C.POLL_WAIT       = 1.2   -- seconds before reconciling a list snapshot
TB.C.POLL_NO_REPLY_LIMIT = 2 -- consecutive silent polls before Unknown

-- Minimap
TB.C.MINIMAP_RADIUS = 80
TB.C.MINIMAP_DEFAULT = { x = 52, y = 52 }

-- Colors (r,g,b) — Turtle palette
TB.C.COLOR = {
    gold   = { 0.95, 0.72, 0.28 },
    text   = { 0.92, 0.90, 0.84 },
    muted  = { 0.62, 0.60, 0.56 },
    green  = { 0.30, 0.90, 0.45 },
    red    = { 1.00, 0.34, 0.28 },
    yellow = { 1.00, 0.82, 0.10 },
    blue   = { 0.42, 0.76, 1.00 },
    bg     = { 0.025, 0.032, 0.045 },
    accent = { 0.78, 0.53, 0.14 },
    accentHi = { 0.95, 0.72, 0.28 },
}

-- Status
TB.C.STATUS = {
    OFFLINE        = "offline",
    OFFLINE_PENDING= "offline-pending",
    UNKNOWN        = "unknown",
    FAILED         = "failed",
    QUEUED         = "queued",
    STARTING       = "starting",
    ONLINE         = "online",
    COMMANDING     = "commanding",
    SUMMONING      = "summoning",
    INVITING       = "inviting",
    KICKING        = "kicking",
    REMOVING       = "removing",
}

TB.C.FORMATIONS = {
    "default", "melee", "queue", "chaos", "circle",
    "line", "shield", "arrow", "near", "far",
}
