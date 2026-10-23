# Lobby, matchmaking, UI separation and battle instances — plan

Status: **PLAN** (2026-10-23), from the owner's pasted spec "Lobby system, matchmaking, UI architecture & performance". Nothing here is built yet. Owner decisions 2026-10-23 (section 9): PC first with touch-ready lobby UI; staged move to two places; third-person free-mouse camera in the lobby.

## 1. Audit of the current project

What exists today (uncommitted work included; Studio NOT RUN for the lobby/match pieces):

| Area | Current state | Files |
|---|---|---|
| Places | **One place** holds lobby and battle (owner 2026-10-20). Rojo builds a single `default.project.json`. | `default.project.json` |
| Lobby world | Medieval courtyard built from parts at runtime, floating west of the base (`Workspace.Lobby`). Queue dais (E joins/leaves the party), war horn (hold F starts a 10 s countdown), notice board, lobby SpawnLocation. Ground found by raycast. | `src/server/Lobby.luau`, `Config.Lobby` |
| Match flow | `Match.luau`: phases `Lobby → Countdown → Fighting → Ended`, one shared party per server, epoch, `Started`/`Ended` signals, `ReturnToLobby` remote, result decided once, everything freezes after. **No reset (T15)**: one match per server, then Play must restart. | `src/server/Match.luau`, `src/server/Spawns.luau`, `src/server/PlayerTeams.server.luau` |
| Battle simulation gating | Good: spawning, events, towers, hero actions and dev tools check `Match.isFighting()` / `inParty`, so combat does not run in the lobby. Map, terrain, flow fields and nature art still load at server start (they must in one place). | `Minions`, `ZombieEvents`, `Structures`, `HeroActions`, `DevTools` |
| UI | 22 client scripts, each builds its own ScreenGui at start with `ResetOnSpawn = false`. **Only `Lobby.client` and `MatchEnd.client` check where the player is.** HUD, crosshair, minimap, Gold, core strip, match clock, scoreboard etc. are **visible in the lobby** — the spec's main UI bug exists today. The first-person locked camera also applies in the lobby. | `src/client/*` |
| UI kit | Solid base to reuse: `UiTheme` (tokens, `block`, `styleBlock`, `text`), `MenuKit` (the standard two-column menu window, tiles, info area, close), `FloatingText`. | `src/shared/UiTheme.luau`, `src/shared/MenuKit.luau` |
| Classes | Only the Mage exists; no class picker (T18, how a class is chosen is OPEN). | `MageAbilities`, `HeroProgress` |
| Progression | In-match only (levels, masteries, Gold). End-of-match reward `ZombieCoresEarned` attribute, **not saved**. **No DataStore code** (T20 TODO). | `HeroProgress`, `Gold`, `Match` |
| Gear / shop / upgrades (persistent) | None. Catalogue and prices OPEN. (Base upgrades are in-match, Gold-bought, battle-only.) | — |
| Party / invites / queue | One server-wide party, no leader, no invites, no queue states. | `Match.luau` |
| Remotes | Created ad hoc by each server script under `ReplicatedStorage`; validation and rate limits per handler. | various |

## 2. Proposed architecture

**Two places in one experience** (as the spec asks), reached in two stages so every step stays testable in Studio:

- **Lobby place:** social courtyard, navigation UI, class/equipment/upgrade/shop panels, party and queue, player data. Runs no combat, AI, waves, map terrain or flow fields.
- **Battle place:** the current arena and all combat code. Each match is **one reserved server** (`TeleportOptions.ShouldReserveServer`), runs **one match**, then sends everyone back and shuts down. This removes the need for a battlefield reset (T15 shrinks to "results then return"), and gives full isolation between matches for free.

**Stage A (single place, Studio-testable):** build the GameContext/UI split, lobby navigation, party and queue against a `MatchLauncher` interface whose first implementation is the existing in-place start (`Match.luau` moves the party to the base pad). **Stage B (two places):** add the `TeleportLauncher` implementation and split the Rojo tree into two projects; the lobby and battle code written in stage A does not change.

Why: TeleportService does not work in Studio play tests, so building teleports first would leave everything untestable until publishing. The launcher interface keeps stage A from being thrown away.

Performance: the lobby server stops loading terrain, flow fields (`SwarmField`), 500+ nature parts and battle remotes; mobile clients in the lobby skip the whole battle map and HUD. Limits: one battle server per match costs a server start (a few seconds of loading); cross-server queues are not included (brief keeps cross-server matchmaking out of scope), so solo players are grouped only with others in the same lobby server. Expansion: a `MemoryStoreService` queue can replace the in-server queue behind the same `Matchmaking` interface.

### Server modules

| Module | Place | Role |
|---|---|---|
| `PlayerData` | both | DataStore profile (T20): load on join, session lock via `UpdateAsync`, throttled save, save on leave and `BindToClose`, retries with backoff, play-without-saving when load fails. Holds Zombie Cores / credits, selected class, owned and equipped gear, permanent upgrades, settings, and the list of reward ids already granted (duplicate-reward guard). |
| `GameContext` (server half) | both | Sets Player attribute `GameContext` = `Lobby` / `Loading` / `Battle`. In two places it is fixed per place except `Loading` during teleports. |
| `LobbyServices` (`ClassService`, `LoadoutService`, `ShopService`) | lobby | Validate and write class pick, equip, purchases through `PlayerData`. Content waits for OPEN catalogue decisions; the services exist with placeholder data. |
| `Party` (removed 2026-10-23, owner: not needed now) | lobby | Parties: leader, invite / accept / decline / leave / kick, `Config.Party.MaxSize`. Player attribute `PartyId`; party data replicated to members only. |
| `Matchmaking` | lobby | Explicit per-party state machine (below). Queue groups parties and solos up to `Config.Match.MaxPlayers`; partial matches launch after `Config.Match.FillSeconds`. Calls `MatchLauncher.launch(group)`. |
| `MatchLauncher` | lobby | `LocalArena` (stage A) or `Teleport` (stage B): reserve server, `TeleportAsync` the whole group with `TeleportData { matchId, expected = {userId…} }`, bounded retries, handles `TeleportInitFailed`. |
| `BattleSession` | battle | Grows from `Match.luau`: battle lifecycle (below), validates arrivals, waits for the expected players with a timeout, starts the fight, grants rewards once per `matchId` via `PlayerData`, returns everyone to the lobby, stops when empty. |
| Existing battle services | battle | `CombatService`, `Heroes`, `HeroActions`, `HeroProgress`, `Minions`, `SwarmField`, `ZombieEvents`, `Structures`, `Gold`, `BaseUpgrades` — unchanged, they already gate on the match. |

TeleportData is used only for non-sensitive context (match id, expected roster for the wait timeout). Valuable state always comes from `PlayerData`. A reserved server can only be entered through its access code, which only the lobby server holds.

## 3. UI ownership matrix

A shared client module `GameContext` exposes the current context and a `changed` signal. Each UI script registers its root ScreenGui(s) and optional `start`/`stop` callbacks; the manager enables only what fits the context and calls `stop` so per-frame loops disconnect. In stage B each place only ships its own scripts, so the manager is also a safety net.

| UI | Context | Script (existing → plan) | ResetOnSpawn |
|---|---|---|---|
| Lobby navigation bar (Play, Classes, Equipment, Upgrades, Shop, Party, Settings) | Lobby | new `LobbyNav.client` | false (survives respawn) |
| Play / queue status panel | Lobby | new `PlayPanel` (in `LobbyNav`) | false |
| Classes, Equipment, Upgrades, Shop panels | Lobby | new panels on `MenuKit` | false |
| Party panel and invite toast | Lobby | new `PartyPanel` | false |
| Lobby world signs and prompts | Lobby | `Lobby.client` (keep) | false (billboards) |
| Hero HUD (level ring, health, XP, ability slots) | Battle | `HeroHud.client` | false, rebinds to each character |
| Crosshair, aim assist marker | Battle | `Crosshair.client`, `HeroControls.client` | false; input and RenderStepped loops stop outside Battle |
| Minimap | Battle | `Minimap.client` | false; 0.1 s refresh stops outside Battle |
| Gold counter, core strip, match timer, announcements | Battle | `GoldCounter`, `CoreStrip`, `MatchTimer`, `Announcements` | false |
| Scoreboard (Tab), Character/mastery menu (U), Base Upgrades menu | Battle | `Scoreboard`, `CharacterMenu`, `BaseUpgradeMenu` | false |
| Death screen, revive prompt, target info, structure and unit bars | Battle | `DeathScreen`, `Revive`, `TargetInfo`, `StructureBars`, `MinionVisuals` | false |
| Match end / results | Battle (Results) | `MatchEnd.client` | false |
| Effects (hero, skill, tower) | Battle | `HeroEffects`, `SkillEffects`, `TowerEffects` | n/a (world effects) |
| Dev panel | Battle, Studio only | `DevPanel.client` | false |
| Settings | Shared (adapts: in battle no lobby links) | new `Settings` panel | false |
| Notifications / toasts | Shared | new `Toasts` (reuses `Announcements` style) | false |
| Loading screen | Loading (both places; `TeleportService:SetTeleportGui` carries it across) | new `LoadingScreen.client` | false |
| Confirmation dialogs | Shared modal | new `Modal` in `MenuKit` | false |

Camera: battle keeps first person; the lobby would use the default third-person camera with a free mouse so the nav bar can be clicked (owner check, section 9).

## 4. Lobby navigation flow

```
Spawn in lobby ──► nav bar always visible (compact; expands on tap/click)
   ├─ Play ──────► Play panel: party list, [Find match] / [Cancel], status line
   ├─ Classes ───► class picker (Mage; Archer, Warrior shown locked until built)
   ├─ Equipment ─► loadout for the selected class (empty until gear exists)
   ├─ Upgrades ──► permanent upgrades (empty until designed)
   ├─ Shop ──────► gear for Zombie Cores/credits (empty until catalogue exists)
   ├─ Party ─────► members, invite nearby players, leave/kick (leader)
   └─ Settings ──► shared settings panel
World shortcuts call the same router:
   queue dais / war horn ─► open Play panel      class NPC ─► open Classes
   (later) shop stall    ─► open Shop             upgrade anvil ─► open Upgrades
```

Rules: one primary panel at a time (opening one closes the other); modals (confirm, invite) stack above and block it; **Esc / the close button / Back** close the top modal, then the panel, then return to the plain lobby view. A `PanelRouter` module owns this; nav buttons and ProximityPrompts both call `PanelRouter.open(name)`, so there is one code path.

## 5. Matchmaking and battle lifecycle

Per party (a solo player is a party of one), server-owned, published as Player attribute `MatchState`:

```
Idle ─(create/join party)─► PartyForming ─(leader: Find match)─► Queued
Queued ─(leader: Cancel | member leaves server)─► PartyForming / Idle
Queued ─(group filled, or FillSeconds passed)─► MatchFound   (cannot cancel after this)
MatchFound ─(reserve server ok)─► Teleporting ─(arrived)─► InBattle
Teleporting ─(failure after N retries)─► PartyForming + toast "Could not join the battle"
InBattle ─(results, Return)─► Returning ─(back in lobby)─► Idle / PartyForming
```

Guards: one queue entry per party; only the leader queues or cancels; a player in a queued party cannot join another; launching sets a per-party `launching` lock so a second request is ignored; leaving the server removes the player from the party and, if the party was queued, re-queues the rest (or cancels if empty).

Battle server (`BattleSession`):

```
WaitingForPlayers (expected roster from join data; timeout Config.Match.ArrivalTimeout)
  ─► Initializing (load each PlayerData profile, spawn heroes on the pad, loading screen)
  ─► Ready (short countdown, everyone gets "Battle starts in 3")
  ─► Running (existing Fighting phase: spawns, events, clock; epoch)
  ─► Ending (a core fell: freeze, stop spawns/events/timers — exists)
  ─► Results (end screen — exists; rewards granted once per matchId and saved)
  ─► Returning (teleport each player to the lobby; retry; kick with message as last resort)
All players gone at any point ─► stop systems, save, let the server close.
```

## 6. Recommended folder structure (Rojo)

```
src/shared/            both places: Config, UiTheme, MenuKit, GameContext, PanelRouter, Targeting, ...
src/common/server/     both places: PlayerData
src/common/client/     both places: LoadingScreen, Toasts, Settings
src/lobby/server/      Lobby (courtyard), Party, Matchmaking, MatchLauncher, ClassService, LoadoutService, ShopService
src/lobby/client/      LobbyNav, panels, Lobby (world signs)
src/battle/server/     today's src/server (CombatService, Minions, Match→BattleSession, ...)
src/battle/client/     today's src/client (HUD, effects, controls, ...)
src/map/               battle map (battle place only)
lobby.project.json     shared + common + lobby
battle.project.json    shared + common + battle + map + assets
```

During stage A the existing `default.project.json` maps all of these into the one place; the move from `src/server` / `src/client` into `src/battle/...` is one mechanical slice with no code changes.

## 7. Reusable existing systems

- `Match.luau` epoch, result-once, freeze, `ReturnToLobby` → becomes `BattleSession` and the `LocalArena` launcher.
- `Lobby.luau` courtyard, ground raycasts, prompts → lobby world; prompts re-pointed at `PanelRouter`.
- `Lobby.client` custom prompt drawing and signs.
- `MatchEnd.client` score screen → Results.
- `UiTheme` + `MenuKit` → every lobby panel, modal and the nav bar.
- `CombatService`, `HeroProgress`, `Gold`, `Minions`, `ZombieEvents`, `Structures` → battle, unchanged.
- `Config.Rewards.ZombieCores` → the reward granted through `PlayerData`.

## 8. Prioritised implementation plan (one slice each, Studio check after each)

1. **UI separation (stage A)** — BUILT 2026-10-23, Studio NOT RUN (see TASK_STATUS): `GameContext` (server attribute + client module); register every battle ScreenGui and stop its loops outside Battle; third-person free-mouse camera in the lobby (if approved). Fixes the HUD-in-lobby bug now.
2. **PanelRouter + lobby nav bar** — BUILT 2026-10-23, Studio NOT RUN: with Play, Classes, Equipment, Upgrades, Shop, Party, Settings; Play panel replaces the dais/horn text flow; prompts open the same panels.
3. **Classes panel** — client part done in slice 2; the server ClassService waits until a second class exists (T18): (Mage selectable, others locked) with a server `ClassService`; Equipment / Upgrades / Shop as empty, clearly labelled panels until their catalogues are decided.
4. **Party service and panel** — built 2026-10-23, then **REMOVED** the same day (owner: not needed now). Replaced by **Create lobby**: E on the dais / Play opens a panel to pick the map and 1-4 players; others join with E; starts when the countdown ends or the lobby is full. The war horn is gone.
5. **Matchmaking states and queue** — first version BUILT 2026-10-23 inside Match.luau, Studio NOT RUN: one lobby room (Idle / Open / Waiting) separate from the battle (Idle / Starting / Fighting / Ended / Resetting); the room closes when its group goes in; a second room waits for the battlefield; loading screen; results then automatic return; battlefield reset (T15); saved stats (first piece of slice 6). Original plan: behind `MatchLauncher` (`LocalArena`), replacing the single server-wide party; partial-fill rule.
6. **PlayerData (T20):** profile, session lock, rewards once per match id, Zombie Cores saved.
7. **Two places (stage B):** Rojo split, `Teleport` launcher, `BattleSession` lifecycle, loading screen, failure handling, return teleport. Needs the owner to create the battle place in the Creator Dashboard and publish both; tested only in the published game.
8. **Optimisation pass (T28):** MicroProfiler and Developer Console stats per section 9 of the spec; enemy tick stagger review, remote traffic counts, StreamingEnabled for the battle place.

Mobile: see section 9. If the owner makes mobile the priority now, slices 1–5 are built touch-first (large buttons, `UIScale` from screen size, no hover-only info), and the battle's touch controls (T26) move up before any phone playtest of a battle.

## 9. Owner decisions

Decided 2026-10-23: (1) **PC first, lobby UI touch-ready**; battle touch controls stay in T26. (2) **Staged**: stage A in one place, then stage B two places. (3) **Lobby camera: third person, free mouse**; first person in battle.

Background for those choices:

1. **Mobile first vs PC first.** The spec says mobile-first; the brief (owner 2026-10-20) says PC launch first, mobile later (T26). Combat on a phone needs touch controls for aiming, abilities and the first-person camera — a large task of its own.
2. **Two places.** The spec asks for separate lobby and battle places; the brief (owner 2026-10-20) says one place for now. Proposed: build stage A in the one place, then split (stage B).
3. **Lobby camera:** third person with a free mouse in the lobby, first person in battle?
Still OPEN:

4. Already OPEN and needed before their panels have content: how a class is chosen/unlocked, gear catalogue and prices, permanent upgrades, the persistent currency (credits vs Zombie Cores), party size and fill rules (proposed: max party 5, max match 5, launch partial after 20 s in queue).
