# Preferans product analytics (build 34 candidate)

This integration adds optional Firebase/GA4 usage measurement, not advertising
tracking. It does not deploy the room server, enable payments, upload a build or
change the selected App Store release. Builds 31-33 did not include this SDK.

## Destinations

- Firebase: `guru-preferans-20261030`
- iOS app: `1:333127048917:ios:07fabd60aff528315f4c5c`
- Bundle: `com.mixandmatch.preferans`
- GA4 property: `561600345`, account: `286586617`
- [Google Analytics](https://analytics.google.com/analytics/web/#/a286586617p561600345/)
- [Firebase](https://console.firebase.google.com/project/guru-preferans-20261030/analytics)

## Building

Firebase Apple SDK is pinned to 13.1.1 in Xcode. The app links FirebaseCore and
FirebaseAnalyticsCore (without IDFA support), not FirebaseAnalytics with identity
support, AdSupport, ATT, Crashlytics or Performance Monitoring. Use Xcode 27.1 or
a compatible toolchain; the SDK requires Swift 6.2.3 or later.

The real `Preferans/Resources/GoogleService-Info.plist` is intentionally ignored.
An already-authorized Google Cloud CLI account with access to this Firebase
project can fetch and validate it:

```sh
node AppStore/Analytics/fetch-config.mjs
```

Do not commit service-account keys, OAuth tokens or signing credentials. The
example plist is not a working configuration. On CI, restore the actual plist
from a protected CI secret before Xcode builds. Configuration failure is visible
in Settings and does not prevent playing. The helper does not expand OAuth
scopes, enable APIs or change Google account permissions. GA4 Admin API calls
were not available with the current CLI scopes; reporting definitions were
configured through the signed-in property UI instead.

## Consent and data boundaries

Collection defaults to OFF. Firebase is not configured until explicit opt-in.
After onboarding (and on upgrades with no recorded choice), a dismiss-disabled
choice sheet offers equally available Allow and Continue without analytics.
Neither online nor offline play requires consent. Settings > Usage analytics
allows withdrawal; it disables collection and resets the local app-instance ID
and deduplication receipts. Withdrawal does not retroactively erase previously
processed aggregates from Google. Successful online-account deletion also
withdraws this device's analytics consent.

Every app collection/advertising default in Info.plist is false. When enabled,
only analytics storage is granted; ad storage, ad user data and advertising
personalization remain denied. IDFV collection and automatic screen reporting
are disabled. No Firebase user ID is assigned. Google Signals was verified OFF
on 3 November 2026. Do not enable Signals, Ads links, advertising audiences,
user-provided data or enhanced conversions without a fresh privacy review.
The property had no completed or pending Google Ads links. Retention was read,
not changed: event data two months, user data fourteen months, reset after new
activity enabled. Standard aggregated reports have separate retention behavior.
Region-level advertising personalization remained at its existing setting;
the app denies it for every event. Disabling it property-wide was requested
separately as an additional safeguard, not silently applied.

Google receives an SDK-generated app-instance identifier, event timestamps,
app/device/OS information and approximate geography derived from the network
address, plus the bounded event fields below. These are pseudonymous data, not
anonymous data. No Location Services permission or precise location is used.
The typed event API accepts no names, emails, account IDs, room codes, invite
URLs, card contents, scores, free text or raw error messages. The existing room
service still processes its separately disclosed account/game/technical data.

Ordinary unit/UI automation never initializes Firebase. Explicit live QA uses
`-analyticsLiveVerification -FIRDebugEnabled` in Debug only; all Debug events
carry `app_environment=qa`, Release events `production`. Exclude QA in reports.
Never use synthetic Measurement Protocol traffic as evidence of app integration.

## Events and reporting

| Event | When | Fields |
| --- | --- | --- |
| `analytics_opt_in` | A choice changes to allowed | none |
| `onboarding_complete` | Tour finishes with consent, or consent immediately follows it | none |
| `screen_view` | An instrumented screen appears | fixed `screen_name`, `screen_class` |
| `local_game_start` | A local table containing a human is created | game context |
| `online_room_flow` | Valid create/join/resume operation starts or resolves | `operation`, `outcome` |
| `bot_seat_change` | Host adds/changes/removes a bot | `operation`, `outcome`, `difficulty` |
| `ready_change` | Ready/unready request starts or resolves | `operation`, `outcome` |
| `online_connection` | Observed connection state changes | `connection_state` |
| `match_start` | The first authoritative deal starts | game context |
| `deal_complete` | Engine scores a deal | game context, `deal_kind` |
| `match_complete` | Engine finishes the pool | game context, `deals_played` |

Game context: `game_mode` (local/online), `player_count` (3/4), `bot_count`
(0..player count), `convention` (vienna/prague/berlin/custom). Operations and
outcomes are fixed enums. Failed form validation before a network request is
not a room-operation failure. Watch-all-bots demos are not local game starts.
SDK lifecycle/session/engagement events are also collected after consent.

Local table/revision identifiers are hashed solely for bounded, on-device
deduplication and never sent to Google. Duplicate game frames after reconnect
are suppressed across app launches (512 recent receipts). Disabling analytics
clears receipts. This is best-effort client telemetry, not accounting.

**Counts are per consenting participant device.** Three players can produce
three match-completion events for the same table. A player joining/reconnecting
late does not backfill an unseen start or history. Do not use these metrics to
bill subscriptions or enforce free-game quotas. Consent selection and dropped
network traffic bias funnel denominators; do not infer all-player counts.

On 3 November 2026 the property UI was used to create ten event-scoped custom
dimensions: Game mode, Player count, Bot count, Convention, Operation, Outcome,
Bot difficulty, Deal kind, Connection state and App environment, matching the
parameters above. The standard-unit custom metric Deals per completed match
maps to `deals_played` and explicitly measures per-device completions.

Useful views after actual data arrives:

- Usage: active users, sessions, engagement and retention in standard reports.
- Room funnel: `online_room_flow`, broken down by operation/outcome; compare
  succeeded/requested for each operation, not mixed operations.
- Play: `match_start` and `match_complete` by game mode/convention/player count.
- Bots: `bot_seat_change` outcome and difficulty; completed matches by bot count.
- Reliability: `online_connection` state changes (not crash/performance data).

DebugView shows explicitly enabled debug devices. Normal reports can take
24-48 hours to populate; new definitions do not reconstruct historical custom
dimensions. GA4/Firebase has no events from older SDK-free installed builds.

## Verification on 3 November 2026

- Ten AppAnalytics unit tests passed (consent, withdrawal, bounded fields,
  automation isolation and reconnect/completion deduplication).
- Seven package-guard tests passed.
- Simulator consent/Settings test passed; enabling and disabling consent works.
- Explicit live Firebase opt-in/local-game test passed on iOS 27.0.
- GA4 DebugView received `analytics_opt_in`, `screen_view`, `local_game_start`,
  `match_start`, `session_start`, `first_open` and `user_engagement` from this app.
- Received match fields were inspected: `app_environment=qa`, `game_mode=local`,
  `player_count=3`, `bot_count=2`, `convention=vienna`.
- Xcode 27.1 Debug/device, Debug/simulator and Release/device builds succeeded.
- The unsigned Release app passed the product-analytics package audit: 14
  manifests with no tracking, seven app data categories, no ATT/IDFA APIs or
  advertising-framework links, and all eight collection defaults false.

This is not a signed/archive/upload verification or a physical-device check.
Online room/bot/completion instrumentation is covered in source and core tests;
it has not yet been exercised with two consenting physical devices in GA4.
No build 34 upload, public policy publication, privacy-label update or server
deployment was performed as part of this verification.

To repeat the explicit live test, pass the opt-in flag to the test runner, not
only xcodebuild's parent process (replace the simulator UUID):

```sh
TEST_RUNNER_PREFERANS_VERIFY_FIREBASE_LIVE=1 xcodebuild \
  -project Preferans.xcodeproj -scheme Preferans -configuration Debug \
  -destination 'id=SIMULATOR_UUID' -parallel-testing-enabled NO \
  -only-testing:PreferansUITests/AnalyticsConsentUITests/testLiveFirebaseOptInAndLocalGame test
```

Without the explicit environment flag the live test skips; a skipped run is not
delivery evidence. Keep ordinary CI runs network-disabled for analytics.

## Release gate

Before shipping 34, publish the reviewed candidate privacy-policy addition,
update App Privacy for this binary (see PrivacyChecklist.md), archive/sign and
audit the final IPA with the explicit product-analytics profile:

```sh
node --test bin/audit-privacy-package.test.mjs
node bin/audit-privacy-package.mjs /absolute/path/to/Preferans.ipa --require-manifest --product-analytics
```

The normal guard remains strict for SDK-free releases. Keep historical build 33
receipts unchanged. An SDK integration does not resolve the previously reported
App Store privacy-label validation conflict by itself. Do not add an unused ATT
prompt or misdeclare tracking to bypass it.

References: [collection controls](https://firebase.google.com/docs/analytics/ios/configure-data-collection),
[GA4 App Store disclosures](https://support.google.com/analytics/answer/10285841),
[Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/).
