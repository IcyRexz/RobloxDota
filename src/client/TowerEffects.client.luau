--!strict
-- Tower effects drawn on each player's own screen: the shot, a glowing orb in
-- the tower's team colour, fired from the sword tip and following its target.
-- (The MOBA-era range ring only ever showed for enemy towers; there are none
-- now, so it was removed 2026-10-20.)
-- Display only. The server picks the target and applies the damage on arrival.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MAX_FLIGHT_TIME = 2 -- ignore shot messages with longer flight times
local ORB_SIZE = 1.4
local ORB_COLORS: { [string]: Color3 } = {
	[Config.Teams.Defenders] = Color3.fromRGB(255, 220, 140),
	[Config.Teams.Zombies] = Color3.fromRGB(150, 230, 110),
}

local shotEvent = ReplicatedStorage:WaitForChild("TowerShot") :: RemoteEvent

local function muzzlePosition(tower: BasePart): Vector3
	local muzzle = tower:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return tower.Position + Vector3.new(0, tower.Size.Y / 2, 0)
end

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
