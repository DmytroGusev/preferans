# Preferans 1.0.3 (33)

Approved non-tracking privacy follow-up to rejected public build 31. Build 32's
online bot controls, Guru of Cards links and owner-hosted protocol are retained.
No server/container/database deployment or payment activation is part of this
release. Public review is NOT automatically resubmitted by these tools.

## Source And Package

Exact archived app source: 82588b067a751444a76f02b0080a9ee10c1e545b.
Privacy fix: b00832c. Xcode 27.1 (27A9275), iOS 27.1 SDK.

The app now bundles PrivacyInfo.xcprivacy with NSPrivacyTracking false, empty
tracking domains, all five real linked/App Functionality disclosures and CA92.1
for app-private UserDefaults. There is no tracking-permission prompt, ATT/IDFA
access or new analytics/advertising SDK. This manifest does NOT automatically
update the App Store questionnaire or prove that its validation is fixed.

`package-verification.json`, `package-audit.json` and `source-manifest.json`
record source hashes, signed IPA checks, all bundled plist/manifest and Mach-O
inspection. The six package-guard tests passed, as did archive/export. Signing,
Apple sign-in, invites, owner URL/storage namespace and bot request symbols were
verified in the IPA. No physical-device gameplay claim is made for this privacy
only update; the original build 32 gameplay evidence remains in Release32.

## Store Operations

`release.mjs --capture` records a protected baseline, without private reviewer
contact fields. Default mode reads processing status. After VALID, `--select`
selects build 33 for editable 1.0.3 and updates reviewer notes with an explicit
pending privacy-label warning. It preserves localizations and other versions.
It does not submit public review or send a reply to Apple. `--external` enables
the existing external group and Beta App Review if required, preserving testers
and the public-link setting; this is separate from public App Review.

The pre-release Store state is REJECTED, selected build 31. The live version is
1.0.2 (28). App Privacy's last legacy tracking flag is Other Diagnostic Data; a
previous attempt to save No was refused with tracking-key validation. The audit
in PrivacyAudit20261102 distinguishes confirmed facts from the unproven theory
that the validator is inspecting live build 28.

Do not mark privacy resolved until a new UI publish succeeds and the product
preview shows no Data Used to Track You. If publishing is still refused, retain
the real diagnostic disclosure, keep public review unsubmitted and report the
blocker honestly. Do not add a fake tracking prompt, publish Data Not Collected,
expire old builds or remove real data categories to evade validation.

Existing builds/archives are retained for rollback. Do not overwrite build 33
with a second upload or amend the source tag. Any later application change needs
a new build number.

## Verified Delivery And Remaining Blocker

Uploaded successfully at 2026-11-02T17:38:33.517Z. Apple processed build 33 as
VALID, ID fb67887b-ddc1-4ad8-8030-25f4f826b7b6. It is selected for version 1.0.3,
which moved to PREPARE_FOR_SUBMISSION. Reviewer notes now describe 33, online bots
and the non-tracking manifest, and explicitly warn that App Privacy correction
is still pending. All 24 version localizations and other Store versions were
read back unchanged. No public review was resubmitted.

TestFlight: IN_BETA_TESTING, Beta App Review APPROVED, existing six external
testers, unchanged membership and public-link setting, auto-notification enabled.
See `testflight.json` and the protected before/after Store snapshots.

The fresh App Privacy publish attempt STILL failed with the same
NSUserTrackingUsageDescription validation. The new manifest did not resolve it.
The published label therefore still has Other Diagnostic Data used for tracking.
See `privacy-label-verification.json`. The editor is left with the accurate No
answer selected and the error visible; no false declaration or disclosure
removal was used as a workaround. The precise validation cause is unconfirmed.

A build-33-specific technical reply was explicitly approved and sent to the
existing App Review conversation at 17:45 UTC. The UI shows Messages (2) and the
posted developer reply. See `apple-review-reply-sent.txt` and
`review-communication.json`. No attachments or public resubmission were sent.
App Privacy is still unresolved pending investigation; repeating uploads or
resubmitting while the legacy tracking flag remains is not a resolution.
