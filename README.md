# TortoiseBots Manager

[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/sagiroth)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white)](https://discord.gg/FT2rZcXm3)

Lightweight, **Vanilla 1.12 (11200)** addon to manage your bots [Tortoise WoW 1.18.1](https://github.com/tortoise-wow/tortoise-wow).

Actions use normal WoW targeting for gameplay intent. Roster is a server-owned lifecycle list for logging bots in/out and managing group membership; no combat controls are attached to rows.

> **Requires the server-side module:** [Sagiroth/TortoiseBots](https://github.com/Sagiroth/TortoiseBots) (`modules/TortoiseBots`). The addon sends its UI commands over the addon command channel while the server advertises it, falls back to `.bot` chat, and consumes structured `TBM:` replies on the transport that carried the request.


---

## Features

* **Tabs by kind of work** — `Fight` (during a pull), `Camp` (between pulls), `Party`, `Roster`, `Guild` (claimed guild bots), `Raid` (only in a raid) and `Log`.
* **Fight** — `Attack`, `Stop`, `Interrupt`, `Flee`; `Pull` / `Pullback` with timers, `End pull`, `Focus Skull`, `CC Mark` (Marks panel); `Follow`, `Stay`, `Come & Hold`, `Guard`, `Free` plus combat-stance pills (`Near`, `Tank`, `Turnback`, `Behind`); party switches `AoE`, `Auto CC`, `Loot`, `Sap` and `Spread` that show the party's real state from the server (On / Off / Mixed, with a lamp); combat tactics `Kite`, `Auto Mark`, `Focus Fire` and `AoE Fear`.
* **Camp** — `Rest`, `Ready Check`, `Repair`, `Sell junk`, `Train` (at a targeted class trainer), a `Release` button that turns into `Corpse run` once your dead bots are ghosts, `Rebuff`, `Reset tactics`, `Drop totems`, all ten formations in two pill rows with a one-line description of the active one, and a `Quests` card (`Accept` / `Share` loop over grouped bots, `Grind` toggles autonomous grinding).
* **Mini mode** — the `Mini` button (or `/tbm mini`) swaps the window for a small draggable bar of fight icons; its `+` brings the window back. The mode survives a reload.
* **Bot panel (gear & bags)** — opened from the bag icon on a Party row, the `Gear & bags` button while a bot is targeted, or `/tbm bags <name>`. Paper doll with the bot's 3D model and durability, a bag grid with upgrade markers, one-click `Equip` / `Unequip` / `Give to me` (the item goes straight into a trade window) / `Use` (the bot uses food, drink or a potion) / `Disenchant` / `Send by mail` / `Put to bank` / `Destroy` (asks first, cannot be undone), an `Equip upgrades` sweep, `Trade`, `Upkeep` (restock) and `Gear up` (re-gear from bags), a `Behaviour` tab with per-bot switches (loot, AoE, auto CC, save mana, cooldowns, threat, potions, mimic, spread out), a `Spells` tab listing what the bot can cast — click a spell to cast it, and `NPC` errands (`Talk`, `Bind home`, `Learn`, `Make leader`, flights list-and-pick). `Bank / mail` opens the vault: read-only bank and mailbox lists for that bot, click a row to take it.
* **Raid tab** — appears only while you are in a raid: `Tank face away`, `Douse runes`, Turtle custom raid tactics on/off, and a per-bot list of loaded boss tactics.
* **Guild tab** — wandering bots you claimed into your guild via `/ginvite` as personal raid alt-bots. Level 60 bots show a `[Locked]` gear badge (they never self-equip or auto-vendor — you gear them), leveling bots show `[Leveling]` (they equip upgrades but keep blues/epics). Checkbox multi-select with `Invite to Raid` / `Summon to Raid`, per-row role cycler (`.bot role`), backpack button opening that bot's gear & bags paperdoll, and a `Release` button that unclaims the bot back to the wandering pool via `/gkick`.
* **Target-derived scope** — party bots by default; targeting a controllable owned bot narrows dynamic actions to that bot. The server remains authoritative.
* **Server-owned roster** — online and offline owned characters arrive from `.bot roster`, with class, lifecycle status, group membership, and reliable last-location metadata when available. A separate assignment snapshot supplies each live bot's current CC mark.
* **Lifecycle bar** — select multiple roster rows and use `Login`, `Logout`, `Invite`, `Kick`, or `Summon`; mixed selections execute only eligible rows.
* **Party roles** — assign class roles to bots or set your own tank/healer/DPS role from the Party tab; player selections are saved locally and sent to the server.
* **Dungeon run (Preview)** — while the server enables its run leader, the Party tab shows `Dungeon run`: bind a lead bot + its group, walk them through the nearest entrance, pick a dungeon plan, `Start` / `Pause` / `Resume` / `Skip` / `Stop`, and watch the live status (state lamp, step x/y progress, leg, phase, note). Any order you give the party pauses the run until `Resume`.
* **Quiet transport** — UI commands travel as addon messages while the server advertises the addon command channel, so a button click prints nothing to chat for you or anyone nearby; `.bot` chat stays for ungrouped or battleground-group cases and for hand-typed commands. Gameplay requests return one compact structured result instead of per-bot chat.
* **Compact UI** — `Fight` is the default tab; `Roster` has checkbox rows and no per-row combat controls. The draggable panel remembers position and supports `Esc` close, minimap toggle, search, and tooltips.
* **Compatibility** — legacy `.bot` commands and `.bot command` remain available server-side; the primary UI does not expose the advanced command console.

## Credit

TortoiseBots Manager and the TortoiseBots module are made by **Sagiroth**.
Forks, repacks, bundles and videos are welcome — please credit them and keep the
in-addon credit (window header, load message, `/tbm help`). Ready to paste:

```text
TortoiseBots + TBM addon by Sagiroth — https://github.com/Sagiroth/TortoiseBots
```

### ☕ Support

If you enjoy TortoiseBots and would like to support its development, you can
buy me a coffee on [**Ko-fi**](https://ko-fi.com/sagiroth). It's completely
optional: every feature stays free and open for everyone.

## Screenshots

<img width="485" height="166" alt="image" src="https://github.com/user-attachments/assets/4f4c7ce6-9f06-4423-81e4-229134ffbdb3" />
<img width="413" height="371" alt="2" src="https://github.com/user-attachments/assets/aff0f250-4760-4f2c-9b43-8d7ef89f023c" />
<img width="653" height="400" alt="3" src="https://github.com/user-attachments/assets/ead1050e-9b3d-4e15-9fa1-5868cb3c0da0" />

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
