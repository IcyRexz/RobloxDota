--!strict
-- Battlefield events (owner 2026-10-21; list and numbers in Config.Events).
-- Every Interval seconds one event happens, picked at random but never the
-- same as the last one; DevTools can trigger the next one early (the regular
-- clock then restarts from that moment).
--  * Nest: a "Zombie Nest" structure (Kind = "Nest", team Zombies) rises on
--    open ground mid-field. This module only places the part; Minions.server
--    listens to NestCreated to spawn its guards and its zombies, and to send
--    our soldiers at it. It falls like any structure (Structures.server).
--  * Zombie Surge (timed): productionFactor is higher while it runs, and
--    BurstRequested asks Minions.server for extra zombies at once.
--  * Zombies Evolve (permanent): strengthBonus grows for the rest of the
--    match; Strengthened tells Minions.server to restat living zombies.
-- A ModuleScript: the clock starts when first required (Minions requires it).
--
-- Remote: ZombieEvent (server -> all clients): (event id: string, phase:
--   "Start" | "End"), so clients can show the banner. Display only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Landscape = require(script.Parent.Landscape)
local SwarmField = require(script.Parent.SwarmField)

local EventConfig = Config.Events
local NestConfig = EventConfig.Nest
local NEST_COLOR = Color3.fromRGB(70, 58, 40) -- muddy brown mound
local NEST_GLOW = Color3.fromRGB(120, 255, 60)

type EventInfo = typeof(EventConfig.List[1])

local ZombieEvents = {}

local nestCreated = Instance.new("BindableEvent")
-- Fires (nest part) once a nest stands on the map.
ZombieEvents.NestCreated = nestCreated.Event
local burstRequested = Instance.new("BindableEvent")
-- Fires (count) when an event sends extra zombies from the Zombie Core at once.
ZombieEvents.BurstRequested = burstRequested.Event
local strengthened = Instance.new("BindableEvent")
-- Fires (old bonus, new bonus) when zombies get permanently stronger.
ZombieEvents.Strengthened = strengthened.Event

local bannerEvent = Instance.new("RemoteEvent")
bannerEvent.Name = "ZombieEvent"
bannerEvent.Parent = ReplicatedStorage

local arena = Workspace:WaitForChild("Arena")
local activeUntil: { [string]: number } = {} -- timed event id -> os.clock() when it ends
local runToken: { [string]: number } = {} -- bumps on each start, so only the latest run ends it
local lastId: string? = nil
local nestCount = 0
local permanentStrength = 0 -- Zombies Evolve, summed (0.25 = +25%)
local nextAt = os.clock() + EventConfig.FirstAt

local function bonus(field: string): number
	local now = os.clock()
	local total = 0
	for _, info in EventConfig.List do
		local value = (info :: any)[field]
		if type(value) == "number" and (activeUntil[info.id] or 0) > now then
			total += value
		end
	end
	return total
end

-- How much faster zombie groups come out (1 = normal).
function ZombieEvents.productionFactor(): number
	return 1 + bonus("productionBonus")
end

-- Permanent extra zombie health and damage from Zombies Evolve (0.25 = +25%).
function ZombieEvents.strengthBonus(): number
	return permanentStrength
end

local function cornersOpen(centre: Vector3, half: Vector3): boolean
	for _, offset in { Vector3.zero, Vector3.new(half.X, 0, half.Z), Vector3.new(-half.X, 0, half.Z), Vector3.new(half.X, 0, -half.Z), Vector3.new(-half.X, 0, -half.Z) } do
		if not SwarmField.isOpen(centre + offset) then
			return false
		end
	end
	return true
end

-- A random open spot mid-field (between the two cores), or nil.
local function nestSpot(): Vector3?
	local baseCore = arena:FindFirstChild("BaseCore", true)
	local zombieCore = arena:FindFirstChild("ZombieCore", true)
	if not (baseCore and baseCore:IsA("BasePart") and zombieCore and zombieCore:IsA("BasePart")) then
		return nil
	end
	local from, to = baseCore.Position, zombieCore.Position
	-- Keep a margin around it so units can walk all the way round.
	local half = NestConfig.Size / 2 + Vector3.new(4, 0, 4)
	for _ = 1, NestConfig.Tries do
		local share = NestConfig.MinShare + math.random() * (NestConfig.MaxShare - NestConfig.MinShare)
		local x = from.X + (to.X - from.X) * share
		local z = (from.Z + to.Z) / 2 + (math.random() * 2 - 1) * NestConfig.HalfWidth
		local spot = Vector3.new(x, 0, z)
		if cornersOpen(spot, half) then
			return spot
		end
	end
	return nil
end

local function raiseNest(): boolean
	local spot = nestSpot()
	if not spot then
		warn("[ZombieEvents] no open ground for a nest; skipped")
		return false
	end
	nestCount += 1
	local size = NestConfig.Size
	local nest = Instance.new("Part")
	nest.Name = `ZombieNest{nestCount}`
	nest.Anchored = true
	nest.Size = size
	nest.Color = NEST_COLOR
	nest.Material = Enum.Material.Slate
	-- Sunk 1 stud so it sits on the hills without a gap.
	nest.Position = Vector3.new(spot.X, Landscape.heightAt(spot.X, spot.Z) + size.Y / 2 - 1, spot.Z)
	nest:SetAttribute("EntityId", nest.Name)
	nest:SetAttribute("DisplayName", "Zombie Nest")
	nest:SetAttribute("Team", Config.Teams.Zombies)
	nest:SetAttribute("Kind", "Nest")
	nest:SetAttribute("MaxHealth", NestConfig.MaxHealth)
	nest:SetAttribute("Health", NestConfig.MaxHealth)
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.Material = Enum.Material.Neon
	glow.Color = NEST_GLOW
	glow.Size = Vector3.new(size.X * 0.5, 0.4, size.Z * 0.5)
	glow.Position = nest.Position + Vector3.new(0, size.Y / 2, 0)
	glow.Parent = nest
	nest.Parent = arena
	nestCreated:Fire(nest)
	print(`[ZombieEvents] {nest.Name} rose at {math.round(spot.X)}, {math.round(spot.Z)}`)
	return true
end

local function start(info: EventInfo)
	lastId = info.id
	if info.id == "Nest" and not raiseNest() then
		return
	end
	bannerEvent:FireAllClients(info.id, "Start")
	print(`[ZombieEvents] {info.name} started`)
	if info.burstZombies then
		burstRequested:Fire(info.burstZombies)
	end
	if info.strengthBonus then
		local old = permanentStrength
		permanentStrength += info.strengthBonus
		strengthened:Fire(old, permanentStrength)
	end
	local duration = info.duration
	if duration then
		local token = (runToken[info.id] or 0) + 1
		runToken[info.id] = token
		activeUntil[info.id] = os.clock() + duration
		task.delay(duration, function()
			if runToken[info.id] == token then
				activeUntil[info.id] = nil
				bannerEvent:FireAllClients(info.id, "End")
				print(`[ZombieEvents] {info.name} ended`)
			end
		end)
	end
end

local function pick(): EventInfo
	local choices: { EventInfo } = {}
	for _, info in EventConfig.List do
		if info.id ~= lastId then
			table.insert(choices, info)
		end
	end
	if #choices == 0 then
		return EventConfig.List[1]
	end
	return choices[math.random(1, #choices)]
end

-- Starts the next event now (DevTools); the regular clock restarts from now.
function ZombieEvents.triggerNext()
	nextAt = os.clock() + EventConfig.Interval
	start(pick())
end

task.spawn(function()
	while true do
		task.wait(1)
		if os.clock() >= nextAt then
			ZombieEvents.triggerNext()
		end
	end
end)

return ZombieEvents
