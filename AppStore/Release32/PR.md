## Scope

Stacked on release/1.0.3-build-31 (PR #10). Integrates the source-only bot feature
from PR #9 via ef40496, without merging that PR or main. Exact archived app and
deployed Worker source: f4b65759eb107c87592e71a84a63307bd43046c0.

- Host-controlled bot seats/difficulty in public and private waiting rooms.
- Two humans can fill a three/four-seat table with one/two bots.
- Human seats protected; explicit Ready reset/reconfirmation; separate Start.
- Settings Club information, Terms/Privacy/Support links and updated source copy.
- Maintained Guru Club/pricing pages in en/ru/uk; payments/quotas NOT activated.
- Preserve build 31 non-tracking changes and all player data/current engine image.

## Delivery And Verification

- Owner Worker: 58c7f8e0-eb14-43cd-a5dc-46e72f0fba58, no container/config reset.
- Existing engine digest 90d5da73... retained, container version 2 unchanged.
- Worker typecheck, 59 unit, 19 lifecycle tests passed.
- 272 app XCTest (3 gated skips), 24 Swift Testing, zero failures.
- Native two-humans-Ready-then-bot flow passed on iPhone and iPad.
- Real Swift/Worker public/private three/four-seat first-deal cases passed on
  both loopback and the deployed owner service; disposable accounts cleaned up.
- Build 32 VALID; external APPROVED / IN_BETA_TESTING for the existing six testers.
- Signed IPA/source/entitlements/bot request/Guru link checks passed, no ATT/IDFA.
- Full Guru site checks passed; scoped 19 public files verified by exact hashes.

No public Store review submission, build-selection change, localization/keyword
edit, real billing activation or friend's-server modification. Build 31's Apple
privacy-editor gate remains separate and unresolved; do not claim public-review
readiness. Nine existing screenshot deletions and four unrelated duplicate docs
were preserved locally and are not included.

Review the stacked branches together before changing main. Do not deploy the
older main owner image pin or independently merge duplicated PR #9 changes.
Client/server rollback cautions and full receipts are in AppStore/Release32.
