# App Review Audit - July 6, 2026

## Current App Review Status

- App: Preferans card game
- Bundle ID: `com.mixandmatch.preferans`
- App Store Connect app ID: `6763581975`
- Version: `1.0`
- Build reviewed: `20`
- App Store state from API: `REJECTED`
- Latest GitHub commit checked: `87b7941 Refresh iPhone App Store screenshots`

## Apple Rejection

Apple rejected build 20 under Guideline 5.1.2(i), Legal - Privacy - Data Use and Sharing.

Apple says the App Store Connect privacy answers currently indicate that the app collects data to track users, including Product Interaction, Other Diagnostic Data, Performance Data, Advertising Data, Name, Crash Data, Other Usage Data, User ID, and Email Address. Apple did not see an App Tracking Transparency permission request before that tracking.

## Code Audit Finding

The current repository does not include advertising, analytics, attribution, crash reporting, or data broker SDKs.

No Firebase, Google Analytics, Facebook, AppsFlyer, Amplitude, Mixpanel, or similar tracking SDK was found.

Online room data is used for app functionality: player identity, display names, room codes, room participation, game state, bids, turns, cards, and scores.

The app privacy policy already states that Preferans does not sell personal information and does not use information for third-party advertising.

## Required App Store Connect Fix

For the current build, App Store Connect App Privacy should be configured as:

- Tracking: No
- Data used to track the user: None
- Email Address: Not collected
- Advertising Data: Not collected
- Product Interaction: Not collected
- Other Usage Data: Not collected
- Crash Data: Not collected
- Performance Data: Not collected
- Other Diagnostic Data: Not collected
- User ID: Collected only if needed for online room identity; used for App Functionality, not Tracking
- Name: Collected only as display name for online rooms; used for App Functionality, not Tracking

This App Privacy questionnaire usually must be edited manually in App Store Connect by an Account Holder or Admin. It is not reliably exposed through Fastlane or the public App Store Connect API.

## Account Deletion

The app includes account deletion in Settings:

- Open Settings from the app.
- Go to Account.
- Tap Delete account data.
- Confirm deletion.

The flow clears the locally stored Sign in with Apple identity, anonymous room account ID, and display name. The current app does not maintain a separate server-side profile database.

## Screenshots

The repository includes current iPhone 6.5-inch screenshots and iPad 13-inch screenshots under `AppStore/Screenshots`.

If App Store Connect blocks screenshot replacement because the version was already submitted, reject/cancel the editable submission or create a new editable version/build before uploading screenshots again.

## Suggested App Review Reply

Hello App Review,

Thank you for the review. We reviewed the app and confirmed that the current iOS build does not track users across apps or websites, does not use IDFA for advertising, and does not include advertising, analytics, attribution, crash reporting, or data broker SDKs.

The App Privacy answers in App Store Connect were too broad and incorrectly marked data as used for tracking. We updated App Privacy to show that the app does not track users. Online room identity and display name are used only for app functionality so invited players can join and identify seats in the same game room.

Account deletion is available in the app from Settings -> Account -> Delete account data.

Please review the updated submission.

