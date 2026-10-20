--!strict
-- Spawns unit waves and moves them as a swarm across the open battlefield.
-- Our minions (team Defenders) come out of each standing inhibitor and head for the
-- zombie cores; zombies (team Zombies) come out of each standing zombie core and
-- head for our Base Core. There are no lanes or routes: every unit follows a
-- shared flow field (SwarmField) around walls and structures, spreads out
-- from its neighbours (separation) and drifts a little (wander), so the horde
-- fans out over open ground and squeezes through the base openings. Each
-- zombie picks one of the base openings at spawn, nearer ones more likely.
-- A unit walking at an enemy goes straight only while the line is open on the
-- flow-field grid; otherwise it follows a short detour around the obstacle.
-- A unit that stops making progress gets a few seconds of pure flow/detour
-- steering (no drift or crowd push) to free itself.
-- Also: fighting enemy units, heroes and structures, dying, despawning, the
-- inhibitor (barracks) bonus, and obeying stuns and slows from hero abilities
-- (UnitEffects): a stunned unit stands still and does not attack; a slowed
-- unit walks slower.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local SwarmField = require(script.Parent.SwarmField)
local UnitEffects = require(script.Parent.UnitEffects)
local Config = require(ReplicatedStorage.Shared.Config)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

type MinionStats = Config.MinionStats

local MinionConfig = Config.Minion

local TICK_SECONDS = 0.2
-- Once holding position, an enemy must back off this much farther before the
-- minion moves again. Stops minions flickering between walking and standing.
local HOLD_SLACK = 1.5
-- Swarm steering (studs and weights; tune by eye in Studio).
local SPAWN_SCATTER = 7 -- units appear anywhere within this radius of their spawn marker
local SEPARATION_RADIUS = 4.5 -- neighbours closer than this push each other apart
local SEPARATION_WEIGHT = 1.4
local WANDER_WEIGHT = 0.45 -- sideways drift, so units fan out instead of queueing
local WANDER_CHANGE = 0.25 -- how fast each unit's drift changes per tick
local STEER_AHEAD = 6 -- studs ahead each MoveTo aims
local OVERLAP_NUDGE = 1.2 -- a unit standing still is nudged apart if neighbours overlap it
local DETOUR_REFRESH = 1 -- seconds a detour waypoint is reused before searching again
local DETOUR_SEARCHES_PER_TICK = 6 -- across all units; the rest reuse their last waypoint
local STUCK_CHECK = 1 -- seconds of walking between progress checks
local STUCK_DISTANCE = 1 -- studs a walking unit must cover per check, or it counts as stuck
local UNSTICK_TIME = 2.5 -- seconds of plain steering once stuck
-- Zombies keep their current target unless something else is this many studs nearer.
local ZOMBIE_SWITCH_SLACK = 2
local COLLISION_GROUP = "Minions" -- minions pass through each other instead of shoving

local DEFENDERS = Config.Teams.Defenders
local ZOMBIES = Config.Teams.Zombies

-- Our minions wear khaki (zombies have their own look below).
local TEAM_COLORS: { [string]: Color3 } = {
	[DEFENDERS] = Color3.fromRGB(158, 140, 100),
}
-- Zombies: dark green skin, blood-red shirt, muddy legs, glowing red eyes.
local ZOMBIE_SKIN = Color3.fromRGB(78, 104, 58)
local ZOMBIE_SHIRT = Color3.fromRGB(110, 34, 30)
local ZOMBIE_LEGS = Color3.fromRGB(62, 70, 48)
local ZOMBIE_EYES = Color3.fromRGB(255, 40, 30)

-- Roblox's own default R15 animations (free for any game). "Tool hold" raises
-- the right arm forward, the way players hold a sword.
local WALK_ANIMATION = "rbxassetid://507777826"
local IDLE_ANIMATION = "rbxassetid://507766388"
local TOOL_HOLD_ANIMATION = "rbxassetid://507768375"
local SLASH_ANIMATION = "rbxassetid://522635514" -- default "tool slash" swing, melee only
-- The walk animation is made for speed 16; scale it so feet match the real speed.
local WALK_ANIMATION_BASE_SPEED = 16

type Minion = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	team: string,
	stats: MinionStats,
	field: string, -- which SwarmField it follows
	wander: number, -- current sideways drift, -1 (left) .. 1 (right)
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
	attacker: Instance?,
	holding: boolean,
	nextAttackAt: number,
	detour: Vector3?, -- current waypoint around an obstacle toward its enemy
	detourAt: number, -- when that waypoint was found
	progressFrom: Vector3, -- where the last stuck check started
	progressAt: number,
	unstickUntil: number, -- plain steering until then (see updateMinion)
	lastTarget: Instance?, -- zombies: what it went for last tick
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

-- Tells every client to play a zombie's hand swipe: (zombie, hitDelay).
-- Server -> client only; the server never listens to it.
local swingEvent = Instance.new("RemoteEvent")
swingEvent.Name = "MinionSwing"
swingEvent.Parent = ReplicatedStorage

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

-- Zombie look: no face, two glowing red eyes, both arms stretched forward.
-- The arms are raised by turning the shoulder joints' resting pose (JointPose),
-- so the walk animation and the client's swipe still play on top of it.
local function makeZombie(body: Model)
	local head = body:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local face = head:FindFirstChild("face")
		if face then
			face:Destroy()
		end
		for _, x in { -0.22, 0.22 } do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(0.22, 0.22, 0.22)
			eye.Color = ZOMBIE_EYES
			eye.Material = Enum.Material.Neon
			eye.Massless = true
			eye.CanCollide = false
			eye.CanQuery = false
			eye.CanTouch = false
			local offset = CFrame.new(x, 0.1, -head.Size.Z / 2)
			eye.CFrame = head.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0 = head
			weld.Part1 = eye
			weld.C0 = offset
			weld.Parent = eye
			eye.Parent = body
		end
	end
	for _, jointName in { "LeftShoulder", "RightShoulder" } do
		local shoulder = JointPose.find(body, jointName)
		if shoulder then
			JointPose.set(shoulder, CFrame.Angles(math.rad(80), 0, 0)) -- arm points forward
		end
		-- Development log: which joint system the rig uses (Motor6D or the
		-- Avatar Joint Upgrade's AnimationConstraint), since posing depends on it.
		print(`[Minions] zombie {jointName}: {if shoulder then shoulder.system else "NOT FOUND"}`)
	end
end

-- One finished body per team and type, built once and cloned for every spawn.
local function buildTemplate(team: string, stats: MinionStats): Model
	local zombie = stats.kind == "Zombie"
	local color = TEAM_COLORS[team] or Color3.new(0.5, 0.5, 0.5)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = if zombie then ZOMBIE_SKIN else color
	description.TorsoColor = if zombie then ZOMBIE_SHIRT else color
	description.LeftArmColor = if zombie then ZOMBIE_SKIN else color
	description.RightArmColor = if zombie then ZOMBIE_SKIN else color
	description.LeftLegColor = if zombie then ZOMBIE_LEGS else color
	description.RightLegColor = if zombie then ZOMBIE_LEGS else color
	local body = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	body.Name = team .. stats.kind
	-- Remove any built-in scripts (such as the default Animate script) so only
	-- this file controls the minion's animations.
	for _, item in body:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	if zombie then
		makeZombie(body)
	elseif stats.kind == "Archer" then
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
	body:ScaleTo(MinionConfig.Scale) -- 1 = player size
	return body
end

local templates: { [string]: Model } = {}
for team, wave in MinionConfig.Waves do
	for _, stats in wave do
		if not templates[team .. stats.kind] then
			templates[team .. stats.kind] = buildTemplate(team, stats)
		end
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

-- Spawn markers. Each names its "Source" structure (our inhibitor, or a zombie
-- core); the marker stops spawning once that structure falls.
type SpawnPoint = { marker: BasePart, team: string, source: Instance? }
local spawnPoints: { SpawnPoint } = {}
for _, item in arena:GetDescendants() do
	local team = item:GetAttribute("Team")
	local sourceName = item:GetAttribute("Source")
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "MinionSpawn" and typeof(team) == "string" then
		table.insert(spawnPoints, {
			marker = item,
			team = team,
			source = if typeof(sourceName) == "string" then arena:FindFirstChild(sourceName, true) else nil,
		})
	end
end
table.sort(spawnPoints, function(a, b) -- same order every run (left side first)
	return a.marker.Name < b.marker.Name
end)

-- Flow fields (see SwarmField). Zombies get one field per base opening, each
-- with the other openings walled off, so a zombie committed to an opening
-- really goes through it; our minions get one field to the nearest zombie core.
local cores: { [string]: { BasePart } } = {}
local openings: { BasePart } = {}
for _, item in arena:GetDescendants() do
	local team = item:GetAttribute("Team")
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Core" and typeof(team) == "string" then
		cores[team] = cores[team] or {}
		table.insert(cores[team], item)
	elseif item:IsA("BasePart") and item:GetAttribute("Kind") == "Opening" then
		table.insert(openings, item)
	end
end
table.sort(openings, function(a, b)
	return a.Name < b.Name
end)

local function standingCores(team: string): () -> { BasePart }
	return function()
		local list: { BasePart } = {}
		local teamCores: { BasePart } = cores[team] or {}
		for _, core in teamCores do
			if CombatService.isAlive(core) then
				table.insert(list, core)
			end
		end
		return list
	end
end

local zombieFields: { string } = {}
for _, opening in openings do
	local others = {}
	for _, other in openings do
		if other ~= opening then
			table.insert(others, other)
		end
	end
	local name = "ToBaseVia" .. opening.Name
	SwarmField.define(name, { goals = standingCores(DEFENDERS), closed = others })
	table.insert(zombieFields, name)
end
if #zombieFields == 0 then -- a map without marked openings: one field straight to the core
	SwarmField.define("ToBase", { goals = standingCores(DEFENDERS), closed = {} })
	table.insert(zombieFields, "ToBase")
end
SwarmField.define("ToZombies", { goals = standingCores(ZOMBIES), closed = {} })

-- A fallen structure frees the ground it stood on (and may remove a goal).
CombatService.Died:Connect(function(target: Instance)
	if target:IsA("BasePart") and Targeting.StructureKinds[target:GetAttribute("Kind")] then
		task.defer(SwarmField.rebuild) -- after Structures.server has removed it
	end
end)

-- Which field a new unit follows. Zombies pick an opening at random, weighted
-- toward shorter walks (1 / distance^2), so both spawn cores feed both openings.
local function pickField(team: string, start: Vector3): string
	if team ~= ZOMBIES then
		return "ToZombies"
	end
	local total = 0
	local weights: { number } = {}
	for i, name in zombieFields do
		local distance = SwarmField.distance(name, start)
		weights[i] = if distance < math.huge then 1 / (distance * distance + 1) else 0
		total += weights[i]
	end
	local roll = math.random() * total
	for i, name in zombieFields do
		roll -= weights[i]
		if roll <= 0 and weights[i] > 0 then
			return name
		end
	end
	return zombieFields[1]
end

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

local function spawnMinion(spawnPoint: SpawnPoint, baseStats: MinionStats)
	local team = spawnPoint.team
	local marker = spawnPoint.marker
	local stats = scaledStats(baseStats, strengthOf(team))
	local direction = if team == DEFENDERS then 1 else -1
	local angle, radius = math.random() * 2 * math.pi, math.sqrt(math.random()) * SPAWN_SCATTER
	local start = marker.Position + Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius)
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
		field = pickField(team, start),
		wander = math.random() * 2 - 1,
		expiresAt = os.clock() + MinionConfig.Lifetime,
		walkTrack = loadTrack(humanoid, WALK_ANIMATION, true),
		idleTrack = loadTrack(humanoid, IDLE_ANIMATION, true),
		slashTrack = if stats.kind == "Melee" then loadTrack(humanoid, SLASH_ANIMATION, false) else nil,
		turn = root:FindFirstChild("Turn") :: AlignOrientation,
		structure = nil,
		attacker = nil,
		holding = false,
		nextAttackAt = 0,
		detour = nil,
		detourAt = -math.huge,
		progressFrom = start,
		progressAt = os.clock(),
		unstickUntil = 0,
		lastTarget = nil,
	}
	minion.turn.CFrame = root.CFrame.Rotation
	minion.idleTrack:Play()
	if stats.kind ~= "Zombie" then -- zombies keep both arms out instead of holding a weapon
		loadTrack(humanoid, TOOL_HOLD_ANIMATION, true):Play()
	end
	table.insert(alive, minion)
	byModel[model] = minion
end

-- Spawns one wave at every spawn marker whose source still stands, never
-- exceeding the unit cap. Units are added one wave slot at a time across all
-- markers, so if the cap is hit no spawn point is left empty; the team that
-- goes first alternates.
local longestWave = 0
for _, wave in MinionConfig.Waves do
	longestWave = math.max(longestWave, #wave)
end
local firstTeam = DEFENDERS
local function spawnWave()
	local order: { string } = if firstTeam == DEFENDERS then { DEFENDERS, ZOMBIES } else { ZOMBIES, DEFENDERS }
	firstTeam = order[2]
	for index = 1, longestWave do
		for _, team in order do
			local stats = MinionConfig.Waves[team] and MinionConfig.Waves[team][index]
			for _, spawnPoint in spawnPoints do
				if stats and spawnPoint.team == team and spawnPoint.source and CombatService.isAlive(spawnPoint.source) then
					if #alive >= MinionConfig.MaxAlive then
						return
					end
					spawnMinion(spawnPoint, stats)
				end
			end
		end
	end
end

local function planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
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

-- Where to walk to and swing at: a structure's nearest side, or a unit's centre.
local function targetPoint(target: Instance, from: Vector3): Vector3?
	if target:IsA("BasePart") then
		return closestPointOn(target, from)
	end
	local root = target:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function drawAggro(minion: Minion, attacker: Instance)
	minion.attacker = attacker
	minion.structure = nil -- fighting back beats a structure lock
end

-- Aggro for our minions (standard rules; zombies ignore it). Each one breaks
-- a structure lock:
--  * retaliation: a unit damaged by an enemy unit or tower turns on that
--    attacker and chases it while it stays within RetaliateRange
--  * call for help: same-team units within HelpRange of the victim that are not
--    already fighting back join in on the same attacker
CombatService.Damaged:Connect(function(target: Instance, attacker: Instance, attackerTeam: string)
	local victim = byModel[target]
	if not (victim and attackerTeam ~= victim.team and victim.team ~= ZOMBIES and targetPoint(attacker, victim.root.Position)) then
		return
	end
	drawAggro(victim, attacker)
	for _, ally in alive do
		if
			ally ~= victim
			and ally.team == victim.team
			and ally.attacker == nil
			and planarDistance(ally.root.Position, victim.root.Position) <= MinionConfig.HelpRange
		then
			drawAggro(ally, attacker)
		end
	end
end)

-- Every tower, barracks and core, found once from the map.
local structures: { BasePart } = {}
for _, item in arena:GetDescendants() do
	if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
		table.insert(structures, item)
	end
end

local function canHitStructure(minion: Minion, structure: BasePart): boolean
	return structure:GetAttribute("Team") ~= minion.team
		and CombatService.isAlive(structure)
		and not CombatService.isLocked(structure)
end

-- Zombies (owner 2026-10-20): simply the nearest enemy within aggro range,
-- unit, player or attackable structure alike, measured to a structure's side.
-- No retaliation chase and no structure lock: hitting a zombie does not make
-- it follow you. The current target is kept unless another is clearly nearer.
local function nearestForZombie(minion: Minion): (Instance?, Vector3)
	local position = minion.root.Position
	local best: Instance? = nil
	local bestPoint = position
	local bestDistance = minion.stats.aggroRange
	local keptPoint: Vector3? = nil
	local keptDistance = math.huge
	local function consider(candidate: Instance, point: Vector3)
		local distance = planarDistance(point, position)
		if candidate == minion.lastTarget and distance <= minion.stats.aggroRange then
			keptPoint, keptDistance = point, distance
		end
		if distance <= bestDistance then
			best, bestPoint, bestDistance = candidate, point, distance
		end
	end
	for _, other in alive do
		if other.team ~= minion.team and CombatService.isAlive(other.model) then
			consider(other.model, other.root.Position)
		end
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
			consider(hero, heroRoot.Position)
		end
	end
	for _, structure in structures do
		if canHitStructure(minion, structure) then
			consider(structure, closestPointOn(structure, position))
		end
	end
	local kept = minion.lastTarget
	if kept and keptPoint and keptDistance <= bestDistance + ZOMBIE_SWITCH_SLACK then
		return kept, keptPoint
	end
	minion.lastTarget = best
	return best, bestPoint
end

-- What this minion fights, and the point it walks to and faces (zombies use
-- nearestForZombie instead):
--  0. an enemy that drew its aggro (see the Damaged handler: whoever hit it or
--     a nearby ally, including towers), while within RetaliateRange: it drops
--     whatever it was doing, even a structure
--  1. the structure it is already hitting, until that falls (structure lock)
--  2. the nearest enemy minion within aggro range
--  3. the nearest enemy hero within aggro range
--  4. the nearest enemy structure within aggro range that can take damage
-- Locked structures are walked past.
local function chooseTarget(minion: Minion): (Instance?, Vector3)
	if minion.team == ZOMBIES then
		return nearestForZombie(minion)
	end
	local position = minion.root.Position
	local attacker = minion.attacker
	if attacker and CombatService.isAlive(attacker) and not CombatService.isLocked(attacker) then
		local point = targetPoint(attacker, position)
		if point and planarDistance(point, position) <= MinionConfig.RetaliateRange then
			return attacker, point
		end
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
		if minion.stats.kind == "Zombie" then
			-- Hand swipe: every client plays it; the hit lands when the claw comes
			-- down. A zombie killed mid-swing never lands it.
			-- The target must still be within reach when the claw lands, so a
			-- player who steps back during the swing dodges it.
			local hitDelay = MinionConfig.ZombieSwipeHitDelay
			local damage, team, zombie, zombieRoot = minion.stats.damage, minion.team, minion.model, minion.root
			local reach = minion.stats.attackRange + HOLD_SLACK
			swingEvent:FireAllClients(zombie, hitDelay)
			task.delay(hitDelay, function()
				if not CombatService.isAlive(zombie) or UnitEffects.isStunned(zombie) then
					return -- dead or stunned mid-swing: the claw never lands
				end
				local point = targetPoint(target, zombieRoot.Position)
				if point and planarDistance(point, zombieRoot.Position) <= reach then
					CombatService.applyDamage(target, damage, zombie, team)
				end
			end)
			return
		end
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
		if not CombatService.isAlive(minion.model) or UnitEffects.isStunned(minion.model) then
			return
		end
		task.delay(flightTime, function()
			CombatService.applyDamage(target, damage, archer, team)
		end)
	end)
end

-- Push away from same-team neighbours that are too close (stronger the closer
-- they are). Flat vector; zero when nobody is near.
local function separation(minion: Minion): Vector3
	local position = minion.root.Position
	local push = Vector3.zero
	for _, other in alive do
		if other ~= minion and other.team == minion.team then
			local offset = Vector3.new(position.X - other.root.Position.X, 0, position.Z - other.root.Position.Z)
			local distance = offset.Magnitude
			if distance < SEPARATION_RADIUS then
				-- Exactly on top of each other: pick any direction to split.
				local away = if distance > 0.05 then offset / distance else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
				push += away * (1 - distance / SEPARATION_RADIUS)
			end
		end
	end
	return push
end

-- Where the swarm wants this unit to go when it has no enemy: downhill on its
-- flow field, bent sideways by its own slowly changing drift, and pushed apart
-- from its neighbours. Nil when it has arrived (or has no goal left).
local function swarmStep(minion: Minion, push: Vector3, unsticking: boolean): Vector3?
	local position = minion.root.Position
	local flow = SwarmField.direction(minion.field, position)
	if not flow then
		return nil
	end
	local plain = position + flow * STEER_AHEAD
	if unsticking then
		return plain
	end
	minion.wander = math.clamp(minion.wander + (math.random() * 2 - 1) * WANDER_CHANGE, -1, 1)
	local sideways = Vector3.new(-flow.Z, 0, flow.X)
	local steer = flow + sideways * minion.wander * WANDER_WEIGHT + push * SEPARATION_WEIGHT
	if steer.Magnitude < 0.05 then
		return plain
	end
	local bent = position + steer.Unit * STEER_AHEAD
	-- Drift or crowding must never steer a unit into a wall or structure.
	return if SwarmField.clearLine(position, bent) then bent else plain
end

-- Detour searches left this tick (reset in updateAll), so a crowd hitting an
-- obstacle at once spreads its searches over several ticks.
local detourBudget = DETOUR_SEARCHES_PER_TICK

-- Direction to walk toward an enemy at aimPoint: straight while the line is
-- open, else toward a detour waypoint around the obstacle (refreshed now and
-- then). Falls back to straight if no detour is found.
local function approachDirection(minion: Minion, aimPoint: Vector3, now: number, unsticking: boolean): Vector3
	local position = minion.root.Position
	local goal = aimPoint
	if unsticking or not SwarmField.clearLine(position, aimPoint) then
		local stale = not minion.detour or now - minion.detourAt >= DETOUR_REFRESH
		if stale and detourBudget > 0 then
			detourBudget -= 1
			minion.detour = SwarmField.waypointToward(position, aimPoint)
			minion.detourAt = now
		end
		goal = minion.detour or aimPoint
	else
		minion.detour = nil
	end
	local toward = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z)
	return if toward.Magnitude > 0.05 then toward.Unit else Vector3.zero
end

-- Stuck check: a unit that keeps trying to walk but covers less than
-- STUCK_DISTANCE in STUCK_CHECK seconds steers plainly for UNSTICK_TIME.
local function trackProgress(minion: Minion, walking: boolean, now: number)
	local position = minion.root.Position
	if not walking then
		minion.progressFrom, minion.progressAt = position, now
		return
	end
	if now - minion.progressAt >= STUCK_CHECK then
		if planarDistance(position, minion.progressFrom) < STUCK_DISTANCE and now >= minion.unstickUntil then
			minion.unstickUntil = now + UNSTICK_TIME
			minion.detour = nil
		end
		minion.progressFrom, minion.progressAt = position, now
	end
end

local function updateMinion(minion: Minion, now: number)
	local position = minion.root.Position
	-- Stunned (or flying from a knockback): stand still, no attacks.
	if UnitEffects.isStunned(minion.model) then
		minion.humanoid:MoveTo(position)
		setWalking(minion, false)
		trackProgress(minion, false, now)
		return
	end
	-- Slowed by an ability: walk at a share of the normal speed.
	local speed = minion.stats.speed * UnitEffects.speedFactor(minion.model)
	if minion.humanoid.WalkSpeed ~= speed then
		minion.humanoid.WalkSpeed = speed
	end
	local unsticking = now < minion.unstickUntil
	local push = if unsticking then Vector3.zero else separation(minion)
	local enemy, aimPoint = chooseTarget(minion)
	local target: Vector3? = nil
	if enemy then
		faceToward(minion, aimPoint)
		-- Close in until within attack range, then hold position and attack.
		local slack = if minion.holding then HOLD_SLACK else 0
		minion.holding = planarDistance(aimPoint, position) <= minion.stats.attackRange + slack
		if not minion.holding then
			-- Approach while spreading out, so a crowd surrounds the target
			-- instead of piling onto one spot.
			local distance = planarDistance(aimPoint, position)
			local steer = approachDirection(minion, aimPoint, now, unsticking) + push * SEPARATION_WEIGHT
			target = if steer.Magnitude > 0.05 then position + steer.Unit * math.min(STEER_AHEAD, distance) else aimPoint
		else
			if now >= minion.nextAttackAt then
				attack(minion, enemy, aimPoint, now)
			end
			-- Standing and fighting: still shuffle apart if packed onto a neighbour.
			if push.Magnitude > 0.5 then
				minion.humanoid:MoveTo(position + push.Unit * OVERLAP_NUDGE)
				setWalking(minion, false)
				trackProgress(minion, false, now)
				return
			end
		end
	else
		minion.holding = false
		minion.detour = nil
		target = swarmStep(minion, push, unsticking)
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
	trackProgress(minion, target ~= nil, now)
end

local function updateAll()
	local now = os.clock()
	detourBudget = DETOUR_SEARCHES_PER_TICK
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
