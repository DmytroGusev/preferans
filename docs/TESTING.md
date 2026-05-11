# Testing and validation

Preferans uses a layered test strategy. Keep fast, deterministic checks near
the engine and reserve simulator runs for behavior that genuinely needs iOS.

## Rules of engagement

- Prefer XCTest/XCUIAutomation for app UI automation. MCP screenshots and
  snapshots are debugging aids only; they are not the source of truth for
  pass/fail validation.
- Query UI through stable accessibility identifiers from `UIIdentifiers`.
  Avoid coordinate taps in tests and validation scripts.
- Wait on explicit state: `waitForExistence`, predicate/property waits, or
  structured test probes. Do not add sleeps to hide race conditions.
- Attach screenshots only on failure or for redesign/reference artifacts.
  Do not use repeated screenshots as the main verifier for functional flows.
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

1. Engine and coordinator unit tests:
   - `swift test --filter RoomOnlineGameCoordinatorTests`
   - `swift test --filter WireCompatibilityTests`
2. UI accessibility contract:
   - `xcodebuild test -project Preferans.xcodeproj -scheme Preferans -only-testing:PreferansUITests/AccessibilityContractTests/testLobbyAndGameExposeStableAutomationRoots`
3. Deployed worker smoke:
   - From `workers/room-worker`: `bun scripts/smoke-live.ts`
4. Multi-simulator invite flow:
   - Boot three or four iOS simulators.
   - Run `bin/verify-online-invite-flow HOST_SIM_UDID CLIENT_SIM_UDID CLIENT_SIM_UDID [CLIENT_SIM_UDID]`.

The invite-flow script builds once, installs the app on all provided
simulators, auto-creates a room on the host, auto-joins every remaining
simulator, and verifies the first deal by parsing structured `ONLINE_FLOW`
lines:

- host publishes `sequence=1 phase=bidding`
- host sends `sequence=1 phase=bidding` to every remote seat
- every remote simulator receives `sequence=1 phase=bidding` for its own seat

Run it once with three UDIDs for the normal 3-player table and once with four
UDIDs for the 4-player rotation/sitting-out shape.

## Simulator tooling notes

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
