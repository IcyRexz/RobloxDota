--!strict
-- In-match XP, levels and rogue-like upgrade picks for each player (owner
-- 2026-10-20; numbers in Config.Hero.Leveling / Config.Hero.Upgrades).
--  * Every zombie that dies (killed by anyone: players, minions, towers) gives
--    every player XpPerZombieDeath (owner 2026-10-20: no last hit needed).
--  * Reaching XpToNext raises the level and adds one pending upgrade pick.
--  * The client asks to spend a pick with an upgrade id (ChooseUpgrade remote);
--    the server checks it and multiplies that stat. Picks stack.
-- Progress lives on the server and is kept for the session (dying does not
-- reset it); saved progression is a separate, later task (T20).
-- Player attributes for the HUD and Character Menu (display only, server-written):
--   Level, Xp, XpToNext, UpgradesPending,
--   <id>Picks for each upgrade id (how many times it was taken),
--   StatMaxHealth, StatAttackDamage, StatMoveSpeed, StatAttackSpeed (attacks per
--   second), StatAttackRange (studs): the values the game actually uses.
--
-- Remote: ChooseUpgrade (client -> server): (upgrade id: string). Ignored unless
--   the id is one of Config.Hero.Upgrades, a pick is pending and the player is
--   within the request limit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

local HeroConfig = Config.Hero
local Leveling = HeroConfig.Leveling
local Upgrades = HeroConfig.Upgrades :: { [string]: number }

local MIN_CHOICE_GAP = 0.2 -- seconds between accepted upgrade requests per player

local HeroProgress = {}

type Progress = {
	level: number,
	xp: number,
	pending: number,
	multipliers: { [string]: number }, -- upgrade id -> current multiplier
	picks: { [string]: number }, -- upgrade id -> times taken
	lastChoiceAt: number,
}
local progressOf: { [Player]: Progress } = {}

local function xpToNext(level: number): number
	local steps = Leveling.XpToLevel
	return steps[math.min(level, #steps)]
end

local function publish(player: Player, progress: Progress)
	player:SetAttribute("Level", progress.level)
	player:SetAttribute("Xp", progress.xp)
	player:SetAttribute("XpToNext", xpToNext(progress.level))
	player:SetAttribute("UpgradesPending", progress.pending)
	for id, count in progress.picks do
		player:SetAttribute(id .. "Picks", count)
	end
	player:SetAttribute("StatMaxHealth", HeroProgress.maxHealth(player))
	player:SetAttribute("StatAttackDamage", HeroProgress.attackDamage(player))
	player:SetAttribute("StatMoveSpeed", HeroProgress.walkSpeed(player))
	player:SetAttribute("StatAttackSpeed", 1 / HeroConfig.Pulse.Cooldown)
	player:SetAttribute("StatAttackRange", HeroConfig.Pulse.Range)
end

local function getProgress(player: Player): Progress
	local existing = progressOf[player]
	if existing then
		return existing
	end
	local multipliers: { [string]: number } = {}
	local picks: { [string]: number } = {}
	for id in Upgrades do
		multipliers[id] = 1
		picks[id] = 0
	end
	local progress: Progress = { level = 1, xp = 0, pending = 0, multipliers = multipliers, picks = picks, lastChoiceAt = -math.huge }
	progressOf[player] = progress
	publish(player, progress)
	return progress
end

-- Current multiplier for an upgrade id (1 if never picked).
function HeroProgress.multiplier(player: Player, id: string): number
	return getProgress(player).multipliers[id] or 1
end

function HeroProgress.maxHealth(player: Player): number
	return math.round(HeroConfig.MaxHealth * HeroProgress.multiplier(player, "Health"))
end

function HeroProgress.walkSpeed(player: Player): number
	return HeroConfig.WalkSpeed * HeroProgress.multiplier(player, "MoveSpeed")
end

-- Capped at the damage gateway's limit: stacked Attack picks grow without end
-- (1.5^14 x 40 is already past it), and a bigger hit would be refused outright.
function HeroProgress.attackDamage(player: Player): number
	return math.min(HeroConfig.Pulse.Damage * HeroProgress.multiplier(player, "Attack"), CombatService.MaxDamage)
end

local function addXp(player: Player, amount: number)
	local progress = getProgress(player)
	progress.xp += amount
	while progress.xp >= xpToNext(progress.level) do
		progress.xp -= xpToNext(progress.level)
		progress.level += 1
		progress.pending += 1
		print(`[HeroProgress] {player.Name} reached level {progress.level}`)
	end
	publish(player, progress)
end

-- Puts the current stats on a living hero; for the Health upgrade the hero also
-- gains the extra max health as current health.
local function applyStats(player: Player, gainedMaxHealth: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and CombatService.isAlive(character)) then
		return
	end
	local maxHealth = HeroProgress.maxHealth(player)
	local health = character:GetAttribute("Health")
	character:SetAttribute("MaxHealth", maxHealth)
	humanoid.MaxHealth = maxHealth
	if typeof(health) == "number" and gainedMaxHealth > 0 then
		character:SetAttribute("Health", math.min(health + gainedMaxHealth, maxHealth))
	end
	humanoid.WalkSpeed = HeroProgress.walkSpeed(player)
end

-- Shared XP: any zombie death gives every player XP.
CombatService.Died:Connect(function(target: Instance)
	if target:GetAttribute("Kind") ~= "Minion" or target:GetAttribute("Team") ~= Config.Teams.Zombies then
		return
	end
	for _, player in Players:GetPlayers() do
		addXp(player, Leveling.XpPerZombieDeath)
	end
end)

local chooseEvent = Instance.new("RemoteEvent")
chooseEvent.Name = "ChooseUpgrade"
chooseEvent.Parent = ReplicatedStorage

chooseEvent.OnServerEvent:Connect(function(player: Player, id: unknown)
	if type(id) ~= "string" or #id > 32 then
		return
	end
	local factor = Upgrades[id]
	if type(factor) ~= "number" then
		return
	end
	local progress = getProgress(player)
	local now = os.clock()
	if progress.pending <= 0 or now - progress.lastChoiceAt < MIN_CHOICE_GAP then
		return
	end
	progress.lastChoiceAt = now
	progress.pending -= 1
	local oldMaxHealth = HeroProgress.maxHealth(player)
	progress.multipliers[id] = (progress.multipliers[id] or 1) * factor
	progress.picks[id] = (progress.picks[id] or 0) + 1
	publish(player, progress)
	applyStats(player, HeroProgress.maxHealth(player) - oldMaxHealth)
	print(`[HeroProgress] {player.Name} chose {id} (x{progress.multipliers[id]})`)
end)

Players.PlayerAdded:Connect(getProgress)
for _, player in Players:GetPlayers() do
	getProgress(player)
end
Players.PlayerRemoving:Connect(function(player)
	progressOf[player] = nil
end)

return HeroProgress
