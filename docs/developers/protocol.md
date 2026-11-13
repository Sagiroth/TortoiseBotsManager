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
| `engage` | "My pull" button on the Fight tab (`.bot action engage`; the success ACK carries an empty executor) |
| `flee` | Flee button and key binding |
| `inventory` | Bag icons and the bot panel |
| `claimed-roster` | Guild tab data |
| `guild-orders` | Guild order window, row status and the `.bot order` sends |
| `guild-order-nobuy` | Player Buy orders refused: the window hides **Buy**, `.bot order <bot> buy` is refused (older servers send no token and keep Buy) |
| `dungeon-run` | Dungeon tab and run window (server needs `DungeonSelfClear` and `RemoteCommander`); raid binds ride the same gate |
| `loot-log` | Loot tab and the `.bot lootlog` catch-up |
| `downtime` | Downtime button for own-alt errands (`.bot downtime`) |
| `choice` | Class block in the bot panel Behaviour view (`.bot choice`) |
| `blessing` | Blessings button on the Party tab and the blessing grid (`.bot blessing`) |
| `professions` | Professions tab in the bot panel, skill line in the guild row tooltip and the `.bot professions` send |

`behavior` is also advertised; the addon does not gate on it.

## Lines the addon reads

| Line | Used for |
| :--- | :--- |
| `TBM:TRANSPORT` | Choose addon channel or chat |
| `TBM:CAPS`, `TBM:VERSION` | Feature gates, server version in the header and Info window |
| `TBM:ROSTER_BEGIN` / `ROSTER` / `ROSTER_END`, `TBM:ROSTER_ERROR` | [Roster tab](../play/party-roster-guild.md#roster-tab); the server is the only roster authority |
| `TBM:ALTBOTS` | Alt-bot markers on the roster |
| `TBM:ALTSUM` / `TBM:ALTSUM_END` | Alt-bot summary: `.bot alts` is answered with one `ALTSUM\|<name>\|<text>` sentence per alt-bot playing alone, then `ALTSUM_END\|<count>`; each sentence shows in the Log tab, count 0 says no alt-bots are out |
| `TBM:CLAIMED_BEGIN` / `CLAIMED` / `CLAIMED_END` | [Guild tab](../play/party-roster-guild.md#guild-tab): `CLAIMED\|<guid>\|<name>\|<class>\|<level>\|<state>\|<grouped>\|<loc>\|<locked>[\|<profs>]` (`<profs>` lists `skillId:value` pairs joined by `;`, or `-`; missing on older servers) |
| `TBM:BOTSTATE_BEGIN` / `BOTSTATE` / `BOTSTATE_END` | Move mode lamps, party switch states, behaviour switches, live spec for role buttons |
| `TBM:CC_ASSIGN_BEGIN` / `CC_ASSIGN` / `CC_ASSIGN_END` | CC mark icons on party rows |
| `TBM:INV_BEGIN` / `INV_EQ` / `INV_ITEM` / `INV_END` | [Bot panel](../play/bot-panel.md) gear and bags |
| `TBM:SERVICE` | [Bot panel](../play/bot-panel.md#conjured-goods): `.bot service <bot>` is answered with `SERVICE\|<bot>\|<food 0/1>\|<water 0/1>\|<healthstone 0/1>\|<portals>` (`<portals>` is `-` or comma-separated `<spellId>:<city>` pairs); `.bot service <bot> portal <spellId>` opens the portal (ACK or ERR, intent `service portal`) |
| `TBM:CHOICE` | [Class choices](../play/bot-panel.md#class-choices): `.bot choice <bot|party> status` is answered with one `CHOICE\|<bot>\|<kind>=<value|auto>,known=<v>+<v>+...` line per kind the bot can choose, then `ACTION_ACK\|choice status\|<scope>\|<n>\|-`. `.bot choice <bot> <kind> <value|auto>` answers with a fresh line, then `ACTION_ACK\|choice\|bot:<Name>\|1\|<kind>=<value>`, or `ACTION_ERR\|choice\|invalid` / `unknown-spell` / `no-bot`. |
| `TBM:BLESSING` | [Blessing grid](../play/party-roster-guild.md#blessings): `.bot blessing <bot\|party\|raid> status` is answered with one `BLESSING\|<paladin>\|warrior=<b>,paladin=<b>,hunter=<b>,rogue=<b>,priest=<b>,shaman=<b>,mage=<b>,warlock=<b>,druid=<b>,known=<b>+<b>...` line per paladin bot, then `ACTION_ACK\|blessing status\|<scope>\|<n>\|-` (`<b>` is `auto`, `might`, `wisdom`, `kings`, `salvation`, `sanctuary` or `light`; `known` lists the trained blessings and may be empty). `.bot blessing <bot> <class> <b>` answers with a fresh line, then `ACTION_ACK\|blessing\|bot:<Name>\|1\|<class>=<b>`, or `ACTION_ERR\|blessing\|invalid` / `unknown-spell` / `no-bot`. |
| `TBM:TOTEM` | [Shaman totems](../play/bot-panel.md#shaman-totems): `.bot totem <bot\|party\|raid> status` is answered with one `TOTEM\|<bot>\|earth=<v>,fire=<v>,water=<v>,air=<v>,mode=<auto\|prepull\|manual>[,known=<totem>+<totem>...]` line per shaman, then `ACTION_ACK\|totem status\|<scope>\|<n>\|-` (`<v>` is `auto`, `none` or a full lowercase totem name; `known` lists the trained totems, may be empty, and is missing on older servers, which then get the whole per-slot list). `.bot totem <scope> set <earth>,<fire>,<water>,<air>` answers with a fresh line per shaman changed, then `ACK totem set` (or `ERR totem set` `invalid` / `no-shaman`). A single-slot or `mode` order is followed by a status request when only its ACK arrived. |
| `TBM:PROF_BEGIN` / `PROF` / `RECIPE` / `RECIPE_MISSING` / `PROF_END` | [Bot panel](../play/bot-panel.md#professions) trade skills and recipes: `.bot professions <bot>` is answered with one `PROF_BEGIN\|<bot>`, one `PROF\|<skillId>\|<value>\|<max>` line per profession, one `RECIPE\|<skillId>\|<spellId>\|<itemId or 0>\|<orange>\|<yellow>\|<green>\|<grey>\|<order>` line per known recipe (item 0 = enchant, `<order>` is `ok` or the craft-order refusal reason and is missing on older servers), one `RECIPE_MISSING\|<skillId>\|<spellId>\|<itemId or 0>\|<reqSkill>\|<recipeItemId or 0>` line per learnable-but-unknown recipe (recipeItemId 0 = trainer only), and `PROF_END\|<bot>\|<recipeCount>\|<missingCount>` (`<missingCount>` missing on older servers, read as 0). The addon keeps the reply only when both counts match the lines received. |
| `TBM:ACTION_ACK`, `TBM:ACTION_ERR` | Status line and Log tab result of each order |
| `TBM:RUN` | [Dungeon run](../play/dungeon-run.md) status (a stop-before-boss run appends `until boss (step N)`) |
| `TBM:RAID_LAYOUT` | [Dungeon run](../play/dungeon-run.md) raid layout (`<bots>|<tanks>|<tankHealers>|<raidHealers>|<groups>`, tanks main first) and `warning|<text>` lines; the bind ACK scope is `raid` |
| `TBM:LOOT_BEGIN` / `LOOT` / `LOOT_END` | [Loot tab](../play/loot-history.md): 24 h catch-up pages of `.bot lootlog [cursor]`, newest first |
| `TBM:ORDER_BEGIN` / `ORDER` / `ORDER_END` | [Guild orders](../play/party-roster-guild.md#guild-orders): full list inside the pair, live one-bot update outside it; `<have>` counts delivered only and a trailing `<carry>` counts what the bot holds in its bags plus its mail, not yet delivered (`-` or missing on old servers means none); a row with carry > 0 shows `(+N carrying)` after the progress and names the count in the tooltip; rows carry a trailing difficulty (`easy` / `medium` / `hard`, `-` or missing on old servers), then a trailing farm time in whole hours or `inf` for no limit (missing on old servers), then a trailing `keep` / `-` flag (missing on old servers), then the supply tail `parent` / `goldCap` / `step` / `need` (`-` or missing on old servers; parent is the parent order's bot or `-`, goldCap is guild gold in copper or `-`, step is `bags` / `bank` / `ah` / `farm` / `craft` / `sub` / `need` / `deliver` or `-`, need is `itemId:count;...` or `-`); `timeout` means the farm time ran out (an `inf` order never times out), `noprogress` means the bot worked 3 hours without gaining a single item, `nobanker` / `bankdenied` (state `working`) name the bank leg's dead end, `noauctioneer` / `nolisting` (state `working`) the auction leg's (no auctioneer in reach / nothing fitting on the AH), and a `working` row can carry a need list; `stocked` means a keep order sits delivered while the bank holds the amount, `needitems` (state `waiting`) means the order waits for the player to bring the need items; the give takes an extra trailing `gold=<copper>` cap (omitted with no cap) and a refused trailing field retries without it (give fallback order: gold, then keep, then inf→24, then bare); cancel on a parent cancels the whole branch; `.bot order list` also asks the window to fetch `ORDER_ACCESS` when it has none yet |
| `TBM:ORDER_ACCESS` | [Guild orders](../play/party-roster-guild.md#guild-orders) bank access: `TBM:ORDER_ACCESS|<rankIndex>|<rankName>|<tabsOk>|<tabsDenied>|<gold 0/1>|<canSetRank 0/1>` rides first inside `ORDER_BEGIN` / `ORDER_END` and again after a rank change (live outside the pair repaints too); tab lists are comma-separated 1-based tabs or `-`; rank `-` means the server leaves bot ranks alone (grey line, no rank control); tabs `-` and `-` with a numeric rank means no unlocked guild bank yet (grey); a denied tab or gold `0` with a real bank shows red with what is missing; `.bot order access` asks for it now, `.bot order rank <idx>` sets the bots' rank (ACK or ERR, then a fresh access line), `.bot order reassign <subBot> <newBot>` hands a sub-order to another guild bot |
| `TBM:ORDER_WHO_BEGIN` / `ORDER_WHO` / `ORDER_WHO_END` | [Guild orders](../play/party-roster-guild.md#guild-orders) guild-wide search: `.bot order search <craft|enchant> <text>` is answered with `ORDER_WHO_BEGIN|<kind>|<n>`, `n` `ORDER_WHO|<kind>|<id>|<name>|<quality>|<slot>|<reqSkill>|<bots>` lines (`<quality>` item quality or `-` on enchant, `<slot>` enchant slot token or `-` on craft, `<bots>` `name:skill:have:need:busy;...` online bots only, skill high to low, `busy` 1 while that bot runs an order, `-` when none, at most 30) and `ORDER_WHO_END`; enchant matches sort by required skill ascending, craft keeps the server order. |
| `TBM:ORDER_ENCHANTS_BEGIN` / `ORDER_ENCHANT` / `ORDER_ENCHANTS_END` | [Guild orders](../play/party-roster-guild.md#guild-orders) per-bot enchant search: `.bot order search <bot> enchant <text>` is answered with one `ORDER_ENCHANTS_BEGIN|<n>`, n `ORDER_ENCHANT|<spellId>|<name>|<slot>|<reqSkill>|<verdict>|<reagents>` lines (`<verdict>` `ok` or a reason token, `<reagents>` is `itemId:need:have` per reagent, `;` between rows, `-` when none) and `ORDER_ENCHANTS_END`; rows carry the spell id as itemId, `TBM:ACTION_ACK|order|bot:<Bot>|1|enchant` closes the window, `TBM:ACTION_ACK|order|bot:<Bot>|1|meet coming|meet later|meet gathering` answers the Meet button (plus the same words as plain system text); `TBM:ACTION_ERR|order|notcapital|noorder|busy|cooldown|nothingtobring|<text>` refuses it (the text shows on screen and in the window, and a `cooldown` refusal (`... Try again in N min.`) greys that bot's Meet button with a countdown) |
| `TBM:ORDER_PREVIEW` | Guild order preview above **Send**: `.bot order <bot> preview <farm\|craft> <item> <amount>` is answered with `TBM:ORDER_PREVIEW|<bot>|<type>|<itemId>|<item>|<want>|<missing>|<difficulty>|<zone>|<reagents>|<minutes>|<goldCap>` (farm or craft; `<reagents>` lists `itemId:need:bags:mail:bank:farm:zone:ah:vendor:sub:player` per base reagent, `;` between rows, `-` when none; `player` is what you must send; `<goldCap>` is copper or `-`). Asked on pick and amount change, never on a timer. A refused preview shows the reason. Both `TBM:ORDER_PREVIEW` and `TBM:ORDER` carry one trailing `<bring>` field (`id,id` or `-`, missing on old servers means nothing ticked); preview refresh and Send ride `bring=<id>,<id>` on craft orders. |
| `TBM:ORDER_STEPS_BEGIN` / `ORDER_STEP` / `ORDER_STEPS_END` | [Guild orders](../play/party-roster-guild.md#guild-orders) step history: `.bot order <bot> steps` is answered with `ORDER_STEPS_BEGIN\|<bot>\|<n>\|<dropped>`, `n` `ORDER_STEP\|<bot>\|<ageSec>\|<state>\|<reason>\|<step>\|<itemId>` lines (oldest first, the `TBM:ORDER` tokens, `-` = none, itemId `0` = none) and `ORDER_STEPS_END\|<bot>`; memory only on the server, at most 16 entries (a restart, a new order or a reassign starts empty) and `<dropped>` counts the older ones no longer kept. Needs the `guild-order-steps` capability (advertised together with `guild-orders`): the addon asks on hover of a guild row, one request per bot per 15 s, and shows the newest steps in the order tooltip. The request records the bot's order identity (type, item and parent); a reply that lands after the bot moved to a different order is dropped, never cached, and the next hover may ask again. The addon commits a reply only when its valid `ORDER_STEP` lines equal `<n>`; a short reply, or an `<n>` above 16, is discarded, the tooltip reads "history incomplete, retrying" and the next hover asks again. Limit: an identical replacement order (same type, item and parent) cannot be told apart until the server sends an order generation id. |
| `TBM:FEATURE`, `TBM:CONFIG_BEGIN` / `CONFIG` / `CONFIG_END` | [Info window](../play/controls.md#info-window) |

Some replies have no structured line and are parsed from the bot's whisper text: spell list (`=== Spells ===`), flights (`=== Taxi ===`), bank (`=== Bank ===`), mailbox (`=== Mailbox ===`), plus lifecycle chat replies for older servers. Those patterns live in `Comms.lua`, `BotPanel.lua`, `BotNpc.lua` and `BotVault.lua` and must follow the module's wording.
