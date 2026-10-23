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
	scale: number?, -- body size relative to a normal unit (default 1)
	limbs: number?, -- limb length: 0 = classic blocky proportions (default), 1 = Roblox's longest built-in limbs
	knockback: number?, -- each hit throws one of our soldiers back at this speed (studs/s)
	splashRadius: number?, -- ranged zombie: its acid hurts everything of ours this close to where it lands
}

-- A mastery tile in the Character Menu's 3x3 grid. `improves` is shown in
-- orange ("Improves: Lightning Strike"): an ability, a stat or our soldiers.
-- Its numbers live with what it improves, below.
export type MasteryInfo = { id: string, name: string, improves: string, text: string }
local function mastery(info: MasteryInfo): MasteryInfo
	return table.freeze(info)
end

-- A base upgrade (one tile of a category's 3x2 grid). Effects, all optional.
-- Soldiers: health / damage / speed / attackSpeed are shares (0.25 = +25%),
-- range is studs, extraPerGroup is soldiers, splash* is extra damage to nearby
-- zombies. Buildings: towerHealth / barracksHealth / coreHealth / towerDamage /
-- towerAttackSpeed are shares, towerRange is studs.
export type BaseUpgrade = {
	id: string,
	name: string,
	improves: string, -- shown in orange on the tile
	text: string,
	cost: number,
	health: number?,
	damage: number?,
	speed: number?,
	attackSpeed: number?,
	range: number?,
	extraPerGroup: number?,
	splashShare: number?,
	splashTargets: number?,
	splashRadius: number?,
	towerHealth: number?,
	barracksHealth: number?,
	coreHealth: number?,
	towerDamage: number?,
	towerRange: number?,
	towerAttackSpeed: number?,
}
local function upgrade(info: BaseUpgrade): BaseUpgrade
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
	aggroRange = 20, -- owner 2026-10-23: was 14
})

-- Zombie variants (owner 2026-10-21), mixed into the zombie groups
-- (Minion.ZombieVariants). Placeholder numbers.
-- Brute: 1.5x the size, much more health (owner 2026-10-23: 500, was 240),
-- twice a zombie's damage, slower. Attacks
-- with a two-handed overhead smash (owner 2026-10-22) that hits its target
-- only and, if it is one of our soldiers, throws it back (not heroes or
-- buildings). No area damage (owner 2026-10-22).
local BRUTE: MinionStats = table.freeze({
	kind = "Brute",
	maxHealth = 500, -- owner 2026-10-23: was 240
	damage = 24,
	attackRange = 10, -- owner 2026-10-22: 6, then 12, now 10
	attackInterval = 1,
	speed = 5.5,
	aggroRange = 20, -- owner 2026-10-23: was 14
	scale = 1.5,
	knockback = 56, -- owner 2026-10-22: 28, tripled to 84, then 2/3 of that
})

-- Spitter: spits a blob of green acid from its mouth, a little farther than
-- our archers shoot (16). The blob is lobbed at the spot its target stood
-- on when it spat and explodes there (owner 2026-10-22: lands, does not
-- follow), burning every one of our units, heroes and buildings within
-- splashRadius of the blast, so moving away in time dodges it. Frail and
-- slow-firing.
local SPITTER: MinionStats = table.freeze({
	kind = "Spitter",
	maxHealth = 70, -- owner 2026-10-23: was 90, slightly less tanky
	damage = 10, -- to each thing in the splash
	attackRange = 20,
	attackInterval = 2.2,
	speed = 7,
	aggroRange = 28, -- beyond its range so it stops at range instead of walking in (owner 2026-10-23: was 22)
	splashRadius = 6,
})

-- Ripper (owner 2026-10-23: "smaller, limbs extended slightly, fast and hits
-- hard"): a small, long-limbed zombie that runs nearly as fast as a hero and
-- claws harder than a Brute, but is frail. Each attack is one swipe, hands
-- taking turns (Minion.RipperSwipeLook), two a second: 28 damage a second
-- against a Brute's 24. Placeholder numbers. Joins the horde through an
-- arrival like Brutes and Spitters (owner 2026-10-23).
local RIPPER: MinionStats = table.freeze({
	kind = "Ripper",
	maxHealth = 80,
	damage = 14, -- per swipe (owner 2026-10-23: was one hit of 26 a second)
	attackRange = 5,
	attackInterval = 0.5, -- one swipe each, hands taking turns
	speed = 14,
	aggroRange = 26,
	scale = 0.75,
	limbs = 0.6,
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
		-- "Base Core under attack" style popups (owner 2026-10-23): one per
		-- building at most every UnderAttackCooldown seconds while it is hit.
		UnderAttackCooldown = 20,
	}),

	-- Gold (T11, owner 2026-10-20): earned by landing the killing hit on a
	-- zombie with your hero. Nothing to spend it on yet.
	-- Gold (economy rework, owner 2026-10-23; aim: matches of 15-20 minutes).
	-- Every zombie death, killed by anyone, gives every player PerDeath for
	-- its kind (like XP); the player whose hero landed the killing hit also
	-- gets LastHitBonus. A destroyed Zombie Nest gives every player PerNest.
	-- Rough rate: 50-70 Gold a minute per player. Upgrades are shared.
	Gold = table.freeze({
		PerDeath = table.freeze({ Zombie = 1, Spitter = 2, Ripper = 2, Brute = 4 }) :: { [string]: number },
		LastHitBonus = 2,
		PerNest = 40,
		Starting = 0, -- was a temporary 1000 for testing; the dev panel adds Gold
	}),

	-- The lobby courtyard (T05, owner 2026-10-23; Lobby.luau, Match.luau).
	-- Offsets are from Centre (x east toward the battlefield, z south).
	Lobby = table.freeze({
		Centre = Vector3.new(-290, 0, 0), -- west of our base, beyond the map's edge
		-- Studs, x by z (owner 2026-10-23: enlarged from 80 x 60 for four pads).
		Size = Vector2.new(110, 90),
		-- The queue daises, in a row along the east side (owner 2026-10-23: four,
		-- flush to one side). Each runs its own lobby room: E creates one, or
		-- joins / leaves the open one.
		Pads = table.freeze({
			Vector3.new(36, 0, -30),
			Vector3.new(36, 0, -10),
			Vector3.new(36, 0, 10),
			Vector3.new(36, 0, 30),
		}),
		QueueRadius = 6,
		SpawnAt = Vector3.new(-25, 0, 0), -- players appear around here, facing the pads
		CountdownSeconds = 10, -- an open lobby starts after this, full or not (owner 2026-10-23)
		LoadingSeconds = 2.5, -- the loading screen going into a battle
		ReturnLoadingSeconds = 1, -- the loading screen going back to the lobby
		ResultsSeconds = 20, -- the results screen, then everyone returns to the lobby
		-- A lobby's creator picks 1 to MaxBattlePlayers players (owner 2026-10-23: 1-4).
		MaxBattlePlayers = 4,
		-- Maps a lobby can pick, top one first (owner 2026-10-23). Only the one
		-- battlefield exists; the name is a placeholder (owner may rename).
		Maps = table.freeze({
			table.freeze({ Id = "ZombieFields", Name = "Zombie Fields" }),
		}) :: { { Id: string, Name: string } },
	}),

	-- Match rewards for meta progression (owner 2026-10-23): every player gets
	-- ZombieCores when the match ends, win or lose (one placeholder number for
	-- now). Shown on the end screen and added to the saved stats
	-- (PlayerData.server); not yet spendable (T20).
	Rewards = table.freeze({
		ZombieCores = 50,
	}),

	-- Developer panel under the Gold counter (owner 2026-10-21). Studio only:
	-- the server ignores these commands in a live game. Amounts per click.
	Dev = table.freeze({
		Xp = 30,
		Gold = 200,
		-- Units the panel can spawn (MinionStats kinds), in button order. Zombies
		-- appear ZombieDistance studs in front of you, our soldiers beside you.
		SpawnKinds = table.freeze({ "Zombie", "Brute", "Spitter", "Ripper", "Melee", "Archer" }),
		ZombieDistance = 20,
		SoldierDistance = 5,
	}),

	-- Battlefield events (owner 2026-10-21): every Interval seconds one event
	-- happens, picked at random but never the same one twice in a row, with a
	-- banner for everyone. Timed events end with a second banner; triggering
	-- one that is still running restarts its timer. Placeholder numbers.
	Events = table.freeze({
		FirstAt = 90, -- seconds after server start (owner 2026-10-23: every 1:30, was 3:00)
		Interval = 90,
		List = table.freeze({
			-- A zombie nest rises somewhere mid-field and keeps sending zombies
			-- until destroyed, guarded by Brutes.
			table.freeze({ id = "Nest", name = "Zombie Nest", text = "A zombie nest has risen on the battlefield" }),
			-- The Zombie Core and nests send their groups more often and the
			-- core at once sends burstZombies extra zombies (owner 2026-10-22).
			table.freeze({
				id = "Surge",
				name = "Zombie Surge",
				text = "Zombies pour out much faster",
				duration = 45,
				-- owner 2026-10-23: the Zombie Core and nests both 1.5x as often
				-- (the core was briefly 2.5x), and a burst of 5 (was 15)
				coreProductionBonus = 0.5,
				nestProductionBonus = 0.5,
				burstZombies = 5,
			}),
			-- Permanent (owner 2026-10-22, replaces Blood Moon): every zombie,
			-- living and new, gets +25% health and damage for the rest of the
			-- match. Each time adds another 25% of the base (not compounding).
			table.freeze({
				id = "Evolve",
				name = "Zombies Evolve",
				text = "Zombies are permanently 25% stronger",
				strengthBonus = 0.25,
			}),
			-- Zombie Ambush (owner 2026-10-23): about ambushTotal plain zombies
			-- (never Brutes or Spitters) burst out at random open spots all
			-- over the battlefield, in groups of 1 to ambushGroupMax (random
			-- sizes, owner 2026-10-23; see Ambush below).
			table.freeze({
				id = "Ambush",
				name = "Zombie Ambush",
				text = "Zombies burst out all over the field",
				ambushTotal = 15,
				ambushGroupMax = 5,
			}),
		}) :: { { id: string, name: string, text: string, duration: number?, coreProductionBonus: number?, nestProductionBonus: number?, burstZombies: number?, strengthBonus: number?, ambushTotal: number?, ambushGroupMax: number? } },
		-- Where ambush groups may appear: open ground on the battlefield, at
		-- least BaseClearance studs from our Base Core (never inside the base)
		-- and HeroClearance from any player; each zombie within GroupScatter
		-- of its group's spot.
		Ambush = table.freeze({
			BaseClearance = 70,
			HeroClearance = 20,
			EdgeMargin = 20, -- studs kept from the battlefield's edges
			Tries = 30,
			GroupScatter = 4,
		}),
		-- One-time arrivals (owner 2026-10-23): the match starts with plain
		-- zombies only; Brutes, Spitters and Rippers each join the zombie
		-- groups (and nest guards, for Brutes) at one of ArrivalTimes (seconds
		-- after the match starts), in a random order every match (owner
		-- 2026-10-23: 3:00, 6:00 and 10:00, no fixed order), announced once
		-- with a banner like the events. Not part of the random rotation.
		Arrivals = table.freeze({
			table.freeze({ id = "BruteArrival", kind = "Brute", name = "The Brutes Arrive", text = "Huge Brutes now march with the horde" }),
			table.freeze({ id = "SpitterArrival", kind = "Spitter", name = "The Spitters Arrive", text = "Spitters now lob acid from range" }),
			table.freeze({ id = "RipperArrival", kind = "Ripper", name = "The Rippers Arrive", text = "Fast Rippers now hunt with the horde" }),
		}) :: { { id: string, kind: string, name: string, text: string } },
		ArrivalTimes = table.freeze({ 180, 360, 600 }) :: { number },
		Nest = table.freeze({
			Size = Vector3.new(10, 9, 10),
			MaxHealth = 1000, -- owner 2026-10-23: +25% (was 800)
			-- Where it rises: this share of the way from our Base Core to the
			-- Zombie Core, anywhere within HalfWidth studs of the middle line.
			MinShare = 0.35,
			MaxShare = 0.7,
			HalfWidth = 110,
			Tries = 20, -- random spots tried for open ground before giving up
			GroupInterval = 8, -- seconds between its groups
			GroupSize = 3, -- zombies per group (they may roll variants too)
			SpawnMinRadius = 8, -- its zombies appear on a ring this close around it
			SpawnMaxRadius = 16,
			Guards = 2, -- Brutes that stay by it until it falls
			GuardRadius = 9, -- studs from its centre where each guard stands
		}),
	}),

	-- Base upgrades (owner 2026-10-21; placeholder numbers): players spend their
	-- own Gold at the Upgrade Workbench. Everything bought is shared by the
	-- whole side and lasts for one match.
	Base = table.freeze({
		-- Studs from the workbench a purchase is accepted (the prompt opens at 10).
		WorkbenchRange = 16,
		-- The menu's upgrade categories, in order (owner 2026-10-21: Buildings,
		-- Warriors (was Melee Units, owner 2026-10-22), Archers; the Base Core's own levels were folded into
		-- Buildings). `unit` = the soldiers a category improves (Config.Minion
		-- kind; "" for Buildings). The ids MeleeBarracks / ArcherBarracks are kept
		-- from when each category was a barracks.
		Categories = table.freeze({
			table.freeze({ id = "Buildings", name = "Buildings", icon = "🏰", unit = "" }),
			table.freeze({ id = "MeleeBarracks", name = "Warriors", icon = "⚔️", unit = "Melee" }),
			table.freeze({ id = "ArcherBarracks", name = "Archers", icon = "🏹", unit = "Archer" }),
		}),
		-- A 3x2 grid per category (owner 2026-10-21): row 1 survival, row 2
		-- attack, in grid order. Each upgrade is bought once with its own Gold
		-- cost, in any order; all six can be owned. Soldier upgrades improve our
		-- soldiers of that kind (living ones at once, new ones on spawn); building
		-- upgrades improve our towers, barracks and Base Core (a health upgrade
		-- also heals the building by the health it gains).
		Upgrades = table.freeze({
			Buildings = table.freeze({
				upgrade({ id = "StoneWalls", improves = "Tower health", name = "Stone Walls", text = "+25% tower health.", cost = 150, towerHealth = 0.25 }),
				upgrade({ id = "ReinforcedBarracks", improves = "Barracks health", name = "Reinforced Barracks", text = "+25% barracks health.", cost = 150, barracksHealth = 0.25 }),
				upgrade({ id = "FortifiedCore", improves = "Base Core health", name = "Fortified Core", text = "+40% Base Core health.", cost = 300, coreHealth = 0.4 }),
				upgrade({ id = "HeavyBolts", improves = "Tower damage", name = "Heavy Bolts", text = "+25% tower damage.", cost = 150, towerDamage = 0.25 }),
				upgrade({ id = "Watchtowers", improves = "Tower range", name = "Watchtowers", text = "+6 tower range.", cost = 200, towerRange = 6 }),
				upgrade({ id = "RapidFire", improves = "Tower attack speed", name = "Rapid Fire", text = "Towers shoot 25% faster.", cost = 250, towerAttackSpeed = 0.25 }),
			}),
			MeleeBarracks = table.freeze({
				upgrade({ id = "MeleeArmor", improves = "Swordsman health", name = "Iron Armor", text = "+25% soldier health.", cost = 150, health = 0.25 }),
				upgrade({ id = "MeleeRally", improves = "Swordsman speed", name = "Rally", text = "Soldiers move 15% faster.", cost = 150, speed = 0.15 }),
				upgrade({ id = "MeleeReinforce", improves = "Group size", name = "Reinforcements", text = "+1 swordsman in every group.", cost = 300, extraPerGroup = 1 }),
				upgrade({ id = "MeleeBlades", improves = "Swordsman damage", name = "Sharpened Blades", text = "+25% soldier damage.", cost = 150, damage = 0.25 }),
				upgrade({ id = "MeleeSwift", improves = "Swordsman attack speed", name = "Swift Strikes", text = "Soldiers attack 25% faster.", cost = 250, attackSpeed = 0.25 }),
				upgrade({
					id = "MeleeCleave",
					improves = "Swordsman hits",
					name = "Cleave",
					text = "Each hit also deals 50% to one more zombie nearby.",
					cost = 300,
					splashShare = 0.5,
					splashTargets = 1,
					splashRadius = 6,
				}),
			}),
			ArcherBarracks = table.freeze({
				upgrade({ id = "ArcherArmor", improves = "Archer health", name = "Padded Armor", text = "+25% archer health.", cost = 150, health = 0.25 }),
				upgrade({ id = "ArcherLongbows", improves = "Archer range", name = "Longbows", text = "+6 archer range.", cost = 200, range = 6 }),
				upgrade({ id = "ArcherReinforce", improves = "Group size", name = "Reinforcements", text = "+1 archer in every group.", cost = 300, extraPerGroup = 1 }),
				upgrade({ id = "ArcherBroadheads", improves = "Archer damage", name = "Broadheads", text = "+25% archer damage.", cost = 150, damage = 0.25 }),
				upgrade({ id = "ArcherQuickDraw", improves = "Archer attack speed", name = "Quick Draw", text = "Archers shoot 25% faster.", cost = 250, attackSpeed = 0.25 }),
				upgrade({
					id = "ArcherVolley",
					improves = "Archer hits",
					name = "Volley",
					text = "Arrows splash 40% damage onto zombies nearby.",
					cost = 300,
					splashShare = 0.4,
					splashTargets = 99,
					splashRadius = 6,
				}),
			}),
		}) :: { [string]: { BaseUpgrade } },
	}),

	-- The class every player uses for now (owner 2026-10-21: the Mage; Archer
	-- and Warrior come later). Placeholder numbers.
	Hero = table.freeze({
		Name = "Mage",
		MaxHealth = 500, -- at level 1
		-- Natural health regeneration in health per second (owner 2026-10-21:
		-- 0.5 for the Mage). Heroes regenerate while alive, even in combat.
		HealthRegen = 0.5,
		WalkSpeed = 16,
		-- Death and revive (owner 2026-10-23). At 0 health a hero is down: the
		-- body lies where it fell and the player watches (grey screen) while
		-- the respawn countdown runs: RespawnBase + RespawnPerLevel per level
		-- above 1, at most RespawnMax seconds. Then they respawn at the pad with
		-- full health. Before that, a living ally holding F for ReviveHold
		-- seconds within ReviveDistance studs of the body stands them back up
		-- where they fell with ReviveHealthShare of their max health. Each
		-- player can be revived once per match. Coming back either way gives
		-- Protection seconds in which they take no damage.
		Death = table.freeze({
			RespawnBase = 5,
			RespawnPerLevel = 1,
			RespawnMax = 20,
			ReviveHold = 3,
			ReviveDistance = 6,
			ReviveHealthShare = 0.3,
			Protection = 2,
		}),
		-- Requests beyond this per second are dropped before any work is done.
		MaxActionsPerSecond = 8,
		-- Automatic growth every level after the first (no choices). Ability
		-- damage grows in step with Damage (same share as the basic attack).
		Growth = table.freeze({
			MaxHealth = 20,
			Damage = 3,
		}),
		-- Basic attack, Lightning Bolt (left mouse): an aimed shot from the head
		-- along the crosshair; the first enemy on the line is hit.
		Pulse = table.freeze({
			-- Shot length in studs from the hero's head along the aim. The red
			-- marker also only shows targets this close.
			Range = 24,
			Damage = 40, -- at level 1
			Cooldown = 0.75, -- seconds from the start of one attack to the next
			Windup = 0.15, -- seconds between starting the swing and the hit
			-- Mastery Chain Bolt: the bolt jumps to the nearest other enemy within
			-- Range of the target for Factor of the damage.
			Chain = table.freeze({ Range = 12, Factor = 0.5 }),
		}),
		-- Passive, Arcane Resonance: every Every-th bolt that hits deals
		-- BonusFactor extra (1 = double damage). Mastery Quick Resonance: every
		-- QuickEvery-th instead.
		Resonance = table.freeze({
			Every = 4,
			QuickEvery = 3,
			BonusFactor = 1,
		}),
		-- In-match levels (owner 2026-10-20/21; reworked 2026-10-23): every
		-- zombie that dies, by anyone's hand, gives every player XpPerDeath for
		-- its kind. Going from level N to N+1 needs FirstLevelXp + XpGrowth *
		-- (N - 1): 20, 22, 24... (was a flat 30), so early levels come faster
		-- and level 25 lands near the end of a 15-20 minute match. Kept for
		-- the session (death does not reset it).
		Leveling = table.freeze({
			XpPerDeath = table.freeze({ Zombie = 1, Spitter = 2, Ripper = 2, Brute = 3 }) :: { [string]: number },
			FirstLevelXp = 20,
			XpGrowth = 2,
			MaxLevel = 25,
		}),
		-- Masteries (owner 2026-10-21): reaching each of these levels gives one
		-- pick from the 3x3 grid below (any tile, each once): 5 of the 9.
		MasteryLevels = table.freeze({ 5, 10, 15, 20, 25 }),
		-- Grid order, left to right, top to bottom (owner 2026-10-21: not all
		-- masteries improve abilities; some improve stats or all our soldiers).
		Masteries = table.freeze({
			mastery({ id = "ChainBolt", improves = "Lightning Bolt", name = "Chain Bolt", text = "Your bolt jumps to a second enemy for half damage." }),
			mastery({ id = "QuickResonance", improves = "Arcane Resonance", name = "Quick Resonance", text = "Triggers every 3rd hit instead of every 4th." }),
			mastery({ id = "Thunderstorm", improves = "Lightning Strike", name = "Thunderstorm", text = "Leaves a storm that keeps hitting enemies inside." }),
			mastery({ id = "EmpoweredLightning", improves = "Lightning Strike", name = "Empowered Lightning", text = "Bigger area and harder hits." }),
			mastery({ id = "QuickBlink", improves = "Teleport", name = "Quick Blink", text = "Teleport recharges much faster." }),
			mastery({ id = "Vitality", improves = "Health", name = "Vitality", text = "+25% max health." }),
			mastery({ id = "ArcanePower", improves = "Damage", name = "Arcane Power", text = "+15% damage on your bolt and abilities." }),
			mastery({ id = "WarDrums", improves = "All soldiers", name = "War Drums", text = "All our soldiers attack 15% faster." }),
			mastery({ id = "Fortify", improves = "All soldiers", name = "Fortify", text = "All our soldiers get +15% health." }),
		}) :: { MasteryInfo },
		-- Numbers for the stat and soldier masteries (shares: 0.25 = +25%).
		-- Soldier masteries do not stack between players.
		MasteryBonus = table.freeze({
			Vitality = 0.25,
			ArcanePower = 0.15,
			WarDrums = 0.15, -- attack speed of all our soldiers
			Fortify = 0.15, -- health of all our soldiers
		}),
		-- The Mage's base buff (owner 2026-10-21: an ability after the 2nd skill
		-- that buffs our side): always on while the player is in the match;
		-- does not stack between players.
		BaseBuff = table.freeze({
			name = "Storm Banner",
			text = "Our soldiers deal more damage while you are in the match.",
			Damage = 0.1, -- +10% damage for all our soldiers
		}),
		-- The Mage's two abilities (owner 2026-10-21; placeholder numbers).
		Skills = table.freeze({
			-- Q: hold to show the area on the ground, release to call the bolt.
			Strike = table.freeze({
				Range = 40, -- studs from you (flat) to the centre of the area
				Radius = 10, -- studs: the area shown on the ground
				Delay = 0.35, -- seconds from cast until the bolt lands
				Damage = 60, -- at level 1
				Cooldown = 10,
				-- Mastery Thunderstorm: for Duration seconds the area strikes one
				-- random enemy inside it every Interval, for Factor of the damage.
				Storm = table.freeze({ Duration = 4, Interval = 0.8, Factor = 0.5 }),
				-- Mastery Empowered Lightning.
				Empowered = table.freeze({ RadiusFactor = 1.4, DamageFactor = 1.4 }),
			}),
			-- E: hold to show the landing spot where you aim (open ground within
			-- Range, flat), release to teleport there.
			Teleport = table.freeze({
				Range = 25,
				Cooldown = 8,
				-- Mastery Quick Blink: cooldown times this.
				QuickFactor = 0.6,
			}),
		}),
	}),

	Minion = table.freeze({
		Melee = MELEE,
		Archer = ARCHER,
		Zombie = ZOMBIE,
		Brute = BRUTE,
		Spitter = SPITTER,
		Ripper = RIPPER,
		-- Variants come along with the zombies, never instead of them (owner
		-- 2026-10-23: the zombie count must not drop): for each zombie in a
		-- group one roll, in this order, may add one variant to the group
		-- (1 in 10 a Brute, owner 2026-10-23: 10%, then 5%, back to 10%; 1 in
		-- 7 a Spitter; 1 in 10 a Ripper, placeholder). A variant only comes
		-- once it has arrived (Events.Arrivals).
		ZombieVariants = table.freeze({
			table.freeze({ stats = BRUTE, chance = 0.1 }),
			table.freeze({ stats = SPITTER, chance = 0.15 }),
			table.freeze({ stats = RIPPER, chance = 0.1 }),
		}) :: { { stats: MinionStats, chance: number } },
		-- Continuous spawning, no waves (owner 2026-10-21: tug of war). Every
		-- GroupInterval seconds each standing barracks sends our group and the
		-- zombie core sends its group, all match long. Placeholder balance: per
		-- minute the zombies send a little more strength than unupgraded soldiers
		-- (60 zombies vs 16 melee + 8 archers), so a front nobody pushes slowly
		-- drifts toward our base; heroes and upgrades are what win ground.
		Groups = table.freeze({
			Defenders = table.freeze({ MELEE, MELEE, ARCHER }), -- per barracks
			Zombies = table.freeze(table.create(4, ZOMBIE)),
		}) :: { [string]: { MinionStats } },
		GroupInterval = table.freeze({ Defenders = 15, Zombies = 4 }) :: { [string]: number },
		-- Live units per team. A group that would go over its team's cap spawns
		-- only what fits; the rest is dropped, never queued.
		-- TEMPORARY (owner 2026-10-21): uncapped to stress-test how many units the
		-- game can take; was { Defenders = 40, Zombies = 70 }. Put caps back after.
		MaxAlive = table.freeze({ Defenders = math.huge, Zombies = math.huge }) :: { [string]: number },
		-- Zombie groups appear at one random spot on a ring around the zombie
		-- core, between these distances (studs), not on top of it...
		ZombieSpawnMinRadius = 16,
		ZombieSpawnMaxRadius = 60,
		-- ...each zombie within this many studs of the group's spot.
		ZombieGroupScatter = 6,
		-- On the way in, each zombie group first heads for its own rally point
		-- somewhere across the battlefield, so the horde spreads over the whole
		-- field instead of taking the shortest line, then makes for a base opening.
		-- Rally points lie this share of the way from the spawn to our Base Core...
		ZombieRallyMinShare = 0.3,
		ZombieRallyMaxShare = 0.65,
		-- ...anywhere within this many studs to either side of the middle line;
		-- each zombie aims within ZombieRallyJitter studs of its group's point.
		ZombieRallyHalfWidth = 120,
		ZombieRallyJitter = 10,
		FirstSpawnDelay = 5, -- seconds after match start
		-- Safety net only: a unit still alive this long (most likely stuck) is
		-- removed. Long, so pushing units never time out mid-push.
		Lifetime = 600,
		-- Our minions: a unit hit by an enemy unit or tower fights back, even if it
		-- was hitting a structure, while the attacker stays within this many studs.
		-- Larger than tower range (28) so towers shooting a unit get attacked back.
		RetaliateRange = 32,
		-- Zombies (owner 2026-10-23): a zombie that gets hit goes for whoever hit
		-- it while they stay within this many studs (beyond the longest hero
		-- ability range, 40). A nearer attacker can steal its aggro, but at most
		-- once every ZombieAggroSwitchCooldown seconds.
		ZombieChaseRange = 45,
		ZombieAggroSwitchCooldown = 3,
		-- Our minions: allies this close to a unit that gets hit join in on the attacker.
		HelpRange = 10,
		-- TEMPORARY, for simulation only: extra health and damage per team, so one
		-- side wins the push. Remove before release.
		TestTeamBonus = table.freeze({}) :: { [string]: number }, -- e.g. { Defenders = 0.2 }
		-- Archer shot: draws the bow, then the arrow flies; damage lands on arrival.
		ArcherDrawTime = 0.3,
		ArrowSpeed = 60, -- studs per second
		-- Zombie hand swipe: seconds from starting the swing to the claw landing
		-- (the damage is applied then). The swing then recovers before the next hit.
		ZombieSwipeHitDelay = 0.3,
		-- Brute smash (owner 2026-10-22: hands, not the bite): both arms rise
		-- overhead and slam down; the hit lands this long after it starts.
		BruteSmashHitDelay = 0.5,
		-- How the smash looks (clients only; owner's swing pattern, 2026-10-22).
		-- Angles in degrees, added on top of the walk/idle animation, around the
		-- torso's left-right axis: positive swings the arms forward and up (flip
		-- the signs if they swing backwards).
		BruteSmashLook = table.freeze({
			raiseAngle = 160, -- arms up overhead, reached at raiseShare of the hit delay
			slamAngle = 30, -- arms slammed down in front, reached when the hit lands
			raiseShare = 0.65,
			recoverTime = 0.4, -- seconds back to the animation's own arms
		}),
		-- Ripper swipe (owner 2026-10-23): attacks take turns, a right-hand
		-- swipe while the body twists toward its left, then a left-hand swipe
		-- while it twists toward its right, and so on. The claw lands (reach
		-- checked again) as it crosses the middle, windup + sweep / 2 seconds
		-- after the attack starts; the whole swipe (windup + sweep + recover)
		-- fits inside the Ripper's attackInterval. Angles in degrees, added on
		-- top of the animation (Brute pattern): twist turns the upper body; the
		-- arm rises to raiseAngle (up over the shoulder) in the windup and claws
		-- down to strikeAngle (below the resting reach) by the end of the sweep
		-- (owner 2026-10-23: up then down; a sideways arm swing did not show).
		RipperSwipeLook = table.freeze({
			windup = 0.12, -- seconds turning back with the arm raised
			sweep = 0.22, -- seconds turning across while the claw comes down
			recover = 0.15, -- seconds back to the animation's own pose
			twist = 35,
			raiseAngle = 140,
			strikeAngle = 30,
		}),
		-- Brute hit: a soldier thrown back (stats.knockback) is stunned this long.
		KnockbackStun = 0.5,
		-- Spitter: seconds of rearing back before the glob leaves its mouth (a
		-- spitter killed or stunned before then never spits), then the glob's speed.
		SpitWindup = 0.35,
		AcidSpeed = 40, -- studs per second
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
