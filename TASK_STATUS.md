# Task status

Project: PC-first co-op base-defense shooter (genre switch 2026-10-20; brief in `docs/01_BRIEF.md`). No schedule: the owner chooses the next change one at a time.
Development started: 2026-10-12 (as a 1v1 MOBA). Genre switched: 2026-10-20.
Owner / experience / place IDs: owner = personal Roblox account; experience/place IDs NOT SET
Public URL: NOT PUBLISHED
Baseline PC: NOT RECORDED. Phones: deferred with the mobile port.
Rojo CLI / plugin / Studio versions: Rojo CLI 7.7.1 / plugin NOT RECORDED / Studio NOT RECORDED
Static check tools (rokit.toml): luau-lsp 1.70.1, selene 0.32.0 (Rokit 1.2.0)

Source state: the code in `src/` is the MOBA prototype (hero, auto-target attack, minion waves, towers, structure bars, banners). It has **not** been converted yet; each task below names the files it reuses. Full MOBA-era log with every dated evidence note: `docs/archive/moba/TASK_STATUS.md`.

Studio evidence carried over from the prototype (owner, 2026-10-13 / 2026-10-15): minion waves and wave timing, towers shooting minions, minion push, dotted tower range ring, spawn on the Blue pad. Everything else in `src/` passed static checks and `rojo build` only (Studio NOT RUN).

## Part A — Mission core loop
- [ ] T01 — Confirm release prerequisites — IN_PROGRESS (carried: personal account chosen; owner reports public publishing available, not verified in Creator Dashboard; test accounts and baseline PC NOT RECORDED)
- [ ] T02 — Toolchain and source layout — IN_PROGRESS (carried: rokit tools, `default.project.json`, static checks and `rojo build` pass; Studio sync used by owner but versions NOT RECORDED)
- [ ] T03 — Build the compound graybox map — TODO (reuse: `src/map/` lane graybox, walled 200x36 arena; needs redesign into compound + open ground)
- [ ] T04 — Camera and desktop movement — IN_PROGRESS (carried: fixed follow camera `src/client/HeroCamera.client.luau` kept as is by owner decision 2026-10-20; shift lock and jump disabled in `default.project.json`; Studio check of camera framing for incoming waves NOT RUN)
- [ ] T05 — Mission flow and party membership — TODO (reuse: `src/server/PlayerTeams.server.luau` already puts every player on one team (Blue) and spawn pad)
- [ ] T06 — Damage authority for the new entity set — IN_PROGRESS (carried: `src/server/CombatService.luau` damage gateway rejects NaN/inf/<=0/>10000, same team, dead targets; records the killer; `Damaged` and `Died` events. Still has the MOBA lock order tower -> barracks -> core to remove; new entity kinds not added)
- [ ] T07 — Player character, death and respawn — IN_PROGRESS (carried: `src/server/Heroes.server.luau` marks every character as the hero, server-owned Health 600, WalkSpeed 16, regen removed, Roblox respawn after 5 s. Class stats and death rules OPEN)
- [ ] T08 — Primary weapon firing (PC) — IN_PROGRESS (carried: Pulse attack via `HeroAction` remote in `src/server/HeroActions.server.luau`: rate limit 8/s, auto-target with server-validated hint (`src/shared/Targeting.luau`), range 24, 40 damage, 0.75 s server-time cooldown, 0.15 s windup with recheck; LMB hold, click/Tab target lock, walk-into-range in `src/client/HeroControls.client.luau`; lightning, hit flash, damage numbers in `src/client/HeroEffects.client.luau`. Aim model for guns OPEN)
- [ ] T09 — Enemy waves — IN_PROGRESS (carried, Studio PASS for waves/push: `src/server/Minions.server.luau` waves of 4 melee + 1 archer every 25 s, cap 30, waypoints, sticky targets, leash, retaliation, smooth turn, archer arrows, 70% scale; `src/client/MinionVisuals.client.luau` bars and bow. Must change from two lanes to one enemy side attacking players/structures/core)
- [ ] T10 — Base Core and win/loss — TODO (reuse: core parts and Health attributes on the map, `src/client/StructureBars.client.luau`, `src/client/Announcements.client.luau` banner)
- [ ] T11 — Gold economy — TODO (reuse: killer reported by CombatService)
- [ ] T12 — Build phase and build nodes — TODO
- [ ] T13 — Walls, turrets and traps — TODO (reuse, Studio PASS for tower shooting: `src/server/Structures.server.luau` tower AI, `src/server/TowerVisuals.server.luau` sword-tip muzzle, `src/client/TowerEffects.client.luau` shots and range ring, `assets/TowerModel.rbxmx`)
- [ ] T14 — Repair — TODO
- [ ] T15 — Results and clean reset — TODO
- [ ] T16 — Complete graybox mission milestone — TODO

## Part B — Hub and progression
- [ ] T17 — Hub area — TODO
- [ ] T18 — Classes — TODO (design OPEN)
- [ ] T19 — Weapons and gear — TODO (catalogue OPEN)
- [ ] T20 — Persistent progression — TODO
- [ ] T21 — Harder maps and difficulty — TODO
- [ ] T22 — Boss final wave — TODO (design OPEN)

## Part C — Polish, ports and release
- [ ] T23 — HUD and onboarding — TODO (reuse: `src/client/HeroHud.client.luau` badge, health bar, level/xp placeholders, four slots, overhead bars)
- [ ] T24 — Combat feedback — TODO
- [ ] T25 — Animations — DEFERRED (owner decision 2026-10-20)
- [ ] T26 — Mobile port — DEFERRED (owner decision 2026-10-20: PC launch first)
- [ ] T27 — Authority and abuse tests — TODO
- [ ] T28 — Performance and lifecycle tests — TODO
- [ ] T29 — Verify public release — TODO
- [ ] T30 — Observed playtests — TODO
- [ ] T31 — Handoff and evidence — TODO

## Decisions and deviations
- 2026-10-20: **Genre switch** (owner): from a mobile-first 1v1 MOBA to a co-op base-defense shooter: 1–5 players, walled compound with a Base Core in the bottom half, enemy waves from the top half, Gold from kills spent on walls/turrets/traps at build nodes and repair between waves, final boss wave; hub with classes (Assault, Engineer, Medic, Heavy), weapons, mission queue; persistent credits and per-class levels unlocking harder maps. MOBA docs, task log, README, CLAUDE.md and templates archived unchanged in `docs/archive/moba/`; live docs rewritten. No code changed in this step.
- 2026-10-20: Docs renumbered after the schedule was dropped: 04_CONTROLS_ANIMATIONS (was 05_MOBILE_ANIMATIONS), 05_ARCHITECTURE, 06_ACCEPTANCE_TESTS, 07_ROJO_SETUP, 08_PUBLIC_PUBLISHING, 09_SOURCES. Tasks renumbered T01–T31; acceptance tests A01–A16.
- 2026-10-20: Schedule removed (owner): no 7-day target or 14-day cap; the owner picks changes one at a time.
- 2026-10-20: PC launch first (owner); mobile touch is a later port (T26), not a launch blocker until scheduled.
- 2026-10-20: Hub and mission arena in one place (owner); separate places/teleports may come later.
- 2026-10-20: Animations deferred (owner); default Roblox animations until T25 is scheduled.
- 2026-10-20: Camera kept exactly as in the prototype (owner).
- 2026-10-20: DataStores now allowed, for persistent progression only (CLAUDE.md updated).
- Carried from the prototype, still valid: code written one file at a time (2026-10-12); jump and shift lock disabled; owner-supplied TowerModel art (source/credit still pending in `templates/ASSET_REGISTER.md`); health bars only within 60 studs of your character; destroyed structures disappear with a banner; the server never moves the player's character.
- TEMPORARY simulation aids still in code, remove before release: `Config.Minion.TestTeamBonus`, `Config.Structure.TestStartHealth` (both empty), and `PlayerTeams.server.luau` putting everyone on Blue (becomes the single defender team in T05).
- MOBA-only decisions (Blue vs Red teams, lane objective order, inhibitor bonus, tower ramp, backdoor protection, MLBB-adapted lane rules, Zeus kit, gold/shop KIV note) are archived in `docs/archive/moba/TASK_STATUS.md` and `docs/archive/moba/02_GDD.md`. Their code stays in `src/` until each task replaces it.

## Per-task evidence template
Task / status / date:
Behavior implemented:
Changed files:
Checks run + evidence:
Manual checks still needed:
Blocker or decision:
Suggested next task:
