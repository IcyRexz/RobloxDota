--!strict
-- Game numbers shared by server and client. Read-only: every table is frozen.
-- The rules behind these numbers live in docs/02_GDD.md; change both together.

-- Unit stats, always in this order: health, attack, range, attack speed,
-- movement speed, then aggro.
export type MinionStats = {
	kind: string,
	maxHealth: number, -- health
	damage: number, -- attack: damage per hit
	attackRange: number, -- range: stops and attacks this close to a target (studs)
	attackInterval: number, -- attack speed: seconds between hits
	speed: number, -- movement speed (studs per second)
	aggroRange: number, -- notices and attacks enemies this close (studs)
}

-- A level-up talent card: a stat talent (multiplies a stat by `factor`) or an
-- ability unlock (`key` is its keyboard key).
export type TalentInfo = { kind: string, name: string, text: string, factor: number?, key: string? }
local function talent(info: TalentInfo): TalentInfo
	return table.freeze(info)
end

-- Our minions: +20% health and attack over the zombie baseline, then another
-- +20% on top (owner 2026-10-20, after the size change), and a wide aggro range
-- so they engage zombies they pass instead of walking by them.
local MELEE: MinionStats = table.freeze({
	kind = "Melee",
	maxHealth = 173, -- was 144 (+20%, rounded)
	damage = 17, -- was 14 (+20% = 16.8, rounded)
	attackRange = 5,
	attackInterval = 1,
	speed = 8,
	aggroRange = 16, -- was 8
})

local ARCHER: MinionStats = table.freeze({
	kind = "Archer",
	maxHealth = 115, -- was 96 (+20%, rounded)
	damage = 14, -- was 12 (+20% = 14.4, rounded)
	attackRange = 16,
	attackInterval = 1,
	speed = 8,
	aggroRange = 22, -- was 16; beyond its range so it closes in on zombies nearby
})

-- The enemy unit (owner decision 2026-10-20): all melee. Same health, attack,
-- range and speeds as our melee minion; a wider aggro range so a passing zombie
-- goes for a nearby tower, unit or player instead of walking by.
local ZOMBIE: MinionStats = table.freeze({
	kind = "Zombie",
	maxHealth = 120,
	damage = 12,
	attackRange = 5,
	attackInterval = 1,
	speed = 8,
	aggroRange = 14,
})

local Config = table.freeze({
	-- The two sides (owner 2026-10-20): us and the zombies. These are the Team
	-- attribute values on players, units and structures; there are no colour teams.
	Teams = table.freeze({
		Defenders = "Defenders",
		Zombies = "Zombies",
	}),

	-- What players can see. Health bars show for units within HealthBarRange of
	-- your hero; it must stay larger than Hero.Pulse.Range so you can always
	-- see the health of anything you can hit.
	Display = table.freeze({
		HealthBarRange = 60,
	}),

	-- Gold (T11, owner 2026-10-20): earned by landing the killing hit on a
	-- zombie with your hero. Nothing to spend it on yet.
	Gold = table.freeze({
		PerLastHit = 1, -- placeholder amount
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
			-- Shot length in studs from the hero's head along the aim. The lock-on
			-- marker also only shows targets this close (planar distance).
			Range = 24,
			Damage = 40,
			Cooldown = 0.75, -- seconds from the start of one attack to the next
			Windup = 0.15, -- seconds between starting the swing and the hit
		}),
		-- In-match levels, rogue-like (owner 2026-10-20, placeholder numbers):
		-- every zombie that dies, by anyone's hand, gives every player XP; each
		-- level-up gives one upgrade pick from the cards below. Kept for the
		-- session (death does not reset it).
		Leveling = table.freeze({
			XpPerZombieDeath = 1,
			-- XP needed to go from level N to N+1 is entry N; the last entry
			-- repeats for every later level (owner: 30 per level for now).
			XpToLevel = table.freeze({ 30 }),
			MaxLevel = 25, -- owner 2026-10-21: 25 levels, no masteries
		}),
		-- Talents offered on level-up (owner 2026-10-21). Three card slots: the
		-- first offer is FirstOffers (the three ability unlocks, slots 1, 2, 3).
		-- Picking a slot replaces only that slot's card with a random talent not
		-- already on offer; the other two stay. Stat talents can be taken again
		-- (multipliers stack: two Damage picks = 1.5 x 1.5); ability unlocks once.
		-- Names and texts are shown on the cards.
		Talents = table.freeze({
			Attack = talent({ kind = "Stat", name = "Damage", factor = 1.5, text = "Your attacks and abilities hit harder." }),
			MoveSpeed = talent({ kind = "Stat", name = "Move Speed", factor = 1.5, text = "You move faster." }),
			Health = talent({ kind = "Stat", name = "Health", factor = 1.5, text = "More max health, healed at once." }),
			Strike = talent({ kind = "Skill", name = "Lightning Strike", key = "1", text = "Call lightning on an area: damage, a short stun, then a slow." }),
			Dash = talent({ kind = "Skill", name = "Storm Dash", key = "2", text = "Dash where you face and knock back zombies where you land." }),
			Ball = talent({ kind = "Skill", name = "Ball Lightning", key = "3", text = "Charge, then hurl a lightning ball at one enemy: heavy damage and a long stun." }),
		}) :: { [string]: TalentInfo },
		FirstOffers = table.freeze({ "Strike", "Dash", "Ball" }),
		-- Zeus's abilities (owner 2026-10-21; placeholder numbers). Damage is
		-- multiplied by the player's Damage talents, like the basic attack.
		Skills = table.freeze({
			-- 1: hold to show the area on the ground, release to call the bolt.
			Strike = table.freeze({
				Range = 40, -- studs from you (flat) to the centre of the area
				Radius = 10, -- studs: the area shown on the ground
				Delay = 0.35, -- seconds from cast until the bolt lands
				Damage = 60,
				StunTime = 0.6, -- seconds hit zombies stand still...
				SlowFactor = 0.5, -- ...then move at this share of their speed...
				SlowTime = 3, -- ...for this long
				Cooldown = 10,
			}),
			-- 2: dash where the camera faces (flat); zombies near the landing spot
			-- are knocked back and briefly stunned.
			Dash = table.freeze({
				Speed = 80, -- studs per second while dashing
				Duration = 0.22, -- seconds, so about 18 studs
				PushRadius = 9,
				PushSpeed = 45, -- studs per second the knocked-back zombie flies off at
				PushStun = 0.5,
				Cooldown = 6,
			}),
			-- 3: needs an enemy under the red marker (or assist) within Range;
			-- charges, then the ball flies; damage and stun land on arrival.
			Ball = table.freeze({
				Range = 40,
				ChargeTime = 1,
				Speed = 70, -- studs per second in flight
				Damage = 300,
				StunTime = 2,
				Cooldown = 30,
			}),
		}),
	}),

	Minion = table.freeze({
		Melee = MELEE,
		Archer = ARCHER,
		Zombie = ZOMBIE,
		-- One wave per spawn marker: our minions come out of each standing
		-- inhibitor, zombies out of each standing zombie core.
		Waves = table.freeze({
			Defenders = table.freeze({ MELEE, MELEE, MELEE, MELEE, ARCHER }),
			Zombies = table.freeze(table.create(12, ZOMBIE)), -- 12 per zombie core (was 16, owner 2026-10-20: -25%)
		}) :: { [string]: { MinionStats } },
		FirstWaveDelay = 5, -- seconds after match start
		WaveInterval = 25,
		MaxAlive = 100, -- across both teams (horde size; check frame rate in Studio)
		Lifetime = 180, -- despawn after this many seconds (long enough to push to the core)
		-- Our minions: a unit hit by an enemy unit or tower fights back, even if it
		-- was hitting a structure, while the attacker stays within this many studs.
		-- Larger than tower range (28) so towers shooting a unit get attacked back.
		-- (Zombies never retaliate; they go for whatever is nearest.)
		RetaliateRange = 32,
		-- Our minions: allies this close to a unit that gets hit join in on the attacker.
		HelpRange = 10,
		-- TEMPORARY, for simulation only: extra health and damage per team, so one
		-- side wins the push. Remove before release.
		TestTeamBonus = table.freeze({}) :: { [string]: number }, -- e.g. { Defenders = 0.2 }
		BarracksBonus = 0.25, -- +25% health and damage after the enemy inhibitor (barracks) falls
		-- Archer shot: draws the bow, then the arrow flies; damage lands on arrival.
		ArcherDrawTime = 0.3,
		ArrowSpeed = 60, -- studs per second
		-- Zombie hand swipe: seconds from starting the swing to the claw landing
		-- (the damage is applied then). The swing then recovers before the next hit.
		ZombieSwipeHitDelay = 0.3,
		TurnRate = 270, -- degrees per second; minions turn smoothly instead of snapping
		Scale = 1, -- body size relative to a normal character (owner 2026-10-20: same height as players)
	}),

	-- Towers. Structure health lives on the map parts (Health / MaxHealth
	-- attributes in src/map/*.model.json).
	Structure = table.freeze({
		-- TEMPORARY, for testing only: starting health for named structures
		-- (max health is unchanged). Remove before release.
		TestStartHealth = table.freeze({}) :: { [string]: number }, -- e.g. { LeftTower = 10 }
		TowerRange = 28,
		TowerAttackInterval = 1,
		TowerDamage = 60, -- every hit on a unit
		TowerShotSpeed = 80, -- studs per second; damage lands when the shot arrives
	}),
})

return Config
