# UI design system

Owner decision 2026-10-21: **this is the one design standard for every piece of UI in the game.** New UI follows it; existing UI was restyled to it. The values live in code in `src/shared/UiTheme.luau`. Scripts read them from there and never hard-code their own fonts or colours. Change the theme file and everything follows.

Goal: minimal, clean and readable mid-fight. Few shapes, no outlines, and one accent, so the battlefield stays the focus.

## The six rules
1. **One font: Builder Sans** (Roblox's own UI font, built in). Weight and size carry the hierarchy, never a second font.
2. **One surface:** a see-through dark panel (`Surface`, 62% opaque on the HUD, 82% for full menus). No thick borders, no outlines, small consistent corner rounding (8 px; 12 px for whole menus).
3. **One accent: gold**, only for progress and rewards: level, XP, Gold, talents, the hovered or selected card, and the pending-pick hint. Everything else is **white at three strengths**: full for values, about 65% for labels, about 40% for captions, locked items and hints.
4. **Colours with a fixed meaning only:** green = friendly health, red = enemy health (and damage you take). No decorative colours: no purple badges, no blue outlines, no team-coloured banners.
5. **Thin bars, label above:** health 8 px, XP 3 px, structure 5 px, unit 4 px. Names and numbers sit above or beside the bar, never inside it. No segment ticks.
6. **Spacing in steps of 4 px** (`UiTheme.space(n)`).

## Tokens (`src/shared/UiTheme.luau`)
| Token | Value | Use |
|---|---|---|
| `Font.Regular / Medium / Bold / Heavy` | Builder Sans 400 / 500 / 700 / 800 | Body / labels / values / headings and names |
| `TextSize` | Caption 11, Small 12, Body 14, Value 16, Title 19, Heading 24 | |
| `Surface` | RGB 12, 14, 18 | Every panel |
| `SurfaceTransparency` / `MenuTransparency` | 0.38 / 0.18 | HUD pieces / full menus |
| `TrackTransparency` | 0.45 | Empty part of a bar |
| `Raised` at `RaisedTransparency` 0.94 (hover 0.90, disabled 0.96) | white 6% (10%, 4%) | Cards and slots inside a menu |
| `Radius` / `RadiusLarge` | 8 / 12 px | |
| `Scrim` at 0.5 | black 50% | Dims the game behind a menu |
| `Text` with `Strength.Value / Label / Faint` | white at TextTransparency 0 / 0.35 / 0.6 | |
| `Gold` | RGB 245, 196, 81 | The accent |
| `OnGold` | RGB 26, 20, 8 | Text on a gold fill |
| `Ally` / `Enemy` | RGB 94, 211, 126 / 229, 83, 75 | Health meaning only |
| `Bar.Health / Xp / Structure / Unit` | 8 / 3 / 5 / 4 px | |
| `Scale` / `MenuScale` | 1.4 / 1.5 | Every screen element is drawn this much larger than its layout numbers (`UiTheme.applyScale`), growing around its anchor; menus still shrink to fit small screens. Layout numbers in this doc are at 1x. |

Helpers: `UiTheme.text`, `UiTheme.panel`, `UiTheme.bar`, `UiTheme.corner`, `UiTheme.space`, `UiTheme.floatingText` (soft dark shadow for text that floats over the world).

## Components
- **Bottom HUD** (`HeroHud.client.luau`): a level ring (52 px circle, surface fill, 2 px gold ring, "LV" caption above the number). The ring is a quiet white line normally and turns gold with a soft pulsing glow only while a talent pick is waiting. To its right, a block 300 px wide: hero name (label strength) and "600 / 600" (value) above an 8 px health bar, then a 3 px gold XP bar with "xp / next XP" (caption, label strength) to its right. Under that, ability slots (40 px, surface, rounded; key hint top-left as a caption; locked slots dimmer with a faint number). **Cooldown: a circular sweep** (`UiTheme.radialCover`): a dark wedge that disappears like a clock hand, with the seconds in the centre. A pending talent pick shows a gold **"LEVEL UP" pill** above the ring (a dark round key chip with a gold "U", then "LEVEL UP" or "LEVEL UP x2"), bobbing gently. Ability slots are dim with only their key until unlocked, then show their name (BOLT, STRIKE, DASH, BALL).
- **Target panel** (`TargetInfo.client.luau`, top centre, flush near the top): what you are aiming at (the enemy under the red marker). A surface panel with a round 44 px portrait (a 3D view of the unit's head; buildings show a short tag), the name and "current / max" above an 8 px health bar (enemy red, ally green). Lingers 0.6 s after you look away, then fades.
- **Overhead bars** (other players, structures, minions): name in floating white text above a thin bar (5 px structures, 4 px units/heroes), ally green or enemy red. No numbers inside, no ticks.
- **Gold counter** (flush in the window's top-right corner, 12 px in, over the top bar area): a surface pill with a 12 px gold dot and the amount in Heavy 16. Earned gold pops a floating gold "+N" from the kill.
- **Character Menu** (`CharacterMenu.client.luau`, U): scrim, then one large menu surface (radius 12). Left about 38%: level ring, name, hero, 3 px gold XP bar with "xp / next XP", then ATTRIBUTES / ABILITIES / TALENTS captions (Caption, Bold, faint, letter-spaced via caps) with label-left, value-right rows and 40 px slots. Right about 62%: "Choose a talent" (Heading) with a gold "Level up" line and three cards (raised white 6%, radius 10; hover or selected = 1 px gold inner line; short gold stat tag, name, description at label strength, "60 → 90" with the new value in gold). Hover tooltips use the surface at 0.1 with no border.
- **Banners** (`Announcements.client.luau`): a surface pill at the upper middle, headline Heavy 22 in white, subline at label strength. No team colours.
- **Crosshair**: white, turning enemy red exactly while the red target marker is on (a click would hit).
- **Minimap**: the map inside a surface panel (radius 8); dots use ally green and enemy red; you are a white dot with a facing tick.
- **Floating text** (`src/shared/FloatingText.luau`, damage numbers and "+1" gold): Builder Sans Heavy with a soft shadow; pops in slightly small, springs to 125% and settles (0.3 s), holds 0.45 s, then drifts up and fades (0.9 s). White for damage you deal, enemy red for damage you take, gold for gold; bigger hits get bigger numbers.

## Not covered: things in the game world
Effects that are part of the world rather than the interface keep their own colours: the lightning bolt, arrows, tower shots, the red target ring on the ground, ability area markers, and the minimap's muted picture of the ground, fences, trees and rocks. Area markers on the ground use `src/shared/GroundRing.luau` (a dashed rim and faint fill whose pieces follow the ground's shape). Anything drawn as interface on top of the game (text, bars, panels, buttons, markers on the minimap) follows this system.

## Writing
Plain words, sentence case for sentences, short labels. Stats are named plainly: Health, Damage, Move Speed, Attack Speed, Range. Upgrades are **talents**. Captions are short and may be uppercase (ATTRIBUTES).

## Process
- New or changed UI must use `UiTheme`: no raw fonts, colours or radii in UI scripts.
- If something truly needs a new token, add it to `UiTheme.luau` and to this doc in the same change, and record why in `TASK_STATUS.md`.
