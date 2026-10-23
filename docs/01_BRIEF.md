# Project brief

Working title: **not chosen yet** (the folder is still called RobloxDota; the MOBA title "Riftbreak Duel" is retired).

Genre switch (owner decision 2026-10-20): the project is now a **cooperative base-defense action game** for Roblox (first-person, aimed attacks; fantasy theme since 2026-10-21). The earlier 1v1 MOBA prototype is archived in `docs/archive/moba/`; much of its code is being reused (see `docs/03_TASKS.md`).

## The game in one paragraph
One to five players fight a cooperative **tug of war** (owner decision 2026-10-21, replacing waves with build phases): our base with its **Base Core**, barracks and towers at one end of an open battlefield, the **Zombie Core** at the other. Both sides spawn units continuously, with no breaks: our barracks send soldiers toward the Zombie Core, the Zombie Core sends zombies toward our base, and the front moves with whichever army is stronger. Left alone, the zombies slowly gain ground; players fight on foot with their hero's attacks and abilities alongside their soldiers to push it back. Both sides grow stronger over the match, the players faster (hero levels, base upgrades bought with **Gold** from kills), so a team that keeps pushing with its army eventually wins. The team wins by destroying the Zombie Core and loses if the Base Core falls. PvE only: no PvP.

Outside matches, players meet in a shared **hub** where they pick a **class** (Mage, Archer or Warrior; owner decision 2026-10-21: each has a basic attack, a passive, two abilities and masteries), equip gear and queue for missions. Each mission feeds **persistent progression**: **credits** buy heroes' gear (and possibly new heroes), and **each hero levels up independently**, which opens harder maps with better rewards. In a match, heroes level up (stats grow automatically) and pick a mastery every 5 levels (see the GDD).

## Theme: warriors vs zombies, fantasy (owner decision 2026-10-21)
The players and their side are fantasy warriors and heroes (swords, bows, magic such as Zeus's lightning, towers, palisades and traps); the enemy is a zombie horde. This replaces the soldiers vs zombies theme chosen on 2026-10-20. The existing placeholder art (sword and bow minions, knight tower model) already fits; T32 now polishes the fantasy look one item at a time. UI follows the minimal design system in `docs/11_UI_DESIGN.md` (owner decision 2026-10-21; plain names: Health, Damage, Move Speed, Attack Speed, Range; upgrades are called talents).

## Two currencies
- **Gold:** in-match only, from kills; spent on base upgrades at the Upgrade Workbench; gone when the match ends.
- **Credits:** persistent, earned per mission; spent in the hub on gear (and possibly heroes; OPEN).

## Platform and launch order (owner decisions 2026-10-20)
- **PC (computer) launch first.** Desktop mouse and keyboard is the primary input. Mobile/touch is a later port and is not a launch blocker until the owner schedules it. Owner 2026-10-23: new lobby UI is built **touch-ready** (large buttons, scale from screen size, no hover-only information) so the port is easy; battle touch controls stay in T26.
- **Hub and mission arena live in one place for now** (one server holds the hub and the mission). Owner 2026-10-23: **staged move to two places** — lobby UI separation, navigation, party and queue are built in the one place first, then the game splits into a lobby place and a battle place (one reserved server per match) with teleports (`docs/15_LOBBY_MATCHMAKING_PLAN.md`).
- **No schedule.** The 7-day target and 14-day cap are dropped. The owner chooses the next change one at a time.
- **Animations later.** A custom animation set is deferred; the owner will decide what is needed afterwards.
- **Camera:** in battle, first person with a centre crosshair (owner decision 2026-10-20, replacing the fixed elevated follow camera); in the lobby, Roblox's default third-person camera with a free mouse (owner 2026-10-23); a fixed-orientation minimap shows the base at the bottom and enemies arriving from the top.

## Required for the complete launch
- One public Roblox experience and working start link.
- Hub: hero pick, loadout, mission queue.
- Three classes (Mage, Archer, Warrior), each with its own attack, passive, abilities, masteries and independent level.
- Gear bought with credits.
- At least one mission map with walls, build nodes and a Base Core; harder maps unlocked by hero level.
- Continuous tug-of-war combat: both sides spawn all match; zombies escalate over time and push back harder near their core (pressure); occasional surge events. (Build nodes, walls/traps and repair: ON HOLD since the 2026-10-21 redesign, owner to decide; boss design OPEN.)
- Win (Zombie Core destroyed) and loss (Base Core destroyed; whether a full party wipe also loses is OPEN).
- Saved progression (credits, hero levels, unlocks) that survives leaving and rejoining.
- Server-owned damage, Gold, credits, building, cooldowns, targets, spawning and results; validated client movement.
- Source/config, README, asset credits, test evidence and known issues.

## Not in scope unless the owner adds it
PvP, paid products/monetization, trading, external HTTP/telemetry, cross-server matchmaking services, free-text chat features beyond Roblox defaults, a level editor.
Possible later Robux points are parked in `docs/14_MONETIZATION_IDEAS.md` (owner 2026-10-23); they stay out of scope until the owner adds them.

## Definition of done
Players on non-editor accounts join the public experience, pick a hero in the hub, play a full mission with 1–5 players to a win or loss, get their rewards, leave and rejoin with progression intact, and every P0 check in `docs/06_ACCEPTANCE_TESTS.md` passes. The README holds the verified URL, controls, goal, decisions, credits, limitations and tested devices.

## Owner decisions still OPEN
Recorded here until decided; Claude does not invent them.
- Game title (should suit fantasy warriors vs zombies).
- Per-hero attack style (aimed at the crosshair is decided; hitscan vs projectile per hero).
- Archer and Warrior kits and masteries (proposed in the owner's 2026-10-21 spec; the Mage is decided and built), and how a class is chosen.
- Our side's colours (currently khaki from the soldier theme).
- Gold: per-player or shared team pool.
- Player death: respawn timer, revive (e.g. by a healer hero), and whether a full party wipe loses the mission.
- Enemy types beyond the zombie, Brute and Spitter (owner 2026-10-21), boss design.
- Catalogue of walls, towers, traps and gear, with prices.
- Credit and hero-XP rewards per mission; level caps; which levels unlock which maps.
- Mobile controls layout (when the mobile port is scheduled).
- Animation requirement (when scheduled).
