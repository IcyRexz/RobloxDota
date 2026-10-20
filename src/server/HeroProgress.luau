--!strict
-- In-match XP, levels and rogue-like talent picks for each player (owner
-- 2026-10-20 / 2026-10-21; numbers and talents in Config.Hero.Leveling,
-- Config.Hero.Talents).
--  * Every zombie that dies (killed by anyone: players, minions, towers) gives
--    every player XpPerZombieDeath. Levels stop at MaxLevel (25).
--  * Each level-up adds one pending pick.
--  * Three card slots. The first offer is Config.Hero.FirstOffers (the three
--    ability unlocks in slots 1, 2, 3). Picking a slot applies that talent and
--    replaces ONLY that slot's card with a random talent not already on offer
--    (stat talents can repeat; an ability, once unlocked, is never offered again).
--  * Stat talents multiply their stat (picks stack); ability talents unlock the
--    ability (HeroActions checks HeroProgress.hasSkill).
-- Progress lives on the server and is kept for the session (dying does not
-- reset it); saved progression is a separate, later task (T20).
-- Player attributes for the HUD and Character Menu (display only, server-written):
--   Level, Xp, XpToNext (0 at max level), UpgradesPending,
--   Offer1, Offer2, Offer3 (talent ids on the cards),
--   <id>Picks for each stat talent, Has<Skill> for each unlocked ability,
--   StatMaxHealth, StatAttackDamage, StatMoveSpeed, StatAttackSpeed (attacks per
--   second), StatAttackRange (studs): the values the game actually uses.
--
-- Remote: ChooseUpgrade (client -> server): (card slot: 1, 2 or 3). Ignored
--   unless it is a whole number 1-3, a pick is pending and the player is within
--   the request limit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatService = require(script.Parent.CombatService)
local Config = require(ReplicatedStorage.Shared.Config)

local HeroConfig = Config.Hero
local Leveling = HeroConfig.Leveling
local Talents = HeroConfig.Talents

local MIN_CHOICE_GAP = 0.2 -- seconds between accepted picks per player
local SLOTS = 3

local HeroProgress = {}

type Progress = {
	level: number,
	xp: number,
	pending: number,
	multipliers: { [string]: number }, -- stat talent id -> current multiplier
	picks: { [string]: number }, -- stat talent id -> times taken
	skills: { [string]: boolean }, -- unlocked abilities
	offers: { string }, -- talent id on each card slot
	lastChoiceAt: number,
}
local progressOf: { [Player]: Progress } = {}

local function xpToNext(level: number): number
	if level >= Leveling.MaxLevel then
		return 0 -- max level: no more XP needed
	end
	local steps = Leveling.XpToLevel
	return steps[math.min(level, #steps)]
end

-- Current multiplier for a stat talent id (1 if never picked).
function HeroProgress.multiplier(player: Player, id: string): number
	local progress = progressOf[player]
	return if progress then progress.multipliers[id] or 1 else 1
end

function HeroProgress.hasSkill(player: Player, id: string): boolean
	local progress = progressOf[player]
	return progress ~= nil and progress.skills[id] == true
end

function HeroProgress.maxHealth(player: Player): number
	return math.round(HeroConfig.MaxHealth * HeroProgress.multiplier(player, "Health"))
end

function HeroProgress.walkSpeed(player: Player): number
	return HeroConfig.WalkSpeed * HeroProgress.multiplier(player, "MoveSpeed")
end

-- Any damage scaled by the player's Damage talents, capped at the damage
-- gateway's limit (stacked picks grow without end, and a bigger hit would be
-- refused outright).
function HeroProgress.scaledDamage(player: Player, base: number): number
	return math.min(base * HeroProgress.multiplier(player, "Attack"), CombatService.MaxDamage)
end

function HeroProgress.attackDamage(player: Player): number
	return HeroProgress.scaledDamage(player, HeroConfig.Pulse.Damage)
end

local function publish(player: Player, progress: Progress)
	player:SetAttribute("Level", progress.level)
	player:SetAttribute("Xp", progress.xp)
	player:SetAttribute("XpToNext", xpToNext(progress.level))
	player:SetAttribute("UpgradesPending", progress.pending)
	for slot = 1, SLOTS do
		player:SetAttribute(`Offer{slot}`, progress.offers[slot])
	end
	for id, count in progress.picks do
		player:SetAttribute(id .. "Picks", count)
	end
	for id, talent in Talents do
		if talent.kind == "Skill" then
			player:SetAttribute("Has" .. id, progress.skills[id] == true)
		end
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
	for id, talent in Talents do
		if talent.kind == "Stat" then
			multipliers[id] = 1
			picks[id] = 0
		end
	end
	local progress: Progress = {
		level = 1,
		xp = 0,
		pending = 0,
		multipliers = multipliers,
		picks = picks,
		skills = {},
		offers = table.clone(HeroConfig.FirstOffers) :: { string },
		lastChoiceAt = -math.huge,
	}
	progressOf[player] = progress
	publish(player, progress)
	return progress
end

local function addXp(player: Player, amount: number)
	local progress = getProgress(player)
	if progress.level >= Leveling.MaxLevel then
		return
	end
	progress.xp += amount
	while progress.level < Leveling.MaxLevel and progress.xp >= xpToNext(progress.level) do
		progress.xp -= xpToNext(progress.level)
		progress.level += 1
		progress.pending += 1
		print(`[HeroProgress] {player.Name} reached level {progress.level}`)
	end
	if progress.level >= Leveling.MaxLevel then
		progress.xp = 0
	end
	publish(player, progress)
end

-- A random talent for an emptied slot: not already on another card, and not an
-- ability the player already has. Sorted first so the choice is fair and stable.
local function nextOffer(progress: Progress, slot: number): string
	local candidates: { string } = {}
	for id, talent in Talents do
		local onOffer = false
		for other = 1, SLOTS do
			if other ~= slot and progress.offers[other] == id then
				onOffer = true
			end
		end
		if not onOffer and not (talent.kind == "Skill" and progress.skills[id]) then
			table.insert(candidates, id)
		end
	end
	table.sort(candidates)
	return candidates[math.random(1, #candidates)]
end

-- Puts the current stats on a living hero; for the Health talent the hero also
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

chooseEvent.OnServerEvent:Connect(function(player: Player, slot: unknown)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > SLOTS then
		return
	end
	local progress = getProgress(player)
	local now = os.clock()
	if progress.pending <= 0 or now - progress.lastChoiceAt < MIN_CHOICE_GAP then
		return
	end
	local id = progress.offers[slot]
	local talent = Talents[id]
	if not talent then
		return
	end
	progress.lastChoiceAt = now
	progress.pending -= 1
	local oldMaxHealth = HeroProgress.maxHealth(player)
	if talent.kind == "Skill" then
		progress.skills[id] = true
	else
		progress.multipliers[id] = (progress.multipliers[id] or 1) * (talent.factor or 1)
		progress.picks[id] = (progress.picks[id] or 0) + 1
	end
	progress.offers[slot] = nextOffer(progress, slot)
	publish(player, progress)
	applyStats(player, HeroProgress.maxHealth(player) - oldMaxHealth)
	print(`[HeroProgress] {player.Name} took {id} from slot {slot}; slot now offers {progress.offers[slot]}`)
end)

Players.PlayerAdded:Connect(getProgress)
for _, player in Players:GetPlayers() do
	getProgress(player)
end
Players.PlayerRemoving:Connect(function(player)
	progressOf[player] = nil
end)

return HeroProgress
