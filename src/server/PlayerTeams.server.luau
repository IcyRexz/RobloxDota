--!strict
-- Every player is on our side (Config.Teams.Defenders) and spawns on our pad.
-- T05 (mission flow) takes over membership later; the side never changes.
-- The server sets the Team attribute; clients only read it.
--
-- One spawn platform for everyone (owner 2026-10-23): the PlayerSpawn pad in
-- the base. RespawnLocation points at it, and every new character (first
-- spawn and every respawn) is also moved onto it here, because Roblox may load
-- a character before RespawnLocation is set (Heroes.server loads characters)
-- and any other SpawnLocation left in the place must never be used. Each
-- character lands at a random spot within PAD_SPREAD of the pad's centre so a
-- party does not stack, standing on the ground found by a ray (the pad itself
-- is invisible and not solid).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local TEAM = Config.Teams.Defenders
local PAD_SPREAD = 4 -- studs from the pad's centre, at most
local GROUND_PROBE_UP = 10
local GROUND_PROBE_DOWN = 40

local spawnPad: SpawnLocation? = nil
for _, item in Workspace:WaitForChild("Arena"):GetDescendants() do
	if item:IsA("SpawnLocation") and item:GetAttribute("Team") == TEAM then
		spawnPad = item
	end
end
if not spawnPad then
	warn("[PlayerTeams] no SpawnLocation with Team = Defenders under Arena; players spawn wherever Roblox puts them")
end

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

-- Stands a new character on the pad: feet on the ground under its spot.
local function placeOnPad(character: Model)
	local pad = spawnPad
	if not pad then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	local angle = math.random() * 2 * math.pi
	local distance = math.random() * PAD_SPREAD
	local spot = pad.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local ground = groundUnder(spot, pad)
	local position = Vector3.new(spot.X, ground + humanoid.HipHeight + root.Size.Y / 2, spot.Z)
	-- Facing the battlefield: our base is at the -X end, the zombies at +X.
	character:PivotTo(CFrame.lookAt(position, position + Vector3.xAxis))
end

local function join(player: Player)
	player:SetAttribute("Team", TEAM)
	if spawnPad then
		player.RespawnLocation = spawnPad
	end
	player.CharacterAdded:Connect(placeOnPad)
	if player.Character then
		task.spawn(placeOnPad, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	join(player)
end
Players.PlayerAdded:Connect(join)
