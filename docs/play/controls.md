---
id: play-controls
title: Mini Bar, Keys and Commands
category: play
summary: Mini bar and favourites, key bindings, slash commands, minimap button, Info window and Log tab.
tags: [mini-bar, keybindings, slash, minimap, info, log]
relates_to:
  - play-fight-camp
  - play-getting-started
---

# Mini Bar, Keys and Commands

## Mini bar

**Mini** in the window header (or `/tbm mini`) swaps the window for a small draggable bar. **+** (or `/tbm full`) brings the window back; the choice survives a reload.

- Category icons (Engage, Pull & Focus, Move, Party switches, Tactics, Camp) open a flyout with the same actions as the [Fight and Camp tabs](fight-and-camp.md). The short bar under a category turns gold while its flyout is open; a thin line separates the categories from your favourites.
- **Right-click** an action in a flyout to pin it as a favourite on the bar; right-click a favourite to remove it.
- Actions follow the same rules as in the window: enemy-target actions are grey without an enemy target.
- **Direction:** right-click the turtle to stack the bar vertically or back horizontally; `/tbm minilayout [horizontal|vertical]` does the same (bare `/tbm minilayout` flips it).

## Key bindings

Under **Key Bindings → TortoiseBots Manager** in the game menu:

| Binding | Same as |
| :--- | :--- |
| Attack target, Stop combat, Interrupt target, Flee | Fight → Engage |
| Pull target, Pull target back (with your pull timers), Focus skull | Fight → Pull and focus |
| Follow, Stay, Come and hold | Fight → Move |
| Mini favourite 1–12 | The favourite in that slot on the mini bar (a bound key shows on the button and in its tooltip) |
| Toggle window, Toggle mini bar | `/tbm`, `/tbm mini` |

## Slash commands

`/tbm`, `/tb`, `/tbot` and `/tortoise` all work.

| Command | Does |
| :--- | :--- |
| `/tbm` | Open or close the window |
| `/tbm mini`, `/tbm full` | Mini bar or full window |
| `/tbm minilayout [horizontal\|vertical]` | Stack the mini bar sideways or upright (no word flips it) |
| `/tbm bags [name]` | [Bot panel](bot-panel.md) of that bot, or of your target |
| `/tbm party`, `/tbm log` | Jump to that tab |
| `/tbm list` | Ask the server for a fresh roster |
| `/tbm resetpos` | Move the window and mini bar back to default |
| `/tbm help` | List the commands |

Hand-typed `.bot` commands keep working next to the addon. Module: [all commands](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/README.md).

## Minimap button

Left-click opens or closes the window, right-click refreshes the roster, drag to move. The tooltip shows how many bots are online.

## Info window

The window header shows the addon version once, next to the title, and under it the credit and, when the server module reports a semantic version (`1.12.0`), that version. The footer at the bottom of the window is the status line: the last reply or reason, green when it worked, red when it did not.

**Info** in the window header shows what the server has switched on (dungeon runs, hiring, world buffs and more) and the module version. The **All** tab searches every bot setting by name. Sends `.bot features` and `.bot features all <text>`. Module: [`.bot features`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-features).

## Log tab

The last 150 bot messages and server replies, with time stamps; **Clear** empties it. Kept across reloads. Useful when a button seems to do nothing: the reason is usually here.
