# RobloxDota

PC-first cooperative fantasy base-defense game for Roblox (working title not chosen; the folder name is from the earlier MOBA prototype). One to five warriors, each playing a hero, defend a walled compound and its Base Core against zombie waves, earn Gold to build walls, towers and traps between waves, and level their heroes between missions. Work in progress; no full mission is playable yet. See [TASK_STATUS.md](TASK_STATUS.md) for progress and [docs/](docs/) for the design. The earlier 1v1 MOBA design is archived in [docs/archive/moba/](docs/archive/moba/). The final README follows [templates/README_TEMPLATE.md](templates/README_TEMPLATE.md).

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
