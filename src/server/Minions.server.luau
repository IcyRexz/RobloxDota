--!strict
-- Spawns minion waves in front of each core and walks them down the lane.
-- Step 1 of the minion system: spawning, walking, stopping at enemies, despawning.
-- Fighting (damage, targets, towers) comes after the match/damage code exists.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

type MinionStats = {
	kind: string,
	maxHealth: number,
	damage: number,
	attackRange: number, -- stops this close to an enemy
	aggroRange: number, -- notices enemies this close
	speed: number,
}

local MELEE: MinionStats =
	{ kind = "Melee", maxHealth = 120, damage = 12, attackRange = 5, aggroRange = 8, speed = 8 }
local ARCHER: MinionStats =
	{ kind = "Archer", maxHealth = 80, damage = 10, attackRange = 16, aggroRange = 16, speed = 8 }
local WAVE: { MinionStats } = { MELEE, MELEE, MELEE, MELEE, ARCHER }

local FIRST_WAVE_DELAY = 3
local WAVE_INTERVAL = 25
local MAX_ALIVE = 30 -- across both teams
local LIFETIME = 60
local TICK_SECONDS = 0.2
local WAYPOINT_REACHED = 2
-- Once holding position, an enemy must back off this much farther before the
-- minion moves again. Stops minions flickering between walking and standing.
local HOLD_SLACK = 1.5
-- Each wave member gets its own formation spot: which side of the structures it
-- passes (-1 north, +1 south) and which file (0 inner, 1 outer). The archer
-- walks between the two south files.
local FORMATION: { { side: number, file: number } } = {
	{ side = -1, file = 0 },
	{ side = 1, file = 0 },
	{ side = -1, file = 1 },
	{ side = 1, file = 1 },
	{ side = 1, file = 0.5 },
}
local COLLISION_GROUP = "Minions" -- minions pass through each other instead of shoving

local TEAM_COLORS: { [string]: Color3 } = {
	Blue = Color3.new(0.2, 0.45, 0.9),
	Red = Color3.new(0.85, 0.2, 0.2),
}

-- Roblox's own default R15 animations (free for any game). "Tool hold" raises
-- the right arm forward, the way players hold a sword.
local WALK_ANIMATION = "rbxassetid://507777826"
local IDLE_ANIMATION = "rbxassetid://507766388"
local TOOL_HOLD_ANIMATION = "rbxassetid://507768375"
-- The walk animation is made for speed 16; scale it so feet match the real speed.
local WALK_ANIMATION_BASE_SPEED = 16

-- Lane route for Blue, which walks toward +X. Red uses the same points mirrored.
-- side/file come from FORMATION. Structures span z -5..5, walls sit at z +-18.
-- Layout reference: barracks x -56, own tower x -40, enemy tower front face x 36.
local function route(team: string, side: number, file: number, attackRange: number): { Vector3 }
	local direction = if team == "Blue" then 1 else -1
	local passZ = side * (8 + 3 * file) -- clear of the structures
	local laneZ = side * (1.5 + 3 * file) -- tighter formation in the open lane
	local points = {
		Vector3.new(-62, 0, passZ), -- step sideways, between core and barracks
		Vector3.new(-34, 0, passZ), -- walk past own barracks and tower
		Vector3.new(-28, 0, laneZ), -- move back toward the middle
		Vector3.new(36 - attackRange - 1, 0, laneZ), -- stop in front of the enemy tower
	}
	for i, point in points do
		points[i] = Vector3.new(point.X * direction, point.Y, point.Z)
	end
	return points
end

type Minion = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	team: string,
	stats: MinionStats,
	waypoints: { Vector3 },
	nextWaypoint: number,
	expiresAt: number,
	walkTrack: AnimationTrack,
	idleTrack: AnimationTrack,
	holding: boolean,
}

local arena = Workspace:WaitForChild("Arena")
local minionFolder = Instance.new("Folder")
minionFolder.Name = "Minions"
minionFolder.Parent = Workspace

local alive: { Minion } = {}

PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

-- Weapons: plain blocks welded to a hand. Decoration only.
local function addWeaponPart(hand: BasePart, size: Vector3, color: Color3, offset: CFrame)
	local part = Instance.new("Part")
	part.Name = "Weapon"
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = hand.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = hand.Parent
end

-- Both weapons sit in the right hand, which the tool-hold pose raises forward.
-- In that pose the hand's -Z axis points up and its -Y axis points forward.
local function addSword(body: Model)
	local hand = body:FindFirstChild("RightHand")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local steel = Color3.fromRGB(190, 195, 200)
	local leather = Color3.fromRGB(90, 70, 40)
	addWeaponPart(hand, Vector3.new(0.18, 0.18, 0.6), leather, CFrame.new(0, -0.15, 0.1)) -- handle
	addWeaponPart(hand, Vector3.new(1, 0.2, 0.15), leather, CFrame.new(0, -0.15, -0.3)) -- crossguard
	addWeaponPart(hand, Vector3.new(0.12, 0.3, 2.6), steel, CFrame.new(0, -0.15, -1.65)) -- blade, pointing up
end

local function addBow(body: Model)
	local hand = body:FindFirstChild("RightHand")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local wood = Color3.fromRGB(120, 80, 40)
	local bend = math.rad(20) -- limb tips lean back toward the archer
	addWeaponPart(hand, Vector3.new(0.2, 0.2, 0.8), wood, CFrame.new(0, -0.2, 0)) -- grip, held upright
	addWeaponPart(hand, Vector3.new(0.15, 0.15, 1.3), wood, CFrame.new(0, 0.02, -1.01) * CFrame.Angles(bend, 0, 0)) -- upper limb
	addWeaponPart(hand, Vector3.new(0.15, 0.15, 1.3), wood, CFrame.new(0, 0.02, 1.01) * CFrame.Angles(-bend, 0, 0)) -- lower limb
	addWeaponPart(hand, Vector3.new(0.05, 0.05, 3.24), Color3.fromRGB(230, 230, 230), CFrame.new(0, 0.26, 0)) -- string
end

-- One finished body per team and type, built once and cloned for every spawn.
local function buildTemplate(team: string, stats: MinionStats): Model
	local color = TEAM_COLORS[team]
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color
	description.RightLegColor = color
	local body = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	body.Name = team .. stats.kind
	-- Remove any built-in scripts (such as the default Animate script) so only
	-- this file controls the minion's animations.
	for _, item in body:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	if stats.kind == "Archer" then
		addBow(body)
	else
		addSword(body)
	end

	local humanoid = body:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = stats.speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

	for _, item in body:GetDescendants() do
		if item:IsA("BasePart") then
			item.CollisionGroup = COLLISION_GROUP
		end
	end

	body:SetAttribute("Kind", "Minion")
	body:SetAttribute("MinionType", stats.kind)
	body:SetAttribute("Team", team)
	body:SetAttribute("MaxHealth", stats.maxHealth)
	body:SetAttribute("Health", stats.maxHealth)
	return body
end

local templates: { [string]: Model } = {}
for team in TEAM_COLORS do
	for _, stats in { MELEE, ARCHER } do
		templates[team .. stats.kind] = buildTemplate(team, stats)
	end
end

local function loadTrack(humanoid: Humanoid, animationId: string): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local track = (animator :: Animator):LoadAnimation(animation)
	track.Looped = true
	return track
end

local function findSpawn(team: string): BasePart?
	for _, item in arena:GetDescendants() do
		if item:IsA("BasePart") and item:GetAttribute("Kind") == "MinionSpawn" and item:GetAttribute("Team") == team then
			return item
		end
	end
	return nil
end

local spawnPoints: { [string]: BasePart? } = { Blue = findSpawn("Blue"), Red = findSpawn("Red") }

local function spawnMinion(team: string, stats: MinionStats, index: number)
	local spawnPoint = spawnPoints[team]
	if not spawnPoint then
		return
	end
	local slot = FORMATION[index]
	local direction = if team == "Blue" then 1 else -1
	local behind = if stats.kind == "Archer" then -1.5 * direction else 0 -- archer starts at the back
	local start = spawnPoint.Position + Vector3.new(behind, 3, slot.side * (1.5 + 2.5 * slot.file))
	local facing = start + Vector3.new(direction, 0, 0)

	local model = templates[team .. stats.kind]:Clone()
	model:PivotTo(CFrame.lookAt(start, facing))
	model.Parent = minionFolder
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(nil) -- the server moves minions, never a player's device

	local minion: Minion = {
		model = model,
		humanoid = humanoid,
		root = root,
		team = team,
		stats = stats,
		waypoints = route(team, slot.side, slot.file, stats.attackRange),
		nextWaypoint = 1,
		expiresAt = os.clock() + LIFETIME,
		walkTrack = loadTrack(humanoid, WALK_ANIMATION),
		idleTrack = loadTrack(humanoid, IDLE_ANIMATION),
		holding = false,
	}
	minion.idleTrack:Play()
	loadTrack(humanoid, TOOL_HOLD_ANIMATION):Play()
	table.insert(alive, minion)
end

-- Spawns one wave for both teams, never exceeding MAX_ALIVE. If there is not
-- room for everyone, the team that goes first alternates each wave.
local firstTeam = "Blue"
local function spawnWave()
	local order: { string } = if firstTeam == "Blue" then { "Blue", "Red" } else { "Red", "Blue" }
	firstTeam = order[2]
	for index, stats in WAVE do
		for _, team in order do
			if #alive >= MAX_ALIVE then
				return
			end
			spawnMinion(team, stats, index)
		end
	end
end

local function planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function nearestEnemy(minion: Minion): Minion?
	local best: Minion? = nil
	local bestDistance = minion.stats.aggroRange
	for _, other in alive do
		if other.team ~= minion.team then
			local distance = planarDistance(other.root.Position, minion.root.Position)
			if distance <= bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function setWalking(minion: Minion, walking: boolean)
	if walking and not minion.walkTrack.IsPlaying then
		minion.idleTrack:Stop(0.2)
		minion.walkTrack:Play(0.2, 1, minion.stats.speed / WALK_ANIMATION_BASE_SPEED)
	elseif not walking and not minion.idleTrack.IsPlaying then
		minion.walkTrack:Stop(0.2)
		minion.idleTrack:Play(0.2)
	end
end

local function updateMinion(minion: Minion)
	local position = minion.root.Position
	local enemy = nearestEnemy(minion)
	local target: Vector3? = nil
	if enemy then
		-- Close in until within attack range, then hold position (fighting comes later).
		local slack = if minion.holding then HOLD_SLACK else 0
		minion.holding = planarDistance(enemy.root.Position, position) <= minion.stats.attackRange + slack
		if not minion.holding then
			target = enemy.root.Position
		end
	else
		minion.holding = false
		local waypoint = minion.waypoints[minion.nextWaypoint]
		if waypoint and planarDistance(waypoint, position) < WAYPOINT_REACHED then
			minion.nextWaypoint += 1
			waypoint = minion.waypoints[minion.nextWaypoint]
		end
		target = waypoint
	end

	if target then
		minion.humanoid:MoveTo(target)
	else
		minion.humanoid:MoveTo(position)
	end
	setWalking(minion, target ~= nil)
end

local function updateAll()
	local now = os.clock()
	for i = #alive, 1, -1 do
		local minion = alive[i]
		if now >= minion.expiresAt or minion.model.Parent == nil then
			minion.model:Destroy()
			table.remove(alive, i)
		end
	end
	for _, minion in alive do
		updateMinion(minion)
	end
end

task.spawn(function()
	task.wait(FIRST_WAVE_DELAY)
	while true do
		spawnWave()
		task.wait(WAVE_INTERVAL)
	end
end)

while true do
	updateAll()
	task.wait(TICK_SECONDS)
end
