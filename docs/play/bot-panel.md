---
id: play-bot-panel
title: Bot Panel
category: play
summary: The per-bot window for gear, bags, behaviour switches, shaman totems, spells, professions, NPC errands, bank and mail.
tags: [bot-panel, gear, bags, inventory, behaviour, totems, spells, professions, bank, mail]
relates_to:
  - play-party-roster
  - play-fight-camp
  - developers-protocol
---

# Bot Panel

One window per bot for its gear and habits. Open it with:

- the bag icon on a [Party](party-roster-guild.md#party-tab) or [Guild](party-roster-guild.md#guild-tab) row,
- **Gear & bags** on the Fight tab while a bot is targeted,
- the small button next to the target frame (only when your target is one of your bots), or the **Open bot controls for target** key binding,
- `/tbm bags <name>` (or `/tbm bags` with the bot targeted).

Everything shown comes from the server; each click sends one request and the server answers with fresh state. Module: [bot panel commands](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-panel-commands).

## Tabs

| Tab | What it shows | Sends |
| :--- | :--- | :--- |
| Gear | Paper doll with the bot's 3D model, durability and money. Click a slot to unequip. | `.bot inv <bot>`, `.bot item <bot> unequip <bag> <slot>` |
| Bags | Every bag item; a green **+** marks an upgrade for this bot. Click an item for the item menu. **Equip upgrades** equips everything better from new loot. | `.bot inv <bot>`, `.bot command <bot> d equip upgrades` |
| Behaviour | Per-bot switches stored on the server (below). | `.bot behavior <bot> <key> on\|off` |
| Spells | What the bot can cast (**Ask for spellbook**). Click a spell and the bot casts it. | `.bot command <bot> spells`, `.bot command <bot> cast <spell>` |
| Professions | Trade skills with skill bars, known recipes coloured for this bot's skill, and a collapsed **Not learned yet** group per skill. A search box filters both lists. Needs the `professions` capability. | `.bot professions <bot>` |

### Item menu

| Option | What it does | Sends |
| :--- | :--- | :--- |
| Equip | The bot equips it. | `.bot item <bot> equip <bag> <slot>` |
| Give to me | Opens a trade with the item already in. Accept to take it. | `.bot item <bot> give <bag> <slot>` |
| Use | The bot uses food, drink or a potion. | `.bot command <bot> u <item>` |
| Disenchant | The bot disenchants it. | `.bot command <bot> <verb> <item>` |
| Send by mail | The bot mails it to you. | same |
| Put to bank | The bot stores it in its bank. | same |
| Destroy | Destroys it. Asks first; cannot be undone. | same |

Module: [item equip](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-equip), [unequip](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-unequip), [give](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-give), [trade](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-trade).

### Behaviour switches

| Switch | What it does |
| :--- | :--- |
| Loot corpses | Loot after a fight. |
| AoE spells | Use area abilities (held next to crowd-controlled mobs). |
| Auto CC | Crowd-control a loose add hitting your healer. Your marks always win. |
| Save mana | Wait longer between casts on long fights. Mana classes only. |
| Cooldowns | Use big offensive cooldowns. |
| Watch threat | Ease off near the tank's threat. |
| Potions | Drink healing and mana potions when low. |
| Mimic | Copy your food, drink and potion use. |
| Spread out | Keep distance instead of stacking. |
| Hold position | Keep following and fighting, but never run from enemies on its own: no fleeing, kiting or stepping back for casting room. Still steps out of ground effects. Hidden until the server reports it. |
| No dungeon Blink | Mages only. Never cast Blink inside dungeons and raids, where it can land in the next pack; Blink still works outdoors. Hidden until the server reports it. |

Module: [`.bot behavior`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-behavior).

### Class choices

On the Behaviour view of a paladin, hunter or warlock, a class block sits
under the switches when the server lists the `choice` capability. Opening
the panel on such a bot (and **Refresh**) asks the server for its choices
(`.bot choice <bot> status`); until the answer arrives the controls read `?`
and stay greyed out.

| Control | What it does | Sends |
| :--- | :--- | :--- |
| Aura (paladin) | Click to pick **Auto** or one of the auras the paladin has trained. | `.bot choice <bot> aura <aura\|auto>` |
| Aspect (hunter) | Click to pick **Auto** or one of the aspects the hunter has trained. | `.bot choice <bot> aspect <aspect\|auto>` |
| Curse (warlock) | Click to pick **Auto** or one of the curses the warlock has trained. | `.bot choice <bot> curse <curse\|auto>` |

The row shows what the server reports. The kinds are data-driven: a new
kind from the server appears with Auto plus its values, with no addon
change. Module: `.bot choice`.

### Shaman totems

On a shaman's Behaviour view a totem block sits under the switches. Opening the panel on a shaman (and **Refresh**) asks the server for its totems (`.bot totem <bot> status`); until the answer arrives the controls read `?` and stay greyed out.

| Control | What it does | Sends |
| :--- | :--- | :--- |
| Earth, Fire, Water, Air | Click to pick **Auto** or one of that slot's totems. Only totems the bot has trained are listed (an older server that does not say lists them all). The row shows what the server reports. | `.bot totem <bot> <slot> <totem\|auto>` |
| Drop | Click to cycle **Auto**, **Before the pull**, **Only on order**. | `.bot totem <bot> mode <auto\|prepull\|manual>` |
| Preset | Click to show the next saved preset. Two come with the addon, **Melee group** (Strength of Earth, Searing, Mana Spring, Windfury) and **Caster group** (Stoneskin, Searing, Mana Spring, Grace of Air); you can overwrite or delete them. | none |
| Apply | Sets this shaman's four totems to the shown preset. | `.bot totem <bot> set <earth>,<fire>,<water>,<air>` |
| Apply all | The same for every shaman in your party. | `.bot totem party set <earth>,<fire>,<water>,<air>` |
| Save | Asks for a name and stores this shaman's four slots under it; a name that exists is overwritten. | none |
| Delete | Removes the shown preset. | none |

Presets are kept on your computer (the addon's saved variables), not on the server. A slot with a chosen totem never switches by itself, except Tremor Totem, which may take the earth slot while the group is feared and then gives it back. The **Drop totems** button on the Camp tab still drops every shaman's totems right now.

### Professions

Opening the tab asks the server once (`.bot professions <bot>`); **Refresh** in the view, or the panel footer, asks again. The reply is cached for the session. Each skill shows its value and max with a bar. Each known recipe shows the made item (or the enchant name when there is no item) in the colour it has for this bot's skill, like in your own trade skill window: orange, yellow, green or grey (grey gives no more skill-ups). The tooltip names the reagents (item tooltip for made items, spell tooltip for enchants).

Each orderable recipe has a **Craft** button that opens the [order window](party-roster-guild.md#guild-orders) with Craft and that item already picked; sending it gives a normal craft order. The button is disabled with the server's plain reason when the recipe cannot be ordered (enchants cannot be ordered yet, soulbound when made, needs a profession to use, long cooldown). Without the order feature, or without the right to give orders, the button is hidden instead.

Under each skill a collapsed **Not learned yet (N)** group lists recipes the bot could still learn at its current rank: each row names the made item, the required skill and where it comes from (**Trainer**, or the recipe item that teaches it, so you know what to hand over). The search box filters known and missing recipes by item name.

Hovering a [guild bot's row](party-roster-guild.md#guild-tab) shows its skills (`Mining 245/300, Herbalism 230/300`) whenever a cached reply exists; hovering never sends a request.

## Footer buttons

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Trade | Opens a trade window; put items or gold in and accept, the bot accepts on its own. | `.bot item <bot> trade` | [trade](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-trade) |
| Refresh | Reload gear, bags, behaviour, totems, conjured goods and professions. | `.bot inv <bot>`, `.bot totem <bot> status`, `.bot professions <bot>` | [inv](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-inv) |
| Upkeep | Restock food, drink, reagents, ammo and repairs. Bot must be online. | `.bot maintenance <bot>` | [maintenance](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-maintenance) |
| AutoGear | Equip the best gear the bot already has in its bags. | `.bot autogear <bot>` | [autogear](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-autogear) |
| NPC | NPC errands (below). | | |
| Bank | Bank and mailbox lists (below). | | |

## Conjured goods

Mages conjure food and water and open portals; warlocks conjure healthstones. When the panel opens
for a mage or warlock it asks the server once (`.bot service <bot>`) and caches the answer for the
session; **Refresh** asks again. The buttons only show when the bot can do it.

| Button | What it does | Sends |
| :--- | :--- | :--- |
| Food & Water | The bot opens a trade with conjured food and water in it. Accept to take it. | `.bot item <bot> trade` |
| Healthstone | The bot opens a trade with a healthstone in it. Accept to take it. | `.bot item <bot> trade` |
| Portal | Pick a city from the dropdown; the bot opens a portal there. | `.bot service <bot> portal <spellId>` |

## NPC errands

You and the bot stand at the NPC.

| Button | What it does | Sends |
| :--- | :--- | :--- |
| Talk | The bot greets the NPC. | `.bot command <bot> talk` |
| Bind home | The bot binds its hearthstone at this innkeeper. | `.bot command <bot> home` |
| Train spells | The bot learns what it can from this trainer. | `.bot command <bot> trainer learn` |
| Take lead | The bot passes party leadership to you. | `.bot command <bot> give leader` |
| Find flights | List this flight master's routes, then click one to fly it. | `.bot command <bot> taxi ?`, `taxi <n>` |

## Bank and mail

Read-only lists of the bot's bank and mailbox (needs a banker or mailbox nearby). Click a row to take it; **Ask again** refreshes.

Sends `.bot command <bot> bank`, `bank -<item>`, `mail ?`, `mail take <n>`.
