# Preferans 1.0.3 (31): Non-Tracking Privacy Correction

2 November 2026. Initially limited to pages/metadata, this task was expanded by
the owner's explicit approval to prepare, upload and select build 31, and use
the existing external TestFlight group. No public
App Review submission or room Worker/container deployment is authorized here.

## Source

Functional baseline is main c462108, the same functional baseline as build 30.
Exact app source commit: `6561e140abaaf9030ab17ff0875bd9dba8afd036`.
The Guru page/metadata migration is included from 23eb204. Build 30's standard
encryption declaration is retained. PRs #8 and #9 are not merged; online bot-seat
controls, Club subscriptions and Firebase drafts are not included.

Changes authored by Codex at the owner's request:

- Remove unused ATT/IDFA code, startup delegate and onboarding tracking requests.
- Remove misleading tracking Settings controls and onboarding permission copy.
- Retain policy/terms links, account deletion, Apple sign-in and owner multiplayer.
- Set the app version to 1.0.3 (31) in Debug and Release configurations.
- Add source/IPA non-tracking guards and onboarding/Settings smoke coverage.

Source hashes, signed IPA verification, test results and delivery receipts belong
in this directory. Generated app archives/IPA files and credentials stay ignored.

## Store Gate

The privacy wizard saved the five actual data types and App Functionality-only
purposes. Name, Gameplay Content, User ID and Product Interaction are marked
not used for tracking. Apple blocked the last Other Diagnostic Data tracking
correction because selected build 30 contains NSUserTrackingUsageDescription.
This is a metadata/binary compatibility blocker, not actual tracking behavior.

Build 31 is now VALID, selected for draft 1.0.3, and IN_BETA_TESTING with Beta
App Review APPROVED for all six existing external testers. Membership/public-link
settings were preserved and notifications enabled. Review notes and all 24
What's New texts were updated; other localization metadata was preserved.

The privacy UI still refuses the final no-tracking answer after selection of
build 31 and in a fresh signed-in page. It continues to display the same
NSUserTrackingUsageDescription validation message, despite the verified new
binary. Whether this is propagation, another version's binary or another Apple
validation condition is not established. The label is NOT fully corrected:
Other Diagnostic Data is still marked used for tracking. Do not submit public
App Review until this is resolved. `apple-support-draft.txt` is prepared but not
sent; no misleading tracking capability was added to satisfy the editor.

The original and fresh privacy dialogs retain the pending No answer. Do not
save the stale Chrome version form over the newer API metadata. Existing
released 1.0.2 (28) and both servers remain unchanged.

For client rollback, reselect build 30 if needed, but do not submit that older
binary with an incompatible privacy declaration. No server rollback is needed:
this update changes no protocol, account namespace, database or gameplay logic.
