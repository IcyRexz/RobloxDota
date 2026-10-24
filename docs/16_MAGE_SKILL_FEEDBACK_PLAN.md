# Mage skill feedback plan (T24 Combat feedback, Mage part)

Status: **plan only, nothing built** (owner request 2026-10-24: "go through the game and see the visual effects for the mage skills ... plan out what's needed for the different Roblox systems, be very detailed and cross-check").

How this was made: the audit below comes from **reading the code** on `main` at `ce127bd`. Nobody ran Studio for it, so anything about how an effect *looks* on screen is inferred from the code and marked that way. The guidance comes from the sources listed at the end. Where a source could not be opened directly (Riot's pages were unreachable from the sandbox), only the search summary was used and it is marked "(summary)".

Rules this plan follows (CLAUDE.md): the server decides every hit; effects are display only. Ground effects find the ground with a raycast. HUD pieces use `UiTheme`. Animations stay deferred (T25). **Sound is OPEN** (`docs/13_OPEN_ISSUES.md` §5), so its slice waits for the owner. No assets get bought.

---

## 1. What exists today

Kit numbers are from `Config.Hero` (level 1, no masteries).

| Skill | Input | Rule (server) | Numbers |
|---|---|---|---|
| Lightning Bolt (basic) | LMB, hold repeats | shot cast from the head along the aim, first enemy on the line | range 24, 40 dmg, cooldown 0.75 s, windup 0.15 s |
| Arcane Resonance (passive) | – | every 4th bolt hit deals double | Quick Resonance: every 3rd |
| Chain Bolt (mastery) | – | hit jumps to the nearest other enemy | within 12 studs, 50% dmg |
| Lightning Strike | hold Q to aim, release | area lands after a delay, hits every enemy unit inside | range 40, radius 10, delay 0.35 s, 60 dmg, cooldown 10 s |
| Thunderstorm (mastery) | – | area keeps striking 1 random enemy | 4 s, every 0.8 s, 50% dmg |
| Empowered Lightning (mastery) | – | bigger, harder Strike | radius ×1.4 (14), dmg ×1.4 |
| Teleport | hold E to aim, release | blink to open ground, stops before fences | range 25, cooldown 8 s (Quick Blink: 4.8 s) |

### 1.1 What each skill shows now, phase by phase

Each skill is split into four phases. **Cast** is the moment you press. **Travel / wind-up** is the delay before it hits. **Impact** is the hit itself. **Aftermath** is what stays on screen afterwards.

| Skill | Cast | Travel / wind-up | Impact | Aftermath | HUD | Sound |
|---|---|---|---|---|---|---|
| Bolt | sword "tool slash" animation plays at once on your device (`HeroControls.client.luau`, asset 522635514) | none (the bolt appears only after the server's 0.15 s windup plus network delay) | 6 neon segments, 0.25 studs thick, hand → target, fade 0.28 s; a 1.6-stud neon ball with a PointLight (range 10) at the end; the target gets a white `Highlight` for 0.2 s; damage number for the attacker (`HeroEffects.client.luau`) | none | radial cooldown sweep (`HeroHud.client.luau`) | none |
| Resonance hit | – | – | same bolt plus a neon ball growing 2 → 7 studs over 0.35 s (`SkillEffects.client.luau` `onResonance`) | – | white pips on the BOLT slot; slot turns gold when the next hit triggers | none |
| Chain Bolt | – | – | thin bolt (0.2 studs) from the first target to the second; damage number | – | – | none |
| Strike | aiming: a dashed ring with a faint fill that follows the ground, while Q is held (`GroundRing`) | after the server answers, a second ring shows for the 0.35 s delay | a bolt from 60 studs up (0.6 thick), a ring bursting out from 30% to 100% of the radius over 0.6 s; a damage number per enemy hit | none | sweep | none |
| Thunderstorm | – | – | faint ring for 4 s; every 0.8 s a thin bolt from 45 studs up plus a small ball (1 → 4 studs) | – | – | none |
| Teleport | aiming: a 2.5-stud ring at the landing spot | – | a 2 → 6 stud ball and an 8-stud upward streak where you left; a 1 → 5 stud ball and a small ground ring where you land | – | sweep | none |

Every effect is the same light blue (150, 210, 255) and built from `Neon` Parts animated with `TweenService`. The code uses no ParticleEmitters, Beams, Trails, sounds, camera effects or Lighting post-effects (grep on `src`, 2026-10-24).

### 1.2 Gaps found, most important first

Each gap names the code it comes from.

1. **No sound at all.** Sound is the cheapest strong hit confirmation (Siege, research §3.4). It is OPEN for the owner.
2. **Kills give no feedback.** A zombie at 0 health is just deleted the next server tick (`Minions.server.luau` `updateAll`: `minion.model:Destroy()`). It vanishes without a fall, puff or kill tick. Players can't tell a kill from the zombie walking behind something.
3. **Ability hits don't flash the target.** Only the basic bolt flashes white (`HeroEffects.flashTarget`). Strike, Thunderstorm and Chain only show numbers to the caster. Allies see nothing on the victims.
4. **Wrong or refused casts are silent.**
   - Q or E on cooldown: the aiming ring still shows, and releasing does nothing (`HeroControls.skillReady` just returns).
   - A Teleport spot the server refuses (no room, too high, a fence): the ring looked valid, then nothing happens (`HeroActions.landingSpot` returns nil, and no message is sent).
   - The HUD slot doesn't react when pressed, and doesn't "pop" when the cooldown ends.
5. **There is a gap between pressing and seeing.** Strike's area, bolt and Teleport's effect only start when the server's `SkillFx` arrives, roughly one round trip after release. The aiming ring disappears on release, so for that moment nothing is on screen (inferred from code).
6. **Every hit looks equally important.** A level-1 bolt, a double-damage Resonance hit and a 14-radius Strike all use the same colour and material and differ only in size. Riot (summary): visual impact should match gameplay impact.
7. **First person was not designed for.** The camera is locked first person (`default.project.json` `CameraMode = LockFirstPerson`).
   - Your own Teleport ball (6 studs) is drawn round your own body, so it probably fills your screen for 0.3 s (inferred, check in Studio).
   - The bolt starts at the `RightHand` you can't see, so it appears from below the view.
   - The sword-slash swing isn't visible to you. Fixing the animation is T25, out of scope here.
8. **Every bolt creates new parts and destroys them** (8 parts per bolt). Every Strike creates 56 ring parts (`GroundRing`: 32 dashes + 24 tiles), and the bursting ring re-raycasts all 56 every frame for 0.6 s. That's fine for one Mage. With 5 Mages, Thunderstorm and the horde all at once it is the first thing to measure. Roblox recommends pooling things that are created often (Performance doc).
9. **Effects reach players who can't see them.** `SkillFx` and `HeroAttack` use `FireAllClients`, which includes players in the lobby. Their devices build parts for a battle they can't see.
10. **Some effects can get stuck.** `onStrike` and `onStorm` use `task.delay` with no check that the battle (or the viewer's context) is still the same. Leaving the battle mid-effect can leave parts behind until the delay ends. They do clean up later, so this is minor.
11. **The Strike bolt can end in the air or underground.** When the server pulls an out-of-range point back, it keeps the client's Y (`withinReach`), and `onStrike` aims the bolt at that point without finding the ground. This breaks the ground placement rule.

---

## 2. Principles from the guides

1. **Readable first, pretty second.** VFX should "provide visual clarity for gameplay and minimise visual clutter"; an area effect must "clearly indicate the damage area" (Riot VFX style guide / Illaoi, summary).
   - **For us:** the Strike ring must match the real hit rule. That rule is the unit's root within `radius` (flat distance), so the ring edge sits at exactly `radius`.
2. **The effect must match the hitbox.** A hitbox that doesn't match its effect is a top source of frustration (Riot clarity 2021, summary).
   - **For us:** the bolt must end exactly where the server's shot ended. It already does: `HeroAttack` sends `endPoint`. Keep it that way.
3. **Visual weight should match gameplay weight.** "A small basic attack shouldn't look as big as an ultimate" (Riot, summary).
   - **For us:** Bolt < Chain < Resonance < Storm bolt < Strike, in size, brightness, light, sound and camera.
4. **Every effect has phases: build-up → hit → fade.** Most of an effect's time is the follow-through, and the fade should finish inside the gameplay window (VFX timing guides, secondary sources). The proportions are heuristics.
   - **For us:** every skill gets a short cast flash, a sharp hit peak, and a fade under 1 s, apart from deliberate lingering areas.
5. **Layer the feedback.** One event should show up as an effect in the world, a HUD reaction, a number or marker, and a sound (game-feel guides).
   - **Keep it restrained:** "juice is seasoning".
6. **Confirm hits and especially kills.** Siege removed hit markers that gave away information but kept the kill confirmation, and made blood splatter bigger to confirm hits instead (Ubisoft dev post).
   - **For us:** zombies are never hidden, so a hit marker leaks nothing. Kill confirmation is the bigger gap.
7. **Respond the moment you press.** The press itself must show something instantly, even if the server decides later. This is the same idea as `HeroControls` playing the swing on your own device first.
   - **For us:** predict the *look* on the caster's device, never the result.
8. **Make your own effects easy to tell from allies'.** Your own effects are brightest; allies' are toned down. Nothing should cover your own crosshair (Riot clarity, summary; our UI rule that the crosshair stays clean).
9. **Accessibility.** Avoid camera shake, or let players turn it off; let players turn off or reduce flashing (Xbox Accessibility Guidelines 117/118).
   - **Flash rate:** under 3 flashes per second (Harding test, a secondary source).
   - **First person:** shake is harsher in first person, so keep it tiny and off by default for other players' casts.
10. **No hit-stop.** Freezing time on a heavy hit is a classic single-player trick (guides cite 50–100 ms). We **can't freeze the server simulation** in a co-op game, and freezing only one player's view would hide what the zombies are really doing.
    - **Instead:** a short camera kick and a light flash on your own Strike, and nothing that pauses the world.
11. **Performance is part of the design.**
    - Particle size and count cost GPU fill rate and overdraw.
    - Changing ParticleEmitter properties often can have a "dramatic impact on performance".
    - Shadows from many lights are expensive.
    - Reuse objects that are created often.
    - All four points are from the Roblox Particle emitters and Performance docs.

---

## 3. Target design per skill

Timings come from Config where the rule needs them. New effect numbers go in a new frozen `Config.Fx` table so effects and tests read one source; HUD colours come from `UiTheme`. The numbers here are starting points to tune in Studio.

"You" = the caster's own device. "Allies" = other players' devices. "Both" = everyone.

### 3.1 Lightning Bolt (basic attack)
- **Cast (you, at once on press, before the server answers):**
  - A small crackle at a fixed "staff tip" point in front of the camera: lower right, about 1.5 studs ahead. Use `ParticleEmitter:Emit(4)` from an emitter on a camera-following attachment.
  - Optional cast "tick" sound (S6).
  - This replaces the invisible-hand origin for your own view only.
- **Travel/impact (both, when `HeroAttack` arrives):**
  - Keep the jagged line, but make it look like a hit:
    - core segment white-hot (0.15), a light-blue glow segment around it (0.4, 0.6 transparency)
    - fade 0.12 s for the core, 0.25 s for the glow
  - For allies, start the line from the caster's hand; for you, from the staff tip.
- **Impact on hit (both):**
  - 6–8 spark particles burst from the hit point (`Emit`, lifetime 0.15–0.3 s, speed 8–14, light emission 1).
  - Keep the 0.2 s white `Highlight`.
  - The PointLight goes **only on your own bolts**, so 5 Mages don't light up the field.
- **Miss (both):** the line to the end point, plus 3 dust particles where it stopped (tells you "out of range", which the game now only shows by the red crosshair).
- **HUD (you):** the BOLT slot does a 1-frame press scale (`UiTheme.pressable` already exists for buttons; use the same tween).
- **Numbers:** white, as now.

### 3.2 Arcane Resonance
- **Hierarchy:** this is the "crit" (double damage), so it must look like the biggest single-target event.
  - The bolt core is **gold** (`UiTheme.Gold` for the HUD piece and a matching world colour in `Config.Fx`) and twice as thick.
  - At the target: a ring of 12 sparks plus a 0.25 s flash ball, 2 → 5 studs. That's smaller than today's 7, so it doesn't cover the next target.
- **Numbers:** gold, +6 px, and a "!" pop (FloatingText already has the overshoot).
- **HUD:** when the slot turns gold it pulses once; when it fires, the pips empty with a quick sweep.

### 3.3 Chain Bolt
- A thinner bolt (0.15) from the first target to the second, **arriving 0.06 s later** so the eye follows the jump.
- Small sparks at the second target, and a smaller number (−4 px).

### 3.4 Lightning Strike
- **Aiming (you, while Q is held):**
  - Keep the ground ring, and add a centre crosshair mark.
  - **Ready:** blue rim.
  - **On cooldown:** grey rim with the seconds left in the centre.
- **Cast (you, at once on release):**
  - The aim ring **stays where it was cast and locks**. Its fill brightens over `Strike.Delay` (a sweep from centre to rim) until the server's `Strike` effect replaces it. This removes the empty frames.
  - If the server never answers within 0.5 s (refused), the ring flashes grey and fades. That doubles as refusal feedback.
- **Telegraph (allies):** the ring appears on the ground and fills over `Delay`, so allies know where lightning will fall.
- **Impact (both, at `Delay`):**
  - **Sky bolt:** a jagged column from 60 studs up to the **ground found by a raycast** (fixes gap 11). Draw it with a `Beam` chain or 8 neon segments: a white core and a blue glow.
  - **Ground flash:** a short `PointLight` (range 24, brightness 4, 0.25 s).
  - **Shock ring:** the existing burst (keep it, it hugs the ground).
  - **Debris:** 12–16 particles up and out (`Emit`).
  - **Scorch:** a dark ring decal on the ground that fades over 1.5 s. Use a flat neon-free part with `Material = Slate` and transparency tween, placed with the same raycast probes as `GroundRing`, so it shows where damage *was*.
  - **Every enemy hit:** white flash (the generic hit flash in §4.4).
- **Camera (you only, and only if you're within `radius × 1.5` of the centre):**
  - a 0.15 s kick of at most 0.3° (applied after the default camera, §4.6)
  - Off when the "Screen shake" setting is off (S7). Allies: none.
- **HUD:** sweep as now, plus the ready pop (§4.5).

### 3.5 Thunderstorm
- **Area (both):**
  - A slowly turning ring of dashes at 70% opacity, plus a dim "cloud" disc 25 studs up.
  - The cloud is a flat transparent part with a few slow smoke particles; `Rate` stays low and never changes while running.
  - The area lasts `Storm.Duration`; the ring dims to nothing in the last 0.5 s, so "the storm is ending" can be read.
- **Each storm bolt (both):** a thinner sky bolt (0.35), a smaller light (range 12), 6 sparks, a hit flash.
  - **Flash rate check:** one storm makes 1.25 bolts/s. Two overlapping storms make about 2.5/s, still under 3. Five can't overlap on one spot within the Strike cooldown unless five Mages stack; the "reduce flashing" setting (S7) covers that case.

### 3.6 Empowered Lightning
- **Same Strike, bigger and brighter.** The ring size already follows the mastery (`MageAbilities.strikeRadius`).
- **Add:** a thicker bolt (0.8), a brighter light (range 30), a gold rim on the aim ring, so you can see the mastery is active.

### 3.7 Teleport
- **Aiming (you):**
  - The landing ring shows **whether the spot is valid**.
  - **Valid:** blue ring.
  - **Invalid:** red/grey ring with a small "X" when the client's check of the server's own rule fails (§4.3).
  - **On cooldown:** grey with the seconds left.
- **Cast (you, at once on release):**
  - A screen flash: a full-screen white-blue frame at 0.6 → 1 transparency over 0.15 s.
  - A 0.15 s field-of-view punch: +6° then back.
  - Both are drawn on screen, not in the world, so the world ball no longer engulfs your view.
- **Departure (allies):**
  - An inward burst at the old spot: particles pulled in (`Shape = Sphere`, `ShapeStyle = Surface`, `ShapeInOut = Inward`), plus the 8-stud upward streak.
  - Your own device skips the world ball at the old spot.
- **Path (both):** a straight fading "after-line" from the old spot to the new one, 0.2 s, so allies see where you went. In first person, you see it behind you if you turn.
- **Arrival (both):** the ground ring burst (existing) plus 8 sparks. Allies also see a 1 → 4 ball.
- **Refused (you):** if the server doesn't move you within 0.5 s, the landing ring flashes red and you hear the "denied" sound (S6).
  - **Better long-term:** have the server reply when a cast is refused (§4.2).
- **Quick Blink:** the cooldown sweep only. No world change; it's a stat mastery.

### 3.8 Things that apply to all skills
- **Kill confirmation (you):**
  - When a target *you* damaged reaches 0, the crosshair shows a short red "X" (Crosshair.client).
  - The number of the killing hit is outlined red.
- **Death puff (both):**
  - Every zombie that dies leaves a small puff and fades.
  - Roblox can't fade a body that is already destroyed, so either:
    - (a) the client copies the body's position when its `Health` attribute reaches 0, which happens before the server's `Destroy` on the next tick, or
    - (b) the server keeps the body 0.3 s longer.
  - **Recommend (a):** it needs no server change.
- **Ally view:** allies get thinner lines, no PointLights, no camera effects and no screen flashes. They do get every area telegraph (Strike ring, storm ring), because those tell allies where damage will land.

---

## 4. Shared systems needed, Roblox piece by piece

### 4.1 One effects toolkit: `src/shared/FxKit.luau` (new, used on devices only, like `FloatingText`)
- **Pooled neon parts.**
  - The pool takes and returns parts with `CanCollide/CanQuery/CanTouch = false` and `CastShadow = false`, parented under one `Workspace.Fx` folder that this device owns.
  - Returned parts get `Transparency = 1` and `Parent = nil`; nothing is destroyed per effect.
  - Cap the pool (e.g. 200 parts) and drop the oldest when it runs out.
  - Bolt, burst and the flash ball move to it.
- **Burst emitters.**
  - One `ParticleEmitter` per effect kind (sparks, debris, dust, smoke), created once, on one attachment each under an invisible anchored part.
  - To play: move the attachment, then call `emitter:Emit(n)`. `Rate = 0` always, and properties are never changed per frame (Roblox warns property changes are costly).
- **Textures.**
  - Start with the textures that ship with Roblox (`rbxasset://textures/particles/sparkles_main.dds`, `smoke_main.dds`; **verify the paths in Studio**) so nothing needs licensing.
  - Anything from the Creator Store gets registered in `templates/ASSET_REGISTER.md`.
- **Short lights.**
  - Pooled `PointLight`s with `Shadows = false`, at most 4 alive at once; the oldest is reused.
  - Roblox: limit the number, range and shadows of lights.
- **Quality scaling.**
  - Read `UserSettings():GetService("UserGameSettings").SavedQualityLevel` (**verify it is readable from a LocalScript in Studio**).
  - At low quality: halve particle counts and skip lights.
  - Roblox already scales particles with graphics quality; this adds our own counts on top.
- **Cleanup.**
  - Every delayed piece checks a token: the battle epoch (`Workspace.MatchEpoch`) and `GameContext.is("Battle")`.
  - Leaving the battle returns everything to the pool (fixes gap 10).
- **Ground.** All ground pieces use `GroundRing`-style probes (Terrain + base floor). Points from the server are dropped to the ground before use (fixes gap 11).

### 4.2 Remotes (server → client): keep them small and display-only
- **Keep `SkillFx` and `HeroAttack` as they are.** Clients already validate every message type and bound.
- **Send only to players in the battle** instead of `FireAllClients`: loop `Match.partyMembers()` (gap 9). This is a server change, but only to *who* gets the message.
- **Optional (S2):** a `SkillRefused` message to the caster only, `(action)`, sent where `HeroActions` returns early after accepting the input:
  - `strike` out of reach
  - `teleport` too high or no landing spot
  - Rate-limit it to one per action per 0.5 s.
  - **Never** send the reason in detail. It is a cosmetic "no".
  - Until it exists, devices use the 0.5 s timeout in §3.4 and §3.7.
- **Caster deduplication.** When your own device has already shown the locked Strike ring, the arriving `Strike` effect *replaces* that ring instead of adding a second one. Match by action plus time.

### 4.3 The rule the client uses to preview a valid Teleport spot
- `HeroActions.landingSpot` (ground under the point, not a fence, a 2×5×2 box of room) and the rise limit move to `src/shared/Targeting.luau`, so the server and the marker run **the same function**. That's the same pattern as `stopAtFence` and `castShot` today.
- The server still runs it itself. The client's answer is only a preview.

### 4.4 Hit flash on targets
- A generic "you hit this" white flash on every target in a caster's `Hit` message, plus the `HeroAttack` target as now.
- **Highlight limit:** Roblox shows at most **255** `Highlight`s at once. A 14-radius Strike on a 30-zombie crowd is 30, safe. Still cap our flashes at 40 at once (skip new ones beyond that) so the red aim marker's `Highlight` is never pushed out.
- Allies see the flash for Strike and Storm hits too, if the server includes the target list in the `Strike` impact. **Alternative:** each device watches `Health` attribute drops on units near the Strike centre. **Recommend the watcher.** It needs no new data and also covers turret and soldier damage later. It must ignore drops more than `radius + 2` from any active Strike area, to avoid flashing every hit on the map.

### 4.5 HUD (`HeroHud.client.luau`, `UiTheme` only)
- **Press:** the slot scales to `UiTheme.PressScale` for 0.08 s on every accepted local cast.
- **Denied:** pressing on cooldown makes the slot nudge sideways 3 px twice (0.15 s), with the seconds text briefly bright.
- **Ready pop:** when a cooldown ends, the slot flashes `Light` fill for 0.2 s and pops 1.08 → 1. Never for the basic bolt (0.75 s would flash constantly).
- **Resonance:** see §3.2.
- **Damage numbers:** keep `FloatingText`. Add a `tier` option (`Normal`, `Chain`, `Crit`, `Kill`) that maps to size and colour from `UiTheme`, instead of each script choosing sizes.
- **Strike on a crowd:** 15 numbers at once is clutter. **OPEN for the owner:** show every number at a smaller size (−4 px, more scatter), or one total.

### 4.6 Camera and screen (first person)
- **Camera kick.**
  - Apply a small rotation offset after Roblox's camera has moved each frame: `RunService:BindToRenderStep("FxCamera", Enum.RenderPriority.Camera.Value + 1, ...)`, multiplying `Workspace.CurrentCamera.CFrame` by a decaying rotation (the "trauma" pattern: offset = noise × trauma², trauma falls each frame).
  - Max 0.3°, about 0.15 s.
  - `Humanoid.CameraOffset` is the other option, but it moves the view position, not the angle, so it reads as a bob rather than a kick.
- **Field-of-view punch:** tween `Camera.FieldOfView` +6° and back (0.15 s), restored to the saved value, never assumed to be 70.
- **Screen flash:** a full-screen `Frame` in a high `DisplayOrder` ScreenGui with `IgnoreGuiInset = true`, colour from `Config.Fx`, transparency 0.6 → 1. **One at a time, at most 2 per second.**
- **Lighting:** don't use `Bloom` / `ColorCorrection` for skills. The death screen already owns a `ColorCorrection` in `Lighting` (`DeathScreen.client.luau`), and two scripts tweening Lighting would fight over it.

### 4.7 Sound (S6, **OPEN: needs the owner's decision first**)
- **Which API.** Roblox's own audio guide now calls `Sound`, `SoundGroup` and `SoundEffect` "discouraged" in favour of the audio objects: `AudioPlayer` → `Wire` → `AudioEmitter` (3D) or `AudioDeviceOutput` (2D), heard through an `AudioListener`.
  - **Recommendation: use the new objects.** They're more pieces to set up, so `FxKit` would hold a small pool of pre-wired players.
  - **This is a decision for you.** `Sound` still works and is simpler.
- **Where sounds come from.** Creator Store audio is "free‑to‑use" per Roblox's docs, and the store has more than 100,000 effects from Roblox's partners.
  - Own recordings can be uploaded: 100 per 30 days without ID verification, 2,000 with it. Uploads start private and are granted to the experience.
  - **Every used ID goes in `templates/ASSET_REGISTER.md`**, which the release checklist requires (`docs/08_PUBLIC_PUBLISHING.md`).
- **Sounds needed for the Mage.** Each line is the sound, how it plays (2D = from no place in the world, 3D = from the spot), and who hears it.

| Sound | How it plays | Who hears it |
|---|---|---|
| bolt cast tick | 2D | you |
| bolt hit zap | 3D at the target | both, quieter for allies |
| bolt miss fizz | 3D | you |
| Resonance chime | 2D | you; 3D for allies |
| Chain jump crackle | 3D | both |
| Strike charge | 3D at the area, over the delay | both |
| Strike thunder | 3D, long fade-out | both |
| Storm rumble loop | 3D, 4 s | both |
| storm bolt crack | 3D | both |
| Teleport whoosh out | 3D at the old spot | allies |
| Teleport whoosh | 2D | you |
| Teleport arrive pop | 3D | both |
| denied blip | 2D | you |
| cooldown ready ping | 2D, soft | you, Strike and Teleport only |
| kill tick | 2D | you |

- **Variety:** shift the pitch ±5–8% on repeated sounds (bolt, hits, kill tick), so they don't grate (game-feel guides).
- **Limits:** at most 6 copies of one sound at once; the oldest is cut.

### 4.8 Settings (S7, **OPEN**)
- The lobby's Settings panel exists and says "No settings yet" (`LobbyMenu.client.luau`).
- **Proposed toggles:**
  - Screen shake (on, off)
  - Reduce flashing (off, on): halves light brightness, removes screen flashes, keeps bolts
  - Effects volume (needs S6)
- **Storage:** device-only (`Player:SetAttribute` on the device and its own memory) until saved progression is wanted. Whether to save them is the owner's call.

---

## 5. Performance budget (to check in Studio with the MicroProfiler)
- **Parts:** at most 200 pooled neon parts on screen; a Strike adds ~70 (the ring, the bolt and the scorch).
- **Particles:**
  - Every effect uses `Emit(n)` with n ≤ 16.
  - Roblox's own cap is 400 particles per second per emitter (100 on mobile), so bursts stay far below it.
  - Lifetimes ≤ 0.6 s, except storm smoke ≤ 2 s.
- **Lights:** ≤ 4 at once, `Shadows = false`.
- **Highlights:** ≤ 40 flashes + 1 marker (Roblox limit 255).
- **Raycasts:** the bursting ring is the hot spot (56 a frame). Lay the ring once from the probes and only *scale* it after, or lower the rim dash count for bursts to 20. Measure both.
- **Test scene:** 5 Mages (Studio "Players: 5" test), all with Thunderstorm + Empowered, casting into a 60-zombie wave. Pass = no frame over 33 ms on the owner's baseline PC (baseline still NOT RECORDED in TASK_STATUS).

---

## 6. Build order (one reviewable slice each, owner picks)

Every slice:
- runs luau-lsp, selene (where it works) and a scratch `rojo build`
- lists Studio steps with expected results
- keeps Config, the GDD and `docs/11_UI_DESIGN.md` in step

| Slice | What | Files | Server change? | Studio check (expected) |
|---|---|---|---|---|
| **S1 Toolkit** | `FxKit` (pool, burst emitters, lights, quality scaling, epoch cleanup, ground drop); move the existing bolt, burst and ring code onto it **with the same look** | new `src/shared/FxKit.luau`, `Config.Fx`; edit `HeroEffects`, `SkillEffects` | send effect events only to the battle party (gap 9) | everything looks as before; MicroProfiler shows fewer instance creations; leaving mid-Strike leaves nothing behind |
| **S2 Cast response** | HUD press, denied and ready pop; aim ring states (ready, cooldown, invalid); locked Strike ring until the server answers; Teleport valid-spot preview; refusal timeout | `HeroHud`, `HeroControls`, `SkillEffects`, `Targeting` (shared landing rule) | `landingSpot` moves to `Targeting` (same rule); optional `SkillRefused` | Q on cooldown → grey ring with seconds, slot nudges; E on a rock → red X ring; release Q → ring stays and fills, then the bolt lands |
| **S3 Hits and kills** | staff-tip origin for your bolt; core and glow bolt; sparks; Resonance gold tier; Chain delay; generic hit flash watcher; kill X on the crosshair; death puff; number tiers | `HeroEffects`, `SkillEffects`, `Crosshair`, `FloatingText`, new `src/client/HitFeedback.client.luau` | none | bolts read from just right of the crosshair; every Strike victim flashes; dead zombies puff; the 4th hit is gold |
| **S4 Strike and storm** | telegraph fill, sky bolt to raycast ground, light, debris, scorch, camera kick, Empowered look, storm cloud and fade-out | `SkillEffects`, `FxKit` | none | aim on a hill and at max range: the bolt ends on the ground; camera kicks only when close; 4 s storm visibly ends |
| **S5 Teleport** | screen flash and field-of-view punch for you; inward burst, after-line, arrival sparks for allies | `SkillEffects`, `FxKit` | none | your screen no longer goes blue-white for a long moment; a second player sees the line between both spots |
| **S6 Sound** (OPEN) | the sounds in §4.7 | `FxKit`, `SoundService` setup | none | each sound plays once per event; pitch varies; no stacking past 6 |
| **S7 Settings** (OPEN) | shake, reduced-flashing (and volume) toggles | `LobbyMenu`, `FxKit` | none | toggles change the effects the next time they play |

Dependencies: S1 first; S2–S5 in any order after it; S6 needs the owner's decision and asset IDs; S7 after S4/S5 (it toggles their effects).

---

## 7. OPEN decisions for the owner
1. **Sound:** go ahead with S6? Which API (new audio objects, recommended, or `Sound`)? Creator Store only, or your own uploads?
2. **Strike crowd numbers:** a smaller number per enemy, or one summed number?
3. **Settings:** build S7? Should settings be saved (DataStore) or kept for the session only?
4. **Kill confirmation style:** a red "X" on the crosshair (proposed), or only a kill sound?
5. **Gold for Resonance in the world:** OK, or keep all lightning blue?
6. **Thunderstorm cloud:** a visible dark cloud overhead (proposed), or only the ground ring?

---

## 8. Cross-check

Each claim in the audit against its evidence. "Code" = verified by reading the named file on `main` `ce127bd`. "Doc" = Roblox creator-docs source read 2026-10-24. "Inferred" = needs Studio.

| Claim | Evidence | Kind |
|---|---|---|
| No sounds in `src` | grep for `Sound`: only `TargetInfo.client.luau` removing Sound objects from portrait copies; `docs/13_OPEN_ISSUES.md` §5 agrees | code |
| No particles, beams, trails or camera effects | grep `ParticleEmitter`/`Beam`/`Trail`/`FieldOfView`: no effect use (FieldOfView only in the TargetInfo portrait camera) | code |
| Zombies vanish at death | `Minions.server.luau` `updateAll`: `not CombatService.isAlive(...)` → `minion.model:Destroy()` | code |
| Only the basic bolt flashes the target | `HeroEffects.flashTarget` is called only from the `HeroAttack` handler; `SkillEffects` has no Highlight | code |
| `Health` reaches 0 before removal, so a death puff can read it | `CombatService.applyDamage` sets the `Health` attribute; removal happens in the later `updateAll` tick | code (the timing gap is inferred) |
| Casting on cooldown is silent | `HeroControls.skillReady` → `cast` returns; the aim ring is still drawn by `drawAreas` regardless of cooldown | code |
| A refused Teleport is silent | `HeroActions.teleport` returns with no message when `landingSpot` is nil | code |
| Strike/Teleport effects wait for the server | `SkillEffects` only reacts to `SkillFx` from the server; `HeroControls` hides the aim ring when the key is released | code; the gap's length is inferred |
| Strike bolt can end off the ground | `withinReach` keeps `point.Y`; `onStrike` draws to `point` with no raycast | code |
| Effects are sent to lobby players | `FireAllClients` in `HeroActions.server.luau` (lines 204, 236, 250, 252, 264, 275, 311, 394) | code |
| 56 parts per ring, re-probed every frame in a burst | `GroundRing`: `RIM_DASHES = 32`, fill 8 + 16; `groundBurst` calls `ring:place` every RenderStepped | code |
| First-person camera | `default.project.json` `CameraMode = LockFirstPerson` | code |
| Your own Teleport ball fills your view | ball 2 → 6 studs at your root, camera inside it | **inferred** |
| Highlight limit 255 | Roblox doc "Highlighting objects": "only displays 255 simultaneous Highlight instances" | doc |
| Particle rate cap 400/s (100 mobile), lifetime ≤ 20 s | Roblox doc "Particle emitters" | doc |
| Particle property changes and transparency overdraw are costly | Roblox doc "Improve performance" | doc |
| `Sound` discouraged in favour of audio objects | Roblox doc "Audio objects" alert | doc |
| Creator Store audio free to use; upload limits 100 / 2,000 per 30 days | Roblox doc "Audio assets" | doc |
| `UserGameSettings.SavedQualityLevel` readable on the device; `rbxasset://textures/particles/*` paths | from memory of the Roblox API, **not re-verified here**: check in Studio in S1 | **to verify** |

Consistency with the project rules:
- **Server authority:** no new message lets a client decide anything. The Teleport preview runs the server's rule only as a preview.
- **Ground placement:** S1 adds a ground drop for server points; scorch and rings use raycast probes.
- **UI rule:** HUD changes use `UiTheme` fill, press-scale and `Strength` values; colours for world effects go in `Config.Fx`, not in UI scripts.
- **Animations deferred:** the cast animation is not touched; the staff-tip flash is an effect, not an animation.
- **No scope creep:** everything here is T24 "hit/damage feedback" for the existing Mage kit. Sound and Settings are marked OPEN, not built.

---

## Sources
- Roblox Creator Docs (source on GitHub, `Roblox/creator-docs`, read 2026-10-24): [Particle emitters](https://create.roblox.com/docs/effects/particle-emitters), [Beams](https://create.roblox.com/docs/effects/beams), [Trails](https://create.roblox.com/docs/effects/trails), [Light sources](https://create.roblox.com/docs/effects/light-sources), [Highlighting objects](https://create.roblox.com/docs/effects/highlighting), [Audio objects](https://create.roblox.com/docs/audio/objects), [Audio assets](https://create.roblox.com/docs/audio/assets), [Improve performance](https://create.roblox.com/docs/performance-optimization/improve)
- Riot Games (search summaries; pages unreachable from the sandbox): [League's VFX style guide (2017)](https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/), [Clarity in League (2021)](https://riotgames.com/en/news/dev-clarity-in-league), [Illaoi update](https://nexus.leagueoflegends.com/en-gb/2018/02/resistance-illaoi-the-final-update/), [Dev blog on VFX (2015, via Surrender at 20)](https://www.surrenderat20.net/2015/06/red-post-collection-dev-blog-on-vfx.html?m=1)
- Ubisoft, [Rainbow Six Siege closed alpha feedback](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/4ZXqtA5sxazw8Npy34Tsxw/closed-alpha-feedback) (hit markers removed, kill confirmation kept)
- Microsoft, [Xbox Accessibility Guidelines](https://learn.microsoft.com/en-us/gaming/accessibility/guidelines) (117 camera motion, 118 photosensitivity)
- Game feel (secondary, tuning starting points only): [Where does game feel come from](https://eastondev.com/blog/en/posts/dev/20260521-game-feedback-feel/), [Game feel checklist (Godot forum)](https://forum.godotengine.org/t/game-feel-checklist-for-godot-4-hit-stop-trauma-shake-coyote-time-and-more/145340), [Accessibility testing for indie games (Harding thresholds)](https://bugnet.io/blog/accessibility-testing-for-indie-games); Jonasson & Purho, "Juice it or lose it", GDC 2012 (cited by those posts, not watched)
