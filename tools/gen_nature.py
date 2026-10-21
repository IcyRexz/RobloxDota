"""Writes src/map/Nature.model.json: the battlefield's trees and rocks.

They are plain map parts (like the towers and spawn pads), so Rojo shows them in
Studio's edit view. Each one stands on the hills made by src/server/Landscape.luau:
height_at() below is an exact copy of Landscape.heightAt (same noise, same
numbers). Change both together, then run:

    python tools/gen_nature.py

Layout (owner request 2026-10-20):
  * a one-row forest belt along the north, south and east edges (no shadows on
    those, for frame rate); the west edge is the base's back fence, left open
  * 14 trees and 16 rocks scattered between the base and the belt, at least
    24 studs apart (never corridors), kept away from the base and zombie areas
  * 2026-10-21 (owner): 14 more scattered trees (placed after the first ones so
    their layout stays), then 24 of the owner's rock model littered between,
    at least 12 studs from anything already placed
Trunks and rocks collide (units walk around them); tree canopies do not.
The minimap and swarm pathing find them by their Kind attribute (Tree / Rock).

Tree art (owner 2026-10-21): each tree is the owner's pine model
(assets/ModelTree1.rbxmx or ModelTree2.rbxmx), cloned onto the tree at server
start by src/server/NatureArt.server.luau. This file only holds the plain
parts: an invisible-in-game trunk block (collision) and a canopy block sized to
the pine's leaves (Kind = Tree; blocks line of sight, drawn on the minimap,
see-through green in Studio's edit view). The canopy carries Art (model name),
ArtScale, ArtYaw (degrees) and Ground (height of the ground under the trunk).
Model rocks (assets/ModelRock1.rbxmx) work the same way with a single block:
Kind = Rock, collides, sized to the rock and turned with it.
"""

import json
import math
import random
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "src" / "map"
OUT = MAP / "Nature.model.json"
ASSETS = ROOT / "assets"

# --- Copy of Landscape.luau (keep in step) -------------------------------------
SEED = 20261020
MAX_RISE = 6
MAX_DEPTH = 4
HEIGHT_SCALE = 7
BROAD_SIZE = 110
DETAIL_SIZE = 45
DETAIL_SHARE = 0.45
FLAT_MARGIN_BASE = 8
FLAT_MARGIN_ZOMBIES = 14
BLEND = 25
LCG_MOD = 2147483647
LCG_MUL = 48271

# --- Trees and rocks -----------------------------------------------------------
BELT_DEPTH = 14
BELT_SPACING = 6
SCATTER_TREES = 14
SCATTER_ROCKS = 16
SCATTER_SPACING = 24
EXTRA_TREES = 14
MODEL_ROCKS = 24
MODEL_ROCK_SPACING = 12
MODEL_ROCK_SCALE = (0.7, 1.6)  # a scale-1 rock is about 5 wide, 2.5 tall
MODEL_ROCK_SINK = 0.1  # share of its height below the ground (owner 2026-10-21: was 0.25, too buried)
SCATTER_KEEP_OUT = 26
TRUNK_COLOR = [110 / 255, 78 / 255, 50 / 255]
LEAF_COLOR = [46 / 255, 140 / 255, 52 / 255]
TREE_ART = ["ModelTree1", "ModelTree2"]
ROCK_ART = "ModelRock1"
TREE_HEIGHT = 18  # studs at size 1 (a placeholder tree was about 12-14)
CANOPY_SHARE = 0.75  # canopy block width / leaf mesh width (a pine is a cone)
ROCK_COLOR = [128 / 255, 128 / 255, 134 / 255]


def load_art(name):
    """Height, leaf width and leaf height/centre (above the model's bottom) of a tree model."""
    parts = {}
    for item in ET.parse(ASSETS / f"{name}.rbxmx").getroot().iter("Item"):
        if item.get("class") != "MeshPart":
            continue
        props = item.find("Properties")
        cf, size = props.find("CoordinateFrame[@name='CFrame']"), props.find("Vector3[@name='size']")
        parts[props.find("string[@name='Name']").text] = ([float(cf.find(k).text) for k in "XYZ"], [float(size.find(k).text) for k in "XYZ"])
    bottom = min(p[1] - s[1] / 2 for p, s in parts.values())
    top = max(p[1] + s[1] / 2 for p, s in parts.values())
    art = {"height": top - bottom,
           "width": max(p[0] + s[0] / 2 for p, s in parts.values()) - min(p[0] - s[0] / 2 for p, s in parts.values()),
           "depth": max(p[2] + s[2] / 2 for p, s in parts.values()) - min(p[2] - s[2] / 2 for p, s in parts.values())}
    if "Leaf" in parts:
        (lp, ls) = parts["Leaf"]
        art.update(leaf_width=max(ls[0], ls[2]), leaf_height=ls[1], leaf_centre=lp[1] - bottom)
    return art


ART = {name: load_art(name) for name in TREE_ART + [ROCK_ART]}


def load_parts(name):
    return json.loads((MAP / name).read_text(encoding="utf-8"))["children"]


def box_around(part, margin):
    p, s = part["properties"]["Position"], part["properties"]["Size"]
    return (p[0] - s[0] / 2 - margin, p[0] + s[0] / 2 + margin, p[2] - s[2] / 2 - margin, p[2] + s[2] / 2 + margin)


ground = next(c for c in load_parts("Battlefield.model.json") if c["name"] == "Ground")
gp, gs = ground["properties"]["Position"], ground["properties"]["Size"]
MIN_X, MAX_X = gp[0] - gs[0] / 2, gp[0] + gs[0] / 2
MIN_Z, MAX_Z = gp[2] - gs[2] / 2, gp[2] + gs[2] / 2

base_floor = next(c for c in load_parts("PlayerBase.model.json") if c["name"] == "BaseFloor")
BASE_BOX = box_around(base_floor, FLAT_MARGIN_BASE)
ZOMBIE_BOXES = [box_around(c, FLAT_MARGIN_ZOMBIES) for c in load_parts("ZombieBase.model.json") if c["className"] == "Part"]
FLAT_BOXES = [BASE_BOX] + ZOMBIE_BOXES

# Value noise table, built exactly as in Landscape.luau.
perm = list(range(256))
values = [0.0] * 256
_state = SEED % LCG_MOD


def _next_int():
    global _state
    _state = (_state * LCG_MUL) % LCG_MOD
    return _state


for _i in range(256):
    values[_i] = _next_int() / LCG_MOD * 2 - 1
for _i in range(255, 0, -1):
    _j = _next_int() % (_i + 1)
    perm[_i], perm[_j] = perm[_j], perm[_i]


def lattice(ix, iz, layer):
    a = perm[(ix + layer * 57) % 256]
    return values[perm[(a + iz) % 256]]


def value_noise(x, z, layer):
    ix, iz = math.floor(x), math.floor(z)
    fx, fz = x - ix, z - iz
    u = fx * fx * (3 - 2 * fx)
    w = fz * fz * (3 - 2 * fz)
    a = lattice(ix, iz, layer)
    b = lattice(ix + 1, iz, layer)
    c = lattice(ix, iz + 1, layer)
    d = lattice(ix + 1, iz + 1, layer)
    top = a + (b - a) * u
    bottom = c + (d - c) * u
    return top + (bottom - top) * w


def distance_to_box(x, z, box):
    dx = max(box[0] - x, 0, x - box[1])
    dz = max(box[2] - z, 0, z - box[3])
    return math.sqrt(dx * dx + dz * dz)


def hill_share(x, z):
    nearest = min(distance_to_box(x, z, b) for b in FLAT_BOXES)
    t = min(max(nearest / BLEND, 0), 1)
    return t * t * (3 - 2 * t)


def soften(v, limit):
    return limit * (1 - math.exp(-v / limit))


def height_at(x, z):
    share = hill_share(x, z)
    if share <= 0:
        return 0.0
    raw = value_noise(x / BROAD_SIZE, z / BROAD_SIZE, 0) + value_noise(x / DETAIL_SIZE, z / DETAIL_SIZE, 1) * DETAIL_SHARE
    h = raw * HEIGHT_SCALE
    h = soften(h, MAX_RISE) if h >= 0 else -soften(-h, MAX_DEPTH)
    return h * share


# --- Parts -----------------------------------------------------------------------
parts = []
counts = {"Tree": 0, "Rock": 0, "ModelRock": 0}


def r(v):
    return round(v, 3)


def add_part(name, size, position, color, rotation=None, shape=None, collide=True, shadow=True, kind=None, transparency=0, extra=None):
    props = {
        "Anchored": True,
        "CanTouch": False,
        "Size": [r(v) for v in size],
        "Color": [r(v) for v in color],
        "Material": "SmoothPlastic",
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    if rotation is None:
        props["Position"] = [r(v) for v in position]
    else:
        props["CFrame"] = {"CFrame": {"position": [r(v) for v in position], "orientation": [[round(v, 6) for v in row] for row in rotation]}}
    if shape:
        props["Shape"] = shape
    if not collide:
        props["CanCollide"] = False
    if not shadow:
        props["CastShadow"] = False
    if transparency:
        props["Transparency"] = transparency
    part = {"name": name, "className": "Part", "properties": props}
    if kind:
        part["attributes"] = {"Kind": kind, **(extra or {})}
    parts.append(part)


def angles(rx, ry, rz):
    """Rotation matrix of Roblox CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz (rows)."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    return [
        [cy * cz, -cy * sz, sy],
        [cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy],
        [sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy],
    ]


def add_tree(rng, x, z, size, shadows):
    counts["Tree"] += 1
    n = counts["Tree"]
    # Look comes from its own generator so the layout (rng) stays as it was.
    look = random.Random(SEED + n)
    name = look.choice(TREE_ART)
    art = ART[name]
    ground = height_at(x, z) - 0.5  # sunk a little so slopes never show a gap
    scale = TREE_HEIGHT * size * rng.uniform(0.85, 1.15) / art["height"]
    trunk_height = art["height"] * scale * 0.6
    add_part(f"Tree{n}Trunk", (1.6 * size, trunk_height, 1.6 * size), (x, ground - 0.5 + trunk_height / 2, z), TRUNK_COLOR, shadow=False)
    width = art["leaf_width"] * scale * CANOPY_SHARE
    add_part(f"Tree{n}", (width, art["leaf_height"] * scale, width), (x, ground + art["leaf_centre"] * scale, z), LEAF_COLOR,
             collide=False, shadow=shadows, kind="Tree", transparency=0.6,
             extra={"Art": name, "ArtScale": round(scale, 4), "ArtYaw": round(look.uniform(0, 360), 1), "Ground": r(ground)})


def add_rock(rng, x, z):
    counts["Rock"] += 1
    n = counts["Rock"]
    y = height_at(x, z)
    for i in range(1, rng.randint(1, 3) + 1):
        shrink = 1 if i == 1 else 1.6
        size = (rng.uniform(3, 7) / shrink, rng.uniform(2.5, 5) / shrink, rng.uniform(3, 7) / shrink)
        ox, oz = (0, 0) if i == 1 else (rng.uniform(-3, 3), rng.uniform(-3, 3))
        rot = angles(rng.uniform(-0.3, 0.3), rng.uniform(0, 2 * math.pi), rng.uniform(-0.3, 0.3))
        ly = height_at(x + ox, z + oz)
        add_part(f"Rock{n}" if i == 1 else f"Rock{n}Piece{i}", size, (x + ox, min(y, ly) + size[1] * 0.3, z + oz),
                 ROCK_COLOR, rotation=rot, kind="Rock" if i == 1 else None)


def add_model_rock(x, z):
    counts["ModelRock"] += 1
    n = counts["ModelRock"]
    look = random.Random(SEED * 2 + n)
    art = ART[ROCK_ART]
    scale = look.uniform(*MODEL_ROCK_SCALE)
    yaw = look.uniform(0, 360)
    height = art["height"] * scale
    ground = height_at(x, z) - height * MODEL_ROCK_SINK  # partly sunk, so slopes never show a gap
    # Slightly smaller than the mesh's box, so units brush its sides rather than
    # stop short of them. Turned with the mesh.
    size = (art["width"] * scale * 0.85, height, art["depth"] * scale * 0.85)
    add_part(f"ModelRock{n}", size, (x, ground + height / 2, z), ROCK_COLOR, rotation=angles(0, math.radians(yaw), 0),
             kind="Rock", transparency=0.6,
             extra={"Art": ROCK_ART, "ArtScale": round(scale, 4), "ArtYaw": round(yaw, 1), "Ground": r(ground)})


def near_any(x, z, boxes, distance):
    return any(distance_to_box(x, z, b) < distance for b in boxes)


def build():
    rng = random.Random(SEED)

    def belt_row(a, b, inward):
        length = math.dist(a, b)
        along = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
        d = BELT_SPACING / 2
        while d < length:
            depth = rng.uniform(2, BELT_DEPTH)
            t = d + rng.uniform(-2, 2)
            x = a[0] + along[0] * t + inward[0] * depth
            z = a[1] + along[1] * t + inward[1] * depth
            size = rng.uniform(1.1, 1.6)
            if not near_any(x, z, [BASE_BOX], 6):
                add_tree(rng, x, z, size, False)
            d += BELT_SPACING * rng.uniform(0.7, 1.1)

    belt_row((MIN_X, MIN_Z), (MAX_X, MIN_Z), (0, 1))
    belt_row((MIN_X, MAX_Z), (MAX_X, MAX_Z), (0, -1))
    belt_row((MAX_X, MIN_Z), (MAX_X, MAX_Z), (-1, 0))

    placed = []

    def try_place(spacing=SCATTER_SPACING):
        for _ in range(60):
            x = rng.uniform(BASE_BOX[1] + SCATTER_KEEP_OUT, MAX_X - BELT_DEPTH - 10)
            z = rng.uniform(MIN_Z + BELT_DEPTH + 10, MAX_Z - BELT_DEPTH - 10)
            if near_any(x, z, ZOMBIE_BOXES, SCATTER_KEEP_OUT):
                continue
            if any(math.dist((x, z), p) < spacing for p in placed):
                continue
            placed.append((x, z))
            return x, z
        return None

    for _ in range(SCATTER_TREES):
        p = try_place()
        if p:
            add_tree(rng, p[0], p[1], rng.uniform(0.9, 1.2), True)
    for _ in range(SCATTER_ROCKS):
        p = try_place()
        if p:
            add_rock(rng, p[0], p[1])
    for _ in range(EXTRA_TREES):
        p = try_place()
        if p:
            add_tree(rng, p[0], p[1], rng.uniform(0.9, 1.2), True)
    for _ in range(MODEL_ROCKS):
        p = try_place(MODEL_ROCK_SPACING)
        if p:
            add_model_rock(p[0], p[1])


build()
# Sample heights the game compares with its own Landscape.heightAt at start-up
# (it warns in Output if they differ, i.e. the two copies drifted apart).
samples = [(10.0, 30.0), (120.0, -90.0), (200.0, 150.0), (-20.0, -150.0), (60.0, 95.5)]
model = {
    "className": "Model",
    "attributes": {"HeightCheck": ";".join(f"{x},{z},{height_at(x, z):.4f}" for x, z in samples)},
    "children": parts,
}
OUT.write_text(json.dumps(model, indent=1) + "\n", encoding="utf-8", newline="\n")
heights = [height_at(x, z) for x in range(int(MIN_X), int(MAX_X), 4) for z in range(int(MIN_Z), int(MAX_Z), 4)]
print(f"Wrote {OUT.relative_to(ROOT)}: {counts['Tree']} trees, {counts['Rock']} rocks, {counts['ModelRock']} model rocks, {len(parts)} parts; "
      f"ground height {min(heights):.2f} .. {max(heights):.2f} studs")
