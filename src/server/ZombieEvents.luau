--!strict
-- Battlefield events (owner 2026-10-21; list and numbers in Config.Events).
-- Every Interval seconds one event happens, picked at random but never the
-- same as the last one; DevTools can trigger the next one early (the regular
-- clock then restarts from that moment).
--  * Nest: a "Zombie Nest" structure (Kind = "Nest", team Zombies) rises on
--    open ground mid-field. This module only places the part; Minions.server
--    listens to NestCreated to spawn its guards and its zombies, and to send
--    our soldiers at it. It falls like any structure (Structures.server).
--  * Zombie Surge (timed): productionFactor is higher while it runs (the
--    Zombie Core and nests each by their own share), and BurstRequested asks
--    Minions.server for extra zombies at once.
--  * Zombies Evolve (permanent): strengthBonus grows for the rest of the
--    match; Strengthened tells Minions.server to restat living zombies.
--  * Zombie Ambush: AmbushRequested asks Minions.server for plain zombies in
--    groups of random size at random spots across the battlefield.
--  * Arrivals (owner 2026-10-23, Config.Events.Arrivals): one-time. Each
--    variant gets one of Config.Events.ArrivalTimes, shuffled every match, and
--    only joins the zombie groups once its arrival has happened (hasArrived);
--    each is announced once with a banner.
-- A ModuleScript. Its clock starts with each fight (Match.Started) and only
-- runs while fighting; the battlefield reset (T15) clears everything.
--
-- Remote: ZombieEvent (server -> all clients): (event id: string, phase:
--   "Start" | "End"), so clients can show the banner. Display only.
-- Workspace attributes for the clients' timers (server time,
-- Workspace:GetServerTimeNow()): Event<id>EndsAt while a
-- timed event runs (removed when it ends).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Landscape = require(script.Parent.Landscape)
local Match = require(script.Parent.Match)
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
local ambushRequested = Instance.new("BindableEvent")
-- Fires (total zombies, largest group) for a Zombie Ambush.
ZombieEvents.AmbushRequested = ambushRequested.Event -- (total, groupMax)
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
local startedAt = os.clock()
local nextAt = startedAt + EventConfig.FirstAt
local arrived: { [string]: boolean } = {} -- variant kind -> joined the horde
-- Variant kind -> seconds after the start when it arrives: the arrival times
-- dealt out in a random order.
local arrivalAt: { [string]: number } = {}

-- A fight starts (Match.Started, T05): the event clock and the arrivals start
-- now, with the arrival times dealt out afresh.
local function startClock()
	startedAt = os.clock()
	nextAt = startedAt + EventConfig.FirstAt
	table.clear(arrived)
	local times = table.clone(EventConfig.ArrivalTimes)
	for index = #times, 2, -1 do
		local other = math.random(1, index)
		times[index], times[other] = times[other], times[index]
	end
	for index, arrival in EventConfig.Arrivals do
		arrivalAt[arrival.kind] = times[index] or times[#times]
	end
end
startClock()
Match.Started:Connect(startClock)

-- Whether a zombie variant (MinionStats kind) may appear yet. Plain zombies
-- and kinds without an arrival always may.
function ZombieEvents.hasArrived(kind: string): boolean
	for _, arrival in EventConfig.Arrivals do
		if arrival.kind == kind then
			return arrived[kind] == true
		end
	end
	return true
end

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

-- How much faster zombie groups come out (1 = normal), from the Zombie Core
-- ("Core") or a nest ("Nest").
function ZombieEvents.productionFactor(source: "Core" | "Nest"): number
	return 1 + bonus(if source == "Nest" then "nestProductionBonus" else "coreProductionBonus")
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
	if info.ambushTotal and info.ambushGroupMax then
		ambushRequested:Fire(info.ambushTotal, info.ambushGroupMax)
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
		Workspace:SetAttribute(`Event{info.id}EndsAt`, Workspace:GetServerTimeNow() + duration)
		task.delay(duration, function()
			if runToken[info.id] == token then
				activeUntil[info.id] = nil
				Workspace:SetAttribute(`Event{info.id}EndsAt`, nil)
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

local function arrive(arrival: typeof(EventConfig.Arrivals[1]))
	if arrived[arrival.kind] then
		return
	end
	arrived[arrival.kind] = true
	bannerEvent:FireAllClients(arrival.id, "Start")
	print(`[ZombieEvents] {arrival.name}`)
end

-- Starts one named event or arrival now (DevTools, owner 2026-10-23: choose
-- the event). An event does not move the regular clock. Returns whether the
-- id was known.
function ZombieEvents.trigger(id: string): boolean
	for _, info in EventConfig.List do
		if info.id == id then
			start(info)
			return true
		end
	end
	for _, arrival in EventConfig.Arrivals do
		if arrival.id == id then
			arrive(arrival)
			return true
		end
	end
	return false
end

-- The battlefield reset (T15): no event running or remembered, zombies at
-- their base strength, the clock and arrivals dealt afresh. (Nests are
-- removed by Structures.server's reset step.)
Match.onReset(40, "ZombieEvents", function()
	for _, info in EventConfig.List do
		runToken[info.id] = (runToken[info.id] or 0) + 1 -- a running timer's end is ignored
		Workspace:SetAttribute(`Event{info.id}EndsAt`, nil)
	end
	table.clear(activeUntil)
	lastId = nil
	permanentStrength = 0
	startClock()
end)

task.spawn(function()
	while true do
		task.wait(1)
		if not Match.isFighting() then
			continue -- events and arrivals only during a fight (T05/T10)
		end
		local now = os.clock()
		for _, arrival in EventConfig.Arrivals do
			if now - startedAt >= arrivalAt[arrival.kind] then
				arrive(arrival)
			end
		end
		if now >= nextAt then
			ZombieEvents.triggerNext()
		end
	end
end)

return ZombieEvents
