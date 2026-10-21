--!strict
-- Puts the owner's tree models on the map's trees (owner request 2026-10-21).
-- src/map/Nature.model.json (written by tools/gen_nature.py) holds plain parts
-- per tree: TreeNTrunk (collision block) and TreeN (Kind = Tree, a canopy block
-- that blocks line of sight and is drawn on the minimap). Like the fences, those
-- blocks stay the real tree; the art is decoration only and never blocks
-- movement, hits or line of sight. Here both blocks are hidden and the model
-- named by the canopy's Art attribute (ServerStorage.Assets.ModelTree1 or
-- ModelTree2, saved from Studio as assets/<name>.rbxmx) is cloned, scaled by
-- ArtScale, turned by ArtYaw degrees and stood with its Trunk on the Ground
-- height under the canopy. A tree whose model is missing keeps its blocks.
-- Model rocks (owner 2026-10-21) are one block, ModelRockN (Kind = Rock, it
-- collides), with the same attributes naming ModelRock1; the rock stands with
-- the middle of its bottom on Ground. Block rocks have no Art and are left alone.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local assets = ServerStorage:WaitForChild("Assets")
local nature = Workspace:WaitForChild("Arena"):WaitForChild("Nature")

local function decorate(part: BasePart, shadow: boolean)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = shadow
end

local function dress(canopy: BasePart) -- the canopy block, or a model rock's block
	local artName, scale, yaw, ground =
		canopy:GetAttribute("Art"), canopy:GetAttribute("ArtScale"), canopy:GetAttribute("ArtYaw"), canopy:GetAttribute("Ground")
	if not (type(artName) == "string" and type(scale) == "number" and type(yaw) == "number" and type(ground) == "number") then
		return
	end
	local template = assets:FindFirstChild(artName)
	if not (template and template:IsA("Model")) then
		return
	end
	local model = template:Clone()
	model.Name = canopy.Name .. "Art"
	model.WorldPivot = CFrame.new(model:GetPivot().Position) -- ignore a tilted saved pivot
	model:ScaleTo(model:GetScale() * scale)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			decorate(item, canopy.CastShadow)
		end
	end
	-- Anchor point: under the trunk (the middle for a rock), at the bottom of the whole model.
	local boxCFrame, boxSize = model:GetBoundingBox()
	local trunk = model:FindFirstChild("Trunk")
	local centre = if trunk and trunk:IsA("BasePart") then trunk.Position else boxCFrame.Position
	local anchor = CFrame.new(centre.X, boxCFrame.Y - boxSize.Y / 2, centre.Z)
	local pivotFromAnchor = anchor:ToObjectSpace(model:GetPivot())
	local base = Vector3.new(canopy.Position.X, ground, canopy.Position.Z)
	model:PivotTo(CFrame.new(base) * CFrame.Angles(0, math.rad(yaw), 0) * pivotFromAnchor)
	model.Parent = nature

	canopy.Transparency = 1
	local trunkBlock = nature:FindFirstChild(canopy.Name .. "Trunk")
	if trunkBlock and trunkBlock:IsA("BasePart") then
		trunkBlock.Transparency = 1
	end
end

for _, item in nature:GetChildren() do
	if item:IsA("BasePart") and item:GetAttribute("Art") ~= nil then
		dress(item)
	end
end
