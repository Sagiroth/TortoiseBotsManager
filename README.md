# TortoiseBots Manager
<img width="365" height="311" alt="2" src="https://github.com/user-attachments/assets/d35eaf72-9b88-462f-8f9a-7aa7051257e6" />
<img width="368" height="310" alt="1" src="https://github.com/user-attachments/assets/16607951-fdcf-4496-a752-cde89e25096d" />

Lightweight, **Vanilla 1.12 (11200)** addon to manage your bots [Tortoise WoW 1.18.1](https://github.com/Penqle/tortoise-wow).

Actions use normal WoW targeting for gameplay intent. Roster is a server-owned lifecycle list for logging bots in/out and managing group membership; no combat controls are attached to rows.

> **Requires the server-side module:** [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots) (`modules/TortoiseBots`). The addon sends `.bot` transport commands, consumes structured `TBM:` responses, and keeps legacy command compatibility.


---

## Features

* **Actions** — `Attack`, `Interrupt`, `Stop`, `Pull`, `Pullback`, `Come`, `Stay`, `Follow`, `Focus Skull`, configurable `CC Mark`, and `AoE`.
* **Target-derived scope** — party bots by default; targeting a controllable owned bot narrows dynamic actions to that bot. The server remains authoritative.
* **Server-owned roster** — online and offline owned characters arrive from `.bot roster`, with class, lifecycle status, group membership, and reliable last-location metadata when available. A separate assignment snapshot supplies each live bot's current CC mark.
* **Lifecycle bar** — select multiple roster rows and use `Login`, `Logout`, `Invite`, `Kick`, or `Summon`; mixed selections execute only eligible rows.
* **Quiet transport** — addon command echoes and structured transport are locally filtered through the standard message filter or legacy chat dispatcher, while gameplay requests return one compact structured result instead of per-bot chat.
* **Compact UI** — `Actions` is the default tab; `Roster` has checkbox rows and no per-row combat controls. The draggable panel remembers position and supports `Esc` close, minimap toggle, search, and tooltips.
* **Compatibility** — legacy `.bot` commands and `.bot command` remain available server-side; the primary UI does not expose the advanced command console.

## Companion Module

This addon is the in-game half of:

**[Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots)** — optional native PlayerBots module for Tortoise WoW 1.18.1 (`Penqle/tortoise-wow` + PR #438). It owns `BotManager`, bot records, `.bot` commands and class AI. The addon requires it.

```
Tortoise WoW core (Headless sessions #438)
        │
        │  .bot chat commands
        ▼
TortoiseBots module (server, authoritative)
        │
        │  CHAT_MSG_SYSTEM + bot whisper replies
        ▼
TortoiseBots Manager (in-game, /tbm, optimistic UI)
```

No module → addon loads but every action replies “TortoiseBots module not loaded” from the server.

## Use

* `/tbm` (primary) — toggle panel. Aliases `/tb` / `/tbot` / `/tortoise` still work.
* `/tbm list` — force a server roster refresh. `/tbm help` and `/tbm resetpos` remain available.
* **Actions** — use normal WoW target selection. With an enemy target, `Attack`, `Interrupt`, `Pull`, and `Pullback` operate on the party; `Interrupt` chooses one capable bot server-side. With an owned bot target, dynamic actions such as `Stay` and `Follow` operate only on that bot.
* **Roster** — select one or more rows, then use the bottom `Login`, `Logout`, `Invite`, `Kick`, or `Summon` action. Disabled actions have no eligible selected rows.
* **Focus / CC** — mark enemies with normal raid icons. Open `CC Mark`, then choose an icon: target a bot first to assign that bot, or target an enemy/leave party scope for automatic executor selection. The Party tab shows each bot's current CC icon; click a bot row to target it for assignment.
* **Search** — filters the server snapshot by name.

## How it works (edge cases)

* `TBM:ROSTER_*` and `TBM:ACTION_*` system messages are parsed as structured state; legacy human-readable responses remain a compatibility fallback.
* Server-side ownership, Headless lifecycle, target validation, executor selection, and mature PlayerbotAI behavior are authoritative. The addon only disables obviously unavailable controls.
* Roster lifecycle operations remain individually acknowledged and time out instead of staying optimistic forever. Gameplay never loops over roster selection.
* Multi-bot Invite advances only after each bot is a real group member, not merely after the server creates its pending invite. Full normal parties upgrade to a raid before another owned bot is invited.
* Normal `.bot` command echoes and structured `TBM:` transport messages are hidden locally through the standard chat filter or the legacy chat dispatcher; critical system errors stay visible.

## Requirements

* **Game:** Tortoise WoW English 1.18.1 (Interface 11200).
* **Server:** TortoiseBots module built with `MODULE_TORTOISEBOTS=static` and core PR #438 (`SessionTransport::Headless`). Without it, `.bot` returns “unknown command”.

## Files

```
TortoiseBotsManager.toc
Constants.lua   — geometry, colors, delays, status
Utils.lua       — Trim, NormalizeName, backdrop, Status helpers
Core.lua        — slash commands, throttled transport, roster polling, SavedVariables UI preferences
Roster.lua      — authoritative snapshot, live state, group membership, CC assignments, checkbox eligibility
Comms.lua       — structured `TBM:` responses plus legacy command parsing
UI.lua          — compact Actions/Roster/Party tabs and contextual lifecycle bar
Minimap.lua     — draggable minimap button
```

## Development check

Run the Vanilla-compatible regression harness from the addon root:

```bash
lua5.1 tests/regression.lua .
```

## Roadmap

* Future — richer structured acknowledgements, strategy presets, and role-aware filters after dungeon playtest.

## Project scope and affiliation

This repository contains addon source code only. It does not distribute
game binaries or extracted game data/assets, provide hosting, or operate
a game service. It is not affiliated with or endorsed by Blizzard Entertainment
or Tortoise WoW. World of Warcraft and related marks belong to their respective
owners.

## Licence

MIT — see [LICENSE](LICENSE). The game is proprietary; this addon only
uses the standard addon interface.

## Links

* Module: https://github.com/Sagiroth/TortoiseBots
* Core: https://github.com/Penqle/tortoise-wow
* Issues: https://github.com/Sagiroth/TortoiseBotsManager/issues
