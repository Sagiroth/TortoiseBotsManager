---
id: play-bot-panel
title: Bot Panel
category: play
summary: The per-bot window for gear, bags, behaviour switches, spells, NPC errands, bank and mail.
tags: [bot-panel, gear, bags, inventory, behaviour, spells, bank, mail]
relates_to:
  - play-party-roster
  - play-fight-camp
  - developers-protocol
---

# Bot Panel

One window per bot for its gear and habits. Open it with:

- the bag icon on a [Party](party-roster-guild.md#party-tab) or [Guild](party-roster-guild.md#guild-tab) row,
- **Gear & bags** on the Fight tab while a bot is targeted,
- `/tbm bags <name>` (or `/tbm bags` with the bot targeted).

Everything shown comes from the server; each click sends one request and the server answers with fresh state. Module: [bot panel commands](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-panel-commands).

## Tabs

| Tab | What it shows | Sends |
| :--- | :--- | :--- |
| Gear | Paper doll with the bot's 3D model, durability and money. Click a slot to unequip. | `.bot inv <bot>`, `.bot item <bot> unequip <bag> <slot>` |
| Bags | Every bag item; a green **+** marks an upgrade for this bot. Click an item for the item menu. **Equip upgrades** equips everything better from new loot. | `.bot inv <bot>`, `.bot command <bot> d equip upgrades` |
| Behaviour | Per-bot switches stored on the server (below). | `.bot behavior <bot> <key> on\|off` |
| Spells | What the bot can cast (**Ask for spellbook**). Click a spell and the bot casts it. | `.bot command <bot> spells`, `.bot command <bot> cast <spell>` |

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

Module: [`.bot behavior`](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-behavior).

## Footer buttons

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Trade | Opens a trade window; put items or gold in and accept, the bot accepts on its own. | `.bot item <bot> trade` | [trade](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-item-trade) |
| Refresh | Reload gear, bags and behaviour. | `.bot inv <bot>` | [inv](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-inv) |
| Upkeep | Restock food, drink, reagents, ammo and repairs. Bot must be online. | `.bot maintenance <bot>` | [maintenance](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-maintenance) |
| AutoGear | Equip the best gear the bot already has in its bags. | `.bot autogear <bot>` | [autogear](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-autogear) |
| NPC | NPC errands (below). | | |
| Bank | Bank and mailbox lists (below). | | |

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
