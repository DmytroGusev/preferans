# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current shipping assumption

The app supports local play and online rooms through Sign in with Apple, an in-app email/Gmail test profile, and iCloud CloudKit. Update these answers if analytics, ads, crash reporting SDKs, push notifications, Google OAuth, or another backend is added.

## Likely answers for the current codebase

- Contact Info: Email address may be collected if the player enters it for the email/Gmail test profile or Apple provides it during Sign in with Apple
- Health & Fitness: Not collected
- Financial Info: Not collected
- Location: Not collected
- Sensitive Info: Not collected
- Contacts: Not collected
- User Content: Gameplay room data is processed for online multiplayer, but no public user-generated content feature is provided
- Browsing History: Not collected
- Search History: Not collected
- Identifiers: Sign in with Apple user identifier or email-derived player identifier may be used for account identity and online room participation
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
