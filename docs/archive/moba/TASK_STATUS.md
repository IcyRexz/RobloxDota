# Task status

Development start date: 2026-10-12 (Day 1)
Day-7 target date: 2026-10-18
Day-14 cap date: 2026-10-25
Owner / experience / place IDs: owner = personal Roblox account; experience/place IDs NOT SET
Public URL: NOT PUBLISHED
Baseline phones: NOT RECORDED
Rojo CLI / plugin / Studio versions: Rojo CLI 7.7.1 / plugin NOT RECORDED / Studio NOT RECORDED
Static check tools (rokit.toml): luau-lsp 1.70.1, selene 0.32.0 (Rokit 1.2.0)

Source state: Rojo template only. Starter-pack code deliberately NOT imported; source files are built one at a time (see CLAUDE.md). Reference docs imported 2026-10-12. No gameplay tasks complete; no runtime tests run.

- [ ] T01 — Confirm release prerequisites — IN_PROGRESS (owner: personal account; owner reports public publishing is available, not yet verified in Creator Dashboard; second account/phone and baseline device NOT RECORDED)
- [ ] T02 — Open the source scaffold — IN_PROGRESS (tooling, docs and project file done; `rojo build` passes; Studio sync NOT RUN; bootstrap scripts not yet written)
- [ ] T03 — Build the graybox arena — IN_PROGRESS (map in `src/map/`, `rojo build` passes, Blue/Red mirror verified by script; Studio walk-through NOT RUN)
- [ ] T04 — Implement mobile camera and movement — IN_PROGRESS (2026-10-15: fixed MOBA follow camera `src/client/HeroCamera.client.luau`; shift lock and jumping disabled in `default.project.json`; static checks + `rojo build` pass; Studio run NOT RUN. Thumbstick/phone check, climbing/swimming states not yet)
- [ ] T05 — Implement match membership and ready flow — TODO
- [ ] T06 — Implement entities and damage authority — IN_PROGRESS (2026-10-14: `CombatService.applyDamage(target, amount, attacker, attackerTeam)` now records the attacker; `Died` fires (target, killer, killerTeam) so last-hit rewards can read the final hitter; dev death log `[Combat] <team> <kind> killed by <team> <kind>` in Output; minion melee and arrows pass their own model. Static checks + `rojo build` pass; Studio run NOT RUN. 2026-10-15: objective order tower -> barracks (inhibitor) -> core enforced in `CombatService.isLocked`; static checks pass; Studio command-bar check NOT RUN. 2026-10-15 hero step: `src/server/Heroes.server.luau` makes every character the hero Zeus (Kind=Hero, team from player, server-owned Health/MaxHealth 600 mirrored to the Humanoid, regen script removed, WalkSpeed 16, Roblox respawn after 5 s); `CombatService.Damaged` used by towers. Minions target enemy heroes after enemy minions; towers target enemy heroes after minions, with 60/90/120 ramp (2 s reset) and switch to an enemy hero who damages an allied hero in range (untestable until heroes can attack). Minions scaled to 70%. `src/client/HeroHud.client.luau`: bottom-left badge + health bar, overhead name + segmented bar for every hero, damage chip; Roblox health bar/name hidden. Static checks + `rojo build` pass; Studio run NOT RUN. Backdoor reduction, spawn protection, hero attacks not yet)
- [ ] T07 — Implement Pulse end to end — IN_PROGRESS (2026-10-15: `src/server/HeroActions.server.luau` handles `HeroAction` remote (one string arg, rate-limited 8/s before work, deny unknown actions): Pulse auto-targets nearest enemy hero, else minion, else unlocked structure within 24 studs with line of sight; no target = no cooldown; cooldown 0.75 s from server time in `PulseReadyAt` attribute; 0.15 s windup, then range/LOS rechecked, hit for 40 via CombatService (hero is attacker, so last hits are credited); death or respawn cancels a pending hit; server swing animation; `HeroAttack` server->client drawn as lightning by `src/client/HeroEffects.client.luau`. Input in `src/client/HeroControls.client.luau` (LMB hold / Attack slot). Minions of a hero hit by an enemy hero turn on that attacker within 20 studs. HUD centred with level/xp placeholders and four skill slots. Static checks + `rojo build` pass; Studio run NOT RUN. 2026-10-15 (2): fixed push-back bug (server no longer sets the client-owned character's CFrame); MLBB-style target marker, walk-into-range, local facing + swing, target hint validated by server via shared `src/shared/Targeting.luau`; hit flash + damage numbers; static checks pass; Studio run NOT RUN. 2026-10-15 (3): health bars shown by distance from the hero (`Config.Display.HealthBarRange` 60 > AcquireRange 40); click/tap/Tab target lock; static checks pass; Studio run NOT RUN. Touch input, protection interaction, match epoch not yet)
- [ ] T08 — Implement death and respawn — TODO
- [ ] T09 — Implement towers and core victory — IN_PROGRESS (2026-10-15: `src/server/Structures.server.luau` (was Towers.server.luau) each living tower keeps its target while it stays in range, else picks the nearest enemy minion within 28 studs, fires every 1 s for 60 damage; shot flies at 80 studs/s and damage lands on arrival via CombatService with the tower as attacker; `TowerShot` server->client RemoteEvent drawn by `src/client/TowerEffects.client.luau`. Studio PASS for towers shooting minions (owner, 2026-10-15). 2026-10-15 follow-up: orb fires from the sword tip (`Muzzle` attachment found by `TowerVisuals.server.luau` as the upper end of the Sword mesh); faint floor range ring per tower (green ally / red enemy) turning bright red when the tower's server-written `Target` ObjectValue is the viewer's character. Static checks + `rojo build` pass; Studio run NOT RUN. 2026-10-15 (2): dotted range ring; Studio PASS for minion push, dotted ring, Blue spawn (owner, 2026-10-15). 2026-10-15 (3): ruins replaced: destroyed structures are removed (with tower art) and the server fires `StructureDestroyed` (kind, team, killerTeam); `src/client/Announcements.client.luau` shows a queued Dota-style banner; structure bars drop with their structure; static checks pass; Studio run NOT RUN. 2026-10-15 (4): banner restyled Mobile Legends-style (scoring-team strip, white bold text, inhibitor line names whose minions got stronger); range ring only for enemy towers, grey when near, red when aiming at you; static checks pass; Studio run NOT RUN. Hero targeting/switch-to-attacker, core victory not yet)
- [ ] T10 — Implement results and clean rematch — TODO
- [ ] T11 — Implement one minion type and waves — IN_PROGRESS (step 1: `src/server/Minions.server.luau` spawns 4 melee + 1 archer per side every 25 s, walks the lane around structures, stops at enemy minions, despawns after 60 s; runs without a match for now; no fighting yet; Studio run NOT RUN. Config step: numbers in `src/shared/Config.luau`, first wave 5 s; Studio PASS (owner, 2026-10-13). Combat step: `src/server/CombatService.luau` damage gateway (rejects NaN/inf/<=0/>10000, same team, dead, locked barracks/core); minions hit enemy minions every 1 s, melee swing animation, dead minions removed; static checks pass; Studio run NOT RUN. Turn step (2026-10-15): Humanoid AutoRotate off, an AlignOrientation turns minions at `Config.Minion.TurnRate` 270 deg/s toward their path or enemy (no more snapping); static checks pass; Studio run NOT RUN. Structure step (2026-10-15): minions target enemy minions first, else the nearest unlocked enemy structure in aggro range (measured to its side), with structure lock; route continues through the enemy base; archers' arrows can hit structures; barracks bonus +25% applied to the destroying team's later spawns; static checks pass; Studio run NOT RUN. Retaliation step (2026-10-15): `CombatService.Damaged` event; a minion hit by an enemy minion fights back while it is within `RetaliateRange` 20, breaking a structure lock; static checks pass; Studio run NOT RUN. Visuals step: archer draw pose + arrow (damage on arrival, server-scheduled via `MinionShot` server->client RemoteEvent), nameless minion health bars in `src/client/MinionVisuals.client.luau`; static checks pass; Studio run NOT RUN)
- [ ] T12 — Reach complete graybox milestone — TODO
- [ ] T13 — Build final three-button touch layout — TODO
- [ ] T14 — Implement aimed Arc Bolt — TODO
- [ ] T15 — Implement Slip and movement validation — TODO
- [ ] T16 — Test first real-phone duel — TODO
- [ ] T17 — Create and publish complete animation set — TODO
- [ ] T18 — Integrate animation arbitration — TODO
- [ ] T19 — Finish combat HUD and onboarding — TODO
- [ ] T20 — Add readable combat feedback — TODO
- [ ] T21 — Run authority and abuse tests — TODO
- [ ] T22 — Run performance and lifecycle tests — TODO
- [ ] T23 — Fix release blockers and tune pacing — TODO
- [ ] T24 — Verify public release — TODO
- [ ] T25 — Run observed mobile playtests — TODO
- [ ] T26 — Finish handoff and evidence — TODO

## Decisions and deviations
- 2026-10-12: Starter-pack code not imported; source written one file at a time.
- 2026-10-12: Team colors fixed Blue vs Red (was Blue vs Orange).
- 2026-10-12: Added a Dota-style barracks per side (700 HP, locked until own tower falls, destroying it empowers the attacker's later minions +50%). This is a deliberate scope addition over the original "tower and core only" plan; estimated +0.5 day across T09/T11. Rules in docs/02_GDD.md.
- 2026-10-12: Minions use the default R15 character, team body colors, spawning in front of their core. Watch phone performance with 24 Humanoids in T22.
- 2026-10-13: Structure labels replaced by client-drawn MOBA health bars (green ally / red enemy). Until teams exist (T05) every player is treated as Blue. Starting Health/MaxHealth set as map attributes (tower 900, barracks 700, core 1200); the server will own these once T06/T09 land.
- 2026-10-13: Lane widened 28 -> 36 studs; trees moved out to stay clear of walls.
- 2026-10-13: Owner-supplied TowerModel used as tower art on both sides (knight body painted team color, stone left grey; each knight turned to face mid-lane; upside-down saved pivot ignored). Tower block stays the invisible hitbox, resized to 8x19x8. Source/credit pending in templates/ASSET_REGISTER.md.
- 2026-10-13: Second minion type (archer) added; waves 4 melee + 1 archer every 25 s; cap 30. Scope addition over the one-minion-type plan.
- 2026-10-13: Lane and turret rules adapted from MLBB reference data (community wiki + player reports; unverified, used as design ideas only): first wave at 5 s, sticky minion targets, minions lock onto structures, 12-stud / 3-second leash, tower ramp 60/90/120 on heroes (2-second reset), 50% backdoor protection without escort. Raw MLBB HP/ATK numbers not copied. Rules in docs/02_GDD.md. Stale 24-minion cap in 03_TASKS and 07_ACCEPTANCE_TESTS corrected to 30.
- 2026-10-15: Objective order is now tower -> inhibitor (barracks) -> core; the core needs its own barracks down, not just the tower (was: barracks optional). Inhibitor bonus for the destroying team's later minions lowered from +50% to +25% (bonus itself not yet coded). Owner decision.
- 2026-10-15: Gold/last-hit economy and base shop are KIV (kept in view): recorded in docs/01_BRIEF.md, not scheduled, not built. Touch controls stay mobile-first but are scheduled after the hero works on desktop keys. Wave timing and dates left as they are. Owner decisions.
- 2026-10-15: Minions attack the nearest enemy structure in aggro range (no explicit order; the lane gives tower -> inhibitor -> core). Minion lifetime 60 -> 180 s so a push can reach the core. Destroyed structures disappear with a team-wide announcement banner (ruins idea dropped same day). Owner decision.
- 2026-10-15: TEMPORARY simulation aids, remove before release: `Config.Minion.TestTeamBonus` (per-team minion bonus) and `Config.Structure.TestStartHealth` (per-structure start health), both empty again since 2026-10-15 (owner reset); `src/server/PlayerTeams.server.luau` puts every player on Blue and spawns them on the Blue pad (replaced by T05).
- 2026-10-15: Hero renamed Spark -> Zeus (owner); kit unchanged for now. Hero is the player's own Roblox avatar marked as a hero (no Zeus model yet). Death uses Roblox's built-in respawn for now; T08 adds protection and death rules. Minions scaled to 70% so heroes read taller. Desktop-first HUD (bottom-left) is a temporary layout: on phones that corner is the thumbstick (owner: mobile port after desktop testing).
- 2026-10-12: Both spawn pads are Neutral until teams exist (T05), so players spawn on either pad for now.

## Per-task evidence template
Task / status / date:
Behavior implemented:
Changed files:
Checks run + evidence:
Manual checks still needed:
Blocker or decision:
Next dependency-eligible task:
