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
  - **T03a — Natural map edges:** replace the temporary invisible boundary with irregular terrain edges, cliffs, mountains or dense forest, kept well away from the combat area.
  - **T03b — Battlefield variety:** occasional rocks, ruins or terrain features that the swarm flows around, never forming corridors or permanent lanes.

### T04 — Camera and desktop movement
- Depends on: T03. Reuses: `HeroCamera.client.luau` (kept as is), old T04.
- Do: Keep the fixed follow camera; WASD movement; no jump/climb/swim.
- Done when: camera shows enough of the top half to see incoming waves. Verify: A02.

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
- Do: Server-owned health per class (placeholder stats until T18); death rules from the GDD (OPEN items decided first).
- Done when: dead players cannot act; respawn restores controls once. Verify: A05.

### T08 — Primary weapon firing (PC)
- Depends on: T04 T06. Reuses: `HeroActions.server.luau`, `HeroControls.client.luau`, `Targeting.luau`, `HeroEffects.client.luau` (old Pulse, T07).
- Do: Fire the equipped weapon with the mouse (aim model confirmed by owner); server validates origin, direction/target, range, line of sight, rate and cooldown; cosmetic tracer.
- Done when: shots hit enemies only through the server path; spam and bad payloads are dropped. Verify: A04 A07.

### T09 — Enemy waves
- Depends on: T06. Reuses: `Minions.server.luau`, `MinionVisuals.client.luau` (old T11).
- Do: Enemies spawn at the top, walk to the compound, target players / built structures / core; wave list per map in Config; alive cap; cleanup on mission end.
- Done when: waves arrive on cue, attack all three target kinds, never exceed the cap, and stop after Results. Verify: A06 A10.

### T10 — Base Core and win/loss
- Depends on: T09. Reuses: core part, `StructureBars.client.luau`, `Announcements.client.luau`, old T09.
- Do: Core health; loss on destruction; win when the final wave is cleared; result committed once per epoch.
- Done when: both outcomes reachable; late damage cannot change a committed result. Verify: A06.

### T11 — Gold economy
- Depends on: T06 T09. Reuses: `CombatService` killer report.
- Do: Gold per kill (per-player or team pool per owner decision); server-owned balance; HUD counter; reset each mission.
- Done when: Gold only changes on server-confirmed kills and purchases. Verify: A07 A08.

### T12 — Build phase and build nodes
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
- Do: Hub zone in the same place; class picker, loadout screen, mission queue pad, map choice limited by level.
- Done when: players pick a class and loadout and start a mission from the hub. Verify: A03.

### T18 — Classes
- Depends on: T07 T08 T17.
- Do: Assault, Engineer, Medic, Heavy stats and abilities (owner design first).
- Done when: each class plays differently in a mission. Verify: A04.

### T19 — Weapons and gear
- Depends on: T08 T17.
- Do: Weapon/gear catalogue in Config; equip in hub; server enforces ownership.
- Done when: equipped items work in missions; unowned items cannot be used. Verify: A07.

### T20 — Persistent progression
- Depends on: T15 T17.
- Do: DataStore profile (credits, class levels/XP, owned items, loadouts); load on join, save on change/leave/shutdown; retries; session lock; credits and XP awarded at Results; shop purchases.
- Done when: progress survives rejoin; failures neither lose nor duplicate progress. Verify: A09.

### T21 — Harder maps and difficulty
- Depends on: T03 T20.
- Do: More maps or difficulty tiers unlocked by class level, with better rewards.
- Done when: locked maps cannot be started; unlocked ones pay more. Verify: A06 A09.

### T22 — Boss final wave
- Depends on: T09 T10.
- Do: Boss enemy for the final wave (owner design first).
- Done when: beating the boss wins; boss cannot break server rules. Verify: A06.

## Part C — Polish, ports and release

### T23 — HUD and onboarding
- Depends on: T11 T15. Reuses: `HeroHud.client.luau`, `Announcements.client.luau`, old T19.
- Do: Gold, wave/phase timer, core bar, ammo, class/level badge; first-mission hints.
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

### T32 — Re-theme to soldiers vs zombies
- Depends on: owner picks each item (theme decided 2026-10-20; brief "Theme").
- Do, one item at a time, art and names only (systems stay):
  - Blue melee minion -> soldier (e.g. bayonet rifle or riot shield) instead of sword.
  - Blue archer minion -> rifleman: rifle instead of bow, tracer instead of arrow (same shot code: aim, travel, damage on arrival).
  - Tower knight model (`assets/TowerModel.rbxmx`) -> turret or bunker art.
  - Inhibitors -> barracks or supply depots (display names, look).
  - Base Core and zombie cores -> military command post and zombie nests/hives (look, names).
  - Base walls/floor -> sandbags, concrete, fences; banner and UI wording.
  - Player hero "Zeus" lightning attack -> a gun (lines up with T08).
- Animations follow the standard patterns in `04_CONTROLS_ANIMATIONS.md`.
- Done when: no medieval placeholder remains in play. Verify: A13.

## Old MOBA tasks with no direct successor
Old T09 lane lock order, T14 Arc Bolt and T15 Slip (could return as class abilities in T18), T16 phone duel (folded into T26). See `docs/archive/moba/03_TASKS.md`.
