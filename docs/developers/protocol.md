---
id: developers-protocol
title: Addon Protocol
category: developers
summary: Addon command transport, capability gating and the TBM protocol lines the addon reads.
tags: [protocol, transport, capabilities, tbm-lines]
relates_to:
  - developers-development
  - play-features
---

# Addon Protocol

The module owns the protocol; this page lists what the addon uses. The full grammar is in the module's [addon page](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/addon.md#synchronization-streams) and [host API](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/developers/host-api.md#addon-command-transport). If the two disagree, the module wins and the addon is fixed.

## Transport

- Every click becomes one command string such as `action pull 10` or `inv Aran`.
- While the last roster reply carried `TBM:TRANSPORT|party`, the addon sends it as an addon message (prefix `TBM`, channel `PARTY`). Nothing appears in chat.
- Otherwise (`TBM:TRANSPORT|none`: ungrouped, a battleground group, or an older server) it sends `.bot <command>` as chat.
- Replies come back on the same transport: addon messages, or system chat lines.
- Sends are spaced at least 0.35 s apart; the roster poll is throttled to once per 5 s.

## Capabilities

`TBM:CAPS|<token>,...` replaces the known set each time it arrives. The addon hides or greys features the server does not list.

| Token | Gates |
| :--- | :--- |
| `pull-seconds` | Pull and pullback timers (without it, plain `pull` / `pullback`) |
| `flee` | Flee button and key binding |
| `inventory` | Bag icons and the bot panel |
| `claimed-roster` | Guild tab data |
| `guild-orders` | Guild order window, row status and the `.bot order` sends |
| `dungeon-run` | Dungeon tab and run window (server needs `DungeonSelfClear` and `RemoteCommander`) |

`behavior` is also advertised; the addon does not gate on it.

## Lines the addon reads

| Line | Used for |
| :--- | :--- |
| `TBM:TRANSPORT` | Choose addon channel or chat |
| `TBM:CAPS`, `TBM:VERSION` | Feature gates, server version in the header and Info window |
| `TBM:ROSTER_BEGIN` / `ROSTER` / `ROSTER_END`, `TBM:ROSTER_ERROR` | [Roster tab](../play/party-roster-guild.md#roster-tab); the server is the only roster authority |
| `TBM:ALTBOTS` | Alt-bot markers on the roster |
| `TBM:CLAIMED_BEGIN` / `CLAIMED` / `CLAIMED_END` | [Guild tab](../play/party-roster-guild.md#guild-tab) |
| `TBM:BOTSTATE_BEGIN` / `BOTSTATE` / `BOTSTATE_END` | Move mode lamps, party switch states, behaviour switches, live spec for role buttons |
| `TBM:CC_ASSIGN_BEGIN` / `CC_ASSIGN` / `CC_ASSIGN_END` | CC mark icons on party rows |
| `TBM:INV_BEGIN` / `INV_EQ` / `INV_ITEM` / `INV_END` | [Bot panel](../play/bot-panel.md) gear and bags |
| `TBM:ACTION_ACK`, `TBM:ACTION_ERR` | Status line and Log tab result of each order |
| `TBM:RUN` | [Dungeon run](../play/dungeon-run.md) status |
| `TBM:ORDER_BEGIN` / `ORDER` / `ORDER_END` | [Guild orders](../play/party-roster-guild.md#guild-orders): full list inside the pair, live one-bot update outside it; rows carry a trailing difficulty (`easy` / `medium` / `hard`, `-` or missing on old servers); `timeout` means the farm time ran out |
| `TBM:ORDER_ITEMS_BEGIN` / `ORDER_ITEM` / `ORDER_ITEMS_END` | Guild order search results with the same trailing difficulty plus a trailing category (`herb` / `ore` / `leather` / `fish` / `cloth` / `drop` / `other`, missing on old servers; an empty pair is a real answer); an `elite` verdict means only from elite creatures; search takes `cat=<kind>` with optional empty text (an old server answering `invalid` is retried without it) |
| `TBM:FEATURE`, `TBM:CONFIG_BEGIN` / `CONFIG` / `CONFIG_END` | [Info window](../play/controls.md#info-window) |

Some replies have no structured line and are parsed from the bot's whisper text: spell list (`=== Spells ===`), flights (`=== Taxi ===`), bank (`=== Bank ===`), mailbox (`=== Mailbox ===`), plus lifecycle chat replies for older servers. Those patterns live in `Comms.lua`, `BotPanel.lua`, `BotNpc.lua` and `BotVault.lua` and must follow the module's wording.
