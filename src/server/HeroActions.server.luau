--!strict
-- Hero actions requested by clients. So far: the basic attack (GDD "Pulse").
-- The client only says "I want to attack"; the server decides everything else:
-- whether the hero may act, the target (nearest enemy hero, else minion, else
-- unlocked structure, in range and line of sight), the cooldown and the damage.
--
-- Remote: HeroAction (client -> server): (action name: string, target hint: Instance?).
--   The hint is the target the player's marker is on. The server uses it only
--   if it passes every check below; otherwise it picks its own target.
-- Remote: HeroAttack (server -> client): (attacker, target, damage dealt) when a
--   hit lands, so clients can draw the lightning and damage numbers. Display only.
-- The swing animation and turning to face the target are done by the
-- attacker's own device (it owns its character's movement); setting the
-- character's CFrame here would snap it back to an out-of-date position.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
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

-- Can this hero hit this target right now: enemy, alive, not locked, in range,
-- in line of sight? Returns the aim point when it can.
local function canHit(character: Model, team: string, target: Instance): Vector3?
	if not Targeting.TargetKinds[target:GetAttribute("Kind")] or target == character then
		return nil
	end
	if target:GetAttribute("Team") == team or not CombatService.isAlive(target) then
		return nil
	end
	if typeof(target:GetAttribute("Team")) ~= "string" or CombatService.isLocked(target) then
		return nil
	end
	local root = Targeting.rootOf(character)
	local point = if root then Targeting.aimPointOf(target, root.Position) else nil
	if not (root and point) or Targeting.planarDistance(point, root.Position) > Pulse.Range then
		return nil
	end
	return if Targeting.hasLineOfSight(target, root.Position, point) then point else nil
end

-- The nearest hittable target, taking heroes first, then minions, then
-- structures (ties: lowest name, so every run picks the same).
local function chooseTarget(character: Model, team: string): Instance?
	local root = Targeting.rootOf(character) :: BasePart
	for _, group in Targeting.candidateGroups() do
		local best: Instance? = nil
		local bestDistance = math.huge
		for _, target in group do
			local point = canHit(character, team, target)
			if point then
				local distance = Targeting.planarDistance(point, root.Position)
				if distance < bestDistance or (distance == bestDistance and best and target.Name < best.Name) then
					best, bestDistance = target, distance
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

local function pulse(player: Player, state: State, time: number, hint: unknown)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local team = character and character:GetAttribute("Team")
	if not (character and humanoid and typeof(team) == "string") then
		return
	end
	if character:GetAttribute("Kind") ~= "Hero" or not CombatService.isAlive(character) then
		return
	end
	local readyAt = character:GetAttribute("PulseReadyAt")
	if time < state.busyUntil or (typeof(readyAt) == "number" and time < readyAt) then
		return -- still swinging or cooling down; never queued for later
	end
	local target: Instance? = nil
	if typeof(hint) == "Instance" and canHit(character, team, hint) then
		target = hint
	else
		target = chooseTarget(character, team)
	end
	if not target then
		return -- no target: no swing, no cooldown
	end

	-- Accepted: cooldown starts now (server time); clients read it for the HUD.
	character:SetAttribute("PulseReadyAt", time + Pulse.Cooldown)
	state.busyUntil = time + Pulse.Windup

	task.delay(Pulse.Windup, function()
		-- The hero must still be this same living character, and the target must
		-- still be hittable (range and line of sight are checked again).
		if player.Character ~= character or not CombatService.isAlive(character) then
			return
		end
		if not canHit(character, team, target) then
			return -- missed: the cooldown stays spent
		end
		local dealt = CombatService.applyDamage(target, Pulse.Damage, character, team)
		attackEvent:FireAllClients(character, target, dealt)
	end)
end

local ACTIONS: { [string]: (Player, State, number, unknown) -> () } = {
	Pulse = pulse,
}

actionEvent.OnServerEvent:Connect(function(player: Player, action: unknown, hint: unknown)
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
		handler(player, state, time, hint)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
