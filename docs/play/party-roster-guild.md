---
id: play-party-roster
title: Party, Roster, Guild and Raid Tabs
category: play
summary: Party roles and blessings, Roster lifecycle, claimed Guild bots and the Raid tab.
tags: [party, roster, guild, raid, roles, blessings, lifecycle]
relates_to:
  - play-getting-started
  - play-bot-panel
  - play-fight-camp
---

# Party, Roster, Guild and Raid Tabs

## Party tab

One row per party member: class icon and colour, level, HP and mana bars with state (Dead, Ghost, Drinking, out of range), the role picker in the middle, and on the right the current CC mark, a summon button and a bag icon that opens the [bot panel](bot-panel.md). Your own row is marked **You**. Click a bot's row to target it; the targeted row highlights gold.

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

### Bots

Next to **Blessings**, a **Bots** button opens one compact row per party bot:
its name with class colour and role, up to four of the switches that matter
in a fight (Hold position, No dungeon Blink, then Loot, AoE, Auto CC, Save
mana, Cooldowns, Watch threat and Potions — whichever the bot panel
Behaviour view shows for that bot), and a **Controls** button that opens the
full [bot panel](bot-panel.md). A chip click sends the same
`.bot behavior <bot> <key> on|off` the Behaviour view sends, and the row
repaints from the next bot-state reply.

### Blessings

With a paladin bot in your party or raid and a server that lists the `blessing` capability, a **Blessings** button appears at the bottom of the Party tab. It opens a small grid: one row per paladin bot, one column per class present in the group (you count too). Each cell shows the blessing that paladin gives that class, as the spell icon, or **Auto** when the paladin chooses.

- **Left-click** a cell for the next blessing, **right-click** for the previous one. The cycle is **Auto** plus the blessings that paladin has trained; the cell waits for the server's answer before it can be clicked again.
- The grid asks the server when it opens and again after the group changes while it is open. It closes by itself when the last paladin bot leaves.

| Click | Sends |
| :--- | :--- |
| Blessings (open, group change) | `.bot blessing party status` (`raid` inside a raid) |
| A cell | `.bot blessing <paladin> <class> <might\|wisdom\|kings\|salvation\|sanctuary\|light\|auto>` |

The server refuses a blessing the paladin has not learned and says so in the status line and the Log tab.

## Roster tab

Every character on your account, from the server (`.bot roster`): class, status (offline, starting, online, removing), whether it is in your group, and last known location. A search box and one row of class icons (plus **All**) filter the list.

Tick rows and use the bar below. Mixed selections only act on the rows where the action makes sense.

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Login | Log selected offline alts in as bots. On an alt-bot playing alone, take it back as your companion. | `.bot add <name>` | [add](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-add) |
| Logout | Log selected bots out. | `.bot logout <name>` | [roster](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-roster) |
| Invite | Invite selected online bots to your group. | `.bot invite <name>` | [invite](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-invite) |
| Kick | Remove selected bots from your group. | `.bot uninvite <name>` | [uninvite](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-uninvite) |
| Summon | Summon selected online bots to you. | `.bot summon <name>` | [summon](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-summon) |
| Fill party | Invite online bots until the party has 5. No selection needed. | `.bot invite <name>` per bot | |

Alts that play on their own in the world are marked as alt-bots. Module: [alt-bots](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#alt-bots-autonomous-alts).

The selection actions fill the bottom row; **Fill party** and **Alt summary** sit above them on the right, since they need no selection.

**Alt summary** (needs no selection): asks every alt-bot playing on its own what it did while you were away (`.bot alts`). Each answer appears in the [Log tab](controls.md#log-tab) as its own sentence, one line per alt-bot (levels, gold, quests, deaths, notable loot, where it is now). When none are out, the status line says so.

## Guild tab

Wandering bots you claimed into your guild with `/ginvite`, kept as raid alts. The list comes from the server's claimed-bot snapshot (needs the `claimed-roster` capability).

Hovering a bot's row shows its professions with skill from the snapshot (`Enchanting 300, Tailoring 275`; older servers send no field, and the [bot panel](bot-panel.md#professions) cache stays the fallback when the row has none). Hovering never sends a request. The search box also matches profession names: typing "enchant" leaves only bots with Enchanting.

### Guild orders

The Guild tab also has a **Guild order** button in the bar under the list (needs the `guild-orders` capability): pick **Craft** or **Enchant**, type at least 3 letters, and see every matching recipe with the guild bots that know it (online bots only, highest skill first; each bot shows how many materials it already holds and whether it already runs an order). Click a bot to open the normal order flow for that bot and item; clicking an enchant opens the per-bot enchant search with that spell picked, ready to **Send**. Each bot row has its own **Order** button that opens the same small window (needs the `guild-orders` capability). Search for an item by name (at least 3 letters), or pick a kind (**All**, **Herbs**, **Ore**, **Leather**, **Fish**, **Cloth**, **Drops**, **Other**) to browse everything of that kind. Pick **Farm** or **Craft** and an amount (1-200): the window shows a preview above **Send** of what the bot will do (what it has, farms, buys, asks other bots for, what you send, rough time, gold cap; craft previews also carry one **I bring it** checkbox per material, auto-ticked when your bags hold the full count — ticked materials ride `bring=<item>,<item>` on preview and Send, and the bot waits for you to trade, mail or bank them instead of buying, withdrawing or farming them). **Buy** only shows while the server allows player Buy orders (older servers always show it). Then **Send**: **No time limit** is ticked by default and the bot farms until it has the amount, however long it takes (only Cancel stops it); untick it to set a **Farm time** (whole hours, 1-24) instead. Tick **Keep in stock** and the bot refills the bank whenever it drops below the amount. **Max guild gold** (empty = no cap) caps what the order may spend from the guild bank, in copper. The list comes from the server, so only real, obtainable items show up; each result says where this bot would farm it, roughly how long it takes (`Ashenvale · about 20 kills · 12% drop`), and how rough the work is (`Easy`, `Medium`, `Hard`) — or why it can't (`needs Skinning`, `no source near level 12`, `only from elite creatures`). Items you never saw show a `?` icon until the client has cached them. Bots farm like players: large amounts or rare drops can take very long or fail. On an old server that refuses trailing fields, the addon retries without them (gold, then keep, then no-limit as 24 hours) and says so.

The window header always shows what the bots can reach: the bots' guild rank, the bank tabs they use, and whether they may spend guild gold. Red means something is missing (a denied bank tab or no gold access); grey means the server leaves bot ranks alone or no guild bank is unlocked yet. Players whose rank may change ranks get a **Rank** button listing the guild's ranks by name (guild master skipped, current bot rank marked): picking one asks "Move all guild bots to rank <name>?" and only Yes sends it. The window also lists every order and sub-order live: which bot, what item, how many delivered of how many, and what it is doing right now (`taking from guild bank`, `buying on AH`, `farming in Elwynn`, `crafting`, `waiting for sub-order`, `needs items from you`, `delivering` — a working order that also needs items from you says so on its row). A row with items still in the bot's bags or mail shows `(+N carrying)` after the progress and names the count in the tooltip (old servers send no carry: delivered progress only). Sub-orders show indented under their parent. When a bot waits for you (`needs items from you`), the tooltip names the missing items — trade them to the bot, mail them, or put them in the guild bank. Each sub-order row on the Guild tab carries **Move**: a dropdown listing the guild's bots the addon knows (claimed roster first, then any other ordered bot), excluding the worker holding the sub-order. Picking one asks "Hand <sub>'s sub-order to <new>?" and only Yes sends it; with no other bots the row just says so. In the order window, sub-orders are live text rows (no buttons; use the row's Move on the Guild tab).

The row then shows the order and its progress live: `Light Leather 4/10 (Ashenvale) · Easy`, a `No limit` mark on orders with no time limit, `Delivering`, `Done`, `Stocked` (a keep order sitting delivered: the amount is in the bank and the bot refills when it drops below), `Mailed to GM`, `No skill` or `Can't` (including when the farm time ran out, or the bot worked 3 hours without gaining a single item: `no progress - the bot found nothing to farm`), with the reason in the tooltip (the tooltip also shows the farm time, or `no limit`, the live step, the gold cap, the need list, explains the difficulty: rough effort for this bot, how many kills, gathers or casts it needs, and names the refill level on keep orders). Hovering a guild bot's row stays short: name, level, class, status, professions and the order on one line. The full story of every order (state and reason, the live step, farm time, gold cap, difficulty, the need list and the last order steps with their age, newest first; servers with step history only) sits in the **Orders** window: the **Orders** button in the Guild tab's bar lists every bot with an order (sub-orders indented), click one to read its detail, **Cancel order** it or open **New order** for it. A reply that lands after the bot moved to a new order is dropped, and an identical replacement order cannot be told apart until the server sends an order generation id. **Cancel** asks first, naming the bot and item — and warning when it cancels a whole branch — then removes the order; cancelling is the only way to end a no-limit order or a stocked keep order. One order per bot; a new order replaces the old one, and **Send** asks "Replace it?" first while the old one is still running. The list refreshes when the tab opens and every 30 seconds; progress lines from the server update the rows in between.

Only guild ranks that may edit officer notes can give or cancel orders; without that right the buttons are greyed out. Without the addon the same orders work from chat: `.bot order <bot> farm <item link> 10 1`, `.bot order <bot> farm <item link> 10 1 keep`, `.bot order <bot> farm <item link> 10 inf`, `.bot order <bot> farm <item link> 10 2 keep gold=10000`, `.bot order <bot> cancel`, `.bot order list`, `.bot order access`, `.bot order rank 2`, `.bot order reassign <subBot> <newBot>`.

**What a bot can be asked:** the order window asks for the bot's trade skills when it opens. A bot without Enchanting has the **Enchant** kind greyed out, and on a Farm order the **Herbs**, **Ore** and **Leather** filters are greyed unless the bot has Herbalism, Mining or Skinning. Until the skills arrive nothing is greyed. The window is only as tall as the current step needs.

**Enchant orders:** pick **Enchant** in the order window, search the bot's enchants and **Send** the spell (`order <bot> enchant <spellId>`). The guild row shows `Ready - come to Stormwind/Orgrimmar (by faction) and press Meet`, `On the way to you` while `coming`, and `Trade open - put your item in Will not be traded` while `enchanting`. An unfinished enchant row shows **Meet** where **Release** sits; the click sends `order <bot> meet`. The button stays greyed out while the bot still gathers, while you carry none of the missing materials, while you stand outside Stormwind/Orgrimmar, or for a few minutes after the server turns a Meet away (the tooltip says why, with a live countdown). A refused Meet also shows its text on screen. When an enchant turns `ready` the row highlights with a one-time message and sound (once per order). From chat: `.bot order <bot> enchant <spellId>`, `.bot order <bot> meet`.

With a mailbox open, the window also shows a **Send missing items** button: it fills the Send Mail form for the first bot in the order tree that needs items (recipient, `Order: <item>` subject, the need list in the body) and attaches one stack of a needed item from your bags (a partial stack when the need is smaller). You press **Send** yourself - one click is one stack, and you click again for the next mail once the server shrinks the need list. Your cursor and the attachment slot must both be empty: with an item on the cursor or one already attached, the click fills the form, says why and attaches nothing rather than swapping your items. The button stays greyed out until a mailbox is open and an order needs items.

- **Badges:** level 60 bots show `Locked` (they never equip or vendor on their own; you gear them). Levelling bots show `Leveling` (they equip upgrades but keep blues and epics). Status reads `Online`, `Offline` or `In party`.
- **Per row:** the backpack button for the [bot panel](bot-panel.md) sits left of the name. The right-hand side has, in one line, the role cycler (`.bot role`), **Order** for the [order window](#guild-orders) and, while the bot has an order, a **...** button. **...** (or a right-click on the row, always) opens a menu with **Release** to send the bot back to the wandering pool (`/gkick`), **Cancel order** and, on a sub-order, **Move sub-order**; each keeps its confirmation.
- **Bar:** tick rows, then **Invite** (to your party; a full party becomes a raid) or **Summon**. **Fill raid** invites online claimed bots until the raid has 40. **Sync** refreshes the list. **Orders** opens the active-orders window (below). **Guild order** opens the guild-wide order search.

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
