--!strict
-- The lobby (T05, owner 2026-10-23): a medieval courtyard floating beside the
-- battlefield, west of our base (Config.Lobby). Built from parts when first
-- required, into Workspace.Lobby (outside the Arena, so map code never sees
-- it). Owner direction: medieval with trees, natural colours, no neon (the
-- reference was a dark neon hall; only its layout was kept).
--   * a grass platform ringed by a low stone wall, a cobbled plaza in the
--     middle and trees (the owner's ModelTree1/2 art) around the edge
--   * four queue daises in a row along the east side (owner 2026-10-23:
--     "make 3 more of such spawn pads and flush to 1 side"; Config.Lobby.Pads),
--     each a round stone platform with its own lobby room: press E to create a
--     lobby there, or join / leave the one open (QueuePrompt, attribute Pad)
--   * a wooden notice board behind each dais (its text is drawn by
--     Lobby.client; owner 2026-10-23: the board is the only countdown)
-- (The war horn start pedestal was removed, owner 2026-10-23: creating a
-- lobby starts its countdown.)
-- Every piece is anchored. The prompts are custom style: Lobby.client draws
-- them in the UI design system; Match.luau handles what they do.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local LobbyConfig = Config.Lobby

local GRASS = Color3.fromRGB(86, 118, 58)
local COBBLE = Color3.fromRGB(122, 118, 110)
local STONE = Color3.fromRGB(104, 100, 96)
local DARK_STONE = Color3.fromRGB(78, 76, 74)
local WOOD = Color3.fromRGB(110, 76, 44)
local DARK_WOOD = Color3.fromRGB(78, 52, 30)
local FLOOR_DEPTH = 6
local WALL_HEIGHT = 3
local WALL_THICKNESS = 2

local Lobby = {}

local folder = Instance.new("Folder")
folder.Name = "Lobby"
folder.Parent = Workspace

local centre = LobbyConfig.Centre
local size = LobbyConfig.Size

-- A part at a point relative to the lobby centre (x east, z south, y up).
local function block(name: string, partSize: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = partSize
	part.Position = centre + at
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

-- Platform, plaza and walls.
block("Floor", Vector3.new(size.X, FLOOR_DEPTH, size.Y), Vector3.new(0, -FLOOR_DEPTH / 2, 0), GRASS, Enum.Material.Grass)
block("Plaza", Vector3.new(size.X * 0.5, 0.2, size.Y * 0.55), Vector3.new(0, 0.1, 0), COBBLE, Enum.Material.Cobblestone)
for _, side in { -1, 1 } do
	block("WallX", Vector3.new(size.X, WALL_HEIGHT, WALL_THICKNESS), Vector3.new(0, WALL_HEIGHT / 2, side * (size.Y / 2 - WALL_THICKNESS / 2)), STONE, Enum.Material.Brick)
	block("WallZ", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, size.Y), Vector3.new(side * (size.X / 2 - WALL_THICKNESS / 2), WALL_HEIGHT / 2, 0), STONE, Enum.Material.Brick)
end

-- The ground under a point inside the lobby (plaza or grass), found by a ray
-- against the lobby's own floor pieces only.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { folder }
function Lobby.groundAt(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, centre.Y + 30, z), Vector3.new(0, -60, 0), groundParams)
	return if hit then hit.Position.Y else centre.Y
end

-- Trees round the edge: the owner's tree art, its lowest point on the grass.
local assets = ServerStorage:FindFirstChild("Assets")
-- (The east side holds the pads and their boards, so no trees there.)
local treeSpots = {
	Vector3.new(-0.42, 0, -0.4),
	Vector3.new(-0.42, 0, 0.4),
	Vector3.new(-0.3, 0, -0.2),
	Vector3.new(-0.3, 0, 0.2),
	Vector3.new(-0.15, 0, -0.42),
	Vector3.new(-0.15, 0, 0.42),
	Vector3.new(0.12, 0, -0.42),
	Vector3.new(0.12, 0, 0.42),
}
for index, share in treeSpots do
	local x, z = centre.X + share.X * size.X, centre.Z + share.Z * size.Y
	local ground = Lobby.groundAt(x, z)
	local template = assets and assets:FindFirstChild(if index % 2 == 0 then "ModelTree1" else "ModelTree2")
	if template and template:IsA("Model") then
		local tree = template:Clone()
		tree.Name = "Tree" .. index
		for _, item in tree:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false -- never caught by the ground rays
			end
		end
		tree:PivotTo(CFrame.new(x, ground, z) * CFrame.Angles(0, math.rad(index * 47), 0))
		-- Rest its lowest point on the grass (ground placement rule).
		local box, boxSize = tree:GetBoundingBox()
		tree:PivotTo(tree:GetPivot() + Vector3.new(0, ground - (box.Y - boxSize.Y / 2), 0))
		tree.Parent = folder
	else
		block("TreeTrunk" .. index, Vector3.new(1.5, 8, 1.5), Vector3.new(x - centre.X, ground - centre.Y + 4, z - centre.Z), DARK_WOOD, Enum.Material.Wood)
		block("TreeTop" .. index, Vector3.new(7, 7, 7), Vector3.new(x - centre.X, ground - centre.Y + 10, z - centre.Z), Color3.fromRGB(44, 96, 46), Enum.Material.Grass)
	end
end

-- The queue daises, each with its prompt and its notice board east of it
-- (the board's face toward the plaza, west). Lobby.Pads[i] is pad i.
export type Pad = { index: number, dais: Part, prompt: ProximityPrompt, board: Part }
local pads: { Pad } = {}
for index, padAt in LobbyConfig.Pads do
	local dais = Instance.new("Part")
	dais.Name = `QueueDais{index}`
	dais.Shape = Enum.PartType.Cylinder
	dais.Anchored = true
	dais.Size = Vector3.new(0.8, LobbyConfig.QueueRadius * 2, LobbyConfig.QueueRadius * 2)
	dais.CFrame = CFrame.new(centre + padAt + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	dais.Color = STONE
	dais.Material = Enum.Material.Slate
	dais:SetAttribute("Pad", index)
	dais.Parent = folder
	local rim = dais:Clone()
	rim.Name = `QueueRim{index}`
	rim.Size = Vector3.new(0.6, LobbyConfig.QueueRadius * 2 + 1.5, LobbyConfig.QueueRadius * 2 + 1.5)
	rim.CFrame = dais.CFrame - Vector3.new(0, 0.15, 0)
	rim.Color = DARK_STONE
	rim.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QueuePrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by Lobby.client
	prompt.ActionText = "Create lobby" -- Lobby.client shows the text for the current state
	prompt.ObjectText = "Battle"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = LobbyConfig.QueueRadius + 2
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Pad", index)
	prompt.Parent = dais

	local boardAt = padAt + Vector3.new(LobbyConfig.QueueRadius + 4, 0, 0)
	for _, side in { -1, 1 } do
		block(`BoardPost{index}`, Vector3.new(0.8, 9, 0.8), boardAt + Vector3.new(0, 4.5, side * 7.6), DARK_WOOD, Enum.Material.Wood)
	end
	local board = block(`NoticeBoard{index}`, Vector3.new(0.6, 6, 14), boardAt + Vector3.new(0, 5.5, 0), WOOD, Enum.Material.WoodPlanks)
	board:SetAttribute("Pad", index)
	pads[index] = { index = index, dais = dais, prompt = prompt, board = board }
end
Lobby.Pads = pads
Lobby.BoardFace = Enum.NormalId.Left -- the boards' west face, toward the plaza

-- Where players stand in the lobby: a random spot on the plaza's west half.
function Lobby.spawnSpot(): Vector3
	local spot = centre + LobbyConfig.SpawnAt + Vector3.new((math.random() * 2 - 1) * 5, 0, (math.random() * 2 - 1) * 5)
	return Vector3.new(spot.X, Lobby.groundAt(spot.X, spot.Z), spot.Z)
end

-- Roblox's own spawn point in the lobby (PlayerTeams points RespawnLocation
-- here for players outside the battle, so Roblox's spawn placement agrees
-- with Spawns.toLobby). Invisible and not solid; neutral.
local spawnPoint = Instance.new("SpawnLocation")
spawnPoint.Name = "LobbySpawn"
spawnPoint.Anchored = true
spawnPoint.Size = Vector3.new(10, 1, 10)
spawnPoint.Position = centre + LobbyConfig.SpawnAt + Vector3.new(0, -0.3, 0)
spawnPoint.Transparency = 1
spawnPoint.CanCollide = false
spawnPoint.CanQuery = false
spawnPoint.Neutral = true
spawnPoint.Duration = 0
spawnPoint.Parent = folder
Lobby.SpawnLocation = spawnPoint

return Lobby
