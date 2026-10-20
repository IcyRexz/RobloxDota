# Server-authoritative architecture

This is the implementation target for the co-op base-defense shooter. Nothing listed here counts as built until the file exists and is tested; current files are named where they exist.

## Ownership of decisions
**Server** (planned name -> current prototype file it grows from):
- MissionService: hub/mission state, party, epoch, wave/build phase timers, results. (new; `PlayerTeams.server.luau` today puts everyone on one team)
- CombatService: the one damage gateway. (`src/server/CombatService.luau`)
- PlayerService: character marking, hero stats, death/respawn. (`src/server/Heroes.server.luau`)
- WeaponService: firing requests, cooldowns, validation. (`src/server/HeroActions.server.luau`)
- EnemyService: waves, AI, cap, cleanup. (`src/server/Minions.server.luau`)
- BuildService: build nodes, placing, repair, Gold spending. (new; tower AI from `src/server/Structures.server.luau`, art from `TowerVisuals.server.luau`)
- EconomyService: Gold balances (in-match). (new)
- ProfileService (own module, not the community library unless the owner approves): DataStore load/save of credits, hero levels/XP, items, loadouts. (new)

**Client** controllers: Input/Controls, Camera, HUD, Effects, Hub UI, Build UI. Clients may predict indicators but never decide damage, kills, Gold, credits, building, wave state or results.

**Shared:** `src/shared/Config.luau` (frozen public tuning), `src/shared/Targeting.luau` (pure target rules used by both sides).

Movement stays client-owned for responsiveness; the server validates positions it relies on (shot origins, build/repair range) and keeps enemies server-owned.

## Remotes
Created only by the server under `ReplicatedStorage`. Fixed small schemas; reject wrong types, extra fields, NaN/infinity and oversized numbers; per-player rate limit before any work; drop floods silently. Never accept client damage, health, Gold, credits, positions as truth, Instance paths or asset IDs.

Planned requests (client -> server), each deny-by-default until its service exists:
- Weapon fire: action name + aim (direction or target hint, per aim decision). Server derives the origin.
- Build: node ID + piece ID. Repair: node ID.
- Hub: pick hero, set loadout, buy item, queue/leave queue, ready.

Server -> client: state snapshot (phase, wave, timer end in server time, core health, recipient's Gold), cosmetic effects (shots, impacts), announcements. Existing prototype events: `HeroAttack`, `TowerShot`, `MinionShot`, `StructureDestroyed` (to be renamed as their services move over).

## Correctness rules
- Every delayed callback captures the mission epoch and character generation and rechecks them before acting.
- Results and death handling are idempotent; one committed result per epoch.
- No health, Gold or credit change bypasses its service.
- Cooldowns use server time; clients show them from `<Action>ReadyAt` attributes.
- Clean every connection, task and spawned instance on death, leave and reset; never keep a Player after PlayerRemoving.

## Persistence (new with the genre switch)
DataStores are now required (owner decision 2026-10-20: persistent progression). Rules:
- Load on join before allowing hub purchases; if loading fails, let the player play without saving and tell them, never overwrite their save with defaults.
- Save on meaningful change (throttled), on leave and in `BindToClose`; use UpdateAsync with a session lock or version check so two servers cannot duplicate or roll back progress.
- Keep budgets in mind (retry with backoff; no save per kill).
- Studio uses a separate test store or API access only when enabled by the owner.
- No player data in logs beyond what testing needs.

## Diagnostics
Studio-only counters (missions started/ended, result reason, alive enemies, rejected requests). Test-only controls behind `RunService:IsStudio()`; never trust a client admin flag. Temporary simulation aids (`Config.Minion.TestTeamBonus`, `Config.Structure.TestStartHealth`) are removed before release.
