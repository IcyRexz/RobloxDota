# Controls and animations

## PC first (owner decision 2026-10-20)
Mouse and keyboard is the launch input. The mobile port is deferred (T26) and the old touch rules are archived in `docs/archive/moba/05_MOBILE_ANIMATIONS.md` as a starting point.

Working assumptions, to confirm with the owner as each task lands:
- **Move:** WASD (Roblox default), relative to the fixed camera. No jump, climb or swim.
- **Camera:** fixed elevated follow camera, no rotation or zoom (`src/client/HeroCamera.client.luau`, kept from the prototype).
- **Fire:** left mouse button, hold to repeat at the weapon's rate. Aim model (mouse-aimed vs auto-target) **OPEN**; the prototype's auto-target path with click/Tab target lock exists today.
- **Abilities:** keys per class (**OPEN**, T18).
- **Build/repair:** interact with a build node during the build phase to open its menu (key and UI **OPEN**, T12).
- **Hub:** UI for class, loadout and queue (T17).

Input rules carried from the prototype: all input routes call one client intent function per action; held actions stop on death, results, focus loss and character removal; disabled actions never queue; the server decides every hit.

## Animations (deferred, owner decision 2026-10-20)
No animation set is required for now; the owner will decide scope later (T25). Until then:
- Players use Roblox default character animations; enemies use the default R15 walk/idle/tool-hold already registered in `templates/ASSET_REGISTER.md`.
- Existing simple server-driven poses stay (prototype swing, archer bow draw).
- When animations are scheduled, follow the archived integration rules (one Animator per character, tracks cleaned on respawn, publish under the experience owner, verify on a non-owner account, no animation-driven damage).
