# Claude project instructions

You are implementing a PC-first cooperative fantasy base-defense action game for Roblox (1–5 warriors defend a walled compound and its Base Core against zombie waves; hub with three classes (Mage, Archer, Warrior), gear and persistent progression). Read `docs/01_BRIEF.md` through `docs/06_ACCEPTANCE_TESTS.md` before coding. The current user request and confirmed decisions outrank these defaults.

Genre switch (owner decision 2026-10-20): the earlier mobile-first 1v1 MOBA is archived in `docs/archive/moba/` (design, task log, decisions). Its code in `src/` is being reused; `docs/03_TASKS.md` says which file feeds which task. Archived docs are history, not rules.

## Work contract
1. Inspect the current files and TASK_STATUS.md. State what actually works. The owner chooses the next change one at a time; if they have not, propose the next dependency-eligible task from docs/03_TASKS.md and wait.
2. For broad or structural changes (genre, scope, many files), present the plan first and wait for the owner's go-ahead.
3. Implement concrete files, not only advice. Keep one reviewable slice per iteration. Prefer simple Luau modules and built-in services; avoid unneeded frameworks/packages.
4. Maintain explicit server authority for membership, damage, cooldowns, targeting, waves, Gold, building/repair, credits, progression and results. Never trust client damage, origin, target, hit, currency or placement messages. Address client-owned movement separately as specified.
5. PC (mouse and keyboard) is the launch platform. Mobile is a later port (T26); keep UI and input code easy to adapt but do not build touch until scheduled.
6. Animations are deferred (owner decision 2026-10-20); default Roblox animations are fine until the owner schedules T25.
7. Design items marked OPEN in docs/01_BRIEF.md and docs/02_GDD.md are the owner's to decide; ask before inventing them. Routine reversible implementation choices need no permission.
8. Run available checks. For checks requiring Studio or real devices, give exact actions and expected results, mark NOT RUN until evidence arrives. Do not claim to have run Studio, Rojo, published an asset, tested a device or completed a mission without actual evidence.
9. Update TASK_STATUS.md with changed paths, checks and blockers. Record design deviations and why; keep Config, GDD and tests consistent. Mark partial tasks IN_PROGRESS, not DONE.
10. There is no schedule (owner decision 2026-10-20). Do not expand scope beyond the brief without the owner.
11. Do not send messages to testers, buy assets/services, pay platform fees, request secrets, overwrite unrelated places or publish externally without appropriate user authorization. Provide the owner a concrete ready-to-publish candidate/checklist.
12. Stop at release gates. A build with failing P0 criteria is unfinished.

## Code conventions
Use `--!strict`, descriptive service/controller names, immutable public config and server-only mutable state. Keep remote schemas small/exact, reject NaN/infinity and oversized numbers, rate-limit before expensive work, use server time for cooldowns, and invalidate delayed callbacks by mission epoch/character generation. Clean every event connection and spawned instance you own. DataStores are allowed for persistent progression only, following the rules in docs/05_ARCHITECTURE.md. No external HTTP, monetization or plugin dependencies unless later explicitly required.

Attack and movement animations follow the three approved patterns in `docs/04_CONTROLS_ANIMATIONS.md` ("Standard way to animate attacks"): client-side joint poses through `src/shared/JointPose.luau` triggered by a server event (zombie bite, archer draw); a per-frame rotation added on top of the animation with `JointPose.addRotation` from PreSimulation, for joints the animations hide (Brute smash, owner 2026-10-22); or Roblox default animation tracks played by the server (sword swing). Never edit `Motor6D.C0` directly.

Ground placement (owner 2026-10-23): anything put on or moved onto the ground (bodies, rings, puddles, markers, spawns, effects) finds the real ground with a raycast (Terrain and floors, ignoring characters and units) and rests its lowest point on it. Never trust a height formula alone (root minus HipHeight, `Landscape.heightAt`). Check on, above or below for flat ground, hills and scaled units, and say what to look for in the Studio check.

All UI follows the design system in `docs/11_UI_DESIGN.md` (owner decision 2026-10-21; blocky restyle 2026-10-22): build panels and buttons with `UiTheme.block` / `styleBlock` and text with `UiTheme.text`; read fonts, colours, radii and bar sizes from `src/shared/UiTheme.luau`; never hard-code them in UI scripts.

Use the `.luau` extension (`.server.luau`, `.client.luau`, plain `.luau` for ModuleScripts).

## Build-one-file-at-a-time rule (owner decision, 2026-10-12)
The original starter pack's prebuilt scaffold (Config, Protocol, AnimationManifest, ActionSchema, RateLimiter, Smoke test, bootstraps) was NOT imported. Code is written one file at a time, each explained and tested in Studio before the next. Remote handlers stay deny-by-default until the matching authoritative implementation exists.

## Reference docs are living documents
`docs/`, `templates/` and this file hold the rules, design and themes. Update them as decisions change rather than leaving them stale; record why in TASK_STATUS.md.

## Static checks (run before asking the owner to test in Studio)
Tools are pinned in `rokit.toml` (luau-lsp, selene). Rojo 7.7.1 is installed separately. If `types/globalTypes.None.d.luau` is missing, download it from `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau`.
```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=types/globalTypes.None.d.luau --sourcemap=sourcemap.json src
selene src
```
Never write to `build.rbxlx`: it is the owner's working Studio place and may hold unsaved-to-repo Studio work. Verify builds into the scratchpad instead (`rojo build default.project.json -o <scratchpad>/check.rbxlx`). Studio-made models are brought into the repo by the owner saving them as `.rbxmx` under `assets/`.

Passing these is not runtime evidence; Studio and device checks remain NOT RUN until the owner reports results.

## Completion report per slice
State: implemented behavior; files changed; checks actually run and results; remaining manual check; suggested next task. Keep concise. On final release, provide the real public URL, source version, tested devices, asset ownership/credits, README and known issues.
