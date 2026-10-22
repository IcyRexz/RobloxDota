--!strict
-- In-match XP, levels and masteries for each player (owner 2026-10-20 /
-- 2026-10-21; numbers in Config.Hero).
--  * Every zombie that dies (killed by anyone: players, minions, towers) gives
--    every player XpPerDeath for its kind. Each level needs a little more XP
--    than the last (FirstLevelXp, XpGrowth). Levels stop at MaxLevel (25).
--  * Each level-up raises max health and damage by Config.Hero.Growth (no
--    choices); the hero heals by the max health gained.
--  * Reaching a level in MasteryLevels (5, 10, 15, 20, 25) gives one mastery
--    point, spent on any untaken tile of the 3x3 mastery grid
--    (Config.Hero.Masteries). HeroActions reads HeroProgress.hasMastery.
--    Stat masteries: Vitality (max health) and Arcane Power (all damage).
--  * Army buffs (owner 2026-10-21): the Mage's base buff, Storm Banner (our
--    soldiers' damage, while the player is in the match), and the War Drums /
--    Fortify masteries (our soldiers' attack speed / health) go to
--    BaseUpgrades.setArmy. Each counts once, however many players have it.
-- Progress lives on the server and is kept for the session (dying does not
-- reset it); saved progression is a separate, later task (T20).
-- Player attributes for the HUD and Character Menu (display only, server-written):
--   Level, Xp, XpToNext (0 at max level), MasteryPoints (picks waiting),
--   Mastery<id> (true once taken),
--   StatMaxHealth, StatHealthRegen (health per second), StatAttackDamage, StatMoveSpeed, StatAttackSpeed (attacks per
--   second), StatAttackRange (studs): the values the game actually uses.
--
-- Remote: ChooseMastery (client -> server): (mastery id: string). Ignored unless
--   it names a mastery not yet taken, a point is waiting and the player is
--   within the request limit.
-- Remote: MasteryPicked (server -> client only; the server never listens):
--   (player, mastery id) when a pick is accepted, for everyone's popup
--   (owner 2026-10-23).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseUpgrades = require(script.Parent.BaseUpgrades)
local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)
local MageAbilities = require(ReplicatedStorage.Shared.MageAbilities)

local HeroConfig = Config.Hero
local Leveling = HeroConfig.Leveling
local Bonus = HeroConfig.MasteryBonus

local MIN_CHOICE_GAP = 0.2 -- seconds between accepted picks per player

local HeroProgress = {}

type Progress = {
	level: number,
	xp: number,
	points: number, -- mastery picks waiting
	masteries: { [string]: boolean },
	lastChoiceAt: number,
}
local progressOf: { [Player]: Progress } = {}

local function xpToNext(level: number): number
	if level >= Leveling.MaxLevel then
		return 0 -- max level: no more XP needed
	end
	return Leveling.FirstLevelXp + Leveling.XpGrowth * (level - 1)
end

local function isMasteryLevel(level: number): boolean
	return table.find(HeroConfig.MasteryLevels, level) ~= nil
end

local function levelOf(player: Player): number
	local progress = progressOf[player]
	return if progress then progress.level else 1
end

function HeroProgress.level(player: Player): number
	return levelOf(player)
end

function HeroProgress.hasMastery(player: Player, id: string): boolean
	local progress = progressOf[player]
	return progress ~= nil and progress.masteries[id] == true
end

-- A check function for MageAbilities (the shared mastery rules).
function HeroProgress.masteryCheck(player: Player): MageAbilities.HasMastery
	return function(id: string): boolean
		return HeroProgress.hasMastery(player, id)
	end
end

local function bonusIf(player: Player, id: string, share: number): number
	return if HeroProgress.hasMastery(player, id) then 1 + share else 1
end

function HeroProgress.maxHealth(player: Player): number
	local grown = HeroConfig.MaxHealth + HeroConfig.Growth.MaxHealth * (levelOf(player) - 1)
	return math.round(grown * bonusIf(player, "Vitality", Bonus.Vitality))
end

-- Health per second (no growth or masteries change it yet).
function HeroProgress.healthRegen(_player: Player): number
	return HeroConfig.HealthRegen
end

function HeroProgress.walkSpeed(_player: Player): number
	return HeroConfig.WalkSpeed
end

function HeroProgress.attackDamage(player: Player): number
	local grown = HeroConfig.Pulse.Damage + HeroConfig.Growth.Damage * (levelOf(player) - 1)
	return grown * bonusIf(player, "ArcanePower", Bonus.ArcanePower)
end

-- An ability's level-1 damage grown in step with the basic attack (level and
-- Arcane Power), capped at
-- the damage gateway's limit (a bigger hit would be refused outright).
function HeroProgress.scaledDamage(player: Player, base: number): number
	local share = HeroProgress.attackDamage(player) / HeroConfig.Pulse.Damage
	return math.min(base * share, CombatService.MaxDamage)
end

local function publish(player: Player, progress: Progress)
	player:SetAttribute("Level", progress.level)
	player:SetAttribute("Xp", progress.xp)
	player:SetAttribute("XpToNext", xpToNext(progress.level))
	player:SetAttribute("MasteryPoints", progress.points)
	for _, info in HeroConfig.Masteries do
		player:SetAttribute("Mastery" .. info.id, progress.masteries[info.id] == true)
	end
	player:SetAttribute("StatMaxHealth", HeroProgress.maxHealth(player))
	player:SetAttribute("StatHealthRegen", HeroProgress.healthRegen(player))
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
	local progress: Progress = {
		level = 1,
		xp = 0,
		points = 0,
		masteries = {},
		lastChoiceAt = -math.huge,
	}
	progressOf[player] = progress
	publish(player, progress)
	return progress
end

-- Puts the current stats on a living hero; it also gains the extra max health
-- as current health.
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

-- Gives the player XP and levels them up (also used by DevTools).
function HeroProgress.addXp(player: Player, amount: number)
	local progress = getProgress(player)
	if progress.level >= Leveling.MaxLevel then
		return
	end
	local oldMaxHealth = HeroProgress.maxHealth(player)
	progress.xp += amount
	while progress.level < Leveling.MaxLevel and progress.xp >= xpToNext(progress.level) do
		progress.xp -= xpToNext(progress.level)
		progress.level += 1
		if isMasteryLevel(progress.level) then
			progress.points += 1
		end
		print(`[HeroProgress] {player.Name} reached level {progress.level}`)
	end
	if progress.level >= Leveling.MaxLevel then
		progress.xp = 0
	end
	publish(player, progress)
	applyStats(player, HeroProgress.maxHealth(player) - oldMaxHealth)
end

-- The buff all players together give our soldiers (each kind counts once).
local function refreshArmy()
	local army = { health = 0, damage = 0, attackSpeed = 0 }
	for player in progressOf do
		army.damage = HeroConfig.BaseBuff.Damage -- Storm Banner: any Mage in the match
		if HeroProgress.hasMastery(player, "WarDrums") then
			army.attackSpeed = Bonus.WarDrums
		end
		if HeroProgress.hasMastery(player, "Fortify") then
			army.health = Bonus.Fortify
		end
	end
	BaseUpgrades.setArmy(army)
end

-- Shared XP: any zombie death gives every player XP.
CombatService.Died:Connect(function(target: Instance)
	if target:GetAttribute("Kind") ~= "Minion" or target:GetAttribute("Team") ~= Config.Teams.Zombies then
		return
	end
	local kind = target:GetAttribute("MinionType")
	local xp = (if type(kind) == "string" then Leveling.XpPerDeath[kind] else nil) or Leveling.XpPerDeath.Zombie
	for _, player in Players:GetPlayers() do
		HeroProgress.addXp(player, xp)
	end
end)

local chooseEvent = Instance.new("RemoteEvent")
chooseEvent.Name = "ChooseMastery"
chooseEvent.Parent = ReplicatedStorage

local pickedEvent = Instance.new("RemoteEvent")
pickedEvent.Name = "MasteryPicked"
pickedEvent.Parent = ReplicatedStorage

chooseEvent.OnServerEvent:Connect(function(player: Player, id: unknown)
	local info = MageAbilities.mastery(id)
	if not info then
		return
	end
	local progress = getProgress(player)
	local now = os.clock()
	if progress.points <= 0 or progress.masteries[info.id] or now - progress.lastChoiceAt < MIN_CHOICE_GAP then
		return
	end
	progress.lastChoiceAt = now
	progress.points -= 1
	local oldMaxHealth = HeroProgress.maxHealth(player)
	progress.masteries[info.id] = true
	publish(player, progress)
	applyStats(player, HeroProgress.maxHealth(player) - oldMaxHealth)
	refreshArmy()
	pickedEvent:FireAllClients(player, info.id)
	print(`[HeroProgress] {player.Name} took mastery {info.id}`)
end)

local function onPlayer(player: Player)
	getProgress(player)
	refreshArmy()
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	progressOf[player] = nil
	refreshArmy()
end)

return HeroProgress
