--!strict
-- Minion visuals drawn on each player's own screen:
--  * a small health bar above every minion (green ally / red enemy, no name),
--    shown within Config.Display.HealthBarRange of your hero
--  * the archer's bow-draw pose and the flying arrow
-- Display only. The server owns minion health and decides every hit; the arrow
-- just shows a shot the server has already scheduled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local VISIBILITY_CHECK_SECONDS = 0.2
local ALLY_COLOR = Color3.fromRGB(70, 200, 90)
local ENEMY_COLOR = Color3.fromRGB(220, 60, 60)
local BAR_BACK_COLOR = Color3.fromRGB(25, 25, 30)
local BAR_SIZE = UDim2.fromOffset(40, 5) -- on-screen pixels
-- Until match teams exist (task T05), everyone is treated as Blue.
local DEFAULT_TEAM = "Blue"

local MAX_SHOT_TIME = 2 -- ignore shot messages with longer draw/flight times
local ARROW_COLOR = Color3.fromRGB(120, 80, 40)
-- Left arm, relative to its resting shoulder: reach forward to the string held
-- in the right hand, then pull back toward the chest before release.
local REACH_POSE = CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(math.rad(95), 0, 0)
local PULL_POSE = CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(math.rad(70), 0, 0)
local REACH_SHARE = 0.35 -- part of the draw time spent reaching
local RELEASE_TIME = 0.2 -- arm drops back to rest after letting go

local player = Players.LocalPlayer
local minionFolder = Workspace:WaitForChild("Minions")
local shotEvent = ReplicatedStorage:WaitForChild("MinionShot") :: RemoteEvent

local function localTeam(): string
	local team = player:GetAttribute("Team")
	return if type(team) == "string" then team else DEFAULT_TEAM
end

-- Health bars ---------------------------------------------------------------

type Bar = { model: Model, billboard: BillboardGui, fill: Frame }
local bars: { [Model]: Bar } = {}

local function refresh(bar: Bar)
	local health = bar.model:GetAttribute("Health")
	local maxHealth = bar.model:GetAttribute("MaxHealth")
	local max = if type(maxHealth) == "number" and maxHealth > 0 then maxHealth else 1
	local current = if type(health) == "number" then math.clamp(health, 0, max) else max
	bar.fill.Size = UDim2.fromScale(current / max, 1)
	local isAlly = bar.model:GetAttribute("Team") == localTeam()
	bar.fill.BackgroundColor3 = if isAlly then ALLY_COLOR else ENEMY_COLOR
end

local function addBar(model: Model)
	local head = model:WaitForChild("Head", 5)
	if not (head and head:IsA("BasePart")) or model.Parent ~= minionFolder then
		return
	end

	-- Parented inside the minion, so it is destroyed together with it.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Adornee = head
	billboard.Size = BAR_SIZE
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.LightInfluence = 0

	local back = Instance.new("Frame")
	back.BorderSizePixel = 0
	back.BackgroundColor3 = BAR_BACK_COLOR
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = billboard
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Parent = back

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Parent = back

	local bar: Bar = { model = model, billboard = billboard, fill = fill }
	bars[model] = bar
	refresh(bar)
	-- These connections end when the minion is destroyed.
	model:GetAttributeChangedSignal("Health"):Connect(function()
		refresh(bar)
	end)
	billboard.Parent = model
end

for _, child in minionFolder:GetChildren() do
	if child:IsA("Model") then
		task.spawn(addBar, child)
	end
end
minionFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		addBar(child)
	end
end)
minionFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		bars[child] = nil
	end
end)

-- Recolor every bar if this player's team changes (e.g. when a match assigns teams).
player:GetAttributeChangedSignal("Team"):Connect(function()
	for _, bar in bars do
		refresh(bar)
	end
end)

-- Show bars only near your hero (measured from the hero, not the camera, so
-- the high MOBA camera does not hide bars of units you can target).
local function heroPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

task.spawn(function()
	while true do
		local origin = heroPosition()
		for _, bar in bars do
			local root = bar.model:FindFirstChild("HumanoidRootPart")
			if origin and root and root:IsA("BasePart") then
				local offset = root.Position - origin
				bar.billboard.Enabled = Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Display.HealthBarRange
			end
		end
		task.wait(VISIBILITY_CHECK_SECONDS)
	end
end)

-- Archer shots --------------------------------------------------------------

local restPoses: { [Motor6D]: CFrame } = {}
local armTweens: { [Motor6D]: Tween } = {}

local function moveArm(shoulder: Motor6D, pose: CFrame, seconds: number, style: Enum.EasingStyle)
	local active = armTweens[shoulder]
	if active then
		active:Cancel()
	end
	local tween = TweenService:Create(
		shoulder,
		TweenInfo.new(seconds, style, Enum.EasingDirection.Out),
		{ C0 = restPoses[shoulder] * pose }
	)
	armTweens[shoulder] = tween
	tween:Play()
end

local function playDraw(archer: Model, drawTime: number)
	local shoulder = archer:FindFirstChild("LeftShoulder", true)
	if not (shoulder and shoulder:IsA("Motor6D")) then
		return
	end
	if not restPoses[shoulder] then
		restPoses[shoulder] = shoulder.C0
		shoulder.Destroying:Connect(function()
			restPoses[shoulder] = nil
			armTweens[shoulder] = nil
		end)
	end
	moveArm(shoulder, REACH_POSE, drawTime * REACH_SHARE, Enum.EasingStyle.Quad)
	task.delay(drawTime * REACH_SHARE, function()
		if shoulder.Parent then
			moveArm(shoulder, PULL_POSE, drawTime * (1 - REACH_SHARE), Enum.EasingStyle.Sine)
		end
	end)
	task.delay(drawTime, function()
		if shoulder.Parent then
			moveArm(shoulder, CFrame.identity, RELEASE_TIME, Enum.EasingStyle.Back)
		end
	end)
end

-- Where an arrow flies to: a minion's body, or the middle of a structure's
-- lower half (structures are tall; this keeps arrows from arcing upward).
local function aimPoint(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position - Vector3.new(0, target.Size.Y / 4, 0)
	end
	local root = target:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Flies an arrow from the bow to the target, following the target if it moves.
local function flyArrow(archer: Model, target: Instance, flightTime: number)
	local hand = archer:FindFirstChild("RightHand")
	local targetPoint = aimPoint(target)
	if not (hand and hand:IsA("BasePart")) or not targetPoint then
		return
	end
	local start = hand.Position

	local arrow = Instance.new("Part")
	arrow.Name = "Arrow"
	arrow.Size = Vector3.new(0.15, 0.15, 2)
	arrow.Color = ARROW_COLOR
	arrow.Material = Enum.Material.SmoothPlastic
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.CastShadow = false
	arrow.CFrame = CFrame.lookAt(start, targetPoint)
	arrow.Parent = Workspace

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		targetPoint = aimPoint(target) or targetPoint -- keep the last point if the target is gone
		local alpha = math.min(elapsed / math.max(flightTime, 0.01), 1)
		local position = start:Lerp(targetPoint :: Vector3, alpha)
		if (targetPoint :: Vector3 - position).Magnitude > 0.01 then
			arrow.CFrame = CFrame.lookAt(position, targetPoint :: Vector3)
		end
		if alpha >= 1 then
			connection:Disconnect()
			arrow:Destroy()
		end
	end)
end

local function isShotTime(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_SHOT_TIME
end

shotEvent.OnClientEvent:Connect(function(archer: unknown, target: unknown, drawTime: unknown, flightTime: unknown)
	if not (typeof(archer) == "Instance" and archer:IsA("Model")) then
		return
	end
	if not (typeof(target) == "Instance" and (target:IsA("Model") or target:IsA("BasePart"))) then
		return
	end
	if not (isShotTime(drawTime) and isShotTime(flightTime)) then
		return
	end
	local draw, flight = drawTime :: number, flightTime :: number
	playDraw(archer, draw)
	task.delay(draw, function()
		-- An archer killed mid-draw never releases (the server agrees).
		if archer.Parent then
			flyArrow(archer, target, flight)
		end
	end)
end)
