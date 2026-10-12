# Ordered implementation tasks

Follow IDs in order unless all dependencies allow an independent task. Estimates are focused developer hours, not guarantees. Studio/asset/account tasks require the owner when Claude has no access. Do not mark a task DONE until its check has evidence. A01–A14 refer to `07_ACCEPTANCE_TESTS.md`.

## T01 — Confirm release prerequisites
- Target day: 1; estimate: 1 h; dependencies: none.
- Do: Choose owner; check live publishing eligibility; select two phone accounts and baseline device; record start date.
- Done when: Eligibility result and device/tester plan recorded; blockers named.
- Verify: A12.
- Status: tracked in `TASK_STATUS.md`.

## T02 — Open the source scaffold
- Target day: 1; estimate: 1 h; dependencies: T01.
- Do: Install matching Rojo v7 CLI/plugin; build a new place; sync; inspect server/client output.
- Done when: Both bootstrap messages appear; project tree maps correctly; no script errors.
- Verify: A01.
- Status: tracked in `TASK_STATUS.md`.

## T03 — Build the graybox arena
- Target day: 1; estimate: 2 h; dependencies: T02.
- Do: Replace scaffold floor with lane, borders, team spawn pads, tower/barracks/core placeholders and explicit entity IDs.
- Done when: Both spawn pads are reachable; no route bypasses bounds; map is mirrored.
- Verify: A02.
- Status: tracked in `TASK_STATUS.md`.

## T04 — Implement mobile camera and movement
- Target day: 1; estimate: 2 h; dependencies: T03.
- Do: Fixed elevated follow camera; native left thumbstick; R15 rig; remove jump and forbidden states.
- Done when: Phone emulator supports motion with unobstructed view; real-phone smoke check queued.
- Verify: A02.
- Status: tracked in `TASK_STATUS.md`.

## T05 — Implement match membership and ready flow
- Target day: 2; estimate: 2 h; dependencies: T03.
- Do: Add MatchService and epoch; assign two teams; Waiting/Countdown/Playing; ready debounce.
- Done when: One player waits; two must Ready; departure cancels countdown.
- Verify: A03.
- Status: tracked in `TASK_STATUS.md`.

## T06 — Implement entities and damage authority
- Target day: 2; estimate: 2 h; dependencies: T05.
- Do: Entity registry for hero/structures; server health; team, alive, protection and core-lock rules; single damage entry point.
- Done when: Client cannot set damage/health; friendly and locked-core damage rejected.
- Verify: A07.
- Status: tracked in `TASK_STATUS.md`.

## T07 — Implement Pulse end to end
- Target day: 2; estimate: 3 h; dependencies: T04 T06.
- Do: Server target selection, line of sight, cooldown, windup and impact revalidation; hold-to-repeat mobile button.
- Done when: Two clients see one accepted hit; no target spends no cooldown; invalid targets never take damage.
- Verify: A04 A07.
- Status: tracked in `TASK_STATUS.md`.

## T08 — Implement death and respawn
- Target day: 2; estimate: 1.5 h; dependencies: T07.
- Do: Cancel hero actions; death animation hook; five-second respawn; protection; new character bindings.
- Done when: Dead heroes cannot act; repeated deaths restore controls once; protection rules work.
- Verify: A05.
- Status: tracked in `TASK_STATUS.md`.

## T09 — Implement towers and core victory
- Target day: 3; estimate: 2 h; dependencies: T07.
- Do: Server tower targeting/fire; tower death unlocks barracks and core; barracks health and destruction flag; transactional win evaluation.
- Done when: Push can end a match; result happens once; same-step dual core destruction draws.
- Verify: A06.
- Status: tracked in `TASK_STATUS.md`.

## T10 — Implement results and clean rematch
- Target day: 3; estimate: 2 h; dependencies: T09.
- Do: Timeout tiebreak; disconnect forfeit; results buttons; match epoch invalidation; destroy spawned entities and reset registry.
- Done when: Three debug-short matches reset health, cooldowns and connections without duplicates.
- Verify: A03 A06 A11.
- Status: tracked in `TASK_STATUS.md`.

## T11 — Implement one minion type and waves
- Target day: 3; estimate: 3 h; dependencies: T10.
- Do: Waypoint movement; target priorities; shared scheduler; lifetime/cap; start/end cleanup; empowered stats after enemy barracks falls.
- Done when: Both sides push; living count never exceeds 24; no waves after result.
- Verify: A06 A10.
- Status: tracked in `TASK_STATUS.md`.

## T12 — Reach complete graybox milestone
- Target day: 3; estimate: 1 h; dependencies: T11.
- Do: Play start-to-core victory with two clients, then rematch; log blockers.
- Done when: A complete lane match works without admin commands.
- Verify: A03 A06.
- Status: tracked in `TASK_STATUS.md`.

## T13 — Build final three-button touch layout
- Target day: 4; estimate: 2 h; dependencies: T04 T07.
- Do: Responsive anchors, safe insets, cooldown overlays; movement/action simultaneous touches; release cancellation.
- Done when: Thumbstick, held Pulse and separate aim touch do not steal one another.
- Verify: A04.
- Status: tracked in `TASK_STATUS.md`.

## T14 — Implement aimed Arc Bolt
- Target day: 4; estimate: 3 h; dependencies: T13 T06.
- Do: Track one aim pointer; local indicator; tap fallback; validated planar direction; server swept projectile.
- Done when: Bolt hits at most one eligible enemy; walls block; cancellation sends no cast.
- Verify: A04 A07.
- Status: tracked in `TASK_STATUS.md`.

## T15 — Implement Slip and movement validation
- Target day: 4; estimate: 2 h; dependencies: T13 T06.
- Do: Server clamp and sweep; bounded dash grant; legal-position history; speed/bounds checks and correction.
- Done when: Dash cannot cross wall; teleport then attack cannot deal remote damage.
- Verify: A07 A08.
- Status: tracked in `TASK_STATUS.md`.

## T16 — Test first real-phone duel
- Target day: 4; estimate: 1 h; dependencies: T14 T15.
- Do: Publish a test build with appropriate access; use two phones in same server; record input and latency defects.
- Done when: Both players move, attack, aim and dash using touch only; urgent issues ticketed.
- Verify: A04 A09.
- Status: tracked in `TASK_STATUS.md`.

## T17 — Create and publish complete animation set
- Target day: 5; estimate: 3 h; dependencies: T08 T14 T15.
- Do: Author/source approved R15 clips; use correct owner; fill manifest with asset IDs and credits; implement loading.
- Done when: Every reachable state has an approved clip; all load on both accounts.
- Verify: A05.
- Status: tracked in `TASK_STATUS.md`.

## T18 — Integrate animation arbitration
- Target day: 5; estimate: 2 h; dependencies: T17.
- Do: Priorities, windup timing, interruption, pooling of tracks, respawn rebinding and remote-player visibility.
- Done when: No stuck pose after cancellation/death/rematch; visual impact matches combat timing.
- Verify: A05.
- Status: tracked in `TASK_STATUS.md`.

## T19 — Finish combat HUD and onboarding
- Target day: 5; estimate: 1.5 h; dependencies: T10 T13.
- Do: Health/core bars, countdown, tutorial hint, result reason, rematch waiting state, target/aim feedback.
- Done when: New tester can find win condition and all actions without keyboard.
- Verify: A04 A13.
- Status: tracked in `TASK_STATUS.md`.

## T20 — Add readable combat feedback
- Target day: 5; estimate: 1 h; dependencies: T18 T19.
- Do: Small pooled VFX, basic licensed audio, tower/core hit feedback; reduce expensive effects.
- Done when: All three actions and enemy attacks are distinguishable on a small phone.
- Verify: A05 A09.
- Status: tracked in `TASK_STATUS.md`.

## T21 — Run authority and abuse tests
- Target day: 6; estimate: 2 h; dependencies: T11 T15.
- Do: Invalid payloads, spam, stale epoch, replay, dead/wrong-team actions, out-of-range and teleported origins.
- Done when: No unauthorized damage or server exception; record expected and actual behavior.
- Verify: A07 A08.
- Status: tracked in `TASK_STATUS.md`.

## T22 — Run performance and lifecycle tests
- Target day: 6; estimate: 2 h; dependencies: T20.
- Do: Baseline phone 15-minute session; max minions; repeated deaths; background/resume; disconnects; memory/instance trend.
- Done when: Meet A09–A11; attach evidence and defects; no unsupported performance claims.
- Verify: A09 A10 A11.
- Status: tracked in `TASK_STATUS.md`.

## T23 — Fix release blockers and tune pacing
- Target day: 6; estimate: 2 h; dependencies: T21 T22.
- Do: Fix P0 defects first; adjust damage/health/waves only; freeze feature list.
- Done when: All current P0 failures resolved and relevant tests rerun.
- Verify: A01–A12.
- Status: tracked in `TASK_STATUS.md`.

## T24 — Verify public release
- Target day: 7; estimate: 2 h; dependencies: T23.
- Do: Follow publishing checklist; review actual public reach; two non-editor mobile accounts join same public server.
- Done when: Verified playable public URL recorded; required audience can access.
- Verify: A12.
- Status: tracked in `TASK_STATUS.md`.

## T25 — Run observed mobile playtests
- Target day: 7; estimate: 1.5 h; dependencies: T24.
- Do: At least five full matches, three consecutive; recruit five first-time testers if available; record understanding/rematch counts.
- Done when: Observed results recorded honestly; insufficient sample flagged, never invented.
- Verify: A13.
- Status: tracked in `TASK_STATUS.md`.

## T26 — Finish handoff and evidence
- Target day: 7; estimate: 1 h; dependencies: T25.
- Do: Fill README; credits; known issues; tested version and device details; source snapshot and optional short demo.
- Done when: Public URL works and all deliverables match shipped behavior.
- Verify: A14.
- Status: tracked in `TASK_STATUS.md`.

## Recovery tasks (only within days 8–14)
R01: reproduce and rank all failing P0 checks. R02: resolve blockers one system at a time. R03: retest changed behavior on two devices. R04: publish the corrected build and verify its version. R05: finalize evidence and freeze at day 14. Never use the buffer for new heroes, ranked play, items or new maps.
