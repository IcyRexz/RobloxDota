# Asset register

Every third-party or owner-supplied asset used by the game is registered here before release.

Repeat per asset:
- Logical key / file:
- Roblox asset ID / source URL:
- Type (animation/audio/image/mesh):
- Creator and owning account/group:
- Permission/license and attribution required:
- Compatible rig / clip duration / priority / loop:
- Non-owner published-place playback verified (date/build/account role):
- Replacement/fallback if unavailable:

Animations are deferred (owner decision 2026-10-20); required animation keys will be listed here once T25 is scheduled. The MOBA-era list is in `docs/archive/moba/templates/ASSET_REGISTER.md`.

## Registered assets

### TowerModel
- Logical key / file: `assets/TowerModel.rbxmx` (placed on both prototype towers by `src/server/TowerVisuals.server.luau`; candidate turret art for the base-defense game)
- Roblox asset ID / source URL: UNKNOWN — owner to confirm where it came from
- Type: model (275 Parts, 7 MeshParts, no scripts; checked 2026-10-13)
- Mesh asset IDs inside: 4906912683, 5992913171, 7095981688, 6571349341
- Creator and owning account/group: UNKNOWN
- Permission/license and attribution required: UNKNOWN
- Non-owner published-place playback verified: NOT RUN (meshes must load for a non-owner account)
- Replacement/fallback if unavailable: plain tower block (script leaves it visible if the model is missing)

### FenceModel
- Logical key / file: `assets/FenceModel.rbxmx` (tiled along every base fence segment by `src/server/FenceVisuals.server.luau`)
- Roblox asset ID / source URL: UNKNOWN — owner to confirm (made in Studio or from the Toolbox?)
- Type: one UnionOperation, 64.6 × 12.4 × 2.4 studs, no scripts (checked 2026-10-20)
- Creator and owning account/group: UNKNOWN
- Permission/license and attribution required: UNKNOWN
- Non-owner published-place playback verified: NOT RUN
- Replacement/fallback if unavailable: wooden placeholder posts and rails built by the same script

### Default R15 walk / idle / tool-hold animations (minions, becoming enemies)
- Roblox asset IDs: 507777826 (walk), 507766388 (idle), 507768375 (tool hold)
- Creator: Roblox (default character animations), usable in any experience
- Used by: `src/server/Minions.server.luau`
- Non-owner published-place playback verified: NOT RUN

### ModelTree1 / ModelTree2 (pine trees)
- Logical key / file: `assets/ModelTree1.rbxmx` (PineTree1), `assets/ModelTree2.rbxmx` (PineTree2); cloned onto every map tree by `src/server/NatureArt.server.luau`
- Roblox asset ID / source URL: Toolbox model "low poly trees" (free), exact asset ID UNKNOWN — owner to confirm
- Type: model (2 MeshParts each: Leaf, Trunk; no scripts; checked 2026-10-21)
- Mesh asset IDs inside: 6194760834, 6177966904 (tree 1); 6194768710, 6177967350 (tree 2)
- Creator and owning account/group: ExedusDev (per the pack's "FREE ASSETS By ExedusDev" sign) — to confirm
- Permission/license and attribution required: free Toolbox asset; credit ExedusDev unless the owner learns otherwise
- Non-owner published-place playback verified: NOT RUN (meshes must load for a non-owner account)
- Replacement/fallback if unavailable: the tree's plain trunk and canopy blocks stay visible (script skips a missing model)

### ModelRock1 (rock)
- Logical key / file: `assets/ModelRock1.rbxmx` (model "lowpolyrocks"); cloned onto 24 map rocks by `src/server/NatureArt.server.luau`
- Roblox asset ID / source URL: Toolbox model, exact asset ID UNKNOWN — owner to confirm
- Type: model (1 MeshPart; no scripts; checked 2026-10-21)
- Mesh asset IDs inside: 14603612699
- Creator and owning account/group: UNKNOWN — owner to confirm
- Permission/license and attribution required: UNKNOWN (free Toolbox asset)
- Non-owner published-place playback verified: NOT RUN (mesh must load for a non-owner account)
- Replacement/fallback if unavailable: the rock's plain grey block stays visible (script skips a missing model)
