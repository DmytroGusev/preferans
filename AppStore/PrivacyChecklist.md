# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current prototype assumption

If the shipped build remains local-only or uses only basic share sheets without account creation, the privacy footprint is minimal.

## Likely answers for the current codebase

- Contact Info: Not collected by the app
- Health & Fitness: Not collected
- Financial Info: Not collected
- Location: Not collected
- Sensitive Info: Not collected
- Contacts: Not collected
- User Content: Not collected by the current prototype
- Browsing History: Not collected
- Search History: Not collected
- Identifiers: Not intentionally collected by the current prototype
- Purchases: Not collected
- Usage Data: Not collected unless analytics SDKs are added
- Diagnostics: Not collected unless crash/analytics SDKs are added

## Update before submission if you add any of these

- Analytics SDK
- Crash reporting SDK
- Authentication
- Real online multiplayer backend
- Push notifications
- Deep-link attribution

Do not submit privacy answers based on this file without comparing them to the actual shipping build.
