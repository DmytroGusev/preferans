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

On 2 November 2026 Apple refused to remove the final legacy tracking answer,
Other Diagnostic Data, even after processed build 31 was selected. The public
submission of 1.0.3 (31) was then rejected for that declaration. A fresh attempt
after rejection still failed with NSUserTrackingUsageDescription validation.
Uploading/selecting a clean binary alone has NOT resolved the privacy label.

The deeper audit confirms signed packages 31/32 contain no tracking permission
key (including localized resources), ATT/IDFA APIs, tracking frameworks or nested
SDK bundles. Their SHA-256 values match the original package receipts. Old build
30 correctly fails the same scanner as a negative control. The upload pipeline
log references the build 31 archive, not an older archive; Apple's processed
metadata matches its version, SDK and bundle ID.

Important: App Privacy is app-level, not a separate label for each TestFlight
build. The live Store version remains 1.0.2 (28). Its committed Release/Debug
configuration contains the tracking key; the signed build 28 package was not
available for this audit. Apple's documentation says answers for an already-live
app should reflect the live version. This is a concrete transition issue to
consider, not proof of which binary Apple's validator actually inspects. Do not
call the validator faulty without establishing that root cause. Do not expire
old builds, publish Data Not Collected, remove actual diagnostics or add unused
ATT merely to bypass validation.

See `PrivacyAudit20261102/audit-results.json`. Do not submit 31 unchanged or claim
that 32 fixes the label. A fresh publish attempt must visibly succeed and the
product-page preview must lose Data Used to Track You before marking this done.
Any reply/resubmission/build-selection change needs a separate owner decision.

Reference: <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>.

## Privacy Manifest And Package Guard

The re-audit also found a separate omission in 31/32: no app privacy manifest,
despite app-private UserDefaults use. The next source revision now bundles
`Preferans/PrivacyInfo.xcprivacy`: NSPrivacyTracking false, empty tracking domains,
all five real functionality/linked-data disclosures and CA92.1 for local defaults.
This fixes that omission; it is not a proven fix for the Store's tracking-key
validation. A manifest does not automatically publish questionnaire answers.

Verified with a local, unsigned Xcode 27.1 Release build. The manifest is present
in its main app bundle and passes the guard. This local build retains number 32
only for verification; it has NOT replaced the already-uploaded build 32. Use a
new, unused build number for any future signed upload.

Before future upload run:

```sh
node --test bin/audit-privacy-package.test.mjs
node bin/audit-privacy-package.mjs /absolute/path/to/Preferans.ipa --require-manifest
```

The guard parses every plist/strings/manifest, scans Mach-O symbols/linkage and
verifies the signature. Run it with the Mac's normal trust-store access; do not
disable certificate checks to make verification pass. Source-only manifest tests
are not a substitute for inspecting the final signed IPA.

Reference: <https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype>.

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
