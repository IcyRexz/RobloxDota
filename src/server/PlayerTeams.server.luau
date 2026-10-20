--!strict
-- Every player is on our side (Config.Teams.Defenders) and spawns on our pad.
-- T05 (mission flow) takes over membership later; the side never changes.
-- The server sets the Team attribute; clients only read it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local TEAM = Config.Teams.Defenders

local spawnPad: SpawnLocation? = nil
for _, item in Workspace:WaitForChild("Arena"):GetDescendants() do
	if item:IsA("SpawnLocation") and item:GetAttribute("Team") == TEAM then
		spawnPad = item
	end
end

local function join(player: Player)
	player:SetAttribute("Team", TEAM)
	if not spawnPad then
		return
	end
	player.RespawnLocation = spawnPad
	-- A character that appeared before this ran may be on the wrong pad.
	if player.Character then
		player.Character:PivotTo(spawnPad.CFrame + Vector3.new(0, 4, 0))
	end
end

for _, player in Players:GetPlayers() do
	join(player)
end
Players.PlayerAdded:Connect(join)
