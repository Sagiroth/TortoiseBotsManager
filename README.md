# TortoiseBots Addon

Lightweight, nice-looking **Vanilla 1.12 (11200)** addon to control your owned bots on [Tortoise WoW 1.18.1](https://github.com/Penqle/tortoise-wow) — without typing in chat.

Press buttons instead of `/.bot` commands. List your alts, see who is online/starting/offline, and summon / follow / stay / group / pull.

> **Requires the server-side module:** [tortoise-wow-stack/TortoiseBots](https://github.com/tortoise-wow-stack/TortoiseBots) (`modules/TortoiseBots`). The addon is a pure UI front-end — it sends `.bot …` chat commands and parses `CHAT_MSG_SYSTEM` replies. It does not work without the module.

![TortoiseBots panel](https://raw.githubusercontent.com/tortoise-wow-stack/TortoiseBots-Addon/main/.github/preview.png)

---

## Features

* **Roster you own** — remembers your alt names (same account) via `SavedVariables`. Auto-discovers bots seen in `.bot list`.
* **State** — `Offline → Starting → Online` (+ `Summoning…` / `Inviting…`), with `Random`/`AI` hint and group membership.
* **Spawn / Despawn** — `.bot add` / `.bot remove` from an input box or per-row Spawn button (same-account check stays server-side).
* **Per-bot actions** — `Summon` (`.bot summon`), `Follow` / `Stay`, `Invite`/`Kick` (`.bot invite/uninvite`), `Remove` (`.bot remove`).
* **Bulk** — `Summon All`, `Follow All`, `Stay All`, `Invite All`, `Uninvite All`.
* **Selection bar** — click a row to drive one bot; `Pull` (` .bot pullback`) uses your current target and the tank in your party.
* **Nice looking & simple** — 520×520 dark parchment panel (gold/blue, like Turtle), draggable, `Esc` closes, remembers position, minimap button, search filter, tooltips.
* **Correct** — throttled sends (350 ms), throttled polls (5 s hard, 8 s panel / 20 s hidden), 2-poll anti-flicker for offline, right-click row to forget offline, all server checks honoured (combat/taxi/teleport/group).

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
        │  CHAT_MSG_SYSTEM replies
        ▼
TortoiseBots addon (client, optimistic UI)
```

No module → addon loads but every action replies “TortoiseBots module not loaded” from the server.

## Install

1. Download or `git clone` this repo into your client:
   ```
   <TurtleWoW>/Interface/AddOns/TortoiseBots/
   ```
   The folder must be named `TortoiseBots` (so the `.toc` is found).
2. Restart the client fully (Vanilla loads addons at startup).
3. Log in — you should see `TortoiseBots v0.1.0 loaded. /tb to open.` in chat.

### From this repo

```bash
git clone https://github.com/tortoise-wow-stack/TortoiseBots-Addon.git
cp -r TortoiseBots-Addon "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBots"
# or symlink
ln -s "$(pwd)/TortoiseBots-Addon" "/mnt/ssd/TurtleWoW eng client 1.18.1/Interface/AddOns/TortoiseBots"
```

## Use

* `/tb` / `/tbot` / `/tortoise` — toggle panel.
* `/tb list` — force poll, `/tb help`, `/tb resetpos`.
* **Minimap button** — left-click toggle, right-click refresh, drag to move (80 px ring).
* **Add bot** — type exact alt name (same account) → `Spawn`. Server replies `queued for login; it will follow you`.
* **Row** — left-click select, double-click follow, right-click (when offline) forget. Per-row: `Summ/Spawn`, `Fol`, `Inv/Kick`, `Stay`, `X` (despawn).
* **Search** — filters by substring.

## How it works (edge cases)

* `CHAT_MSG_SYSTEM` scraping is lenient — matches both `Name: in world, random 0, AI 1` list lines and action replies (`Summoning`, `Invitation sent`, `already online`, `cannot be summoned`, etc.). Missing bot in two consecutive `list` polls → marked offline (avoids flicker on lag).
* All precondition checks (alive/combat/taxi/teleporting/group-full) are re-checked server-side; addon disables buttons early for UX but treats server reply as truth and rolls back optimistic `summoning`/`inviting` on failure.
* Rate: one `.bot` per 350 ms, one `list` per 5 s. Bulk actions queue.

## Requirements

* **Client:** Turtle WoW English 1.18.1 (Interface 11200).
* **Server:** TortoiseBots module built with `MODULE_TORTOISEBOTS=static` and Headless PR #411 (`SessionTransport::Headless`). Without it, `.bot` returns “unknown command”.

## Files

```
TortoiseBots.toc
Core.lua      — slash, throttle, poll, SavedVariables
Roster.lua    — roster + live state + group tracking
Comms.lua     — build .bot and parse system messages
UI.lua        — 520×520 panel, rows, bulk & selection bars
Minimap.lua   — draggable minimap button
```

## Roadmap

* v0.2 — optional server seam `.bot listowned` (offline roster + level/class/spec) and addon-channel `TB:OWN|…` so you don't have to type alt names; distance/health column.
* Future — strategy presets, per-bot talent/gear hint (requires module surface).

## Licence

MIT — see `LICENCE.md` in the module repo. Turtle client is proprietary — this addon only touches `Interface/AddOns`.

## Links

* Module: https://github.com/tortoise-wow-stack/TortoiseBots
* Core: https://github.com/Penqle/tortoise-wow
* Issues: https://github.com/tortoise-wow-stack/TortoiseBots-Addon/issues
