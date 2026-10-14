--!strict
-- Game numbers shared by server and client. Read-only: every table is frozen.
-- The rules behind these numbers live in docs/02_GDD.md; change both together.

export type MinionStats = {
	kind: string,
	maxHealth: number,
	damage: number,
	attackRange: number, -- stops and attacks this close to a target
	aggroRange: number, -- notices enemy units this close
	attackInterval: number, -- seconds between hits
	speed: number,
}

local MELEE: MinionStats = table.freeze({
	kind = "Melee",
	maxHealth = 120,
	damage = 12,
	attackRange = 5,
	aggroRange = 8,
	attackInterval = 1,
	speed = 8,
})

local ARCHER: MinionStats = table.freeze({
	kind = "Archer",
	maxHealth = 80,
	damage = 10,
	attackRange = 16,
	aggroRange = 16,
	attackInterval = 1,
	speed = 8,
})

local Config = table.freeze({
	-- What players can see. Health bars show for units within HealthBarRange of
	-- your hero; it must stay larger than Hero.Pulse.AcquireRange so you can
	-- always see the health of anything you can target.
	Display = table.freeze({
		HealthBarRange = 60,
	}),

	-- The one hero both players use (owner decision 2026-10-15: Zeus).
	Hero = table.freeze({
		Name = "Zeus",
		MaxHealth = 600,
		WalkSpeed = 16,
		RespawnTime = 5, -- seconds after death
		-- Requests beyond this per second are dropped before any work is done.
		MaxActionsPerSecond = 8,
		-- Basic attack (GDD "Pulse"): auto-targets the nearest enemy hero, else
		-- minion, else unlocked structure, in range and line of sight.
		Pulse = table.freeze({
			Range = 24, -- studs (to a unit's centre, or a structure's side)
			-- Targets this close are marked and chased into Range when attack is
			-- pressed (client-side movement; the server still checks Range).
			AcquireRange = 40,
			Damage = 40,
			Cooldown = 0.75, -- seconds from the start of one attack to the next
			Windup = 0.15, -- seconds between starting the swing and the hit
		}),
	}),

	Minion = table.freeze({
		Melee = MELEE,
		Archer = ARCHER,
		Wave = table.freeze({ MELEE, MELEE, MELEE, MELEE, ARCHER }),
		FirstWaveDelay = 5, -- seconds after match start
		WaveInterval = 25,
		MaxAlive = 30, -- across both teams
		Lifetime = 180, -- despawn after this many seconds (long enough to push to the core)
		-- A unit target is dropped once it is this far beyond the minion's aggro range.
		TargetSlack = 2,
		-- Leash: give up a chase this far from where the minion left its path,
		-- or after chasing this long without reaching attack range.
		LeashDistance = 12,
		-- A minion hit by an enemy minion fights back (even if it was hitting a
		-- structure) while the attacker stays within this many studs.
		RetaliateRange = 20,
		LeashChaseTime = 3,
		LeashReturnedDistance = 2, -- back on the path once this close to the anchor
		-- TEMPORARY, for simulation only: extra health and damage per team, so one
		-- side wins the push. Remove before release.
		TestTeamBonus = table.freeze({}) :: { [string]: number }, -- e.g. { Blue = 0.2 }
		BarracksBonus = 0.25, -- +25% health and damage after the enemy inhibitor (barracks) falls
		-- Archer shot: draws the bow, then the arrow flies; damage lands on arrival.
		ArcherDrawTime = 0.3,
		ArrowSpeed = 60, -- studs per second
		TurnRate = 270, -- degrees per second; minions turn smoothly instead of snapping
		Scale = 0.7, -- body size relative to a normal character, so heroes stand taller
	}),

	-- Used by the structure code (T09). Map attributes must match until then.
	Structure = table.freeze({
		-- TEMPORARY, for testing only: starting health for named structures
		-- (max health is unchanged). Remove before release.
		TestStartHealth = table.freeze({}) :: { [string]: number }, -- e.g. { RedTower = 10 }
		TowerHealth = 900,
		BarracksHealth = 700,
		CoreHealth = 1200,
		TowerRange = 28,
		TowerAttackInterval = 1,
		TowerDamage = 60, -- every hit on a minion
		TowerShotSpeed = 80, -- studs per second; damage lands when the shot arrives
		TowerHeroRamp = table.freeze({ 60, 90, 120 }), -- hits in a row on one hero; last value repeats
		TowerRampReset = 2, -- seconds without a hit on that hero
		BackdoorReduction = 0.5, -- hero damage taken without an enemy minion escort
		BackdoorEscortRange = 28,
	}),
})

return Config
