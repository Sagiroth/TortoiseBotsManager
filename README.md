# TortoiseBots Manager

[![Latest release](https://img.shields.io/github/v/release/Sagiroth/TortoiseBotsManager?label=release&logo=github)](https://github.com/Sagiroth/TortoiseBotsManager/releases/latest)
[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/sagiroth)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white)](https://discord.gg/FT2rZcXm3)

The in-game control panel (`/tbm`) for [TortoiseBots](https://github.com/Sagiroth/TortoiseBots), the PlayerBots module for **Tortoise WoW 1.18.1**. A Vanilla 1.12 (11200) addon: log your alts in as bots, group them, and command them with buttons instead of typing `.bot` commands. This is an unofficial, community-driven project, not affiliated with Turtle WoW or Blizzard Entertainment.

> [!IMPORTANT]
> The addon only works on a server running the [TortoiseBots](https://github.com/Sagiroth/TortoiseBots) module. New to TortoiseBots? Start with its [Getting Started](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/getting-started.md) guide.

## 📦 Install

1. Download `TortoiseBotsManager.zip` from the [latest release](https://github.com/Sagiroth/TortoiseBotsManager/releases/latest).
2. Extract it into `World of Warcraft/Interface/AddOns/`, so the folder is `Interface/AddOns/TortoiseBotsManager` (not nested twice).
3. Start the game and type `/tbm`.

After an update, restart the game client fully: WoW loads new addon files only on a restart, not on `/reload`.

## ✨ What's inside

| Tab | What it's for |
| :--- | :--- |
| **Fight** | Attack, stop, interrupt, flee, pull and pull back, focus and CC marks, movement orders, party switches (AoE, auto CC, loot, sap, spread) and tactics. |
| **Camp** | Between pulls: rest, ready check, repair, sell junk, train, release and corpse run, rebuff, formations, quests and grinding. |
| **Party** | Your group and its roles; opens each bot's gear and bags. |
| **Guild** | Bots you claimed into your guild as raid alts. |
| **Roster** | Your account's characters: log in, log out, invite, kick, summon; fill party or raid. |
| **Raid** | Shown only in a raid: raid tactics and loaded boss tactics. |
| **Dungeon** | Shown only when the server enables it: let your bots run a dungeon, with bots or you leading. |
| **Log** | Recent bot messages and server replies. |

- **Bot panel** — paper doll, bags with upgrade markers, equip, trade, use, mail or bank items, per-bot behaviour switches, spells, NPC errands and flights. Open it from a Party row, the `Gear & bags` button, or `/tbm bags <name>`.
- **Mini mode** — `Mini` (or `/tbm mini`) swaps the window for a small bar of fight buttons and favourites.
- **Quiet** — button clicks travel as addon messages, so nothing shows up in chat for you or anyone nearby.

Targeting one of your bots narrows the orders to that bot; otherwise they go to the whole party. Full guide: [TortoiseBotsManager addon](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/addon.md) and [Bot panel](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md).

### Slash commands

| Command | Does |
| :--- | :--- |
| `/tbm` | Open or close the window |
| `/tbm mini` / `/tbm full` | Small fight bar / full window |
| `/tbm bags [name]` | Gear and bags of a bot (or your target) |
| `/tbm party`, `/tbm log` | Jump to that tab |
| `/tbm resetpos` | Move the window back to the centre |
| `/tbm help` | List the commands |

## 🖼️ Screenshots

<img width="485" height="166" alt="TortoiseBots Manager screenshot" src="https://github.com/user-attachments/assets/4f4c7ce6-9f06-4423-81e4-229134ffbdb3" />
<img width="413" height="371" alt="TortoiseBots Manager screenshot" src="https://github.com/user-attachments/assets/aff0f250-4760-4f2c-9b43-8d7ef89f023c" />
<img width="653" height="400" alt="TortoiseBots Manager screenshot" src="https://github.com/user-attachments/assets/ead1050e-9b3d-4e15-9fa1-5868cb3c0da0" />

## 🙏 Credit

TortoiseBots Manager and the TortoiseBots module are made by **Sagiroth**. Forks, repacks, bundles and videos are welcome — please credit them and keep the in-addon credit (window header, load message, `/tbm help`). Ready to paste:

```text
TortoiseBots + TBM addon by Sagiroth — https://github.com/Sagiroth/TortoiseBots
```

### ☕ Support

If you enjoy TortoiseBots and would like to support its development, you can buy me a coffee on [**Ko-fi**](https://ko-fi.com/sagiroth). It's completely optional: every feature stays free and open for everyone.

## 📜 License

MIT — see [LICENSE](LICENSE). Bugs and ideas: [issues](https://github.com/Sagiroth/TortoiseBotsManager/issues) or [Discord](https://discord.gg/FT2rZcXm3).

**Disclaimer:** This repository contains addon source code only; it ships no game files and runs no game service. It is not affiliated with Turtle WoW or Tortoise WoW. World of Warcraft is a trademark of Blizzard Entertainment; this project is not affiliated with Blizzard.
