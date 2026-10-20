# Acceptance and testing criteria

All checks start **NOT RUN**. Record results in `templates/TEST_LOG.md` with build version, date, device, steps, expected/actual, evidence and tester. Intended results are never evidence. P0 failures block release; P1 results guide iteration.

## A01 — Clean start (P0)
Build/sync into a fresh place; start a server with two clients. No script errors; expected service tree; one copy of each controller.

## A02 — Map and movement (P0)
Players spawn inside the compound, reach every build node and cannot leave the map, jump onto walls or the core, or spawn inside geometry. Enemies always have a path to the core. The camera shows incoming waves without manual adjustment.

## A03 — Hub and mission flow (P0)
Solo and party (2 and 5 players) can start from the hub. Leaving during Briefing cancels it. Leaving mid-mission keeps the others playing; last player leaving resets. Results return everyone to the hub. Three missions in a row start clean (no leftover Gold, pieces, enemies or cooldowns).

## A04 — Weapons and classes (P0)
Each class's weapon and abilities work while moving. Holding fire never exceeds the weapon's rate; no doubled or stuck shots; focus loss and death stop held fire.

## A05 — Death and respawn (P0)
Dead players cannot fire, build or repair. Respawn/revive follows the GDD; repeated deaths restore controls exactly once.

## A06 — Waves, structures and results (P0)
Waves spawn as configured and attack players, built pieces and the core. Walls block, turrets fire, traps trigger, destroyed pieces free their node. Core destruction loses; clearing the final wave (boss when present) wins. Damage arriving after the result cannot change it.

## A07 — Remote and combat authority (P0)
With a Studio-only test client, send wrong types, extra keys, NaN/infinite/huge numbers, unknown actions, stale epoch, and 100 requests/s for 10 s. Fire while dead, outside a mission, on cooldown, at targets out of range/behind walls. Expected: no exception, no unauthorized damage, no unbounded replies or logs.

## A08 — Economy and building authority (P0)
Building outside the build phase, at a taken or unknown node, from far away, without enough Gold, or with a forged piece ID is rejected. Gold changes only on confirmed kills and purchases. Repair cannot overheal or go below cost.

## A09 — Persistence (P0)
Credits, class levels/XP, owned items and loadouts survive leave/rejoin and server shutdown. Simulated DataStore failure does not wipe or duplicate progress. Joining a second server while the first is still saving does not roll back. Locked maps and unowned items cannot be used.

## A10 — Capacity and cleanup (P0)
At the enemy cap with five players and full builds: no backlog, no unbounded tasks. After three missions, enemy/projectile counts return to zero and connection counts to baseline.

## A11 — Interruptions (P0)
Disconnect and rejoin mid-mission; die during a shot; mission reset with shots in flight. Old-epoch effects never hit new entities; UI matches the server phase.

## A12 — PC performance (P0)
On the baseline PC, a full 5-player mission at the enemy cap holds a playable frame rate (target and tool recorded with the result). Record join time and visible stalls.

## A13 — Usability (P1)
First-time players, uncoached for 30 seconds, can say how to win and how to build. Record counts honestly with sample size.

## A14 — Public access (P0)
Real experience ID and public URL recorded. Non-editor accounts join through the public link, play a mission and keep progression. Studio/private links do not count.

## A15 — Mobile (deferred; P0 once the owner schedules the mobile port)
A full mission plays on real phones with touch only; safe insets respected; frame rate recorded on the baseline phone.

## A16 — Handoff (P0)
README with working URL, source version, truthful feature list, asset credits/permissions, P0 evidence and known issues. No secrets in the repository.
