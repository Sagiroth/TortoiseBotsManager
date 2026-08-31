# TortoiseBots Manager

Lightweight, nice-looking **Vanilla 1.12 (11200)** addon to control your owned bots on [Tortoise WoW 1.18.1](https://github.com/Penqle/tortoise-wow) — without typing in chat.

Press buttons instead of `/.bot` commands. List your alts, see who is online/starting/offline, and summon / follow / stay / group / pull.

> **Requires the server-side module:** [tortoise-wow-stack/TortoiseBots](https://github.com/tortoise-wow-stack/TortoiseBots) (`modules/TortoiseBots`). The addon is a pure UI front-end — it sends `.bot …` chat commands and parses native system plus bot whisper replies. It does not work without the module.

![TortoiseBots Manager panel](https://raw.githubusercontent.com/tortoise-wow-stack/TortoiseBotsManager/main/.github/preview.png)

---

## Features

* **Roster you own** — remembers your alt names (same account) via `SavedVariables`. Auto-discovers bots seen in `.bot list`.
* **State** — `Offline → Starting → Online`, with `Queued`, `Working`, `Summoning…`, `Inviting…`, `Kicking…`, `Removing…`, `Unknown`, and `Failed` states plus `Random`/`AI` and group hints.
* **Spawn / Despawn** — `.bot add` / `.bot remove` from an input box or per-row Spawn button (same-account check stays server-side).
* **Per-bot quick** — `Summ`/`Spawn`, `Follow`, `Invite`/`Kick`, `X` Remove — one click per row.
* **Party** — filtered `Summon` / `Follow` / `Invite` / `Kick` bulk actions plus target-aware `Pullback`.
* **Public controls** — selected-bot `Follow`, `Stay`, `Guard`, `Free`, `Attack`, `Ready`, `Formation`, and `Status` buttons; controls not advertised by `.bot help` stay disabled.
* **Server tools** — explicit `Stats` / `Help` buttons, plus an `Advanced AI` box for the full transitional `.bot command` surface. Forwarded AI replies appear in the status line and remain in a short in-memory history.
* **Nice looking & simple** — 520×520 dark parchment with themed **TortoiseBots Manager** title (gold + turtle green), draggable, `Esc` closes, remembers position, minimap button, search filter, tooltips.
* **Correct** — throttled sends (350 ms), throttled polls (5 s hard, 8 s panel / 20 s hidden), operation timeouts, stale-reply protection, 2-poll anti-flicker for offline, right-click row to forget offline, and server checks honoured (combat/taxi/teleport/group).

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
3. Log in — you should see `TortoiseBots Manager v0.1.2 loaded. /tbm to open.` in chat.

### From this repo

```bash
git clone https://github.com/tortoise-wow-stack/TortoiseBotsManager.git
cp -r TortoiseBotsManager "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBotsManager"
# or symlink
ln -s "$(pwd)/TortoiseBotsManager" "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBotsManager"
```

## Use

* `/tbm` (primary) — toggle panel. Aliases `/tb` / `/tbot` / `/tortoise` still work.
* `/tbm list` — force poll, `/tbm help`, `/tbm resetpos`.
* **Minimap button** — left-click toggle (`/tbm`), right-click refresh, drag to move (80 px ring).
* **Add bot** — type exact alt name (same account) → `Spawn`. Server replies `queued for login; it will follow you`.
* **Row** — left-click select, right-click (when offline) forget. Per-row: `Summ`/`Spawn`, `Follow`, `Invite`/`Kick`, `X` (despawn).
* **Party bar** — bulk actions apply to filtered rows; pending, unknown, failed, and inapplicable bots are skipped. `Pullback` uses your current living target and lets the server choose an eligible tank.
* **Server tools** — `Stats` and `Help` send `.bot stats` and `.bot help`; help discovery also gates optional public controls.
* **Selected bar** — click a row, then use the public movement/combat/status buttons. `Attack` and `Pullback` require a living target. `Advanced AI` forwards a mature Playerbot command and shows its reply when the bot whispers back.
* **Search** — filters by substring.

## How it works (edge cases)

* `CHAT_MSG_SYSTEM` scraping is lenient — matches list/status lines and native action replies. Advanced `.bot command` responses are accepted from `CHAT_MSG_WHISPER` and `CHAT_MSG_ADDON` while a command is pending.
* All precondition checks (alive/combat/taxi/teleporting/group-full) are re-checked server-side; the addon disables buttons early for UX and treats matching server replies as truth.
* Named operations time out instead of remaining permanently optimistic. A late reply cannot overwrite a newer operation, and repeated silent list polls show `Unknown` rather than falsely claiming the bot is online.
* Rate: one `.bot` per 350 ms, one `list` per 5 s. Bulk actions queue eligible work and skip pending operations.

## Requirements

* **Client:** Turtle WoW English 1.18.1 (Interface 11200).
* **Server:** TortoiseBots module built with `MODULE_TORTOISEBOTS=static` and Headless PR #411 (`SessionTransport::Headless`). Without it, `.bot` returns “unknown command”.

## Files

```
TortoiseBotsManager.toc
Constants.lua   — geometry, colors, delays, status
Utils.lua       — Trim, NormalizeName, backdrop, Status helpers
Core.lua        — slash (/tbm), throttle, poll, SavedVariables
Roster.lua      — roster + live state + group + poll reconcile
Comms.lua       — build .bot and parse system messages
UI.lua          — 520×520 panel, rows, public controls, Party & Selected bars
Minimap.lua     — draggable minimap button
```

## Development check

Run the Vanilla-compatible regression harness from the addon root:

```bash
lua5.1 tests/regression.lua .
```

## Roadmap

* v0.2 — optional server seam `.bot listowned` (offline roster + level/class/spec) and addon-channel `TB:OWN|…` so you don't have to type alt names; distance/health column.
* Future — strategy presets, per-bot talent/gear hint (requires module surface).

## Licence

MIT — see `LICENCE.md` in the module repo. Turtle client is proprietary — this addon only touches `Interface/AddOns`.

## Links

* Module: https://github.com/tortoise-wow-stack/TortoiseBots
* Core: https://github.com/Penqle/tortoise-wow
* Issues: https://github.com/tortoise-wow-stack/TortoiseBotsManager/issues
