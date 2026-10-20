--!strict
-- Crowd-control on units (zombies and minions): stun, slow and knockback,
-- applied by hero abilities (HeroActions) and obeyed by the unit AI
-- (Minions.server). Server-only state; units are server-owned, so the server
-- may move them. Each unit also gets a "StunnedUntil" attribute (server time)
-- so clients could show it later.

local Workspace = game:GetService("Workspace")

local UnitEffects = {}

type State = { stunUntil: number, slowUntil: number, slowFactor: number }
-- Weak keys: a destroyed unit's entry goes away with it.
local states: { [Instance]: State } = setmetatable({}, { __mode = "k" }) :: any

local function stateOf(unit: Instance): State
	local state = states[unit]
	if not state then
		state = { stunUntil = 0, slowUntil = 0, slowFactor = 1 }
		states[unit] = state
	end
	return state
end

-- The unit stands still and does not attack for `seconds` (longest stun wins).
function UnitEffects.stun(unit: Instance, seconds: number)
	local state = stateOf(unit)
	state.stunUntil = math.max(state.stunUntil, os.clock() + seconds)
	unit:SetAttribute("StunnedUntil", Workspace:GetServerTimeNow() + (state.stunUntil - os.clock()))
end

-- The unit moves at `factor` of its speed for `seconds` (strongest slow wins
-- while it lasts).
function UnitEffects.slow(unit: Instance, factor: number, seconds: number)
	local state = stateOf(unit)
	local now = os.clock()
	if now >= state.slowUntil or factor < state.slowFactor then
		state.slowFactor = factor
	end
	state.slowUntil = math.max(state.slowUntil, now + seconds)
end

function UnitEffects.isStunned(unit: Instance): boolean
	local state = states[unit]
	return state ~= nil and os.clock() < state.stunUntil
end

-- Share of normal move speed right now (1 = not slowed).
function UnitEffects.speedFactor(unit: Instance): number
	local state = states[unit]
	if state and os.clock() < state.slowUntil then
		return state.slowFactor
	end
	return 1
end

-- Throws the unit away from `from` (flat) at `speed`, with a small hop, and
-- stuns it for `stun` seconds so its AI does not walk straight back.
function UnitEffects.knockback(unit: Model, from: Vector3, speed: number, stun: number)
	local root = unit:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local away = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	end
	UnitEffects.stun(unit, stun)
	root.AssemblyLinearVelocity = away.Unit * speed + Vector3.yAxis * speed * 0.35
end

return UnitEffects
