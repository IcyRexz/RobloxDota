--!strict
-- Flow fields for swarm movement. The battlefield is cut into a grid; for each
-- named field, every open cell stores its walking distance to that field's
-- goal (shortest path around walls and structures). A unit just walks
-- "downhill" from the cell it stands on, so hundreds of units share one cheap
-- calculation instead of each running its own pathfinding.
-- Fields are rebuilt when a structure falls (the space it stood on opens up).
-- The same grid also answers "is the straight line from A to B open?" and gives
-- short detours around obstacles (clearLine, waypointToward), for units walking
-- at an enemy instead of along a field.

local Workspace = game:GetService("Workspace")

local Landscape = require(script.Parent.Landscape)

local SwarmField = {}

local CELL = 4 -- studs per grid cell
local X_MIN, X_MAX = -160, 180 -- area covered by the grid (the base is at -X)
local Z_MIN, Z_MAX = -132, 132
local CLEARANCE = 2 -- studs units keep from walls and structures (full-size bodies)
local GOAL_MARGIN = 6 -- cells within this many studs of a goal's side count as "arrived"
local BLOCK_HEIGHT = 1.5 -- parts whose top is this far above the ground under them are obstacles (floors are not)
local DIAGONAL = math.sqrt(2)
-- Detours: blocked cells this close to either end of a line are ignored (a unit
-- brushing a wall, or walking up to a structure's side, which is itself blocked).
local END_IGNORE = CLEARANCE + CELL
local DETOUR_MAX_CELLS = 400 -- search budget per detour (chases are short), keeps it cheap
local DETOUR_ARRIVE = 6 -- studs from the target where a detour may end

local NX = math.floor((X_MAX - X_MIN) / CELL)
local NZ = math.floor((Z_MAX - Z_MIN) / CELL)

export type FieldSpec = {
	-- Structures to walk to (any of them); ones that no longer exist are skipped.
	goals: () -> { BasePart },
	-- Extra areas treated as walls for this field only (e.g. the other base opening).
	closed: { BasePart },
}

local arena = Workspace:WaitForChild("Arena")
local blocked: { boolean } = {}
local specs: { [string]: FieldSpec } = {}
local fields: { [string]: { number } } = {}

local function index(ix: number, iz: number): number
	return iz * NX + ix + 1
end

local function cellCentre(ix: number, iz: number): Vector3
	return Vector3.new(X_MIN + (ix + 0.5) * CELL, 0, Z_MIN + (iz + 0.5) * CELL)
end

local function cellOf(position: Vector3): (number, number)
	return math.floor((position.X - X_MIN) / CELL), math.floor((position.Z - Z_MIN) / CELL)
end

local function inGrid(ix: number, iz: number): boolean
	return ix >= 0 and ix < NX and iz >= 0 and iz < NZ
end

-- Ground-plane box of a part (handles rotation), grown by margin on every side.
local function footprint(part: BasePart, margin: number): (number, number, number, number)
	local half = part.Size / 2
	local cf = part.CFrame
	local hx = math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z
	local hz = math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
	local p = part.Position
	return p.X - hx - margin, p.X + hx + margin, p.Z - hz - margin, p.Z + hz + margin
end

-- Calls visit(cellIndex) for every cell whose centre lies inside the box.
local function forCellsIn(x0: number, x1: number, z0: number, z1: number, visit: (number) -> ())
	local ix0 = math.max(0, math.ceil((x0 - X_MIN) / CELL - 0.5))
	local ix1 = math.min(NX - 1, math.floor((x1 - X_MIN) / CELL - 0.5))
	local iz0 = math.max(0, math.ceil((z0 - Z_MIN) / CELL - 0.5))
	local iz1 = math.min(NZ - 1, math.floor((z1 - Z_MIN) / CELL - 0.5))
	for iz = iz0, iz1 do
		for ix = ix0, ix1 do
			visit(index(ix, iz))
		end
	end
end

local function isObstacle(part: BasePart): boolean
	return part.CanCollide
		and part:GetAttribute("Kind") ~= "Boundary"
		and part.Position.Y + part.Size.Y / 2 > Landscape.heightAt(part.Position.X, part.Position.Z) + BLOCK_HEIGHT
end

local function rasterize()
	Landscape.build() -- terrain for units to walk on (trees and rocks are map parts)
	table.clear(blocked)
	for i = 1, NX * NZ do
		blocked[i] = false
	end
	for _, item in arena:GetDescendants() do
		if item:IsA("BasePart") and isObstacle(item) then
			local x0, x1, z0, z1 = footprint(item, CLEARANCE)
			forCellsIn(x0, x1, z0, z1, function(i)
				blocked[i] = true
			end)
		end
	end
end

-- Minimal binary heap of (cell, distance) pairs for Dijkstra.
local function heapPush(heap: { { number } }, cell: number, distance: number)
	table.insert(heap, { cell, distance })
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if heap[parent][2] <= heap[i][2] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function heapPop(heap: { { number } }): { number }?
	local top = heap[1]
	if not top then
		return nil
	end
	local last = table.remove(heap) :: { number }
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local left, right, smallest = i * 2, i * 2 + 1, i
			if left <= #heap and heap[left][2] < heap[smallest][2] then
				smallest = left
			end
			if right <= #heap and heap[right][2] < heap[smallest][2] then
				smallest = right
			end
			if smallest == i then
				break
			end
			heap[smallest], heap[i] = heap[i], heap[smallest]
			i = smallest
		end
	end
	return top
end

local NEIGHBOURS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, DIAGONAL },
	{ 1, -1, DIAGONAL },
	{ -1, 1, DIAGONAL },
	{ -1, -1, DIAGONAL },
}

-- Diagonal steps may not cut a blocked corner.
local function canStep(ix: number, iz: number, dx: number, dz: number, closed: { boolean }): boolean
	local nx, nz = ix + dx, iz + dz
	if not inGrid(nx, nz) or closed[index(nx, nz)] then
		return false
	end
	if dx ~= 0 and dz ~= 0 then
		return not closed[index(ix + dx, iz)] and not closed[index(ix, iz + dz)]
	end
	return true
end

local function compute(spec: FieldSpec): { number }
	local closed = table.clone(blocked)
	for _, area in spec.closed do
		local x0, x1, z0, z1 = footprint(area, 0)
		forCellsIn(x0, x1, z0, z1, function(i)
			closed[i] = true
		end)
	end

	local distance: { number } = table.create(NX * NZ, math.huge)
	local heap: { { number } } = {}
	for _, goal in spec.goals() do
		local x0, x1, z0, z1 = footprint(goal, GOAL_MARGIN)
		forCellsIn(x0, x1, z0, z1, function(i)
			if not closed[i] then
				distance[i] = 0
				heapPush(heap, i, 0)
			end
		end)
	end

	while true do
		local entry = heapPop(heap)
		if not entry then
			break
		end
		local cell, d = entry[1], entry[2]
		if d <= distance[cell] then
			local ix, iz = (cell - 1) % NX, (cell - 1) // NX
			for _, step in NEIGHBOURS do
				if canStep(ix, iz, step[1], step[2], closed) then
					local next = index(ix + step[1], iz + step[2])
					local nd = d + step[3]
					if nd < distance[next] then
						distance[next] = nd
						heapPush(heap, next, nd)
					end
				end
			end
		end
	end
	return distance
end

-- Adds (or replaces) a named field and computes it now.
function SwarmField.define(name: string, spec: FieldSpec)
	if #blocked == 0 then
		rasterize()
	end
	specs[name] = spec
	fields[name] = compute(spec)
end

-- Re-reads the map (a structure fell, so its cells open up) and recomputes every field.
function SwarmField.rebuild()
	rasterize()
	for name, spec in specs do
		fields[name] = compute(spec)
	end
end

-- True if a unit can walk the straight line from a to b without crossing a
-- blocked cell (ignoring cells within END_IGNORE of either end).
function SwarmField.clearLine(a: Vector3, b: Vector3): boolean
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	if length <= 2 * END_IGNORE then
		return true
	end
	local stepLength = CELL / 2
	local d = END_IGNORE
	while d <= length - END_IGNORE do
		local point = a + flat * (d / length)
		local ix, iz = cellOf(point)
		if inGrid(ix, iz) and blocked[index(ix, iz)] then
			return false
		end
		d += stepLength
	end
	return true
end

-- A point to walk toward on the way from `from` to `to` around obstacles, or
-- nil if no way is found within the search budget. A* over the grid; the
-- answer is the farthest cell along the found path that can be walked to in a
-- straight line, so units cut corners smoothly instead of zig-zagging.
function SwarmField.waypointToward(from: Vector3, to: Vector3): Vector3?
	local sx, sz = cellOf(from)
	if not inGrid(sx, sz) then
		return nil
	end
	local start = index(sx, sz)
	local cost: { [number]: number } = { [start] = 0 }
	local cameFrom: { [number]: number } = {}
	local heap: { { number } } = {}
	local function estimate(ix: number, iz: number): number
		local c = cellCentre(ix, iz)
		return Vector3.new(c.X - to.X, 0, c.Z - to.Z).Magnitude / CELL
	end
	heapPush(heap, start, estimate(sx, sz))
	local expanded = 0
	local reached: number? = nil
	while expanded < DETOUR_MAX_CELLS do
		local entry = heapPop(heap)
		if not entry then
			break
		end
		local cell = entry[1]
		local ix, iz = (cell - 1) % NX, (cell - 1) // NX
		expanded += 1
		if estimate(ix, iz) * CELL <= DETOUR_ARRIVE then
			reached = cell
			break
		end
		for _, step in NEIGHBOURS do
			-- The start cell may itself be blocked (unit pressed against a wall).
			if canStep(ix, iz, step[1], step[2], blocked) then
				local next = index(ix + step[1], iz + step[2])
				local nc = cost[cell] + step[3]
				if nc < (cost[next] or math.huge) then
					cost[next] = nc
					cameFrom[next] = cell
					heapPush(heap, next, nc + estimate(ix + step[1], iz + step[2]))
				end
			end
		end
	end
	if not reached then
		return nil
	end
	-- Walk back from the end; keep the farthest cell still in straight sight.
	local path: { number } = {}
	local cell: number? = reached
	while cell and cell ~= start do
		table.insert(path, 1, cell)
		cell = cameFrom[cell]
	end
	local best: Vector3? = nil
	for _, c in path do
		local centre = cellCentre((c - 1) % NX, (c - 1) // NX)
		if best and not SwarmField.clearLine(from, centre) then
			break
		end
		best = centre
	end
	return best
end

-- Walking distance (in cells) from a position to the field's goal; huge if unreachable.
function SwarmField.distance(name: string, position: Vector3): number
	local field = fields[name]
	local ix, iz = cellOf(position)
	if not field or not inGrid(ix, iz) then
		return math.huge
	end
	return field[index(ix, iz)]
end

-- Flat unit direction to walk from this position, or nil if there is nowhere to go
-- (no goal left, or already at the goal). Blends every downhill neighbour so the
-- flow is smooth rather than locked to 8 directions.
function SwarmField.direction(name: string, position: Vector3): Vector3?
	local field = fields[name]
	if not field then
		return nil
	end
	local ix, iz = cellOf(position)
	if not inGrid(ix, iz) then
		-- Outside the grid: head back toward the middle of it.
		local back = Vector3.new((X_MIN + X_MAX) / 2 - position.X, 0, (Z_MIN + Z_MAX) / 2 - position.Z)
		return if back.Magnitude > 0 then back.Unit else nil
	end
	local here = field[index(ix, iz)]
	if here == 0 then
		return nil
	end

	local sum = Vector3.zero
	local bestCell: Vector3? = nil
	local bestDistance = math.huge
	for _, step in NEIGHBOURS do
		local nx, nz = ix + step[1], iz + step[2]
		if inGrid(nx, nz) then
			local d = field[index(nx, nz)]
			if d < bestDistance then
				bestDistance, bestCell = d, cellCentre(nx, nz)
			end
			if here < math.huge and d < here then
				local offset = Vector3.new(step[1], 0, step[2]).Unit
				sum += offset * ((here - d) / step[3])
			end
		end
	end
	if sum.Magnitude > 0.001 then
		return sum.Unit
	end
	-- Standing in a blocked cell (pushed against a wall): step to the best neighbour.
	if bestCell and bestDistance < math.huge then
		local toward = Vector3.new(bestCell.X - position.X, 0, bestCell.Z - position.Z)
		return if toward.Magnitude > 0.001 then toward.Unit else nil
	end
	return nil
end

return SwarmField
