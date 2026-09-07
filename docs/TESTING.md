# Testing and validation

Preferans uses a layered test strategy. Keep fast, deterministic checks near
the engine and reserve simulator runs for behavior that genuinely needs iOS.

`bin/test-engine` selects a dependency-free SwiftPM graph containing the rules
engine, pure test support, and a portable Swift Testing suite. It runs 42
cases under Command Line Tools: 36 seeded three- and four-player generative
walks plus focused deterministic bot-planning and driver-diagnostic contracts.
The default `swift test` graph remains the complete graph: core XCTest plus
projection/coordinator/app integration suites, which require full Xcode on this
machine.

## Rules of engagement

- Prefer Swift Testing for portable engine coverage and XCTest/XCUIAutomation
  for app and UI automation. MCP screenshots and
  snapshots are debugging aids only; they are not the source of truth for
  pass/fail validation.
- Query UI through stable accessibility identifiers from `UIIdentifiers`.
  Avoid coordinate taps in tests and validation scripts.
- Wait on explicit state: `waitForExistence`, predicate/property waits, or
  structured test probes. Do not add sleeps to hide race conditions.
- Attach screenshots only on failure or for redesign/reference artifacts.
  Do not use repeated screenshots as the main verifier for functional flows.
- Run redesign/reference capture through `bin/screens`. It clears the prior
  file-based buckets, gathers both XCTest attachments and deduplicated
  `build/screens*` playthrough frames into one timestamped run, and makes that
  run discoverable through `bin/screens-latest`.
- Keep live-network validation small and bounded. The deployed worker smoke
  should prove 3-player and 4-player room creation, joining, and message
  delivery without playing a full match.

Apple's testing guidance points in the same direction: keep most coverage in
fast unit/integration tests, use XCUIAutomation for common UI flows, launch the
app with explicit `XCUIApplication.launchArguments`, wait on element state with
`XCUIElement.waitForExistence(timeout:)` or property predicates, and keep
screenshots/log files as attachments for diagnosis rather than as the primary
assertion mechanism.

References:

- https://developer.apple.com/documentation/xcode/testing
- https://developer.apple.com/documentation/xcuiautomation/xcuiapplication
- https://developer.apple.com/documentation/xcuiautomation/xcuielement/waitforexistence(timeout:)
- https://developer.apple.com/documentation/xctest/adding-attachments-to-tests-activities-and-issues

## Validation ladder

1. Portable seeded engine checks (no Xcode or simulator):
   - `bin/test-engine`
2. Full engine, projection, and coordinator unit tests (full Xcode):
   - `swift test --filter RoomOnlineGameCoordinatorTests`
   - `swift test --filter WireCompatibilityTests`
3. UI accessibility contract:
   - `xcodebuild test -project Preferans.xcodeproj -scheme Preferans -only-testing:PreferansUITests/AccessibilityContractTests/testLobbyAndGameExposeStableAutomationRoots`
4. Deployed worker smoke:
   - From `workers/room-worker`: `bun scripts/smoke-live.ts`
5. Multi-simulator invite flow:
   - Boot three or four iOS simulators.
   - Run `bin/verify-online-invite-flow HOST_SIM_UDID CLIENT_SIM_UDID CLIENT_SIM_UDID [CLIENT_SIM_UDID]`.

The invite-flow script builds once, installs the app on all provided
simulators, auto-creates a room on the host, auto-joins every remaining
simulator, and verifies the first deal by parsing structured `ONLINE_FLOW`
lines:

- server sends the manager `sequence=1 phase=bidding`
- every remote simulator receives `sequence=1 phase=bidding` for its own seat

Run it once with three UDIDs for the normal 3-player table and once with four
UDIDs for the 4-player rotation/sitting-out shape.

## Simulator tooling notes

`bin/screens` and `bin/test-ui` use one runner on the requested simulator.
Set `DEST_ID` to select an exact runtime when several devices share a name.
Individual tests have a 60-second default and a 90-second maximum allowance;
shrink or fix a slow scenario instead of increasing those limits. Screenshot
runs retain phase output and attachments. System-wide failure diagnostics are
off by default because their collection can outlast the test by minutes; set
`PREFERANS_TEST_DIAGNOSTICS=on-failure` for a specific infrastructure diagnosis.

Screenshot provenance hashes app sources/resources, shared engine sources,
UI fixtures, package resolution, and project/scheme settings. `--no-build`
rejects mismatched products. Each completed run records the source digest,
destination, selected tests, and result in `capture.json`. `bin/screens-latest`
compares that digest with the current source, including uncommitted changes;
new PNG modification times cannot make an old build pass the freshness check.

If `mcp__xcodebuildmcp__.snapshot_ui` returns an empty zero-size app tree but
XCUITest can still find `UIIdentifiers` elements, treat the MCP snapshot as
unavailable for that process. Continue through XCUITest, `.xcresult` bundles,
and structured app logs.

## Online-flow harness flags

These flags are for validation only:

- `-uiTestOnlineFlowLogging`: emits concise `ONLINE_FLOW` lines.
- `-uiTestAutoCreateOnlineRoom`: creates a deployed-worker invite room after
  the lobby appears.
- `-uiTestAutoJoinOnlineRoom <code>`: joins the room after the lobby appears.
- `-uiTestAutoStartOnlineDealOnJoin`: host starts the first deal after a real
  remote client hello/resync.
