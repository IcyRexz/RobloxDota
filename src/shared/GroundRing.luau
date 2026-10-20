--!strict
-- A circle drawn on the ground that follows its shape (owner 2026-10-21: the
-- Lightning Strike area should hug the ground, not float as a flat disc).
-- A rim of short dashes plus a faint fill of small tiles; every piece is
-- dropped onto the ground below it (Terrain and the base floor) and tilted to
-- the slope. Used for the Strike aiming area and the ability effects.
-- Client-side display only.

local Workspace = game:GetService("Workspace")

local GroundRing = {}
GroundRing.__index = GroundRing

local RIM_DASHES = 32
local FILL_RINGS = { 0.33, 0.66 } -- fill tiles on circles at these shares of the radius
local FILL_PER_RING = { 8, 16 }
local DROP_FROM = 20 -- studs above the centre each probe starts
local DROP_LENGTH = 60

export type Ring = typeof(setmetatable(
	{} :: {
		model: Model,
		rim: { Part },
		fill: { { part: Part, share: number, angle: number } },
		radius: number,
		params: RaycastParams,
	},
	GroundRing
))

local function piece(model: Model, size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- The ground to stick to: Terrain plus the base floor (not units, trees or rocks).
local function groundParams(): RaycastParams
	local include: { Instance } = { Workspace.Terrain }
	local arena = Workspace:FindFirstChild("Arena")
	local base = arena and arena:FindFirstChild("PlayerBase")
	local floor = base and base:FindFirstChild("BaseFloor")
	if floor then
		table.insert(include, floor)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	return params
end

function GroundRing.new(color: Color3, radius: number, rimTransparency: number, fillTransparency: number): Ring
	local model = Instance.new("Model")
	model.Name = "GroundRing"
	local rim: { Part } = {}
	for _ = 1, RIM_DASHES do
		table.insert(rim, piece(model, Vector3.new(0.35, 0.06, 1), color, rimTransparency))
	end
	local fill = {}
	for index, share in FILL_RINGS do
		local count = FILL_PER_RING[index]
		for i = 1, count do
			local tile = piece(model, Vector3.new(0.5, 0.05, 0.5), color, fillTransparency)
			table.insert(fill, { part = tile, share = share, angle = (i / count) * 2 * math.pi + index })
		end
	end
	local self = setmetatable({
		model = model,
		rim = rim,
		fill = fill,
		radius = radius,
		params = groundParams(),
	}, GroundRing)
	return self
end

-- Ground point and normal below (x, z), or a flat fallback at `y`.
function GroundRing.probe(self: Ring, x: number, z: number, y: number): (Vector3, Vector3)
	local hit = Workspace:Raycast(Vector3.new(x, y + DROP_FROM, z), Vector3.new(0, -DROP_LENGTH, 0), self.params)
	if hit then
		return hit.Position, hit.Normal
	end
	return Vector3.new(x, y, z), Vector3.yAxis
end

-- Lays a piece flat on the ground at `point`, long side along `tangent`.
local function lay(part: Part, point: Vector3, normal: Vector3, tangent: Vector3)
	local along = tangent - normal * tangent:Dot(normal)
	if along.Magnitude < 1e-3 then
		along = Vector3.xAxis
	end
	along = along.Unit
	local right = along:Cross(normal)
	part.CFrame = CFrame.fromMatrix(point + normal * 0.08, right, normal)
end

-- Draws the circle around `centre` (any height; it drops to the ground).
-- `radius` overrides the size (for growing rings).
function GroundRing.place(self: Ring, centre: Vector3, radius: number?)
	local r = radius or self.radius
	local dashLength = 2 * math.pi * r / RIM_DASHES * 0.6
	for i, dash in self.rim do
		local angle = (i / RIM_DASHES) * 2 * math.pi
		local x, z = centre.X + math.cos(angle) * r, centre.Z + math.sin(angle) * r
		local point, normal = self:probe(x, z, centre.Y)
		dash.Size = Vector3.new(0.35, 0.06, dashLength)
		lay(dash, point, normal, Vector3.new(-math.sin(angle), 0, math.cos(angle)))
	end
	for _, tile in self.fill do
		local d = r * tile.share
		local x, z = centre.X + math.cos(tile.angle) * d, centre.Z + math.sin(tile.angle) * d
		local point, normal = self:probe(x, z, centre.Y)
		lay(tile.part, point, normal, Vector3.xAxis)
	end
	self.model.Parent = Workspace
end

function GroundRing.hide(self: Ring)
	self.model.Parent = nil
end

-- Sets every piece's transparency: rim, then fill (for fading).
function GroundRing.setTransparency(self: Ring, rim: number, fill: number)
	for _, dash in self.rim do
		dash.Transparency = rim
	end
	for _, tile in self.fill do
		tile.part.Transparency = fill
	end
end

function GroundRing.destroy(self: Ring)
	self.model:Destroy()
end

return GroundRing
