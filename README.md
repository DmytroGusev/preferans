# Preferans iOS

Preferans is a SwiftUI iOS card game for local play and online rooms with friends.

## What is included

- Xcode project: `Preferans.xcodeproj`
- SwiftUI app flow for lobby and table
- Preferans bidding, talon exchange, whist/pass decisions, trick play, claims, and scoring
- Rule variants such as Sochi, Leningrad, Rostov, and classic-style scoring modes
- Online rooms with manual room codes and CloudKit sync
- App Store submission drafts in `AppStore`
- Public legal pages in `docs`

## What is not production-ready yet

- CloudKit production schema must be deployed before public release
- Multiplayer sync needs more real-device race-condition testing
- Full Preferans convention edge cases need continued QA
- Universal links need a real hosted domain before one-tap invite links can replace room-code entry

## Open In Xcode

1. Open `Preferans.xcodeproj`
2. Confirm the bundle identifier and development team
3. Build on a simulator or device
4. Archive from Xcode when submitting a new App Store build

## Legal Pages

- Support: `docs/support.md`
- Privacy Policy: `docs/privacy-policy.md`
- Terms of Use: `docs/terms-of-use.md`

These pages are intended to be published through GitHub Pages for App Store Connect URLs:

- Support URL: `https://dmytrogusev.github.io/preferans/`
- Privacy Policy URL: `https://dmytrogusev.github.io/preferans/privacy-policy.html`
- Terms of Use URL: `https://dmytrogusev.github.io/preferans/terms-of-use.html`

## App Store Notes

The current uploaded build uses Apple services for identity and online sync:

- Sign in with Apple
- iCloud CloudKit

Before public release, deploy the CloudKit schema to Production and test online rooms on at least two real devices under separate Apple IDs.
