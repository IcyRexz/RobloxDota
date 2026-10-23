--!strict
-- Hero actions requested by clients: the Mage's kit (owner 2026-10-21; numbers
-- in Config.Hero, mastery rules in MageAbilities):
--  * Pulse, Lightning Bolt (left mouse): (aim direction: Vector3). See "Aimed
--    shot" below. Passive Arcane Resonance: every Nth bolt that hits deals bonus
--    damage (the count is the character's Resonance attribute, for the HUD).
--    Masteries: Chain Bolt (jumps to a second enemy), Quick Resonance (every
--    3rd hit), Arcane Power (more damage, via HeroProgress).
--  * Strike, Lightning Strike (Q): (target point: Vector3). Within Range (flat)
--    of the hero. After Delay, every enemy unit within the radius takes damage.
--    Masteries: Thunderstorm (the area keeps striking one enemy at a time),
--    Empowered Lightning (bigger, harder).
--  * Teleport (E): (landing point: Vector3). Open ground within Range (flat),
--    pulled back to before the first fence (Targeting.stopAtFence); the server
--    checks the spot and moves the hero there. Mastery: Quick Blink
--    (shorter cooldown).
-- Damage grows with the player's level (HeroProgress). Cooldowns are server
-- time in the character's <Action>ReadyAt attributes, with the full length in
-- <Action>Cooldown (masteries can change it); the HUD reads both.
--
-- Aimed shot (owner 2026-10-20): the client sends only the direction it is
-- aiming (the camera's look direction = the crosshair). The server casts the
-- shot itself from the hero's head along that direction, up to Pulse.Range:
-- the first enemy on that line is hit; allies, hills and fences are passed
-- through; trees, rocks and structures stop it; nothing in range = a miss.
-- Every accepted shot spends the cooldown, hit or miss.
--
-- Remote: HeroAction (client -> server): (action name: string, argument).
--   Directions must be finite and roughly unit length; points finite and in range.
-- Remote: HeroAttack (server -> client): (attacker, target or nil, damage dealt,
--   end point) for every shot, so clients can draw the bolt (to the end point)
--   and, on a hit, the flash and damage number. Display only.
-- Remote: SkillFx (server -> clients): effects for SkillEffects.client:
--   Strike (point, radius, delay), Storm (point, radius, duration), StormBolt
--   (point), Teleport (from, to), Resonance (target), Chain (from, to); and to
--   the caster only Hit
--   (target, damage dealt) for damage numbers.
-- The swing animation and turning to face the target are done by the
-- attacker's own device (it owns its character's movement).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local HeroProgress = require(script.Parent.HeroProgress)
local Match = require(script.Parent.Match)
local Config = require(ReplicatedStorage.Shared.Config)
local MageAbilities = require(ReplicatedStorage.Shared.MageAbilities)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local HeroConfig = Config.Hero
local Pulse = HeroConfig.Pulse
local Skills = HeroConfig.Skills

local POINT_SLACK = 2 -- studs of range slack for movement between the client's aim and now
-- The server sees a walking hero a little behind where its own device has it
-- (owner 2026-10-23: E held while walking often did nothing, refused as out of
-- range). A point up to this far beyond the range is pulled back to
-- Range + POINT_SLACK instead of refused; farther is refused.
local MOVE_SLACK = 10
local TELEPORT_MAX_RISE = 25 -- studs the landing spot may be above or below the hero
local CLEARANCE = Vector3.new(2, 5, 2) -- room the hero needs at the landing spot

local actionEvent = Instance.new("RemoteEvent")
actionEvent.Name = "HeroAction"
actionEvent.Parent = ReplicatedStorage

local attackEvent = Instance.new("RemoteEvent")
attackEvent.Name = "HeroAttack"
attackEvent.Parent = ReplicatedStorage

local skillFx = Instance.new("RemoteEvent")
skillFx.Name = "SkillFx"
skillFx.Parent = ReplicatedStorage

local minionFolder = Workspace:WaitForChild("Minions")

-- Per-player server state. Cleared when the player leaves.
type State = {
	requestTimes: { number }, -- recent request times, for the rate limit
	busyUntil: number, -- end of the current windup
	hits: number, -- bolt hits towards the next Arcane Resonance
	hitsCharacter: Model?, -- the character `hits` belongs to (reset on respawn)
}
local states: { [Player]: State } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Rate limit: at most MaxActionsPerSecond requests in any one-second window.
local function allowRequest(state: State, time: number): boolean
	local times = state.requestTimes
	while times[1] and time - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= HeroConfig.MaxActionsPerSecond then
		return false
	end
	table.insert(times, time)
	return true
end

-- Starts a cooldown: when it ends and how long it is (both for the HUD).
local function startCooldown(character: Model, action: string, time: number, seconds: number)
	character:SetAttribute(action .. "Cooldown", seconds)
	character:SetAttribute(action .. "ReadyAt", time + seconds)
end

-- Can this hero damage this instance: an enemy target kind, alive, not locked?
local function isEnemyTarget(character: Model, team: string, target: Instance): boolean
	if not Targeting.TargetKinds[target:GetAttribute("Kind")] or target == character then
		return false
	end
	local targetTeam = target:GetAttribute("Team")
	return typeof(targetTeam) == "string"
		and targetTeam ~= team
		and CombatService.isAlive(target)
end

-- A usable aim direction from the client: a finite, roughly unit Vector3.
local function readDirection(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local length = value.Magnitude
	if length ~= length or length < 0.5 or length > 1.5 then
		return nil -- NaN, infinite or not a direction
	end
	return value / length
end

local function isFinitePoint(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	for _, axis in { value.X, value.Y, value.Z } do
		if axis ~= axis or math.abs(axis) > 1e5 then
			return false
		end
	end
	return true
end

-- Enemy units (not structures) within `radius` (flat) of a point.
local function enemyUnitsNear(character: Model, team: string, point: Vector3, radius: number): { Model }
	local found: { Model } = {}
	for _, unit in minionFolder:GetChildren() do
		if unit:IsA("Model") and isEnemyTarget(character, team, unit) then
			local root = Targeting.rootOf(unit)
			if root and Targeting.planarDistance(root.Position, point) <= radius then
				table.insert(found, unit)
			end
		end
	end
	return found
end

-- Deals ability damage and shows the caster the number.
local function hit(player: Player, character: Model, team: string, target: Instance, damage: number): number
	local dealt = CombatService.applyDamage(target, math.min(damage, CombatService.MaxDamage), character, team)
	if dealt > 0 then
		skillFx:FireClient(player, "Hit", target, dealt)
	end
	return dealt
end

-- The player's living hero and team, if this action is off cooldown.
local function readyFor(player: Player, action: string, time: number): (Model?, string?)
	local character = player.Character
	local team = character and character:GetAttribute("Team")
	if not (character and typeof(team) == "string" and character:GetAttribute("Kind") == "Hero") then
		return nil, nil
	end
	if not CombatService.isAlive(character) or not (Match.isFighting() and Match.inParty(player)) then
		return nil, nil -- attacks and abilities only in a running fight (T05: not in the lobby; T10: not after the result)
	end
	local readyAt = character:GetAttribute(action .. "ReadyAt")
	if typeof(readyAt) == "number" and time < readyAt then
		return nil, nil
	end
	return character, team
end

-- Lightning Bolt -----------------------------------------------------------------------

-- Chain Bolt mastery: the hit jumps from where the shot ended to the nearest other enemy.
local function chainBolt(player: Player, character: Model, team: string, target: Instance, at: Vector3, damage: number)
	if HeroProgress.hasMastery(player, "ChainBolt") then
		local nearest: Model? = nil
		local nearestDistance = Pulse.Chain.Range
		for _, unit in enemyUnitsNear(character, team, at, Pulse.Chain.Range) do
			local root = Targeting.rootOf(unit)
			if unit ~= target and root then
				local distance = Targeting.planarDistance(root.Position, at)
				if distance <= nearestDistance then
					nearest, nearestDistance = unit, distance
				end
			end
		end
		local nearestRoot = nearest and Targeting.rootOf(nearest)
		if nearest and nearestRoot then
			skillFx:FireAllClients("Chain", at, nearestRoot.Position)
			hit(player, character, team, nearest, damage * Pulse.Chain.Factor)
		end
	end
end

local function pulse(player: Player, state: State, time: number, aim: unknown)
	local direction = readDirection(aim)
	local character, team = readyFor(player, "Pulse", time)
	if not (direction and character and team) or time < state.busyUntil then
		return -- still swinging or cooling down; never queued for later
	end
	if state.hitsCharacter ~= character then
		-- A new life: Resonance starts over.
		state.hits, state.hitsCharacter = 0, character
		character:SetAttribute("Resonance", 0)
	end

	-- Accepted: cooldown starts now (server time); clients read it for the HUD.
	startCooldown(character, "Pulse", time, Pulse.Cooldown)
	state.busyUntil = time + Pulse.Windup

	task.delay(Pulse.Windup, function()
		-- The hero must still be this same living character; the shot is cast
		-- now, from where the hero stands at the end of the windup.
		if player.Character ~= character or not CombatService.isAlive(character) then
			return
		end
		local target, endPoint = Targeting.castShot(character, team, direction, Pulse.Range, function(candidate)
			return isEnemyTarget(character, team, candidate)
		end)
		if not target then
			attackEvent:FireAllClients(character, nil, 0, endPoint)
			return
		end
		local damage = HeroProgress.attackDamage(player)
		-- Arcane Resonance: counts hits; the Nth deals bonus damage.
		local resonated = false
		state.hits += 1
		if state.hits >= MageAbilities.resonanceEvery(HeroProgress.masteryCheck(player)) then
			state.hits = 0
			resonated = true
			damage *= 1 + HeroConfig.Resonance.BonusFactor
		end
		character:SetAttribute("Resonance", state.hits)
		local dealt = CombatService.applyDamage(target, math.min(damage, CombatService.MaxDamage), character, team)
		attackEvent:FireAllClients(character, target, dealt, endPoint)
		if resonated then
			skillFx:FireAllClients("Resonance", target)
		end
		chainBolt(player, character, team, target, endPoint, damage)
	end)
end

-- Lightning Strike ------------------------------------------------------------------------

-- Thunderstorm mastery: the area strikes one random enemy inside it every
-- Interval for Duration. Stops early if the player leaves.
local function storm(player: Player, character: Model, team: string, at: Vector3, radius: number, damage: number)
	local S = Skills.Strike.Storm
	skillFx:FireAllClients("Storm", at, radius, S.Duration)
	task.spawn(function()
		for _ = 1, math.floor(S.Duration / S.Interval + 1e-6) do
			task.wait(S.Interval)
			if player.Parent == nil then
				return
			end
			local units = enemyUnitsNear(character, team, at, radius)
			local unit = units[math.random(1, math.max(#units, 1))]
			local root = unit and Targeting.rootOf(unit)
			if unit and root then
				skillFx:FireAllClients("StormBolt", root.Position)
				hit(player, character, team, unit, damage * S.Factor)
			end
		end
	end)
end

-- An ability's aimed point, if it is within reach of the hero as the server
-- sees it: pulled back toward the hero when only movement lag puts it beyond.
local function withinReach(root: BasePart, point: Vector3, range: number): Vector3?
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	local distance = flat.Magnitude
	if distance <= range + POINT_SLACK then
		return point
	elseif distance > range + MOVE_SLACK then
		return nil
	end
	local pulled = root.Position + flat.Unit * (range + POINT_SLACK)
	return Vector3.new(pulled.X, point.Y, pulled.Z)
end

local function strike(player: Player, _state: State, time: number, point: unknown)
	local S = Skills.Strike
	local character, team = readyFor(player, "Strike", time)
	local root = character and Targeting.rootOf(character)
	if not (character and team and root and isFinitePoint(point)) then
		return
	end
	local at = withinReach(root, point :: Vector3, S.Range)
	if not at then
		return
	end
	local has = HeroProgress.masteryCheck(player)
	local radius = MageAbilities.strikeRadius(has)
	local damage = HeroProgress.scaledDamage(player, MageAbilities.strikeDamage(has))
	startCooldown(character, "Strike", time, S.Cooldown)
	skillFx:FireAllClients("Strike", at, radius, S.Delay)
	task.delay(S.Delay, function()
		for _, unit in enemyUnitsNear(character, team, at, radius) do
			hit(player, character, team, unit, damage)
		end
		if has("Thunderstorm") then
			storm(player, character, team, at, radius, damage)
		end
	end)
end

-- Teleport --------------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local roomParams = OverlapParams.new()
roomParams.FilterType = Enum.RaycastFilterType.Exclude
roomParams.RespectCanCollide = true

-- Characters and units are not ground and do not block a landing.
local function ignoreList(): { Instance }
	local ignore: { Instance } = { minionFolder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	return ignore
end

local function isFence(part: Instance): boolean
	local node: Instance? = part
	while node and node ~= Workspace do
		if node:GetAttribute("Kind") == "Fence" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Where the hero would stand at a requested point: the top surface under it
-- (not a fence), with room to stand. Nil if there is no such spot.
local function landingSpot(point: Vector3): Vector3?
	local ignore = ignoreList()
	groundParams.FilterDescendantsInstances = ignore
	local ground = Workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -12, 0), groundParams)
	if not ground or isFence(ground.Instance) then
		return nil
	end
	local landing = ground.Position
	table.insert(ignore, Workspace.Terrain) -- the slope under the feet is not in the way
	roomParams.FilterDescendantsInstances = ignore
	local room = CFrame.new(landing + Vector3.new(0, 0.4 + CLEARANCE.Y / 2, 0))
	if #Workspace:GetPartBoundsInBox(room, CLEARANCE, roomParams) > 0 then
		return nil
	end
	return landing
end

local function teleport(player: Player, _state: State, time: number, point: unknown)
	local T = Skills.Teleport
	local character, team = readyFor(player, "Teleport", time)
	local root = character and Targeting.rootOf(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and team and root and humanoid and isFinitePoint(point)) then
		return
	end
	local target = withinReach(root, point :: Vector3, T.Range)
	if not target then
		return
	end
	if math.abs(target.Y - root.Position.Y) > TELEPORT_MAX_RISE then
		return
	end
	-- Never through a fence (owner 2026-10-23): the same rule as the client's
	-- marker, so a point beyond a fence lands just before it.
	local landing = landingSpot(Targeting.stopAtFence(root.Position, target))
	if not landing then
		return
	end
	local has = HeroProgress.masteryCheck(player)
	startCooldown(character, "Teleport", time, MageAbilities.teleportCooldown(has))
	skillFx:FireAllClients("Teleport", root.Position, landing)
	-- Stand on the spot: the root sits HipHeight plus half its height above the feet.
	local standAt = landing + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	character:PivotTo(CFrame.new(standAt) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
end

local ACTIONS: { [string]: (Player, State, number, unknown) -> () } = {
	Pulse = pulse,
	Strike = strike,
	Teleport = teleport,
}

actionEvent.OnServerEvent:Connect(function(player: Player, action: unknown, argument: unknown)
	local state = states[player]
	if not state then
		state = { requestTimes = {}, busyUntil = 0, hits = 0, hitsCharacter = nil }
		states[player] = state
	end
	local time = now()
	if not allowRequest(state, time) then
		return
	end
	if type(action) ~= "string" then
		return
	end
	local handler = ACTIONS[action]
	if handler then
		handler(player, state, time, argument)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
