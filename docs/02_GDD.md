# Scoped game design document

All numerical values below are starting hypotheses, not validated balance. Keep them in `src/shared/Config.lua` as systems are implemented.

## Match and map
Two player slots: Blue and Orange, also identified by labels/icons. Both use Spark. One straight lane about 160 studs long and 28 studs wide, symmetrical cover-free combat space, fenced edges, no vertical routes. Cores at lane ends, each tower about 32 studs in front of its core; protected spawn pads behind cores. These coordinates describe the final map, not the bundled scaffold baseplate.

Use a fixed elevated follow camera, same world orientation for both sides, and conspicuous friendly/enemy objective labels. Native thumbstick motion follows that camera. Disable jump, climbing and swimming; constrain the arena so these states cannot be entered. Keep characters visually consistent through an R15 template or controlled appearance. Do not let arbitrary avatar proportions alter hitboxes.

State flow: Waiting -> Countdown -> Playing -> Results -> Resetting -> Waiting.
Both players tap Ready. Five-second countdown; any departure cancels it. Start health/cooldowns at clean values; spawn first wave when Playing begins. Match clock runs only during Playing. At six minutes, higher remaining core health percentage wins; ties use tower health percentage; exact ties are draws. Kills never break a tie. A destroyed core ends the match immediately. Evaluate simultaneous objective deaths within the same simulation step as a draw; commit one result only.

During Playing a departure ends the match as a forfeit win for the remaining participant. Before Playing it returns to Waiting. No reconnect/resume within a match. New arrivals during Results wait for the next match, never inherit the prior player's slot/state. Results displays outcome and reason. Each player can tap Rematch; when both accept, fully reset and start a new countdown. After 30 seconds without both accepting, reset to Waiting. A lone player sees 'Waiting for opponent'. A replacement player must Ready. Configure maximum server size to two; no cross-server matchmaker. Testers join a friend's server through Roblox's permitted join flow.

## Hero: Spark
Health 600; movement speed 16 studs/second; no mana, passive regeneration, critical hits, armor, random damage, stun or item modifiers. Restore health on respawn only. Death disables abilities and movement, plays death animation, then respawns after five seconds. Spawn protection lasts two seconds and ends immediately if the player makes an accepted attack/cast; protected heroes cannot deal damage without dropping protection. Dash is allowed and does not remove protection.

Three right-thumb actions:
- **Pulse (basic attack):** tap once to attack; hold repeats at most once per 0.75 seconds. Range 24 studs, 40 damage, 0.15-second windup. Server auto-selects nearest eligible enemy hero, else minion, else unlocked structure in range and line of sight. Ties use stable entity ID. No target means no cooldown. Recheck eligibility at impact; if target left range/line of sight, miss and retain spent cooldown. No homing physical projectile is required: use an authoritative hit and cosmetic tracer.
- **Arc Bolt:** 6-second cooldown, 100 damage, 40-stud maximum travel, 80 studs/second, 0.20-second windup, collision radius 2 studs. Press-drag-release to aim; tap uses nearest eligible enemy direction or current facing. Stop at the first enemy or solid obstruction; no piercing, ally damage or core damage while locked. Use server swept collision, not client touch reports. Valid release consumes cooldown even if it misses.
- **Slip (dash):** 8-second cooldown, up to 12 studs over 0.18 seconds, no damage/invulnerability. Tap uses current movement direction, else facing. Direction is planar. Server clamps distance, sweeps against walls, checks arena limits and issues a bounded movement authorization. No wall crossing, knockback, attack reset or target lock.

Starting an action sets its cooldown immediately on server acceptance. Pulse and Bolt windups cannot overlap; dash is rejected during a windup. Pulse/Bolt are rejected during dash. Death cancels pending impacts/projectiles from that hero, and rematch cancels every prior-match task. Holding Pulse must not queue attacks for later execution while another action is locked. Visual hit reactions never add gameplay stun.

## Lane systems
Each side spawns three identical minions every 15 seconds, starting at match start. Minion health 120, damage 12, range 5 studs, attack interval 1 second, movement speed 8. Max 24 living minions across both sides. If a wave would exceed that cap, spawn only available slots, alternating side priority each wave; skip remaining units, never build a backlog. Despawn units after 60 seconds or at match end.

Minions follow fixed lane waypoints, stop to attack the nearest enemy minion in 8 studs, otherwise enemy hero in 8 studs, otherwise next enemy structure within attack range. Resume advancing when targets leave. No pathfinding service dependency on this flat lane. Minions and towers do not target protected heroes.

Tower health 900, range 28 studs, 60 damage every 1 second. Prefer enemy minions, then enemy hero; retain an eligible target until it dies/leaves range/protection changes. A hero may damage a tower without a minion escort, but taking tower damage makes solo rushing risky. Core health 1200; it does not attack. Its tower must be destroyed before it takes any damage, including bolt or minion hits. All structures have visible health and team icons. No tower respawn mid-match.

## Presentation and feedback
One-line objective: 'Push with your minions. Break the tower, then the core.' Display both core bars, own HP, clock, three actions, cooldown overlays, death countdown, result and rematch. Show an outline/ring for Pulse's current predicted target and aim line for Bolt, but treat these as predictions. Telegraph a bolt before release, use distinct team shapes/colors, and cap particles. A missed spell and a server rejection have distinct feedback. Disable buttons and targeting in non-playing states.

## What to show in the final demo
A real mobile duel: move while aiming, dodge a bolt, push with minions, destroy tower/core, see result, rematch. Briefly show one animation close-up and a test log entry demonstrating server rejection of invalid requests. Do not build mock ranked menus, fake player numbers, hero cards for unimplemented characters or store screens. Reuse a restrained visual style with clearly labeled placeholder art if needed.
