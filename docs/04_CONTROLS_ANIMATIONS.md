# Controls and animations

## PC first (owner decision 2026-10-20)
Mouse and keyboard is the launch input. The mobile port is deferred (T26) and the old touch rules are archived in `docs/archive/moba/05_MOBILE_ANIMATIONS.md` as a starting point.

Working assumptions, to confirm with the owner as each task lands:
- **Move:** WASD (Roblox default), relative to the camera. Space jumps (Roblox default power 50, owner 2026-10-20). No climb or swim.
- **Character Menu:** U opens/closes it (or click the gold level badge): stats on the left, upgrade cards on the right when a pick is waiting; click a card or press 1/2/3.
- **Camera:** first person (Roblox `CameraMode = LockFirstPerson`, owner decision 2026-10-20): mouse turns the view, centre crosshair. Shift lock (Roblox's built-in third-person mouse lock) stays off; first person locks the mouse anyway.
- **Fire:** left mouse button, hold to repeat at the weapon's rate. Shoots where the crosshair points (owner 2026-10-20); out of range = miss, no auto-walk. Aim assist: put the crosshair on or right next to an enemy in range and it gets a red outline and your shots go straight at it.
- **Abilities:** keys 1, 2, 3 (ultimate) per hero; abilities **OPEN** (T18).
- **Build/repair:** interact with a build node during the build phase to open its menu (key and UI **OPEN**, T12).
- **Hub:** UI for hero pick, loadout and queue (T17).

Input rules carried from the prototype: all input routes call one client intent function per action; held actions stop on death, results, focus loss and character removal; disabled actions never queue; the server decides every hit.

## Animations (deferred, owner decision 2026-10-20)
No animation set is required for now; the owner will decide scope later (T25). Until then:
- Players use Roblox default character animations; units use the default R15 walk/idle/tool-hold already registered in `templates/ASSET_REGISTER.md`.

### Standard way to animate attacks (owner decision 2026-10-20: use these as the basis for every future attack/movement animation)
The zombie bite, the archer bow draw and the minion sword swing are the approved references. New unit or weapon animations copy one of these two patterns instead of inventing a new one:

1. **Procedural joint poses on the client** (zombie bite, archer bow draw).
   - The server decides the attack and its timing, then fires a server -> client RemoteEvent with only the unit and the timing (`MinionSwing (zombie, hitDelay)`, `MinionShot (archer, target, drawTime, flightTime)`). Clients validate the message (type, finite number, upper bound) and ignore bad ones.
   - Each client tweens body joints itself with `src/shared/JointPose.luau` (`find` / `set` / `tween`), which poses a joint on both Roblox joint systems (Motor6D C0 and the Avatar Joint Upgrade's AnimationConstraint / rig attachment). Never edit `Motor6D.C0` directly: on upgraded rigs it does nothing (this is why the first two zombie swipes were invisible).
   - Poses are offsets on the joint's resting pose, in phases (wind-up, strike, recover) with tween timings derived from the server's timing. Code: `src/client/MinionVisuals.client.luau`.
   - Damage is applied by the server at the moment the strike lands (`task.delay(hitDelay)` / arrow arrival); a unit killed mid-wind-up never lands it. Animation never applies damage.
   - Resting poses set on the server template (e.g. zombie arms forward) also go through `JointPose.set`.
   - **Zombie bite (owner approved, keep):** wind-up leans the body back (waist), strike lunges the upper body and head forward like a bite; the shoulder also moves but the visible effect in Studio is the head lunge. Hit lands 0.3 s in (`Config.Minion.ZombieSwipeHitDelay`).
2. **Roblox default animation tracks on the server** (minion sword swing; walk, idle, tool-hold).
   - Loaded once per unit on its Humanoid's Animator (`loadTrack` in `src/server/Minions.server.luau`), played by the server, replicated by Roblox. Attack tracks use Action priority. Only Roblox-owned default IDs or assets owned by the experience owner, each listed in `templates/ASSET_REGISTER.md`.

Weapon parts (sword, bow) are plain blocks welded to the hand (`addWeaponPart`), decoration only.
- When animations are scheduled, follow the archived integration rules (one Animator per character, tracks cleaned on respawn, publish under the experience owner, verify on a non-owner account, no animation-driven damage).
