--!strict
-- Builds the battlefield landscape when the server starts (owner request 2026-10-20):
--  * rolling Roblox Terrain: gentle rises up to MAX_RISE and dips down to
--    MAX_DEPTH studs, flat (height 0) in and around our base and around the
--    zombie cores and spawns, so structures never float or sink
--  * green placeholder trees (trunk + ball canopy) and grey placeholder rocks:
--    a forest belt along the open map edges (hides the invisible boundary) and
--    a few scattered ones on the battlefield, spaced so they never form corridors
-- Trees and rocks go into Workspace.Arena.Nature, so the swarm flow fields
-- (SwarmField, which calls build() before reading the map) walk around them.
-- Hills never block attacks (owner decision 2026-10-20): Targeting's line of
-- sight ignores Terrain. Same seed every time, so the map is always the same.
-- The flat Ground part stays as the map's bounds marker (minimap) but stops
-- colliding and is hidden once the terrain replaces it. Terrain made here only
-- exists while the game runs; Studio's edit view still shows the flat ground.

local Workspace = game:GetService("Workspace")

local Landscape = {}

local SEED = 20261020
local MAX_RISE = 6 -- studs above the flat ground at most
local MAX_DEPTH = 4 -- studs below it at most
local HEIGHT_SCALE = 9 -- raw noise to studs, before the soft limits
local BROAD_SIZE = 110 -- studs across one broad hill or hollow
local DETAIL_SIZE = 45 -- smaller bumps on top
local DETAIL_SHARE = 0.45
local FLAT_MARGIN_BASE = 8 -- studs of flat ground kept around the base floor
local FLAT_MARGIN_ZOMBIES = 14 -- around zombie cores and spawns
local BLEND = 25 -- studs over which the ground eases from flat into hills
local VOXEL = 4
local BOTTOM = -12 -- terrain is filled from here up to the surface

-- Trees and rocks.
local BELT_DEPTH = 14 -- studs of forest along each open edge
local BELT_SPACING = 6 -- one row of bigger trees (was two passes) to keep the part count down
local SCATTER_TREES = 14
local SCATTER_ROCKS = 16
local SCATTER_SPACING = 24 -- min studs between scattered props (no corridors)
local SCATTER_KEEP_OUT = 26 -- studs from the base floor and zombie areas
local TRUNK_COLOR = Color3.fromRGB(110, 78, 50)
local LEAF_COLOR = Color3.fromRGB(46, 140, 52)
local ROCK_COLOR = Color3.fromRGB(128, 128, 134)

local arena = Workspace:WaitForChild("Arena")
local battlefield = arena:WaitForChild("Battlefield")
local ground = battlefield:WaitForChild("Ground") :: BasePart
local minX = ground.Position.X - ground.Size.X / 2
local maxX = ground.Position.X + ground.Size.X / 2
local minZ = ground.Position.Z - ground.Size.Z / 2
local maxZ = ground.Position.Z + ground.Size.Z / 2

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
local baseBox = flatBoxes[1]
local zombieBoxes: { Box } = {}
for _, item in arena:WaitForChild("ZombieBase"):GetChildren() do
	if item:IsA("BasePart") then
		local box = boxAround(item, FLAT_MARGIN_ZOMBIES)
		table.insert(flatBoxes, box)
		table.insert(zombieBoxes, box)
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
	local raw = math.noise(x / BROAD_SIZE, z / BROAD_SIZE, 0.37)
		+ math.noise(x / DETAIL_SIZE, z / DETAIL_SIZE, 5.71) * DETAIL_SHARE
	local h = raw * HEIGHT_SCALE
	h = if h >= 0 then soften(h, MAX_RISE) else -soften(-h, MAX_DEPTH)
	return h * share
end

local function buildTerrain()
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
	-- Animated grass blades over the whole map cost every player frame rate.
	pcall(function()
		(terrain :: any).Decoration = false
	end)
	ground.CanCollide = false
	ground.Transparency = 1
end

-- Props ---------------------------------------------------------------------------

local nature = Instance.new("Model")
nature.Name = "Nature"

local function newPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = nature
	return part
end

-- Trunk blocks movement; the canopy (marked Kind = "Tree" for the minimap) is
-- above head height and does not collide.
-- Far-off belt trees skip shadows (cheaper to draw; nobody fights near them).
local function addTree(rng: Random, x: number, z: number, size: number, shadows: boolean)
	local y = Landscape.heightAt(x, z) - 1 -- sunk a little so slopes never show a gap
	local trunkHeight = 6 * size
	local trunk = newPart(Enum.PartType.Block, Vector3.new(1.6, trunkHeight, 1.6) * Vector3.new(size, 1, size), CFrame.new(x, y + trunkHeight / 2, z), TRUNK_COLOR)
	trunk.CastShadow = false
	local canopy = 8 * size * rng:NextNumber(0.85, 1.15)
	local leaves = newPart(Enum.PartType.Ball, Vector3.one * canopy, CFrame.new(x, y + trunkHeight + canopy * 0.3, z), LEAF_COLOR)
	leaves.CanCollide = false
	leaves.CastShadow = shadows
	leaves:SetAttribute("Kind", "Tree")
end

-- One to three grey lumps at random angles, partly sunk into the ground.
local function addRock(rng: Random, x: number, z: number)
	local y = Landscape.heightAt(x, z)
	for i = 1, rng:NextInteger(1, 3) do
		local size = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(2.5, 5), rng:NextNumber(3, 7)) / (if i == 1 then 1 else 1.6)
		local offset = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		local spin = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 2 * math.pi), rng:NextNumber(-0.3, 0.3))
		local rock = newPart(Enum.PartType.Block, size, CFrame.new(Vector3.new(x, y + size.Y * 0.3, z) + offset) * spin, ROCK_COLOR)
		if i == 1 then
			rock:SetAttribute("Kind", "Rock")
		end
	end
end

local function nearAny(x: number, z: number, boxes: { Box }, distance: number): boolean
	for _, box in boxes do
		if distanceToBox(x, z, box) < distance then
			return true
		end
	end
	return false
end

local function buildProps()
	local rng = Random.new(SEED)
	-- Forest belt along the north, south and east edges. The west edge is the
	-- base's back fence, so it stays open.
	local function beltRow(fromA: Vector3, toA: Vector3, inward: Vector3)
		local length = (toA - fromA).Magnitude
		local along = (toA - fromA).Unit
		local d = BELT_SPACING / 2
		while d < length do
			local depth = rng:NextNumber(2, BELT_DEPTH)
			local p = fromA + along * (d + rng:NextNumber(-2, 2)) + inward * depth
			if not nearAny(p.X, p.Z, { baseBox }, 6) then
				addTree(rng, p.X, p.Z, rng:NextNumber(1.1, 1.6), false)
			end
			d += BELT_SPACING * rng:NextNumber(0.7, 1.1)
		end
	end
	beltRow(Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), Vector3.new(0, 0, 1))
	beltRow(Vector3.new(minX, 0, maxZ), Vector3.new(maxX, 0, maxZ), Vector3.new(0, 0, -1))
	beltRow(Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), Vector3.new(-1, 0, 0))

	-- Scattered trees and rocks between the base and the forest belt.
	local placed: { Vector3 } = {}
	local function tryPlace(): Vector3?
		for _ = 1, 60 do
			local x = rng:NextNumber(baseBox.x1 + SCATTER_KEEP_OUT, maxX - BELT_DEPTH - 10)
			local z = rng:NextNumber(minZ + BELT_DEPTH + 10, maxZ - BELT_DEPTH - 10)
			local ok = not nearAny(x, z, zombieBoxes, SCATTER_KEEP_OUT)
			for _, other in placed do
				if ok and Vector3.new(x - other.X, 0, z - other.Z).Magnitude < SCATTER_SPACING then
					ok = false
				end
			end
			if ok then
				local p = Vector3.new(x, 0, z)
				table.insert(placed, p)
				return p
			end
		end
		return nil
	end
	for _ = 1, SCATTER_TREES do
		local p = tryPlace()
		if p then
			addTree(rng, p.X, p.Z, rng:NextNumber(0.9, 1.2), true)
		end
	end
	for _ = 1, SCATTER_ROCKS do
		local p = tryPlace()
		if p then
			addRock(rng, p.X, p.Z)
		end
	end
	nature.Parent = arena
end

local built = false

-- Builds the terrain, trees and rocks once; later calls do nothing.
function Landscape.build()
	if built then
		return
	end
	built = true
	buildTerrain()
	buildProps()
end

return Landscape
