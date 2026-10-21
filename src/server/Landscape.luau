--!strict
-- The battlefield's rolling ground (owner request 2026-10-20): Roblox Terrain
-- with gentle rises up to MAX_RISE and dips down to MAX_DEPTH studs, flat
-- (height 0) in and around our base and around the zombie core, so
-- structures never float or sink. Hills never block attacks (owner decision
-- 2026-10-20): Targeting's line of sight ignores Terrain.
--
-- Trees and rocks are NOT made here: they are ordinary map parts in
-- src/map/Nature.model.json, written by tools/gen_nature.py, so Rojo shows them
-- in Studio's edit view. That script copies heightAt below exactly (same noise,
-- same numbers) to stand each tree on the ground. Change both together, then
-- re-run the script.
--
-- Rojo cannot sync terrain, so the terrain is built two ways:
--  * once by hand in edit mode, so it shows (and saves) in your place. Studio
--    View > Command Bar, while not playing:
--      require(game.ServerScriptService.Server.Landscape).buildTerrain()
--    This also stamps the terrain with BAKE_KEY (an attribute saved with the place).
--  * at server start (SwarmField calls build()), ONLY if the place's terrain
--    does not carry the current BAKE_KEY. Rewriting baked terrain made every
--    client re-download and rebuild the whole ground at start, which showed as
--    the landscape "growing in" with a stutter (owner report 2026-10-21).
-- Change any height setting and BAKE_KEY changes with it, so stale baked
-- terrain is rebuilt automatically (and should be baked again in Studio).

local Workspace = game:GetService("Workspace")

local Landscape = {}

-- Keep these in step with tools/gen_nature.py.
local SEED = 20261020
local MAX_RISE = 6 -- studs above the flat ground at most
local MAX_DEPTH = 4 -- studs below it at most
local HEIGHT_SCALE = 7 -- raw noise to studs, before the soft limits
local BROAD_SIZE = 110 -- studs across one broad hill or hollow
local DETAIL_SIZE = 45 -- smaller bumps on top
local DETAIL_SHARE = 0.45
local FLAT_MARGIN_BASE = 8 -- studs of flat ground kept around the base floor
local FLAT_MARGIN_ZOMBIES = 14 -- around zombie cores and spawns
local BLEND = 25 -- studs over which the ground eases from flat into hills
local VOXEL = 4
local BOTTOM = -12 -- terrain is filled from here up to the surface

local arena = Workspace:WaitForChild("Arena")
local battlefield = arena:WaitForChild("Battlefield")
local ground = battlefield:WaitForChild("Ground") :: BasePart
local minX = ground.Position.X - ground.Size.X / 2
local maxX = ground.Position.X + ground.Size.X / 2
local minZ = ground.Position.Z - ground.Size.Z / 2
local maxZ = ground.Position.Z + ground.Size.Z / 2

-- Value noise ----------------------------------------------------------------------
-- Our own noise instead of math.noise, so a script outside Roblox can compute
-- identical heights. A 256-entry table of random values on a 1-stud lattice
-- (after scaling), shuffled by a permutation; between lattice points the
-- values blend smoothly. All arithmetic stays exact in doubles.

local LCG_MOD = 2147483647
local LCG_MUL = 48271
local perm: { number } = table.create(256, 0)
local values: { number } = table.create(256, 0)
do
	local state = SEED % LCG_MOD
	local function nextInt(): number
		state = (state * LCG_MUL) % LCG_MOD
		return state
	end
	for i = 0, 255 do
		perm[i + 1] = i
		values[i + 1] = nextInt() / LCG_MOD * 2 - 1
	end
	for i = 255, 1, -1 do
		local j = nextInt() % (i + 1)
		perm[i + 1], perm[j + 1] = perm[j + 1], perm[i + 1]
	end
end

local function lattice(ix: number, iz: number, layer: number): number
	local a = perm[(ix + layer * 57) % 256 + 1]
	return values[perm[(a + iz) % 256 + 1] + 1]
end

local function valueNoise(x: number, z: number, layer: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	local u = fx * fx * (3 - 2 * fx)
	local w = fz * fz * (3 - 2 * fz)
	local a = lattice(ix, iz, layer)
	local b = lattice(ix + 1, iz, layer)
	local c = lattice(ix, iz + 1, layer)
	local d = lattice(ix + 1, iz + 1, layer)
	local top = a + (b - a) * u
	local bottom = c + (d - c) * u
	return top + (bottom - top) * w
end

-- Flat areas -----------------------------------------------------------------------

-- Areas kept flat: (x0, x1, z0, z1) boxes.
type Box = { x0: number, x1: number, z0: number, z1: number }
local flatBoxes: { Box } = {}

local function boxAround(part: BasePart, margin: number): Box
	local p, half = part.Position, part.Size / 2
	return { x0 = p.X - half.X - margin, x1 = p.X + half.X + margin, z0 = p.Z - half.Z - margin, z1 = p.Z + half.Z + margin }
end

local playerBase = arena:WaitForChild("PlayerBase")
local baseFloor = playerBase:WaitForChild("BaseFloor") :: BasePart
table.insert(flatBoxes, boxAround(baseFloor, FLAT_MARGIN_BASE))
for _, item in arena:WaitForChild("ZombieBase"):GetChildren() do
	if item:IsA("BasePart") then
		table.insert(flatBoxes, boxAround(item, FLAT_MARGIN_ZOMBIES))
	end
end

local function distanceToBox(x: number, z: number, box: Box): number
	local dx = math.max(box.x0 - x, 0, x - box.x1)
	local dz = math.max(box.z0 - z, 0, z - box.z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- 0 inside a flat area, easing up to 1 at BLEND studs away.
local function hillShare(x: number, z: number): number
	local nearest = math.huge
	for _, box in flatBoxes do
		nearest = math.min(nearest, distanceToBox(x, z, box))
	end
	local t = math.clamp(nearest / BLEND, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Soft limit: grows like v near zero and levels off at `limit`.
local function soften(v: number, limit: number): number
	return limit * (1 - math.exp(-v / limit))
end

-- Ground height (studs, flat ground = 0) at a point on the battlefield.
function Landscape.heightAt(x: number, z: number): number
	local share = hillShare(x, z)
	if share <= 0 then
		return 0
	end
	local raw = valueNoise(x / BROAD_SIZE, z / BROAD_SIZE, 0) + valueNoise(x / DETAIL_SIZE, z / DETAIL_SIZE, 1) * DETAIL_SHARE
	local h = raw * HEIGHT_SCALE
	h = if h >= 0 then soften(h, MAX_RISE) else -soften(-h, MAX_DEPTH)
	return h * share
end

-- Terrain ----------------------------------------------------------------------------

-- Writes the whole battlefield's terrain. Safe to call again (same result);
-- works in edit mode from the Command Bar as well as in a running game.
-- Names every setting that shapes the ground; terrain stamped with a different
-- key was made by older settings.
local BAKE_KEY = string.format(
	"v1/%d/%g/%g/%g/%g/%g/%g/%g/%g/%g/%g/%g/%d/%d/%d/%d",
	SEED, MAX_RISE, MAX_DEPTH, HEIGHT_SCALE, BROAD_SIZE, DETAIL_SIZE, DETAIL_SHARE,
	FLAT_MARGIN_BASE, FLAT_MARGIN_ZOMBIES, BLEND, VOXEL, BOTTOM,
	math.floor(minX), math.floor(maxX), math.floor(minZ), math.floor(maxZ)
)
-- The flat areas too, so moving the base or the zombie core asks for a re-bake.
for _, box in flatBoxes do
	BAKE_KEY ..= string.format("/%d,%d,%d,%d", math.floor(box.x0), math.floor(box.x1), math.floor(box.z0), math.floor(box.z1))
end

function Landscape.buildTerrain()
	local terrain = Workspace.Terrain
	local x0 = math.floor(minX / VOXEL) * VOXEL
	local z0 = math.floor(minZ / VOXEL) * VOXEL
	local nx = math.ceil((maxX - x0) / VOXEL)
	local nz = math.ceil((maxZ - z0) / VOXEL)
	local ny = math.ceil((MAX_RISE + VOXEL - BOTTOM) / VOXEL)
	local materials = table.create(nx)
	local occupancy = table.create(nx)
	for ix = 1, nx do
		local matColumn, occColumn = table.create(ny), table.create(ny)
		materials[ix], occupancy[ix] = matColumn, occColumn
		for iy = 1, ny do
			matColumn[iy], occColumn[iy] = table.create(nz), table.create(nz)
		end
		for iz = 1, nz do
			local h = Landscape.heightAt(x0 + (ix - 0.5) * VOXEL, z0 + (iz - 0.5) * VOXEL)
			local surfaceMaterial = if h < -1.5 then Enum.Material.Ground else Enum.Material.Grass
			for iy = 1, ny do
				local bottom = BOTTOM + (iy - 1) * VOXEL
				-- Share of this voxel below the surface; a part-filled top voxel
				-- puts the smooth surface between voxel edges.
				local fill = math.clamp((h - bottom) / VOXEL, 0, 1)
				occColumn[iy][iz] = fill
				matColumn[iy][iz] = if fill <= 0 then Enum.Material.Air else surfaceMaterial
			end
		end
	end
	local region = Region3.new(
		Vector3.new(x0, BOTTOM, z0),
		Vector3.new(x0 + nx * VOXEL, BOTTOM + ny * VOXEL, z0 + nz * VOXEL)
	)
	terrain:WriteVoxels(region, VOXEL, materials, occupancy)
	terrain:SetAttribute("LandscapeKey", BAKE_KEY)
	-- Animated grass blades over the whole map cost every player frame rate.
	pcall(function()
		(terrain :: any).Decoration = false
	end)
end

-- tools/gen_nature.py stores a few of its heights on the Nature model; if they
-- differ from ours, the two copies of the height formula have drifted apart
-- and trees would float or sink. Development check only (prints a warning).
local function checkNatureHeights()
	local nature = arena:FindFirstChild("Nature")
	local samples = nature and nature:GetAttribute("HeightCheck")
	if type(samples) ~= "string" then
		return
	end
	for entry in string.gmatch(samples, "[^;]+") do
		local x, z, h = string.match(entry, "^([^,]+),([^,]+),([^,]+)$")
		local nx, nz, nh = tonumber(x), tonumber(z), tonumber(h)
		if nx and nz and nh and math.abs(Landscape.heightAt(nx, nz) - nh) > 0.01 then
			warn(`[Landscape] height at ({nx}, {nz}) is {Landscape.heightAt(nx, nz)}, Nature.model.json expects {nh}: re-run tools/gen_nature.py`)
		end
	end
end

local built = false

-- Builds the terrain once per server; later calls do nothing.
function Landscape.build()
	if built then
		return
	end
	built = true
	if Workspace.Terrain:GetAttribute("LandscapeKey") == BAKE_KEY then
		print("[Landscape] baked terrain found in the place; not rebuilding it")
	else
		local started = os.clock()
		Landscape.buildTerrain()
		print(
			`[Landscape] terrain built at start in {string.format("%.2f", os.clock() - started)} s `
				.. "(bake it in Studio to skip this: see Landscape.luau)"
		)
	end
	checkNatureHeights()
end

return Landscape
