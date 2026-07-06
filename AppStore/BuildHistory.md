# Build History

This file records App Store/TestFlight build provenance and review-facing changes.

## 1.0 (24) - App Store Connect

- Date: 2026-07-06
- Git commit: `fda2fa4 Add first launch onboarding and ATT prompt path for build 24`
- Operational change made by: Codex in the onboarding and ATT reliability session
- Source base: build `1.0 (23)`, commit `b37c4c1`
- App Store upload: uploaded successfully; package processed as `VALID` and attached to version `1.0`

Changes:

- Added a first-run four-slide onboarding experience with native SwiftUI illustrations for cards, table play, online room invites, and pulka scoring.
- Added a persistent onboarding completion flag so the flow appears only after a fresh install/reset.
- Added an explicit onboarding-level ATT request path: the app asks automatically after onboarding appears, and retries on onboarding completion if iOS status is still `notDetermined`.
- Bumped `CURRENT_PROJECT_VERSION` from `23` to `24`.

Verification:

- `xcodebuild build -project Preferans.xcodeproj -scheme Preferans -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild archive -project Preferans.xcodeproj -scheme Preferans -configuration Release -destination 'generic/platform=iOS'`
- `xcodebuild -exportArchive` with App Store Connect API key upload
- App Store Connect API check: version `1.0`, state `PREPARE_FOR_SUBMISSION`, attached build `24`

## 1.0 (23) - App Store Connect

- Date: 2026-07-06
- Git commit: `5c0e570 Request ATT from active app lifecycle for build 23`
- Operational change made by: Codex in the ATT prompt fix session
- Source base: build `1.0 (22)`, commit `d2cb285`
- App Store upload: uploaded successfully; package processed as `VALID` and attached to version `1.0`

Changes:

- Moved the automatic App Tracking Transparency request from a SwiftUI scene-phase modifier to a UIKit `UIApplicationDelegate.applicationDidBecomeActive` hook.
- Kept a one-second delay after active launch so the system prompt is requested only after the first screen is visible.
- Bumped `CURRENT_PROJECT_VERSION` from `22` to `23`.

Verification:

- `xcodebuild build -project Preferans.xcodeproj -scheme Preferans -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild archive -project Preferans.xcodeproj -scheme Preferans -configuration Release -destination 'generic/platform=iOS'`
- `xcodebuild -exportArchive` with App Store Connect API key upload
- App Store Connect API check: version `1.0`, state `PREPARE_FOR_SUBMISSION`, attached build `23`

## 1.0 (22) - App Store Connect

- Date: 2026-07-06
- Git commit: `d1b7849 Fix first launch ATT prompt gating for build 22`
- Operational change made by: Codex in the ATT prompt fix session
- Source base: build `1.0 (21)`, commit `3ec23d5`

Changes:

- Changed first-launch ATT request logic to use the real iOS `ATTrackingManager.trackingAuthorizationStatus` instead of suppressing the prompt with the app's local `trackingPermissionRequested` audit flag.
- Moved the automatic request to the active scene phase so iOS can present the system prompt after the first screen is visible.
- Bumped `CURRENT_PROJECT_VERSION` from `21` to `22`.

Verification:

- `xcodebuild build -project Preferans.xcodeproj -scheme Preferans -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`

## 1.0 (21) - App Store Connect

- Date: 2026-07-06
- Git commit: `ffa2419 Request ATT permission on first launch for build 21`
- Operational change made by: Codex in the App Store privacy-compliance session
- Source base: build `1.0 (20)`, commit `9dd7b2a`
- App Store upload: uploaded successfully; package processed as `VALID` and attached to version `1.0`

Changes:

- Added a first-launch App Tracking Transparency request path so the system permission sheet appears automatically when iOS tracking status is not determined.
- Kept the Settings -> Privacy status and manual request button for reviewers and users who inspect privacy controls later.
- Bumped `CURRENT_PROJECT_VERSION` from `20` to `21`.

Verification:

- `xcodebuild build -project Preferans.xcodeproj -scheme Preferans -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild archive -project Preferans.xcodeproj -scheme Preferans -configuration Release -destination 'generic/platform=iOS'`
- `xcodebuild -exportArchive` with App Store Connect API key upload
- App Store Connect API check: version `1.0`, state `PREPARE_FOR_SUBMISSION`, attached build `21`

## 1.0 (20) - App Store Connect

- Date: 2026-07-03
- Git tag: `appstore/1.0-build-20`
- Git commit: `a529b54 Fix launch crash for App Store build 20`
- Repository author recorded by Git: `DmytroGusev <dmytro.gusev@gmail.com>`
- Operational change made by: Codex in the App Store review-fix session
- Source base: build `1.0 (19)`, commit `32c0389`
- App Store upload: uploaded successfully; package processing started in App Store Connect

Changes:

- Fixed launch crash found after App Review rejected build `1.0 (19)`.
- Removed the unused launch-time `HostedOnlineGameCoordinator` from `PreferansApp`.
- This prevents `defaultCloudStore()` and `CloudKitGameArchiveStore` from creating a `CKContainer` during initial app launch.
- Kept online room functionality lazy through the lobby/session flow instead of constructing CloudKit-backed online state before the first screen.
- Bumped `CURRENT_PROJECT_VERSION` from `19` to `20`.

Verification:

- `swift test --filter LobbyViewModelTests/testOnlinePlayerNameIsRequiredBeforeCreateJoinOrDebugRoom`
- `xcodebuild build -project Preferans.xcodeproj -scheme Preferans -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- Cold launch on iPad simulator after uninstall/reinstall.
- `xcodebuild archive` for iOS Release.
- `xcodebuild -exportArchive` upload to App Store Connect succeeded.

## 1.0 (19) - App Store Connect

- Date: 2026-07-03
- Git tag: `appstore/1.0-build-19`
- Git commit: `32c0389 Prepare App Store build 19 privacy compliance`
- Repository author recorded by Git: `DmytroGusev <dmytro.gusev@gmail.com>`
- Operational change made by: Codex in the App Store privacy-compliance session
- Source base: build `1.0 (18)`, commit `e5d88e8`
- App Store upload: uploaded successfully, but later rejected by automated App Review launch-crash check

Changes:

- Added App Tracking Transparency permission flow in `Settings -> Privacy -> Request tracking permission`.
- Added `NSUserTrackingUsageDescription`.
- Added in-app account deletion flow in `Settings -> Account -> Delete account data`.
- Updated App Store review notes, privacy checklist, and privacy policy.
- Bumped `CURRENT_PROJECT_VERSION` from `18` to `19`.

## 1.0 (18) - TestFlight Baseline

- Date: 2026-06-13
- Git tag: `testflight/1.0-build-18`
- Git commit: `e5d88e8 Prepare TestFlight build 18`
- Repository author recorded by Git: `DmytroGusev <dmytro.gusev@gmail.com>`
- Notable prior contributor commits included before this baseline: `ontofractal <v@ontofractal.com>` commits through `3f4e593 Calculate pulka settings per player`

Notes:

- Build `1.0 (18)` is the baseline used for the build `19` privacy-compliance update.
- Build `1.0 (20)` is the current App Store candidate after fixing the launch crash.
