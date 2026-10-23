# Monetization ideas (parked)

Owner note 2026-10-23: "keep this in as potential Robux points". **Not in scope.** `docs/01_BRIEF.md` still lists paid products/monetization as out of scope; nothing here gets built until the owner moves it into the brief and `docs/03_TASKS.md`. Prices, which items exist, and whether anything affects gameplay are all OPEN.

## Reference
`docs/reference/store_style_tab_example.webp`: the Style tab of another game's store (a military army game). What it shows:
- **Store layout:** left tab column (Featured, Gold, Commander, Arsenal, Elite Units, Style, Calls), premium-currency counter with a "+" buy button top right, sections with a title and a one-line explainer, horizontal rows of locked tiles (padlock icon), a "Wearing" highlight on the equipped one, and a "More below" scroll hint.
- **Army camo:** one purchase re-skins every allied unit; friend-or-foe marks keep team colours so it never hurts readability.
- **Base style:** a glow colour that lights the base at night, and emblems that fly on every flag.
- **Other tabs:** Gold packs, commander perks, weapons, elite units, one-off "calls" (support strikes).

## How it could map to this game
Cosmetic first (safe in co-op, no balance work):
- **Soldier livery:** colour/pattern sets for our allied soldiers (like army camo). Team colour cues and health bars stay unchanged.
- **Base style:** banner emblems on base flags and towers; a glow colour for the base at night (only if a day/night cycle exists).
- **Hero cosmetics:** class outfits, spell/arrow/sword effect colours, kill effects.
- **Fence and tower skins** for the base.

Convenience or power (needs an owner call on pay-to-win in co-op):
- **Gold boost** at match start or **credit boost** for persistent progression.
- **Elite soldiers:** a stronger allied unit type unlocked with Robux.
- **Calls:** one-use support abilities (e.g. a lightning strike on a zone) bought per match.

## Before anything is built
- Owner moves monetization into scope in `docs/01_BRIEF.md`.
- Decide cosmetic-only vs. any power, and premium-currency vs. direct Robux prices.
- Roblox rules: Developer Products (consumables) and Game Passes (permanent), `MarketplaceService.ProcessReceipt` handled server-side and idempotently, purchases saved through the DataStore rules in `docs/05_ARCHITECTURE.md`.
- Store UI follows `docs/11_UI_DESIGN.md` (`UiTheme`).
