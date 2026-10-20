--!strict
-- Dresses every fence segment in the map (Part with Kind = "Fence"; a see-through
-- dark slab in Studio's edit view as a placeholder, hidden here when the art goes on).
-- Like the towers: the plain block is the real fence (it blocks movement and
-- the swarm flow fields walk around it); the art is decoration only, so it
-- never blocks movement, hits or line of sight. Fences cannot be broken
-- (owner decision 2026-10-20).
-- Art: ServerStorage.Assets.FenceModel (the owner's model, saved from Studio as
-- assets/FenceModel.rbxmx; a Model or a single part such as a Union) repeated
-- along each segment and scaled to its height.
-- Until that file exists, a placeholder of wooden posts and two rails is built.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local POST_SPACING = 6 -- studs between placeholder posts
local POST_WIDTH = 0.6
local RAIL_THICKNESS = 0.3
local RAIL_HEIGHTS = { 0.35, 0.8 } -- fraction of the fence height
local WOOD_COLOR = Color3.fromRGB(124, 92, 60)
-- Every copy of the owner's model is turned so the same side of it faces the
-- base (owner 2026-10-20: the front fence faced the wrong way). If all fences
-- end up facing the wrong way, set this to false to turn every one around.
local MODEL_FRONT_FACES_INWARD = true

local assets = ServerStorage:WaitForChild("Assets")
local arena = Workspace:WaitForChild("Arena")

local function decorate(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- The segment's long horizontal direction, its length and the ground point of its centre.
local function measure(block: BasePart): (Vector3, number, Vector3)
	local cf = block.CFrame
	local alongX = block.Size.X >= block.Size.Z
	local axis = if alongX then cf.RightVector else cf.LookVector
	local length = if alongX then block.Size.X else block.Size.Z
	local base = block.Position - Vector3.yAxis * block.Size.Y / 2
	return Vector3.new(axis.X, 0, axis.Z).Unit, length, base
end

local function addPart(parent: Instance, size: Vector3, cframe: CFrame)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = WOOD_COLOR
	part.Material = Enum.Material.Wood
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	decorate(part)
	part.Parent = parent
end

local function buildPlaceholder(block: BasePart, holder: Model)
	local axis, length, base = measure(block)
	local height = block.Size.Y
	-- Facing along the segment, so the part's Z axis runs along the fence.
	local frame = CFrame.lookAt(base, base + axis)
	local posts = math.max(1, math.ceil(length / POST_SPACING))
	for i = 0, posts do
		local along = -length / 2 + length * i / posts
		addPart(holder, Vector3.new(POST_WIDTH, height, POST_WIDTH), frame * CFrame.new(0, height / 2, -along))
	end
	for _, share in RAIL_HEIGHTS do
		addPart(holder, Vector3.new(RAIL_THICKNESS, RAIL_THICKNESS * 1.5, length), frame * CFrame.new(0, height * share, 0))
	end
end

-- Repeats the owner's model along the segment. The model is scaled so its
-- height matches the fence, its longest side is treated as its length, and
-- enough copies to cover the whole segment are spread evenly from one end to
-- the other (neighbours overlap a little rather than leave a gap).
local function buildFromModel(block: BasePart, holder: Model, template: Model)
	local axis, length, base = measure(block)
	local probe = template:Clone()
	probe.WorldPivot = CFrame.new(probe:GetPivot().Position) -- ignore a tilted saved pivot
	local _, size = probe:GetBoundingBox()
	probe:Destroy()
	local scale = block.Size.Y / math.max(size.Y, 0.01)
	local modelAlongX = size.X >= size.Z
	local pieceLength = math.max(if modelAlongX then size.X else size.Z, 0.01) * scale
	local count = math.max(1, math.ceil(length / pieceLength - 0.05))
	-- Turn the model's long side onto the segment.
	local yaw = math.atan2(-axis.Z, axis.X) - (if modelAlongX then 0 else math.pi / 2)
	-- Then pick which way it faces: the model's front (its +Z side, or +X for a
	-- model that is long along Z) toward the base floor's centre, or away from it.
	local floor = block.Parent and block.Parent:FindFirstChild("BaseFloor")
	if floor and floor:IsA("BasePart") then
		local front = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(if modelAlongX then Vector3.zAxis else Vector3.xAxis)
		local inward = Vector3.new(floor.Position.X - block.Position.X, 0, floor.Position.Z - block.Position.Z)
		if (front:Dot(inward) >= 0) ~= MODEL_FRONT_FACES_INWARD then
			yaw += math.pi
		end
	end
	for i = 1, count do
		-- First piece flush with one end, last flush with the other.
		local along = if count == 1 then 0 else (-length + pieceLength) / 2 + (length - pieceLength) * (i - 1) / (count - 1)
		local model = template:Clone()
		model.WorldPivot = CFrame.new(model:GetPivot().Position)
		model:ScaleTo(model:GetScale() * scale)
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				decorate(item)
			end
		end
		local boxCFrame, boxSize = model:GetBoundingBox()
		local pivotFromBox = boxCFrame:ToObjectSpace(model:GetPivot())
		local centre = base + axis * along + Vector3.yAxis * boxSize.Y / 2
		model:PivotTo(CFrame.new(centre) * CFrame.Angles(0, yaw, 0) * pivotFromBox)
		model.Parent = holder
	end
end

-- The fence art as a Model (a single saved part is wrapped in one).
local function loadTemplate(): Model?
	local saved = assets:FindFirstChild("FenceModel")
	if saved and saved:IsA("Model") then
		return saved
	elseif saved and saved:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = "FenceModel"
		saved:Clone().Parent = wrapper
		return wrapper
	end
	return nil
end

local template = loadTemplate()
for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Fence" then
		local holder = Instance.new("Model")
		holder.Name = item.Name .. "Visual"
		if template then
			buildFromModel(item, holder, template)
		else
			buildPlaceholder(item, holder)
		end
		holder.Parent = item.Parent
		item.Transparency = 1
	end
end
