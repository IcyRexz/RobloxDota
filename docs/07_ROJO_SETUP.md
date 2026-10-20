# Rojo setup

Prerequisites: Roblox Studio, your own Roblox account, Rojo 7.7.1 CLI and matching Studio plugin, Rokit for the pinned static-check tools (`rokit.toml`). Follow the official [installation guide](https://rojo.space/docs/v7/getting-started/installation/). Record actual versions in `TASK_STATUS.md`.

```bash
rojo --version
rojo build default.project.json -o build.rbxlx
rojo serve default.project.json
```
Open the place in Studio and connect the Rojo plugin (default port 34872). `build.rbxlx` is the owner's working place: Claude never writes to it and verifies builds into its scratchpad instead. Rojo sync can overwrite managed instances and is not a two-way backup; keep Studio-authored art outside managed folders and bring it into the repo by saving `.rbxmx` files under `assets/`. Service boundaries use `$ignoreUnknownInstances`. [Project format](https://rojo.space/docs/v7/project-format/) · [sync limits](https://rojo.space/docs/v7/sync-details/).

## Source mapping (`default.project.json`)
- `src/shared` -> ReplicatedStorage.Shared (Config, Targeting).
- `src/server` -> ServerScriptService.Server (services and server scripts).
- `src/client` -> StarterPlayer.StarterPlayerScripts.Client.
- `src/map` -> Workspace.Arena (graybox map as `.model.json`).
- `assets` -> ServerStorage.Assets (owner-saved models such as `TowerModel.rbxmx`).
- StarterPlayer properties: shift lock off, first-person camera, jump power 50 (Roblox default, set explicitly so a synced place that had 0 is reset).
- Remotes are created at runtime by the server scripts that own them.

The original starter-pack scaffold (bootstraps, Protocol, Smoke test) was never imported (owner decision 2026-10-12); files are written one at a time.

## Studio work outside source sync
Server capacity (planned 5), R15, supported devices (PC first), Studio API access for DataStores (owner choice), ownership and audience are Studio/Dashboard settings not held in this file; record them in the release checklist. When the place ID is known, consider `servePlaceIds` to prevent syncing into an unrelated place.
