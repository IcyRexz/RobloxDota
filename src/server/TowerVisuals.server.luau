--!strict
-- Puts the TowerModel art on top of each tower block in the map.
-- The plain block stays the real tower (hitbox, health, name label);
-- the model is decoration only, so it never blocks hits or line of sight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

-- Khaki for our side, zombie green for theirs (no colour teams).
local TEAM_COLORS: { [string]: Color3 } = {
	[Config.Teams.Defenders] = Color3.fromRGB(158, 140, 100),
	[Config.Teams.Zombies] = Color3.fromRGB(72, 98, 52),
}
-- The knight's body parts are the MeshParts directly inside the model; everything
-- else (stone, pillars) keeps its original color. The sword stays grey too.
local UNPAINTED_MESHES = { Sword = true }

local assets = ServerStorage:WaitForChild("Assets")
local template = assets:WaitForChild("TowerModel") :: Model
local arena = Workspace:WaitForChild("Arena")

-- Flattens a direction onto the ground so only left/right turning is measured.
local function groundDirection(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(-1, 0, 0)
end

local function dressTower(block: BasePart)
	local team = block:GetAttribute("Team")
	local teamColor = if type(team) == "string" then TEAM_COLORS[team] else nil

	local model = template:Clone()
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end
	if teamColor then
		for _, child in model:GetChildren() do
			if child:IsA("MeshPart") and not UNPAINTED_MESHES[child.Name] then
				child.Color = teamColor
			end
		end
	end

	-- The saved pivot is upside down, so reset it to upright before measuring.
	model.WorldPivot = CFrame.new(model:GetPivot().Position)

	-- Turn the model so the knight faces the battlefield (+X, toward the zombies).
	local head = model:FindFirstChild("Head")
	local facing = groundDirection(if head and head:IsA("BasePart") then head.CFrame.LookVector else Vector3.zero)
	local yaw = math.atan2(facing.Z, facing.X) -- turning by this lines the face up with +X

	-- Stand the model on the floor, centred on the block.
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivotFromBox = boxCFrame:ToObjectSpace(model:GetPivot())
	local floorY = block.Position.Y - block.Size.Y / 2
	local boxTarget = CFrame.new(block.Position.X, floorY + boxSize.Y / 2, block.Position.Z)
		* CFrame.Angles(0, yaw, 0)
	model:PivotTo(boxTarget * pivotFromBox)

	model.Name = block.Name .. "Visual"
	model.Parent = block.Parent
	block.Transparency = 1

	-- Shots start at the sword tip: the upper end of the sword's long side.
	-- Structures.server and the client effects read this "Muzzle" attachment.
	local sword = model:FindFirstChild("Sword")
	if sword and sword:IsA("BasePart") then
		local size = sword.Size
		local longAxis = if size.X >= size.Y and size.X >= size.Z
			then Vector3.xAxis * size.X
			elseif size.Y >= size.Z then Vector3.yAxis * size.Y
			else Vector3.zAxis * size.Z
		local endA = sword.CFrame:PointToWorldSpace(longAxis / 2)
		local endB = sword.CFrame:PointToWorldSpace(-longAxis / 2)
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Parent = block
		muzzle.WorldPosition = if endA.Y >= endB.Y then endA else endB
	end
end

for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Tower" then
		dressTower(item)
	end
end
