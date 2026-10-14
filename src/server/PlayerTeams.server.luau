--!strict
-- TEMPORARY until match membership (T05): every player joins Blue and spawns
-- on the Blue pad. T05 replaces this with real Blue/Red slots.
-- The server sets the Team attribute; clients only read it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TEAM = "Blue"

local blueSpawn: SpawnLocation? = nil
for _, item in Workspace:WaitForChild("Arena"):GetDescendants() do
	if item:IsA("SpawnLocation") and item:GetAttribute("Team") == TEAM then
		blueSpawn = item
	end
end

local function join(player: Player)
	player:SetAttribute("Team", TEAM)
	if not blueSpawn then
		return
	end
	player.RespawnLocation = blueSpawn
	-- A character that appeared before this ran may be on the wrong pad.
	if player.Character then
		player.Character:PivotTo(blueSpawn.CFrame + Vector3.new(0, 4, 0))
	end
end

for _, player in Players:GetPlayers() do
	join(player)
end
Players.PlayerAdded:Connect(join)
