---
id: play-getting-started
title: Getting Started
category: play
summary: Requirements, install, first login of a bot and how orders are scoped.
tags: [install, setup, quickstart]
relates_to:
  - play-features
  - play-party-roster
  - play-controls
---

# Getting Started

## Requirements

- A **Vanilla 1.12 (11200)** client for Tortoise WoW 1.18.1.
- A server running the [TortoiseBots](https://github.com/Sagiroth/TortoiseBots) module. Without it the buttons do nothing. Server side setup: [module Getting Started](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/getting-started.md).

## Install

1. Download `TortoiseBotsManager.zip` from the [latest release](https://github.com/Sagiroth/TortoiseBotsManager/releases/latest).
2. Extract it into `World of Warcraft/Interface/AddOns/`. The result must be `Interface/AddOns/TortoiseBotsManager/TortoiseBotsManager.toc`, not a folder inside a folder.
3. Start the game and type `/tbm`, or click the minimap button.

After an update, quit and restart the client. WoW only loads newly added addon files on a full restart; `/reload` is not enough.

## Your first bot

1. Open `/tbm` and go to **Roster**. It lists the other characters on your account.
2. Tick one and click **Login**. It logs in as a bot (no game client needed).
3. Click **Invite**. Once it joins your group it shows up on **Party** and follows you.
4. Go to **Fight** and target an enemy: **Attack**, **Pull**, **Stop**.

You can also hire mercenaries at inn recruiters; they appear in your party the same way. See [roster and hiring](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md) in the module docs.

## Who an order goes to

- By default an order goes to **all your bots in the party**.
- **Target one of your bots** and orders go to that bot only. The Fight tab shows the current scope at the top.
- The server checks every order. If a bot cannot do it, the status line and the [Log tab](controls.md#log-tab) say why.

## Next

- [Every feature at a glance](features.md)
- [All Fight and Camp buttons](fight-and-camp.md)
