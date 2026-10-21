--!strict
-- The Mage's current ability numbers once masteries are counted (owner
-- 2026-10-21). One rule for both sides: the server passes HeroProgress's
-- record of the player's masteries, a device passes the player's
-- Mastery<id> attributes (display only), so the aiming circle, the HUD
-- cooldown and the Character Menu always match what the server does.
-- Damage here is the level-1 number; callers scale it with the player's level.

local Config = require(script.Parent.Config)

local Hero = Config.Hero
local Strike = Hero.Skills.Strike
local Teleport = Hero.Skills.Teleport

export type HasMastery = (id: string) -> boolean

local MageAbilities = {}

function MageAbilities.strikeRadius(has: HasMastery): number
	return if has("EmpoweredLightning") then Strike.Radius * Strike.Empowered.RadiusFactor else Strike.Radius
end

function MageAbilities.strikeDamage(has: HasMastery): number
	return if has("EmpoweredLightning") then Strike.Damage * Strike.Empowered.DamageFactor else Strike.Damage
end

function MageAbilities.teleportCooldown(has: HasMastery): number
	return if has("QuickBlink") then Teleport.Cooldown * Teleport.QuickFactor else Teleport.Cooldown
end

-- Every how many bolt hits Arcane Resonance triggers.
function MageAbilities.resonanceEvery(has: HasMastery): number
	return if has("QuickResonance") then Hero.Resonance.QuickEvery else Hero.Resonance.Every
end

-- The mastery with this id, or nil (also the check for ids sent by a client).
function MageAbilities.mastery(id: unknown): Config.MasteryInfo?
	if type(id) ~= "string" then
		return nil
	end
	for _, info in Hero.Masteries do
		if info.id == id then
			return info
		end
	end
	return nil
end

return MageAbilities
