---
id: play-loot-history
title: Loot History
category: play
summary: The Loot tab that shows what your party bots looted or rolled.
tags: [loot, rolls, history]
relates_to:
  - play-features
  - developers-protocol
---

# Loot History

The **Loot** tab shows what your own party bots (owned alts and hired companions) looted or rolled: items in their quality colour, money as coins, and roll votes with the reason. Each row names the time, the bot and the source (corpse, chest, gathering node or object). Only bots that were in your party at the time appear.

## When it shows up

Only when the server advertises the `loot-log` capability. Without it there is no tab and nothing is sent.

## How it fills

On login the addon asks the server for the last 24 hours of rows (`.bot lootlog [cursor]`), newest first, and pages through until the server says there is no more. The history is kept per character on your machine (up to 2000 rows; the oldest drop), so it survives relogs. **Clear** wipes this character's stored history.

## Filters

Bot, item name, quality, source and row type (items / rolls / all) combine: every filter narrows the same list. Scroll down for older rows.
