--!strict
-- Minion visuals drawn on each player's own screen:
--  * a thin health bar above every minion (green ally / red enemy, no name,
--    UI design system: docs/11_UI_DESIGN.md), shown within
--    Config.Display.HealthBarRange of your hero
--  * the archer's bow-draw pose and the flying arrow
--  * the zombie's hand swipe (arm rears up, claws down, body lunges in)
-- Display only. The server owns minion health and decides every hit; the arrow
-- and the swipe just show a hit the server has already scheduled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local UiTheme = require(ReplicatedStorage.Shared.UiTheme)

local VISIBILITY_CHECK_SECONDS = 0.2
local BAR_SIZE = UDim2.fromOffset(36, UiTheme.Bar.Unit) -- on-screen pixels
-- Players are always on our side; used until the server sets the attribute.
local DEFAULT_TEAM = Config.Teams.Defenders

local MAX_SHOT_TIME = 2 -- ignore shot messages with longer draw/flight times
local ARROW_COLOR = Color3.fromRGB(120, 80, 40)
-- Left arm, relative to its resting shoulder: reach forward to the string held
-- in the right hand, then pull back toward the chest before release.
local REACH_POSE = CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(math.rad(95), 0, 0)
local PULL_POSE = CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(math.rad(70), 0, 0)
local REACH_SHARE = 0.35 -- part of the draw time spent reaching
local RELEASE_TIME = 0.2 -- arm drops back to rest after letting go

local MAX_SWING_TIME = 1 -- ignore swing messages with a longer hit delay
-- Zombie swipe, relative to the resting pose (arms stretched forward):
-- the arm rears up over the head while the body leans back, then claws down
-- and inward across the body while the body lunges forward, then settles.
local SWIPE_RAISE_POSE = CFrame.Angles(math.rad(75), 0, 0)
local SWIPE_STRIKE_ANGLE = math.rad(-85)
local SWIPE_STRIKE_TILT = math.rad(35) -- inward, toward the body's middle
local LEAN_BACK_POSE = CFrame.Angles(math.rad(10), 0, 0)
local LUNGE_POSE = CFrame.Angles(math.rad(-25), 0, 0)
local SWIPE_RAISE_SHARE = 0.7 -- part of the hit delay spent rearing up; the rest is the strike
local SWIPE_RECOVER_TIME = 0.3

local player = Players.LocalPlayer
local minionFolder = Workspace:WaitForChild("Minions")
local shotEvent = ReplicatedStorage:WaitForChild("MinionShot") :: RemoteEvent
local swingEvent = ReplicatedStorage:WaitForChild("MinionSwing") :: RemoteEvent

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
	bar.fill.BackgroundColor3 = if isAlly then UiTheme.Ally else UiTheme.Enemy
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

	local parts = UiTheme.bar(billboard, UiTheme.Bar.Unit, UiTheme.Ally)
	parts.track.Size = UDim2.fromScale(1, 1)

	local bar: Bar = { model = model, billboard = billboard, fill = parts.fill }
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

-- Recolor every bar if this player's team changes (e.g. when a match assigns teams).
player:GetAttributeChangedSignal("Team"):Connect(function()
	for _, bar in bars do
		refresh(bar)
	end
end)

-- Show bars only near your hero (flat distance from the hero).
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

-- Joint poses (archer draw, zombie swipe) ---------------------------------------
-- Poses are applied on this client only, on top of each joint's resting pose,
-- through JointPose (works with Motor6D and AnimationConstraint rigs).

type PosedJoint = { joint: JointPose.Joint, tweens: { Tween } }
local posedJoints: { [Model]: { [string]: PosedJoint } } = {}
local warnedMissing = false

-- Finds a joint and remembers its resting pose the first time it is used.
local function joint(model: Model, name: string): PosedJoint?
	local byName = posedJoints[model]
	if not byName then
		byName = {}
		posedJoints[model] = byName
	end
	local posed = byName[name]
	if not posed then
		local found = JointPose.find(model, name)
		if not found then
			if not warnedMissing then
				warnedMissing = true
				warn(`[MinionVisuals] no joint named {name} in {model.Name}; poses will not show`)
			end
			return nil
		end
		posed = { joint = found, tweens = {} }
		byName[name] = posed
	end
	return posed
end

local function moveArm(posed: PosedJoint, pose: CFrame, seconds: number, style: Enum.EasingStyle)
	for _, tween in posed.tweens do
		tween:Cancel()
	end
	posed.tweens = JointPose.tween(posed.joint, pose, TweenInfo.new(seconds, style, Enum.EasingDirection.Out))
end

-- Archer shots --------------------------------------------------------------

local function playDraw(archer: Model, drawTime: number)
	local shoulder = joint(archer, "LeftShoulder")
	if not shoulder then
		return
	end
	moveArm(shoulder, REACH_POSE, drawTime * REACH_SHARE, Enum.EasingStyle.Quad)
	task.delay(drawTime * REACH_SHARE, function()
		if archer.Parent then
			moveArm(shoulder, PULL_POSE, drawTime * (1 - REACH_SHARE), Enum.EasingStyle.Sine)
		end
	end)
	task.delay(drawTime, function()
		if archer.Parent then
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

-- Zombie swipes --------------------------------------------------------------

local swipeCounts: { [Model]: number } = {}
local loggedFirstSwipe = false

-- A removed minion's bar, poses and swipe count are forgotten (one cleanup for all).
minionFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		bars[child] = nil
		posedJoints[child] = nil
		swipeCounts[child] = nil
	end
end)

local function playSwipe(zombie: Model, hitDelay: number)
	-- Arms take turns.
	local count = (swipeCounts[zombie] or 0) + 1
	swipeCounts[zombie] = count
	local side = if count % 2 == 1 then "Right" else "Left"
	local shoulder = joint(zombie, side .. "Shoulder")
	local waist = joint(zombie, "Waist")
	if not shoulder then
		return
	end
	if not loggedFirstSwipe then
		-- Development log: proves swipe messages arrive and which joints are posed.
		loggedFirstSwipe = true
		print(`[MinionVisuals] first zombie swipe: shoulder joint system {shoulder.joint.system}, waist {if waist then waist.joint.system else "none"}`)
	end
	local inward = if side == "Right" then 1 else -1
	local raiseTime = hitDelay * SWIPE_RAISE_SHARE
	local strikeTime = hitDelay - raiseTime

	moveArm(shoulder, SWIPE_RAISE_POSE, raiseTime, Enum.EasingStyle.Quad)
	if waist then
		moveArm(waist, LEAN_BACK_POSE, raiseTime, Enum.EasingStyle.Quad)
	end
	task.delay(raiseTime, function()
		if zombie.Parent ~= minionFolder then
			return
		end
		moveArm(shoulder, CFrame.Angles(SWIPE_STRIKE_ANGLE, 0, SWIPE_STRIKE_TILT * inward), strikeTime, Enum.EasingStyle.Quart)
		if waist then
			moveArm(waist, LUNGE_POSE, strikeTime, Enum.EasingStyle.Quart)
		end
	end)
	task.delay(hitDelay, function()
		if zombie.Parent ~= minionFolder then
			return
		end
		moveArm(shoulder, CFrame.identity, SWIPE_RECOVER_TIME, Enum.EasingStyle.Sine)
		if waist then
			moveArm(waist, CFrame.identity, SWIPE_RECOVER_TIME, Enum.EasingStyle.Sine)
		end
	end)
end

swingEvent.OnClientEvent:Connect(function(zombie: unknown, hitDelay: unknown)
	if not (typeof(zombie) == "Instance" and zombie:IsA("Model") and zombie.Parent == minionFolder) then
		return
	end
	if not (type(hitDelay) == "number" and hitDelay == hitDelay and hitDelay > 0 and hitDelay <= MAX_SWING_TIME) then
		return
	end
	playSwipe(zombie, hitDelay)
end)
