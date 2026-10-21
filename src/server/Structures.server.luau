--!strict
-- Structures: tower targeting and firing, and removing destroyed structures.
-- Each living tower shoots the nearest enemy unit in range (keeping its current
-- target while it stays in range) every TowerAttackInterval seconds. The shot
-- flies to its target and the damage lands on arrival, so a tower can steal a
-- last hit just like a minion. Damage, range and attack speed include our
-- Buildings upgrades (BaseUpgrades.towerStats, read on every check).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseUpgrades = require(script.Parent.BaseUpgrades)
local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local StructureConfig = Config.Structure

local TICK_SECONDS = 0.1

type Tower = {
	part: BasePart,
	team: string,
	target: Model?,
	nextShotAt: number,
	range: number, -- with upgrades, refreshed every tick
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
		table.insert(towers, { part = item, team = team, target = nil, nextShotAt = 0, range = StructureConfig.TowerRange })
	end
end

-- Where shots start: the sword tip ("Muzzle", placed by TowerVisuals), else the top of the tower.
local function muzzleOf(tower: Tower): Vector3
	local muzzle = tower.part:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return tower.part.Position + Vector3.new(0, tower.part.Size.Y / 2, 0)
end

-- Can this tower shoot this unit right now: an enemy, alive, and in range?
local function canShoot(tower: Tower, unit: Model): boolean
	local team = unit:GetAttribute("Team")
	if typeof(team) ~= "string" or team == tower.team or not CombatService.isAlive(unit) then
		return false
	end
	local root = Targeting.rootOf(unit)
	return root ~= nil and Targeting.planarDistance(root.Position, tower.part.Position) <= tower.range
end

-- Keeps the current target while it stays shootable; otherwise the nearest
-- enemy unit in range (ties: lowest name, so every run picks the same).
local function chooseTarget(tower: Tower): Model?
	local current = tower.target
	if current and canShoot(tower, current) then
		return current
	end
	local best: Model? = nil
	local bestDistance = math.huge
	for _, unit in minionFolder:GetChildren() do
		if unit:IsA("Model") and canShoot(tower, unit) then
			local root = Targeting.rootOf(unit) :: BasePart
			local distance = Targeting.planarDistance(root.Position, tower.part.Position)
			if distance < bestDistance or (distance == bestDistance and best and unit.Name < best.Name) then
				best, bestDistance = unit, distance
			end
		end
	end
	return best
end

local function fire(tower: Tower, target: Model, now: number)
	local root = Targeting.rootOf(target) :: BasePart
	local flightTime = (root.Position - muzzleOf(tower)).Magnitude / StructureConfig.TowerShotSpeed
	local towerPart, team = tower.part, tower.team
	local stats = BaseUpgrades.towerStats(team)
	tower.nextShotAt = now + stats.attackInterval
	shotEvent:FireAllClients(towerPart, target, flightTime)
	-- Lands even if the target walks out of range mid-flight; applyDamage refuses
	-- it if the target is already dead (another unit took the last hit).
	task.delay(flightTime, function()
		CombatService.applyDamage(target, stats.damage, towerPart, team)
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
CombatService.Died:Connect(function(target: Instance, _killer: Instance, killerTeam: string)
	local kind = target:GetAttribute("Kind")
	local team = target:GetAttribute("Team")
	if not (target:IsA("BasePart") and typeof(kind) == "string" and Targeting.StructureKinds[kind] and typeof(team) == "string") then
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
			tower.range = BaseUpgrades.towerStats(tower.team).range
			tower.target = chooseTarget(tower)
			local target = tower.target
			if target and now >= tower.nextShotAt then
				fire(tower, target, now)
			end
		else
			tower.target = nil
		end
	end
end

while true do
	updateAll()
	task.wait(TICK_SECONDS)
end
