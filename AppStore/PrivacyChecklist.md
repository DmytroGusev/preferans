# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current shipping assumption

The app supports local play and online rooms through Sign in with Apple, anonymous room identity, Cloudflare room sync, and optional Apple/iCloud capabilities. The app includes an App Tracking Transparency permission flow in Settings so tracking can be enabled only after the user grants iOS permission.

## Likely answers for the current codebase

- Tracking: Yes, only if you intentionally configure App Store Connect privacy labels for tracking and only after the user grants App Tracking Transparency permission.
- Data used to track the user: Only collect tracking data after ATT authorization. Do not collect IDFA or cross-app/cross-website tracking data before permission.
- Contact Info: Email address is not requested by the app. If Apple provides relay email information in the future, update this answer before submission.
- Health & Fitness: Not collected
- Financial Info: Not collected
- Location: Not collected
- Sensitive Info: Not collected
- Contacts: Not collected
- User Content: Gameplay room data is processed for online multiplayer, but no public user-generated content feature is provided
- Browsing History: Not collected
- Search History: Not collected
- Identifiers: Sign in with Apple user identifier or anonymous room identifier may be used for account identity and online room participation
- Purchases: Not collected
- Usage Data: Not collected unless analytics SDKs are added
- Diagnostics: Not collected unless crash/analytics SDKs are added

## ATT implementation

The tracking permission request is available in the app at **Settings → Privacy → Request tracking permission**.

The generated Info.plist includes `NSUserTrackingUsageDescription`.

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
