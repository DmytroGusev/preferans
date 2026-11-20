# Privacy Checklist

Use this file when filling in App Store Connect privacy answers.

## Current main source

The current shipping app supports local play and authenticated online rooms
through Sign in with Apple, guest accounts, and Cloudflare room sync. This
source does not request App Tracking Transparency or access IDFA.

Match the App Store Connect answers to the exact submitted binary and its
backend. In particular, other release branches can include optional usage
analytics that isn't present here. Functional diagnostics or usage analytics
are not tracking merely because they are collected.

## Likely answers for the current codebase

- Tracking: No for this source.
- Data used to track the user: None for this source.
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
- Other Diagnostic Data: Online service logs used for troubleshooting and operation; not used for tracking.
- Crash Data: Not collected
- Performance Data: Not collected
- Advertising Data: Not collected

## Package verification

Check the exported app and any nested bundles for tracking purpose strings and
ATT or AdSupport linkage before uploading. A source cleanup does not modify
an already-uploaded binary or the published App Privacy answers.

## Account deletion

The app includes an authenticated **Delete online account** action in
**Settings → Account**. It deletes the Cloudflare account record, active bearer
sessions, game library, room identity, and room credentials before clearing the
local Keychain session and profile. Active games containing the account are
abandoned and lose their resume snapshot; shared finished history retains only
an anonymized seat and score.

## Update before submission if you add any of these

- Analytics SDK
- Crash reporting SDK
- A new authentication provider
- Another backend beyond the current Cloudflare room service
- Push notifications
- Deep-link attribution

Do not submit privacy answers based on this file without comparing them to the actual shipping build.
