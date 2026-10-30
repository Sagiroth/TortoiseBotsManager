---
id: play-dungeon-run
title: Dungeon Run
category: play
summary: The Dungeon tab and run window that drive the module's run leader.
tags: [dungeon, run-leader, preview]
relates_to:
  - play-features
  - developers-protocol
---

# Dungeon Run (Preview)

The **Dungeon** tab lets your bots run a dungeon from a stored plan. It drives the module's [run leader](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/commander.md#run-leader-bot-run).

## When it shows up

Only when the server advertises the `dungeon-run` capability, which needs [`AiPlayerbot.DungeonSelfClear`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/server/settings/dungeons-raids.md#aiplayerbotdungeonselfclear) and [`AiPlayerbot.RemoteCommander`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/server/settings/performance.md#aiplayerbotremotecommander) on. Without it there is no tab, no window and nothing is sent.

## Two ways to run

| Mode | Who leads | Best when |
| :--- | :--- | :--- |
| **Bots lead** | A bot tank leads and pulls; you stay in the party. Bind first (target the tank bot), then Start. | You heal or deal damage. |
| **I lead** | You walk where you like; bots pull the plan's packs near you, mark, crowd-control, rest and revive. No Bind needed: Start binds your party. Target a bot to make it the puller when your party has no bot tank. | You tank. |

The tab explains both, shows the current run, and has **Open run window**.

## Run window

| Section | What you do | Sends |
| :--- | :--- | :--- |
| Mode | Pick Bots lead or I lead. | |
| Party | Bind the lead bot and up to four more (bots lead), or bind the raid with its main tank. The raid bind shows its layout (`Main <tank> + N off`, full tank/healer lists in the chat's `Raid layout:` lines) under the row. | `.bot commander bind <lead> [<bot> ...] inparty`, `.bot commander bind <lead> raid`, `commander unbind`, `commander status` |
| Plan | Walk them to the nearest entrance, list and search plans, pick one. Raid plans group after the dungeon plans. | `.bot cmd enter near`, `.bot run list` |
| Controls | Start, Pause, Resume, Skip a step, Stop (bots stay where they are, still bound; optional reason). No boss stops the run before the first boss step (bots lead only). | `.bot run start [plan] [until boss] [player]`, `run pause`, `run resume`, `run skip`, `run stop [reason]` |
| Status | Live state lamp, step x/y, leg, phase, stop label and note. | reads `TBM:RUN`, `TBM:RAID_LAYOUT` |

**Bots lead:** any order you give the party (buttons, `.bot`, whispers) pauses the run until **Resume**; the window and status line say so. **I lead:** your orders never pause the run.

Module: [run leader details](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/dungeon-run-leader.md), [commander bind](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/commander.md#bot-commander-bind), [cmd enter](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/commander.md#bot-cmd-enter).
