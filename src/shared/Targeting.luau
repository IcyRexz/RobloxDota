--!strict
-- Targeting helpers shared by the server (which decides hits) and the client
-- (which only shows a marker on the target it expects the server to pick).
-- Pure reads of instances and attributes; nothing here changes the game.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Targeting = {}

Targeting.TargetKinds = table.freeze({ Hero = true, Minion = true, Tower = true, Barracks = true, Core = true, Nest = true })
Targeting.StructureKinds = table.freeze({ Tower = true, Barracks = true, Core = true, Nest = true })

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

-- Things attacks pass through (owner decisions 2026-10-20): hills (Terrain) and
-- fences. Fence collision parts block walking, and Roblox always lets raycasts
-- hit a part that collides (CanQuery only works with CanCollide off), so they
-- are excluded here by their Kind attribute. The fence list is read from the
-- map once the game has fully loaded (on a client, parts may still be arriving
-- before that, so it is not kept until then).
local fences: { Instance }? = nil
function Targeting.seeThrough(): { Instance }
	local list: { Instance } = { Workspace.Terrain }
	if not fences then
		local arena = Workspace:FindFirstChild("Arena")
		if arena then
			local found: { Instance } = {}
			for _, item in arena:GetDescendants() do
				if item:IsA("BasePart") and item:GetAttribute("Kind") == "Fence" then
					table.insert(found, item)
				end
			end
			if game:IsLoaded() then
				fences = found
			end
			for _, fence in found do
				table.insert(list, fence)
			end
			return list
		end
	end
	if fences then
		for _, fence in fences do
			table.insert(list, fence)
		end
	end
	return list
end

-- The map's fence collision parts (Kind = "Fence").
function Targeting.fenceParts(): { Instance }
	local list = Targeting.seeThrough()
	table.remove(list, 1) -- Terrain
	return list
end

-- Teleport rule (owner 2026-10-23: follow the marker, never through a fence),
-- shared by the client's landing marker and the server: `to` pulled back along
-- the flat line from `from` to just before the first fence in the way. A tall
-- box is swept so a fence is found on hills too. Keeps `to`'s height.
Targeting.FenceStopMargin = 2.5 -- studs kept between the landing and the fence
local FENCE_SWEEP = Vector3.new(0.5, 14, 0.5)
function Targeting.stopAtFence(from: Vector3, to: Vector3): Vector3
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude < 0.01 then
		return to
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = Targeting.fenceParts()
	local hit = Workspace:Blockcast(CFrame.new(from), FENCE_SWEEP, flat, params)
	if not hit then
		return to
	end
	local stop = from + flat.Unit * math.max(hit.Distance - Targeting.FenceStopMargin, 0)
	return Vector3.new(stop.X, to.Y, stop.Z)
end

-- Nothing solid between two points. Units (minions, characters), hills and
-- fences never block.
function Targeting.hasLineOfSight(target: Instance, from: Vector3, to: Vector3): boolean
	local ignore = Targeting.seeThrough()
	table.insert(ignore, target)
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

-- Every structure in the map, read once the game has fully loaded (the arena
-- also holds hundreds of trees, rocks and fence parts, so it is not re-scanned
-- on every call). Destroyed structures are removed from the map and dropped
-- here; structures added later make it read the map again.
local structureCache: { Instance }? = nil
local cacheWatch: RBXScriptConnection? = nil
local function standingStructures(): { Instance }
	if not structureCache then
		local arena = Workspace:FindFirstChild("Arena")
		if not arena then
			return {}
		end
		local found: { Instance } = {}
		for _, item in arena:GetDescendants() do
			if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
				table.insert(found, item)
			end
		end
		if not game:IsLoaded() then
			return found -- parts may still be arriving: do not keep this list yet
		end
		structureCache = found
		-- A structure added later (a zombie nest, or one put back by the
		-- battlefield reset, T15) means the list is read again next time.
		if not cacheWatch then
			cacheWatch = arena.DescendantAdded:Connect(function(item: Instance)
				if item:IsA("BasePart") and Targeting.StructureKinds[item:GetAttribute("Kind")] then
					structureCache = nil
				end
			end)
		end
	end
	local cache = structureCache :: { Instance }
	for i = #cache, 1, -1 do
		if not cache[i].Parent then
			table.remove(cache, i)
		end
	end
	return cache
end

-- The basic attack's shot, shared so the client can predict exactly what a
-- click will hit (the red marker shows whenever it would) and the server
-- decides with the same rule. A sphere of ShotRadius is swept from the hero's
-- head along `direction` for `range` studs: the first enemy hit (isEnemy says
-- which) is the target; allies are passed through; hills and fences are seen
-- through (seeThrough); anything else (trees, rocks, structures that are not
-- valid targets) stops the shot. Returns the enemy hit (or nil) and where the
-- shot ended.
Targeting.ShotRadius = 1 -- studs; a thin sphere instead of a line, so near misses still hit
local MAX_PASS_THROUGH = 6 -- allies the shot may pass through before giving up

-- The target kind (unit model or structure part) a hit part belongs to.
function Targeting.ownerOf(part: Instance): Instance?
	local instance: Instance? = part
	while instance and instance ~= Workspace do
		if Targeting.TargetKinds[instance:GetAttribute("Kind")] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

function Targeting.castShot(
	character: Model,
	team: string,
	direction: Vector3,
	range: number,
	isEnemy: (Instance) -> boolean
): (Instance?, Vector3)
	local head = character:FindFirstChild("Head")
	local from = if head and head:IsA("BasePart") then head else Targeting.rootOf(character)
	if not from then
		return nil, Vector3.zero
	end
	local origin = from.Position
	local ignore = Targeting.seeThrough()
	table.insert(ignore, character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, MAX_PASS_THROUGH do
		params.FilterDescendantsInstances = ignore
		local result = Workspace:Spherecast(origin, Targeting.ShotRadius, direction * range, params)
		if not result then
			return nil, origin + direction * range
		end
		local owner = Targeting.ownerOf(result.Instance)
		if owner and isEnemy(owner) then
			return owner, result.Position
		end
		if owner and owner:GetAttribute("Team") == team then
			table.insert(ignore, owner) -- an ally: the shot passes through
		else
			return nil, result.Position -- a tree, rock, structure or locked target
		end
	end
	return nil, origin + direction * range
end

-- Every enemy unit worth considering, in priority order: heroes, then minions,
-- then structures. Callers check team, range, health and locks themselves.
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
	return { heroes, minions, table.clone(standingStructures()) }
end

return table.freeze(Targeting)
