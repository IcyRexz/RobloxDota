--!strict
-- Structures: tower targeting and firing, and removing destroyed structures.
-- Each living tower shoots one enemy in range every
-- TowerAttackInterval seconds. The shot flies to its target and the damage lands
-- on arrival, so a tower can steal a last hit just like a minion.
-- Targets: enemy minions first, then enemy heroes. A tower switches to an enemy
-- hero who damages an allied hero in its range. Hits on the same hero ramp up
-- (TowerHeroRamp) until the tower switches target or stops hitting that hero.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

local StructureConfig = Config.Structure

local TICK_SECONDS = 0.1

type Tower = {
	part: BasePart,
	team: string,
	target: Model?,
	-- Shows clients who this tower is aiming at (the range ring turns bright red
	-- for a player it targets). Written only by this script.
	targetValue: ObjectValue,
	nextShotAt: number,
	-- Hero ramp: which hero the last shots hit, how many in a row, and when.
	rampHero: Model?,
	rampHits: number,
	rampLastAt: number,
}

local arena = Workspace:WaitForChild("Arena")
local minionFolder = Workspace:WaitForChild("Minions")

-- Tells every client to show a tower shot: (tower, target, flightTime).
-- Server -> client only; the server never listens to it.
local shotEvent = Instance.new("RemoteEvent")
shotEvent.Name = "TowerShot"
shotEvent.Parent = ReplicatedStorage

-- TEMPORARY test aid: start some structures damaged (Config.Structure.TestStartHealth).
for _, item in arena:GetDescendants() do
	local startHealth = StructureConfig.TestStartHealth[item.Name]
	if startHealth and item:GetAttribute("Health") ~= nil then
		item:SetAttribute("Health", startHealth)
	end
end

local towers: { Tower } = {}
for _, item in arena:GetDescendants() do
	local team = item:GetAttribute("Team")
	if item:IsA("BasePart") and item:GetAttribute("Kind") == "Tower" and typeof(team) == "string" then
		local targetValue = Instance.new("ObjectValue")
		targetValue.Name = "Target"
		targetValue.Parent = item
		table.insert(towers, {
			part = item,
			team = team,
			target = nil,
			targetValue = targetValue,
			nextShotAt = 0,
			rampHero = nil,
			rampHits = 0,
			rampLastAt = 0,
		})
	end
end

local function planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Where shots start: the sword tip ("Muzzle", placed by TowerVisuals), else the top of the tower.
local function muzzleOf(tower: Tower): Vector3
	local muzzle = tower.part:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return tower.part.Position + Vector3.new(0, tower.part.Size.Y / 2, 0)
end

local function rootOf(unit: Model): BasePart?
	local root = unit:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Can this tower shoot this unit right now: an enemy, alive, and in range?
local function canShoot(tower: Tower, unit: Model): boolean
	local team = unit:GetAttribute("Team")
	if typeof(team) ~= "string" or team == tower.team or not CombatService.isAlive(unit) then
		return false
	end
	local root = rootOf(unit)
	return root ~= nil and planarDistance(root.Position, tower.part.Position) <= StructureConfig.TowerRange
end

local function heroes(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute("Kind") == "Hero" then
			table.insert(list, character)
		end
	end
	return list
end

-- The nearest shootable unit in a list (ties: lowest name, so every run picks the same).
local function nearest(tower: Tower, units: { Instance }): Model?
	local best: Model? = nil
	local bestDistance = math.huge
	for _, unit in units do
		if unit:IsA("Model") and canShoot(tower, unit) then
			local root = rootOf(unit) :: BasePart
			local distance = planarDistance(root.Position, tower.part.Position)
			if distance < bestDistance or (distance == bestDistance and best and unit.Name < best.Name) then
				best, bestDistance = unit, distance
			end
		end
	end
	return best
end

-- Keeps the current target while it stays shootable; otherwise picks the
-- nearest enemy minion in range, else the nearest enemy hero.
local function chooseTarget(tower: Tower): Model?
	local current = tower.target
	if current and canShoot(tower, current) then
		return current
	end
	return nearest(tower, minionFolder:GetChildren()) or nearest(tower, heroes())
end

-- Call for help: an enemy hero who damages an allied hero inside this tower's
-- range becomes the tower's target straight away.
CombatService.Damaged:Connect(function(target: Instance, attacker: Instance)
	if target:GetAttribute("Kind") ~= "Hero" or attacker:GetAttribute("Kind") ~= "Hero" or not attacker:IsA("Model") then
		return
	end
	local victimRoot = rootOf(target :: Model)
	for _, tower in towers do
		if
			target:GetAttribute("Team") == tower.team
			and CombatService.isAlive(tower.part)
			and victimRoot
			and planarDistance(victimRoot.Position, tower.part.Position) <= StructureConfig.TowerRange
			and canShoot(tower, attacker)
		then
			tower.target = attacker
		end
	end
end)

-- Damage for the next shot: minions always take TowerDamage; heroes take the
-- ramp (60, 90, 120, 120 ...), which restarts on a new hero or after a pause.
local function shotDamage(tower: Tower, target: Model, now: number): number
	if target:GetAttribute("Kind") ~= "Hero" then
		return StructureConfig.TowerDamage
	end
	if tower.rampHero ~= target or now - tower.rampLastAt > StructureConfig.TowerRampReset then
		tower.rampHero = target
		tower.rampHits = 0
	end
	tower.rampHits += 1
	tower.rampLastAt = now
	local ramp = StructureConfig.TowerHeroRamp
	return ramp[math.min(tower.rampHits, #ramp)]
end

local function fire(tower: Tower, target: Model, now: number)
	local root = rootOf(target) :: BasePart
	local flightTime = (root.Position - muzzleOf(tower)).Magnitude / StructureConfig.TowerShotSpeed
	local towerPart, team = tower.part, tower.team
	local damage = shotDamage(tower, target, now)
	tower.nextShotAt = now + StructureConfig.TowerAttackInterval
	shotEvent:FireAllClients(towerPart, target, flightTime)
	-- Lands even if the target walks out of range mid-flight; applyDamage refuses
	-- it if the target is already dead (another unit took the last hit).
	task.delay(flightTime, function()
		CombatService.applyDamage(target, damage, towerPart, team)
	end)
end

-- Tells every client a structure fell: (kind, team that lost it, team that destroyed it).
-- Server -> client only; clients show the announcement banner.
local destroyedEvent = Instance.new("RemoteEvent")
destroyedEvent.Name = "StructureDestroyed"
destroyedEvent.Parent = ReplicatedStorage

-- A destroyed structure disappears (with a tower's knight art) and everyone is
-- told. Code holding a reference sees it as dead: CombatService.isAlive checks
-- Parent, so the next structure unlocks. Core destruction ending the match comes next.
local STRUCTURE_KINDS = { Tower = true, Barracks = true, Core = true }
CombatService.Died:Connect(function(target: Instance, _killer: Instance, killerTeam: string)
	local kind = target:GetAttribute("Kind")
	local team = target:GetAttribute("Team")
	if not (target:IsA("BasePart") and typeof(kind) == "string" and STRUCTURE_KINDS[kind] and typeof(team) == "string") then
		return
	end
	local art = target.Parent and target.Parent:FindFirstChild(target.Name .. "Visual")
	if art then
		art:Destroy()
	end
	target:Destroy()
	destroyedEvent:FireAllClients(kind, team, killerTeam)
	print(`[Structures] {target.Name} destroyed by {killerTeam}`)
end)

local function updateAll()
	local now = os.clock()
	for _, tower in towers do
		if CombatService.isAlive(tower.part) then
			tower.target = chooseTarget(tower)
			local target = tower.target
			if tower.targetValue.Value ~= target then
				tower.targetValue.Value = target
			end
			if target and now >= tower.nextShotAt then
				fire(tower, target, now)
			end
		else
			tower.target = nil
			tower.targetValue.Value = nil
		end
	end
end

while true do
	updateAll()
	task.wait(TICK_SECONDS)
end
