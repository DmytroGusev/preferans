# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current shipping assumption

The current shipping app supports local play and online rooms through Sign in with Apple, anonymous room identity, Cloudflare room sync, and optional Apple/iCloud capabilities. It does not include advertising, analytics, attribution, crash reporting, or data broker SDKs.

For the current build, configure App Store Connect App Privacy as **No Tracking**. Do not mark data as "used to track the user" unless a future build adds third-party advertising, attribution, analytics, or data broker sharing.

## Likely answers for the current codebase

- Tracking: No
- Data used to track the user: None
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

The current app does not track users, does not access IDFA during normal gameplay, and does not share collected data with advertisers or data brokers. ATT is therefore not required for the current App Store privacy configuration.

If a future build adds tracking, update this checklist, request App Tracking Transparency permission before collecting tracking data, and update App Store Connect privacy labels before submission.

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
