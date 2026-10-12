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
- [ ] T04 — Implement mobile camera and movement — TODO
- [ ] T05 — Implement match membership and ready flow — TODO
- [ ] T06 — Implement entities and damage authority — TODO
- [ ] T07 — Implement Pulse end to end — TODO
- [ ] T08 — Implement death and respawn — TODO
- [ ] T09 — Implement towers and core victory — TODO
- [ ] T10 — Implement results and clean rematch — TODO
- [ ] T11 — Implement one minion type and waves — IN_PROGRESS (step 1: `src/server/Minions.server.luau` spawns 4 melee + 1 archer per side every 25 s, walks the lane around structures, stops at enemy minions, despawns after 60 s; runs without a match for now; no fighting yet; Studio run NOT RUN)
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
- 2026-10-12: Both spawn pads are Neutral until teams exist (T05), so players spawn on either pad for now.

## Per-task evidence template
Task / status / date:
Behavior implemented:
Changed files:
Checks run + evidence:
Manual checks still needed:
Blocker or decision:
Next dependency-eligible task:
