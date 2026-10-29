---
id: play-fight-camp
title: Fight and Camp Tabs
category: play
summary: Every Fight and Camp tab button, what it does, and the .bot command it sends.
tags: [fight, camp, actions, pull, formations, toggles]
relates_to:
  - play-features
  - play-controls
  - play-party-roster
---

# Fight and Camp Tabs

**Fight** holds what you use during a pull, **Camp** what you use between pulls. Each button sends one command to your party, or to your targeted bot (see [who an order goes to](getting-started.md#who-an-order-goes-to)). Downtime is the exception: it sends `.bot downtime`, a direct command for your own alts only. The last column links to the module page that explains how the bots carry it out.

Module docs base: [party actions](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md).

## Fight tab

### Engage

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Attack | Bots attack your target. Needs an enemy target. | `.bot action attack` | [attack](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-attack) |
| Stop | Stop attacking, clear targets, back to formation. | `.bot action stop` | [stop](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-stop) |
| Interrupt | Bots with a kick, pummel or counterspell interrupt the target's cast. | `.bot action interrupt` | [interrupt](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-interrupt) |
| Flee | Disengage and run behind you until the next order. | `.bot action flee` | [flee](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-flee) |

### Pull and focus

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Pull | The tank pulls your target; the others wait the **pull timer** (0–60 s, default 10) before joining. | `.bot action pull <s>` | [pull](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-pull) |
| Pullback | The tank pulls and runs back to you; the others wait the **pullback timer** (default 3 s) after it is back. | `.bot action pullback <s>` | [pullback](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-pullback) |
| End pull | Calls off the current pull. | `.bot action end pull` | [end pull](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-end-pull) |
| Focus Skull | Everyone burns the Skull target. | `.bot action focus skull` | [focus skull](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-focus-skull) |
| CC Mark | Opens the marks panel: give each raid mark to one bot for crowd control, clear one mark or all. Party rows show each bot's mark. | `.bot action cc <mark> <bot>`, `cc clear [bot]` | [cc](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-cc) |

The timers are `-`/`+` controls under the pull buttons (shift-click steps by 5) and are saved per character. A server that does not advertise `pull-seconds` gets the plain command without seconds.

### Move

| Button | What it does | Sends |
| :--- | :--- | :--- |
| Follow | Follow you in formation. | `.bot action follow` |
| Stay | Hold position until the next order. | `.bot action stay` |
| Come | Run to you and hold there. | `.bot action come` |
| Guard | Plant where they stand and fight anything close. | `.bot action guard` |
| Free | Leave guard posts and move freely. | `.bot action free` |

Follow, Stay, Guard and Free stay lit while that mode is active, read from the server's live bot state. Module: [follow](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-follow), [stay](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-stay), [come](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-come), [guard](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-guard), [free](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-free).

**Combat stance** pills (`.bot action stance <name>`, [stance](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-stance)):

| Pill | Where melee stands |
| :--- | :--- |
| Near | Default: crowd close around the target. |
| Tank | Tank goes toe-to-toe and turns the target away from the party. |
| Turnback | Melee holds the far side of the target, away from your casters. |
| Behind | Melee works the target's back, clear of frontal cleaves. |

### Party switches

On/off for the whole party. Each shows the real state from the server with a lamp: **On**, **Off** or **Mixed** (bots differ).

| Switch | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| AoE | DPS bots may use area spells (still held next to a crowd-controlled mob). | `.bot action aoe on\|off` | [aoe](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-aoe) |
| Auto CC | Bots sheep or sap a loose add that hits your healer. Your marks always win. | `.bot action auto cc on\|off` | [auto cc](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-auto-cc) |
| Sap | Rogues open with Sap on the pull target. Needs a rogue. | `.bot action sap on\|off` | [sap](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-sap) |
| Spread | Bots keep distance from each other against area damage. | `.bot behavior party spread on\|off` | [behavior](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/bot-panel.md#bot-behavior) |
| Loot | Bots loot corpses after a fight. | `.bot action loot on\|off` | [loot](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-loot) |

### Tactics

One-click strategy toggles (`.bot strategy ~<name>`, [strategy](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-strategy)):

| Button | What it does |
| :--- | :--- |
| Kite | Keep distance from enemies while fighting. |
| Auto Mark | Bots mark the next target with Skull when a fight starts. |
| Focus Fire | All DPS on one target instead of spreading damage. |
| AoE Fear | Bots may fear groups. Held back inside instances. |

The **Gear & bags** button opens the [bot panel](bot-panel.md) of your targeted bot.

## Camp tab

| Button | What it does | Sends | Module |
| :--- | :--- | :--- | :--- |
| Rest | Eat and drink until full. | `.bot action rest` | [rest](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-rest) |
| Ready Check | Starts the game's ready check and asks bots if they are ready (health, mana, debuffs). | `.bot action ready` | [ready](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-ready) |
| Repair | Repair at a nearby vendor. | `.bot action repair` | [repair](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-repair) |
| Sell junk | Sell grey items. | `.bot action sell` | [sell](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-sell) |
| Train | Learn what the targeted class trainer offers. | `.bot action learn` | [learn](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-learn) |
| Downtime | Own alt runs trainer, vendor and repair errands, then comes back. Needs the `downtime` capability; hires and pool bots are refused. | `.bot downtime` | [downtime](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-downtime) |
| Release / Corpse run | Dead bots release spirit; once they are ghosts the button turns into Corpse run. | `.bot action release` / `corpse run` | [release](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-release), [corpse run](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-corpse-run) |
| Rebuff | Re-cast missing group buffs. | `.bot action rebuff` | [rebuff](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-action-rebuff) |
| Reset tactics | Clear your strategy changes back to defaults. | `.bot strategy reset` | [strategy](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-strategy) |

### Formations

Ten formations in two pill rows, with a one-line description of the active one. Sends `.bot formation <name>` (or for the targeted bot only). Module: [formation](https://github.com/Sagiroth/TortoiseBots/blob/main/docs/play/commands/party-actions.md#bot-formation).

| Formation | Use it for |
| :--- | :--- |
| Shield | Dungeons: tank in front, melee on the flanks, healers behind. |
| Near | Tight stack, for corridors and sneaking past patrols. |
| Queue | Single file, for bridges and ledges. |
| Arrow | Wedge pointing forward, open ground. |
| Circle | Ring around you, facing out. |
| Line | Side by side with you in the middle. |
| Far | Loose spread at leash range, open-world pulling. |
| Melee | Melee stack on the tank's target, ranged hang back. |
| Chaos | Scattered, no fixed shape. |
| Default | Server default spacing. |

### Quests

| Button | What it does | Sends |
| :--- | :--- | :--- |
| Accept | Every grouped bot accepts the quest you were offered. | `.bot command <bot> accept` per bot |
| Share | Share your tracked quests with every grouped bot. | `.bot command <bot> share` per bot |
| Grind | Bots roam and grind mobs on their own; click again to stop. | `.bot strategy +grind` / `-grind` |
