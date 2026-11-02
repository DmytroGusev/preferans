# Guru of Cards migration and release preflight

2 November 2026. The initial scope was **pages and metadata only**. After Apple
blocked the final privacy answer for build 30, the owner explicitly expanded
scope to build/upload/select non-tracking build 31 and distribute it to the
existing external TestFlight group. No PR was merged, no Worker/container was
deployed and no public App Review was submitted. Current release receipts and
the remaining privacy blocker are in [Release31](../Release31/README.md).

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
  A later scoped policy clarification distinguishes build 31 from older ATT
  prompts: source `5f1ccb3ac6fc46f1bca33f1bb2a070b82ba9c890`, backup
  `/home/gurujtkn/.guru-cards-releases/preferans-pages-before.kMEGo1`.
  All 16 public HTML/CSS checks again returned 200 with exact hashes.
  Full build/check suite passed, including 1,685 HTML pages and scoped page tests.
  The existing dirty website checkout was not altered; integrate this source
  before any future whole-site publication so older untracked pages cannot return.
- Draft 1.0.3 already selected build 30 when this task began. That selection is
  initially preserved. Stale build-27 notes were replaced with build-30
  instructions, then authorized build-31 instructions after the privacy fix.
- Updated all 24 draft support and marketing links plus all 24 draft privacy
  links. Russian/Ukrainian locales use translated pages; other locales use English.
  Privacy Choices points to the direct account-deletion help section.
- Filled empty What's New for all 24 locales with actual build-30 changes.
  The build-31 follow-up appends a translated privacy-correction sentence.
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
- Draft: 1.0.3 (31), PREPARE_FOR_SUBMISSION, explicitly authorized selection.
- Build 31: VALID, Beta App Review APPROVED, external IN_BETA_TESTING for the
  six existing testers, unchanged membership/public-link settings.
- Build 30: VALID, Beta App Review APPROVED, external state IN_BETA_TESTING;
  existing external tester configuration unchanged during this task.
- Online bot feature: PR #9, source `9864885`, green Worker and portable-engine CI;
  tested locally/native, but not merged, deployed or present in build 30.
- Release/config PR #8 remains open/draft. A future rollout must retain its newer
  deployed engine digest; do not deploy the older main config by accident.
- Remote English screenshots exist: three each in APP_IPHONE_67, APP_IPHONE_61,
  APP_IPAD_PRO_3GEN_129. No screenshot was changed or claimed visually re-audited.
  The nine unrelated local screenshot deletions were preserved and not committed.

## Remaining Review Gate: Final Privacy Answer

The owner signed into the dedicated browser and authorized correction. Using
the official App Store Connect UI, the collected types were reduced to Name,
User ID, Gameplay Content, Product Interaction and Other Diagnostic Data. All
five now have App Functionality-only purposes and remain linked to identity.
Unsupported email, advertising, crash, performance and catch-all usage types
were removed. No guessed/private API or extracted browser credentials were used.

Four categories are saved as not used for tracking. Apple refuses to save the
last Other Diagnostic Data No answer, citing NSUserTrackingUsageDescription.
The owner authorized removing that unused capability in build 31; signed IPA
checks verify the key, tracking frameworks and ATT/IDFA APIs are absent.

The same validation error persists after build 31 is VALID/selected and in a
fresh signed-in editor. Its cause is not established; it may involve metadata
propagation or another binary, but neither is proven. The questionnaire is
**not fully corrected**, and the preview still shows Diagnostics under Data
Used to Track You. Do not submit public review until this is resolved.

`Release31/apple-support-draft.txt` is prepared for Apple to check the binary
used for validation. It has not been sent. The signed-in editor remains open
with the desired No answer pending; no fake tracking implementation was added.
Do not save the older native Chrome version form over the newer API metadata.

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
