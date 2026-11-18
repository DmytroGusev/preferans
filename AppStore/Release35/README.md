# Preferans 1.0.3 (35): Online game diagnostics

## TestFlight Delivery

Uploaded and processed on 18 November 2026. The feature revision is
`3d24335`. The [TestFlight build](https://appstoreconnect.apple.com/apps/6763581975/testflight/ios/8b813494-d3fc-4a8f-bfd9-135a4d87184b/metadata)
is `VALID`, with English What to Test verified after saving. Internal status:
`READY_FOR_BETA_TESTING`; external status: `READY_FOR_BETA_SUBMISSION`. No group
was assigned, and neither Beta App Review nor public App Review was submitted.

- Xcode 27.1 (27A9275); 22 Swift tests and seven package guard tests passed.
- Signed IPA SHA-256: `12d917f12060c3d12386d00eed92ba0fdc6fe6fc49b86fb33712f1cfc086993d`.
  Signature, all 14 manifests, and the no-tracking check passed.
- No Distribution, App Privacy, public privacy policy, or Worker changes.
  Receipt of build 35's new events from a physical device is not yet verified.

## What to test

See the [TestFlight notes](what-to-test.txt) for the tester-facing summary.

1. With analytics off, create/join a table and try reconnecting; the game
   should work the same way and no optional diagnostic events should be sent.
2. Enable Share usage analytics. Create a table, briefly disconnect while
   waiting or playing, then restore connectivity and confirm the seat recovers.
3. Try an actual rejected join, for example joining an expired table by code.
   Verify the existing error is still shown. For a controlled first-deal test,
   suppress the receipt on a test server and look for one missing-confirmation
   event, even though gameplay still retries.

In the dedicated Preferans Firebase/GA4 property (561600345), filter
`online_diagnostic` by `app_build=b35`. Break down event counts by operation,
stage, and diagnostic code; keep QA separate. There is no new Worker deployment.
The three event-scoped dimensions were registered and verified in the
Preferans property on 18 November 2026.

## Privacy Notice Supplement

> For version 1.0.3 build 35 and later, optional Firebase usage analytics also
> includes technical reports when creating or joining a table, restoring a
> connection, changing readiness, or starting the first deal. The report is
> limited to an operation, a stage, a predefined code for a failure or recovery,
> and the app build number. Firebase also processes the app-instance identifier
> and other standard analytics data described in the existing policy. We do not
> include account information, table codes, invitations, cards, or raw error
> messages. These reports are off unless you enable Share usage analytics. You
> can turn them off at any time in Settings. They are not used for advertising
> or cross-company tracking.

App Privacy: retain `Other Diagnostic Data`, mark `App Functionality` for
operational troubleshooting and `Analytics` for these optional reports, and
answer `No tracking`. Keep the rest of the build 34 Firebase disclosures.
No ATT prompt or advertising service was added. A new build does not, on its
own, correct the legacy App Store Connect tracking declaration. Before a public
submission, publish the policy supplement and verify the actual public label.
