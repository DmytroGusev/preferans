# Preferans 1.0.3 (34): TestFlight upload

Uploaded on 16 November 2026 from `96b9ccef080859126defac7810d3c638fd5eca49`.
Apple accepted the signed IPA under delivery
`1982a4a7-b568-43a6-aeb0-9da1a6d66258`.
App Store Connect processed it as `VALID` with that same build ID.
Internal status is `READY_FOR_BETA_TESTING`; external status is
`READY_FOR_BETA_SUBMISSION`, not submitted.

- Signed IPA SHA-256: `a29af2a2bcfa58f5b99e72e85849c1cf47d170ad3847a3e7bfd8937260a122eb`
- Xcode 27.1 (27A9275), SDK build 24A94232.
- 11 analytics unit tests, one consent UI test, and seven privacy-package
  tests passed. The signed IPA passed the product-analytics audit, including
  all 14 manifests and eight disabled collection defaults. The dedicated
  Preferans Firebase configuration and signing entitlements were verified.
- Build 34 adds opt-in Firebase usage analytics only. It contains no ad-serving
  SDK, ATT request or advertising-ID access. No Google Ads account is linked,
  no ad conversion was imported, and no campaign or spend was initiated.
- Upload only. No public App Review or external beta review was submitted.
  The live app, build 33's Distribution selection, App Privacy declarations,
  public privacy notice and TestFlight group membership were not changed.

Before public release, align App Privacy with the exact candidate and all its
bundled SDKs, and publish the analytics notice. For an installs-only Google Ads
setup without identifiable ad tracking, follow the
[attribution handoff](../Analytics/google-ads-install-attribution.md).
