# TortoiseBots Manager
<img width="365" height="311" alt="2" src="https://github.com/user-attachments/assets/d35eaf72-9b88-462f-8f9a-7aa7051257e6" />
<img width="368" height="310" alt="1" src="https://github.com/user-attachments/assets/16607951-fdcf-4496-a752-cde89e25096d" />

Lightweight, **Vanilla 1.12 (11200)** addon to manage your bots [Tortoise WoW 1.18.1](https://github.com/tortoise-wow/tortoise-wow).

Actions use normal WoW targeting for gameplay intent. Roster is a server-owned lifecycle list for logging bots in/out and managing group membership; no combat controls are attached to rows.

> **Requires the server-side module:** [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots) (`modules/TortoiseBots`). The addon sends its UI commands over the addon command channel while the server advertises it, falls back to `.bot` chat, and consumes structured `TBM:` replies on the transport that carried the request.


---

## Features

* **Actions** — `Attack`, `Interrupt`, `Stop`, `Pull`, `Pullback`, `Come`, `Stay`, `Follow`, `Focus Skull`, `CC Mark` (Marks panel), and `AoE`.
* **Target-derived scope** — party bots by default; targeting a controllable owned bot narrows dynamic actions to that bot. The server remains authoritative.
* **Server-owned roster** — online and offline owned characters arrive from `.bot roster`, with class, lifecycle status, group membership, and reliable last-location metadata when available. A separate assignment snapshot supplies each live bot's current CC mark.
* **Lifecycle bar** — select multiple roster rows and use `Login`, `Logout`, `Invite`, `Kick`, or `Summon`; mixed selections execute only eligible rows.
* **Party roles** — assign class roles to bots or set your own tank/healer/DPS role from the Party tab; player selections are saved locally and sent to the server.
* **Quiet transport** — UI commands travel as addon messages while the server advertises the addon command channel, so a button click prints nothing to chat for you or anyone nearby; `.bot` chat stays for ungrouped or battleground-group cases and for hand-typed commands. Gameplay requests return one compact structured result instead of per-bot chat.
* **Compact UI** — `Actions` is the default tab; `Roster` has checkbox rows and no per-row combat controls. The draggable panel remembers position and supports `Esc` close, minimap toggle, search, and tooltips.
* **Compatibility** — legacy `.bot` commands and `.bot command` remain available server-side; the primary UI does not expose the advanced command console.

## Companion Module

This addon is the in-game half of:

**[Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots)** — optional native PlayerBots module for Tortoise WoW 1.18.1 (`tortoise-wow/tortoise-wow` + PR #438). It owns `BotManager`, bot records, `.bot` commands and class AI. The addon requires it.

```
Tortoise WoW core (Headless sessions #438 + addon message hooks #476)
        │
        │  addon command channel (prefix TBM) — ".bot" chat as fallback
        ▼
TortoiseBots module (server, authoritative)
        │
        │  addon replies or CHAT_MSG_SYSTEM, same transport as the request
        ▼
TortoiseBots Manager (in-game, /tbm, optimistic UI)
```

No module → addon loads but every action replies “TortoiseBots module not loaded” from the server.

## Use

* `/tbm` (primary) — toggle panel. Aliases `/tb` / `/tbot` / `/tortoise` still work.
* `/tbm list` — force a server roster refresh. `/tbm help` and `/tbm resetpos` remain available.
* **Actions** — use normal WoW target selection. With an enemy target, `Attack`, `Interrupt`, `Pull`, and `Pullback` operate on the party; `Interrupt` chooses one capable bot server-side. With an owned bot target, dynamic actions such as `Stay` and `Follow` operate only on that bot.
* **Pull timers** — small `− N s +` steppers under the `Pull` and `Pull back` buttons set the DPS delay before Pull (default 10 s) and the join delay before Pull back (default 3 s). Range 0–60 s, step 1 (shift-click = 5), persisted in SavedVariables. When the server advertises `pull-seconds` in its `TBM:CAPS|…` roster trailer the buttons send `pull <n>` / `pullback <n>`; older servers send no `CAPS` line and the buttons send the plain intents exactly as before.
* **Roster** — select one or more rows, then use the bottom `Login`, `Logout`, `Invite`, `Kick`, or `Summon` action. Disabled actions have no eligible selected rows.
* **Party** — use the player row's class-role buttons to tell bots whether you are tank, healer, or DPS. The selection sends `.bot role self <role>`; bot rows retain their existing role controls.
* **Focus / CC** — mark enemies with normal raid icons. Open `CC Mark` for the Marks panel: 8 rows (one per raid icon) showing the current owner, a `Next` button assigning the mark to the next online bot by explicit name (`cc <mark> <Bot>`), a per-row `X` clearing that mark's owner (`cc clear <Owner>`), and `Clear all` (`cc clear`). Ownership is exclusive server-side (one mark = one bot); the Party tab shows each bot's current CC icon.
* **Search** — filters the server snapshot by name.

## How it works (edge cases)

* `TBM:ROSTER_*` and `TBM:ACTION_*` system messages are parsed as structured state; legacy human-readable responses remain a compatibility fallback.
* Server-side ownership, Headless lifecycle, target validation, executor selection, and mature PlayerbotAI behavior are authoritative. The addon only disables obviously unavailable controls.
* Roster lifecycle operations remain individually acknowledged and time out instead of staying optimistic forever. Gameplay never loops over roster selection.
* Multi-bot Invite advances only after each bot is a real group member, not merely after the server creates its pending invite. Full normal parties upgrade to a raid before another owned bot is invited.
* Normal `.bot` command echoes and structured `TBM:` transport messages are hidden locally through the standard chat filter or the legacy chat dispatcher; critical system errors stay visible.
* UI commands use the addon command channel only while the server says so: every roster reply ends with `TBM:TRANSPORT|party` or `|none`. A group change invalidates that verdict, so the next command falls back to `.bot` chat until the server restates it; a battleground group with no pre-battleground group reports `none`, because the core never dispatches those addon messages to the module.

## Requirements

* **Game:** Tortoise WoW English 1.18.1 (Interface 11200).
* **Server:** TortoiseBots module built with `MODULE_TORTOISEBOTS=static` and core PR #438 (`SessionTransport::Headless`). Without it, `.bot` returns “unknown command”.

## Files

```
TortoiseBotsManager.toc
Constants.lua   — geometry, colors, delays, status
Utils.lua       — Trim, NormalizeName, backdrop, Status helpers
Core.lua        — slash commands, throttled transport (addon channel or `.bot` chat), roster polling, SavedVariables UI preferences
Roster.lua      — authoritative snapshot, live state, group membership, CC assignments, checkbox eligibility
Comms.lua       — addon command channel, structured `TBM:` responses plus legacy command parsing
UI.lua          — compact Actions/Roster/Party tabs and contextual lifecycle bar
Minimap.lua     — draggable minimap button
```

## Versions (per-merge builds)

Every merge to `main` stamps a build version `<UTC date>-v<N>` (e.g.
`2026-09-25-v1` is the first real merge that UTC day; the counter resets to
v1 daily and the workflow's own `[skip ci]` commits never count). It lives in
`Constants.lua` (`TB.C.VERSION`) and the `.toc` `## Version:` line, and the
workflow tags each merge commit (`git tag <version>`, lightweight, no
release). The daily `vYYYY-MM-DD` release and Discord post stay, but the tag
moves to the day's latest version commit and the notes open with the build
range (e.g. `Builds 2026-09-25-v1 – v7`).

In game: the addon prints its version on load, and the `/tbm` window header
shows `TBM <addon version> · server <server version>` from the server's
`TBM:VERSION|<version>` roster trailer (`.bot version` / `.bot help` answer it
too). `server ?` means the server predates the version reply — everything
else keeps working.

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
* Core: https://github.com/tortoise-wow/tortoise-wow
* Issues: https://github.com/Sagiroth/TortoiseBotsManager/issues
