# TortoiseBots Manager

Lightweight, nice-looking **Vanilla 1.12 (11200)** addon for the Actions and Roster surfaces of [Tortoise WoW 1.18.1](https://github.com/Penqle/tortoise-wow).

Actions use normal WoW targeting for gameplay intent. Roster is a server-owned lifecycle list for logging bots in/out and managing group membership; no combat controls are attached to rows.

> **Requires the server-side module:** [tortoise-wow-stack/TortoiseBots](https://github.com/tortoise-wow-stack/TortoiseBots) (`modules/TortoiseBots`). The addon sends `.bot` transport commands, consumes structured `TBM:` responses, and keeps legacy command compatibility.

![TortoiseBots Manager panel](https://raw.githubusercontent.com/tortoise-wow-stack/TortoiseBotsManager/main/.github/preview.png)

---

## Features

* **Actions** — `Attack`, `Stop`, `Pull`, `Pullback`, `Come`, `Stay`, `Follow`, `Focus Skull`, `CC Moon`, and `AoE`.
* **Target-derived scope** — party bots by default; targeting a controllable owned bot narrows dynamic actions to that bot. The server remains authoritative.
* **Server-owned roster** — online and offline owned characters arrive from `.bot roster`, with class, lifecycle status, group membership, and reliable last-location metadata when available.
* **Lifecycle bar** — select multiple roster rows and use `Login`, `Logout`, `Invite`, `Kick`, or `Summon`; mixed selections execute only eligible rows.
* **Quiet transport** — addon command echoes are locally filtered when the client supports message filters, and new gameplay requests return one compact structured result instead of per-bot chat.
* **Compact UI** — `Actions` is the default tab; `Roster` has checkbox rows and no per-row combat controls. The draggable panel remembers position and supports `Esc` close, minimap toggle, search, and tooltips.
* **Compatibility** — legacy `.bot` commands and `.bot command` remain available server-side; the primary UI does not expose the advanced command console.

## Companion Module

This addon is the client half of:

**[tortoise-wow-stack/TortoiseBots](https://github.com/tortoise-wow-stack/TortoiseBots)** — optional native PlayerBots module for Tortoise WoW 1.18.1 (`Penqle/tortoise-wow` + PRs #411/#416). It owns `BotManager`, `Headless` sessions, `.bot` commands and class AI. The addon requires it.

```
Tortoise WoW core (Headless sessions #411)
        │
        │  .bot chat commands
        ▼
TortoiseBots module (server, authoritative)
        │
        │  CHAT_MSG_SYSTEM + bot whisper replies
        ▼
TortoiseBots Manager (client, /tbm, optimistic UI)
```

No module → addon loads but every action replies “TortoiseBots module not loaded” from the server.

## Install

1. Download or `git clone` this repo into your client:
   ```
   <TurtleWoW>/Interface/AddOns/TortoiseBotsManager/
   ```
   The folder must be named `TortoiseBotsManager` (so the `.toc` is found).
2. Restart the client fully (Vanilla loads addons at startup).
3. Log in — you should see `TortoiseBots Manager v1.1.0 loaded. /tbm to open.` in chat.

### From this repo

```bash
git clone https://github.com/tortoise-wow-stack/TortoiseBotsManager.git
cp -r TortoiseBotsManager "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBotsManager"
# or symlink
ln -s "$(pwd)/TortoiseBotsManager" "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBotsManager"
```

## Use

* `/tbm` (primary) — toggle panel. Aliases `/tb` / `/tbot` / `/tortoise` still work.
* `/tbm list` — force a server roster refresh. `/tbm help` and `/tbm resetpos` remain available.
* **Actions** — use normal WoW target selection. With an enemy target, `Attack`, `Pull`, and `Pullback` operate on the party; with an owned bot target, dynamic actions such as `Stay` and `Follow` operate only on that bot.
* **Roster** — select one or more rows, then use the bottom `Login`, `Logout`, `Invite`, `Kick`, or `Summon` action. Disabled actions have no eligible selected rows.
* **Focus / CC** — mark an enemy with the normal Skull or Moon raid icon, then press `Focus Skull` or `CC Moon`. Target your owned bot before `CC Moon` to request that executor specifically.
* **Search** — filters the server snapshot by name.

## How it works (edge cases)

* `TBM:ROSTER_*` and `TBM:ACTION_*` system messages are parsed as structured state; legacy human-readable responses remain a compatibility fallback.
* Server-side ownership, Headless lifecycle, target validation, executor selection, and mature PlayerbotAI behavior are authoritative. The client only disables obviously unavailable controls.
* Roster lifecycle operations remain individually acknowledged and time out instead of staying optimistic forever. Gameplay never loops over roster selection.
* Normal `.bot` command echoes and structured `TBM:` transport messages are hidden locally through the standard chat filter or the legacy chat dispatcher; critical system errors stay visible.

## Requirements

* **Client:** Turtle WoW English 1.18.1 (Interface 11200).
* **Server:** TortoiseBots module built with `MODULE_TORTOISEBOTS=static` and Headless PR #411 (`SessionTransport::Headless`). Without it, `.bot` returns “unknown command”.

## Files

```
TortoiseBotsManager.toc
Constants.lua   — geometry, colors, delays, status
Utils.lua       — Trim, NormalizeName, backdrop, Status helpers
Core.lua        — slash commands, throttled transport, roster polling, SavedVariables UI preferences
Roster.lua      — authoritative snapshot, live state, group membership, checkbox eligibility
Comms.lua       — structured `TBM:` responses plus legacy command parsing
UI.lua          — compact Actions/Roster tabs and contextual lifecycle bar
Minimap.lua     — draggable minimap button
```

## Development check

Run the Vanilla-compatible regression harness from the addon root:

```bash
lua5.1 tests/regression.lua .
```

## Roadmap

* Future — richer structured acknowledgements, configurable raid marks, strategy presets, and role-aware filters after dungeon playtest.

## Project scope and affiliation

This repository contains client-addon source code only. It does not distribute
game-client binaries or extracted game data/assets, provide hosting, or operate
a game service. It is not affiliated with or endorsed by Blizzard Entertainment
or Turtle WoW. World of Warcraft and related marks belong to their respective
owners.

## Licence

MIT — see [LICENSE](LICENSE). The game client is proprietary; this addon only
uses the client addon interface under `Interface/AddOns`.

## Links

* Module: https://github.com/tortoise-wow-stack/TortoiseBots
* Core: https://github.com/Penqle/tortoise-wow
* Issues: https://github.com/tortoise-wow-stack/TortoiseBotsManager/issues
