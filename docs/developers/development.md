---
id: developers-development
title: Development
category: developers
summary: File map, tests, packaging, releases and keeping the addon in step with the module.
tags: [development, tests, release, files]
relates_to:
  - developers-protocol
  - docs-index
---

# Development

Plain Vanilla 1.12 Lua (Lua 5.0 API in the client): no libraries, no Ace. Copy the folder into `Interface/AddOns/` to try a change; new files need a full client restart.

## Files

| File | What it holds |
| :--- | :--- |
| `TortoiseBotsManager.toc` | Load order, version, saved variables (`TortoiseBotsDB`) |
| `Constants.lua` | Version, every action (label, icon, tooltip, intent), formations, CC marks, behaviours, timings |
| `Utils.lua` | Helpers and class roles |
| `Core.lua` | Sending commands, pull timers, formations, slash commands, load events |
| `Comms.lua` | Transport choice, inbound routing, `TBM:` line and chat reply parsing |
| `Roster.lua` | Roster, claimed-bot and CC snapshots; lifecycle state |
| `UI.lua` | Main window and all tabs |
| `BotPanel.lua` | Bot panel: live bot state, gear, bags, behaviour, spells |
| `BotNpc.lua`, `BotVault.lua` | NPC errands and flights; bank and mail lists |
| `BotRun.lua` | Dungeon tab and run window |
| `ServerInfo.lua` | Info window |
| `MiniBar.lua`, `Minimap.lua` | Mini bar with favourites; minimap button |
| `Bindings.xml`, `Bindings.lua` | Key bindings |

New buttons for party orders go into `TB.C.ACTION_DEFINITIONS` in `Constants.lua`; the Fight/Camp tabs and the mini bar are built from it.

## Tests

```bash
lua5.1 tests/regression.lua .
```

A mock of the 1.12 widget API runs the real addon files. The release workflow runs the same command and stops on failure.

Docs check:

```bash
python3 tools/verify_okf.py
```

It checks frontmatter, the `relates_to` graph, the manifest and every relative link. Run it after changing anything under `docs/`.

## Release

The **Generate Changelog & Release** workflow (manual, owner only) runs the tests, writes `CHANGELOG.md`, bumps the version in `Constants.lua` and the `.toc`, packages the zip with `tools/package_addon.py` (only `.lua`, `.toc`, `.xml`, textures, `README.md` and `LICENSE`; no docs, tests or tools) and posts the changelog to Discord.

## Keeping in step with the module

- The module defines every command and `TBM:` line ([protocol](protocol.md)). Change the module first, then the addon.
- When a button, tab or tooltip changes, update the matching page in `docs/play/` and the module's [addon page](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/addon.md) if players see the difference.
- New server-gated features need a capability token, so the addon stays usable on older servers.
