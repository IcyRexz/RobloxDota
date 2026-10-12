# RobloxDota

Mobile-first 1v1 Roblox lane battler (working title Riftbreak Duel). Work in progress; nothing is playable yet. See [TASK_STATUS.md](TASK_STATUS.md) for progress and [docs/](docs/) for the design. The final README follows [templates/README_TEMPLATE.md](templates/README_TEMPLATE.md).

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
