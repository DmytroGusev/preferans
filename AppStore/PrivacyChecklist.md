# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current shipping assumption

The app supports local play and online rooms through Sign in with Apple and iCloud CloudKit. Update these answers if analytics, ads, crash reporting SDKs, push notifications, or another backend is added.

## Likely answers for the current codebase

- Contact Info: Not collected by the app
- Health & Fitness: Not collected
- Financial Info: Not collected
- Location: Not collected
- Sensitive Info: Not collected
- Contacts: Not collected
- User Content: Gameplay room data is processed for online multiplayer, but no public user-generated content feature is provided
- Browsing History: Not collected
- Search History: Not collected
- Identifiers: Sign in with Apple user identifier may be used for account identity and online room participation
- Purchases: Not collected
- Usage Data: Not collected unless analytics SDKs are added
- Diagnostics: Not collected unless crash/analytics SDKs are added

## Update before submission if you add any of these

- Analytics SDK
- Crash reporting SDK
- Authentication
- A backend beyond Apple iCloud CloudKit
- Push notifications
- Deep-link attribution

Do not submit privacy answers based on this file without comparing them to the actual shipping build.
