## Scope

- Migrate Preferans support/marketing/legal links to the live Guru of Cards pages.
- Refresh all 24 draft locale release notes while preserving live keywords/descriptions.
- Remove unused ATT/IDFA and first-launch tracking controls in app build 31.
- Upload/select 1.0.3 (31) and distribute to the existing external TestFlight group.
- No Worker/container deployment, bot-feature merge or public App Review submission.

## Verification

- Signed Xcode 27.1 archive/export and strict signature/entitlements checks passed.
- IPA has no tracking usage key, tracking framework linkage or ATT/IDFA symbols.
- 268 app XCTest cases (3 gated skips), 24 Swift Testing cases, zero failures.
- Two focused native UI tests passed on each of iPhone and iPad.
- Build 31 is VALID, selected, externally APPROVED / IN_BETA_TESTING for six existing testers.
- Website scoped publication verified all 16 public HTML/CSS hashes and statuses.

## Remaining Gate

App Privacy is only partially corrected. Five actual data types and App
Functionality-only purposes are saved; four types are not used for tracking.
Apple still blocks removing the last Other Diagnostic Data tracking answer,
citing the old tracking usage key despite the processed/selected non-tracking
binary and a fresh browser session. Do not submit public review until resolved.
Evidence and an unsent Apple support-message draft are in AppStore/Release31.

This branch does not merge PR #8 or #9 and does not change the owner's currently
deployed engine digest. Do not redeploy main's older server configuration as
part of reviewing this client/privacy branch. Existing account/game data is not
reset. Nine unrelated pre-existing local screenshot deletions are not included.
