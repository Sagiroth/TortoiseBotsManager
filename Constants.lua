-- TortoiseBotsManager/Constants.lua
-- Single source of truth for dimensions, colors, timings, and UX strings.
-- Vanilla 1.12 safe.

TortoiseBots = TortoiseBots or {}
local TB = TortoiseBots
TB.C = TB.C or {}

TB.C.VERSION = "0.1.2"

-- Panel geometry
TB.C.PANEL_W = 520
TB.C.PANEL_H = 520
TB.C.ROW_H   = 36
TB.C.ROW_N   = 6

-- Throttle / poll
TB.C.SEND_DELAY      = 0.35  -- min seconds between SendChatMessage(".bot …")
TB.C.LIST_THROTTLE   = 5     -- hard throttle for .bot list
TB.C.POLL_PANEL_IV   = 8     -- poll every N sec while panel open
TB.C.POLL_HIDDEN_IV  = 20    -- while hidden, if autoPoll
TB.C.POLL_AFTER_CMD  = 1.4   -- poll soon after any command
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
