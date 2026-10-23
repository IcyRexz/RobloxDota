# Open issues review (living document)

Rechecked against the code on 2026-10-23 (third pass; earlier passes 2026-10-21 in chat and 2026-10-22). Covers commits up to `5ad1222` plus the uncommitted win/loss, core strip, score screen and Ripper work. Numbers are from `src/shared/Config.luau` unless a file is named. Static checks on 2026-10-23: luau-lsp 0 errors, selene 0/0, scratch `rojo build` OK (about 13,200 lines of Luau).

Status key: **OPEN** (not started), **PARTLY** (some of it built), **DONE** (built, Studio NOT RUN unless noted), **ON HOLD**.

## Summary

| # | Area | Status | What is left |
|---|---|---|---|
| 1 | Match loop | PARTLY | Lobby/start, reset and restart, mission epoch |
| 2 | MOBA leftovers | DONE | Unit caps still off (owner: leave off for now) |
| 3 | Pressure curve | PARTLY | Steady time escalation, frontline pressure, Ripper in rotation, boss |
| 4 | Economy | DONE (to tune) | Measure the `[Economy]` log, then tune costs; match length target |
| 5 | Sound | OPEN | Everything |
| 6 | Death and revive | DONE | Healing outside combat; solo has no revive |
| 7 | Building | ON HOLD | |
| 8 | Co-op incentives | PARTLY | Combos, ping |
| 9 | HUD | PARTLY | Next-event countdown, under-attack alerts, front line, key hints |
| 10 | Mage kit | OPEN | Unchanged |
| 11 | Uncommitted work | OPEN | 21 changed files and 5 new ones not committed |
| 12 | Test evidence | OPEN | Formal Studio pass still not run |

## 1. Match loop: PARTLY
- **Done (2026-10-23, uncommitted):** `src/server/Match.luau` commits the result once when either core dies (Workspace `MatchResult`, `MatchEndedAt`). After the result everything freezes: no damage (`CombatService`), no spawns or movement (`Minions`), no events (`ZombieEvents`), towers hold fire, hero actions and revives refused. Match clock (`MatchTimer.client.luau`), core strip with both core bars (`CoreStrip.client.luau`), score screen (`MatchEnd.client.luau`: VICTORY/DEFEAT, time, Gold earned, per-player level, kills, masteries, Zombie Cores reward 50). Dev panel Win / Lose.
- **Missing:**
  - No start: the match begins when the server starts. No lobby, ready check or countdown (T05).
  - Reset built 2026-10-23 (T15, Studio NOT RUN): after the result everyone returns to the lobby and the battlefield resets. `BaseUpgrades.reset()` exists but nothing calls it; Gold, levels, masteries, `ReviveUsed`, events, nests and units are never cleared (T15).
  - No mission epoch: delayed callbacks (respawns, storms, spits, event timers) are not tied to a match. Needed before reset can be safe.
  - Zombie Cores reward is only a Player attribute; nothing saves it (T20).
  - Name clash: the currency "Zombie Cores" shares its name with the Zombie Core building (noted in TASK_STATUS).

## 2. MOBA leftovers: DONE
- Lock rule removed (tower -> barracks -> core order, `GuardedBy`) 2026-10-23.
- Barracks-destroyed bonus removed 2026-10-23.
- Pushing out is the intended win, so soldiers marching to the Zombie Core is correct.
- Still open: **unit caps off** (`MaxAlive = math.huge` for both teams; owner 2026-10-23: leave off for now). With events every 1:30, Surges, Ambushes and nests, unit count can grow without limit. Turn back on (were 40 soldiers / 70 zombies) once the frame-rate test is done.
- `Lifetime` 600 s stays as a safety net for stuck units.

## 3. Pressure curve: PARTLY
- **Built:**
  - Zombie variants: Brute (500 HP, 10% of slots, from 3:00), Spitter (70 HP, 15%, from 6:00).
  - Events every 1:30 (first at 1:30): Zombie Nest (1000 HP, guarded), Zombie Surge (core 1.5x, nests 1.5x, 5-zombie burst), Zombies Evolve (+25% zombie strength each time, permanent, about every 6 minutes), Zombie Ambush (15 zombies in groups of 1-5 across the field).
  - Zombies now chase whoever damages them (within 45 studs, 3 s switch lock) unless already hitting something.
- **Missing:**
  - Steady escalation: the only lasting ramp is Evolve, which comes at random about every 6 minutes. No zombie group size or stats by minute.
  - Frontline pressure (more zombies the closer we push to their core) from the agreed tug-of-war plan.
  - **Ripper** (fast, 80 HP, double claw) exists but only from the dev panel; when it joins the groups or arrivals is the owner's call.
  - Boss (T22, design OPEN).

## 4. Economy: DONE, needs tuning
- **Built (owner choice 2026-10-23):** every zombie death pays every player (Zombie 1, Spitter 2, Ripper 2, Brute 4), the killer also gets +2, a nest pays everyone 40, starting Gold 0. XP by kind (1/2/2/3), level N to N+1 costs 20 + 2 per level, max 25. Studio prints an `[Economy]` line every minute.
- Gold is still per player (each player gets their own share); upgrades are still shared by the side. Every player is paid the same base share, so the "one player funds everything" problem is smaller but still possible.
- Estimates only (not measured): 50-70 Gold a minute per player, so all 18 upgrades (3,850 Gold) in about 55-75 minutes solo; first mastery about 1:45; level 25 about 17-18 minutes.
- **Missing:** a measured `[Economy]` log from a real 10+ minute run; a target match length to tune costs and the level curve against (owner decision).

## 5. Sound: OPEN
- Still no sounds in `src` (the only "Sound" match is `TargetInfo.client.luau` removing sounds from portrait copies).
- First pass: bolt cast/hit, kill tick, Strike thunder, teleport, level-up and mastery ping, downed and revive, Base Core hit alarm, event horn (events now have red banners), Brute smash, Spitter splat, Ripper claws, win/lose stings, ambient music.

## 6. Death and revive: DONE
- **Built 2026-10-23:** at 0 HP you are downed (body on the ground, placed by raycast), grey death screen with an orbit camera; respawn after 5 s + 1 s per level above 1 (max 20 s) on the shared spawn pad at full health; an ally holding F for 3 s within 6 studs revives you where you fell at 30% health, once per player per match; 2 s spawn protection; popups to everyone; party portrait greyed with the timer and revive progress; a party wipe changes nothing (owner).
- **Still open:**
  - Healing: regen is still 0.5 HP/s everywhere (about 17 minutes from empty). Dying is now slower than before (up to 20 s at high level), but there is still no way to heal up except waiting or dying. Out-of-combat regen or a pad heal was proposed, not decided.
  - Solo players can never be revived (revive needs an ally). Owner to decide whether that is fine.
  - Revive once per match has no reset yet (needs T15).

## 7. Building: ON HOLD (owner 2026-10-21)
- Build nodes, walls, traps and repair on hold since the tug-of-war redesign. Base upgrades are still invisible percentage buffs (no visual change on towers or barracks).

## 8. Co-op incentives: PARTLY
- Now shared: XP, Gold share per zombie death, base upgrades, soldier masteries (no stacking), revive, mastery popups to everyone.
- Missing: combos between players, a ping/marker key.

## 9. HUD: PARTLY
- **Built:** health/XP/level, ability slots with cooldowns, Gold, minimap, target panel (with ally hover and real-colour portraits), party list with downed state, Tab scoreboard, red event banners, structure bars, **core strip** (both cores, always visible), **match clock with running-event pills**, **death screen**, **score screen**, mastery popups.
- **Missing:**
  - Countdown to the *next* event (the clock only shows events already running).
  - "Base Core / Barracks / Tower under attack" alerts (the core strip shows health, but nothing calls attention to a hit).
  - Front-line indicator (where the clash is).
  - First-match key hints (LMB, Q, E, F, U, Tab, and F to revive).

## 10. Mage kit: OPEN (unchanged)
- Bolt range 24 vs Strike 40; no ultimate; Storm Banner (+10% soldier damage) invisible; Teleport ignores fences (Strike/Teleport now accept aim up to 10 studs past range while walking); sword-slash attack animation (T25).
- Archer and Warrior classes not started.

## 11. Uncommitted work: OPEN
- `git status` shows 21 modified files and new `Match.luau`, `CoreStrip.client.luau`, `MatchEnd.client.luau`, `docs/14_MONETIZATION_IDEAS.md`, `docs/reference/` not committed (win/loss, score screen, Ripper and its swipes, colour changes). Worth a commit before the next slice.

## 12. Test evidence: OPEN
- Owner Studio evidence so far: portrait colours (PASS), Ripper arm motion (partial: twist showed, swing fixed afterwards), plus screenshots that led to fixes (menus, downed body, puddle, Brute arms). Everything else since the Mage rewrite is Studio NOT RUN.
- `docs/STUDIO_TEST_PASS.md` has been updated for groups and the new screens, but section 8 still says "after 5 minutes of waves", and it has no steps yet for downed/revive, the core strip, events/arrivals or the Ripper.
- Status lines in `TASK_STATUS.md` for T05, T15 and T23 lag behind the dated log (fixed for T11 and T23 in this review).

## Decisions still open (owner)
1. **Healing:** out-of-combat regen (for example 3% max HP/s after 5 s without damage), a spawn-pad heal (10%/s), both, or keep 0.5/s only.
2. **Solo revive:** can a solo player revive at all (for example a self-revive once per match), or always wait out the timer?
3. **Match length target** (to tune Gold, costs and the level curve).
4. **Escalation:** add a steady ramp (zombie group size or stats per minute) on top of Evolve, and/or frontline pressure?
5. **Ripper:** when does it join (arrival time, share of slots), and keep the name and numbers?
6. **Unit caps:** turn back on after the frame-rate test (at what numbers)?
7. **Next slice:** T05 + T15 (start and reset), sound, or the remaining HUD items.

## Suggested order
1. Commit the current work.
2. Run the Studio pass (update section 8 and add downed/revive, core strip, events, Ripper steps first).
3. T05 + T15: start countdown, epoch, full reset and "Play again", so matches can be played back to back. This is the last big piece of the core loop.
4. Remaining HUD items (next-event countdown, under-attack alerts, key hints).
5. Tune the economy and level curve from a measured `[Economy]` log against the match length target.
6. Sound pass.
7. Steady escalation, Ripper in rotation, unit caps back on.
8. Then Archer and Warrior, and persistent progression (T20).

## History
- 2026-10-22 pass: found the barracks-destroyed bonus and lock rule still live (both removed 2026-10-23), unit caps off; GDD win line fixed from waves to tug of war; death, economy and HUD chosen as next work.
- 2026-10-23 pass (this one): death/revive, economy rework, win/loss with core strip and score screen, events every 1:30 with Ambush and arrivals, zombie retaliation and the Ripper all built since; match start, reset, sound, healing and the remaining HUD items are what is left.
