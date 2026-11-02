# Verification: online waiting-room bots

Follow-up: the owner subsequently authorized the Worker/build-32 rollout.
See AppStore/Release32 for live deployment and native/live-network receipts.
The original source-only verification below is retained as historical evidence.

2026-11-02. Base main: `c4621082a8a36c3cffdbf58d1f7a01faff64cefa`.
No Cloudflare deployment, TestFlight upload, build-number change or Store
metadata/review mutation was performed for this feature.

## Results

- Worker typecheck: passed.
- Worker Node unit suite: 59 passed, zero failed.
- Real local workerd suite: 19 passed, zero failed.
- Portable engine lane: 10 tests / 4 suites passed, including 36 seeded walks.
- Full Swift suite: passed, zero test failures; app target executed 272 XCTest
  cases with 3 opt-in live-backend skips; server/engine XCTest and 34 Swift Testing
  cases also passed.
- Final client rerun after the Ready/edit guard: 20 focused coordinator/transport
  tests passed, including explicit-null removal and failed-edit UI recovery.
- Native iPhone 17 Pro / iOS 27.0 QA simulator: one new end-to-end test passed in
  45.132 seconds, below the existing 60-second test limit. It registered a native
  host, created a public table, joined a real second QA account/socket, added a
  Casual bot, changed it to Expert, removed it, re-added Seasoned, confirmed
  both humans Ready, started the game and checked ten private host cards.
- The first native attempt failed because the new test omitted the JSON body of
  its peer join request (HTTP 400). The fixture was corrected to send its seat
  request; no product workaround, timeout extension or arbitrary sleep was added.
- Portable SwiftPM deletes Package.resolved in its narrow lane; that test-owned
  deletion was restored before the provenance-checked native build. Dependency
  versions were not changed.

Tests used loopback Worker port 8787 and Swift engine port 18081, never the
owner's or friend's production backend. Disposable native/API accounts were
deleted during test cleanup. Generated simulator products/logs remain ignored.

## Commands

Run `npm run typecheck`, `npm test`, `npm run test:runtime` in
`workers/room-worker`. Run `bin/test-engine` and `swift test` from the repo root.
The native case requires the loopback services described in the Worker README:

```sh
bin/test-ui -only-testing:PreferansUITests/NativeOnlineUITests/testNativeHostConfiguresBotBesideFriendAndStartsPublicTable
```

The local verification used Xcode 27.1 and a dedicated QA simulator. It does not
replace physical-device testing after the subsequent authorized server/client
rollout. Four-seat partial filling and human-seat protection have automated
Worker coverage; the native flow exercised three seats.

## Rollout Boundary

Deploy the updated Worker to the owner's account using the currently deployed
owner config and image pin. Do not copy the older main image digest over the
newer release-30 pin: first integrate the release PR/config. No new engine build
is required solely for bot difficulty; all three profiles are already supported
by the current Swift service. Keep the same Durable Object namespaces/data.

Then upload a later-numbered client build and test with two physical devices.
Build 30 does not contain these controls. The feature branch changes no deploy
configuration, so merging it cannot itself deploy or roll back anything.
