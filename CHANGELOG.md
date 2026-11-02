# Changelog

All notable changes to TortoiseBotsManager are documented here.

## Unreleased

### Camp
- New Downtime button sends your own alt to its class trainer, vendor and repair, then back to you. Shown only when the server advertises the `downtime` capability; hires and pool bots are refused by the server.

### Dungeon Run
- Raid bind: Bind raid binds your target as the main tank of your raid (same `dungeon-run` gate, no new capability). The applied layout shows as `Main <tank> + N off` under the Party row (the full tank and healer lists stay in the chat's `Raid layout:` lines, which no longer reach the chat).
- Stop before the boss: the No boss checkbox adds `until boss` to the next Start (bots lead only; locked while a run goes or in I-lead mode), and the status shows the stop on its own line.
- Raid plans group after the dungeon plans in the picker; servers without them behave as before.

### Guild Orders
- Guild tab: every claimed bot row has an Order button opening an order window — search a real item by name, or pick a kind (All, Herbs, Ore, Leather, Fish, Cloth, Drops, Other) to browse it. Pick Farm / Buy / Craft and an amount (1-200), then send it: No time limit is ticked by default and the bot farms until it has the amount, however long it takes (only Cancel stops it); untick it to set a farm time (whole hours, 1-24) instead. Tick Keep in stock to have the bot refill the bank whenever it drops below the amount. Each result says where the bot would farm, roughly how long, the drop rate (`12% drop`, never on 100% nodes) and the difficulty (`Easy` / `Medium` / `Hard`) — or why it can't (`only from elite creatures` greys the row like other unusable results; a too-low skill names the lower zone when there is one). Fish results count casts. The window warns that large amounts or rare drops can take very long or fail. On an old server that rejects keep, the farm time or the kind filter, the addon resends without it (keep first, then a refused no-limit retries once as 24 hours, then bare).
- Guild bot rows show the live order (`Light Leather 4/10 (Ashenvale) · Easy`, `No limit` on orders with no time limit, `Delivering`, `Done`, `Stocked` for a delivered keep order, `Mailed to GM`, `No skill`, `Can't`, including when the farm time ran out or the bot worked 3 hours without gaining a single item; keep orders carry a `Keep` marker) with the reason, the chosen farm time (or `no limit`) and the refill level in the tooltip (the tooltip explains the difficulty as rough effort: how many kills, gathers or casts the bot needs); Cancel asks first, naming the bot and item, and only Yes removes it — cancelling is the only way to end a no-limit order or a stocked keep order. Needs the `guild-orders` server capability and a guild rank that may edit officer notes.
- Supply chain: the order window header shows the bots' guild rank, bank tabs and gold access (red with what is missing, grey when the server leaves ranks alone or no bank is unlocked yet); players with rank rights get a Rank button stepping the bots' rank. Every order and sub-order is a live row — bot, item, have/amount and readable step (`taking from guild bank`, `buying on AH`, `farming in Elwynn`, `crafting`, `waiting for sub-order`, `needs items from you`, `delivering`) — sub-orders indented under their parent. A `needs items from you` order names the missing items in the tooltip (trade, mail or put them in the guild bank). **Max guild gold** (empty = no cap) caps guild spending per give (`gold=<copper>`; old servers retry without it). Guild-tab sub-order rows carry **Mv**: a dropdown of the guild's bots (excluding the worker; "no other bots" message when empty) — pick, confirm, send (`.bot order reassign`); the **Rank** button lists guild rank names (GM skipped, current row disabled; pick, confirm, send `.bot order rank`). `gold=0` caps guild gold to nothing (empty means no cap). Parent Cancel warns it takes the whole branch at any depth. Same `guild-orders` capability, same officer-note gate.

---

## v1.4.1 (2026-10-28)

### Roster & Lifecycle
- Guild tab claimed bot list now refreshes correctly on the 1.12 client instead of going blank after the first refresh. [#50](https://github.com/Sagiroth/TortoiseBotsManager/pull/50)
- Clearing the claimed list now resets the client’s remembered list length, preventing empty-slot sorting failures and the “Roster.lua:278: attempt to index local 'b' (a nil value)” chat error every 8 seconds. [#50](https://github.com/Sagiroth/TortoiseBotsManager/pull/50)
---

## v1.4.0 (2026-10-27)

### Loot & History
- New Loot tab with a 24-hour history of what your bots looted: every item, money amount and roll vote, each with the reason for the roll. [#47](https://github.com/Sagiroth/TortoiseBotsManager/pull/47)
- Items are shown in their quality colour, with combinable filters for bot, item, quality, source and row type, plus a clear button and paging to reach older rows. [#47](https://github.com/Sagiroth/TortoiseBotsManager/pull/47)
- History is stored locally per character, capped at 2000 rows; on login the addon asks the server for the last 24 hours and appends only rows it has not seen yet. [#47](https://github.com/Sagiroth/TortoiseBotsManager/pull/47)
- Loot now lands in the tab live as the server reports it, so the list keeps up with the bots while you play. [#48](https://github.com/Sagiroth/TortoiseBotsManager/pull/48)

### Party & Summoning
- Summon button on every bot row in the Party tab, plus Summon Party and Summon Raid buttons to pull the whole group in one click. [#48](https://github.com/Sagiroth/TortoiseBotsManager/pull/48)

### UI & Controls
- Hovering a loot row now shows the item's full tooltip, so you can check stats without leaving the tab. [#48](https://github.com/Sagiroth/TortoiseBotsManager/pull/48)

---

## v1.3.4 (2026-10-27)

### Comms & Protocol
- When a dungeon run pauses at a locked door, the status line now tells you exactly what opens it—e.g., "open with Shadowforge Key (item 11000) or Lockpicking 250"—so you can resume without guesswork. [#46](https://github.com/Sagiroth/TortoiseBotsManager/pull/46)

---

## v1.3.3 (2026-10-26)

### Documentation
- README is now short and consistent with the TortoiseBots README: same headings, release badge, a "requires the TortoiseBots module" note, and proper install steps [#45](https://github.com/Sagiroth/TortoiseBotsManager/pull/45)
- Tab overview is now a single accurate table — the Dungeon tab is finally documented, and the dungeon run is no longer misdescribed as a Party tab button [#45](https://github.com/Sagiroth/TortoiseBotsManager/pull/45)
- New `docs` folder in the same knowledge-base format as TortoiseBots, covering getting started and a full feature catalog, with a documentation table linking it all from the README [#45](https://github.com/Sagiroth/TortoiseBotsManager/pull/45)

---

## v1.3.2 (2026-10-26)

### UI & Controls
- Party tab role buttons now use the same spec names as the recruiter, so what you hired is exactly what you see. [#44](https://github.com/Sagiroth/TortoiseBotsManager/pull/44)
- Warrior gains a Fury role button; Priests now show Holy / Discipline / Shadow instead of a vague Hybrid; Shaman gets its missing tank option. [#44](https://github.com/Sagiroth/TortoiseBotsManager/pull/44)
- No more guessing which spec a bot was recruited as — role labels are consistent across every class. [#44](https://github.com/Sagiroth/TortoiseBotsManager/pull/44)

---

## v1.3.1 (2026-10-26)

### Tactical & Roles
- Party tab role buttons now reflect each bot's real server-reported spec — fresh Retribution and Balance hires show as DPS, and holy priests who also deal damage correctly read as Hybrid [#43](https://github.com/Sagiroth/TortoiseBotsManager/pull/43)
- Your own row in the Party tab is now clearly a "role you fill for your bots" selector, not a spec swap — no more confusion about accidentally respeccing yourself [#43](https://github.com/Sagiroth/TortoiseBotsManager/pull/43)

### UI & Controls
- Follow, Stay, Guard, and Free now stay visibly lit in the party panel, so you can always tell which lasting move mode your party is in at a glance [#43](https://github.com/Sagiroth/TortoiseBotsManager/pull/43)

---

## v1.3.0 (2026-10-26)

### Dungeon Runs
- New **Dungeon** tab in the main window, shown only when your server has the dungeon run enabled — no more dead tab on servers without it. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- Both run modes are spelled out in plain words, with a run-at-a-glance summary and the run window opening straight from the tab. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- The run window now handles **who leads**: pick *Bots lead* for a bot tank to take point while you stay in the party (healers and damage), or *I lead* to walk the route while bots pull nearby packs (tanks). [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- A switch on the run window always shows the currently picked lead mode, so nobody has to guess mid-run. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- The old dungeon button on the Party tab is gone — dungeon controls all live in one place now. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)

### UI & Controls
- Flat button styling across the addon for a cleaner, less noisy look. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- Mini bar favourites: keep your most-used actions one click away. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)
- Server info surfaced in the UI so you can see what the connected server actually supports before you plan a run. [#42](https://github.com/Sagiroth/TortoiseBotsManager/pull/42)

### Docs & Release Comms
- v1.2.0 changelog is complete again: bot panel, Dungeon run (Preview), fixes and the required server are all listed, and the stray "Unreleased" section is gone. [#41](https://github.com/Sagiroth/TortoiseBotsManager/pull/41)
- New manual **"Re-post Discord changelog"** workflow to push a single release's changelog section to the changelog thread when the automatic post misses. [#41](https://github.com/Sagiroth/TortoiseBotsManager/pull/41)
- Releases now post the full changelog to the changelog thread, matching TortoiseBots — the short release announcement links there instead of repeating half the notes. [#40](https://github.com/Sagiroth/TortoiseBotsManager/pull/40)

---

## v1.2.0 (2026-10-25)

### Tactical & Actions
- Sap and Spread now have party-wide toggles alongside AoE, Auto CC, and Loot; the UI shows "Mixed" when bots differ. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- End a pull instantly with the new End pull button in the pull card. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Movement controls add Guard and Free next to Follow, Stay, Come, and Hold, plus stance buttons: Near, Tank, Turnback, Behind. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- New Tactics card gives one-click Kite, Auto Mark, Focus Fire, and AoE Fear. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Camp & Formations
- Camp tab adds Rebuff, Reset tactics, and Drop totems actions. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Formations expanded from six to ten slots. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Quests card: accept and share quests, toggle grinding on/off; Ready now also triggers the game's ready check. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Roster & Guild
- Class filter plus Fill party and Fill raid for faster group setup. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Key bindings added for the new roster and guild controls. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Bot panel
- New Spells tab: the bot's spells, paged; click a spell to cast it. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Item menu adds Use, Disenchant, Send by mail, Put to bank and Destroy (asks first); soulbound items keep Disenchant and Bank. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- New Bank and mailbox window for the open bot: withdraw items and take letters, paged. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- New NPC window: talk, bind at the inn, learn from a trainer, make leader, pick a flight. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Upkeep and AutoGear buttons, mimic and spread switches per bot, and Equip upgrades in the bags view. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Dungeon run (Preview)
- A Dungeon run window on the Party tab binds your bot party, takes it into the dungeon, picks a plan and starts, pauses, resumes, skips or stops the run with live progress. It only appears when the server has the dungeon run turned on. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Fixes
- Damage and healer role changes now reach the bots (they were sent in a form the server ignored). [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- The roster no longer goes empty with ClassicAPI.dll, and one bad roster line no longer empties the whole roster. Fixes [#38](https://github.com/Sagiroth/TortoiseBotsManager/issues/38). [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)
- Layout: nothing overlaps or runs out of its window, labels fit their buttons, and the new windows can be dragged safely in the 1.12 client. [#39](https://github.com/Sagiroth/TortoiseBotsManager/pull/39)

### Needs a server
- Stances, Guard/Free, End pull, Rebuff, Reset tactics, the toggle status queries and the sap state need TortoiseBots with [PR #1247](https://github.com/Sagiroth/TortoiseBots/pull/1247) (released in [#1248](https://github.com/Sagiroth/TortoiseBots/pull/1248)).

---

## v1.1.0 (2026-10-19)

### UI & Controls
- Introduced shared UI building blocks (card, button, toggle, stepper, row, icon button) and a single spacing grid, so future visual changes land in one place instead of every tab [#36](https://github.com/Sagiroth/TortoiseBotsManager/pull/36)
- Fight and Camp tabs now build one card at a time, cutting down the giant single builder that used to handle both [#36](https://github.com/Sagiroth/TortoiseBotsManager/pull/36)
- Fight/Camp buttons and the mini bar now read from a single shared action table — no more two hand-maintained copies drifting apart [#36](https://github.com/Sagiroth/TortoiseBotsManager/pull/36)

### Tactical & Actions
- Role handling (tank, healer, DPS) consolidated into one code path instead of three separate implementations [#36](https://github.com/Sagiroth/TortoiseBotsManager/pull/36)

### Compatibility
- Pure groundwork: no visible UI changes and no changes to what's sent over the wire — existing tabs behave exactly as before [#36](https://github.com/Sagiroth/TortoiseBotsManager/pull/36)

---

## v1.0.1 (2026-10-17)

### Roster & Lifecycle
- Alt-bots seen playing alone are now flagged directly in the roster with an "Alt-bot · Playing alone" label and tooltip, so you can spot them at a glance [#35](https://github.com/Sagiroth/TortoiseBotsManager/pull/35)
- Login on an alt-bot row recruits it back as your companion (`.bot add`); Logout sends it on its way, reusing the controls you already know [#35](https://github.com/Sagiroth/TortoiseBotsManager/pull/35)
- Flags reset on every new roster snapshot, so the feature stays silent on older servers and never lingers stale [#35](https://github.com/Sagiroth/TortoiseBotsManager/pull/35)
- Regression tests cover the new parsing and flag lifecycle (`lua5.1 tests/regression.lua` passes) [#35](https://github.com/Sagiroth/TortoiseBotsManager/pull/35)

### Comms & Protocol
- Parses the new `TBM:ALTBOTS|<names>` line sent after roster rows; the existing roster row protocol is untouched [#35](https://github.com/Sagiroth/TortoiseBotsManager/pull/35)

---

## v1.0.0 (2026-10-17)

### UI & Controls

- The header drag bar no longer swallows clicks on the **Mini** button — clicking it now toggles the compact window exactly like `/tbm mini` does, including the hover/press highlight. [#34](https://github.com/Sagiroth/TortoiseBotsManager/pull/34)
- You can still drag the window by the header; the drag area just stops short of the Mini button, and the Mini/close buttons are raised above the drag layer so they always win the click. [#34](https://github.com/Sagiroth/TortoiseBotsManager/pull/34)
- Added a regression test covering the header/button click priority, so this overlap doesn't sneak back in. [#34](https://github.com/Sagiroth/TortoiseBotsManager/pull/34)

---

## 2026-10-14

### Comms & Protocol
- Changelog posts (auto-post, re-post, and edits) now land in the dedicated Discord changelog thread using its own `DISCORD_CHANGELOG_WEBHOOK_URL` secret, keeping release chatter out of the issue feed. [#32](https://github.com/Sagiroth/TortoiseBotsManager/pull/32)
- Issue notifications are untouched — they still use the original webhook and thread, so nothing changes for bug reports and PR pings. [#32](https://github.com/Sagiroth/TortoiseBotsManager/pull/32)

---

## 2026-10-07

### Guild Tab & Claimed Guild Bots (Issue #489)
- New dedicated **Guild** tab for managing autonomous wandering bots claimed into your guild as personal raid alt-bots.
- **Raid Assembly:** Checkbox multi-select with one-click **Invite to Raid** and **Summon to Raid** buttons.
- **Gear Protection Transparency:** Clear visual badges distinguishing Level 60 `[Locked]` gear (hard-locked: bots never self-equip or auto-vendor) from Level 1–59 `[Leveling]` gear (self-equips world upgrades, preserves blues & epics).
- **One-Click Gear & Bags Paperdoll:** Backpack button on each row opens `BotPanel` showing equipped items, durabilities, bags, and gear lock status.
- **Combat Role Cycling:** One-click role button on each row cycles combat roles (Tank, Healer, DPS, spec strategies) and sends `.bot role` updates.
- **Release Confirmation:** Release button with confirmation popup unclaims bots back to the wandering pool via `/gkick`.
- **Responsive Tab Bar:** Dynamic width and stride adjustments so all 6 or 7 tabs fit cleanly across the standard panel width.

### MiniBar Fixes
- Mini mode now restores the bar on reload/login even when the login events fire before the UI initializes, and also re-applies on `InitUI`.
- Mini bar sits on `DIALOG` strata, clamps to screen, drags from the background as well as the turtle handle, and `/tbm resetpos` re-centers it.

---

### Guild Roster
- New Guild tab lists your claimed bots, with gear inspection built in so you can audit loadouts without leaving the panel. [#31](https://github.com/Sagiroth/TortoiseBotsManager/pull/31)
- Cycle roles directly from the Guild tab and use assembly to gather the group in one click. [#31](https://github.com/Sagiroth/TortoiseBotsManager/pull/31)
- Release prompt added for claimed bots, so handing a companion back is an explicit action. [#31](https://github.com/Sagiroth/TortoiseBotsManager/pull/31)

### UI & Controls
- MiniBar strata corrected — it no longer sinks behind other frames. [#31](https://github.com/Sagiroth/TortoiseBotsManager/pull/31)
- MiniBar drag support works as expected, and its position is restored correctly after a UI reload. [#31](https://github.com/Sagiroth/TortoiseBotsManager/pull/31)

## 2026-10-05

### UI & Controls
- The Mini button and `/tbm mini` no longer fail silently after an addon update — if the mini bar isn't loaded yet, you now get a chat message telling you to fully restart the game client (a `/reload` won't cut it on 1.12) [#30](https://github.com/Sagiroth/TortoiseBotsManager/pull/30)
- Regression test added to keep this from sneaking back in [#30](https://github.com/Sagiroth/TortoiseBotsManager/pull/30)

---

## 2026-09-27

### UI & Controls
- New tabbed layout by task: `Fight` · `Camp` · `Party` · `Roster` · `Raid` (raid-only) · `Log` — no more hunting through one long panel [#29](https://github.com/Sagiroth/TortoiseBotsManager/pull/29)
- `Fight` tab groups Engage (Attack, Stop, Interrupt, Flee), Pull & Focus (timers, Skull, CC mark), Move (Follow, Stay, Come) and switches; add `Camp` for Rest, Ready Check, Repair, Sell junk, Train, Release/Corpse run, plus six formations including the new Line [#29](https://github.com/Sagiroth/TortoiseBotsManager/pull/29)
- AoE / Auto CC / Loot switches now reflect the server's real state (On / Off / Mixed with a status lamp) instead of guessing [#29](https://github.com/Sagiroth/TortoiseBotsManager/pull/29)
- Mini mode and the bot gear panel are now available for tighter screen real estate and quick equipment checks [#29](https://github.com/Sagiroth/TortoiseBotsManager/pull/29)

### Meta & Attribution
- Author credit now shows in the window header (`TBM <addon> · server <server> · by Sagiroth`), the load message, and `/tbm help`, with `## Author` and repo link set in the `.toc` [#28](https://github.com/Sagiroth/TortoiseBotsManager/pull/28)
- README gains a paste-ready credit section and updated version-line docs; regression tests assert the new header line [#28](https://github.com/Sagiroth/TortoiseBotsManager/pull/28)

---

## 2026-09-25

### Tactical & Actions
- New **CC Marks panel** replaces the old target-first picker — open it from the Actions tab's "CC Mark" button and assign marks without targeting a bot first. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- Eight rows, one per raid icon, each showing the mark's current owner at a glance. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **Next** per row sends `cc <mark> <Bot>`, cycling through bots by name so you can rotate marks without retyping names. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **X** per row sends `cc clear <Owner>` to release a single mark. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- **Clear all** at the bottom sends `cc clear` to wipe every assignment in one click. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)

### UI & Controls
- Panel stays open across target changes, so you can hand out several marks in one pass. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)
- "CC Mark" button is now a plain label — no more hardcoded Moon icon misleading you about the current assignment. [#23](https://github.com/Sagiroth/TortoiseBotsManager/pull/23)

---

### Build & Versioning
- Per-merge build versions (`<UTC date>-v<N>`) are now stamped into `Constants.lua` (`TB.C.VERSION`) and the `.toc` `## Version:` field on each `[skip ci]` bot commit, with a lightweight tag per build — no more guessing which build you're running. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)
- The daily release, zip and Discord post stay in place, and the daily tag moves to the latest build. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)
- `/tbm` now displays `TBM <addon version> · server <server version>`, with the server version read from the module's `TBM:VERSION|…` line. [#24](https://github.com/Sagiroth/TortoiseBotsManager/pull/24)

### CI & Releases
- The build-version workflow now actually completes: stamped version files are committed before `git pull --rebase`, so the run no longer aborts on unstaged changes. [#25](https://github.com/Sagiroth/TortoiseBotsManager/pull/25)
- Releases are only created or edited when notes were actually written; the daily tag still moves to the latest build. [#25](https://github.com/Sagiroth/TortoiseBotsManager/pull/25)
- Build range now shows up in titles: releases list as `<repo> <date> (builds v1–vN)` and the Discord embed as `<repo> build <date>-vN`, with the link still pointing at the daily release. [#26](https://github.com/Sagiroth/TortoiseBotsManager/pull/26)

### Tactical & Actions
- Pull and Pull back now accept an adjustable timer: set a pull DPS delay (default 10 s) and a pullback join delay (default 3 s), each tunable from 0-60 s, so your bots engage and regroup on your schedule instead of a fixed cadence. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Timers are sent as `pull <n>` / `pullback <n>` commands, keeping the same command/addon transport you already use, so nothing changes in how you issue orders. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

### UI & Controls
- New compact "- N s +" steppers sit directly under the Pull and Pull back buttons in the Actions tab, styled to match the existing panel buttons; shift-click steps by 5 for fast coarse adjustment. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Tooltips on the steppers explain what each delay controls, so group leaders can tune timing without guessing. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

### Comms & Protocol
- Both delays persist as SavedVariables, so your preferred timings are remembered across sessions. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)
- Timed pulls are only sent when the server advertises `pull-seconds` in its `TBM:CAPS` roster trailer; the capability list is parsed robustly. On older servers without it, the addon falls back to plain pull/pullback intents exactly as before — no breakage. [#27](https://github.com/Sagiroth/TortoiseBotsManager/pull/27)

## 2026-09-24

### UI & Controls
- Added one-click player role override buttons on your row in the Party tab, using your class’s available roles so you can swap without leaving `/tbm`. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)
- Selected role now highlights in gold for instant feedback. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

### Tactical & Actions
- Clicking a role button sets `TortoiseBotsDB.playerRole` and issues `.bot role self <tank|healer|dps>` to the server. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

### Testing & Docs
- Added unit and regression coverage in `tests/regression.lua`, and updated README and CHANGELOG. [#22](https://github.com/Sagiroth/TortoiseBotsManager/pull/22)

---

## 2026-09-23

### UI & Controls

- Window dragging is now isolated to the title/header bar only — clicking action buttons like **Attack** no longer starts an accidental frame drag. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)
- Eliminated the fatal client crash (**ERROR #132 ACCESS_VIOLATION**) caused by `StopMovingOrSizing()` re-anchoring the main dialog during unintended drags. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)
- Buttons and controls inside the dialog now respond reliably without moving the parent window. [#21](https://github.com/Sagiroth/TortoiseBotsManager/pull/21)

### Roles & Party

- The Party tab now exposes player role buttons, persists the selected display role, and sends `.bot role self <tank|healer|dps>`. [#264](https://github.com/Sagiroth/TortoiseBots/issues/264)

---

## 2026-09-22

### Comms & Protocol
- Summon rejections caused by the server's GM-gate are now recognized, so the optimistic `SUMMONING` state resolves to a visible failure instead of hanging until it times out. [#20](https://github.com/Sagiroth/TortoiseBotsManager/pull/20)
- Adds a `summonRestricted` pattern included in the summon-failure disjunction, mirroring the NonGmFreeSummon gate from TortoiseBots #255; regression.lua passes. [#20](https://github.com/Sagiroth/TortoiseBotsManager/pull/20)

---

## 2026-09-21

### CI, Docs & Project
- Added Discord issue alerts and an automated changelog/release pipeline. [#18](https://github.com/Sagiroth/TortoiseBotsManager/pull/18)
- Standardized public naming and docs on Tortoise WoW. [#15](https://github.com/Sagiroth/TortoiseBotsManager/pull/15)
- Fixed README links after ownership transfer and removed broken/personal paths. [#11](https://github.com/Sagiroth/TortoiseBotsManager/pull/11)
- Added MIT license and clarified the addon does not ship the game client/assets or run a hosted service. [#4](https://github.com/Sagiroth/TortoiseBotsManager/pull/4)

### Roles & Party
- Added a Party tab for viewing party members and one-click class role switching. [#10](https://github.com/Sagiroth/TortoiseBotsManager/pull/10)
- Tank button now forces `.bot role <name> tank`; Tank→DPS demotion clears forced role before applying the spec strategy. [#17](https://github.com/Sagiroth/TortoiseBotsManager/pull/17)

### Tactical & Actions
- Added an Interrupt button that sends exactly one `.bot action interrupt` and reports ACK/ERR results. [#13](https://github.com/Sagiroth/TortoiseBotsManager/pull/13)
- Added per-bot CC raid-mark assignment UI with all eight icons and live current-mark display on targetable party rows. [#14](https://github.com/Sagiroth/TortoiseBotsManager/pull/14)
- Added formation presets, Come & Hold, ready check, and hold/stack actions, and removed redundant roster refresh/filter buttons. [#8](https://github.com/Sagiroth/TortoiseBotsManager/pull/8)
- Made selected-bot controls state-aware for guard, free, attack, ready, formation, and status; moved pullback to target-scoped party controls. [#2](https://github.com/Sagiroth/TortoiseBotsManager/pull/2)
- Surface native pullback and master-assignment failures from reworked safe-summon/pullback responses. [#3](https://github.com/Sagiroth/TortoiseBotsManager/pull/3)

### UI & Controls
- Revamped Actions/Roster with card layout, class colors, icons, master select-all, and fixed roster anchoring/alt discovery. [#7](https://github.com/Sagiroth/TortoiseBotsManager/pull/7)
- Replaced the mixed Party/Roster UI with Actions and Roster tabs, authoritative snapshots, offline rows, multi-select, contextual Login/Logout/Invite/Kick/Summon, structured TBM parsing, and local chat filtering. [#6](https://github.com/Sagiroth/TortoiseBotsManager/pull/6)
- Compacted the panel to 500×395 with Party/Roster tabs, removed redundant AI Command/Add bars, and bumped to 1.0.0. [#5](https://github.com/Sagiroth/TortoiseBotsManager/pull/5)

### Comms & Protocol
- UI commands now go over the addon command channel when advertised, avoiding chat-frame and nearby-player spam; fallback remains `.bot` chat. [#16](https://github.com/Sagiroth/TortoiseBotsManager/pull/16)
- Added a timestamped bot activity log tab and filtered bot lifecycle announcements out of `/say`/General chat. [#9](https://github.com/Sagiroth/TortoiseBotsManager/pull/9)

### Core & Reliability
- Made the addon Vanilla 1.12-safe: button roster rows, safe partial init, fixed reconciliation timers/throttled queue, reconcile after `.bot list`, explicit Stats/Help/AI controls, optimistic rollback, and version 0.1.1. [#1](https://github.com/Sagiroth/TortoiseBotsManager/pull/1)
- Added core, comms, roster, and UI updates with regression coverage. [#12](https://github.com/Sagiroth/TortoiseBotsManager/pull/12)

---

### Roster & Lifecycle
- Raid roster changes now refresh reactively: the watcher listens to the 1.12-compatible `RAID_ROSTER_UPDATE` event instead of the Retail-only `GROUP_ROSTER_UPDATE`, so raid converts and subgroup shifts update group membership correctly. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)

### UI & Controls
- Fixed formation metadata being clobbered: structured `TB.C.FORMATIONS` now stays intact for id/label/tip lookups, while raw formation IDs live in `TB.C.FORMATION_IDS`, restoring formation labels and tooltips. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)

### Tactical & Actions
- Hunter Survival and Rogue Subtlety are back in `CLASS_ROLES`, matching backend strategy support so those specs can be assigned and recognized properly. [#19](https://github.com/Sagiroth/TortoiseBotsManager/pull/19)
