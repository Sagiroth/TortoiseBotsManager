# Changelog

All notable changes to TortoiseBotsManager are documented here.

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
