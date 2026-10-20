# Roblox public publishing checklist

Owner completes account-sensitive actions. This pack does not publish anything. Check eligibility on day one and recheck before release. Platform requirements may change.

## Account feasibility (day one)
- [ ] Choose user/group owner and confirm edit/publish permissions.
- [ ] Check current publishing requirements in the actual account and intended audience. The official page checked 12 October 2026 describes account good standing/age, age checking and a content maturity/compliance questionnaire for Public/Limited reach; wider Kids/Select reach has additional verification, 2FA, subscription-or-fee and evaluation conditions. Do not assume one fixed historical rule applies to every audience.
- [ ] Confirm intended mobile testers are eligible for the chosen reach. Record the requirement screen/blocker, not private identity documents.
- [ ] Allow time for moderation/evaluation. The owner handles verification, subscriptions or fees; Claude must not invent eligibility or promise review timing.

See the current [Roblox publishing requirements and audience settings](https://create.roblox.com/docs/production/publishing/publish-games-and-places). Recheck there for exact thresholds and prices rather than relying on this summary.

## Prepare the build
- [ ] Run all P0 acceptance checks on the candidate, with evidence.
- [ ] Set a clear title/description: prototype, 1v1, touch controls, tower then core objective.
- [ ] Confirm server capacity 2, R15, mobile support, landscape, correct start place and team spawns.
- [ ] Publish all animation/audio/image assets with appropriate ownership/access; verify on another account.
- [ ] Remove test-only controls from live execution; retain safe diagnostics only.
- [ ] Complete required content questionnaire accurately; use permitted original/licensed assets and credits.
- [ ] Save source snapshot and a known-good place version; record candidate identifier.

## Publish and prove access
- [ ] Publish the candidate place from Studio into the intended experience.
- [ ] In Creator Dashboard set its Audience to Public (current docs place this under Configure > Settings); save and confirm actual reach. If UI changes, follow the official guide.
- [ ] Record the real experience ID, start-place ID and copied Roblox experience URL. Do not fabricate IDs.
- [ ] Two non-editor eligible accounts open the link in the Roblox mobile app, join the same public server through allowed friend/server joining, and complete a match plus rematch.
- [ ] Confirm the server runs the latest build; refresh servers through appropriate platform controls if needed and warn active testers before disruption.
- [ ] Record device/build/date, permissions/reach and evidence in TEST_LOG; insert the verified URL in the final README.
- [ ] Retain rollback source/place version. If release introduces a blocker, restore that version and verify it on mobile.

## Delivery gate
A public setting without a successful mobile join is insufficient evidence. A Limited/playtester or private build is useful during development but does not meet this project's public requirement. If eligibility or moderation blocks release by day 14, deliver source and a precise blocker report; label public publication incomplete. Never call it done on the basis of a screenshot alone.
