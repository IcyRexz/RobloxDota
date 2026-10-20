# Game design document

Co-op base-defense shooter (owner decision 2026-10-20; brief in `docs/01_BRIEF.md`). Numbers marked *(carried)* come from the MOBA prototype code in `src/shared/Config.luau` and are starting points only. Anything marked **OPEN** waits for an owner decision; do not invent it. Keep this file and `Config.luau` consistent as systems land.

## Structure of a session
Hub -> mission (Briefing -> Build phase -> Wave -> Build phase -> … -> Final wave) -> Results -> back to Hub.

- **Hub:** shared area in the same place as the mission arena (owner decision 2026-10-20). Players pick a class, equip unlocked weapons/gear and stand on a queue pad (or similar) to start a mission. Map choice limited by class level.
- **Party size:** 1–5 players per mission. Server capacity 5 (to confirm when the hub is built; with one shared arena only one mission runs per server).
- **Mission state flow:** Hub -> Briefing (short countdown; leaving cancels) -> BuildPhase -> Wave -> BuildPhase -> … -> Results -> Resetting -> Hub. Every match has an epoch; delayed callbacks from an older epoch never act.
- **Win:** the final wave (full version: a boss) is cleared with the Base Core still standing.
- **Lose:** the Base Core is destroyed. Full party wipe: **OPEN**.
- **Leaving mid-mission:** the mission continues for the rest of the party; if the last player leaves it resets. Rewards for leavers: **OPEN**.

## Map layout (mission)
- **Bottom half:** walled compound with the **Base Core** near the bottom edge, player spawn inside the compound, gaps/gates in the wall line, and pre-placed **build nodes**.
- **Top half:** open ground; enemies spawn along the top edge and cross it toward the compound.
- **Camera (kept from the prototype):** fixed elevated follow camera, 55° down, 70 studs back, FOV 40, smooth follow, never rotates; compound at the bottom of the screen, enemies arrive from the top (`src/client/HeroCamera.client.luau`). Shift lock disabled; jump disabled (jump power 0 in `default.project.json`).
- **Reuse:** the current graybox in `src/map/` (Blue base, lane, Red base, decor) is the starting point: Blue base -> compound, lane -> open ground, Red base area -> enemy spawn zone. Exact dimensions **OPEN** until T03.

## Players and classes
- Each player's Roblox avatar is their character (as in the prototype); the server marks it, owns Health/MaxHealth attributes and removes default regen *(carried: 600 HP, WalkSpeed 16, respawn 5 s)*.
- **Classes:** Assault, Engineer, Medic, Heavy. Each has its own stats and level. Abilities and stat differences **OPEN**. Classes can obviously lean on the base systems (e.g. Engineer and building/repair, Medic and healing/revive, Heavy and durability) — owner to confirm.
- **Weapons:** each player fires their equipped weapon. PC: mouse aim is the working assumption (**OPEN** to confirm). The prototype's Pulse attack (auto-target nearest enemy within 24 studs, line of sight, 40 damage, 0.75 s cooldown, 0.15 s windup, server-validated target hint) is the starting server path for firing *(carried)*. Ammo/reload **OPEN**.
- **Death/respawn:** **OPEN** (respawn timer, revive, penalties).

## Enemies and waves
- **Reuse:** the prototype minion system (`src/server/Minions.server.luau`) becomes the enemy system: wave spawner with an alive cap *(carried: cap 30)*, waypoint walking, sticky targets, 12-stud / 3 s leash, retaliation within 20 studs, smooth turning (270°/s), melee and ranged types (the archer's draw-then-arrow attack, damage on arrival), 70% scale.
- **Targets:** enemies attack players, walls (and other built structures) and the Base Core. Priority order **OPEN**; working default: nearest player in aggro range, else whatever blocks the path (wall/turret/trap), else the core.
- **Waves:** number of waves per map, composition, spacing and scaling **OPEN**. Waves start after the build phase timer ends (or when all players ready up — **OPEN**).
- **Boss:** the final wave of the full version is a boss. Design **OPEN**.
- Enemy types beyond melee and ranged: **OPEN**.

## Gold, building and repair
- **Gold** is earned in-match by killing enemies. `CombatService` already reports the killer, so kill credit is ready. Per-player vs team pool **OPEN**. Gold resets every mission.
- **Build phase:** between waves; duration **OPEN**. Players spend Gold at pre-placed build nodes on:
  - **Walls:** block enemies; enemies attack them.
  - **Turrets:** fire at enemies. Reuse the prototype tower AI in `src/server/Structures.server.luau` *(carried: range 28, 60 damage every 1 s, glowing shot 80 studs/s with damage on arrival, keeps its target while in range)*, its visuals (`TowerVisuals.server.luau`, `TowerEffects.client.luau`, the knight `assets/TowerModel.rbxmx` as possible turret art) and the range ring.
  - **Traps:** **OPEN** (types, trigger, damage).
- **Repair:** players spend Gold (or time — **OPEN**) to restore damaged walls/turrets/traps (and the core? **OPEN**) before the next wave. Repair during waves **OPEN**.
- Catalogue, prices, health and node layout **OPEN**.
- Removed from the prototype: tower -> barracks -> core lock order, tower damage ramp on heroes, backdoor protection, barracks minion bonus, minion lifetime despawn rule (enemies now live until killed — confirm).

## Base Core
Single core per mission *(carried: core health 1200)*. Does not attack. Its health bar is always visible on the HUD. When it reaches 0 the mission is lost immediately; result committed once.

## Persistent progression
- Saved per player (DataStores; first persistence in the project): credits, per-class level and XP, owned weapons/gear, current loadout per class.
- **Credits** earned per mission (amount by result/map/difficulty **OPEN**), spent in the hub on weapons and gear.
- **Class XP** per mission for the class played; levels unlock harder maps with better rewards. Curves and caps **OPEN**.
- Saving must handle DataStore failures without losing or duplicating progress (session lock / retry rules decided in T20).

## HUD and presentation (PC first)
- **Kept from the prototype:** overhead name + segmented health bar on each player, health bars on enemies and structures within 60 studs of your character *(carried)*, damage numbers and hit flash, MLBB-style announcement banner (to be reused for "WAVE 3 INCOMING", "BUILD PHASE", "CORE UNDER ATTACK", win/loss).
- **New:** Gold counter, wave counter and phase timer, Base Core health bar, ammo/weapon slot, class badge and level (replaces the "LV 1" placeholder), build menu at nodes, results screen with rewards.
- Mobile layout comes with the mobile port (T26).

## Removed with the genre switch
Archived in `docs/archive/moba/` (see that folder for the full rules): 1v1 teams Blue vs Red, lane objectives (tower, inhibitor, core per side), hero Zeus's Arc Bolt and Slip, match timeout tiebreaks, rematch-by-both-players, minion lane push rules, tower targeting of heroes, the 7/14-day schedule.
