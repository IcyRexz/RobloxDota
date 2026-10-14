--!strict
-- Spawns minion waves in front of each core and walks them down the lane.
-- So far: spawning, walking, fighting enemy minions, heroes and structures,
-- dying, despawning, and the inhibitor (barracks) bonus. Leash comes later.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

type MinionStats = Config.MinionStats

local MinionConfig = Config.Minion

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
local SLASH_ANIMATION = "rbxassetid://522635514" -- default "tool slash" swing, melee only
-- The walk animation is made for speed 16; scale it so feet match the real speed.
local WALK_ANIMATION_BASE_SPEED = 16

-- Lane route for Blue, which walks toward +X. Red uses the same points mirrored.
-- side/file come from FORMATION. Structures span z -5..5, walls sit at z +-18.
-- Layout reference: barracks x -56, own tower x -40, enemy tower x 36..44,
-- enemy barracks x 52..60, enemy core x 67..77. Enemy structures are fought
-- when they come into range (see chooseTarget); once one falls it becomes a
-- ruin minions walk through, and the route carries on to the next.
local function route(team: string, side: number, file: number): { Vector3 }
	local direction = if team == "Blue" then 1 else -1
	local passZ = side * (8 + 3 * file) -- clear of the structures
	local laneZ = side * (1.5 + 3 * file) -- tighter formation in the open lane
	local points = {
		Vector3.new(-62, 0, passZ), -- step sideways, between core and barracks
		Vector3.new(-34, 0, passZ), -- walk past own barracks and tower
		Vector3.new(-28, 0, laneZ), -- move back toward the middle
		Vector3.new(30, 0, laneZ), -- up to the enemy tower
		Vector3.new(34, 0, passZ), -- step sideways around it
		Vector3.new(62, 0, passZ), -- past the enemy tower and barracks
		Vector3.new(62, 0, laneZ), -- in front of the enemy core
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
	slashTrack: AnimationTrack?,
	turn: AlignOrientation,
	-- A structure this minion has started hitting; it keeps hitting it until it
	-- falls (structure lock), even if enemy minions arrive.
	structure: BasePart?,
	-- An enemy that drew this minion's aggro: an enemy minion that hit it, or an
	-- enemy hero that hit one of its heroes. It fights back (see chooseTarget).
	attacker: Model?,
	holding: boolean,
	nextAttackAt: number,
}

local arena = Workspace:WaitForChild("Arena")
local minionFolder = Instance.new("Folder")
minionFolder.Name = "Minions"
minionFolder.Parent = Workspace

local alive: { Minion } = {}
local byModel: { [Instance]: Minion } = {}

-- Tells every client to show an archer's shot: (archer, target, drawTime, flightTime).
-- Server -> client only; the server never listens to it.
local shotEvent = Instance.new("RemoteEvent")
shotEvent.Name = "MinionShot"
shotEvent.Parent = ReplicatedStorage

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

	-- Turning: the Humanoid would snap to face where it walks, so that is switched
	-- off and an AlignOrientation turns the body at most TurnRate degrees/second.
	humanoid.AutoRotate = false
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart
	local turnAttachment = Instance.new("Attachment")
	turnAttachment.Name = "TurnAttachment"
	turnAttachment.Parent = root
	local turn = Instance.new("AlignOrientation")
	turn.Name = "Turn"
	turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turn.Attachment0 = turnAttachment
	turn.MaxTorque = math.huge
	turn.MaxAngularVelocity = math.rad(MinionConfig.TurnRate)
	turn.Responsiveness = 200
	turn.Parent = root

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
	body:ScaleTo(MinionConfig.Scale) -- smaller than a hero
	return body
end

local templates: { [string]: Model } = {}
for team in TEAM_COLORS do
	for _, stats in { MinionConfig.Melee, MinionConfig.Archer } do
		templates[team .. stats.kind] = buildTemplate(team, stats)
	end
end

local function loadTrack(humanoid: Humanoid, animationId: string, looped: boolean): AnimationTrack
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local track = (animator :: Animator):LoadAnimation(animation)
	track.Looped = looped
	if not looped then
		track.Priority = Enum.AnimationPriority.Action -- plays over walk/idle/hold
	end
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

-- Teams that destroyed the enemy barracks: their later minions are stronger.
local empowered: { [string]: boolean } = {}
CombatService.Died:Connect(function(target: Instance, _killer: Instance, killerTeam: string)
	if target:GetAttribute("Kind") == "Barracks" and not empowered[killerTeam] then
		empowered[killerTeam] = true
		print(`[Minions] {killerTeam} destroyed the enemy barracks: their new minions get +{MinionConfig.BarracksBonus * 100}%`)
	end
end)

-- Health and damage bonus for a team's next spawns (both bonuses add up).
local function strengthOf(team: string): number
	local bonus = MinionConfig.TestTeamBonus[team] or 0
	if empowered[team] then
		bonus += MinionConfig.BarracksBonus
	end
	return 1 + bonus
end

local function scaledStats(base: MinionStats, multiplier: number): MinionStats
	if multiplier == 1 then
		return base
	end
	local stats = table.clone(base)
	stats.maxHealth = math.round(base.maxHealth * multiplier)
	stats.damage = math.round(base.damage * multiplier)
	return table.freeze(stats)
end

local function spawnMinion(team: string, baseStats: MinionStats, index: number)
	local spawnPoint = spawnPoints[team]
	if not spawnPoint then
		return
	end
	local stats = scaledStats(baseStats, strengthOf(team))
	local slot = FORMATION[index]
	local direction = if team == "Blue" then 1 else -1
	local behind = if stats.kind == "Archer" then -1.5 * direction else 0 -- archer starts at the back
	local start = spawnPoint.Position + Vector3.new(behind, 3, slot.side * (1.5 + 2.5 * slot.file))
	local facing = start + Vector3.new(direction, 0, 0)

	local model = templates[team .. stats.kind]:Clone()
	model:PivotTo(CFrame.lookAt(start, facing))
	model:SetAttribute("MaxHealth", stats.maxHealth)
	model:SetAttribute("Health", stats.maxHealth)
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
		waypoints = route(team, slot.side, slot.file),
		nextWaypoint = 1,
		expiresAt = os.clock() + MinionConfig.Lifetime,
		walkTrack = loadTrack(humanoid, WALK_ANIMATION, true),
		idleTrack = loadTrack(humanoid, IDLE_ANIMATION, true),
		slashTrack = if stats.kind == "Melee" then loadTrack(humanoid, SLASH_ANIMATION, false) else nil,
		turn = root:FindFirstChild("Turn") :: AlignOrientation,
		structure = nil,
		attacker = nil,
		holding = false,
		nextAttackAt = 0,
	}
	minion.turn.CFrame = root.CFrame.Rotation
	minion.idleTrack:Play()
	loadTrack(humanoid, TOOL_HOLD_ANIMATION, true):Play()
	table.insert(alive, minion)
	byModel[model] = minion
end

-- Spawns one wave for both teams, never exceeding the minion cap. If there is not
-- room for everyone, the team that goes first alternates each wave.
local firstTeam = "Blue"
local function spawnWave()
	local order: { string } = if firstTeam == "Blue" then { "Blue", "Red" } else { "Red", "Blue" }
	firstTeam = order[2]
	for index, stats in MinionConfig.Wave do
		for _, team in order do
			if #alive >= MinionConfig.MaxAlive then
				return
			end
			spawnMinion(team, stats, index)
		end
	end
end

local function planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Aggro, breaking any structure lock:
--  * a minion hit by an enemy minion fights back
--  * a hero hit by an enemy hero: that hero's minions within RetaliateRange of
--    the attacker turn on the attacker (MOBA "don't hit heroes near minions")
CombatService.Damaged:Connect(function(target: Instance, attacker: Instance)
	if not attacker:IsA("Model") then
		return
	end
	local victim = byModel[target]
	local enemy = byModel[attacker]
	if victim and enemy and enemy.team ~= victim.team then
		victim.attacker = enemy.model
		victim.structure = nil
		return
	end
	local heroTeam = target:GetAttribute("Team")
	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
	if
		target:GetAttribute("Kind") == "Hero"
		and attacker:GetAttribute("Kind") == "Hero"
		and attacker:GetAttribute("Team") ~= heroTeam
		and attackerRoot
		and attackerRoot:IsA("BasePart")
	then
		for _, minion in alive do
			if
				minion.team == heroTeam
				and planarDistance(minion.root.Position, attackerRoot.Position) <= MinionConfig.RetaliateRange
			then
				minion.attacker = attacker
				minion.structure = nil
			end
		end
	end
end)

-- Every tower, barracks and core, found once from the map.
local structures: { BasePart } = {}
for _, item in arena:GetDescendants() do
	local kind = item:GetAttribute("Kind")
	if item:IsA("BasePart") and (kind == "Tower" or kind == "Barracks" or kind == "Core") then
		table.insert(structures, item)
	end
end

-- The point of a structure's footprint closest to a position (at ground level).
-- Minions measure range to the structure's side, not its centre.
local function closestPointOn(structure: BasePart, position: Vector3): Vector3
	local centre, half = structure.Position, structure.Size / 2
	return Vector3.new(
		math.clamp(position.X, centre.X - half.X, centre.X + half.X),
		position.Y,
		math.clamp(position.Z, centre.Z - half.Z, centre.Z + half.Z)
	)
end

local function canHitStructure(minion: Minion, structure: BasePart): boolean
	return structure:GetAttribute("Team") ~= minion.team
		and CombatService.isAlive(structure)
		and not CombatService.isLocked(structure)
end

-- What this minion fights, and the point it walks to and faces:
--  1. the structure it is already hitting, until that falls (structure lock)
--  0. an enemy that drew its aggro (see the Damaged handler), while within
--     RetaliateRange: it drops whatever it was doing, even a structure
--  2. the nearest enemy minion within aggro range
--  3. the nearest enemy hero within aggro range
--  4. the nearest enemy structure within aggro range that can take damage
-- Locked structures are walked past. Since minions walk down the lane, they
-- naturally meet the tower, then the barracks, then the core.
local function chooseTarget(minion: Minion): (Instance?, Vector3)
	local position = minion.root.Position
	local attacker = minion.attacker
	local attackerRoot = attacker and attacker:FindFirstChild("HumanoidRootPart")
	if
		attacker
		and attackerRoot
		and attackerRoot:IsA("BasePart")
		and CombatService.isAlive(attacker)
		and planarDistance(attackerRoot.Position, position) <= MinionConfig.RetaliateRange
	then
		return attacker, attackerRoot.Position
	end
	minion.attacker = nil

	local locked = minion.structure
	if locked and canHitStructure(minion, locked) then
		return locked, closestPointOn(locked, position)
	end
	minion.structure = nil

	local best: Instance? = nil
	local bestPoint = position
	local bestDistance = minion.stats.aggroRange
	for _, other in alive do
		if other.team ~= minion.team and CombatService.isAlive(other.model) then
			local distance = planarDistance(other.root.Position, position)
			if distance <= bestDistance then
				best, bestPoint, bestDistance = other.model, other.root.Position, distance
			end
		end
	end
	if best then
		return best, bestPoint
	end

	for _, player in Players:GetPlayers() do
		local hero = player.Character
		local heroRoot = hero and hero:FindFirstChild("HumanoidRootPart")
		if
			hero
			and heroRoot
			and heroRoot:IsA("BasePart")
			and hero:GetAttribute("Kind") == "Hero"
			and typeof(hero:GetAttribute("Team")) == "string"
			and hero:GetAttribute("Team") ~= minion.team
			and CombatService.isAlive(hero)
		then
			local distance = planarDistance(heroRoot.Position, position)
			if distance <= bestDistance then
				best, bestPoint, bestDistance = hero, heroRoot.Position, distance
			end
		end
	end
	if best then
		return best, bestPoint
	end

	for _, structure in structures do
		if canHitStructure(minion, structure) then
			local point = closestPointOn(structure, position)
			local distance = planarDistance(point, position)
			if distance <= bestDistance then
				best, bestPoint, bestDistance = structure, point, distance
			end
		end
	end
	return best, bestPoint
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

-- Sets the direction the minion turns toward (at its turn rate, flat on the ground).
local function faceToward(minion: Minion, point: Vector3)
	local offset = Vector3.new(point.X - minion.root.Position.X, 0, point.Z - minion.root.Position.Z)
	if offset.Magnitude > 0.1 then
		minion.turn.CFrame = CFrame.lookAt(Vector3.zero, offset)
	end
end

-- Hits the target (an enemy minion or structure) at aimPoint. The server decides
-- the hit; the swing animation is only for show. The minion is already turning
-- to face the target (see updateMinion).
local function attack(minion: Minion, target: Instance, aimPoint: Vector3, now: number)
	local position = minion.root.Position
	minion.nextAttackAt = now + minion.stats.attackInterval
	if target:IsA("BasePart") then
		minion.structure = target -- structure lock: keep hitting it until it falls
	end

	if minion.stats.kind ~= "Archer" then
		CombatService.applyDamage(target, minion.stats.damage, minion.model, minion.team)
		if minion.slashTrack then
			minion.slashTrack:Play(0.05)
		end
		return
	end

	-- Archer: draw, release, and the damage lands when the arrow arrives.
	-- An archer killed mid-draw never releases. Once released, the arrow still
	-- lands if the archer dies; applyDamage ignores a target that is already dead.
	local drawTime = MinionConfig.ArcherDrawTime
	local flightTime = planarDistance(position, aimPoint) / MinionConfig.ArrowSpeed
	local damage, team, archer = minion.stats.damage, minion.team, minion.model
	shotEvent:FireAllClients(minion.model, target, drawTime, flightTime)
	task.delay(drawTime, function()
		if not CombatService.isAlive(minion.model) then
			return
		end
		task.delay(flightTime, function()
			CombatService.applyDamage(target, damage, archer, team)
		end)
	end)
end

local function updateMinion(minion: Minion, now: number)
	local position = minion.root.Position
	local enemy, aimPoint = chooseTarget(minion)
	local target: Vector3? = nil
	if enemy then
		faceToward(minion, aimPoint)
		-- Close in until within attack range, then hold position and attack.
		local slack = if minion.holding then HOLD_SLACK else 0
		minion.holding = planarDistance(aimPoint, position) <= minion.stats.attackRange + slack
		if not minion.holding then
			target = aimPoint
		elseif now >= minion.nextAttackAt then
			attack(minion, enemy, aimPoint, now)
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
		if not enemy then
			faceToward(minion, target)
		end
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
		-- Dead (health 0), expired or removed some other way.
		if now >= minion.expiresAt or not CombatService.isAlive(minion.model) then
			byModel[minion.model] = nil
			minion.model:Destroy()
			table.remove(alive, i)
		end
	end
	for _, minion in alive do
		-- An earlier minion's hit this tick may have killed this one.
		if CombatService.isAlive(minion.model) then
			updateMinion(minion, now)
		end
	end
end

task.spawn(function()
	task.wait(MinionConfig.FirstWaveDelay)
	while true do
		spawnWave()
		task.wait(MinionConfig.WaveInterval)
	end
end)

while true do
	updateAll()
	task.wait(TICK_SECONDS)
end
