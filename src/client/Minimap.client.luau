--!strict
-- Minimap in the bottom-right corner of each player's own screen.
-- Fixed orientation matching the map layout (docs/02_GDD.md): our base at the
-- bottom, zombies arriving from the top. World +X is screen up, world +Z is
-- screen right. It never rotates with the camera.
-- Drawn from what the client already sees in Workspace:
--  * the battlefield Ground part sets the bounds; base floor, fences, trees and
--    rocks are drawn once
--  * towers, barracks and cores (Kind attribute) as squares, removed when destroyed
--  * units in Workspace.Minions and every player character as dots,
--    green your team, red the enemy; your own hero is a white dot with a facing tick
-- Display only: nothing here is sent to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local MAP_SIZE = 200 -- on-screen pixels, longest side
local MARGIN = UiTheme.space(4) -- from the screen edges
local DOT_UPDATE_SECONDS = 0.1
-- Dots and squares use the UI meaning colours; the map itself (ground, floor,
-- fences, trees, rocks) is a muted picture of the world.
local ALLY_COLOR = UiTheme.Ally
local ENEMY_COLOR = UiTheme.Enemy
local GROUND_COLOR = Color3.fromRGB(52, 66, 44)
local FLOOR_COLOR = Color3.fromRGB(84, 86, 92)
local FENCE_COLOR = Color3.fromRGB(196, 150, 100)
local TREE_COLOR = Color3.fromRGB(34, 110, 40)
local ROCK_COLOR = Color3.fromRGB(140, 140, 146)
local PROP_COLORS: { [string]: Color3 } = { Fence = FENCE_COLOR, Tree = TREE_COLOR, Rock = ROCK_COLOR }
local STRUCTURE_SIZES: { [string]: number } = { Tower = 9, Barracks = 8, Core = 12 }
local UNIT_DOT = 4
local HERO_DOT = 7
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arena = Workspace:WaitForChild("Arena")
local battlefield = arena:WaitForChild("Battlefield")
local ground = battlefield:WaitForChild("Ground") :: BasePart

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function teamColor(item: Instance): Color3
	return if item:GetAttribute("Team") == localTeam() then ALLY_COLOR else ENEMY_COLOR
end

-- Map bounds from the ground part (axis-aligned).
local minX = ground.Position.X - ground.Size.X / 2
local maxX = ground.Position.X + ground.Size.X / 2
local minZ = ground.Position.Z - ground.Size.Z / 2
local maxZ = ground.Position.Z + ground.Size.Z / 2
local scale = MAP_SIZE / math.max(maxX - minX, maxZ - minZ) -- pixels per stud

-- World position -> pixel position inside the map frame.
local function toMap(position: Vector3): UDim2
	return UDim2.fromOffset((position.Z - minZ) * scale, (maxX - position.X) * scale)
end

local screen = Instance.new("ScreenGui")
screen.Name = "Minimap"
screen.ResetOnSpawn = false
screen.Parent = playerGui

-- The map sits in a standard HUD surface panel (UI design system).
local holder = UiTheme.panel(screen)
holder.Name = "Holder"
holder.AnchorPoint = Vector2.new(1, 1)
holder.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
holder.Size = UDim2.fromOffset((maxZ - minZ) * scale + 8, (maxX - minX) * scale + 8)
UiTheme.applyScale(holder)

local map = Instance.new("Frame")
map.Name = "Map"
map.Position = UDim2.fromOffset(4, 4)
map.Size = UDim2.new(1, -8, 1, -8)
map.BackgroundColor3 = GROUND_COLOR
map.BorderSizePixel = 0
map.ClipsDescendants = true
map.Parent = holder
UiTheme.corner(map, UiTheme.Radius - 2)

-- A rectangle covering a part's footprint (parts are axis-aligned on this map).
local function addFootprint(part: BasePart, color: Color3, zIndex: number): Frame
	local box = Instance.new("Frame")
	box.Name = part.Name
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = toMap(part.Position)
	box.Size = UDim2.fromOffset(math.max(part.Size.Z * scale, 2), math.max(part.Size.X * scale, 2))
	box.BackgroundColor3 = color
	box.BorderSizePixel = 0
	box.ZIndex = zIndex
	box.Parent = map
	return box
end

-- Base floor, fences, trees and rocks: static map parts, drawn once.
local playerBase = arena:WaitForChild("PlayerBase")
local baseFloor = playerBase:WaitForChild("BaseFloor")
if baseFloor:IsA("BasePart") then
	addFootprint(baseFloor, FLOOR_COLOR, 1)
end
local function addProp(item: Instance)
	local kind = item:GetAttribute("Kind")
	local color = if type(kind) == "string" then PROP_COLORS[kind] else nil
	if color and item:IsA("BasePart") then
		addFootprint(item, color, if kind == "Fence" then 3 else 2)
	end
end
for _, item in arena:GetDescendants() do
	addProp(item)
end

-- Structures: a square each, recoloured on team change, removed when destroyed
-- (the server destroys the part).
local function addStructure(part: Instance)
	local kind = part:GetAttribute("Kind")
	local size = if type(kind) == "string" then STRUCTURE_SIZES[kind] else nil
	if not (size and part:IsA("BasePart")) then
		return
	end
	local square = Instance.new("Frame")
	square.Name = part.Name
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = toMap(part.Position)
	square.Size = UDim2.fromOffset(size, size)
	square.BackgroundColor3 = teamColor(part)
	square.BorderSizePixel = 0
	square.ZIndex = 4
	square.Parent = map
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1
	stroke.Parent = square
	local teamConnection = player:GetAttributeChangedSignal("Team"):Connect(function()
		square.BackgroundColor3 = teamColor(part)
	end)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(Workspace) then
			teamConnection:Disconnect()
			square:Destroy()
		end
	end)
end

for _, item in arena:GetDescendants() do
	addStructure(item)
end

-- Unit and hero dots: a reused pool, repositioned on a short timer.
local dotPool: { Frame } = {}
local dotsUsed = 0

local function nextDot(): Frame
	dotsUsed += 1
	local existing = dotPool[dotsUsed]
	if existing then
		existing.Visible = true
		return existing
	end
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = dot
	dot.Parent = map
	dotPool[dotsUsed] = dot
	return dot
end

-- Your own hero: white dot with a tick showing which way you face. The tick sits
-- in a square holder centred on the dot, so rotating the holder swings it round.
local selfMarker = Instance.new("Frame")
selfMarker.Name = "You"
selfMarker.AnchorPoint = Vector2.new(0.5, 0.5)
selfMarker.Size = UDim2.fromOffset(18, 18)
selfMarker.BackgroundTransparency = 1
selfMarker.ZIndex = 7
selfMarker.Visible = false
selfMarker.Parent = map
local selfDot = Instance.new("Frame")
selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
selfDot.Position = UDim2.fromScale(0.5, 0.5)
selfDot.Size = UDim2.fromOffset(HERO_DOT + 1, HERO_DOT + 1)
selfDot.BackgroundColor3 = Color3.new(1, 1, 1)
selfDot.BorderSizePixel = 0
selfDot.ZIndex = 8
selfDot.Parent = selfMarker
local selfRound = Instance.new("UICorner")
selfRound.CornerRadius = UDim.new(0.5, 0)
selfRound.Parent = selfDot
local selfStroke = Instance.new("UIStroke")
selfStroke.Color = Color3.new(0, 0, 0)
selfStroke.Thickness = 1.5
selfStroke.Parent = selfDot
local facingTick = Instance.new("Frame")
facingTick.AnchorPoint = Vector2.new(0.5, 0)
facingTick.Position = UDim2.fromScale(0.5, 0)
facingTick.Size = UDim2.fromOffset(3, 7)
facingTick.BackgroundColor3 = Color3.new(1, 1, 1)
facingTick.BorderSizePixel = 0
facingTick.ZIndex = 8
facingTick.Parent = selfMarker

local function rootOf(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isAlive(model: Instance): boolean
	local health = model:GetAttribute("Health")
	return type(health) ~= "number" or health > 0
end

local function placeDot(model: Instance, size: number)
	local root = rootOf(model)
	if not (root and isAlive(model)) then
		return
	end
	local dot = nextDot()
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = teamColor(model)
	dot.Position = toMap(root.Position)
end

local function updateDots()
	dotsUsed = 0
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		for _, unit in minions:GetChildren() do
			placeDot(unit, UNIT_DOT)
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			placeDot(other.Character, HERO_DOT)
		end
	end
	for i = dotsUsed + 1, #dotPool do
		dotPool[i].Visible = false
	end
end

-- Own marker every frame (cheap, and it keeps the facing tick smooth).
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and rootOf(character)
	if not (root and character and isAlive(character)) then
		selfMarker.Visible = false
		return
	end
	selfMarker.Visible = true
	selfMarker.Position = toMap(root.Position)
	-- Screen up is +X and screen right is +Z, so facing (x, z) is atan2(z, x) from up.
	local look = root.CFrame.LookVector
	selfMarker.Rotation = math.deg(math.atan2(look.Z, look.X))
end)

task.spawn(function()
	while true do
		updateDots()
		task.wait(DOT_UPDATE_SECONDS)
	end
end)
