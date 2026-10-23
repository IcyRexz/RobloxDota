--!strict
-- Every player is on our side (Config.Teams.Defenders). The server sets the
-- Team attribute; clients only read it.
-- Where each new character appears (first spawn and every respawn): on our
-- base's spawn pad for a player in the battle (Match.inBattle), otherwise in
-- the lobby courtyard (T05, owner 2026-10-23). Each player's RespawnLocation
-- follows that (base pad or Lobby.SpawnLocation) so Roblox's own placement
-- agrees, and every character is also placed here (Spawns.luau), since Roblox
-- may load a character before RespawnLocation is updated.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lobby = require(script.Parent.Lobby)
local Match = require(script.Parent.Match)
local Spawns = require(script.Parent.Spawns)

local TEAM = Config.Teams.Defenders

local function updateRespawn(player: Player)
	local pad = if Match.inBattle(player) then Spawns.BasePad else Lobby.SpawnLocation
	if pad then
		player.RespawnLocation = pad
	end
end

local function join(player: Player)
	player:SetAttribute("Team", TEAM)
	updateRespawn(player)
	player:GetAttributeChangedSignal("InParty"):Connect(function()
		updateRespawn(player)
	end)
	local function place(character: Model)
		updateRespawn(player)
		if Match.inBattle(player) then
			Spawns.toBase(character)
		else
			Spawns.toLobby(character)
		end
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(place, character)
	end)
	if player.Character then
		task.spawn(place, player.Character)
	end
end

Workspace:GetAttributeChangedSignal("MatchPhase"):Connect(function()
	for _, player in Players:GetPlayers() do
		updateRespawn(player)
	end
end)

for _, player in Players:GetPlayers() do
	join(player)
end
Players.PlayerAdded:Connect(join)
