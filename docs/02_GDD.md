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
Open battlefield for swarm defence (owner redesign 2026-10-20, replacing the same-day two-lane map; `src/map/`). The map runs along X: our base at negative X is the bottom of the screen, zombies come from positive X at the top. Screen-left is -Z, screen-right is +Z. Simple low-poly graybox style.
- **Battlefield** (`Battlefield.model.json`): one open grass ground 423×420 studs (x -153..270, z -210..210); the base sits flush against its bottom edge (owner 2026-10-20). No lanes, no road strips, no arena walls. The fighting happens roughly between x -150 and 160, z ±130, so the edges are far from it.
- **Boundary:** the base's back wall is the bottom edge; TEMPORARY invisible walls on the other edges and just behind the back wall (`Kind = Boundary`) until natural edges are built (T03a).
- **Base** (`PlayerBase.model.json`, bottom half): stone floor x -150..-70, z -66..66, walls 8 tall. A front wall facing the enemy covers the middle (z -34..34); back and side walls close the rest, leaving two **broad openings** (32 studs each) at the front-left and front-right corners (z ±34..66). A tower guards each opening (`LeftTower` / `RightTower`, x -84, z ±50; 900 HP; knight art). Behind each tower an inhibitor (`LeftInhibitor` / `RightInhibitor`, Kind `Barracks`; x -104, z ±30; 700 HP). `BaseCore` in the centre (x -118, z 0; 1200 HP). Player spawn pad behind the core (x -138). Invisible `Opening` markers mark each gap for the swarm code.
- **Zombie side** (`ZombieBase.model.json`): two zombie spawning cores, `LeftZombieCore` and `RightZombieCore` (x 150, z ±70; 12×14×12; 1200 HP; dark green), spaced apart across the top. They do not attack.
- **Objective order** (each structure's `GuardedBy` attribute; rule in `Targeting.isLocked`): an inhibitor cannot be damaged while its tower stands; the Base Core cannot be damaged while **both** inhibitors stand. Zombie cores have no guards.
- **Unit spawns:** our minions spawn just inside the base in front of each inhibitor; zombies spawn in front of each zombie core, scattered within 7 studs. A spawn point stops once its source structure falls.
- **Camera (kept from the prototype):** fixed elevated follow camera, 55° down, 70 studs back, FOV 40, smooth follow, never rotates; base at the bottom of the screen, zombies arrive from the top (`src/client/HeroCamera.client.luau`). Shift lock disabled; jump disabled.
- **Not built yet (owner: keep as tasks, do not implement now):** natural map edges (irregular terrain, cliffs, mountains, dense forest) replacing the invisible boundary, kept well away from the combat area (T03a); occasional rocks, ruins or terrain features for variety that never divide the map into corridors or lanes (T03b). Compound build nodes are also still planned (placement **OPEN**).

## Players and classes
- Each player's Roblox avatar is their character (as in the prototype); the server marks it, owns Health/MaxHealth attributes and removes default regen *(carried: 600 HP, WalkSpeed 16, respawn 5 s)*.
- **Classes:** Assault, Engineer, Medic, Heavy. Each has its own stats and level. Abilities and stat differences **OPEN**. Classes can obviously lean on the base systems (e.g. Engineer and building/repair, Medic and healing/revive, Heavy and durability) — owner to confirm.
- **Weapons:** each player fires their equipped weapon. PC: mouse aim is the working assumption (**OPEN** to confirm). The prototype's Pulse attack (auto-target nearest enemy within 24 studs, line of sight, 40 damage, 0.75 s cooldown, 0.15 s windup, server-validated target hint) is the starting server path for firing *(carried)*. Ammo/reload **OPEN**.
- **Death/respawn:** **OPEN** (respawn timer, revive, penalties).

## Enemies and waves
- **Current state (owner redesign 2026-10-20):** every 25 s (first at 5 s) each standing zombie core sends 16 **zombies** (doubled from 8) and each standing inhibitor sends our wave (4 melee + 1 archer, blue). Zombies are all melee on the standard Roblox R15 body at 70% scale: dark green skin, blood-red torso, muddy green legs, no face, glowing red eyes, both arms stretched forward. Attack: a **bite** (owner approved 2026-10-20, keep): the body leans back, then the upper body and head lunge forward; the shoulder also moves (arms alternate), played on each client from the server's `MinionSwing` event like the archer draw; the damage lands when the claw comes down (`ZombieSwipeHitDelay` 0.3 s) and a zombie killed mid-swing never lands it. Unit cap 100 (check frame rate). Inhibitor bonus (+25% on later spawns for the side that destroys one) still applies. Code team id for zombies is `Red`; banners say "ZOMBIES".
- **Unit stats** (`Config.Minion`; order: health, attack, range, attack speed, movement speed, aggro):

  | Unit | Health | Attack | Range | Attack speed | Move speed | Aggro |
  |---|---|---|---|---|---|---|
  | Zombie | 120 | 12 | 5 (melee) | 1 hit / 1 s | 8 | 14 |
  | Our melee minion | 144 | 14 | 5 (melee) | 1 hit / 1 s | 8 | 16 |
  | Our archer minion | 96 | 12 | 16 (arrow 60 studs/s) | 1 shot / 1 s (0.3 s draw) | 8 | 22 |

  Our minions were buffed +20% health and attack and given wider aggro on 2026-10-20 (owner: they were walking past zombies). Was melee 120 / 12 / aggro 8, archer 80 / 10 / aggro 16.

- **Aggro (standard rules, owner 2026-10-20):** a unit attacks, in order: whoever damaged it (unit, hero **or tower**), chasing while that attacker is within 32 studs (`RetaliateRange`, beyond tower range 28); the structure it is already hitting; the nearest enemy unit in aggro range; the nearest enemy hero in aggro range; the nearest unlocked enemy structure in aggro range (measured to its side). **Call for help:** when a unit is hit, same-team units within 10 studs (`HelpRange`) that are not already fighting back join in on the attacker. A hero hit by an enemy hero still pulls that hero's nearby minions onto the attacker.
- **Swarm movement** (`src/server/SwarmField.luau` + `Minions.server.luau`): no lanes or routes. The server keeps flow fields on a 4-stud grid (shortest walking distance around walls and structures, rebuilt when a structure falls). Units walk downhill on their field, plus **separation** (same-team units within 3.5 studs push apart) and a slowly changing sideways **wander**, so the horde fans out over open ground, flows around obstacles and converges on the openings. Each zombie picks one base opening at spawn, weighted 1/distance² (about 55% / 45% from either core), so neither core feeds only one opening. Our minions follow a field to the nearest zombie core. A unit with an enemy in aggro range leaves the field, closes in while still spreading out and surrounds the target instead of stacking; units standing to fight shuffle apart if packed.
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
- Prototype rules not used in the new design (code still present until replaced): tower damage ramp on heroes, backdoor protection, minion lifetime despawn (180 s; whether enemies should live until killed is **OPEN**). The tower -> inhibitor -> core order and the inhibitor bonus are back for now (2026-10-20). Lanes and waypoint routes are gone (swarm movement replaced them).

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
