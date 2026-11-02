# Privacy Checklist

Compare every answer with the exact submitted binary and backend behavior.

## Build 31

Build 31 removes the unused App Tracking Transparency request, advertising-ID
helper, tracking controls and NSUserTrackingUsageDescription. There is no ad,
analytics, attribution or third-party crash-reporting SDK in this release.
Do not declare tracking for hypothetical future integrations. Adding one later
requires a fresh data-flow review, updated disclosures and consent where required.

The app still collects online account and game data. Do not select Data Not
Collected. Local-only play is not an anonymous description of the online service.

## App Privacy Answers

Declare these types for App Functionality only, linked to the user's identity,
not used for cross-app tracking:

- Name: Apple fullName/display name, visible to room participants.
- User ID: guest/Apple account identity used for authentication and game access.
- Gameplay Content: persistent online game state and history.
- Product Interaction: gameplay actions and saved position in a game.
- Other Diagnostic Data: technical/security service logs and troubleshooting.

Remove unsupported Advertising Data, Email Address, Crash Data, Performance Data
and Other Usage Data declarations. Apple sign-in requests fullName, not email.
Voluntary support correspondence is separate; reassess Apple's optional-support
criteria if its collection or use changes.

No Third-Party Advertising, Developer Advertising/Marketing, Analytics,
Product Personalization or Other Purposes are implemented for these categories.
No device ID/IDFA, location, contacts, financial or health data is collected here.
Apple's own platform diagnostics are not an added developer crash-reporting SDK.

## Store Validation

On 2 November 2026 Apple refused to remove the last legacy tracking answer while
build 30, which includes NSUserTrackingUsageDescription, was selected. The UI
explicitly required a new binary or actual tracking disclosures. The correct
resolution is a non-tracking build, not falsely claiming advertising behavior.
Select processed build 31, complete the remaining answer, publish, reload and
verify every type plus the absence of Data Used to Track You.

`node AppStore/Release31/verify-privacy.mjs --ipa build/export31/Preferans.ipa`
checks source, signed IPA plist, linked frameworks and tracking API symbols.

## Account Deletion

Settings > Account > Delete online account is authenticated and permanent.
It removes the server account, sessions, game library and local credentials;
active games are abandoned and shared finished history retains anonymized seats.
Sign-out or uninstalling is not deletion. Test the full flow on physical devices
before review. The smoke test opens/cancels confirmation without deleting data.

## Public Notices

- <https://guruofcards.com/apps/preferans/privacy/>
- <https://guruofcards.com/apps/preferans/terms/>
- <https://guruofcards.com/apps/preferans/support/#account-deletion>
- support@guruofcards.com

Guru of Cards is the public brand; it does not change the Apple seller's legal
identity. Confirm any legally required controller/trader disclosures separately.

Reference: <https://developer.apple.com/app-store/app-privacy-details/>.
