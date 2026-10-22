--!strict
-- Gold (T11; owner 2026-10-20 / 2026-10-21; economy rework 2026-10-23): each
-- player's own Gold.
--  * Earned: every zombie death (killed by anyone) gives every player
--    Config.Gold.PerDeath for its kind; the player whose hero landed the
--    killing hit also gets LastHitBonus. A fallen Zombie Nest gives every
--    player PerNest.
--  * Every player starts with Config.Gold.Starting.
--  * Studio only: each minute Output shows zombie deaths, Gold and levels for
--    that minute ([Economy] lines), for tuning the numbers.
--  * Spent: Gold.spend (base upgrades, BaseUpgrades.luau).
--  * Kills: the same killing hits are counted in the Player attribute "Kills"
--    (zombies the player's hero finished), shown on the Tab scoreboard.
-- The total lives on the server and is shown on the player's screen through the
-- Player attribute "Gold" (server-written, display only). Kept for the session
-- and not saved. A ModuleScript so other server code can spend Gold; it starts
-- counting when first required (BaseUpgrades requires it).
--
-- Remote: GoldGained (server -> that player only): (amount: number, where: Vector3)
--   so the killer's screen can show "+N" rising from their kill (shared Gold
--   from other kills only ticks the counter). Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- For the per-minute tuning log.
local minuteDeaths = 0
local minuteGold: { [Player]: number } = {}

local function give(player: Player, amount: number)
	local current = goldOf[player]
	if current and amount > 0 then
		setGold(player, current + amount)
		minuteGold[player] = (minuteGold[player] or 0) + amount
	end
end

CombatService.Died:Connect(function(target: Instance, killer: Instance)
	if target:GetAttribute("Team") ~= Config.Teams.Zombies then
		return
	end
	local kind = target:GetAttribute("Kind")
	if kind == "Nest" then
		for _, player in Players:GetPlayers() do
			give(player, Config.Gold.PerNest)
		end
		return
	elseif kind ~= "Minion" then
		return
	end
	minuteDeaths += 1
	local unitType = target:GetAttribute("MinionType")
	local share = (if type(unitType) == "string" then Config.Gold.PerDeath[unitType] else nil) or Config.Gold.PerDeath.Zombie
	local killerPlayer = if killer:IsA("Model") then Players:GetPlayerFromCharacter(killer) else nil
	for _, player in Players:GetPlayers() do
		if player ~= killerPlayer then
			give(player, share)
		end
	end
	if killerPlayer and goldOf[killerPlayer] then
		killsOf[killerPlayer] = (killsOf[killerPlayer] or 0) + 1
		killerPlayer:SetAttribute("Kills", killsOf[killerPlayer])
		local amount = share + Config.Gold.LastHitBonus
		give(killerPlayer, amount)
		local root = target:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			gainedEvent:FireClient(killerPlayer, amount, root.Position)
		end
	end
end)

if RunService:IsStudio() then
	task.spawn(function()
		local minute = 0
		while true do
			task.wait(60)
			minute += 1
			local parts: { string } = {}
			for _, player in Players:GetPlayers() do
				local level = player:GetAttribute("Level")
				table.insert(parts, `{player.Name} +{minuteGold[player] or 0} Gold (total {Gold.get(player)}), level {level}`)
			end
			print(`[Economy] minute {minute}: {minuteDeaths} zombie deaths; {table.concat(parts, "; ")}`)
			minuteDeaths = 0
			table.clear(minuteGold)
		end
	end)
end

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
	minuteGold[player] = nil
end)

return Gold
