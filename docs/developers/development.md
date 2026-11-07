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
| `Media/*.tga` | Interface glyphs (close, check, search, gradient), drawn by `tools/make_media.py` |
| `Bindings.xml`, `Bindings.lua` | Key bindings |

### Look and feel

`Utils.lua` holds the theme (colours in `TB.C.THEME` in `Constants.lua`): `TB.ApplySurface(frame, "window"|"card"|"row"|"input")` for flat 1px-framed surfaces, `TB.AddWindowHeader`, `TB.StyleButton(button, kind)` with kinds `action`, `mode` (outlined choice), `primary`, `danger`, `TB.StyleTab`, `TB.StyleCloseButton`, `TB.StyleEditBox(box, placeholder)` and `TB.StyleCheckButton`. Use them for new windows instead of the stock templates' art so everything matches. Gold means picked or primary; labels are light; section titles use `color("title")`. A Media texture only loads after a full client restart, so `TB.SetMediaTexture` falls back to stock art when the file is missing.

New buttons for party orders go into `TB.C.ACTION_DEFINITIONS` in `Constants.lua`; the Fight/Camp tabs and the mini bar are built from it.

## Tests

```bash
lua5.1 tests/regression.lua .
lua5.1 tests/lua50_syntax.lua .
```

`lua50_syntax.lua` also runs `luac5.1 -l` on every file and fails on any function with more than 32 upvalues: Lua 5.0 (the 1.12 client) refuses those with `too many upvalues (limit=32)` while 5.1 loads them. When it fires, move a block of the function into its own local function.

### UI previews

`tools/preview/` renders every window and tab to PNG without the game: a recording mock of the 1.12 widget API (`mock.lua`), a script that loads the addon on it with a sample party, roster and guild (`scenes.lua`), and a canvas renderer that resolves anchors and paints backdrops, textures and text (`render.js`, Playwright's Chromium).

```bash
tools/preview/run.sh <out dir> <asset dir> [scene ...]
```

`<asset dir>/fonts` must hold the client's `FRIZQT__.ttf` and `ARIALN.ttf` (not in the repo); textures are downloaded into `<asset dir>/tex` from the community interface-art export. Use it to check a layout change before trying it in game.

A mock of the 1.12 widget API runs the real addon files. `lua50_syntax.lua` tokenizes every `.toc` file and fails on Lua 5.1-only syntax (`%`, `#`, `select('#'`, `gmatch`, `goto`) that the 1.12 client rejects. The release workflow runs both commands and stops on failure.

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
