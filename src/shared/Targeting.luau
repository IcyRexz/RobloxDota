--!strict
-- Targeting helpers shared by the server (which decides hits) and the client
-- (which only shows a marker on the target it expects the server to pick).
-- Pure reads of instances and attributes; nothing here changes the game.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Targeting = {}

Targeting.TargetKinds = table.freeze({ Hero = true, Minion = true, Tower = true, Barracks = true, Core = true })
Targeting.StructureKinds = table.freeze({ Tower = true, Barracks = true, Core = true })

function Targeting.planarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Targeting.rootOf(model: Instance): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The point to measure range to and aim at: a unit's centre, or the nearest
-- point on a structure's side (at the attacker's height).
function Targeting.aimPointOf(target: Instance, from: Vector3): Vector3?
	if target:IsA("BasePart") then
		local centre, half = target.Position, target.Size / 2
		return Vector3.new(
			math.clamp(from.X, centre.X - half.X, centre.X + half.X),
			from.Y,
			math.clamp(from.Z, centre.Z - half.Z, centre.Z + half.Z)
		)
	end
	local root = Targeting.rootOf(target)
	return if root then root.Position else nil
end

-- Objective order, read from the map: a structure's "GuardedBy" attribute names
-- the structures protecting it (comma-separated). It cannot be damaged while ALL
-- of them still stand; once any guard is gone (destroyed structures are removed
-- from the map), it unlocks. An inhibitor lists its lane's tower; the Base Core
-- lists both inhibitors, so it opens when either lane breaks.
-- isAlive is passed in because the server and client check health differently.
function Targeting.isLocked(target: Instance, isAlive: (Instance) -> boolean): boolean
	local guards = target:GetAttribute("GuardedBy")
	local arena = Workspace:FindFirstChild("Arena")
	if typeof(guards) ~= "string" or guards == "" or not arena then
		return false
	end
	for name in string.gmatch(guards, "[^,%s]+") do
		local guard = arena:FindFirstChild(name, true)
		if not (guard and isAlive(guard)) then
			return false
		end
	end
	return true
end

-- Nothing solid between two points. Units (minions, characters) never block.
function Targeting.hasLineOfSight(target: Instance, from: Vector3, to: Vector3): boolean
	local ignore: { Instance } = { target }
	local minions = Workspace:FindFirstChild("Minions")
	if minions then
		table.insert(ignore, minions)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, to - from, params) == nil
end

-- Every enemy unit worth considering, in priority order: heroes, then minions,
-- then structures. Callers check range, health and locks themselves.
function Targeting.candidateGroups(): { { Instance } }
	local heroes: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute("Kind") == "Hero" then
			table.insert(heroes, character)
		end
	end
	local minionFolder = Workspace:FindFirstChild("Minions")
	local minions: { Instance } = if minionFolder then minionFolder:GetChildren() else {}
	local structures: { Instance } = {}
	local arena = Workspace:FindFirstChild("Arena")
	if arena then
		for _, item in arena:GetDescendants() do
			if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
				table.insert(structures, item)
			end
		end
	end
	return { heroes, minions, structures }
end

return table.freeze(Targeting)
