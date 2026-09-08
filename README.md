# Preferans iOS

Preferans is a SwiftUI iOS card game for local play and online rooms with friends.

## What is included

- Xcode project: `Preferans.xcodeproj`
- SwiftUI app flow for lobby and table, with six persistent appearance themes
- Three- or four-seat bot spectator tables, read-only hands, and instant rematches
- Preferans bidding, talon exchange, whist/pass decisions, trick play, claims, and scoring
- Rule variants such as Sochi, Leningrad, Rostov, and classic-style scoring modes (the lobby surfaces these under our house names — Одеса, Wien, Θεσσαλονίκη, Крути — with hover/tap hints back to the standard names)
- Server-authoritative online tables on Cloudflare, with durable command receipts and automatic reconnect
- Shared Swift rules engine for local and online play; per-player private projections
- App Store submission drafts in `AppStore`
- Public legal pages in `docs`

## What is not production-ready yet

- Multiplayer sync needs more real-device race-condition testing
- Full Preferans convention edge cases need continued QA
- Universal links need a real hosted domain before one-tap invite links can replace room-code entry

## Multiplayer development

Run `bin/dev-online` to start the Linux engine and local Cloudflare rooms. See
[the multiplayer contract](docs/MULTIPLAYER.md) and [Worker guide](workers/room-worker/README.md)
for tests, protocol details, and deployment. Protocol 4 is a clean break from old rooms.

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

The current uploaded build uses Sign in with Apple for optional identity and
the Preferans room service for online sync:

- Sign in with Apple
- In-app email/Gmail test profile
- Cloudflare-hosted account, room, and recovery storage

Before public release, test online rooms on at least two real devices under
separate accounts.
