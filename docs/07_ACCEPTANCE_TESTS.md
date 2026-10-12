# Acceptance and testing criteria

All checks start **NOT RUN**. Save actual results in `templates/TEST_LOG.md`; include build version, date, device, procedure, expected/actual, evidence and owner. No prefilled claim is evidence. P0 failures block release. P1 research targets inform iteration and may be reported as unmet.

## A01 — Clean start (P0)
Build/sync into a fresh place. Start server with two clients. No project errors; expected service tree; one copy of each controller. Connect/disconnect Rojo safely and repeat from source. Record CLI/plugin versions. The scaffold-only smoke run is distinct from the later full-game acceptance run.

## A02 — Map and controls baseline (P0)
Both sides can traverse the lane on touch. Character scale does not alter effective combat reach. Neither can escape, jump onto objectives, fall into a usable out-of-bounds route or spawn inside geometry. Test both landscape orientations and small/large aspect ratios. Camera shows relevant attacks without manual adjustment.

## A03 — Membership and lifecycle (P0)
One player waits; both Ready; countdown has no active damage; third player cannot enter a full server. Leave during countdown returns to Waiting. Leave during play causes exactly one forfeit. Join during Results waits for next match. Both rematch; one declines/times out; replacement player must Ready. No inherited team, ready, cooldown or score state.

## A04 — Touch combat (P0)
On each real phone, perform 20 Pulse presses/holds, 20 aimed/tap bolts and 20 dashes. Do this while moving, including three simultaneous touches. No doubled action, phantom release, stuck hold, obscured button or cooldown bypass. Cancel bolt 10 times; no cast/cooldown. Focus loss/rotation/death cancels held input. Every gameplay and results action works without keyboard or mouse.

## A05 — Animation completeness (P0)
Check all nine manifest clips on local and opponent views using non-owner accounts. Confirm no asset permission errors or missing IDs. Run blends correctly; Pulse/Bolt telegraphs match impact; hit reaction does not suppress cast/death; death cancels action; spawn/victory stop correctly. Repeat five deaths and three rematches without accumulating tracks/connections. Confirm all omitted movement states are truly unreachable.

## A06 — MOBA rules and results (P0)
Verify minion waves, targeting, tower behavior, core lock across all damage paths, and exact reset. Complete a core win for each side. Test six-minute timeout using shortened Studio-only clock: higher core %, then tower %, then draw. Test both cores destroyed in one step, result lock, and damage arriving after result. Invalid late effects must not change a committed result.

## A07 — Remote and combat authority (P0)
Use a Studio-only test client to send wrong types, extra keys, huge sequence, NaN/infinite vector components, zero/nonplanar/non-unit direction, unknown action, stale epoch, duplicated sequence and out-of-order sequence. Burst 100 requests/s for 10 seconds. Also cast while dead/not a participant/in countdown/on cooldown. Expected: no exception, unauthorized damage, reflection of arbitrary data or unbounded replies/logs. Test target out of range, behind wall, friendly, dead and protected at both request and impact time. Client-reported damage/targets are not accepted fields.

## A08 — Movement and physics (P0)
In a controlled Studio test, teleport a client-owned hero beside a core then attack, fly above lane, cross a wall, speed up, and falsify a dash. Server corrects/denies effects from illegal positions. Confirm legitimate spawn, dash, packet jitter and delayed updates are tolerated within the documented allowance. Nearby clients must not take over NPC simulation. Server ray/sweep results govern hits; fake touch events do nothing.

## A09 — Real devices and latency (P0)
Record model/OS/Roblox version and network for at least two real phones; include the lowest-spec available intended baseline. Run a 15-minute session with active waves/effects. Target median >=30 FPS and >=90% of sampled frames <=50 ms on that baseline after loading; measure with available performance tooling, do not infer from feel alone. Record cold join time and visible stalls. Under a controlled ~150 ms RTT and separately ~300 ms RTT, verify no duplicate hits, cooldown bypass or permanent desync; record RTT actually achieved. Instant local button/aim feedback should normally appear within 100 ms; server confirmation depends on network. Fix sustained <30 FPS or input loss before release; report baseline limitations. Studio emulation alone does not satisfy this check.

## A10 — Capacity and cleanup (P0)
Force the 24-minion cap and sustained projectiles in Studio. No wave backlog, unbounded tasks, or duplicated AI scheduler. Across three rematches, old-match NPCs/projectiles become zero and tracked connection counts return to baseline. Sample memory/instance counts after each reset; investigate monotonic growth rather than attributing all engine caching to a leak.

## A11 — Interruptions (P0)
Background each phone for 10 seconds, resume; disconnect/rejoin; die during bolt windup and dash; restart match with projectile in flight. App stays recoverable, held input stops, old epoch effects do not hit new entities, and UI reflects the authoritative phase. If platform disconnects a backgrounded client, the specified forfeit rule applies.

## A12 — Public access (P0)
Record actual experience/start-place IDs and public URL. Two eligible non-editor mobile accounts open that URL and use Roblox joining to enter the same public server. Start, finish and rematch on the published version. Public visibility and permitted audience reach are checked in Dashboard. Private/test-access links and Studio tests do not count. Record any account/age/audience restrictions honestly.

## A13 — Usability and pacing (P1 research)
Observe five first-time testers if available. Read only the one-line objective; do not coach for 30 seconds. Ask them to explain how to win. Count correct answers (target >=4/5), actual voluntary rematches (>=3/5), accidental taps, confusion and match durations (target roughly 4–6 minutes). At least five full matches and three consecutive same-server matches are required functional evidence. If fewer first-time testers are available, disclose sample size; never extrapolate market demand.

## A14 — Handoff (P0)
Completed README, working public link, exact source/build identifier, truthful feature list, asset credits/permissions, all P0 results with evidence, known issues, and rollback place/source snapshot. Remove scaffold label only after it is genuinely replaced. No secrets in the ZIP/repository. Recheck final build after publication.

## Bug priority and exit
P0: cannot join/play/finish/rematch; broken touch or animation; unauthorized damage; repeated crashes; severe performance; missing public access. P1: unclear feedback, pacing, smaller cosmetic/UX defects. Fix P0 first, rerun changed checks plus one complete two-phone match. Stop adding features on day 6. At day 14 report failed gates explicitly if any remain.
