---
id: play-party-roster
title: Party, Roster, Guild and Raid Tabs
category: play
summary: Party roles, Roster lifecycle, claimed Guild bots and the Raid tab.
tags: [party, roster, guild, raid, roles, lifecycle]
relates_to:
  - play-getting-started
  - play-bot-panel
  - play-fight-camp
---

# Party, Roster, Guild and Raid Tabs

## Party tab

One row per party member: class colour, current CC mark, a bag icon that opens the [bot panel](bot-panel.md), and role buttons.

**Bot roles** use the same spec names as the inn recruiter. The lit button is the bot's real spec as the server reports it.

| Class | Roles |
| :--- | :--- |
| Warrior | Protection, Arms, Fury |
| Paladin | Protection, Holy, Retribution |
| Hunter | Beastmaster, Marksman, Survival |
| Rogue | Combat, Assassination, Subtlety |
| Priest | Holy, Discipline, Shadow |
| Shaman | Restoration, Elemental, Enhancement, Enh Tank |
| Mage | Frost, Fire, Arcane |
| Warlock | Affliction, Demonology, Destruction |
| Druid | Feral Bear, Feral Cat, Restoration, Balance |

A tank pick sends `.bot role <bot> tank`; other picks send `.bot strategy <specs> <bot>` (and clear a previous tank role). Module: [`.bot role`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-role).

**Your own row** picks the role *you* fill for your bots (Tank, Healer, DPS), sent as `.bot role self <role>`. It does not change your spec.

## Roster tab

Every character on your account, from the server (`.bot roster`): class, status (offline, starting, online, removing), whether it is in your group, and last known location. Search box and class filter chips at the top.

Tick rows and use the bar below. Mixed selections only act on the rows where the action makes sense.

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Login | Log selected offline alts in as bots. On an alt-bot playing alone, take it back as your companion. | `.bot add <name>` | [add](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-add) |
| Logout | Log selected bots out. | `.bot logout <name>` | [roster](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-roster) |
| Invite | Invite selected online bots to your group. | `.bot invite <name>` | [invite](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-invite) |
| Kick | Remove selected bots from your group. | `.bot uninvite <name>` | [uninvite](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-uninvite) |
| Summon | Summon selected online bots to you. | `.bot summon <name>` | [summon](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-summon) |
| Fill | Invite online bots until the party has 5. No selection needed. | `.bot invite <name>` per bot | |

Alts that play on their own in the world are marked as alt-bots. Module: [alt-bots](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#alt-bots-autonomous-alts).

## Guild tab

Wandering bots you claimed into your guild with `/ginvite`, kept as raid alts. The list comes from the server's claimed-bot snapshot (needs the `claimed-roster` capability).

### Guild orders

Each bot row has an **Order** button (`Ord`) that opens a small window (needs the `guild-orders` capability). Search for an item by name (at least 3 letters), or pick a kind (**All**, **Herbs**, **Ore**, **Leather**, **Fish**, **Cloth**, **Drops**, **Other**) to browse everything of that kind. Pick **Farm**, **Buy** or **Craft** and an amount (1-200), then **Send**: **No time limit** is ticked by default and the bot farms until it has the amount, however long it takes (only Cancel stops it); untick it to set a **Farm time** (whole hours, 1-24) instead. Tick **Keep in stock** and the bot refills the bank whenever it drops below the amount. **Max guild gold** (empty = no cap) caps what the order may spend from the guild bank, in copper. The list comes from the server, so only real, obtainable items show up; each result says where this bot would farm it, roughly how long it takes (`Ashenvale · about 20 kills · 12% drop`), and how rough the work is (`Easy`, `Medium`, `Hard`) — or why it can't (`needs Skinning`, `no source near level 12`, `only from elite creatures`). Items you never saw show a `?` icon until the client has cached them. Bots farm like players: large amounts or rare drops can take very long or fail. On an old server that refuses trailing fields, the addon retries without them (gold, then keep, then no-limit as 24 hours) and says so.

The window header always shows what the bots can reach: the bots' guild rank, the bank tabs they use, and whether they may spend guild gold. Red means something is missing (a denied bank tab or no gold access); grey means the server leaves bot ranks alone or no guild bank is unlocked yet. Players whose rank may change ranks get a **Rank** button listing the guild's ranks by name (guild master skipped, current bot rank marked): picking one asks "Move all guild bots to rank <name>?" and only Yes sends it. The window also lists every order and sub-order live: which bot, what item, how many it has of how many, and what it is doing right now (`taking from guild bank`, `buying on AH`, `farming in Elwynn`, `crafting`, `waiting for sub-order`, `needs items from you`, `delivering`). Sub-orders show indented under their parent. When a bot waits for you (`needs items from you`), the tooltip names the missing items — trade them to the bot, mail them, or put them in the guild bank. Each sub-order row on the Guild tab carries **Mv**: a dropdown listing the guild's bots the addon knows (claimed roster first, then any other ordered bot), excluding the worker holding the sub-order. Picking one asks "Hand <sub>'s sub-order to <new>?" and only Yes sends it; with no other bots the row just says so. In the order window, sub-orders are live text rows (no buttons; use the row's Mv on the Guild tab).

The row then shows the order and its progress live: `Light Leather 4/10 (Ashenvale) · Easy`, a `No limit` mark on orders with no time limit, `Delivering`, `Done`, `Stocked` (a keep order sitting delivered: the amount is in the bank and the bot refills when it drops below), `Mailed to GM`, `No skill` or `Can't` (including when the farm time ran out, or the bot worked 3 hours without gaining a single item: `no progress - the bot found nothing to farm`), with the reason in the tooltip (the tooltip also shows the farm time, or `no limit`, the live step, the gold cap, the need list, explains the difficulty: rough effort for this bot, how many kills, gathers or casts it needs, and names the refill level on keep orders). **Can** asks first, naming the bot and item — and warning when it cancels a whole branch — then removes the order; cancelling is the only way to end a no-limit order or a stocked keep order. One order per bot; a new order replaces the old one. The list refreshes when the tab opens and every 30 seconds; progress lines from the server update the rows in between.

Only guild ranks that may edit officer notes can give or cancel orders; without that right the buttons are greyed out. Without the addon the same orders work from chat: `.bot order <bot> farm <item link> 10 1`, `.bot order <bot> farm <item link> 10 1 keep`, `.bot order <bot> farm <item link> 10 inf`, `.bot order <bot> farm <item link> 10 2 keep gold=10000`, `.bot order <bot> cancel`, `.bot order list`, `.bot order access`, `.bot order rank 2`, `.bot order reassign <subBot> <newBot>`.

- **Badges:** level 60 bots show `[Locked]` (they never equip or vendor on their own; you gear them). Levelling bots show `[Leveling]` (they equip upgrades but keep blues and epics).
- **Per row:** role cycler (`.bot role`), backpack button for the [bot panel](bot-panel.md), **Ord** for the [order window](#guild-orders), **Can** to remove the order, **Rel** to release the bot back to the wandering pool (`/gkick`).
- **Bar:** tick rows, then **Invite to Raid** or **Summon to Raid**. **Fill Raid** invites online claimed bots until the raid has 40. **Sync** refreshes the list.

Module: [autonomous guilds](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/world/social.md#autonomous-guild-formation).

## Raid tab

Shown only while you are in a raid. Orders go to your bots in the raid, or to your targeted bot.

| Button | What it does | Sends |
| :--- | :--- | :--- |
| Tank face away | Target a dragon (Onyxia and others): tank bots turn it so breath and cleave miss the raid. | `.bot action raid tankface` |
| Douse runes | Molten Core: bots douse nearby runes (they must carry Aqual or Eternal Quintessence). | `.bot action raid douse` |
| Custom tactics on/off | Scripted boss moves for Emerald Sanctum, Lower Karazhan and Karazhan Crypt. Turn off to steer the bots yourself. | `.bot action raid custom on\|off` |
| Check | Ask every bot whether custom tactics are on. | `.bot action raid custom status` |

The tab also lists the boss tactics each bot has loaded. Bots switch to boss tactics on their own in supported raids; these buttons are the manual extras. Module: [raid actions](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-raid-tankface), [raid tactics](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/dungeons-and-raids.md#raid-tactics--boss-mechanics).
