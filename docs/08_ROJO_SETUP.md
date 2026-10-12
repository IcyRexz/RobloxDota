# Rojo setup and scaffold guide

Prerequisites: Roblox Studio on a supported development computer, your own Roblox account, matching Rojo v7 CLI and Studio plugin, and a source editor. No Node/Python dependency is required by the game. Follow the official [installation guide](https://rojo.space/docs/v7/getting-started/installation/) rather than trusting an unverified installer. Record the actual tool versions in TASK_STATUS.md; this pack does not pin an untested binary.

In a terminal opened at the extracted root:
```powershell
rojo --version
rojo build default.project.json -o build.rbxlx
rojo serve default.project.json
```
Open the generated place in Studio; connect the matching Rojo plugin to the displayed local server (default port 34872). Work in a new place first. Rojo synchronization can overwrite managed instances; keep Studio-authored art under a separate unmanaged location and export/back up it deliberately. This project uses `$ignoreUnknownInstances` at service boundaries to preserve unrelated content, but that is not a substitute for backups. Rojo sync is not a two-way backup of Studio edits. [Project format](https://rojo.space/docs/v7/project-format/) · [build/sync guide](https://rojo.space/docs/v7/getting-started/new-game/) · [sync limits](https://rojo.space/docs/v7/sync-details/).

## Initial smoke check
Press Play. Expect a baseplate, default spawn/avatar, top banner saying 'Starter scaffold — gameplay not implemented', and server/client bootstrap logs. This verifies source placement only. The default avatar is not the finished hero, the initial camera is not the finished mobile camera, and the floor is not the final lane.

In a running Studio SERVER command bar, execute:
```lua
require(game.ServerScriptService.Server.Tests.Smoke)()
```
It checks the scaffold schema/rate limiter. Tests are callable ModuleScripts, not auto-running production scripts. They are only a small foundation; A01–A14 cover the actual release. Use Script Analysis for Luau errors. The pack was not run in Studio during creation.

## Source mapping
- `src/shared` -> ReplicatedStorage.Shared (Config, Protocol, AnimationManifest).
- `src/server` -> ServerScriptService.Server (bootstrap, Security modules, Tests).
- `src/client` -> StarterPlayer.StarterPlayerScripts.Client (bootstrap).
- Remotes are created at runtime by server bootstrap.
- Workspace holds a generated anchored baseplate and SpawnLocation for the smoke run.

The bootstrap rejects every valid combat action with `NOT_IMPLEMENTED`. Keep this deny-by-default state until authoritative gameplay validation is wired in. Match/FX remotes are reserved but not implemented. Do not mistake the existence of a RemoteEvent for a completed feature.

## Studio work outside source sync
Set experience capacity to 2, R15 character configuration, supported mobile devices, landscape orientation, ownership and public audience in appropriate Studio/Dashboard settings. Author/publish animations under the correct owner, then enter IDs in the manifest. These settings/assets are not completely represented by this Rojo file. Record them in the release checklist. Once the target place ID is known, consider adding `servePlaceIds` to prevent syncing to an unrelated place. Build files are generated artifacts and excluded from Git by default.

## If Rojo is unavailable
Create matching folders in Studio and insert each file as the mapped Script/LocalScript/ModuleScript, copying contents manually. Names ending `.server.lua` are Scripts, `.client.lua` are LocalScripts, other `.lua` files are ModuleScripts. This fallback requires extra care and source reconciliation; return to Rojo when practical. No prebuilt `.rbxl` is included because the scaffold has not been built/validated with Rojo here.
