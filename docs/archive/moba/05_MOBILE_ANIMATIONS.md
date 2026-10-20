# Mobile controls and animation specification

## Touch-first interaction
Landscape is the supported gameplay orientation. Set the StarterGui orientation accordingly in Studio and test both landscape directions; handle rotation/backgrounding by cancelling active aim and held attacks. Desktop keys can help developers, but no acceptance check depends on them.

Left thumb: native movement thumbstick. Right thumb cluster: large Pulse bottom-right, Bolt above-left, Slip above-right. Initial targets: Pulse ~80 logical pixels diameter, skills ~64, separation >=12; adapt to viewport and validate on the smallest test device. These are design targets, not physical-pixel guarantees. Anchor inside `CoreUISafeInsets`; never cover native joystick, Roblox controls, chat or device cutouts. Health and clock at top, core status at top center. Text stays readable without color as its only signal. Avoid hover, double tap, keyboard-only confirmation and precision world taps.

Pulse: press begins an attempt; hold repeats on cadence, release anywhere stops. Bolt: capture the specific touch that began on its button; drag at least 12 logical pixels for directional aim; release to cast, release into a visible cancel zone to cancel. Below threshold, auto-aim to predicted nearest eligible enemy or facing. Slip: tap uses movement/facing. Pressing disabled buttons does not queue future actions. Track touch identities, not a single global touch flag. Moving with one touch must not move the aim pointer owned by another touch. A button press must not also act as a world/camera gesture.

Project aim into the XZ plane with the current camera; normalize once. Keep aim preview bounded to range; no world position or client target is authoritative. Stop held actions on death, result, character removal, focus loss and input cancellation. Rebind once after respawn. Use `GuiButton`/input events or the current Input Action System after verifying API behavior; do not mix multiple bindings that double-fire. All input routes call the same client intent function.

Camera target: elevated follow at approximately 60 degrees downward with enough forward lane visibility to see a 40-stud bolt. Tune distance/FOV on phones instead of promising these starting numbers work on every aspect ratio. Smooth following must not hide incoming attacks; disable uncontrolled rotation/zoom for this prototype.

## Complete animation set for the one hero
Store IDs and provenance in `src/shared/AnimationManifest.lua` and `templates/ASSET_REGISTER.md`. Entries initially have ID 0, deliberately meaning missing; never treat them as completed assets.

- Idle: looping, Idle priority; relaxed readable stance.
- Run: looping, Movement priority; adjusts with movement speed; blend from idle.
- Pulse: non-looping Action priority, ~0.45 s, visible impact at 0.15 s.
- ArcBolt: non-looping Action priority, ~0.60 s, release at 0.20 s.
- Slip: non-looping Action priority, ~0.25 s, motion during 0.18 s authorized dash.
- HitReact: non-looping Action priority, ~0.15 s; subtle, no movement lock; skip during casts/dash/death so it never hides telegraphs.
- Death: non-looping Action4 priority, ~0.8 s; hold terminal pose until despawn.
- Spawn: non-looping Action priority, ~0.5 s; interruptible on input; protection ring indicates remaining protection time.
- Victory: non-looping Action priority, ~1.2 s, result screen only; losing player uses idle/death.

No jump, fall, climb, swim or stun mechanic is in scope. Keep the flat arena enclosed and disable those states; if implementation makes any such state reachable, add the missing clip or remove that behavior before release. There is one run speed, so no walk/sprint set is necessary.

## Integration
Use a consistent R15 skeleton and a server-created Animator. Publish clips under the correct creator for the experience and test asset access with a non-owner account. Use Animator:LoadAnimation, retain tracks per character, and clean them on replacement. Verify actual current permissions rather than assuming an asset ID makes it usable. [Animation export](https://create.roblox.com/docs/animation/editor) · [Animator](https://create.roblox.com/docs/reference/engine/classes/Animator).

Server timestamps determine damage; animation markers only align local sound/VFX. Do not send 'animation hit' messages as damage authority. For local prediction, use request sequence IDs to reconcile accepted/denied actions and avoid double animation when the authoritative effect arrives. Choose one replication path per action: local-player Animator replication for hero action clips, with explicit server VFX messages; do not also play the same remote hero clip from both systems. Death/spawn/result presentation must follow authoritative state. Test visibility on the opponent's phone.

Minimum QA: every clip on both players; movement blending; interrupted cast; hit during cast; death during dash; five respawns; three rematches; unavailable asset handling. Missing clips are release blockers, even if the code has a fallback idle pose. See [mobile input](https://create.roblox.com/docs/input/mobile) and [safe insets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets).
