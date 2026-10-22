--!strict
-- The one place damage is applied. Anything that hurts anything calls applyDamage.
-- First version of T06's damage gateway: handles minions and structures, which
-- keep their health in the server-owned Health/MaxHealth attributes. Heroes and
-- backdoor protection are added when hero damage exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Targeting = require(ReplicatedStorage.Shared.Targeting)

local CombatService = {}

local MAX_DAMAGE = 10000 -- no single hit is ever this big; anything larger is a bug
-- Callers that scale damage up (level-up picks) cap their hits at this.
CombatService.MaxDamage = MAX_DAMAGE

local diedEvent = Instance.new("BindableEvent")
-- Fires (target: Instance, killer: Instance, killerTeam: string) once, when a
-- target's health reaches 0. The killer is whoever landed the final hit, so
-- last-hit rewards (gold later) read it from here. The killer may already be
-- dead or removed (an archer's arrow still lands after the archer dies).
CombatService.Died = diedEvent.Event

local damagedEvent = Instance.new("BindableEvent")
-- Fires (target: Instance, attacker: Instance, attackerTeam: string, dealt: number)
-- after every hit that deals damage (before Died, if the hit was fatal).
CombatService.Damaged = damagedEvent.Event

-- Development log: prints every death and its killer to Output. Off by default:
-- with a 100-unit horde it floods Output; switch on when debugging kills.
local LOG_DEATHS = false

local function describe(unit: Instance): string
	local team = unit:GetAttribute("Team")
	local kind = unit:GetAttribute("MinionType") or unit:GetAttribute("Kind") or unit.ClassName
	return `{if typeof(team) == "string" then team else "?"} {kind}`
end

local function isValidAmount(amount: number): boolean
	return amount == amount -- false for NaN
		and amount > 0
		and amount <= MAX_DAMAGE
end

function CombatService.getHealth(target: Instance): number
	local health = target:GetAttribute("Health")
	return if typeof(health) == "number" then health else 0
end

function CombatService.isAlive(target: Instance): boolean
	return target.Parent ~= nil and CombatService.getHealth(target) > 0
end

-- Objectives fall in order: a lane's tower, then its inhibitor (barracks), then
-- the core once either inhibitor is down. The rule lives in Targeting.isLocked
-- (shared with the client's target marker) and reads "GuardedBy" from the map.
function CombatService.isLocked(target: Instance): boolean
	return Targeting.isLocked(target, CombatService.isAlive)
end

-- Spawn protection: a hero just back from death takes no damage until the
-- server time in its ProtectedUntil attribute (set by Heroes.server).
local function isProtected(target: Instance): boolean
	local untilTime = target:GetAttribute("ProtectedUntil")
	return typeof(untilTime) == "number" and Workspace:GetServerTimeNow() < untilTime
end

-- Deals damage from an attacker to a target. attackerTeam is captured by the
-- caller when the attack starts, so a delayed hit still knows its side.
-- Returns the damage actually dealt (0 if the hit was refused: bad amount,
-- same team, already dead, locked or spawn-protected).
function CombatService.applyDamage(target: Instance, amount: number, attacker: Instance, attackerTeam: string): number
	if not isValidAmount(amount) then
		return 0
	end
	if target:GetAttribute("Team") == attackerTeam then
		return 0
	end
	if not CombatService.isAlive(target) or CombatService.isLocked(target) or isProtected(target) then
		return 0
	end

	local health = CombatService.getHealth(target)
	local dealt = math.min(amount, health)
	target:SetAttribute("Health", health - dealt)
	damagedEvent:Fire(target, attacker, attackerTeam, dealt)
	if health - dealt <= 0 then
		if LOG_DEATHS then
			print(`[Combat] {describe(target)} killed by {describe(attacker)}`)
		end
		diedEvent:Fire(target, attacker, attackerTeam)
	end
	return dealt
end

return CombatService
