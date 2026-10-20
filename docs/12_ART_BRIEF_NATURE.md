# Art brief: trees and rocks (for Claude Design)

Status: brief written 2026-10-21; no art made yet. The placeholders (green ball trees, grey block rocks) are generated into `src/map/Nature.model.json` by `tools/gen_nature.py`. Finished meshes would replace them (saved by the owner as `.rbxmx` under `assets/`, like `TowerModel` and `FenceModel`).

## Facts about the game (data to give the designer)
- **Engine:** Roblox. Models import as MeshParts (FBX/OBJ). Roblox allows up to 20,000 triangles per mesh, but we want far fewer.
- **Genre and theme:** a co-op fantasy base-defense game. Warriors and heroes (swords, bows, lightning magic) defend a fenced base against zombie hordes on an open, rolling grass battlefield.
- **Camera:** first person. Trees and rocks are seen from about 5 studs (right next to them) out to about 200 studs (the forest edge as a backdrop).
- **Scale:** 1 stud is about 28 cm. A player or zombie is about 5 studs tall, fences 9 studs, towers 19 studs.
- **Current placeholder sizes** (match these roughly):
  - Trees: trunk 1.4–2.6 studs wide; total height 9–17 studs; canopy 7–13 studs across.
  - Rocks: 3–7 studs wide, 2.5–5 studs tall, placed in clusters of 1–3 at random angles, partly sunk into the ground.
- **How many:** about 237 trees in a forest belt along three map edges, 14 trees and 16 rock clusters scattered on the battlefield. Up to 100 zombies plus 5 players are on screen too, so the art must stay cheap to draw.
- **Map colours today:** Roblox Grass terrain (mid green), placeholder leaves RGB 46, 140, 52, trunks RGB 110, 78, 50, rocks RGB 128, 128, 134. **Zombies are dark green (skin RGB 78, 104, 58)**, so foliage should not be that exact green or zombies blend into the trees. Push leaves warmer (yellow-green, olive, autumn touches) or cooler (blue-green pine).
- **UI style for reference:** minimal, dark see-through panels, gold accent (`docs/11_UI_DESIGN.md`). The world can be more colourful than the UI.

## Style target: medium poly
- **Not** high-end or realistic (no photo-scanned bark, no thousands of individual leaves).
- **Not** ultra low-poly either (no 12-triangle cones or perfect cubes).
- In between: clear, chunky silhouettes with some real shape. Faceted foliage clumps, a slightly twisted trunk with a few roots and branches, rocks with bevelled planes and a few cracks. Soft painted gradients or vertex colours rather than detailed textures. Readable in one glance from far away; still pleasant up close.
- A hint of dark fantasy to suit the zombies (a few dead or gnarled trees), but mostly a natural, inviting forest.

## Budgets and technical rules
- **Triangles:** trees 600–1,500 each; rocks 150–500 each; small props under 300.
- **Materials:** one material per mesh. Use vertex colours or a single texture of 512 px or less per family (a shared atlas is ideal).
- **Pivot** at the bottom centre (where it meets the ground), Y up, sized in studs.
- **Separate trunk and canopy meshes** for trees: only the trunk collides (units walk around it); the canopy sits above head height and does not collide.
- Rocks: one collision shape per rock (simple box or hull).
- Smoothing: hard edges on rocks, softer shading on foliage.
- Names like `Tree_Oak_A`, `Tree_Pine_B`, `Rock_Boulder_A`.

## What to deliver
1. A **style and colour sheet**: the palette swatches, a lighting note, and how trees and rocks look against the grass with a zombie and a player next to them for scale.
2. **Trees (10 total):** 3 broadleaf oaks, 3 pines (good for the dense edge forest), 2 gnarled or dead trees (the zombie touch), and 2 saplings or bushes for variety.
3. **Rocks (8 total):** 3 boulders, 2 flat slabs, 2 small multi-rock clusters, and 1 mossy boulder.
4. For each: front and side views, a top silhouette, the triangle count and its size in studs.
