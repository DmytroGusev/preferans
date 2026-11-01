# Quickstart: Preferans iOS App

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Spec**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

All commands run from the repository root (`preferans/`). Test lanes, CI, fastlane and App Store tooling are described in depth in [`../006-testing-and-release`](../006-testing-and-release/); this page covers the app.

## Prerequisites

- macOS with **full Xcode** selected (`xcode-select -p` must not point at CommandLineTools). Command Line Tools alone cannot build the SwiftUI app, compile the string catalog, or run the Simulator (`bin/lib/xcode-sim.sh` `preferans_require_xcode`).
- Swift 6 toolchain; iOS 17+ simulator runtime (the Xcode targets deploy to iOS 17.0).
- The scripts default to simulators named **iPhone 17** (`bin/sim`) and **iPhone 17 Pro** (`bin/test-ui`, `bin/screens`); override with `DEST_NAME='<name>'` (or `DEST_ID='<udid>'` for `bin/test-ui`/`bin/screens`; `bin/sim` resolves the UDID from `DEST_NAME` only).
- Online development additionally needs Docker and Bun (`bin/dev-online`).

## Open in Xcode

```sh
open Preferans.xcodeproj
```

- Scheme: **Preferans** (app + `PreferansUITests`). Targets: `Preferans` (bundle id `com.mixandmatch.preferans`, version 1.0.3, build 29) and `PreferansUITests` (`com.mixandmatch.preferans.uitests`).
- Swift packages resolve from the local package reference (`Package.swift` at the root): products `PreferansEngine` and `Dependencies`.
- Signing uses the team configured in the project (automatic signing); change it under *Signing & Capabilities* for your own account. Capabilities: Game Center, Sign in with Apple, Associated Domains.
- Run (⌘R) on any iOS 17+ simulator or device. Mac Catalyst is enabled (`SUPPORTS_MACCATALYST = YES`).

## Run on the simulator from the command line

`bin/sim` builds the app into `build/DerivedData`, boots the simulator, installs and launches it with harness flags.

```sh
bin/sim                                            # lobby, random deals
bin/sim game1                                      # scripted match (game1 | game2 | game3)
bin/sim --scenario northBidsSpadesSix --dealer south
bin/sim --seed 42                                  # deterministic random deals
bin/sim game2 -- -uiTestPoolTarget 30              # anything after -- is passed as launch arguments
bin/sim --no-rotate-viewer game1                   # do not pass -uiTestViewerFollowsActor
bin/sim --animations game1                         # keep animations (default passes -uiTestDisableAnimations)
bin/sim --skip-build game1                         # reinstall the last build
DEST_NAME='iPad Pro 13-inch (M4)' bin/sim          # another simulator
```

Notes:

- By default `bin/sim` passes `-uiTestViewerFollowsActor` and `-uiTestDisableAnimations`. Any `-uiTest…` argument counts as UI automation, which **skips onboarding and the ATT prompt** and makes the viewer follow the acting seat. To see first-run behaviour exactly as shipped, use `bin/sim --no-rotate-viewer --animations` (no harness flags) on a fresh simulator, or erase the app's data.
- `-uiTestFastBotDelay` is never passed by `bin/sim`, so the lobby's Bot speed picker applies.

Equivalent raw commands (what `bin/sim` does):

```sh
xcodebuild build -project Preferans.xcodeproj -scheme Preferans -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath build/DerivedData
xcrun simctl boot "<UDID>" || true
xcrun simctl install "<UDID>" build/DerivedData/Build/Products/Debug-iphonesimulator/Preferans.app
xcrun simctl launch "<UDID>" com.mixandmatch.preferans -uiTestViewerFollowsActor -uiTestDisableAnimations -uiTestMatchScript game1
```

## Run the app unit tests (SwiftPM, macOS host)

The SwiftUI app code is compiled by the SwiftPM library target `PreferansApp` and tested by `PreferansAppTests` (sources in `Tests/PreferansEngineTests/` — note the folder name). Run with full Xcode selected and **without** `PREFERANS_ENGINE_TESTS_ONLY`/`PREFERANS_SERVER_ONLY` set:

```sh
swift test --filter PreferansAppTests                   # every app + online-integration test in the target
swift test --filter LobbyViewModelTests
swift test --filter GameViewModelTapAdvanceTests
swift test --filter GameViewModelDealSourceTests
swift test --filter TableLayoutModelTests
swift test --filter ScenarioFlowTests
swift test --filter LocalizationCatalogTests
swift test --filter ThemePaletteTests
swift test --filter "ActivityLogFeedTests|CardDisplayOrderingTests|DealSummaryPresentationTests|SeatRoleBadgeFeedTests|OnlineWaitingRoomLayoutTests|TestHarnessTests"
swift test                                              # complete default graph (engine core, server core, app)
```

App tests that exercise clock/UUID-dependent code (e.g. `GameViewModelTapAdvanceTests`, `GameViewModelDealSourceTests`, `LobbyViewModelTests`, `ScenarioFlowTests`, `RoomOnlineGameCoordinatorTests`) inherit from `AppTestCase` (the rest use plain `XCTestCase` or Swift Testing), which installs `ImmediateClock` and an incrementing UUID generator via swift-dependencies; tests that need virtual time wrap their body in `withDependencies { $0.continuousClock = TestClock() }`.

Engine-only portable lane (no SwiftUI, works with Command Line Tools):

```sh
bin/test-engine
bin/test-engine --filter EngineGenerativeTests
```

## Run the snapshot tests

`TableScreenSnapshotTests` (Swift Testing, `.snapshots(record: .missing)`) writes **structural text** snapshots (`.lines` strategy), not images:

```sh
swift test --filter TableScreenSnapshotTests
```

References live in `Tests/PreferansEngineTests/__Snapshots__/TableScreenSnapshotTests/*.txt` (`biddingEastViewerKeepsClockwiseTableOrder.east.txt`, `talonExchangeDefenderViewKeepsPublicPrikupScreen.east.txt`, `midTrickDefenderViewKeepsTrickPlacement.east.txt`). Missing references are recorded on the first run; to re-record an intentional change, delete the affected `.txt` file and run the suite again, then review the diff. (`ProjectionSnapshotTests` in the same folder belongs to [`../004-online-multiplayer`](../004-online-multiplayer/).)

## Run the UI tests (Xcode / simulator)

```sh
bin/test-ui                                         # build-for-testing + all PreferansUITests except RedesignScreenshotTests
bin/test-ui --no-build                              # reuse the last build
bin/test-ui -only-testing:PreferansUITests/AccessibilityContractTests
bin/test-ui -only-testing:PreferansUITests/FullGameUITests/testGame1_ClassicSochi
bin/test-ui -only-testing:PreferansUITests/ThemeUITests/testThemeSwitchPreservesLiveDealAndPersistsOnRelaunch
DEST_NAME='iPad Pro 13-inch (M4)' bin/test-ui -only-testing:PreferansUITests/OnlineWaitingRoomUITests
```

Direct `xcodebuild` form (from `docs/TESTING.md`):

```sh
xcodebuild test -project Preferans.xcodeproj -scheme Preferans \
  -only-testing:PreferansUITests/AccessibilityContractTests/testLobbyAndGameExposeStableAutomationRoots
```

`NativeOnlineUITests` require a local worker (see below) and pass its URL to the app through `PREFERANS_ROOM_WORKER_URL`. Individual UI tests should finish within 60 s (90 s maximum); shrink the scenario rather than raising timeouts (AGENTS.md).

## Screenshots (only from current source)

Never reason about the UI from PNGs left on disk. Use:

```sh
dir="$(bin/screens-latest)" || { bin/screens && dir="$(bin/screens-latest)"; }
bin/screens --only-testing PreferansUITests/RedesignScreenshotTests/testCaptureRedesignScreens
bin/screens --no-open --keep-runs 5
```

`bin/screens` runs `RedesignScreenshotTests` and `OnlineScreensScreenshotTests` and writes `bin/.screens/<run-id>/*.png` plus `capture.json` provenance; `bin/screens-latest` exits 2 when no run exists and 3 when the newest run does not match the current source.

## Local online development

```sh
bin/dev-online      # builds Dockerfile.server, runs the engine on 127.0.0.1:18081, then wrangler dev on http://127.0.0.1:8787
```

Point a simulator build at it (DEBUG only, and only together with a `-uiTest…` argument):

```sh
SIMCTL_CHILD_PREFERANS_ROOM_WORKER_URL=http://127.0.0.1:8787 \
  xcrun simctl launch "<UDID>" com.mixandmatch.preferans -uiTestDisableAnimations
```

`TestHarness.localRoomWorkerURL` accepts only `http://localhost` or `http://127.0.0.1` root URLs without credentials, query or fragment; local identities are stored under a separate `.uiTestLocal.<host>.<port>` suffix. Multi-simulator invite verification: `bin/verify-online-invite-flow HOST_UDID CLIENT_UDID CLIENT_UDID [CLIENT_UDID]` (see `../004-online-multiplayer` and `../006-testing-and-release`).

## Launch Arguments

All flags are defined in `UITestFlags` (`Sources/PreferansEngine/UIIdentifiers.swift`) and consumed through `TestHarness` (`Preferans/Support/TestHarness.swift`) unless noted. Any argument beginning with `-uiTest` marks the process as UI automation (onboarding bypass, no ATT request, automation affordances allowed).

| Flag | Value | Effect | Consumer |
| --- | --- | --- | --- |
| `-uiTestTheme` | theme raw value | Persist theme before views load (DEBUG only) | `PreferansApp.init` |
| `-uiTestShowOnboarding` | — | Force the onboarding tour | `TestHarness.shouldShowOnboarding` |
| `-uiTestPreviewSettlement` | — | Root = `SettlementPreviewGallery` (DEBUG only) | `PreferansApp.rootContent` |
| `-uiTestDisableAnimations` | — | Disable UIKit + SwiftUI animations | `PreferansApp.init` |
| `-uiTestFastBotDelay` | — | Bot delay = `BotPacing.testFast` (10 ms), local and online | `LobbyViewModel.startLocalTable`, `onlineBotMoveDelay` |
| `-uiTestSkipTapToAdvance` | — | `tapToAdvanceEnabled = false` | `LobbyViewModel.startLocalTable` |
| `-uiTestViewerFollowsActor` | — | `ViewerPolicy.followsActor` | `TestHarness.resolveConfiguration` |
| `-uiTestPinLanguageEn` / `-uiTestPinLanguageRu` | — | Apply English / Russian at launch | `PreferansApp.init` |
| `-uiTestMatchScript` | `game1`/`Game1ClassicSochi`, `game2`/`Game2LongSochi`, `game3`/`Game3RostovDedicatedTotus` | Players, first dealer, rules, match and scripted decks from `MatchScriptFixtures` | `resolveConfiguration` |
| `-uiTestPlayers` | `north,east,south[,west]` | Override seat IDs (bots are then not assigned) | `resolveConfiguration` |
| `-uiTestFirstDealer` | player id | Override first dealer | `resolveConfiguration` |
| `-uiTestPoolTarget` | integer | Override `MatchSettings.poolTarget` | `resolveConfiguration` |
| `-uiTestRaspasyPolicy` | `singleshot`, `sochi`/`arithmetic`/`1-2-3`, `leningrad`/`piter`/`2-4-6`, `geometric`/`1-2-4` | Override raspasy policy | `resolveConfiguration` |
| `-uiTestTotusPolicy` | `asTenTrickGame:<bool>` or `dedicated:<bool>:<bonusPool>` | Override totus policy | `resolveConfiguration` |
| `-uiTestDealScenario` | `sortedDeck`, `northBidsSpadesSix`, `northBidsMisere` | Scripted single-deck source | `TestHarness.dealSource(from:)` |
| `-uiTestDealSeed` | UInt64 | `SeededDealSource(seed:)` | `TestHarness.dealSource(from:)` |
| `-uiTestOnlineFlowLogging` | — | Emit `ONLINE_FLOW` log lines | online coordinators |
| `-uiTestAutoCreateOnlineRoom` | — | Create a private worker room after the lobby appears | `LobbyView.runOnlineHarnessIfNeeded` |
| `-uiTestAutoJoinOnlineRoom` | room code | Join that room after the lobby appears | `LobbyView.runOnlineHarnessIfNeeded` |
| `-uiTestAutoStartOnlineDealOnJoin` | — | Host auto-starts the first deal once every expected player has joined/connected (and the host can start) | online coordinators |
| `-uiTestAutoCreateInMemoryRoom` | — | DEBUG all-bot in-memory room → waiting room | `LobbyView.runOnlineHarnessIfNeeded` |
| `-uiTestAutoCreateInMemoryInviteRoom` | — | In-memory room with open remote seats | `LobbyView.runOnlineHarnessIfNeeded` |

Auto-create/join flows seed the online name "Player" when no identity is valid. Standard system arguments used by the UI tests also work, e.g. `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, `-AppleLanguages "(ru)"`, `-AppleLocale ru_RU`, `-settings.appLanguage ru`.

## Environment Variables

| Variable | Used by | Meaning |
| --- | --- | --- |
| `PREFERANS_ROOM_WORKER_URL` | app (`TestHarness.localRoomWorkerURL`) | Loopback worker base URL (only with a `-uiTest…` flag, DEBUG) |
| `PREFERANS_ENGINE_TESTS_ONLY=1` | `Package.swift`, `bin/test-engine`, CI | Engine-only package graph (no app target) |
| `PREFERANS_SERVER_ONLY=1` | `Package.swift` | Server-only package graph |
| `SCHEME`, `DEST_NAME`, `DEST_ID`, `DERIVED`, `BUNDLE_ID` | `bin/sim`, `bin/test-ui`, `bin/screens` (`DEST_ID` only in `bin/test-ui`/`bin/screens`; `BUNDLE_ID` only in `bin/sim`) | Scheme, simulator selection, derived-data path, bundle id |
| `KEEP_RUNS` | `bin/screens` | Number of screenshot runs to keep (default 3) |
| `PREFERANS_TEST_DIAGNOSTICS=on-failure` | UI test scripts | Opt-in system diagnostics collection |
| `WATCH=1` | `bin/test-engine` | Re-run on `.swift` change (needs `watchexec`) |
