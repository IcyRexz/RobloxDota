# Asset register

No third-party media is included in the starter. All animation IDs are placeholders.

Repeat per asset:
- Logical key / file:
- Roblox asset ID / source URL:
- Type (animation/audio/image/mesh):
- Creator and owning account/group:
- Permission/license and attribution required:
- Compatible rig / clip duration / priority / loop:
- Non-owner published-place playback verified (date/build/account role):
- Replacement/fallback if unavailable:

Required animation keys: Idle, Run, Pulse, ArcBolt, Slip, HitReact, Death, Spawn, Victory. Every key must be complete before release. A fallback prevents a crash; it does not satisfy the animation requirement.

## Registered assets

### TowerModel
- Logical key / file: `assets/TowerModel.rbxmx` (placed on both towers by `src/server/TowerVisuals.server.luau`)
- Roblox asset ID / source URL: UNKNOWN — owner to confirm where it came from
- Type: model (275 Parts, 7 MeshParts, no scripts; checked 2026-10-13)
- Mesh asset IDs inside: 4906912683, 5992913171, 7095981688, 6571349341
- Creator and owning account/group: UNKNOWN
- Permission/license and attribution required: UNKNOWN
- Non-owner published-place playback verified: NOT RUN (meshes must load for a non-owner account)
- Replacement/fallback if unavailable: plain tower block (script leaves it visible if the model is missing)

### Default R15 walk / idle / tool-hold animations (minions)
- Roblox asset IDs: 507777826 (walk), 507766388 (idle), 507768375 (tool hold)
- Creator: Roblox (default character animations), usable in any experience
- Used by: `src/server/Minions.server.luau`
- Non-owner published-place playback verified: NOT RUN
