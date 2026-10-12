# Claude project instructions

You are implementing this mobile-first 1v1 Roblox MOBA prototype from the files in this repository. Read docs/01_BRIEF.md through docs/07_ACCEPTANCE_TESTS.md before coding. The current user request and confirmed decisions outrank these defaults. The old 3v3 plan is superseded; unavailable old content must not be invented.

## Work contract
1. Inspect the current files and TASK_STATUS.md. State what actually works, then take the next unmet dependency-eligible task from docs/03_TASKS.md.
2. Implement concrete files, not only advice. Keep one reviewable slice per iteration. Prefer simple Luau modules and built-in services; avoid unneeded frameworks/packages.
3. Maintain explicit server authority for membership, damage, cooldowns, targeting, objectives and results. Never trust client damage, origin, target or hit messages. Address client-owned movement separately as specified.
4. Optimize for mobile. Desktop test keys are development helpers only. Do not defer touch until the final day.
5. Preserve one hero's complete animation set and public-playtesting requirement. Never mark zero animation IDs or permission failures complete.
6. Run available checks. For checks requiring Studio/real phones, give exact actions and expected results, mark NOT RUN until evidence arrives, and keep independent work moving. Do not claim to have run Studio, Rojo, published an asset, tested a phone or completed a match without actual evidence.
7. Update TASK_STATUS.md with changed paths, checks and blockers. Record design deviations and why; keep Config, GDD and tests consistent. Mark partial tasks IN_PROGRESS, not DONE.
8. Use the seven-day target and fourteen-calendar-day cap. No feature expansion. Cut decorative work first. Do not ask permission for routine reversible implementation choices; ask only for truly missing requirements or account/paid/publishing actions outside granted access.
9. Do not send messages to testers, buy assets/services, pay platform fees, request secrets, overwrite unrelated places or publish externally without appropriate user authorization. Provide the owner a concrete ready-to-publish candidate/checklist.
10. Stop at release gates. A build with failing P0 criteria is unfinished. On day 14 deliver current source and exact unmet requirements rather than silently extending the schedule.

## Code conventions
Use `--!strict`, descriptive service/controller names, immutable public config and server-only mutable state. Keep remote schemas small/exact, reject NaN/infinity and oversized numbers, rate-limit before expensive work, use server time for cooldowns, and invalidate delayed callbacks by match epoch/character generation. Clean every event connection and spawned instance you own. No DataStores, external HTTP, monetization or plugin dependencies unless later explicitly required.

Use the `.luau` extension (`.server.luau`, `.client.luau`, plain `.luau` for ModuleScripts).

## Build-one-file-at-a-time rule (owner decision, 2026-10-12)
The original starter pack shipped a prebuilt source scaffold (Config, Protocol, AnimationManifest, ActionSchema, RateLimiter, a Smoke test, server/client bootstraps). The owner chose NOT to import it. Code is written one file at a time, each explained and tested in Studio before the next. Docs that mention "the scaffold", "bundled source" or specific `.lua` files describe that unimported pack; treat them as design intent, not as files that exist. Update those docs as the real files land. Remote handlers stay deny-by-default until the matching authoritative implementation exists.

## Reference docs are living documents
`docs/`, `templates/` and this file hold the rules, design and themes. Update them as decisions change rather than leaving them stale; record why in TASK_STATUS.md.

## Static checks (run before asking the owner to test in Studio)
Tools are pinned in `rokit.toml` (luau-lsp, selene). Rojo 7.7.1 is installed separately. If `types/globalTypes.None.d.luau` is missing, download it from `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau`.
```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=types/globalTypes.None.d.luau --sourcemap=sourcemap.json src
selene src
```
Passing these is not runtime evidence; Studio and phone checks remain NOT RUN until the owner reports results.

## Completion report per slice
State: implemented behavior; files changed; checks actually run and results; remaining manual check; next task. Keep concise. On final release, provide the real public URL, source version, tested devices, animation ownership/credits, README and known issues.
