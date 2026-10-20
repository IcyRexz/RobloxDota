--!strict
-- Hero actions requested by clients: the basic attack (GDD "Pulse") and Zeus's
-- three abilities (owner 2026-10-21; numbers in Config.Hero.Skills), each only
-- after its talent is taken (HeroProgress.hasSkill):
--  * Strike (key 1): (target point: Vector3). Within Range (flat) of the hero.
--    After Delay, every enemy unit within Radius takes Damage, is stunned for
--    StunTime and then slowed (UnitEffects).
--  * Dash (key 2): (direction: Vector3). The hero's own device moves the
--    character (Roblox gives each player their character's movement); the
--    server spends the cooldown and, when the dash ends, knocks back enemy units
--    within PushRadius of where the hero landed.
--  * Ball (key 3): (target: Instance). An enemy within Range of the hero's head
--    in line of sight. Charges for ChargeTime, then the ball flies; Damage and a
--    StunTime stun land on arrival.
-- Ability damage is scaled by the player's Damage talents. Cooldowns are server
-- time in the character's <Ability>ReadyAt attributes (the HUD reads them).
--
-- Aimed shot (owner 2026-10-20): the client sends only the direction it is
-- aiming (the camera's look direction = the crosshair). The server casts the
-- shot itself from the hero's head along that direction, up to Pulse.Range:
-- the first enemy on that line is hit; allies, hills and fences are passed
-- through; trees, rocks and structures stop it; nothing in range = a miss.
-- Every accepted shot spends the cooldown, hit or miss.
--
-- Remote: HeroAction (client -> server): (action name: string, aim direction: Vector3).
--   The direction must be finite and roughly unit length; it is normalised.
-- Remote: HeroAttack (server -> client): (attacker, target or nil, damage dealt,
--   end point) for every shot, so clients can draw the bolt (to the end point)
--   and, on a hit, the flash and damage number. Display only.
-- Remote: SkillFx (server -> clients): ability effects for SkillEffects.client:
--   Strike (point, radius, delay), Dash (hero, duration), DashPush (point,
--   radius), BallCharge (hero, chargeTime), BallFly (hero, target, flightTime);
--   and to the caster only Hit (target, damage dealt) for damage numbers.
-- The swing animation and turning to face the target are done by the
-- attacker's own device (it owns its character's movement); setting the
-- character's CFrame here would snap it back to an out-of-date position.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local HeroProgress = require(script.Parent.HeroProgress)
local UnitEffects = require(script.Parent.UnitEffects)
local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local HeroConfig = Config.Hero
local Pulse = HeroConfig.Pulse
local Skills = HeroConfig.Skills

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

-- Can this hero damage this instance: an enemy target kind, alive, not locked?
local function isEnemyTarget(character: Model, team: string, target: Instance): boolean
	if not Targeting.TargetKinds[target:GetAttribute("Kind")] or target == character then
		return false
	end
	local targetTeam = target:GetAttribute("Team")
	return typeof(targetTeam) == "string"
		and targetTeam ~= team
		and CombatService.isAlive(target)
		and not CombatService.isLocked(target)
end

-- Casts the shot from the hero's head (shared rule in Targeting.castShot, the
-- same one the client uses to show its red marker). Returns the enemy hit (or
-- nil) and where the shot ended.
local function castShot(character: Model, team: string, direction: Vector3): (Instance?, Vector3)
	return Targeting.castShot(character, team, direction, Pulse.Range, function(target)
		return isEnemyTarget(character, team, target)
	end)
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

local function pulse(player: Player, state: State, time: number, aim: unknown)
	local direction = readDirection(aim)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local team = character and character:GetAttribute("Team")
	if not (direction and character and humanoid and typeof(team) == "string") then
		return
	end
	if character:GetAttribute("Kind") ~= "Hero" or not CombatService.isAlive(character) then
		return
	end
	local readyAt = character:GetAttribute("PulseReadyAt")
	if time < state.busyUntil or (typeof(readyAt) == "number" and time < readyAt) then
		return -- still swinging or cooling down; never queued for later
	end

	-- Accepted: cooldown starts now (server time); clients read it for the HUD.
	character:SetAttribute("PulseReadyAt", time + Pulse.Cooldown)
	state.busyUntil = time + Pulse.Windup

	task.delay(Pulse.Windup, function()
		-- The hero must still be this same living character; the shot is cast
		-- now, from where the hero stands at the end of the windup.
		if player.Character ~= character or not CombatService.isAlive(character) then
			return
		end
		local target, endPoint = castShot(character, team, direction)
		local dealt = 0
		if target then
			-- Damage includes the player's Attack level-up picks.
			dealt = CombatService.applyDamage(target, HeroProgress.attackDamage(player), character, team)
		end
		attackEvent:FireAllClients(character, target, dealt, endPoint)
	end)
end

-- Abilities --------------------------------------------------------------------------

-- The player's living hero and team, if the ability is unlocked and off cooldown.
local function readyForSkill(player: Player, skill: string, time: number): (Model?, string?)
	if not HeroProgress.hasSkill(player, skill) then
		return nil, nil
	end
	local character = player.Character
	local team = character and character:GetAttribute("Team")
	if not (character and typeof(team) == "string" and character:GetAttribute("Kind") == "Hero") then
		return nil, nil
	end
	if not CombatService.isAlive(character) then
		return nil, nil
	end
	local readyAt = character:GetAttribute(skill .. "ReadyAt")
	if typeof(readyAt) == "number" and time < readyAt then
		return nil, nil
	end
	return character, team
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

local function strike(player: Player, _state: State, time: number, point: unknown)
	local S = Skills.Strike
	local character, team = readyForSkill(player, "Strike", time)
	local root = character and Targeting.rootOf(character)
	if not (character and team and root and isFinitePoint(point)) then
		return
	end
	local at = point :: Vector3
	if Targeting.planarDistance(at, root.Position) > S.Range + 2 then
		return -- small slack for movement between the client's aim and now
	end
	character:SetAttribute("StrikeReadyAt", time + S.Cooldown)
	skillFx:FireAllClients("Strike", at, S.Radius, S.Delay)
	local damage = HeroProgress.scaledDamage(player, S.Damage)
	task.delay(S.Delay, function()
		for _, unit in enemyUnitsNear(character, team, at, S.Radius) do
			local dealt = CombatService.applyDamage(unit, damage, character, team)
			if dealt > 0 then
				skillFx:FireClient(player, "Hit", unit, dealt)
			end
			if CombatService.isAlive(unit) then
				UnitEffects.stun(unit, S.StunTime)
				UnitEffects.slow(unit, S.SlowFactor, S.StunTime + S.SlowTime)
			end
		end
	end)
end

local function dash(player: Player, _state: State, time: number, aim: unknown)
	local D = Skills.Dash
	local character, team = readyForSkill(player, "Dash", time)
	local direction = readDirection(aim)
	if not (character and team and direction) then
		return
	end
	if Vector3.new(direction.X, 0, direction.Z).Magnitude < 0.1 then
		return -- straight up or down: no flat direction to dash in
	end
	character:SetAttribute("DashReadyAt", time + D.Cooldown)
	skillFx:FireAllClients("Dash", character, D.Duration)
	task.delay(D.Duration + 0.05, function()
		local root = Targeting.rootOf(character)
		if player.Character ~= character or not root or not CombatService.isAlive(character) then
			return
		end
		local landed = root.Position
		skillFx:FireAllClients("DashPush", landed, D.PushRadius)
		for _, unit in enemyUnitsNear(character, team, landed, D.PushRadius) do
			UnitEffects.knockback(unit, landed, D.PushSpeed, D.PushStun)
		end
	end)
end

local function ball(player: Player, _state: State, time: number, target: unknown)
	local B = Skills.Ball
	local character, team = readyForSkill(player, "Ball", time)
	local head = character and character:FindFirstChild("Head")
	if not (character and team and head and head:IsA("BasePart") and typeof(target) == "Instance") then
		return
	end
	if not isEnemyTarget(character, team, target) then
		return
	end
	local point = Targeting.aimPointOf(target, head.Position)
	if not point or (point - head.Position).Magnitude > B.Range + 2 then
		return
	end
	if not Targeting.hasLineOfSight(target, head.Position, point) then
		return
	end
	character:SetAttribute("BallReadyAt", time + B.Cooldown)
	skillFx:FireAllClients("BallCharge", character, B.ChargeTime)
	local damage = HeroProgress.scaledDamage(player, B.Damage)
	task.delay(B.ChargeTime, function()
		-- The hero must still be alive, and the target still a valid enemy.
		if player.Character ~= character or not CombatService.isAlive(character) then
			return
		end
		if not isEnemyTarget(character, team, target) then
			return
		end
		local from = head.Position
		local to = Targeting.aimPointOf(target, from) or from
		local flightTime = (to - from).Magnitude / B.Speed
		skillFx:FireAllClients("BallFly", character, target, flightTime)
		task.delay(flightTime, function()
			local dealt = CombatService.applyDamage(target, damage, character, team)
			if dealt > 0 then
				skillFx:FireClient(player, "Hit", target, dealt)
			end
			if target:IsA("Model") and CombatService.isAlive(target) then
				UnitEffects.stun(target, B.StunTime)
			end
		end)
	end)
end

local ACTIONS: { [string]: (Player, State, number, unknown) -> () } = {
	Pulse = pulse,
	Strike = strike,
	Dash = dash,
	Ball = ball,
}

actionEvent.OnServerEvent:Connect(function(player: Player, action: unknown, argument: unknown)
	local state = states[player]
	if not state then
		state = { requestTimes = {}, busyUntil = 0 }
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
