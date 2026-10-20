--!strict
-- Gold (T11, first part; owner 2026-10-20): a player whose hero lands the
-- killing hit on a zombie earns Config.Gold.PerLastHit. The total lives on the
-- server and is shown on the player's screen through the Player attribute
-- "Gold" (server-written, display only). Nothing spends it yet; it is kept for
-- the session and not saved.
--
-- Remote: GoldGained (server -> that player only): (amount: number, where: Vector3)
--   so the player's screen can show a "+1" rising from the kill. Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

local goldOf: { [Player]: number } = {}

local gainedEvent = Instance.new("RemoteEvent")
gainedEvent.Name = "GoldGained"
gainedEvent.Parent = ReplicatedStorage

local function setGold(player: Player, amount: number)
	goldOf[player] = amount
	player:SetAttribute("Gold", amount)
end

CombatService.Died:Connect(function(target: Instance, killer: Instance)
	if target:GetAttribute("Kind") ~= "Minion" or target:GetAttribute("Team") ~= Config.Teams.Zombies then
		return
	end
	local player = if killer:IsA("Model") then Players:GetPlayerFromCharacter(killer) else nil
	if player and goldOf[player] then
		local amount = Config.Gold.PerLastHit
		setGold(player, goldOf[player] + amount)
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			gainedEvent:FireClient(player, amount, root.Position)
		end
	end
end)

local function onPlayer(player: Player)
	setGold(player, 0)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	goldOf[player] = nil
end)
