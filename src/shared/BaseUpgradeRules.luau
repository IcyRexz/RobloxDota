--!strict
-- What base upgrades do (owner 2026-10-21; numbers in Config.Base.Upgrades):
-- to our soldiers, plus the army buffs heroes give (the Mage's Storm Banner,
-- the War Drums and Fortify masteries; HeroProgress works them out), and to our
-- buildings (towers, barracks, Base Core).
-- One rule for both sides: the server passes BaseUpgrades' record of what was
-- bought and the current army buff, a device passes ReplicatedStorage's
-- Owned<UpgradeId> and Army* attributes (display only), so the menu's numbers
-- match what the soldiers and buildings really get.

local Config = require(script.Parent.Config)

export type Owned = (id: string) -> boolean

-- Buffs for all our soldiers from heroes (shares: 0.1 = +10%).
export type Army = { health: number, damage: number, attackSpeed: number }

-- Everything bought for one soldier kind, added up.
export type UnitMods = {
	health: number, -- share: 0.25 = +25%
	damage: number,
	speed: number,
	attackSpeed: number,
	range: number, -- studs
	extraPerGroup: number, -- soldiers
	splashShare: number, -- share of each hit dealt to nearby zombies (0 = none)
	splashTargets: number,
	splashRadius: number,
}

-- Everything bought for our buildings, added up (shares, range in studs).
export type BuildingMods = {
	towerHealth: number,
	barracksHealth: number,
	coreHealth: number,
	towerDamage: number,
	towerRange: number,
	towerAttackSpeed: number,
}

-- A tower's shooting numbers with upgrades.
export type TowerStats = { damage: number, range: number, attackInterval: number }

local BaseUpgradeRules = {}

-- The category id that improves soldiers of `kind`, if any.
function BaseUpgradeRules.categoryFor(kind: string): string?
	for _, category in Config.Base.Categories do
		if category.unit == kind then
			return category.id
		end
	end
	return nil
end

-- The upgrade with this id in this category, or nil (also the check for ids
-- sent by a client).
function BaseUpgradeRules.upgrade(categoryId: unknown, upgradeId: unknown): Config.BaseUpgrade?
	if type(categoryId) ~= "string" or type(upgradeId) ~= "string" then
		return nil
	end
	local list = Config.Base.Upgrades[categoryId]
	if not list then
		return nil
	end
	for _, info in list do
		if info.id == upgradeId then
			return info
		end
	end
	return nil
end

function BaseUpgradeRules.unitMods(kind: string, owned: Owned, army: Army?): UnitMods
	local mods: UnitMods = {
		health = if army then army.health else 0,
		damage = if army then army.damage else 0,
		speed = 0,
		attackSpeed = if army then army.attackSpeed else 0,
		range = 0,
		extraPerGroup = 0,
		splashShare = 0,
		splashTargets = 0,
		splashRadius = 0,
	}
	local categoryId = BaseUpgradeRules.categoryFor(kind)
	local list = categoryId and Config.Base.Upgrades[categoryId]
	if not list then
		return mods
	end
	for _, info in list do
		if owned(info.id) then
			mods.health += info.health or 0
			mods.damage += info.damage or 0
			mods.speed += info.speed or 0
			mods.attackSpeed += info.attackSpeed or 0
			mods.range += info.range or 0
			mods.extraPerGroup += info.extraPerGroup or 0
			mods.splashShare = math.max(mods.splashShare, info.splashShare or 0)
			mods.splashTargets = math.max(mods.splashTargets, info.splashTargets or 0)
			mods.splashRadius = math.max(mods.splashRadius, info.splashRadius or 0)
		end
	end
	return mods
end

-- A soldier's stats with the upgrades applied. The base stats are not changed.
function BaseUpgradeRules.applyMods(base: Config.MinionStats, mods: UnitMods): Config.MinionStats
	local stats = table.clone(base)
	stats.maxHealth = math.round(base.maxHealth * (1 + mods.health))
	stats.damage = math.round(base.damage * (1 + mods.damage))
	stats.speed = base.speed * (1 + mods.speed)
	stats.attackInterval = base.attackInterval / (1 + mods.attackSpeed)
	stats.attackRange = base.attackRange + mods.range
	stats.aggroRange = base.aggroRange + mods.range -- notices targets as far as it can shoot
	return table.freeze(stats)
end

function BaseUpgradeRules.buildingMods(owned: Owned): BuildingMods
	local mods: BuildingMods = {
		towerHealth = 0,
		barracksHealth = 0,
		coreHealth = 0,
		towerDamage = 0,
		towerRange = 0,
		towerAttackSpeed = 0,
	}
	for _, info in Config.Base.Upgrades.Buildings do
		if owned(info.id) then
			mods.towerHealth += info.towerHealth or 0
			mods.barracksHealth += info.barracksHealth or 0
			mods.coreHealth += info.coreHealth or 0
			mods.towerDamage += info.towerDamage or 0
			mods.towerRange += info.towerRange or 0
			mods.towerAttackSpeed += info.towerAttackSpeed or 0
		end
	end
	return mods
end

-- A building's max health with upgrades, from its map max health (structure
-- Kind: Tower, Barracks or Core; other kinds are unchanged).
function BaseUpgradeRules.buildingMaxHealth(kind: string, baseMax: number, mods: BuildingMods): number
	local share = if kind == "Tower"
		then mods.towerHealth
		elseif kind == "Barracks" then mods.barracksHealth
		elseif kind == "Core" then mods.coreHealth
		else 0
	return math.round(baseMax * (1 + share))
end

function BaseUpgradeRules.towerStats(mods: BuildingMods): TowerStats
	local structure = Config.Structure
	return {
		damage = math.round(structure.TowerDamage * (1 + mods.towerDamage)),
		range = structure.TowerRange + mods.towerRange,
		attackInterval = structure.TowerAttackInterval / (1 + mods.towerAttackSpeed),
	}
end

return BaseUpgradeRules
