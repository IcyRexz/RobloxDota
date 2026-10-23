--!strict
-- Where a character is put (T05): on our base's PlayerSpawn pad for players
-- in the battle, or in the lobby courtyard (Lobby.luau) for everyone else.
-- Moved here from PlayerTeams.server (owner 2026-10-23: one spawn platform
-- for everyone in the battle): a random spot within PAD_SPREAD of the pad's
-- centre so a party does not stack, feet on the ground found by a ray (the
-- pad itself is invisible and not solid), facing the battlefield (+X).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lobby = require(script.Parent.Lobby)

local PAD_SPREAD = 4 -- studs from the pad's centre, at most
local GROUND_PROBE_UP = 10
local GROUND_PROBE_DOWN = 40

local Spawns = {}

local basePad: SpawnLocation? = nil
for _, item in Workspace:WaitForChild("Arena"):GetDescendants() do
	if item:IsA("SpawnLocation") and item:GetAttribute("Team") == Config.Teams.Defenders then
		basePad = item
	end
end
if not basePad then
	warn("[Spawns] no SpawnLocation with Team = Defenders under Arena")
end
Spawns.BasePad = basePad

-- The ground under a point on the pad (floor or terrain), ignoring the pad
-- itself and every character.
local function groundUnder(position: Vector3, pad: SpawnLocation): number
	local ignore: { Instance } = { pad }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, GROUND_PROBE_UP, 0), Vector3.new(0, -GROUND_PROBE_DOWN, 0), params)
	return if hit then hit.Position.Y else pad.Position.Y + pad.Size.Y / 2
end

-- Stands a character with its feet at `ground`, facing the battlefield. Waits
-- until the character is in the world and one more frame: Roblox moves a
-- freshly loaded character onto its spawn point just after CharacterAdded,
-- which would otherwise undo this (owner 2026-10-23: players appeared on the
-- battlefield instead of in the lobby). Yields; call it in its own thread.
local function stand(character: Model, ground: Vector3)
	if not character:IsDescendantOf(Workspace) then
		character.AncestryChanged:Wait()
	end
	RunService.Heartbeat:Wait()
	if not character:IsDescendantOf(Workspace) then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	local position = ground + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	character:PivotTo(CFrame.lookAt(position, position + Vector3.xAxis))
end

-- On our base's spawn pad (the battle).
function Spawns.toBase(character: Model)
	local pad = basePad
	if not pad then
		return
	end
	local angle = math.random() * 2 * math.pi
	local distance = math.random() * PAD_SPREAD
	local spot = pad.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	stand(character, Vector3.new(spot.X, groundUnder(spot, pad), spot.Z))
end

-- In the lobby courtyard.
function Spawns.toLobby(character: Model)
	stand(character, Lobby.spawnSpot())
end

return Spawns
