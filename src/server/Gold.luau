--!strict
-- Gold (T11; owner 2026-10-20 / 2026-10-21): each player's own Gold.
--  * Earned: a player whose hero lands the killing hit on a zombie gets
--    Config.Gold.PerLastHit.
--  * Every player starts with Config.Gold.Starting (TEMPORARY test amount).
--  * Spent: Gold.spend (base upgrades, BaseUpgrades.luau).
--  * Kills: the same killing hits are counted in the Player attribute "Kills"
--    (zombies the player's hero finished), shown on the Tab scoreboard.
-- The total lives on the server and is shown on the player's screen through the
-- Player attribute "Gold" (server-written, display only). Kept for the session
-- and not saved. A ModuleScript so other server code can spend Gold; it starts
-- counting when first required (BaseUpgrades requires it).
--
-- Remote: GoldGained (server -> that player only): (amount: number, where: Vector3)
--   so the player's screen can show a "+1" rising from the kill. Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

local Gold = {}

local goldOf: { [Player]: number } = {}
local killsOf: { [Player]: number } = {}

local gainedEvent = Instance.new("RemoteEvent")
gainedEvent.Name = "GoldGained"
gainedEvent.Parent = ReplicatedStorage

local function setGold(player: Player, amount: number)
	goldOf[player] = amount
	player:SetAttribute("Gold", amount)
end

function Gold.get(player: Player): number
	return goldOf[player] or 0
end

-- Gives the player `amount` Gold (DevTools; kills add theirs below).
function Gold.add(player: Player, amount: number)
	local current = goldOf[player]
	if current and amount > 0 then
		setGold(player, current + amount)
	end
end

-- Takes `amount` from the player if they have that much. Returns whether it did.
function Gold.spend(player: Player, amount: number): boolean
	local current = goldOf[player]
	if not current or amount < 0 or current < amount then
		return false
	end
	setGold(player, current - amount)
	return true
end

CombatService.Died:Connect(function(target: Instance, killer: Instance)
	if target:GetAttribute("Kind") ~= "Minion" or target:GetAttribute("Team") ~= Config.Teams.Zombies then
		return
	end
	local player = if killer:IsA("Model") then Players:GetPlayerFromCharacter(killer) else nil
	if player and goldOf[player] then
		killsOf[player] = (killsOf[player] or 0) + 1
		player:SetAttribute("Kills", killsOf[player])
		local amount = Config.Gold.PerLastHit
		setGold(player, goldOf[player] + amount)
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			gainedEvent:FireClient(player, amount, root.Position)
		end
	end
end)

local function onPlayer(player: Player)
	setGold(player, Config.Gold.Starting)
	killsOf[player] = 0
	player:SetAttribute("Kills", 0)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	goldOf[player] = nil
	killsOf[player] = nil
end)

return Gold
