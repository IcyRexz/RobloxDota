# Roblox public publishing checklist

The owner completes account-sensitive actions; Claude does not publish. Platform requirements change: recheck the official [publishing guide](https://create.roblox.com/docs/production/publishing/publish-games-and-places) rather than trusting this summary.

## Account feasibility
- [ ] Choose user/group owner; confirm edit/publish permissions.
- [ ] Check current publishing requirements and audience settings for the account (age/verification, maturity questionnaire, reach rules).
- [ ] Confirm intended testers are eligible for the chosen reach.
- [ ] Enable Studio access to API services only if the owner wants DataStores testable in Studio.

## Prepare the build
- [ ] All P0 acceptance checks run with evidence.
- [ ] Clear title/description: co-op base defense, 1–5 players, PC controls (mobile when ported).
- [ ] Server capacity matches the hub/mission design (currently 5), R15, correct start place and spawns.
- [ ] All animation/audio/image/mesh assets owned or licensed, credited, and verified on another account.
- [ ] Temporary test aids and Studio-only controls removed from live execution.
- [ ] DataStore names final; no test data left in the live store.
- [ ] Content questionnaire completed accurately.
- [ ] Source snapshot and known-good place version saved.

## Publish and prove access
- [ ] Publish from Studio into the intended experience; set Audience to Public in Creator Dashboard.
- [ ] Record the real experience ID, place ID and URL (never fabricated).
- [ ] Non-editor accounts join through the public link, finish a mission, rejoin and keep progress.
- [ ] Record device/build/date and evidence in TEST_LOG; put the URL in the README.
- [ ] Keep a rollback version; if release breaks something, restore and re-verify.

A private or playtester-only build helps during development but does not meet the public requirement. A screenshot of settings alone is not evidence.
