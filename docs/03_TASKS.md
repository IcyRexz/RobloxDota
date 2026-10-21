# Implementation tasks

Task list for the co-op base-defense shooter (genre switch 2026-10-20). There is no schedule: the owner picks the next change one at a time. Dependencies show what must exist first. A task is DONE only with evidence; partial work is IN_PROGRESS. A01–A16 refer to `06_ACCEPTANCE_TESTS.md`. Status lives in `TASK_STATUS.md`.

**Reuses** names the existing prototype code (or old MOBA task, archived in `docs/archive/moba/03_TASKS.md`) the task starts from.

## Part A — Mission core loop

### T01 — Confirm release prerequisites
- Depends on: none. Reuses: old T01.
- Do: Owning account/group, live publishing eligibility, test accounts, baseline PC (and later phones).
- Done when: eligibility result and tester plan recorded; blockers named. Verify: A14.

### T02 — Toolchain and source layout
- Depends on: T01. Reuses: old T02 (Rojo project, rokit, static checks).
- Do: Keep `default.project.json` mapping; confirm Studio sync; record versions.
- Done when: Rojo syncs into Studio with no script errors. Verify: A01.

### T03 — Build the compound graybox map
- Depends on: T02. Reuses: `src/map/` (BlueBase, Lane, RedBase, Decor), old T03.
- Do: Walled compound with Base Core in the bottom half, gates, player spawn, pre-placed build nodes; open ground in the top half; enemy spawn markers along the top; enemy path waypoints. Keep the map closed so players cannot escape.
- Done when: players spawn in the compound, can reach every node, cannot leave the map; enemies have a valid path to the core. Verify: A02.
- Follow-ups kept for later (owner 2026-10-20, not to implement yet):
  - **T03a — Natural map edges:** (placeholder forest belt done 2026-10-20) replace the temporary invisible boundary with irregular terrain edges, cliffs, mountains or dense forest, kept well away from the combat area.
  - **T03b — Battlefield variety:** (placeholder hills, trees and rocks done 2026-10-20) occasional rocks, ruins or terrain features that the swarm flows around, never forming corridors or permanent lanes.

### T04 — Camera and desktop movement
- Depends on: T03. Reuses: old T04.
- Do: first-person camera (`CameraMode = LockFirstPerson`, owner decision 2026-10-20; `HeroCamera.client.luau` removed) with crosshair (`Crosshair.client.luau`); WASD movement; jump allowed (owner 2026-10-20); no climb/swim; minimap (`Minimap.client.luau`).
- Done when: players can see incoming waves with the camera and on the minimap. Verify: A02.

### T05 — Mission flow and party membership
- Depends on: T03. Reuses: `PlayerTeams.server.luau` (single defender team), old T05.
- Do: MissionService with epoch; Hub -> Briefing -> BuildPhase/Wave loop -> Results -> Resetting; 1–5 players; join/leave rules from the GDD.
- Done when: a solo player and a 2-player party can start a mission; leaving during Briefing cancels; leaving mid-mission keeps the others playing. Verify: A03.

### T06 — Damage authority for the new entity set
- Depends on: T05. Reuses: `CombatService.luau` (validation, killer tracking, `Damaged`/`Died` events), old T06.
- Do: One defender team; entity kinds Player, Enemy, Wall, Turret, Trap, Core; remove the lane lock order; no friendly fire.
- Done when: client cannot set health/damage; friendly damage rejected; killer reported for Gold. Verify: A07.

### T07 — Player character, death and respawn
- Depends on: T06. Reuses: `Heroes.server.luau`, old T08.
- Do: Server-owned health per hero (placeholder stats until T18); death rules from the GDD (OPEN items decided first).
- Done when: dead players cannot act; respawn restores controls once. Verify: A05.

### T08 — Primary weapon firing (PC)
- Depends on: T04 T06. Reuses: `HeroActions.server.luau`, `HeroControls.client.luau`, `Targeting.luau`, `HeroEffects.client.luau` (old Pulse, T07).
- Do: Fire the equipped weapon with the mouse (aim model confirmed by owner); server validates origin, direction/target, range, line of sight, rate and cooldown; cosmetic tracer.
- Done when: shots hit enemies only through the server path; spam and bad payloads are dropped. Verify: A04 A07.

### T09 — Continuous enemy spawning (tug of war; was Enemy waves)
- Depends on: T06. Reuses: `Minions.server.luau`, `MinionVisuals.client.luau` (old T11).
- Do (owner 2026-10-21): both sides spawn small groups continuously, no waves; zombies march on the base, soldiers on the Zombie Core; caps per team with no backlog; then frontline pressure (3 levels, hysteresis), time escalation of zombie stats, Zombie Surge event; cleanup on mission end.
- Done when: the front moves with the stronger army, an unpushed front drifts toward our base, caps are never exceeded, and spawning stops after Results. Verify: A06 A10.

### T10 — Base Core and win/loss
- Depends on: T09. Reuses: core part, `StructureBars.client.luau`, `Announcements.client.luau`, old T09.
- Do: Core health; loss when the Base Core is destroyed; win when the Zombie Core is destroyed (owner 2026-10-21); stop spawning and damage; result committed once per epoch.
- Done when: both outcomes reachable; late damage cannot change a committed result. Verify: A06.

### T11 — Gold economy
- Depends on: T06 T09. Reuses: `CombatService` killer report.
- Do: Gold per kill (per-player or team pool per owner decision); server-owned balance; HUD counter; reset each mission. Done so far: per-player Gold from last hits, TEMPORARY starting Gold, and base upgrades at the Upgrade Workbench (Buildings, Melee Units, Archers; owner 2026-10-21).
- Done when: Gold only changes on server-confirmed kills and purchases. Verify: A07 A08.

### T12 — Build phase and build nodes
- ON HOLD (2026-10-21 tug-of-war redesign: no breaks between waves; owner to decide). T13 and T14 depend on it.
- Depends on: T05 T11.
- Do: Build-phase timer; build menu at nodes; server checks phase, node free, Gold, range to node; places a wall/turret/trap.
- Done when: building works only in the build phase, only at nodes, only with enough Gold. Verify: A08.

### T13 — Walls, turrets and traps
- Depends on: T12. Reuses: `Structures.server.luau` tower AI, `TowerVisuals.server.luau`, `TowerEffects.client.luau`, `assets/TowerModel.rbxmx`.
- Do: Wall (blocks, has health), turret (targets enemies), trap (per owner design); destroyed pieces free their node.
- Done when: each piece works against a live wave. Verify: A06.

### T14 — Repair
- Depends on: T13.
- Do: Repair damaged pieces (rules per owner decision); server-checked cost and phase.
- Done when: repair restores health, costs correctly and cannot overheal. Verify: A08.

### T15 — Results and clean reset
- Depends on: T10. Reuses: old T10 (epoch invalidation, reset).
- Do: Results screen with outcome and rewards; destroy mission entities; reset Gold, structures, core; return players to the hub.
- Done when: three back-to-back missions reset fully with no leftover enemies, pieces or connections. Verify: A03 A10 A11.

### T16 — Complete graybox mission milestone
- Depends on: T08 T13 T14 T15. Reuses: old T12.
- Do: Play hub -> full mission -> results -> hub with two clients.
- Done when: a whole mission works without admin commands. Verify: A03 A06.

## Part B — Hub and progression

### T17 — Hub area
- Depends on: T05.
- Do: Hub zone in the same place; hero picker, loadout screen, mission queue pad, map choice limited by level.
- Done when: players pick a hero and loadout and start a mission from the hub. Verify: A03.

### T18 — Heroes
- Depends on: T07 T08 T17.
- Do: three classes (owner decision 2026-10-21): Mage (built first: basic attack, passive, Q/E abilities, 9 masteries, automatic growth), then Archer and Warrior on the same structure, plus a way to choose a class.
- Done when: each hero plays differently in a mission. Verify: A04.

### T19 — Weapons and gear
- Depends on: T08 T17.
- Do: Weapon/gear catalogue in Config; equip in hub; server enforces ownership.
- Done when: equipped items work in missions; unowned items cannot be used. Verify: A07.

### T20 — Persistent progression
- Depends on: T15 T17.
- Do: DataStore profile (credits, hero levels/XP, owned items, loadouts); load on join, save on change/leave/shutdown; retries; session lock; credits and XP awarded at Results; shop purchases.
- Done when: progress survives rejoin; failures neither lose nor duplicate progress. Verify: A09.

### T21 — Harder maps and difficulty
- Depends on: T03 T20.
- Do: More maps or difficulty tiers unlocked by hero level, with better rewards.
- Done when: locked maps cannot be started; unlocked ones pay more. Verify: A06 A09.

### T22 — Boss final wave
- Depends on: T09 T10.
- Do: Boss enemy for the final wave (owner design first).
- Done when: beating the boss wins; boss cannot break server rules. Verify: A06.

## Part C — Polish, ports and release

### T23 — HUD and onboarding
- Depends on: T11 T15. Reuses: `HeroHud.client.luau`, `Announcements.client.luau`, old T19.
- Do: Gold, wave/phase timer, core bar, hero badge; first-mission hints. (XP bar, level badge wiring and minimap done 2026-10-20.)
- Done when: a new player understands the goal and how to build without coaching. Verify: A13.

### T24 — Combat feedback
- Depends on: T13 T23. Reuses: `HeroEffects`, `TowerEffects`, old T20.
- Do: Pooled VFX, licensed audio, hit/damage feedback on enemies, walls and core.
- Done when: important events are readable during a full wave. Verify: A12.

### T25 — Animations (deferred)
- Depends on: owner decision. Reuses: old T17/T18 rules (archived).
- Do: Owner decides scope later. Until then, Roblox default animations are used and no animation gate blocks release.

### T26 — Mobile port (deferred)
- Depends on: owner scheduling. Reuses: old T13–T16 touch rules (archived `05_MOBILE_ANIMATIONS.md`).
- Do: Touch controls, safe insets, mobile HUD layout, real-phone tests.
- Done when: a full mission plays on a phone with touch only. Verify: A15.

### T27 — Authority and abuse tests
- Depends on: T14 T20. Reuses: old T21.
- Do: Bad payloads, spam, stale epoch, building/repair/purchase abuse, teleport-then-shoot.
- Done when: no unauthorized damage, Gold, credits or builds; no server exception. Verify: A07 A08 A09.

### T28 — Performance and lifecycle tests
- Depends on: T24. Reuses: old T22.
- Do: Full 5-player mission at the enemy cap; repeated missions; disconnect/rejoin; memory trend.
- Done when: A10–A12 met with evidence. Verify: A10 A11 A12.

### T29 — Verify public release
- Depends on: T27 T28. Reuses: old T24.
- Do: Follow `08_PUBLIC_PUBLISHING.md`; non-editor accounts join, play and keep progress.
- Done when: verified public URL recorded. Verify: A14.

### T30 — Observed playtests
- Depends on: T29. Reuses: old T25.
- Do: Watch first-time players; record understanding and replay honestly.
- Done when: results recorded; small samples flagged. Verify: A13.

### T31 — Handoff and evidence
- Depends on: T30. Reuses: old T26.
- Do: README, credits, known issues, tested version and devices.
- Done when: deliverables match shipped behavior. Verify: A16.

### T32 — Fantasy polish: warriors vs zombies
- Depends on: owner picks each item (theme changed to fantasy warriors 2026-10-21; brief "Theme").
- Do, one item at a time, art and names only (systems stay):
  - Our minions: keep sword and bow; a proper warrior look and our side's colours (currently khaki from the soldier theme; colour OPEN).
  - Tower knight model (`assets/TowerModel.rbxmx`): keep or swap for a ballista or arcane tower.
  - Inhibitors -> barracks or war camps (display names, look).
  - Base Core and zombie cores -> a keep or shrine, and zombie nests or plague pits (look, names).
  - Base floor -> stone or packed earth; fences -> palisades if wanted; banner and UI wording follow `docs/11_UI_DESIGN.md`.
- Animations follow the standard patterns in `04_CONTROLS_ANIMATIONS.md`.
- Done when: no medieval placeholder remains in play. Verify: A13.

## Old MOBA tasks with no direct successor
Old T09 lane lock order, T14 Arc Bolt and T15 Slip (could return as hero abilities in T18), T16 phone duel (folded into T26). See `docs/archive/moba/03_TASKS.md`.
