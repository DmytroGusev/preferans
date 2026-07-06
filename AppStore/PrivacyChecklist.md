# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current shipping assumption

The current shipping app supports local play and online rooms through Sign in with Apple, anonymous room identity, Cloudflare room sync, and optional Apple/iCloud capabilities. Build 21 requests App Tracking Transparency on first launch when iOS tracking status is not determined.

Only mark data as "used to track the user" in App Store Connect if the submitted build actually collects that category for tracking, advertising attribution, third-party analytics, or data broker sharing. Do not mark categories that are not collected by the app.

## Likely answers for the current codebase

- Tracking: Yes only if App Store Connect privacy labels intentionally declare tracking for advertising attribution or similar tracking use.
- Data used to track the user: Only the categories actually collected for tracking after ATT authorization.
- Contact Info: Email address is not requested or stored by the app.
- Health & Fitness: Not collected
- Financial Info: Not collected
- Location: Not collected
- Sensitive Info: Not collected
- Contacts: Not collected
- User Content: Gameplay room data is processed for online multiplayer, but no public user-generated content feature is provided.
- Browsing History: Not collected
- Search History: Not collected
- Identifiers: Sign in with Apple user identifier or anonymous room identifier may be collected, linked to the user, and used only for app functionality and online room participation.
- Name: Display name may be collected, linked to the user, and used only for app functionality so other room participants can identify seats.
- Purchases: Not collected
- Usage Data: Not collected
- Product Interaction: Not collected
- Diagnostics: Not collected
- Crash Data: Not collected
- Performance Data: Not collected
- Advertising Data: Not collected

## ATT implementation

Build 21 requests App Tracking Transparency automatically on first launch before future tracking data can be accessed. The permission status and manual request button are also available in **Settings → Privacy**.

Code may access the advertising identifier only through `TrackingPermissionCenter.advertisingIdentifierForTracking`, which returns a value only after `ATTrackingManager.trackingAuthorizationStatus == .authorized`.

## Account deletion

The app includes an in-app **Delete account data** action in **Settings → Account**. It clears locally stored Sign in with Apple identity, anonymous room account ID, and display name from the device. The current app does not maintain a separate server-side profile database.

## Update before submission if you add any of these

- Analytics SDK
- Crash reporting SDK
- Authentication
- A backend beyond Apple iCloud CloudKit
- Push notifications
- Deep-link attribution

Do not submit privacy answers based on this file without comparing them to the actual shipping build.
