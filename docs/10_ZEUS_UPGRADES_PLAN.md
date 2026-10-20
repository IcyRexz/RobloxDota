# Zeus upgrade pool — PLAN (owner review needed)

Status: **partly decided and partly built (2026-10-21).** Decided by the owner and **built**: **25 levels, no masteries**; the three abilities below (Lightning Strike, Storm Dash, Ball Lightning) with their unlock cards; the slot rule for offers. Still a proposal: the rest of the 25-talent pool (stat and modifier talents beyond the three placeholder stat cards).

## Decided and built (owner 2026-10-21)
- **Levels 1-25**, one talent pick per level-up (24 picks). No masteries for now.
- **Card slots:** the first offer is always the three ability unlocks: **slot 1 Lightning Strike, slot 2 Storm Dash, slot 3 Ball Lightning**. Picking a slot replaces **only that slot** with a new random talent not already on offer (an unlocked ability is never offered again); the other two stay. Min level and tier are ignored for these. Server-owned in `src/server/HeroProgress.luau`; talents in `Config.Hero.Talents`.
- **1, Lightning Strike:** hold 1 to show the area on the ground (exact size), release to call a bolt from the sky there. Enemy units inside take damage, are stunned briefly, then slowed. Placeholder numbers: range 40, radius 10, 60 damage, 0.6 s stun, then 50% speed for 3 s, 10 s cooldown.
- **2, Storm Dash:** dash where you face (about 18 studs); zombies within 9 studs of where you land are knocked back and briefly stunned. 6 s cooldown.
- **3, Ball Lightning:** press 3 with an enemy under the crosshair (red marker or aim assist, range 40); charge 1 s, then a lightning ball flies to that one target: 300 damage and a 2 s stun. 30 s cooldown.
- Ability damage scales with the Damage talent, like the basic attack. Numbers live in `Config.Hero.Skills`; code in `src/server/HeroActions.server.luau` (rules), `src/server/UnitEffects.luau` (stun, slow, knockback), `src/client/HeroControls.client.luau` (keys, ground indicator, dash), `src/client/SkillEffects.client.luau` (visuals).

## Reference: Crap Patrol 2 (SC2 Arcade)
What the community wiki says about its progression ([wiki](https://crap-patrol-2.fandom.com/wiki/Crap_Patrol_2_Wikia), [Talents](https://crap-patrol-2.fandom.com/wiki/Talents), [Tychus](https://crap-patrol-2.fandom.com/wiki/Tychus)):
- **Talents**, one point per level: learn a new skill, upgrade a skill, or raise a stat (attack damage, range, sight, move speed, health, energy).
- **Masteries**, rarer and much stronger: one at the start and one every 10 levels (more from kill streaks or found artifacts). Some have **level gates** (Armour Mastery needs level 10) or **unlock conditions** (a combined score of 2500).
- Each hero has its own talent and mastery list, plus a few shared ones.
- The wiki does **not** describe random offers. The "fixed list, offered in a random order, with a few hard-coded early unlocks" idea is the owner's design, and this plan follows it.

## How the pool works (proposal)
- **25 fixed upgrades for Zeus.** Each has: id, name, effect, **max ranks**, **tier** (Common / Rare / Mastery), **min level**, **requires** (other upgrades) and a **weight**.
- **On each level-up the server rolls 3 different cards** from the upgrades currently eligible: below max rank, min level reached, requirements owned. Higher weight means more likely. So each run offers a different order, but always from the same 25.
- **Hard-coded early offers**, so every run starts the same way and learns the basics:
  - ~~Level 2/3/6 fixed offers and mastery rolls~~ **Superseded 2026-10-21:** the first offer is the three ability unlocks in slots 1-3, and there are no masteries (see "Decided and built").
- **Server-owned:** the server rolls and remembers the 3 offered ids; the client can only pick one of those three. A **reroll** (once per level, or for Gold) is an option; **OPEN**.
- Numbers are first guesses for Zeus's 40-damage, 24-stud, 0.75 s Pulse.

## The 25 upgrades

### Stats (Common, repeatable)
| # | Name | Effect per rank | Ranks | Min lvl | Requires |
|---|---|---|---|---|---|
| 1 | Charged Bolts | +20% Pulse damage | 5 | 2 | — |
| 2 | Static Step | +10% move speed | 3 | 2 | — |
| 3 | Thunder Hide | +20% max health (heals the gain) | 5 | 2 | — |
| 4 | Quick Discharge | −8% Pulse cooldown | 3 | 3 | — |
| 5 | Long Arc | +4 studs Pulse range | 2 | 4 | — |
| 6 | Grounding | −8% damage taken | 3 | 4 | — |

### Pulse modifiers (Common / Rare)
| # | Name | Effect | Ranks | Tier | Min lvl | Requires |
|---|---|---|---|---|---|---|
| 7 | Chain Lightning | Pulse jumps to +1 more enemy within 8 studs (60% damage) | 3 | Rare | 4 | — |
| 8 | Overcharge | Every 4th Pulse deals triple damage | 1 | Rare | 5 | — |
| 9 | Static Shock | Pulse slows zombies 30% for 1.5 s | 1 | Common | 3 | — |
| 10 | Conductor | +50% Pulse damage to structures | 1 | Common | 3 | — |
| 11 | Ion Burst | A zombie killed by Pulse explodes for 30 damage in 6 studs | 2 | Rare | 6 | — |
| 12 | Wide Arc | Shot radius 1 -> 2 studs (easier hits) | 1 | Common | 3 | — |

### Skill unlocks (fill the three locked HUD slots) — DECIDED 2026-10-21
| # | Name | Effect |
|---|---|---|
| 13 | Lightning Strike (key 1) | Area bolt from above: damage, short stun, then slow (built) |
| 14 | Storm Dash (key 2) | Dash forward, knock back zombies where you land (built) |
| 15 | Ball Lightning (key 3) | Charged single-target ball: heavy damage and long stun (built) |

The skill upgrades below (16-20) were drafted for the old Thunderclap / Storm Cloud / Wrath ideas and need re-drafting for these three abilities: **OPEN**.

### Skill upgrades
| # | Name | Effect | Ranks | Tier | Requires |
|---|---|---|---|---|---|
| 16 | Aftershock | Thunderclap pulses a second time 1 s later | 1 | Rare | Thunderclap |
| 17 | Rolling Thunder | Thunderclap radius +3, cooldown −2 s | 2 | Common | Thunderclap |
| 18 | Gathering Storm | Storm Cloud lasts +3 s | 2 | Common | Storm Cloud |
| 19 | Tempest | Storm Cloud follows Zeus | 1 | Rare | Storm Cloud |
| 20 | Olympian Fury | Wrath of Zeus +6 strikes | 1 | Rare | Wrath of Zeus |

### Survival and economy
| # | Name | Effect | Ranks | Tier | Min lvl |
|---|---|---|---|---|---|
| 21 | Siphon Spark | Heal 3% of Pulse damage dealt | 3 | Rare | 5 |
| 22 | Divine Vigor | Regenerate 2% max health per second after 4 s without taking damage | 1 | Common | 4 |
| 23 | Tithe | +1 Gold per last hit | 2 | Common | 3 |
| 24 | Wisdom of Olympus | +25% XP | 2 | Common | 3 |

### ~~Mastery~~ (dropped 2026-10-21: no masteries for now)
Slot 25 needs a new regular talent instead: **OPEN**.

## Open questions for the owner
1. ~~Hero name and theme.~~ Answered 2026-10-21: no classes; a Dota-style hero roster in a fantasy theme, so Zeus stays a hero and this is his pool. The menu calls these **talents**.
2. **Pool size.** 25 for now; is the target still about 50 per hero later?
3. **Rerolls and banishing.** None, one free reroll per level, or rerolls for Gold?
4. **Stacking.** Additive per rank (as above: 5 × 20% = +100%) or multiplicative like today's placeholder (1.5 × 1.5 …)? Additive keeps late game in check.
5. ~~Mastery timing.~~ Answered 2026-10-21: no masteries; 25 levels.
6. **What carries between missions?** Probably nothing (in-match only), with persistent hero levels unlocking new talents later (T20).
