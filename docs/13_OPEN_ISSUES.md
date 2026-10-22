# Open issues review (living document)

Rechecked against the code on 2026-10-22 (after the tug-of-war redesign, zombie variants, battlefield events and the dev panel). Replaces the chat review of 2026-10-21. Numbers are from `src/shared/Config.luau` unless a file is named. Nothing here has Studio evidence yet: `docs/STUDIO_TEST_PASS.md` is still NOT RUN, and parts of it (waves, two zombie cores) are now out of date.

Status key: **OPEN** (not started), **PARTLY** (some of it built), **DECIDED** (owner settled the direction), **FIXED**.

## 1. Match loop: OPEN (critical)
- Direction **DECIDED** (owner 2026-10-21): tug of war, no waves. Win = Zombie Core destroyed, loss = Base Core destroyed.
- Still missing: start/lobby, match timer, win and loss handling, results screen, reset. When the Base Core dies it just disappears (`Structures.server.luau:116`: "Core destruction ending the match comes next"). Destroying the Zombie Core stops zombie spawns but nothing declares a win.
- No mission epoch exists yet, so delayed callbacks (storms, spits, events, respawns) would leak into a next match.
- Gold, levels, masteries and base upgrades last the whole server session; `BaseUpgrades.reset()` exists but nothing calls it.
- Fix: T05 (state machine `Lobby -> Countdown -> Fighting -> Results -> Resetting`, `Mission` attributes, epoch), T10 (core `Died` = loss, Zombie Core `Died` = win, committed once), T15 (results and full reset).

## 2. MOBA leftovers: PARTLY
- Pushing out is now the intended win (DECIDED), so soldiers marching to the Zombie Core is correct.
- **Barracks-destroyed bonus still live** (`Minions.server.luau:463`): when zombies destroy one of our barracks, every new zombie gets +25% health and damage for the rest of the session (`BarracksBonus = 0.25`). Zombies have no barracks, so we can never get it. Decide: keep it as a "losing ground hurts" rule, or cut it.
- **Lock rule still on our side** (`GuardedBy` in `src/map/PlayerBase.model.json`): zombies cannot hurt a barracks until its tower falls, or the Base Core until a barracks falls. The Zombie Core has no guard. Decide: keep (MOBA-style layers of defence) or cut (core always hittable).
- Soldier `Lifetime` 600 s is now only a safety net for stuck units: fine.
- **Unit caps are off** (`MaxAlive = math.huge` for the stress test). Must go back to real numbers (were 40 / 70) after the frame-rate test.

## 3. Pressure curve: PARTLY
- Built: Brute and Spitter variants (10% / 15% of zombie slots); battlefield events every 180 s (Nest, Surge with a 15-zombie burst, Evolve +25% zombie strength each time, permanent).
- Missing: steady time escalation (zombie stats or group size by minute), frontline pressure (more zombies the closer we push), a runner type that slips past soldiers, the boss (T22). Evolve only happens when it is rolled, so escalation is random.

## 4. Economy: OPEN (next)
- Income: 1 Gold per killing blow by your hero (`PerLastHit`). Zombies arrive at 4 every 4 s (60 a minute). Soldiers, towers and allies take most kills; a player landing about 15 a minute earns about 15 Gold a minute.
- Costs: 18 upgrades, 3,850 Gold in total. That is about 4 hours of play for one player. `Gold.Starting = 1000` (TEMPORARY) and the dev panel's +200 Gold hide this.
- Gold is per player, upgrades are shared by the side: one player can fund everything or spend on something the others did not want.
- Nests, Brutes and Spitters give the same 1 Gold as a plain zombie. Destroying a nest gives nothing.
- XP runs much faster than Gold: every zombie death gives every player 1 XP, 30 per level, so level 25 arrives at about 12 minutes.

## 5. Sound: OPEN
- Still zero `Sound` instances in `src`. First pass: bolt cast/hit, kill tick, Strike thunder, teleport, level-up and mastery ping, core-under-attack alarm, event horn, Brute smash, Spitter splat, ambient music.

## 6. Death is free: ADDRESSED 2026-10-23 (downed state, countdown 5 s + 1 s/level max 20, revive once per match by an ally holding F, 2 s spawn protection; see GDD). History below.
- `Heroes.server.luau`: Roblox respawns you after 5 s (`RespawnTime`) at full health on the pad, keeping level, XP and masteries. No penalty, no death screen, no countdown.
- Regen is 0.5 HP/s in and out of combat (about 17 minutes from empty). So when badly hurt, the fastest heal is to die.
- No revive exists. A full party wipe has no effect (the GDD marks it OPEN).
- The server keeps no "downed" state; the Humanoid simply dies and `Players.RespawnTime` handles the rest.

## 7. Building: ON HOLD (owner 2026-10-21)
- Build nodes, walls, traps and repair are on hold since the tug-of-war redesign. Base upgrades are still invisible percentage buffs (no visual change on towers or barracks).

## 8. Co-op incentives: OPEN
- Shared: XP, base upgrades, soldier masteries (no stacking). Individual: Gold, kills. No revive, no combos, no ping.

## 9. HUD gaps: PARTLY (next)
- Built: health/XP/level, ability slots with cooldowns, Gold, minimap, target panel, party list, Tab scoreboard, banners for structures and events, structure bars over the buildings (only within 60 studs).
- Missing:
  - Base Core and Zombie Core health on the HUD (visible from anywhere);
  - match timer and a countdown to the next event (events fire every 180 s with no warning);
  - "Core under attack" / "Barracks under attack" alerts;
  - death screen with respawn countdown (and revive progress once it exists);
  - where the front line is (a tug-of-war bar or a minimap marker);
  - onboarding key hints (LMB, Q, E, F, U, Tab).

## 10. Mage kit: unchanged
- Bolt range 24 vs Strike 40; no ultimate; Storm Banner (+10% soldier damage) invisible; Teleport ignores fences; sword-slash attack animation (T25).

## 11. Built ahead of the loop
- Level curve tuned for nothing: level 25 at about 12 minutes of a match with no end.
- Studio-only dev panel is useful; keep it Studio-only (it checks `RunService:IsStudio()`).

## 12. Test evidence: OPEN
- Every slice since the Mage rewrite is Studio NOT RUN apart from owner screenshots of the Brute and the puddle. `docs/STUDIO_TEST_PASS.md` section 7 still describes waves and two zombie cores and needs updating before it is run.

## Decisions for the next session (owner to answer; not asked yet)
Next work (owner 2026-10-22): death and revive, economy, extra HUD. Options below are proposals; the first in each list is Claude's recommendation.

1. **Death cost and coming back**
   - a. Downed + revive: at 0 HP you go down for about 12 s; an ally holds F beside you for 3 s to revive you at 40% HP. If nobody does, you die and respawn after 5 s + 1 s per level (max 20 s) at the pad.
   - b. Scaling respawn only: no downed state, respawn 5 s + 1 s per level (max 20 s). Simplest, works solo.
   - c. As a, and a real death also costs 10% of your Gold.
2. **Solo play with revive:** if revive is chosen, can a solo player self-revive (for example once per few minutes), or do they always bleed out?
3. **Full party wipe:** does everyone dead at once lose the match, or only the Base Core falling?
4. **Healing**
   - a. Out-of-combat regen + pad: after 5 s without damage regen rises to 3% max HP/s; standing on the spawn pad heals 10%/s; in combat stays 0.5/s.
   - b. Pad heal only (keep 0.5/s everywhere).
   - c. Out-of-combat regen only.
5. **Gold model**
   - a. Shared team pool: one balance for the side, any player buys at the Workbench; scoreboard still shows who earned what.
   - b. Personal Gold plus a share of every zombie death (like XP), with a bonus for last hits.
   - c. Keep personal last-hit Gold and just retune amounts and costs.
6. **Gold amounts:** target time to afford everything (for example 60% of the upgrades in a 20-minute match), Gold per zombie type (Brute and Spitter worth more?), a reward for destroying a nest, and when `Gold.Starting` goes to 0.
7. **Match length target** (needed to tune both Gold and the level curve): roughly how long should a winning match take?
8. **HUD first slice** (pick any):
   - a. Base Core and Zombie Core health at top centre, always visible, flashing when hit.
   - b. Match timer and a countdown to the next battlefield event, with a 10 s warning.
   - c. Throttled "Base Core / Barracks / Tower under attack" alerts.
   - d. Death screen with respawn countdown (and downed / revive progress).
   - e. Front-line indicator (tug-of-war bar or minimap marker).
   - f. First-match key hints (LMB, Q, E, F, U, Tab).
9. **MOBA leftovers:** keep or cut the barracks-destroyed bonus (zombies +25% after taking one of our barracks), and keep or cut the lock rule (tower before barracks before Base Core).
10. **Unit caps:** turn them back on (were 40 soldiers / 70 zombies) now, or after the frame-rate test?

## Doc fixes made in this review
- `docs/02_GDD.md`: mission flow and win line still described waves ("final wave cleared"); now say tug of war, Zombie Core destroyed.
