# Preferans 1.0.3 (35): Online game diagnostics

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
