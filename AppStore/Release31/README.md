# Preferans 1.0.3 (31): Non-Tracking Privacy Correction

2 November 2026. Initially limited to pages/metadata, this task was expanded by
the owner's explicit approval to prepare, upload and select build 31. No public
App Review submission or room Worker/container deployment is authorized here.

## Source

Functional baseline is main c462108, the same functional baseline as build 30.
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

After build 31 processes, select it for draft 1.0.3, finish/publish the last
non-tracking answer and read the UI back. Do not submit while that gate remains.
Existing released 1.0.2 (28) and the server must remain unchanged.

For client rollback, reselect build 30 if needed, but do not submit that older
binary with an incompatible privacy declaration. No server rollback is needed:
this update changes no protocol, account namespace, database or gameplay logic.
