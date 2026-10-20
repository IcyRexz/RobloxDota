# RobloxDota

PC-first cooperative base-defense shooter for Roblox (working title not chosen; the folder name is from the earlier MOBA prototype). One to five players defend a walled compound and its Base Core against enemy waves, earn Gold to build walls, turrets and traps between waves, and progress their class between missions. Work in progress; no full mission is playable yet. See [TASK_STATUS.md](TASK_STATUS.md) for progress and [docs/](docs/) for the design. The earlier 1v1 MOBA design is archived in [docs/archive/moba/](docs/archive/moba/). The final README follows [templates/README_TEMPLATE.md](templates/README_TEMPLATE.md).

## Build and sync

```bash
rojo build default.project.json -o build.rbxlx
```

Open `build.rbxlx` in Roblox Studio, then run `rojo serve` and connect the Rojo plugin.

## Static checks

```bash
rokit install
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=types/globalTypes.None.d.luau --sourcemap=sourcemap.json src
selene src
```
