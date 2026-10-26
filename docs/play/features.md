---
id: play-features
title: What the Addon Can Do
category: play
summary: Catalog of every addon feature, where it lives, what the server must enable, and the module docs behind it.
tags: [features, capabilities, catalog]
relates_to:
  - play-getting-started
  - play-fight-camp
  - play-party-roster
  - play-bot-panel
  - play-dungeon-run
  - play-controls
  - developers-protocol
---

# What the Addon Can Do

Every feature, where to find it, and what the server needs. "Always" means any TortoiseBots server; a capability name means the server must advertise it (see [protocol](../developers/protocol.md#capabilities)), otherwise the button is hidden or greyed.

| Feature | Where | Needs | Addon page | Module page |
| :--- | :--- | :--- | :--- | :--- |
| Attack, stop, interrupt | Fight | Always | [Engage](fight-and-camp.md#engage) | [party actions](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md) |
| Flee | Fight | `flee` | [Engage](fight-and-camp.md#engage) | [flee](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-flee) |
| Pull and pullback with timers | Fight | Timers need `pull-seconds` | [Pull and focus](fight-and-camp.md#pull-and-focus) | [pullback](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/dungeons-and-raids.md#the-pullback-maneuver) |
| Focus Skull, CC marks | Fight | Always | [Pull and focus](fight-and-camp.md#pull-and-focus) | [crowd control](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/dungeons-and-raids.md#crowd-control-protocol) |
| Follow, stay, come, guard, free, stances | Fight | Always | [Move](fight-and-camp.md#move) | [movement](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#direct-movement-and-party-commands) |
| Party switches (AoE, auto CC, sap, spread, loot) | Fight | Always | [Party switches](fight-and-camp.md#party-switches) | [party actions](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-aoe) |
| Tactics (kite, auto mark, focus fire, AoE fear) | Fight | Always | [Tactics](fight-and-camp.md#tactics) | [strategy](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-strategy) |
| Rest, ready check, repair, sell, train, release, rebuff, totems | Camp | Always | [Camp tab](fight-and-camp.md#camp-tab) | [party actions](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md) |
| Ten formations | Camp | Always | [Formations](fight-and-camp.md#formations) | [formation](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-formation) |
| Quest accept/share, grind | Camp | Always | [Quests](fight-and-camp.md#quests) | [commands](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/README.md) |
| Bot roles by spec, your own role | Party | Always | [Party tab](party-roster-guild.md#party-tab) | [role](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md#bot-role) |
| Log in/out, invite, kick, summon, fill party | Roster | Always | [Roster tab](party-roster-guild.md#roster-tab) | [roster and hiring](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/roster-and-hiring.md) |
| Claimed guild bots, fill raid | Guild | `claimed-roster` | [Guild tab](party-roster-guild.md#guild-tab) | [guilds](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/world/social.md#autonomous-guild-formation) |
| Raid helpers, custom raid tactics | Raid (in a raid) | Always | [Raid tab](party-roster-guild.md#raid-tab) | [raid tactics](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/dungeons-and-raids.md#raid-tactics--boss-mechanics) |
| Gear, bags, item menu, trade, upkeep, autogear | Bot panel | `inventory` | [Bot panel](bot-panel.md) | [bot panel](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-panel-commands) |
| Per-bot behaviour switches | Bot panel | Always | [Behaviour](bot-panel.md#behaviour-switches) | [behavior](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-behavior) |
| Spells, NPC errands, flights, bank, mail | Bot panel | Always | [Bot panel](bot-panel.md#npc-errands) | [bot panel](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md) |
| Dungeon run (Preview) | Dungeon | `dungeon-run` | [Dungeon run](dungeon-run.md) | [run leader](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/commander.md#run-leader-bot-run) |
| Mini bar and favourites | Header | Always | [Mini bar](controls.md#mini-bar) | |
| Key bindings, slash commands, minimap | Game menu, chat | Always | [Controls](controls.md) | |
| Server switches and settings search | Info window | Always | [Info window](controls.md#info-window) | [features](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-features) |
| Quiet commands (no chat spam) | Everywhere | Server advertises the addon channel | [Protocol](../developers/protocol.md#transport) | [addon transport](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/addon.md#addon-command-transport-player-view) |

What the bots do with each order (rotations, pulling rules, loot, travel) is the module's job; see the [module feature catalog](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/features.md).
