# Project brief

Working title: **Riftbreak Duel** (name availability unverified).

Build a public, touch-only playable Roblox 1v1 lane battler in which two players use the same hero to push minions, destroy a tower, and break the enemy core. A match should take roughly four to six minutes. The prototype tests whether mobile movement, readable combat, and a push-versus-defend decision are enjoyable enough to replay.

## Required deliverables
- One public Roblox experience and working start-place link.
- One symmetrical lane, two opposing players, one shared R15 hero kit.
- Basic attack, aimed bolt, short dash; a full animation set for every reachable gameplay state.
- Minion waves, one defensive tower, one inhibitor (called "barracks" in code) and one core per side, destroyed in that order: tower, inhibitor, core. (Inhibitor added by owner decision 2026-10-12; order enforced by owner decision 2026-10-15; see GDD.)
- Join, ready, countdown, match, death/respawn, result, rematch.
- Touch HUD, readable camera, cooldown and health feedback.
- Server-owned match outcomes, damage, cooldowns, targets and objectives; validated movement observations.
- Source/config, short completed README, asset credits, test evidence and known issues.

## Design hypothesis and evidence
With five first-time mobile testers, aim for at least four to explain the win condition after 30 seconds and at least three to voluntarily rematch. Record counts and comments; this tiny sample is directional evidence, not a market-demand or retention claim. Play at least five complete two-device matches, including three consecutive matches in the same server. Engineering gates are mandatory even if the fun hypothesis fails.

## Exclusions
No 3v3, second hero, neutral shrine, jungle, shops, leveling, items, ultimates, ranked play, matchmaking services, hero-selection screen, persistence, paid products, progression trees, spectator system, elaborate lobby, bots posing as real PvP, or second map. Use one minion type. No free-text chat feature is needed. Default platform features are not new project scope.

## Definition of done
Two non-editor accounts can use actual phones to join the same public server, finish and rematch without developer intervention, see correct animations and results, and meet every P0 test. The README contains the verified URL, controls, goal, major design decisions, credits, limitations and exact tested devices. A single-player Studio demonstration or private link does not satisfy delivery.

## Owner decisions needed on day one
Choose the account/group that owns the game and animations, confirm publishing eligibility, recruit the second phone/account, record a baseline mobile device, and enter the actual start date. Defaults cover ordinary gameplay choices; do not delay implementation for visual preferences. If publishing is blocked, report it immediately and continue independent coding without pretending the public requirement is met.

## Kept in view (KIV), not scheduled
Owner note 2026-10-15: a small economy may be added later if time allows: gold for last hits (CombatService already reports the killer), a passive gold tick, gold in the HUD, and a base-only shop with 3-4 stat items (damage, health, move speed). Not part of the current scope and not built until the owner schedules it; the exclusions above still apply until then.
