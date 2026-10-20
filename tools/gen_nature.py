"""Writes src/map/Nature.model.json: the battlefield's placeholder trees and rocks.

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
Trunks and rocks collide (units walk around them); tree canopies do not.
The minimap and swarm pathing find them by their Kind attribute (Tree / Rock).
"""

import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "src" / "map"
OUT = MAP / "Nature.model.json"

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
SCATTER_KEEP_OUT = 26
TRUNK_COLOR = [110 / 255, 78 / 255, 50 / 255]
LEAF_COLOR = [46 / 255, 140 / 255, 52 / 255]
ROCK_COLOR = [128 / 255, 128 / 255, 134 / 255]


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
counts = {"Tree": 0, "Rock": 0}


def r(v):
    return round(v, 3)


def add_part(name, size, position, color, rotation=None, shape=None, collide=True, shadow=True, kind=None):
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
    part = {"name": name, "className": "Part", "properties": props}
    if kind:
        part["attributes"] = {"Kind": kind}
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
    y = height_at(x, z) - 1  # sunk a little so slopes never show a gap
    trunk_height = 6 * size
    add_part(f"Tree{n}Trunk", (1.6 * size, trunk_height, 1.6 * size), (x, y + trunk_height / 2, z), TRUNK_COLOR, shadow=False)
    canopy = 8 * size * rng.uniform(0.85, 1.15)
    add_part(f"Tree{n}", (canopy, canopy, canopy), (x, y + trunk_height + canopy * 0.3, z), LEAF_COLOR,
             shape="Ball", collide=False, shadow=shadows, kind="Tree")


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

    def try_place():
        for _ in range(60):
            x = rng.uniform(BASE_BOX[1] + SCATTER_KEEP_OUT, MAX_X - BELT_DEPTH - 10)
            z = rng.uniform(MIN_Z + BELT_DEPTH + 10, MAX_Z - BELT_DEPTH - 10)
            if near_any(x, z, ZOMBIE_BOXES, SCATTER_KEEP_OUT):
                continue
            if any(math.dist((x, z), p) < SCATTER_SPACING for p in placed):
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
print(f"Wrote {OUT.relative_to(ROOT)}: {counts['Tree']} trees, {counts['Rock']} rocks, {len(parts)} parts; "
      f"ground height {min(heights):.2f} .. {max(heights):.2f} studs")
