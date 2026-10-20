# Zeus upgrade pool — PLAN (owner review needed)

Status: **PROPOSED 2026-10-20, not built.** Every name, number and rule below is a draft for the owner to accept, change or cut. Nothing here is in code yet; the live system is still the three placeholder cards (Attack / Move speed / Health x1.5) in `src/server/HeroProgress.luau`.

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
  - **Level 2:** always Charged Bolts, Static Step and Thunder Hide (the three current cards).
  - **Level 3:** one card is always **Thunderclap** (first skill unlock); the other two are random.
  - **Level 6:** one card is always **Storm Cloud** if not yet taken.
  - **Levels 10, 20, 30…:** a **Mastery-only** roll (3 masteries), like Crap Patrol's mastery every 10 levels.
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

### Skill unlocks (fill the three locked HUD slots)
| # | Name | Effect | Ranks | Tier | Min lvl | Requires |
|---|---|---|---|---|---|---|
| 13 | Thunderclap (key 1) | Stun zombies within 10 studs for 1 s, 60 damage, 10 s cooldown | 1 | Rare | 3 (hard-coded offer) | — |
| 14 | Storm Cloud (key 2) | Place a cloud for 6 s that zaps one zombie under it every 0.5 s for 25 | 1 | Rare | 6 (hard-coded offer) | — |
| 15 | Wrath of Zeus (key 3, ultimate) | 12 lightning strikes over a 25-stud area in front, 150 each, 60 s cooldown | 1 | Mastery | 10 | — |

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

### Mastery (offered only on the every-10-levels roll)
| # | Name | Effect |
|---|---|---|
| 25 | Thunder God | Every Pulse chains to 2 enemies and Thunderclap's cooldown is halved |

Mastery rolls draw from #15 Wrath of Zeus, #25 Thunder God and any Rare not yet maxed. Two or three more true masteries would make those rolls feel special: **OPEN**.

## Open questions for the owner
1. ~~Hero name and theme.~~ Answered 2026-10-21: no classes; a Dota-style hero roster in a fantasy theme, so Zeus stays a hero and this is his pool. The menu calls these **talents**.
2. **Pool size.** 25 for now; is the target still about 50 per hero later?
3. **Rerolls and banishing.** None, one free reroll per level, or rerolls for Gold?
4. **Stacking.** Additive per rank (as above: 5 × 20% = +100%) or multiplicative like today's placeholder (1.5 × 1.5 …)? Additive keeps late game in check.
5. **Mastery timing.** Every 10 levels (Crap Patrol) or earlier, since at 30 XP per level level 10 needs 270 zombie deaths?
6. **What carries between missions?** Probably nothing (in-match only), with persistent hero levels unlocking new talents later (T20).
