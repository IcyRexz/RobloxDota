--!strict
-- Base upgrades (owner 2026-10-21; numbers in Config.Base): players spend their
-- own Gold at the Upgrade Workbench.
--  * Three categories (Config.Base.Categories): Buildings, Warriors and
--    Archers, each a 3x2 grid of upgrades (Config.Base.Upgrades), each bought
--    once for its own cost, in any order. BaseUpgradeRules works out what they
--    do.
--  * Warriors / Archers improve our soldiers of that kind. Minions.server
--    reads BaseUpgrades.unitMods for new soldiers and listens to
--    BaseUpgrades.Changed to update living ones. Zombies never get them.
--  * Buildings improve our towers, barracks and Base Core. Max health is set
--    here from each building's map max health (kept in its BaseMaxHealth
--    attribute); a health upgrade also heals the building by what it gains.
--    Structures.server reads BaseUpgrades.towerStats for every shot.
--  * Army buffs from heroes (Storm Banner, War Drums, Fortify) are set by
--    HeroProgress through BaseUpgrades.setArmy and added to every soldier.
--  * Everything bought is shared by our whole side (every player is a
--    Defender) and lasts for one match: BaseUpgrades.reset() clears it (at
--    server start and at every battlefield reset, Match.onReset).
-- Published for the HUD/menu (display only), as ReplicatedStorage attributes:
--   Owned<UpgradeId> (true once bought); <CategoryId>Label ("2/6");
--   ArmyHealth, ArmyDamage, ArmyAttackSpeed (the current army buff shares).
--
-- Remote: BaseUpgrade (client -> server): (category id: string, upgrade id:
--   string). Accepted only for a known, not-yet-bought upgrade, from a living
--   hero within Config.Base.WorkbenchRange of the workbench, with enough Gold,
--   at most once per MIN_REQUEST_GAP. The Gold is taken by the server.
-- Remote: BaseUpgradeResult (server -> that player): (result: string, category
--   id, detail). Results: "Bought" (detail = upgrade id), "NotEnoughGold",
--   "Owned", "TooFar".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatService = require(script.Parent.CombatService)
local Gold = require(script.Parent.Gold)
local Match = require(script.Parent.Match)
local BaseUpgradeRules = require(ReplicatedStorage.Shared.BaseUpgradeRules)
local Config = require(ReplicatedStorage.Shared.Config)

local BaseConfig = Config.Base
local DEFENDERS = Config.Teams.Defenders
local MIN_REQUEST_GAP = 0.25 -- seconds between accepted requests per player
local BUILDING_KINDS = { Tower = true, Barracks = true, Core = true }

local arena = Workspace:WaitForChild("Arena")

local BaseUpgrades = {}

local owned: { [string]: boolean } = {} -- upgrade id -> bought
local army: BaseUpgradeRules.Army = { health = 0, damage = 0, attackSpeed = 0 }

local changed = Instance.new("BindableEvent")
-- Fires (category id) after anything is bought, and for every category on reset.
BaseUpgrades.Changed = changed.Event

local function isOwned(id: string): boolean
	return owned[id] == true
end

-- Everything bought for soldiers of `kind` on `team` (nothing for zombies).
function BaseUpgrades.unitMods(team: string, kind: string): BaseUpgradeRules.UnitMods
	if team ~= DEFENDERS then
		return BaseUpgradeRules.unitMods(kind, function()
			return false
		end)
	end
	return BaseUpgradeRules.unitMods(kind, isOwned, army)
end

-- A tower's shooting numbers right now (zombies have no towers or upgrades).
function BaseUpgrades.towerStats(team: string): BaseUpgradeRules.TowerStats
	return BaseUpgradeRules.towerStats(BaseUpgradeRules.buildingMods(function(id: string): boolean
		return team == DEFENDERS and isOwned(id)
	end))
end

-- The buff heroes give all our soldiers right now (HeroProgress calls this).
function BaseUpgrades.setArmy(newArmy: BaseUpgradeRules.Army)
	if newArmy.health == army.health and newArmy.damage == army.damage and newArmy.attackSpeed == army.attackSpeed then
		return
	end
	army = table.clone(newArmy)
	ReplicatedStorage:SetAttribute("ArmyHealth", army.health)
	ReplicatedStorage:SetAttribute("ArmyDamage", army.damage)
	ReplicatedStorage:SetAttribute("ArmyAttackSpeed", army.attackSpeed)
	changed:Fire("Army")
end

-- Our towers, barracks and core, each with its map max health remembered.
local buildings: { BasePart } = {}
for _, item in arena:GetDescendants() do
	local kind = item:GetAttribute("Kind")
	if item:IsA("BasePart") and item:GetAttribute("Team") == DEFENDERS and typeof(kind) == "string" and BUILDING_KINDS[kind] then
		local maxHealth = item:GetAttribute("MaxHealth")
		if item:GetAttribute("BaseMaxHealth") == nil and type(maxHealth) == "number" then
			item:SetAttribute("BaseMaxHealth", maxHealth)
		end
		table.insert(buildings, item)
	end
end

-- Sets every living building's max health for what is bought. `healGain` adds
-- any extra max health to its current health (a purchase); otherwise health is
-- only capped.
local function applyBuildings(healGain: boolean)
	local mods = BaseUpgradeRules.buildingMods(isOwned)
	for _, building in buildings do
		local baseMax = building:GetAttribute("BaseMaxHealth")
		local oldMax = building:GetAttribute("MaxHealth")
		if not (CombatService.isAlive(building) and type(baseMax) == "number") then
			continue
		end
		local newMax = BaseUpgradeRules.buildingMaxHealth(building:GetAttribute("Kind") :: string, baseMax, mods)
		building:SetAttribute("MaxHealth", newMax)
		local health = CombatService.getHealth(building)
		local gain = if healGain and type(oldMax) == "number" then math.max(newMax - oldMax, 0) else 0
		building:SetAttribute("Health", math.min(health + gain, newMax))
	end
end

local function publish()
	for categoryId, list in BaseConfig.Upgrades do
		local count = 0
		for _, info in list do
			ReplicatedStorage:SetAttribute("Owned" .. info.id, isOwned(info.id))
			count += if isOwned(info.id) then 1 else 0
		end
		ReplicatedStorage:SetAttribute(categoryId .. "Label", `{count}/{#list}`)
	end
end

-- Everything back to the start (start of a match).
function BaseUpgrades.reset()
	table.clear(owned)
	publish()
	applyBuildings(false)
	for _, category in BaseConfig.Categories do
		changed:Fire(category.id)
	end
end

local function workbenchNear(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bench = arena:FindFirstChild("UpgradeWorkbench", true)
	if not (character and root and root:IsA("BasePart") and bench and bench:IsA("BasePart")) then
		return false
	end
	return CombatService.isAlive(character) and (root.Position - bench.Position).Magnitude <= BaseConfig.WorkbenchRange
end

local requestEvent = Instance.new("RemoteEvent")
requestEvent.Name = "BaseUpgrade"
requestEvent.Parent = ReplicatedStorage

local resultEvent = Instance.new("RemoteEvent")
resultEvent.Name = "BaseUpgradeResult"
resultEvent.Parent = ReplicatedStorage

local lastRequestAt: { [Player]: number } = {}

requestEvent.OnServerEvent:Connect(function(player: Player, categoryId: unknown, upgradeId: unknown)
	local info = BaseUpgradeRules.upgrade(categoryId, upgradeId)
	if not info then
		return
	end
	local id = categoryId :: string
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < MIN_REQUEST_GAP then
		return
	end
	lastRequestAt[player] = now

	if isOwned(info.id) then
		resultEvent:FireClient(player, "Owned", id, nil)
		return
	end
	if not workbenchNear(player) then
		resultEvent:FireClient(player, "TooFar", id, nil)
		return
	end
	if not Gold.spend(player, info.cost) then
		resultEvent:FireClient(player, "NotEnoughGold", id, nil)
		return
	end

	owned[info.id] = true
	publish()
	if id == "Buildings" then
		applyBuildings(true)
	end
	changed:Fire(id)
	resultEvent:FireClient(player, "Bought", id, info.id)
	print(`[BaseUpgrades] {player.Name} bought {info.id}`)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)

BaseUpgrades.reset()
-- Each battlefield reset (T15) clears them again, after Structures.server has
-- put the buildings back.
Match.onReset(20, "BaseUpgrades", BaseUpgrades.reset)

return BaseUpgrades
