# Guru of Cards migration and release preflight

2 November 2026. The owner explicitly chose **pages and metadata only**.
No PR was merged, no room Worker/container was deployed, no new app was built or
uploaded, and neither App Store Review nor Beta App Review was submitted here.

## Completed

- Published EN/UK/RU application, support, privacy, terms and cookie pages under
  <https://guruofcards.com/apps/preferans/>. Public pages use Guru of Cards and
  support@guruofcards.com, not a personal owner name. The support mailbox directory
  exists; this is not an end-to-end mail-delivery guarantee.
- Scope: 15 HTML pages, CSS and scoped Apache config. Every public HTML/CSS byte
  matched the generated SHA-256; all 16 HTTP checks returned 200; .htaccess 403.
  Old content is backed up outside public_html. Other games/site paths untouched.
- Website source is in the existing masti-card-encyclopedia repository:
  [PR #1](https://github.com/DmytroGusev/masti-card-encyclopedia/pull/1).
  Exact deployed source: `e2502cdd98f5879b4e2457fb80d84ebaedf66c6a`.
  Backup: `/home/gurujtkn/.guru-cards-releases/preferans-pages-before.5GBrY7`.
  Full build/check suite passed, including 1,685 HTML pages and scoped page tests.
  The existing dirty website checkout was not altered; integrate this source
  before any future whole-site publication so older untracked pages cannot return.
- Draft 1.0.3 already selected build 30 when this task began. That selection is
  preserved. Replaced stale build-27 App Review notes with build-30 instructions.
- Updated all 24 draft support and marketing links plus all 24 draft privacy
  links. Russian/Ukrainian locales use translated pages; other locales use English.
  Privacy Choices points to the direct account-deletion help section.
- Filled empty What's New for all 24 locales with actual build-30 changes.
- Corrected draft age declarations: no advertising, no messaging/chat, no social
  media and no age-restricted social media. Apple required the last two previously
  unanswered fields with the update. Other age answers were preserved.
- Remote keywords, names, descriptions, promotional copy and private reviewer
  contact/demo fields were preserved. Local keyword sources were synchronized
  from the current draft to avoid reverting the owner's recent pref/tick edits.
- Added legacy GitHub-page redirect sources and canonical Guru links to local
  metadata. Those GitHub redirects do not become public until this source PR is
  integrated/published. Existing released Store metadata likewise stays on its
  prior URLs until the new version is released; no public version was submitted.

The app's Settings already points to the Guru privacy and terms pages in build
30, so changing those page contents/Store URLs needs no new binary. A later
build is required for new online bot-seat controls.

## Current Release State

- Public version: 1.0.2 (28), unchanged. It uses the earlier separate online service.
- Draft: 1.0.3 (30), PREPARE_FOR_SUBMISSION, unchanged build selection.
- Build 30: VALID, Beta App Review APPROVED, external state IN_BETA_TESTING;
  existing external tester configuration unchanged during this task.
- Online bot feature: PR #9, source `9864885`, green Worker and portable-engine CI;
  tested locally/native, but not merged, deployed or present in build 30.
- Release/config PR #8 remains open/draft. A future rollout must retain its newer
  deployed engine digest; do not deploy the older main config by accident.
- Remote English screenshots exist: three each in APP_IPHONE_67, APP_IPHONE_61,
  APP_IPAD_PRO_3GEN_129. No screenshot was changed or claimed visually re-audited.
  The nine unrelated local screenshot deletions were preserved and not committed.

## Remaining Review Gate: App Privacy Questionnaire

The public Apple product page was read on 2 November 2026 and still says
**Data Used to Track You**, with advertising/marketing/analytics purposes for
Contact Info, Identifiers, Usage Data and Diagnostics. This is separate from
the privacy-policy URL and separate from the age-rating advertising checkbox.
It was **not changed** by the API scripts. Do not submit while declarations and
actual processing disagree.

The owner subsequently approved correcting the questionnaire. It cannot be
edited with the supported metadata endpoints used here. The Orca CLI was missing
(`zsh:1: command not found: orca`), but the separate browser connector is available.
Native Chrome was signed in yet contained a stale unsaved version form, which was
left untouched to avoid overwriting the API updates. Its UI control could not be
used reliably. A dedicated in-app browser tab is open at the App Store Connect
sign-in page, awaiting the owner's login. No privacy-label mutation has yet been
performed. No guessed/private API or extracted browser credentials were used.

In App Store Connect -> Preferans -> App Privacy, review these exact points:

1. Current build 30 has no ads/analytics/attribution SDK, and no use of the unused
   IDFA helper was found. No third-party-data advertising linkage/data-broker
   sharing is implemented. Do not mark data as used for tracking just because ATT
   permission can be requested or because a future release might add analytics.
2. Do **not** switch to Data Not Collected: persistent online accounts/game history
   do collect data off device. Declare display/name information, account User ID
   and Gameplay Content for App Functionality, linked to the online account.
3. Remove advertising, developer-marketing and analytics purposes only where they
   do not actually occur. Review Product Interaction/diagnostic types against
   retained service logs instead of checking every category speculatively.
4. Apple sign-in in this build requests fullName, not the email scope. Support
   email correspondence is a distinct processing path. Assess its disclosure
   against Apple's optional-support disclosure criteria; do not invent account
   email collection or omit mandatory categories without reviewing the facts.
5. Publish the corrected questionnaire and verify its preview/public label. Apple
   permits updating privacy answers without a new binary; the URL change alone
   cannot correct them. Keep any actually collected categories disclosed.

Reference: [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).

## Other Final Checks

Test Apple sign-in, invite links/codes, deletion and resume on two physical
devices using the same compatible build. Local/native automated tests do not
guarantee every physical-device condition. No recovery-backup/restore audit or
production capacity certification was performed in this metadata task.

Guru of Cards is the public brand, not a newly registered legal entity. The
Apple account holder/seller and private review contact have not been renamed.
The owner must confirm legally required trader/controller identity and contact
disclosures for the intended territories. These policies are source-based
product disclosures, not a legal opinion or a guarantee of review approval.

## Evidence And Reuse

`before.json` / `after.json` and `verification.json` cover link/review-note changes.
`preflight-before.json` / `preflight-after.json` and `preflight-verification.json`
cover missing release text and age answers. Snapshots exclude private reviewer
contact and demo credentials. Website deployment evidence lives in its own repo.

Use ASC_KEY_PATH pointing to the existing private key outside version control.
The scripts are pinned to this draft and selected build; inspect snapshots before
reuse. They do not select a build or submit a review. Do not bulk-apply historical
App Store templates over live user-edited keywords/descriptions.
