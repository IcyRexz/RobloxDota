--!strict
-- Minion visuals drawn on each player's own screen:
--  * a thin health bar above every minion (green ally / red enemy, no name,
--    UI design system: docs/11_UI_DESIGN.md), shown within
--    Config.Display.HealthBarRange of your hero
--  * the archer's bow-draw pose and the flying arrow
--  * the zombie's hand swipe (arm rears up, claws down, body lunges in); the
--    Brute instead smashes down with both hands; the Ripper twists and
--    claws down with one hand, the other hand on its next attack
--  * the spitter's acid blob (lobbed onto a spot) and the green puddle it leaves
-- Display only. The server owns minion health and decides every hit; the arrow,
-- the swipe and the acid just show a hit the server has already scheduled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
-- Brute smash (owner 2026-10-22): both arms swing up overhead, then slam down
-- in front, using the owner's swing pattern: every frame, after the walk/idle
-- animation, a rotation is added to each shoulder's Transform
-- (JointPose.addRotation), so the animation cannot hide it. Angles and timing
-- in Config.Minion.BruteSmashLook; the hit delay comes from the server.
-- Ripper swipe (owner 2026-10-23), same pattern, hands taking turns: the
-- upper body twists back to the striking arm's side with that arm raised,
-- then the claw comes down as the body turns through the middle to the
-- other side, and it settles. Right hand (twisting left), then left hand
-- (twisting right), and so on.
-- Angles and timing in Config.Minion.RipperSwipeLook (the server lands each
-- claw from the same numbers).

local ACID_COLOR = Color3.fromRGB(50, 140, 35) -- a world effect; owner 2026-10-22: darker acid green (same as the spitter's mouth, Minions.server)
local ACID_ARC = 0.25 -- peak height of the blob's lob, as a share of its length
local ACID_MAX_RADIUS = 20 -- ignore acid messages with a bigger blast
-- Acid puddle (owner 2026-10-22): splats out to the blast size, stays, then fades.
local PUDDLE_SPLAT_TIME = 0.15
local PUDDLE_STAY = 2 -- seconds at full strength (owner 2026-10-22: was 4)
local PUDDLE_FADE = 1 -- seconds to fade away (was 2)
local PUDDLE_TRANSPARENCY = 0.25
local PUDDLE_THICKNESS = 0.05 -- studs (was 0.15)
-- Not round (owner 2026-10-22): a main splat plus a few smaller blots around
-- its edge, overlapping into a puddle outline. Shares of the blast radius.
local PUDDLE_MAIN = 0.7 -- main splat radius
local PUDDLE_BLOTS = 4 -- smaller blots around it
local PUDDLE_BLOT_SIZE = { 0.3, 0.5 } -- blot radius range
local PUDDLE_BLOT_REACH = { 0.35, 0.6 } -- how far from the centre each blot sits
local PUDDLE_PROBE = 20 -- studs above and below the landing point searched for the ground

local player = Players.LocalPlayer
local minionFolder = Workspace:WaitForChild("Minions")
local acidEvent = ReplicatedStorage:WaitForChild("ZombieAcid") :: RemoteEvent
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
-- Brute smashes in progress (see playBruteSmash).
type ArmSwing = { shoulders: { Instance }, started: number, raiseTime: number, slamTime: number }
local armSwings: { [Model]: ArmSwing } = {}
-- Ripper swipes in progress (see playRipperSwipe): the waist, the striking
-- shoulder and which way the body turns (1 toward its left, -1 its right).
type RipperSwipe = { waists: { Instance }, shoulders: { Instance }, turn: number, started: number }
local ripperSwipes: { [Model]: RipperSwipe } = {}
local loggedFirstSwipe = false

-- A removed minion's bar, poses and swipe count are forgotten (one cleanup for all).
minionFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		bars[child] = nil
		armSwings[child] = nil
		ripperSwipes[child] = nil
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

-- Smooth 0 -> 1 curve (slow start, slow finish).
local function ease(x: number): number
	return (1 - math.cos(math.clamp(x, 0, 1) * math.pi)) / 2
end


local function playBruteSmash(brute: Model, hitDelay: number)
	local shoulders: { Instance } = {}
	for _, name in { "LeftShoulder", "RightShoulder" } do
		for _, shoulder in JointPose.animated(brute, name) do
			table.insert(shoulders, shoulder)
		end
	end
	local raiseTime = hitDelay * Config.Minion.BruteSmashLook.raiseShare
	armSwings[brute] = {
		shoulders = shoulders,
		started = os.clock(),
		raiseTime = raiseTime,
		slamTime = hitDelay - raiseTime,
	}
end

-- The arms' extra angle (degrees) at time t into a smash, or nil once it is over.
local function smashAngle(swing: ArmSwing, t: number): number?
	local look = Config.Minion.BruteSmashLook
	local hitAt = swing.raiseTime + swing.slamTime
	if t < swing.raiseTime then
		return look.raiseAngle * ease(t / swing.raiseTime)
	elseif t < hitAt then
		return look.raiseAngle + (look.slamAngle - look.raiseAngle) * ease((t - swing.raiseTime) / swing.slamTime)
	elseif t < hitAt + look.recoverTime then
		return look.slamAngle * (1 - ease((t - hitAt) / look.recoverTime))
	end
	return nil
end

local function playRipperSwipe(ripper: Model)
	-- Hands take turns: right first.
	local count = (swipeCounts[ripper] or 0) + 1
	swipeCounts[ripper] = count
	local right = count % 2 == 1
	ripperSwipes[ripper] = {
		waists = JointPose.animated(ripper, "Waist"),
		shoulders = JointPose.animated(ripper, if right then "RightShoulder" else "LeftShoulder"),
		turn = if right then 1 else -1,
		started = os.clock(),
	}
end

-- A swipe's key poses, in degrees: { time, twist, arm lift }, for a right-hand
-- swipe (a left-hand one mirrors the twist). Twist turns about the torso's up
-- axis (positive turns toward the Ripper's left); lift raises the arm forward
-- and up (negative claws it down). The claw crosses the middle halfway
-- through the sweep, when the hit lands.
type SwipeKey = { number }
local function ripperKeys(): { SwipeKey }
	local look = Config.Minion.RipperSwipeLook
	local t = look.twist
	local sweepEnd = look.windup + look.sweep
	return {
		{ 0, 0, 0 },
		{ look.windup, -t, look.raiseAngle }, -- turned right, arm raised
		{ sweepEnd, t, -look.strikeAngle }, -- turned left, claw down across the middle
		{ sweepEnd + look.recover, 0, 0 },
	}
end
local RIPPER_KEYS = ripperKeys()

-- The swipe's pose at time t, or nil once it is over.
local function ripperPose(t: number): SwipeKey?
	for index = 2, #RIPPER_KEYS do
		local from, to = RIPPER_KEYS[index - 1], RIPPER_KEYS[index]
		if t < to[1] then
			local alpha = ease((t - from[1]) / (to[1] - from[1]))
			local pose = {}
			for column = 2, #from do
				pose[column] = from[column] + (to[column] - from[column]) * alpha
			end
			return pose
		end
	end
	return nil
end

local function rotateAll(joints: { Instance }, rotation: CFrame)
	for _, item in joints do
		if item.Parent then
			JointPose.addRotation(item, rotation)
		end
	end
end

RunService.PreSimulation:Connect(function()
	local now = os.clock()
	for ripper, swipe in ripperSwipes do
		local pose = ripperPose(now - swipe.started)
		if not pose or ripper.Parent ~= minionFolder then
			ripperSwipes[ripper] = nil
		else
			rotateAll(swipe.waists, CFrame.Angles(0, math.rad(pose[2] * swipe.turn), 0))
			rotateAll(swipe.shoulders, CFrame.Angles(math.rad(pose[3]), 0, 0))
		end
	end
	for brute, swing in armSwings do
		local t = now - swing.started
		local angle = smashAngle(swing, t)
		if not angle or brute.Parent ~= minionFolder then
			armSwings[brute] = nil
		else
			local rotation = CFrame.Angles(math.rad(angle), 0, 0)
			for _, shoulder in swing.shoulders do
				if shoulder.Parent then
					JointPose.addRotation(shoulder, rotation)
				end
			end
		end
	end
end)

swingEvent.OnClientEvent:Connect(function(zombie: unknown, hitDelay: unknown)
	if not (typeof(zombie) == "Instance" and zombie:IsA("Model") and zombie.Parent == minionFolder) then
		return
	end
	if not (type(hitDelay) == "number" and hitDelay == hitDelay and hitDelay > 0 and hitDelay <= MAX_SWING_TIME) then
		return
	end
	local kind = zombie:GetAttribute("MinionType")
	if kind == "Brute" then
		playBruteSmash(zombie, hitDelay)
	elseif kind == "Ripper" then
		playRipperSwipe(zombie)
	else
		playSwipe(zombie, hitDelay)
	end
end)

-- Spitter acid ----------------------------------------------------------------

-- A short-lived, non-colliding world part (the blob and its puddle).
local function effectPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = ACID_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- The puddle the blob leaves: a flat green disc as wide as the blast, which
-- splats out, stays a while and fades. Display only (the damage was dealt
-- once, when the blob landed).
-- The real ground under a point: the server's landing height comes from the
-- terrain formula, but the terrain is built from voxels, so its surface can be
-- higher and would hide the puddle. Only the terrain and the base floor count
-- (not trees, rocks, units or players).
local function groundUnder(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local ground: { Instance } = { Workspace.Terrain }
	local arena = Workspace:FindFirstChild("Arena")
	local floor = arena and arena:FindFirstChild("BaseFloor", true)
	if floor then
		table.insert(ground, floor)
	end
	params.FilterDescendantsInstances = ground
	local hit = Workspace:Raycast(point + Vector3.new(0, PUDDLE_PROBE, 0), Vector3.new(0, -PUDDLE_PROBE * 2, 0), params)
	return if hit then hit.Position else point
end

-- One flat disc of the puddle on the ground at `centre`, splatting out to
-- `size` radius, then fading after PUDDLE_STAY.
local function puddleBlot(centre: Vector3, size: number, height: number)
	local blot = effectPart("AcidPuddle", Vector3.new(PUDDLE_THICKNESS, 0.5, 0.5))
	blot.Shape = Enum.PartType.Cylinder
	blot.Material = Enum.Material.SmoothPlastic -- flat, not glowing, so it reads as a darker puddle
	blot.Transparency = PUDDLE_TRANSPARENCY
	-- Each blot a hair higher than the last so overlaps do not flicker.
	blot.CFrame = CFrame.new(groundUnder(centre) + Vector3.new(0, 0.05 + height, 0)) * CFrame.Angles(0, 0, math.rad(90))
	blot.Parent = Workspace
	TweenService:Create(blot, TweenInfo.new(PUDDLE_SPLAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(PUDDLE_THICKNESS, size * 2, size * 2),
	}):Play()
	local fade = TweenService:Create(blot, TweenInfo.new(PUDDLE_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, PUDDLE_STAY), {
		Transparency = 1,
	})
	fade.Completed:Connect(function()
		blot:Destroy()
	end)
	fade:Play()
end

local function between(range: { number }): number
	return range[1] + math.random() * (range[2] - range[1])
end

local function showPuddle(landing: Vector3, radius: number)
	puddleBlot(landing, radius * PUDDLE_MAIN, 0)
	local turn = math.random() * 2 * math.pi
	for index = 1, PUDDLE_BLOTS do
		-- Spread round the edge, each at a slightly random angle.
		local angle = turn + (index + math.random() * 0.6) / PUDDLE_BLOTS * 2 * math.pi
		local reach = radius * between(PUDDLE_BLOT_REACH)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
		puddleBlot(landing + offset, radius * between(PUDDLE_BLOT_SIZE), index * 0.005)
	end
end

-- Lobs a blob from `from` to `landing` in an arc over `flightTime`, then it
-- leaves a puddle there.
local function flyAcid(from: Vector3, landing: Vector3, flightTime: number, radius: number)
	local blob = effectPart("AcidBlob", Vector3.new(0.8, 0.8, 0.8))
	blob.CFrame = CFrame.new(from)
	blob.Parent = Workspace
	local height = (landing - from).Magnitude * ACID_ARC
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		local alpha = math.min(elapsed / math.max(flightTime, 0.01), 1)
		blob.CFrame = CFrame.new(from:Lerp(landing, alpha) + Vector3.new(0, height * 4 * alpha * (1 - alpha), 0))
		if alpha >= 1 then
			connection:Disconnect()
			blob:Destroy()
			showPuddle(landing, radius)
		end
	end)
end

local function isFinitePoint(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e5
end

acidEvent.OnClientEvent:Connect(function(spitter: unknown, from: unknown, landing: unknown, flightTime: unknown, radius: unknown)
	if not (typeof(spitter) == "Instance" and spitter:IsA("Model")) then
		return
	end
	if not (isFinitePoint(from) and isFinitePoint(landing) and isShotTime(flightTime)) then
		return
	end
	if not (type(radius) == "number" and radius == radius and radius >= 0 and radius <= ACID_MAX_RADIUS) then
		return
	end
	flyAcid(from :: Vector3, landing :: Vector3, flightTime :: number, radius :: number)
end)
