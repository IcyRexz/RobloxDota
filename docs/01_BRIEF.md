# Project brief

Working title: **not chosen yet** (the folder is still called RobloxDota; the MOBA title "Riftbreak Duel" is retired).

Genre switch (owner decision 2026-10-20): the project is now a **cooperative base-defense action game** for Roblox (first-person, aimed attacks; fantasy theme since 2026-10-21). The earlier 1v1 MOBA prototype is archived in `docs/archive/moba/`; much of its code is being reused (see `docs/03_TASKS.md`).

## The game in one paragraph
One to five players defend a walled compound with a **Base Core** in the bottom half of the map against waves of enemies coming from the upper half across open ground. The feel is closer to a Helldivers 2 defence mission than to tower defence: players fight on foot with their hero's own attacks and abilities. Enemies attack players, walls and the core. Players earn **Gold** during the match by killing enemies, and between waves spend it on walls, towers and traps at pre-placed **build nodes**, then repair before the next wave hits. The team wins by surviving the final wave (in the full version, a boss) with the core still standing.

Outside matches, players meet in a shared **hub** where they pick a **hero** from a roster (Dota-style: each hero has its own attack, abilities and talents; owner decision 2026-10-21, replacing the four classes), equip gear and queue for missions. Each mission feeds **persistent progression**: **credits** buy heroes' gear (and possibly new heroes), and **each hero levels up independently**, which opens harder maps with better rewards. In a match, heroes also level up rogue-like and pick talents (see the GDD).

## Theme: warriors vs zombies, fantasy (owner decision 2026-10-21)
The players and their side are fantasy warriors and heroes (swords, bows, magic such as Zeus's lightning, towers, palisades and traps); the enemy is a zombie horde. This replaces the soldiers vs zombies theme chosen on 2026-10-20. The existing placeholder art (sword and bow minions, knight tower model) already fits; T32 now polishes the fantasy look one item at a time. UI follows the minimal design system in `docs/11_UI_DESIGN.md` (owner decision 2026-10-21; plain names: Health, Damage, Move Speed, Attack Speed, Range; upgrades are called talents).

## Two currencies
- **Gold:** in-match only, from kills; spent on building and repairing; gone when the match ends.
- **Credits:** persistent, earned per mission; spent in the hub on gear (and possibly heroes; OPEN).

## Platform and launch order (owner decisions 2026-10-20)
- **PC (computer) launch first.** Desktop mouse and keyboard is the primary input. Mobile/touch is a later port and is not a launch blocker until the owner schedules it.
- **Hub and mission arena live in one place** (one server holds the hub and the mission). Separate places with teleports may come later.
- **No schedule.** The 7-day target and 14-day cap are dropped. The owner chooses the next change one at a time.
- **Animations later.** A custom animation set is deferred; the owner will decide what is needed afterwards.
- **Camera:** first person with a centre crosshair (owner decision 2026-10-20, replacing the fixed elevated follow camera); a fixed-orientation minimap shows the base at the bottom and enemies arriving from the top.

## Required for the complete launch
- One public Roblox experience and working start link.
- Hub: hero pick, loadout, mission queue.
- A hero roster (size OPEN), each hero with its own attack, abilities, talents and independent level.
- Gear bought with credits.
- At least one mission map with walls, build nodes and a Base Core; harder maps unlocked by hero level.
- Enemy waves; build phase between waves with walls, towers, traps and repair; final boss wave.
- Win (final wave survived, core standing) and loss (core destroyed; whether a full party wipe also loses is OPEN).
- Saved progression (credits, hero levels, unlocks) that survives leaving and rejoining.
- Server-owned damage, Gold, credits, building, cooldowns, targets, wave state and results; validated client movement.
- Source/config, README, asset credits, test evidence and known issues.

## Not in scope unless the owner adds it
PvP, paid products/monetization, trading, external HTTP/telemetry, cross-server matchmaking services, free-text chat features beyond Roblox defaults, a level editor.

## Definition of done
Players on non-editor accounts join the public experience, pick a hero in the hub, play a full mission with 1–5 players to a win or loss, get their rewards, leave and rejoin with progression intact, and every P0 check in `docs/06_ACCEPTANCE_TESTS.md` passes. The README holds the verified URL, controls, goal, decisions, credits, limitations and tested devices.

## Owner decisions still OPEN
Recorded here until decided; Claude does not invent them.
- Game title (should suit fantasy warriors vs zombies).
- Per-hero attack style (aimed at the crosshair is decided; hitscan vs projectile per hero).
- Hero roster: how many heroes, their names, roles, abilities and talent pools (Zeus is the first; a 25-talent draft is in `docs/10_ZEUS_UPGRADES_PLAN.md`).
- Our side's colours (currently khaki from the soldier theme).
- Gold: per-player or shared team pool.
- Player death: respawn timer, revive (e.g. by a healer hero), and whether a full party wipe loses the mission.
- Enemy types, wave count per map, boss design.
- Catalogue of walls, towers, traps and gear, with prices.
- Credit and hero-XP rewards per mission; level caps; which levels unlock which maps.
- Mobile controls layout (when the mobile port is scheduled).
- Animation requirement (when scheduled).
