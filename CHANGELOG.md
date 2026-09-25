# Changelog

All notable changes to TortoiseBotsManager are documented here.

## 2026-09-25

### Tactical & Actions
- New **CC Marks panel** replaces the old target-first picker — open it from the Actions tab's "CC Mark" button and assign marks without targeting a bot first. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- Eight rows, one per raid icon, each showing the mark's current owner at a glance. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **Next** per row sends `cc <mark> <Bot>`, cycling through bots by name so you can rotate marks without retyping names. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **X** per row sends `cc clear <Owner>` to release a single mark. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **Clear all** at the bottom sends `cc clear` to wipe every assignment in one click. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)

### UI & Controls
- Panel stays open across target changes, so you can hand out several marks in one pass. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- "CC Mark" button is now a plain label — no more hardcoded Moon icon misleading you about the current assignment. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)

---

### Build & Versioning
- Per-merge build versions (`<UTC date>-v<N>`) are now stamped into `Constants.lua` (`TB.C.VERSION`) and the `.toc` `## Version:` field on each `[skip ci]` bot commit, with a lightweight tag per build — no more guessing which build you're running. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)
- The daily release, zip and Discord post stay in place, and the daily tag moves to the latest build. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)
- `/tbm` now displays `TBM <addon version> · server <server version>`, with the server version read from the module's `TBM:VERSION|…` line. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)

### CI & Releases
- The build-version workflow now actually completes: stamped version files are committed before `git pull --rebase`, so the run no longer aborts on unstaged changes. [#25](https://github.com/Sagiroth/TortoiseBotsManager/pull/25)
- Releases are only created or edited when notes were actually written; the daily tag still moves to the latest build. [#25](https://github.com/Sagiroth/TortoiseBotsManager/pull/25)
- Build range now shows up in titles: releases list as `<repo> <date> (builds v1–vN)` and the Discord embed as `<repo> build <date>-vN`, with the link still pointing at the daily release. [#26](https://github.com/Sagiroth/TortoiseBotsManager/pull/26)

### Tactical & Actions
- Pull and Pull back now accept an adjustable timer: set a pull DPS delay (default 10 s) and a pullback join delay (default 3 s), each tunable from 0-60 s, so your bots engage and regroup on your schedule instead of a fixed cadence. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Timers are sent as `pull <n>` / `pullback <n>` commands, keeping the same command/addon transport you already use, so nothing changes in how you issue orders. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

### UI & Controls
- New compact "- N s +" steppers sit directly under the Pull and Pull back buttons in the Actions tab, styled to match the existing panel buttons; shift-click steps by 5 for fast coarse adjustment. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Tooltips on the steppers explain what each delay controls, so group leaders can tune timing without guessing. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

### Comms & Protocol
- Both delays persist as SavedVariables, so your preferred timings are remembered across sessions. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Timed pulls are only sent when the server advertises `pull-seconds` in its `TBM:CAPS` roster trailer; the capability list is parsed robustly. On older servers without it, the addon falls back to plain pull/pullback intents exactly as before — no breakage. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

## 2026-09-24

### UI & Controls
- Added one-click player role override buttons on your row in the Party tab, using your class’s available roles so you can swap without leaving `/tbm`. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)
- Selected role now highlights in gold for instant feedback. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

### Tactical & Actions
- Clicking a role button sets `TortoiseBotsDB.playerRole` and issues `.bot role self <tank|healer|dps>` to the server. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

### Testing & Docs
- Added unit and regression coverage in `tests/regression.lua`, and updated README and CHANGELOG. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

---

## 2026-09-23

### UI & Controls

- Window dragging is now isolated to the title/header bar only — clicking action buttons like **Attack** no longer starts an accidental frame drag. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)
- Eliminated the fatal client crash (**ERROR #132 ACCESS_VIOLATION**) caused by `StopMovingOrSizing()` re-anchoring the main dialog during unintended drags. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)
- Buttons and controls inside the dialog now respond reliably without moving the parent window. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)

### Roles & Party

- The Party tab now exposes player role buttons, persists the selected display role, and sends `.bot role self <tank|healer|dps>`. [#264](https://github.com/Sagiroth/TortoiseBots/issues/264)

---

## 2026-09-22

### Comms & Protocol
- Summon rejections caused by the server's GM-gate are now recognized, so the optimistic `SUMMONING` state resolves to a visible failure instead of hanging until it times out. [#20](https://github.com/Sagiroth/TortoiseBotsManager/pull/20)
- Adds a `summonRestricted` pattern included in the summon-failure disjunction, mirroring the NonGmFreeSummon gate from TortoiseBots #255; regression.lua passes. [#20](https://github.com/Sagiroth/TortoiseBotsManager/pull/20)

---

## 2026-09-21

### CI, Docs & Project
- Added Discord issue alerts and an automated changelog/release pipeline. [#18](https://github.com/Sagiroth/TortoiseBotsManager/pull/18)
- Standardized public naming and docs on Tortoise WoW. [#15](https://github.com/Sagiroth/TortoiseBotsManager/pull/15)
- Fixed README links after ownership transfer and removed broken/personal paths. [#11](https://github.com/Sagiroth/TortoiseBotsManager/pull/11)
- Added MIT license and clarified the addon does not ship the game client/assets or run a hosted service. [#4](https://github.com/Sagiroth/TortoiseBotsManager/pull/4)

### Roles & Party
- Added a Party tab for viewing party members and one-click class role switching. [#10](https://github.com/Sagiroth/TortoiseBotsManager/pull/10)
- Tank button now forces `.bot role <name> tank`; Tank→DPS demotion clears forced role before applying the spec strategy. [#17](https://github.com/Sagiroth/TortoiseBotsManager/pull/17)

### Tactical & Actions
- Added an Interrupt button that sends exactly one `.bot action interrupt` and reports ACK/ERR results. [#13](https://github.com/Sagiroth/TortoiseBotsManager/pull/13)
- Added per-bot CC raid-mark assignment UI with all eight icons and live current-mark display on targetable party rows. [#14](https://github.com/Sagiroth/TortoiseBotsManager/pull/14)
- Added formation presets, Come & Hold, ready check, and hold/stack actions, and removed redundant roster refresh/filter buttons. [#8](https://github.com/Sagiroth/TortoiseBotsManager/pull/8)
- Made selected-bot controls state-aware for guard, free, attack, ready, formation, and status; moved pullback to target-scoped party controls. [#2](https://github.com/Sagiroth/TortoiseBotsManager/pull/2)
- Surface native pullback and master-assignment failures from reworked safe-summon/pullback responses. [#3](https://github.com/Sagiroth/TortoiseBotsManager/pull/3)

### UI & Controls
- Revamped Actions/Roster with card layout, class colors, icons, master select-all, and fixed roster anchoring/alt discovery. [#7](https://github.com/Sagiroth/TortoiseBotsManager/pull/7)
- Replaced the mixed Party/Roster UI with Actions and Roster tabs, authoritative snapshots, offline rows, multi-select, contextual Login/Logout/Invite/Kick/Summon, structured TBM parsing, and local chat filtering. [#6](https://github.com/Sagiroth/TortoiseBotsManager/pull/6)
- Compacted the panel to 500×395 with Party/Roster tabs, removed redundant AI Command/Add bars, and bumped to 1.0.0. [#5](https://github.com/Sagiroth/TortoiseBotsManager/pull/5)

### Comms & Protocol
- UI commands now go over the addon command channel when advertised, avoiding chat-frame and nearby-player spam; fallback remains `.bot` chat. [#16](https://github.com/Sagiroth/TortoiseBotsManager/pull/16)
- Added a timestamped bot activity log tab and filtered bot lifecycle announcements out of `/say`/General chat. [#9](https://github.com/Sagiroth/TortoiseBotsManager/pull/9)

### Core & Reliability
- Made the addon Vanilla 1.12-safe: button roster rows, safe partial init, fixed reconciliation timers/throttled queue, reconcile after `.bot list`, explicit Stats/Help/AI controls, optimistic rollback, and version 0.1.1. [#1](https://github.com/Sagiroth/TortoiseBotsManager/pull/1)
- Added core, comms, roster, and UI updates with regression coverage. [#12](https://github.com/Sagiroth/TortoiseBotsManager/pull/12)

---

### Roster & Lifecycle
- Raid roster changes now refresh reactively: the watcher listens to the 1.12-compatible `RAID_ROSTER_UPDATE` event instead of the Retail-only `GROUP_ROSTER_UPDATE`, so raid converts and subgroup shifts update group membership correctly. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)

### UI & Controls
- Fixed formation metadata being clobbered: structured `TB.C.FORMATIONS` now stays intact for id/label/tip lookups, while raw formation IDs live in `TB.C.FORMATION_IDS`, restoring formation labels and tooltips. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)

### Tactical & Actions
- Hunter Survival and Rogue Subtlety are back in `CLASS_ROLES`, matching backend strategy support so those specs can be assigned and recognized properly. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)
