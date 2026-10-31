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
| `dungeon-run` | Dungeon tab and run window (server needs `DungeonSelfClear` and `RemoteCommander`); raid binds ride the same gate |
| `loot-log` | Loot tab and the `.bot lootlog` catch-up |
| `downtime` | Downtime button for own-alt errands (`.bot downtime`) |

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
| `TBM:RUN` | [Dungeon run](../play/dungeon-run.md) status (a stop-before-boss run appends `until boss (step N)`) |
| `TBM:RAID_LAYOUT` | [Dungeon run](../play/dungeon-run.md) raid layout (`<bots>|<tanks>|<tankHealers>|<raidHealers>|<groups>`, tanks main first) and `warning|<text>` lines; the bind ACK scope is `raid` |
| `TBM:LOOT_BEGIN` / `LOOT` / `LOOT_END` | [Loot tab](../play/loot-history.md): 24 h catch-up pages of `.bot lootlog [cursor]`, newest first |
| `TBM:ORDER_BEGIN` / `ORDER` / `ORDER_END` | [Guild orders](../play/party-roster-guild.md#guild-orders): full list inside the pair, live one-bot update outside it; rows carry a trailing difficulty (`easy` / `medium` / `hard`, `-` or missing on old servers), then a trailing farm time in whole hours or `inf` for no limit (missing on old servers), then a trailing `keep` / `-` flag (missing on old servers), then the supply tail `parent` / `goldCap` / `step` / `need` (`-` or missing on old servers; parent is the parent order's bot or `-`, goldCap is guild gold in copper or `-`, step is `bags` / `bank` / `ah` / `farm` / `craft` / `sub` / `need` / `deliver` or `-`, need is `itemId:count;...` or `-`); `timeout` means the farm time ran out (an `inf` order never times out), `noprogress` means the bot worked 3 hours without gaining a single item, `stocked` means a keep order sits delivered while the bank holds the amount, `needitems` (state `waiting`) means the order waits for the player to bring the need items; the give takes an extra trailing `gold=<copper>` cap (omitted with no cap) and a refused trailing field retries without it (give fallback order: gold, then keep, then inf→24, then bare); cancel on a parent cancels the whole branch; `.bot order list` also asks the window to fetch `ORDER_ACCESS` when it has none yet |
| `TBM:ORDER_ACCESS` | [Guild orders](../play/party-roster-guild.md#guild-orders) bank access: `TBM:ORDER_ACCESS|<rankIndex>|<rankName>|<tabsOk>|<tabsDenied>|<gold 0/1>|<canSetRank 0/1>` rides first inside `ORDER_BEGIN` / `ORDER_END` and again after a rank change (live outside the pair repaints too); tab lists are comma-separated 1-based tabs or `-`; rank `-` means the server leaves bot ranks alone (grey line, no rank control); tabs `-` and `-` with a numeric rank means no unlocked guild bank yet (grey); a denied tab or gold `0` with a real bank shows red with what is missing; `.bot order access` asks for it now, `.bot order rank <idx>` sets the bots' rank (ACK or ERR, then a fresh access line), `.bot order reassign <subBot> <newBot>` hands a sub-order to another guild bot |
| `TBM:FEATURE`, `TBM:CONFIG_BEGIN` / `CONFIG` / `CONFIG_END` | [Info window](../play/controls.md#info-window) |

Some replies have no structured line and are parsed from the bot's whisper text: spell list (`=== Spells ===`), flights (`=== Taxi ===`), bank (`=== Bank ===`), mailbox (`=== Mailbox ===`), plus lifecycle chat replies for older servers. Those patterns live in `Comms.lua`, `BotPanel.lua`, `BotNpc.lua` and `BotVault.lua` and must follow the module's wording.
