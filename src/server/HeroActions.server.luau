--!strict
-- Hero actions requested by clients. So far: the basic attack (GDD "Pulse").
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
-- The swing animation and turning to face the target are done by the
-- attacker's own device (it owns its character's movement); setting the
-- character's CFrame here would snap it back to an out-of-date position.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local HeroProgress = require(script.Parent.HeroProgress)
local Config = require(ReplicatedStorage.Shared.Config)
local Targeting = require(ReplicatedStorage.Shared.Targeting)

local HeroConfig = Config.Hero
local Pulse = HeroConfig.Pulse

local actionEvent = Instance.new("RemoteEvent")
actionEvent.Name = "HeroAction"
actionEvent.Parent = ReplicatedStorage

local attackEvent = Instance.new("RemoteEvent")
attackEvent.Name = "HeroAttack"
attackEvent.Parent = ReplicatedStorage

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

local ACTIONS: { [string]: (Player, State, number, unknown) -> () } = {
	Pulse = pulse,
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
