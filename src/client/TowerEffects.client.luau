--!strict
-- Tower effects drawn on each player's own screen:
--  * the shot: a glowing orb in the tower's team color, fired from the sword tip
--  * the attack range of ENEMY towers (MOBA convention: your own tower can never
--    hit you, so its ring is not shown): a faint grey dotted circle that appears
--    when you come near, and turns red while the tower is aiming at you
-- Display only. The server picks the target and applies the damage on arrival.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MAX_FLIGHT_TIME = 2 -- ignore shot messages with longer flight times
local ORB_SIZE = 1.4
local ORB_COLORS: { [string]: Color3 } = {
	Blue = Color3.fromRGB(110, 170, 255),
	Red = Color3.fromRGB(255, 110, 90),
}

local IDLE_COLOR = Color3.fromRGB(200, 200, 205)
local AGGRO_COLOR = Color3.fromRGB(235, 50, 45)
local RING_TRANSPARENCY = 0.55 -- faint while the tower is not aiming at you
local RING_AGGRO_TRANSPARENCY = 0.05 -- strong while it is
-- The ring shows once your character is this close to the ring's edge.
local RING_SHOW_MARGIN = 20
local PROXIMITY_CHECK_SECONDS = 0.2
local RING_HEIGHT = 0.05 -- just above the floor (floor top is y = 0)
local DASH_COUNT = 40
local DASH_SHARE = 0.55 -- part of each dash+gap step that is dash
local DASH_WIDTH = 0.5
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

local player = Players.LocalPlayer
local arena = Workspace:WaitForChild("Arena")
local shotEvent = ReplicatedStorage:WaitForChild("TowerShot") :: RemoteEvent

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

local function muzzlePosition(tower: BasePart): Vector3
	local muzzle = tower:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return tower.Position + Vector3.new(0, tower.Size.Y / 2, 0)
end

-- Range rings ----------------------------------------------------------------

type Ring = { tower: BasePart, model: Model, dashes: { Part }, targetValue: ObjectValue? }
local rings: { Ring } = {}

local function characterPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function refreshRing(ring: Ring)
	local target = if ring.targetValue then ring.targetValue.Value else nil
	local aimedAtMe = target ~= nil and target == player.Character

	local health = ring.tower:GetAttribute("Health")
	local standing = type(health) == "number" and health > 0
	local isEnemy = ring.tower:GetAttribute("Team") ~= localTeam()
	local position = characterPosition()
	local near = position ~= nil
		and Vector3.new(position.X - ring.tower.Position.X, 0, position.Z - ring.tower.Position.Z).Magnitude
			<= Config.Structure.TowerRange + RING_SHOW_MARGIN
	ring.model.Parent = if standing and isEnemy and (near or aimedAtMe) then Workspace else nil

	local color = if aimedAtMe then AGGRO_COLOR else IDLE_COLOR
	local transparency = if aimedAtMe then RING_AGGRO_TRANSPARENCY else RING_TRANSPARENCY
	for _, dash in ring.dashes do
		dash.Color = color
		dash.Transparency = transparency
	end
end

local function addRing(tower: BasePart)
	local radius = Config.Structure.TowerRange
	local centre = Vector3.new(tower.Position.X, RING_HEIGHT, tower.Position.Z)
	local model = Instance.new("Model")
	model.Name = tower.Name .. "Range"
	-- Short flat dashes laid around the circle, each along its tangent.
	local dashLength = 2 * math.pi * radius / DASH_COUNT * DASH_SHARE
	local dashes: { Part } = {}
	for i = 1, DASH_COUNT do
		local angle = (i / DASH_COUNT) * 2 * math.pi
		local position = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local dash = Instance.new("Part")
		dash.Name = "Dash"
		dash.Size = Vector3.new(DASH_WIDTH, 0.05, dashLength)
		dash.CFrame = CFrame.lookAt(position, position + tangent)
		dash.Material = Enum.Material.Neon
		dash.Anchored = true
		dash.CanCollide = false
		dash.CanQuery = false
		dash.CanTouch = false
		dash.CastShadow = false
		dash.Parent = model
		table.insert(dashes, dash)
	end

	local ring: Ring = { tower = tower, model = model, dashes = dashes, targetValue = nil }
	table.insert(rings, ring)

	local function watchTarget(value: Instance)
		if value.Name == "Target" and value:IsA("ObjectValue") then
			ring.targetValue = value
			value.Changed:Connect(function()
				refreshRing(ring)
			end)
			refreshRing(ring)
		end
	end
	local existing = tower:FindFirstChild("Target")
	if existing then
		watchTarget(existing)
	end
	tower.ChildAdded:Connect(watchTarget)
	tower:GetAttributeChangedSignal("Health"):Connect(function()
		refreshRing(ring)
	end)
	refreshRing(ring)
end

for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Tower" then
		addRing(item)
	end
end

local function refreshAllRings()
	for _, ring in rings do
		refreshRing(ring)
	end
end
player:GetAttributeChangedSignal("Team"):Connect(refreshAllRings)
player.CharacterAdded:Connect(refreshAllRings)
task.spawn(function()
	while true do
		task.wait(PROXIMITY_CHECK_SECONDS)
		refreshAllRings()
	end
end)

-- Shots ----------------------------------------------------------------------

local function aimPoint(model: Model): Vector3?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Flies the orb from the sword tip to the target, following it if it moves.
local function flyShot(tower: BasePart, target: Model, flightTime: number)
	local targetPoint = aimPoint(target)
	if not targetPoint then
		return
	end
	local start = muzzlePosition(tower)
	local team = tower:GetAttribute("Team")
	local color = if type(team) == "string" and ORB_COLORS[team] then ORB_COLORS[team] else Color3.new(1, 1, 1)

	local orb = Instance.new("Part")
	orb.Name = "TowerShot"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * ORB_SIZE
	orb.Color = color
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Position = start
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 2
	light.Parent = orb
	orb.Parent = Workspace

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		targetPoint = aimPoint(target) or targetPoint -- keep the last point if the target is gone
		local alpha = math.min(elapsed / math.max(flightTime, 0.01), 1)
		orb.Position = start:Lerp(targetPoint :: Vector3, alpha)
		if alpha >= 1 then
			connection:Disconnect()
			orb:Destroy()
		end
	end)
end

shotEvent.OnClientEvent:Connect(function(tower: unknown, target: unknown, flightTime: unknown)
	if not (typeof(tower) == "Instance" and tower:IsA("BasePart")) then
		return
	end
	if not (typeof(target) == "Instance" and target:IsA("Model")) then
		return
	end
	if not (type(flightTime) == "number" and flightTime == flightTime and flightTime >= 0 and flightTime <= MAX_FLIGHT_TIME) then
		return
	end
	flyShot(tower, target, flightTime)
end)
