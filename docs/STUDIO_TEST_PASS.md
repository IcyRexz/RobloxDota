# Studio test pass (2026-10-21)

One pass over everything built since the Mage rewrite, before the match loop is started.
Tick each box, write PASS / FAIL and a note (screenshot or Output line for any FAIL).
Static checks (luau-lsp, selene, scratch `rojo build`) passed on 2026-10-21; nothing below has run yet.

## 0. Setup

- [ ] 0.1 Run `rojo serve default.project.json`, open `build.rbxlx` in Studio, connect the Rojo plugin. **Expect:** plugin says Connected, no sync errors.
- [ ] 0.2 Record versions in TASK_STATUS.md line 8: Studio (File > About Studio... or Help > About) and the Rojo plugin version.
- [ ] 0.3 Open View > Output and View > Script Performance. Keep Output visible for every test.
- [ ] 0.4 Terrain bake (once): in Edit mode, Command Bar: `require(game.ServerScriptService.Server.Landscape).buildTerrain()`. Save the place. **Expect:** hills appear in Edit view.

**Optional fast-test settings** (in `src/shared/Config.luau`, revert after section 5):
- `Hero.Leveling.XpToLevel = { 3 }`: level 5 after about 12 zombie deaths instead of 120.
- `Structure.TestStartHealth = { LeftTower = 10, MeleeBarracks = 10 }`: structures that die in one or two hits.

## 1. Start-up (solo, Play / F5)

- [ ] 1.1 Output on start. **Expect:** `[Landscape] baked terrain found in the place; not rebuilding it`; `[Minions] zombie ...` joint line; no red errors or `warn` lines about heights.
- [ ] 1.2 Spawn. **Expect:** you stand on the round raised SpawnPad, in first person, centre crosshair, no Roblox player list.
- [ ] 1.3 HUD. **Expect:** bottom, no box behind it, no name: navy level ring "1", chunky green health bar with "500 / 500" inside, gold XP bar with "0 / 30 XP" beside it, blue slots BOLT (LMB chip, Resonance pips along its bottom) / STRIKE (Q) / TELEPORT (E); BOLT turns gold when the next bolt triggers Resonance; all text white with a thin dark outline, holes in o / e / a stay open; top right Gold 1000; minimap bottom right; party list top left.
- [ ] 1.4 Nature. **Expect:** pine trees stand on the hills (trunks touch the ground, not floating or buried), model rocks visible and not sunk out of sight, no green/grey see-through blocks.
- [ ] 1.5 Fences. **Expect:** fence art along every base edge, no gaps, both front corners open.

## 2. Movement and camera

- [ ] 2.1 WASD, jump (Space). **Expect:** smooth, jump works, cannot walk through fences, trees or rocks.
- [ ] 2.1a Dev panel HERO Die (solo). **Expect:** the body lies down where you stood, grey screen with "YOU DIED" and "Respawn in 5" counting down, "You have fallen" popup on the right, crosshair gone, the mouse orbits the camera round the body and the wheel zooms, WASD/Space do nothing; at 0 you appear on the pad at full health in first person with colour back.
- [ ] 2.1b Resize the Studio window (or try 1280x720 and full screen). **Expect:** HUD, minimap, party list, Gold, target panel and menus grow and shrink with the window height and stay on screen.
- [ ] 2.1c Hold Q, press and hold E, release Q, then release E. **Expect:** Strike casts on Q's release (if off cooldown), then Teleport on E's. Aim the teleport marker past a fence: it stops just before the fence and you land there.
- [ ] 2.1d Watch the timer above the minimap's top right. **Expect:** counts up from 0:00; during a Zombie Surge a red "Zombie Surge 0:45" pill counts down beside it and disappears at the end. Only plain zombies until 4:00 ("THE BRUTES ARRIVE" banner), Spitters from 8:00. Brutes are clearly darker than zombies, eyes red at eye height with no face behind them, blood streaks and rot patches visible (check the details sit on the body, not floating or hidden inside it).
- [ ] 2.2 Walk to the map edge. **Expect:** forest belt + invisible boundary stops you.

## 3. Lightning Bolt (left mouse)

- [ ] 3.1 Aim at a zombie further than 24 studs. **Expect:** crosshair white, no red marker; clicking fires a bolt that ends short and deals no damage.
- [ ] 3.2 Aim at a zombie within 24 studs. **Expect:** red marker + red crosshair, top-centre target panel (head portrait, name, HP); click hits, damage number pops (about 40).
- [ ] 3.3 Hold left mouse. **Expect:** one shot every 0.75 s, not faster.
- [ ] 3.4 Shoot through a fence at a zombie outside. **Expect:** hits. Shoot at a zombie behind a tree or rock. **Expect:** blocked.
- [ ] 3.5 Arcane Resonance. **Expect:** pips fill per hit; every 4th hit deals double (about 80) with its effect.
- [ ] 3.6 Kill a zombie with the last hit. **Expect:** "+1" gold popup, counter springs to 1001, `Kills` goes up on the Tab board.

## 4. Abilities

- [ ] 4.1 Hold Q. **Expect:** dashed ring on the ground hugging the slope, within 40 studs. Release. **Expect:** bolt lands after about 0.35 s, zombies in radius 10 take about 60, STRIKE slot shows a 10 s radial cooldown.
- [ ] 4.2 Press Q during cooldown. **Expect:** nothing.
- [ ] 4.3 Hold E, aim at open ground within 25 studs, release. **Expect:** you land there instantly, no snap back or rubber-band within 1 s, 8 s cooldown.
- [ ] 4.4 Teleport aiming into a tree, rock or structure. **Expect:** refused or moved to the nearest open ground, never stuck inside.
- [ ] 4.5 Teleport across a fence from inside to outside, and back. **Expect:** works (current rule). Note if it feels wrong.
- [ ] 4.6 Teleport while walking and jumping. **Expect:** no flinging, falling through the map or camera glitch.

## 5. Levels, growth, masteries (Character Menu, U)

- [ ] 5.1 Any zombie death (by soldiers too). **Expect:** XP bar fills; at 30 XP level 2, `[HeroProgress] ... reached level 2` in Output, max health +20.
- [ ] 5.2 Press U. **Expect:** Character Menu opens, mouse is free, left: abilities + Health Regen 0.5/s etc., right: 3x3 mastery grid all locked (grey) before level 5, with the info area under it (blocky window titled "Character", red X closes it). Q/E/left click do nothing while it is open. U again closes it, first person returns.
- [ ] 5.3 At level 5. **Expect:** gold "MASTERY" pill on the HUD; in the menu tiles are open; click Chain Bolt (**Expect:** it only shows in the info area, nothing is picked), then press the gold PICK! button. **Expect:** `took mastery ChainBolt` in Output, tile marked taken, pill gone; next bolt jumps to a second zombie for about half damage.
- [ ] 5.4 Take Thunderstorm (needs level 10, or use the fast setting). **Expect:** Strike leaves a storm hitting a random zombie in the area every 0.8 s for 4 s.
- [ ] 5.5 Quick Blink. **Expect:** Teleport cooldown shows about 4.8 s.
- [ ] 5.6 Vitality. **Expect:** max health +25% on the HUD and in the menu.
- [ ] 5.7 Die (walk into a zombie pack). **Expect:** respawn after 5 s on the pad at full health; level, XP and masteries kept.
- [ ] 5.8 Take damage then stand still away from zombies for 20 s. **Expect:** health rises by about 10 (0.5/s).

## 6. Base Upgrades (F at the Upgrade Workbench)

- [ ] 6.1 Walk to the workbench. **Expect:** "Open Upgrades" prompt with key F (not E). Press F. **Expect:** blocky menu titled "Base Upgrades" on the gold rim (no icon) with a red X top right; Buildings / Warriors / Archers cards on the left; 3x2 tiles on the right showing name + orange "Improves" line + a small green "<cost> Gold" button; info area under the tiles with only the upgrade text (no cost line) and a green "<cost> Gold" button in its bottom-right corner. Clicking a category card shows that category in the info area. Clicking the X closes it.
- [ ] 6.2 Buy Stone Walls (150). **Expect:** Gold 1000 -> 850, `[BaseUpgrades] ... bought StoneWalls`, tower max health +25% on its bar, tile turns green with a check; the info button says OWNED.
- [ ] 6.3 Buy Reinforcements (Melee). **Expect:** the next group spawns 3 swordsmen per barracks instead of 2; menu "Per barracks" number updates.
- [ ] 6.4 Buy Watchtowers. **Expect:** tower range ring larger (+6), towers shoot further.
- [ ] 6.5 Spend down to under 150 Gold. **Expect:** the info button of an unaffordable upgrade is grey; clicking it (or the tile) shows the red "Not Enough Gold" chip; Gold never goes negative.
- [ ] 6.6 Open the menu, walk away (or teleport) more than 16 studs, click a tile. **Expect:** purchase refused.
- [ ] 6.7 Every text in the menu is readable, nothing overlaps or clips.

## 7. Waves, soldiers, structures

- [ ] 7.1 Spawning starts about 5 s in and never stops (tug of war, updated 2026-10-22). **Expect:** a group of 4 zombies (some Brutes and Spitters) every 4 s from a ring around the single Zombie Core at the back; 2 swordsmen + 1 archer from each barracks every 15 s.
- [ ] 7.2 Zombies fan out across the field, then funnel into both base openings; none stuck on towers, fences, trees or rocks for more than a few seconds. Soldiers push toward the Zombie Core and hit it when they reach it.
- [ ] 7.3 Zombie bite visible (head forward), archer draw visible, arrows and tower shots fly.
- [ ] 7.4 Health bars only within 60 studs; structure bars show name + icon.
- [ ] 7.5 Let a tower die (fast setting or wait). **Expect:** it disappears, banner "... destroyed", `[Structures] LeftTower destroyed by Zombies`, removed from the minimap, zombies path through.
- [ ] 7.6 Let MeleeBarracks die. **Expect:** no more swordsmen from it; menu "Per barracks" reflects it.
- [ ] 7.7 Let BaseCore die. **Expect (known gap):** it vanishes, banner shows, match keeps running. Note anything else that happens (errors, zombies freezing).

## 8. Performance (solo, after 5 minutes of waves)

- [ ] 8.1 Count units (minimap dots or Explorer). **Expect:** up to 100 humanoids alive.
- [ ] 8.2 Shift+F5 (render stats) or the F9 Developer Console. Record client FPS at the base opening during a fight: ______ fps. **Target:** 60, acceptable 45+.
- [ ] 8.3 Script Performance window: record the top 3 scripts by activity: ______. **Expect:** Minions.server under about 20%.
- [ ] 8.4 Note whether zombies stop spawning while many soldiers are alive (shared cap of 100).

## 9. Small window

- [ ] 9.1 Resize the Studio game window to about 1280x720, then about 1024x600 (or Test > Device emulator, a laptop preset). **Expect:** HUD, Gold, minimap, party list and banners do not overlap; Character Menu, Base Upgrades menu and Tab board shrink to fit with nothing cut off.
- [ ] 9.2 Open chat. Note whether the chat window covers the party list.

## 10. Two players (Test > Clients and Servers: Local Server, 2 players, Start)

- [ ] 10.1 Both spawn on the pad. Party list shows both with level and health; hold Tab: both rows with name, class, level, kills, mastery chips, Gold.
- [ ] 10.2 Player 1 kills a zombie. **Expect:** only player 1's Gold and Kills go up; both get XP.
- [ ] 10.3 Player 1 buys an upgrade. **Expect:** player 2's menu shows it owned instantly; player 2's Gold unchanged.
- [ ] 10.4 Both buy the same tile at the same moment. **Expect:** one succeeds, the other is refused and keeps their Gold.
- [ ] 10.5 Both take War Drums. **Expect:** soldier attack speed bonus is +15%, not +30% (no stacking). Same for Storm Banner: +10% with two Mages.
- [ ] 10.6 Player 2 teleports and casts Strike. **Expect:** player 1 sees the effects at the right place.
- [ ] 10.7 Player 2 leaves (close their window). **Expect:** removed from party list and Tab board, no errors in the server Output.
- [ ] 10.8a Player 2 dies (dev panel HERO Die, or let zombies kill them). **Expect:** both see "Player2 has fallen" on the right; player 2's screen goes grey with "YOU DIED", a countdown (5 s at level 1) and the revive hint, the camera orbiting the body, which lies on its back; player 1's party list shows player 2's portrait grey with a shrinking wedge and the seconds.
- [ ] 10.8b Player 1 walks to the body. **Expect:** a "F Revive Player2" block over it; hold F 3 s: the bar fills, player 2 sees "Player1 is reviving you" with a filling bar, and player 2's portrait ring turns green in player 1's party list. Let go early: everything resets.
- [ ] 10.8c Complete the hold. **Expect:** player 2 stands up where they fell with 30% health, colour and controls back, "YOU HAVE BEEN REVIVED" banner; both see "Player1 revived Player2"; zombies cannot hurt player 2 for about 2 s.
- [ ] 10.8d Player 2 dies again. **Expect:** no revive prompt this time; the hint says already revived; after the countdown they respawn at the pad with full health.
- [ ] 10.8 Check the server Output window (not just the clients'). **Expect:** no red errors.

## Report back

For each section: PASS / FAIL count, and for every FAIL the step number, what happened and any Output error text. Plus the numbers from 8.2 and 8.3 and the versions from 0.2.
