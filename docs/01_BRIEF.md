# Project brief

Working title: **not chosen yet** (the folder is still called RobloxDota; the MOBA title "Riftbreak Duel" is retired).

Genre switch (owner decision 2026-10-20): the project is now a **cooperative base-defense shooter** for Roblox. The earlier 1v1 MOBA prototype is archived in `docs/archive/moba/`; much of its code is being reused (see `docs/03_TASKS.md`).

## The game in one paragraph
One to five players defend a walled compound with a **Base Core** in the bottom half of the map against waves of enemies coming from the upper half across open ground. The feel is closer to a Helldivers 2 defence mission than to tower defence: players fight on foot with their own weapons. Enemies attack players, walls and the core. Players earn **Gold** during the match by killing enemies, and between waves spend it on walls, turrets and traps at pre-placed **build nodes**, then repair before the next wave hits. The team wins by surviving the final wave (in the full version, a boss) with the core still standing.

Outside matches, players meet in a shared **hub** where they pick a class (**Assault, Engineer, Medic or Heavy**), equip weapons and queue for missions. Each mission feeds **persistent progression**: **credits** buy new weapons and gear, and **each class levels up independently**, which opens harder maps with better rewards.

## Theme: soldiers vs zombies (owner decision 2026-10-20)
The players and their side are a modern military force (soldiers, guns, turrets, sandbags, mines); the enemy is a zombie horde. Chosen over "warriors vs zombies" because it fits the shooter genre, the Helldivers-style defence feel, the four classes, guns-and-gear progression, and reads clearly from the top-down camera. Current placeholder art is still medieval (sword/bow minions, knight tower model); it gets re-themed later, one item at a time (T32 in `docs/03_TASKS.md`), not all at once.

## Two currencies
- **Gold:** in-match only, from kills; spent on building and repairing; gone when the match ends.
- **Credits:** persistent, earned per mission; spent in the hub on weapons and gear.

## Platform and launch order (owner decisions 2026-10-20)
- **PC (computer) launch first.** Desktop mouse and keyboard is the primary input. Mobile/touch is a later port and is not a launch blocker until the owner schedules it.
- **Hub and mission arena live in one place** (one server holds the hub and the mission). Separate places with teleports may come later.
- **No schedule.** The 7-day target and 14-day cap are dropped. The owner chooses the next change one at a time.
- **Animations later.** A custom animation set is deferred; the owner will decide what is needed afterwards.
- **Camera:** keep the current fixed elevated follow camera (base at the bottom of the screen, enemies arriving from the top).

## Required for the complete launch
- One public Roblox experience and working start link.
- Hub: class pick, loadout, mission queue.
- Four classes with independent levels.
- Weapons and gear bought with credits.
- At least one mission map with walls, build nodes and a Base Core; harder maps unlocked by class level.
- Enemy waves; build phase between waves with walls, turrets, traps and repair; final boss wave.
- Win (final wave survived, core standing) and loss (core destroyed; whether a full party wipe also loses is OPEN).
- Saved progression (credits, class levels, unlocks) that survives leaving and rejoining.
- Server-owned damage, Gold, credits, building, cooldowns, targets, wave state and results; validated client movement.
- Source/config, README, asset credits, test evidence and known issues.

## Not in scope unless the owner adds it
PvP, paid products/monetization, trading, external HTTP/telemetry, cross-server matchmaking services, free-text chat features beyond Roblox defaults, a level editor.

## Definition of done
Players on non-editor accounts join the public experience, pick a class in the hub, play a full mission with 1–5 players to a win or loss, get their rewards, leave and rejoin with progression intact, and every P0 check in `docs/06_ACCEPTANCE_TESTS.md` passes. The README holds the verified URL, controls, goal, decisions, credits, limitations and tested devices.

## Owner decisions still OPEN
Recorded here until decided; Claude does not invent them.
- Game title (should suit soldiers vs zombies).
- Weapon aiming on PC (mouse-aimed shots is the working assumption; hitscan vs projectile per weapon).
- Class abilities for Assault, Engineer, Medic and Heavy.
- Gold: per-player or shared team pool.
- Player death: respawn timer, revive (e.g. Medic), and whether a full party wipe loses the mission.
- Enemy types, wave count per map, boss design.
- Catalogue of walls, turrets, traps, weapons and gear, with prices.
- Credit and class-XP rewards per mission; level caps; which levels unlock which maps.
- Mobile controls layout (when the mobile port is scheduled).
- Animation requirement (when scheduled).
