# Server-authoritative architecture and contracts

This document is the implementation target. The bundled source only initializes remotes, publishes a scaffold phase, and validates/denies action requests. None of the planned services below is silently considered implemented.

## Ownership of decisions
Server modules: MatchService (membership, epoch, state, clock, results), EntityService (IDs/team/health), CombatService (damage gateway), AbilityService (cooldowns/action locks), ProjectileService (sweeps), MinionService (waves/AI), StructureService (targeting/core lock), MovementService (legal positions/dash authorization), ReplicationService (bounded snapshots/effects). Keep these ordinary small modules; no dependency framework is required.

Client controllers: Input, Camera, HUD, Animation, Effects. Clients may predict indicators/cooldown feedback but cannot decide damage, winners, respawns or targets. Shared config defines public tuning and protocol names; it is readable by clients and contains no secrets. A local edit of shared config affects only that client; server code reads its own copy.

Roblox distributes physics, so a character observed by the server is not automatically a trustworthy position. This prototype's combat and match rules are server-authoritative, while normal character motion may remain client-owned for responsiveness. Implement position validation and accepted-position tracking; do not advertise fully server-simulated movement. Use anchored objectives and server-owned minions or anchored logical minion movement. See [network ownership](https://create.roblox.com/docs/physics/network-ownership).

## Network protocol v1
Create remotes only on the server under `ReplicatedStorage.Remotes`. Use fixed field sets, numeric IDs and bounded arrays. Never accept arbitrary Instance paths, asset IDs, functions or client damage values.

`ActionRequest` client -> server: `{version=1, matchId=integer, sequence=positive integer, action="Pulse"|"ArcBolt"|"Slip", direction=Vector3?}`. Pulse omits direction; Bolt/Slip require a finite planar unit vector within tolerance. Client supplies neither origin nor target. Match ID is the current server epoch. Sequence increases for the connection across matches; duplicate/out-of-order values are rejected. No client timestamp is required; use current server state, with no lag compensation for this prototype.

Validation order: per-player token bucket before expensive work -> exact shallow schema/known fields -> finite ranges -> current match ID -> sequence -> membership/phase/alive/protection/action lock -> cooldown -> legal server origin -> target/range/line-of-sight/collision -> commit action -> broadcast bounded effects. Consume sequence for well-formed current-epoch requests even if gameplay later rejects them. Rate limit all remotes separately; cooldown is not an anti-spam limiter. Drop flood requests without per-request replies/logging. [Boundary validation reference](https://create.roblox.com/docs/scripting/security/client-server-boundary).

`ActionResult` server -> requesting client: `{sequence, accepted, reason, serverTime, cooldownEndsAt?}`. Reasons are fixed short codes. Accepted action effects have unique event IDs for deduplication. Denied prediction rolls back the local overlay; no damage was committed.

`MatchRequest` client -> server: `{version=1, matchId, command="Sync"|"Ready"|"Rematch"}`. Max 2 requests/s with burst 4; Sync returns a current snapshot at any phase; Ready and Rematch require membership and appropriate phase. Server records flags once, so repeated Ready cannot accelerate countdown.

`StateSnapshot` server -> client: `{version, matchId, revision, phase, serverTime, endsAt, teams, cores, towers, readyFlags, result?}` plus only the recipient's action cooldowns. Bound collections to two participants and four structures. Send an initial snapshot on Sync, on transitions and at up to 5 Hz for HUD state; normal character replication carries motion. Client subscribes before Sync, discards older epoch/revision, and uses Workspace:GetServerTimeNow for countdown display.

`CombatFX` server -> clients: bounded per-action `{matchId, eventId, kind, actorId, origin, direction, serverTime}`. Origins and directions come from validated server execution. No client-to-client forwarding. Keep damage results in authoritative health state/snapshots; cosmetic effects never apply damage.

## Simulation and correctness
Use one central Heartbeat-driven scheduler with accumulated time: gameplay at ~20 Hz, minion decision updates at ~5 Hz, bounded catch-up after stalls. Sweeps use previous/current projectile positions so fast bolts do not tunnel. Compare time deadlines, never assume task.wait duration is exact. Stable entity IDs resolve equal-distance targets.

Every delayed callback captures match epoch and character generation. Recheck both before applying an effect. Cancel old tasks, projectiles and connections on death/leave/reset as appropriate; never retain a Player after PlayerRemoving. Make death/structure removal and result commitment idempotent. Evaluate both core deaths before selecting winner for the simulation step. No health modification may bypass CombatService.

MovementService samples at ~10 Hz and checks speed, vertical displacement, arena bounds and swept wall crossings from the last accepted point. Use a bounded latency allowance that does not accumulate into permanent teleport credit. A server dash grant covers one known segment and expiry only; spawn/respawn teleports use explicit server grants. Reject damage originating from invalid/recently corrected motion and restore the legal transform. Tune tolerance under simulated delay; log sampled violations and correct before considering penalties. Never auto-ban from one lag spike. Include vertical/flying checks even on a flat map. Fully server-owned character movement is an alternative only after two-phone responsiveness tests.

Represent projectile collision logically on the server, rendering cosmetic tracers on clients. Do not use client-owned Touched events as proof of impact. NPC ownership must not drift to nearby players. Core lock and friendly-fire checks sit inside the common damage function so every attack path obeys them.

## Cleanup, diagnostics and code shape
No DataStore, external HTTP, secrets, marketplace or telemetry service is needed. Keep temporary server counters: match starts/ends, duration, result reason, ability accepts/reject totals, alive minions, active projectiles. Avoid logging names/chat/device identifiers beyond voluntary test evidence. Return bounded diagnostic snapshots only in Studio. Keep test-only controls behind RunService:IsStudio(); never trust a client 'isAdmin' flag.

Each service exposes Init/Start/Stop or equivalent explicit ownership. Track and disconnect connections. Freeze or treat config as immutable; mutable match state lives on the server. Make pure targeting/tie-break/schema functions testable. Enable strict Luau and run Studio Script Analysis. Do not introduce code-generation frameworks, packages or security claims that are not needed for these tasks.
