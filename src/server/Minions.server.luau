--!strict
-- Spawns units continuously (small groups, no waves) and moves them as a swarm
-- across the open battlefield, so the front moves with whichever side is stronger.
-- Our minions (team Defenders) come out of each standing inhibitor and head for the
-- zombie core; zombies (team Zombies) appear anywhere on a ring around the
-- zombie core and head for our Base Core. There are no lanes or routes: every
-- unit follows a shared flow field (SwarmField) around walls and structures,
-- spreads out from its neighbours (separation) and drifts a little (wander),
-- so the horde fans out over open ground and squeezes through the base
-- openings. Each zombie group first walks to its own rally point somewhere
-- across the battlefield, so the horde covers the whole field instead of taking
-- the shortest line, then picks a base opening, the one nearer that point more likely.
-- A unit walking at an enemy goes straight only while the line is open on the
-- flow-field grid; otherwise it follows a short detour around the obstacle.
-- A unit that stops making progress gets a few seconds of pure flow/detour
-- steering (no drift or crowd push) to free itself.
-- Also: fighting enemy units, heroes and structures, dying, despawning, the
-- inhibitor (barracks) bonus, and obeying stuns and slows from hero abilities
-- (UnitEffects): a stunned unit stands still and does not attack; a slowed
-- unit walks slower.
-- Base upgrades (BaseUpgrades, rules in BaseUpgradeRules): our soldiers get
-- what was bought at their barracks (health, damage, move and attack speed,
-- range, splash, extra soldiers per group). A minion keeps its unupgraded
-- `base` stats; its `stats` are base + upgrades, worked out again whenever
-- something is bought, so living soldiers improve at once (keeping their
-- health share) and new ones start with it.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseUpgrades = require(script.Parent.BaseUpgrades)
local BaseUpgradeRules = require(ReplicatedStorage.Shared.BaseUpgradeRules)
local CombatService = require(script.Parent.CombatService)
local SwarmField = require(script.Parent.SwarmField)
local UnitEffects = require(script.Parent.UnitEffects)
local Config = require(ReplicatedStorage.Shared.Config)
local JointPose = require(ReplicatedStorage.Shared.JointPose)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local UnitRequests = require(script.Parent.UnitRequests)
local ZombieEvents = require(script.Parent.ZombieEvents)
local Landscape = require(script.Parent.Landscape)

type MinionStats = Config.MinionStats

local MinionConfig = Config.Minion

local TICK_SECONDS = 0.2
-- Once holding position, an enemy must back off this much farther before the
-- minion moves again. Stops minions flickering between walking and standing.
local HOLD_SLACK = 1.5
-- Swarm steering (studs and weights; tune by eye in Studio).
local SPAWN_SCATTER = 7 -- our units appear anywhere within this radius of their spawn marker
local SPAWN_TRIES = 8 -- random spots tried for a zombie spawn or rally point before giving up
local RALLY_ARRIVE = 8 -- studs from its rally point where a zombie heads for the base
local BURST_GROUP_SIZE = 5 -- Zombie Surge's extra zombies come out in clusters this big
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
-- Zombies: glowing red eyes, no face; skin, shirt and legs by kind.
type ZombieLook = { skin: Color3, shirt: Color3, legs: Color3 }
local ZOMBIE_LOOKS: { [string]: ZombieLook } = {
	-- dark green skin, blood-red shirt, muddy legs
	Zombie = { skin = Color3.fromRGB(78, 104, 58), shirt = Color3.fromRGB(110, 34, 30), legs = Color3.fromRGB(62, 70, 48) },
	-- darker, greyer skin, near-black red shirt (and 1.5x the size)
	Brute = { skin = Color3.fromRGB(62, 82, 50), shirt = Color3.fromRGB(70, 22, 20), legs = Color3.fromRGB(44, 48, 36) },
	-- sickly yellow-green, with a glowing acid mouth
	Spitter = { skin = Color3.fromRGB(132, 160, 62), shirt = Color3.fromRGB(86, 96, 34), legs = Color3.fromRGB(62, 70, 48) },
}
local ZOMBIE_EYES = Color3.fromRGB(255, 40, 30)
local ACID_COLOR = Color3.fromRGB(50, 140, 35) -- owner 2026-10-22: darker acid green; same as MinionVisuals.client

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
	base: MinionStats, -- before base upgrades
	stats: MinionStats, -- what it fights with: base + base upgrades
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
	rally: Vector3?, -- zombies: where to walk before heading for the base (nil once there)
	-- Nest guards: the nest they stay by and the spot they stand on, until it falls.
	guard: BasePart?,
	guardPoint: Vector3?,
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

-- Tells every client to show a spitter's acid blob: (spitter, from, landing,
-- flightTime, radius). Server -> client only; the server never listens to it.
local acidEvent = Instance.new("RemoteEvent")
acidEvent.Name = "ZombieAcid"
acidEvent.Parent = ReplicatedStorage

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

-- A small glowing ball welded to the front of the head (eyes, acid mouth).
local function addFacePart(body: Model, head: BasePart, name: string, size: Vector3, color: Color3, offset: CFrame)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = head.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = body
end

-- Zombie look: no face, two glowing red eyes, both arms stretched forward; a
-- spitter also has a glowing green mouth. The arms are raised by turning the
-- shoulder joints' resting pose (JointPose), so the walk animation and the
-- client's swipe still play on top of it.
local function makeZombie(body: Model, kind: string)
	local head = body:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local face = head:FindFirstChild("face")
		if face then
			face:Destroy()
		end
		for _, x in { -0.22, 0.22 } do
			addFacePart(body, head, "Eye", Vector3.new(0.22, 0.22, 0.22), ZOMBIE_EYES, CFrame.new(x, 0.1, -head.Size.Z / 2))
		end
		if kind == "Spitter" then
			addFacePart(body, head, "Mouth", Vector3.new(0.4, 0.4, 0.4), ACID_COLOR, CFrame.new(0, -0.3, -head.Size.Z / 2))
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
	local zombie = team == ZOMBIES
	local color = TEAM_COLORS[team] or Color3.new(0.5, 0.5, 0.5)
	local look = ZOMBIE_LOOKS[stats.kind] or ZOMBIE_LOOKS.Zombie
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = if zombie then look.skin else color
	description.TorsoColor = if zombie then look.shirt else color
	description.LeftArmColor = if zombie then look.skin else color
	description.RightArmColor = if zombie then look.skin else color
	description.LeftLegColor = if zombie then look.legs else color
	description.RightLegColor = if zombie then look.legs else color
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
		makeZombie(body, stats.kind)
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
	body:ScaleTo(MinionConfig.Scale * (stats.scale or 1)) -- 1 = player size
	return body
end

local templates: { [string]: Model } = {}
local function addTemplate(team: string, stats: MinionStats)
	if not templates[team .. stats.kind] then
		templates[team .. stats.kind] = buildTemplate(team, stats)
	end
end
for team, group in MinionConfig.Groups do
	for _, stats in group do
		addTemplate(team, stats)
	end
end
for _, variant in MinionConfig.ZombieVariants do
	addTemplate(ZOMBIES, variant.stats)
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
-- ringMin/ringMax: zombie groups appear on this ring around the marker
-- (default: the Zombie Core's ring from Config).
type SpawnPoint = { marker: BasePart, team: string, source: Instance?, ringMin: number?, ringMax: number? }
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
-- toward shorter walks from their rally point (1 / distance^2), so zombies
-- rallying on one side mostly use that side's opening, but not always.
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
	if team == ZOMBIES then
		bonus += ZombieEvents.strengthBonus() -- Zombies Evolve
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

local function upgradedStats(team: string, base: MinionStats): MinionStats
	return BaseUpgradeRules.applyMods(base, BaseUpgrades.unitMods(team, base.kind))
end

-- Something was bought (or everything reset): living soldiers get their new
-- stats; a change in max health keeps the same share of their health.
local function restat(minion: Minion)
	minion.stats = upgradedStats(minion.team, minion.base)
	local newMax = minion.stats.maxHealth
	local oldMax = minion.model:GetAttribute("MaxHealth")
	local health = minion.model:GetAttribute("Health")
	if type(oldMax) == "number" and oldMax > 0 and type(health) == "number" and health > 0 and newMax ~= oldMax then
		minion.model:SetAttribute("MaxHealth", newMax)
		minion.model:SetAttribute("Health", math.max(math.round(health / oldMax * newMax), 1))
	end
end

BaseUpgrades.Changed:Connect(function()
	for _, minion in alive do
		restat(minion)
	end
end)

-- Zombies Evolve: living zombies get the new strength too (keeping their
-- health share); new ones spawn with it (strengthOf).
ZombieEvents.Strengthened:Connect(function(old: number, new: number)
	local now = strengthOf(ZOMBIES)
	local ratio = now / (now - (new - old))
	for _, minion in alive do
		if minion.team == ZOMBIES then
			minion.base = scaledStats(minion.base, ratio)
			restat(minion)
		end
	end
end)

-- Cleave / Volley upgrades: part of a hit also lands on enemy units near the target.
local function splash(team: string, kind: string, attacker: Model, target: Instance, damage: number)
	local mods = BaseUpgrades.unitMods(team, kind)
	local targetRoot = if target:IsA("Model") then target:FindFirstChild("HumanoidRootPart") else nil
	if mods.splashShare <= 0 or not (targetRoot and targetRoot:IsA("BasePart")) then
		return
	end
	local centre = targetRoot.Position
	local hits = 0
	for _, other in alive do
		if hits >= mods.splashTargets then
			return
		end
		if other.model ~= target and other.team ~= team and CombatService.isAlive(other.model) then
			local offset = other.root.Position - centre
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= mods.splashRadius then
				CombatService.applyDamage(other.model, math.round(damage * mods.splashShare), attacker, team)
				hits += 1
			end
		end
	end
end

-- A random open spot from pick() (tried SPAWN_TRIES times), or nil.
local function openSpot(pick: () -> Vector3): Vector3?
	for _ = 1, SPAWN_TRIES do
		local spot = pick()
		if SwarmField.isOpen(spot) then
			return spot
		end
	end
	return nil
end

-- A random spot on the ground between minRadius and maxRadius of centre,
-- evenly spread over that ring's area (not bunched toward its inner edge).
-- Open ground if one is found, else any such spot.
local function spotAround(centre: Vector3, minRadius: number, maxRadius: number): Vector3
	local function pick(): Vector3
		local angle = math.random() * 2 * math.pi
		local radius = math.sqrt(minRadius ^ 2 + math.random() * (maxRadius ^ 2 - minRadius ^ 2))
		return Vector3.new(centre.X + math.cos(angle) * radius, 0, centre.Z + math.sin(angle) * radius)
	end
	local spot = openSpot(pick) or pick()
	return Vector3.new(spot.X, Landscape.heightAt(spot.X, spot.Z), spot.Z)
end

-- A zombie group's rally point: part of the way from its spawn toward our Base
-- Core, shifted anywhere across the battlefield's width. Nil if none is found.
local function rallyFor(start: Vector3): Vector3?
	local baseCores = standingCores(DEFENDERS)()
	if #baseCores == 0 then
		return nil
	end
	local goal = baseCores[1].Position
	return openSpot(function()
		local share = MinionConfig.ZombieRallyMinShare
			+ math.random() * (MinionConfig.ZombieRallyMaxShare - MinionConfig.ZombieRallyMinShare)
		local x = start.X + (goal.X - start.X) * share
		local z = (start.Z + goal.Z) / 2 + (math.random() * 2 - 1) * MinionConfig.ZombieRallyHalfWidth
		return Vector3.new(x, 0, z)
	end)
end

local function spawnMinion(team: string, baseStats: MinionStats, ground: Vector3, rally: Vector3?): Minion
	local base = scaledStats(baseStats, strengthOf(team))
	local stats = upgradedStats(team, base)
	local start = ground + Vector3.new(0, 3, 0)
	local direction = if team == DEFENDERS then 1 else -1
	local facing = if rally then Vector3.new(rally.X, start.Y, rally.Z) else start + Vector3.new(direction, 0, 0)

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
		base = base,
		stats = stats,
		field = pickField(team, rally or start),
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
		rally = rally,
		guard = nil,
		guardPoint = nil,
	}
	minion.turn.CFrame = root.CFrame.Rotation
	minion.idleTrack:Play()
	if team ~= ZOMBIES then -- zombies keep both arms out instead of holding a weapon
		loadTrack(humanoid, TOOL_HOLD_ANIMATION, true):Play()
	end
	table.insert(alive, minion)
	byModel[model] = minion
	return minion
end

local function aliveCount(team: string): number
	local count = 0
	for _, minion in alive do
		if minion.team == team then
			count += 1
		end
	end
	return count
end

-- One group from one spawn marker. Our soldiers appear scattered around their
-- marker. A zombie group appears together at one random spot on the ring
-- around the zombie core and shares a rally point (each zombie aiming a little
-- off it), so the field fills with separate clusters. Spawns only what fits
-- under the team's cap; the rest is dropped (no backlog).
local function spawnGroup(spawnPoint: SpawnPoint, group: { MinionStats })
	local team = spawnPoint.team
	local room = (MinionConfig.MaxAlive[team] or 0) - aliveCount(team)
	if room <= 0 then
		return
	end
	local marker = spawnPoint.marker.Position
	local zombies = team == ZOMBIES
	local centre = if zombies
		then spotAround(
			marker,
			spawnPoint.ringMin or MinionConfig.ZombieSpawnMinRadius,
			spawnPoint.ringMax or MinionConfig.ZombieSpawnMaxRadius
		)
		else marker
	local groupRally = if zombies then rallyFor(centre) else nil
	local scatter = if zombies then MinionConfig.ZombieGroupScatter else SPAWN_SCATTER
	for index = 1, math.min(#group, room) do
		local rally = if groupRally then spotAround(groupRally, 0, MinionConfig.ZombieRallyJitter) else nil
		spawnMinion(team, group[index], spotAround(centre, 0, scatter), rally)
	end
end

-- A zombie group slot: maybe a variant (ZombieVariants chances, in order).
local function rollVariant(stats: MinionStats): MinionStats
	local roll = math.random()
	for _, variant in MinionConfig.ZombieVariants do
		if roll < variant.chance then
			return variant.stats
		end
		roll -= variant.chance
	end
	return stats
end

-- Every standing spawn marker of a team sends its group; our barracks add
-- their Reinforcements upgrades, zombie slots may become variants.
local function spawnTeam(team: string)
	local group: { MinionStats } = table.clone(MinionConfig.Groups[team] or {})
	if team == ZOMBIES then
		for index, stats in group do
			group[index] = rollVariant(stats)
		end
	elseif team == DEFENDERS then
		for _, extra in { MinionConfig.Melee, MinionConfig.Archer } do
			for _ = 1, BaseUpgrades.unitMods(DEFENDERS, extra.kind).extraPerGroup do
				table.insert(group, extra)
			end
		end
	end
	for _, spawnPoint in spawnPoints do
		if spawnPoint.team == team and spawnPoint.source and CombatService.isAlive(spawnPoint.source) then
			spawnGroup(spawnPoint, group)
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

-- Area hit (spitter acid): damage to every unit, hero and attackable
-- building of the other side within radius of centre (buildings measured to
-- their side).
local function areaHit(centre: Vector3, radius: number, damage: number, attacker: Model, team: string)
	for _, other in alive do
		if other.team ~= team and planarDistance(other.root.Position, centre) <= radius then
			CombatService.applyDamage(other.model, damage, attacker, team)
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
			and hero:GetAttribute("Team") ~= team
			and planarDistance(heroRoot.Position, centre) <= radius
		then
			CombatService.applyDamage(hero, damage, attacker, team)
		end
	end
	for _, structure in structures do
		if
			structure:GetAttribute("Team") ~= team
			and CombatService.isAlive(structure)
			and planarDistance(closestPointOn(structure, centre), centre) <= radius
		then
			CombatService.applyDamage(structure, damage, attacker, team)
		end
	end
end

-- Spitter: rears back (the swipe lunge, SpitWindup), then lobs a blob at the
-- spot its target stands on at that moment. It lands after its flight and
-- explodes there (owner 2026-10-22), hurting everything of ours within
-- splashRadius, so a target that moves away in time dodges it. A spitter
-- killed or stunned before the blob leaves its mouth never spits.
local function spit(minion: Minion, target: Instance, aimPoint: Vector3)
	local windup = MinionConfig.SpitWindup
	local radius = minion.stats.splashRadius or 0
	local damage = minion.stats.damage
	local team, spitter, spitterRoot = minion.team, minion.model, minion.root
	swingEvent:FireAllClients(spitter, windup)
	task.delay(windup, function()
		if not CombatService.isAlive(spitter) or UnitEffects.isStunned(spitter) then
			return
		end
		local head = spitter:FindFirstChild("Head")
		local from = if head and head:IsA("BasePart") then head.Position else spitterRoot.Position
		local point = targetPoint(target, from) or aimPoint
		local landing = Vector3.new(point.X, Landscape.heightAt(point.X, point.Z), point.Z)
		local flightTime = (landing - from).Magnitude / MinionConfig.AcidSpeed
		acidEvent:FireAllClients(spitter, from, landing, flightTime, radius)
		task.delay(flightTime, function()
			areaHit(landing, radius, damage, spitter, team)
		end)
	end)
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

	if minion.stats.kind == "Spitter" then
		spit(minion, target, aimPoint)
		return
	end

	if minion.stats.kind ~= "Archer" then
		if minion.team == ZOMBIES then
			-- Hand swipe: every client plays it; the hit lands when the claw comes
			-- down. A zombie killed mid-swing never lands it.
			-- The target must still be within reach when the claw lands, so a
			-- player who steps back during the swing dodges it.
			local hitDelay = if minion.stats.kind == "Brute" then MinionConfig.BruteSmashHitDelay else MinionConfig.ZombieSwipeHitDelay
			local damage = minion.stats.damage
			local team, zombie, zombieRoot = minion.team, minion.model, minion.root
			local knockback = minion.stats.knockback
			local reach = minion.stats.attackRange + HOLD_SLACK
			swingEvent:FireAllClients(zombie, hitDelay)
			task.delay(hitDelay, function()
				if not CombatService.isAlive(zombie) or UnitEffects.isStunned(zombie) then
					return -- dead or stunned mid-swing: the claw never lands
				end
				local point = targetPoint(target, zombieRoot.Position)
				if point and planarDistance(point, zombieRoot.Position) <= reach then
					CombatService.applyDamage(target, damage, zombie, team)
					-- Brute: throws one of our soldiers back (not heroes or buildings).
					local victim = byModel[target]
					if knockback and victim and victim.team ~= team and CombatService.isAlive(target) then
						UnitEffects.knockback(victim.model, zombieRoot.Position, knockback, MinionConfig.KnockbackStun)
					end
				end
			end)
			return
		end
		CombatService.applyDamage(target, minion.stats.damage, minion.model, minion.team)
		splash(minion.team, minion.stats.kind, minion.model, target, minion.stats.damage)
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
			splash(team, "Archer", archer, target, damage)
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

-- A zombie on its way to its rally point: the direction there (around
-- obstacles, like walking at an enemy). Nil, and the rally point is dropped,
-- once it is reached or the zombie is already nearer the base than it is.
local function rallyDirection(minion: Minion, now: number, unsticking: boolean): Vector3?
	local rally = minion.rally
	if not rally then
		return nil
	end
	local position = minion.root.Position
	if
		planarDistance(position, rally) <= RALLY_ARRIVE
		or SwarmField.distance(minion.field, position) <= SwarmField.distance(minion.field, rally)
	then
		minion.rally = nil
		minion.detour = nil
		return nil
	end
	local toward = approachDirection(minion, rally, now, unsticking)
	return if toward.Magnitude > 0 then toward else nil
end

-- A nest guard with no enemy near walks back to its spot by the nest and
-- waits there. Once the nest falls it joins the swarm (nil this tick).
local function guardStep(minion: Minion, now: number, unsticking: boolean): Vector3?
	local point = minion.guardPoint
	if not (point and minion.guard and CombatService.isAlive(minion.guard)) then
		minion.guard, minion.guardPoint = nil, nil
		return nil
	end
	local position = minion.root.Position
	if planarDistance(position, point) <= HOLD_SLACK * 2 then
		return nil
	end
	local toward = approachDirection(minion, point, now, unsticking)
	return position + toward * math.min(STEER_AHEAD, planarDistance(position, point))
end

-- Where the swarm wants this unit to go when it has no enemy: toward its rally
-- point (zombies, at first), else downhill on its flow field; bent sideways by
-- its own slowly changing drift, and pushed apart from its neighbours. Nil
-- when it has arrived (or has no goal left).
local function swarmStep(minion: Minion, push: Vector3, now: number, unsticking: boolean): Vector3?
	local position = minion.root.Position
	local flow = rallyDirection(minion, now, unsticking) or SwarmField.direction(minion.field, position)
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
		if not minion.rally then
			minion.detour = nil -- a rallying zombie keeps its detour around obstacles
		end
		target = if minion.guard then guardStep(minion, now, unsticking) else swarmStep(minion, push, now, unsticking)
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

-- Continuous spawning: each team on its own clock, all match long.
-- Continuous spawning: each team on its own clock, all match long. Zombie
-- Surge (ZombieEvents) shortens the zombies' wait.
for team, interval in MinionConfig.GroupInterval do
	task.spawn(function()
		task.wait(MinionConfig.FirstSpawnDelay)
		while true do
			spawnTeam(team)
			task.wait(if team == ZOMBIES then interval / ZombieEvents.productionFactor() else interval)
		end
	end)
end

-- Zombie Nest (ZombieEvents): an extra zombie goal for our soldiers and an
-- obstacle; its guards stand by it; it sends its own groups on its own clock
-- until it falls.
local NestConfig = Config.Events.Nest
ZombieEvents.NestCreated:Connect(function(nest: BasePart)
	table.insert(structures, nest)
	cores[ZOMBIES] = cores[ZOMBIES] or {}
	table.insert(cores[ZOMBIES], nest)
	SwarmField.rebuild()
	local centre = nest.Position
	for index = 1, NestConfig.Guards do
		local angle = (index - 1) / NestConfig.Guards * 2 * math.pi + math.pi -- first one on the base side
		local point = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * NestConfig.GuardRadius
		local ground = spotAround(point, 0, 2)
		local guard = spawnMinion(ZOMBIES, MinionConfig.Brute, ground, nil)
		guard.guard, guard.guardPoint = nest, ground
	end
	local spawnPoint: SpawnPoint = {
		marker = nest,
		team = ZOMBIES,
		source = nest,
		ringMin = NestConfig.SpawnMinRadius,
		ringMax = NestConfig.SpawnMaxRadius,
	}
	local group = table.create(NestConfig.GroupSize, MinionConfig.Zombie)
	task.spawn(function()
		while CombatService.isAlive(nest) do
			local rolled: { MinionStats } = {}
			for index, stats in group do
				rolled[index] = rollVariant(stats)
			end
			spawnGroup(spawnPoint, rolled)
			task.wait(NestConfig.GroupInterval / ZombieEvents.productionFactor())
		end
	end)
end)

-- Zombie Surge burst: extra zombies from the Zombie Core at once, in a few
-- clusters (BURST_GROUP_SIZE each, variants possible) around its ring.
ZombieEvents.BurstRequested:Connect(function(count: number)
	for _, spawnPoint in spawnPoints do
		if spawnPoint.team == ZOMBIES and spawnPoint.source and CombatService.isAlive(spawnPoint.source) then
			local left = count
			while left > 0 do
				local group: { MinionStats } = {}
				for index = 1, math.min(BURST_GROUP_SIZE, left) do
					group[index] = rollVariant(MinionConfig.Zombie)
				end
				spawnGroup(spawnPoint, group)
				left -= #group
			end
		end
	end
end)

-- Developer panel (DevTools): spawn one unit of a known kind at a point.
local UNITS_BY_KIND: { [string]: MinionStats } = {
	Zombie = MinionConfig.Zombie,
	Brute = MinionConfig.Brute,
	Spitter = MinionConfig.Spitter,
	Melee = MinionConfig.Melee,
	Archer = MinionConfig.Archer,
}
UnitRequests.SpawnRequested:Connect(function(team: string, kind: string, position: Vector3)
	local stats = UNITS_BY_KIND[kind]
	if not stats or (team ~= DEFENDERS and team ~= ZOMBIES) or not templates[team .. stats.kind] then
		return
	end
	spawnMinion(team, stats, spotAround(position, 0, 1), nil)
end)

while true do
	updateAll()
	task.wait(TICK_SECONDS)
end
