# Feature Specification: Quality Engineering & Release Tooling

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `Package.swift`, `Package.resolved`, `Tests/`, `PreferansUITests/`, `Sources/PreferansEngine/{HandRecipe,MatchScript,MatchScriptFixtures,EngineMatchDriver,DealSource,UIIdentifiers}.swift`, `Preferans/Support/{TestHarness,BotPacing}.swift`, `bin/`, `.github/workflows/`, `Preferans.xcodeproj/`, `fastlane/`, `AppStore/`, `docs/`, `AGENTS.md`

Related specs (not duplicated here): rules engine [`specs/001-game-rules`](../001-game-rules), scoring [`specs/002-scoring-and-variants`](../002-scoring-and-variants), bots [`specs/003-bots`](../003-bots), backend/worker tests and server deploy [`specs/004-online-multiplayer`](../004-online-multiplayer), screens/themes/localization [`specs/005-ios-app`](../005-ios-app).

## Summary

Preferans ships a layered, deterministic test system and a script-driven release process:

- **Three SwiftPM lanes** chosen by environment variable inside `Package.swift`: a dependency-free *portable engine* lane (`PREFERANS_ENGINE_TESTS_ONLY=1`) that runs on Command Line Tools and Linux, a *server* lane (`PREFERANS_SERVER_ONLY=1`) used only to build the Linux engine container, and the *default* lane with every library and test target.
- **A test pyramid** of 645 runnable Swift/Python cases: 3 tooling tests → 47 portable engine cases → 234 engine-core cases → 298 app/server integration cases (including 9 structural text snapshots) → 63 XCUITest instances, plus a multi-simulator invite-flow script. (Worker tests are in `specs/004`.)
- **Deterministic fixtures**: recipe-built decks (`HandRecipe`), declarative whole-match scripts (`MatchScript`) replayed identically by the engine driver and the UI driver, named single-deal decks (`DealScenario`), and a portable seeded xoshiro256\*\* RNG.
- **A robot/driver/oracle UI architecture** (`MatchUIRobot`, `MatchUIDriver`) that speaks engine domain types and never sleeps.
- **Source-bound simulator artifacts**: every build-for-testing and every screenshot run is stamped with a SHA-256 manifest of app/engine/UI-test/project inputs; stale products and stale screenshots are refused (`bin/screens-latest` exit codes 2/3).
- **Linux-only CI** (worker contracts + portable engine on every push; a build-only server-image workflow). No macOS/Xcode job exists.
- **Release** by `xcodebuild archive`/`-exportArchive`, App Store Connect (ASC) API Node scripts that refuse to edit non-draft versions and write JSON evidence, git tags per uploaded build, and a legacy fastlane setup. Legal pages are Markdown under `docs/` for GitHub Pages.

### Test pyramid (counts as of `cd78828`)

| Layer | Target (directory) | Framework | Test functions | Runnable cases | How to run |
|---|---|---|---|---|---|
| L0 tooling | `Tests/Tooling/test_screen_provenance.py` | Python `unittest` | 3 | 3 | `python3 Tests/Tooling/test_screen_provenance.py` |
| L1 portable engine | `PreferansEngineCLITests` (`Tests/PreferansEngineCLITests`) | Swift Testing | 10 | **47** (36 generative + 11) | `bin/test-engine` |
| L2 engine core | `PreferansEngineTests` (`Tests/PreferansEngineCoreTests`) | XCTest | 234 | 234 | `swift test --filter PreferansEngineTests` |
| L3 app integration | `PreferansAppTests` (`Tests/PreferansEngineTests`) | XCTest 265 + Swift Testing 24 | 289 | 289 (3 skip without `PREFERANS_WORKER_URL`) | `swift test --filter PreferansAppTests` |
| L3 server core | `PreferansServerCoreTests` (`Tests/PreferansServerCoreTests`) | XCTest | 9 | 9 | `swift test --filter PreferansServerCoreTests` |
| **Default SwiftPM total** | 4 test targets | | 542 | **579** | `swift test` |
| L4 UI | `PreferansUITests` (Xcode target) | XCUITest | 59 in 10 files (12 Swift files incl. `MatchUIRobot`/`MatchUIDriver` helpers) | 63 (`OwnerOnlineUITests` re-runs 4 inherited) — 51 in `bin/test-ui` default scope | `bin/test-ui`, `bin/screens` |
| L5 multi-device | `bin/verify-online-invite-flow` | shell + `simctl` + unified log | — | 1 flow per 3 or 4 sims | see Story 8 |
| Worker (see `specs/004`) | `workers/room-worker` | node:test + vitest/workerd | 52 + 14 | 66 | `bun run check` |

Note the **name/directory inversion**: SwiftPM target `PreferansEngineTests` lives in `Tests/PreferansEngineCoreTests`, while target `PreferansAppTests` lives in `Tests/PreferansEngineTests` (`Package.swift`).

## User Scenarios & Testing

### User Story 1 – Run the portable engine tests without Xcode (Priority: P1)

As a contributor, I can run the rules engine's seeded generative and determinism suite with only Swift Command Line Tools (or the Linux `swift:6.3.2-jammy` image) so that rules changes get fast feedback without building the SwiftUI app or booting a simulator.

**Why this priority**: It is the only Swift test lane that CI runs, and the cheapest gate on the shared engine that local play, bots and the server all depend on.

**Independent Test**: On a machine where `xcode-select -p` points at `/Library/Developer/CommandLineTools`, run `bin/test-engine`; 47 cases execute and pass. In CI the `portable-engine` job runs the same graph.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** I run `bin/test-engine`, **Then** the script exports `PREFERANS_ENGINE_TESTS_ONLY=1`, module caches under `/tmp/preferans-*-module-cache`, and runs `swift test` against a graph with no external package dependencies (`bin/test-engine`, `Package.swift`).
2. **Given** the active developer directory ends in `/CommandLineTools`, **When** `bin/test-engine` runs, **Then** it adds `-Xswiftc -plugin-path …/usr/lib/swift/host/plugins/testing` and two `-Xlinker -rpath` flags so Swift Testing loads without Xcode.
3. **Given** I pass `--filter EngineGenerativeTests`, **When** the script runs, **Then** the argument is forwarded verbatim to `swift test`.
4. **Given** `WATCH=1` and `watchexec` installed, **When** I run `bin/test-engine`, **Then** tests rerun on every `.swift` change; **Given** `watchexec` is missing, **Then** the script exits `1` with `WATCH=1 requires watchexec.`
5. **Given** any engine change that breaks an invariant or Codable round trip on any of 36 seeded walks, **When** the suite runs, **Then** the failure names the seed and step (`EngineGenerativeTests.swift`).

---

### User Story 2 – Run the full SwiftPM graph (Priority: P1)

As a contributor with full Xcode, I can run `swift test` to execute engine-core, app view-model/coordinator, snapshot, and server-core tests on the macOS host.

**Why this priority**: 532 of the 642 Swift test cases (83%) exist only in this lane (projection privacy, online coordinators, scoring variants, lobby view model, localization catalog completeness).

**Independent Test**: `swift test` reports 579 cases; exactly 3 (`OnlineWorkerIntegrationTests`) skip unless `PREFERANS_WORKER_URL` is set.

**Acceptance Scenarios**:

1. **Given** full Xcode, **When** I run `swift test`, **Then** targets `PreferansEngineCLITests`, `PreferansEngineTests`, `PreferansAppTests`, `PreferansServerCoreTests` build against `swift-snapshot-testing`, `swift-dependencies` and `hummingbird` (`Package.swift`).
2. **Given** an app test subclassing `AppTestCase`, **When** it runs, **Then** `\.continuousClock` is `ImmediateClock()` and `\.uuid` is `.incrementing`, so bot timers never really sleep (`Tests/PreferansEngineTests/AppTestCase.swift`).
3. **Given** `PREF_SIM_FULL=1`, **When** `BotSimulationReportTests` runs, **Then** it plays 50 seeded bot matches instead of the 5-match smoke batch (`Tests/PreferansEngineCoreTests/BotSimulationReportTests.swift`).
4. **Given** `PREFERANS_UPDATE_WIRE_FIXTURE=1`, **When** `AuthoritativeGameServiceTests.testCheckedInWireFixtureMatchesSwiftCodec` runs, **Then** it rewrites `workers/room-worker/fixtures/create-game.json` from the Swift codec before asserting equality.

---

### User Story 3 – Run the UI suite on one warm simulator with bounded time (Priority: P1)

As a contributor, I can run `bin/test-ui` to build once and iterate on XCUITests against a single warm simulator, with each test bounded to 60 s (hard maximum 90 s) and never against stale build products.

**Why this priority**: UI tests are the only proof that the SwiftUI surface, accessibility identifiers and harness flags agree with the engine.

**Independent Test**: `bin/test-ui` then `bin/test-ui --no-build -only-testing:PreferansUITests/MatchUITests`; edit any file under `Preferans/` and repeat `--no-build` — the run is refused with exit code 3.

**Acceptance Scenarios**:

1. **Given** no `-only-testing:` argument, **When** I run `bin/test-ui`, **Then** scope is `-only-testing:PreferansUITests -skip-testing:PreferansUITests/RedesignScreenshotTests` on `iPhone 17 Pro` (`bin/test-ui`).
2. **Given** a build, **When** tests run, **Then** `xcodebuild test-without-building` uses `-parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 -collect-test-diagnostics ${PREFERANS_TEST_DIAGNOSTICS:-never}` (`bin/lib/xcode-sim.sh`).
3. **Given** a source file changed after the last `build-for-testing`, **When** I run `bin/test-ui --no-build`, **Then** `screen-provenance.py check` lists up to 8 changed paths and exits 3 before `xcodebuild` starts.
4. **Given** a file changes *during* `build-for-testing`, **When** the build finishes, **Then** the post-build check fails and the pending manifest is not promoted to `.preferans-test-build.json`.
5. **Given** several simulators share a name, **When** I set `DEST_ID=<UDID>`, **Then** the destination is `platform=iOS Simulator,id=<UDID>`.
6. **Given** only Command Line Tools, **When** any Xcode script runs, **Then** it prints the active developer dir and exits `69`.

---

### User Story 4 – Look only at screenshots rendered from the current source (Priority: P1)

As a reviewer or AI agent, I can obtain the newest screenshot run **only if** it was rendered from exactly the current working-tree inputs, so that I never critique stale pixels.

**Why this priority**: `AGENTS.md` makes this a hard rule; App Store media generation (`AppStore/render-media.mjs`) depends on it.

**Independent Test**: `dir="$(bin/screens-latest)" || { bin/screens && dir="$(bin/screens-latest)"; }` — after any edit under `Preferans/`, `Sources/`, `PreferansUITests/`, the project file, schemes, or `Package.*`, `bin/screens-latest` exits 3.

**Acceptance Scenarios**:

1. **Given** no run directory under `bin/.screens/` containing a PNG, **When** I run `bin/screens-latest`, **Then** it prints `[screens-latest] No rendered screenshots. Run bin/screens.` and exits **2**.
2. **Given** the newest run lacks `capture.json` (legacy) or its `sourceDigest` differs from the current manifest, **When** I run `bin/screens-latest`, **Then** it lists changed files and exits **3**.
3. **Given** a matching run, **When** I run `bin/screens-latest`, **Then** it prints the absolute run path and exits 0.
4. **Given** I touch every input file without changing content, **When** I check provenance, **Then** it still passes (mtime is ignored) (`Tests/Tooling/test_screen_provenance.py`).
5. **Given** `bin/screens`, **When** it runs, **Then** it deletes old `build/screens*` buckets, prunes to `KEEP_RUNS` (default 3), runs `RedesignScreenshotTests` and `OnlineScreensScreenshotTests`, extracts XCTest attachments plus deduplicated bucket PNGs into `bin/.screens/<YYYYmmdd-HHMMSS>/`, writes `capture.json`, opens the folder unless `--no-open`, and exits with the test status.

---

### User Story 5 – Write a deterministic scenario once, replay it in engine and UI (Priority: P2)

As a contributor, I can describe a whole match (deck recipe + auction + discard + contract + whists + play strategy per deal) as a `MatchScript`, validate it in milliseconds through `EngineMatchDriver`, then replay the identical script through the SwiftUI app.

**Why this priority**: It removes re-derivation of auctions/plays in UI tests and turns UI drift into immediate, well-located failures.

**Independent Test**: `swift test --filter EngineMatchDriverTests` passes; `bin/test-ui -only-testing:PreferansUITests/FullGameUITests/testGame1_ClassicSochi` passes; `bin/sim game1` shows the same deals.

**Acceptance Scenarios**:

1. **Given** a `MatchScript` that supplies too many deals, **When** replayed, **Then** `MatchScriptError.gameOverBeforeDealConsumed` is thrown; too few → `.matchDidNotReachGameOver` (`EngineMatchDriver.swift`).
2. **Given** `-uiTestMatchScript game1`, **When** the app's lobby starts a local table, **Then** players, first dealer, rules, match settings and a `ScriptedDealSource` of recipe-built decks come from `MatchScriptFixtures.game1ClassicSochi` (`TestHarness.swift`).
3. **Given** `MatchUIDriver.run()`, **When** each scripted action is tapped through `MatchUIRobot`, **Then** the same action is applied to an internal engine, and at the end the game-over panel's deal count, winner and every player's pool/mountain must equal the engine's `MatchSummary` (`MatchUIDriver.swift`).
4. **Given** a script that would emit a settlement action, **When** the UI driver meets it, **Then** the test fails (`XCTFail`) because the UI driver only supports trick-by-trick play.
5. **Given** a `HandRecipe` called with other than 3 unique active seats, **When** `deck(for:)` runs, **Then** it traps with a precondition.

---

### User Story 6 – Launch the app in a known state on a simulator (Priority: P2)

As a contributor, I can run `bin/sim game2` (or `--scenario northBidsSpadesSix --dealer south`, `--seed 42`) to eyeball a reproducible table without editing the Xcode scheme.

**Why this priority**: Manual visual QA of a specific mid-match state otherwise requires wiring launch arguments by hand.

**Independent Test**: `bin/sim --scenario northBidsSpadesSix --dealer south` boots `iPhone 17`, installs a Debug build of `com.mixandmatch.preferans` and launches with `-uiTestViewerFollowsActor -uiTestDisableAnimations -uiTestDealScenario northBidsSpadesSix -uiTestFirstDealer south`.

**Acceptance Scenarios**:

1. **Given** no simulator named `DEST_NAME`, **When** I run `bin/sim`, **Then** it exits 1. (The script's `No available simulator named '…'. Set DEST_NAME=.` hint is unreachable: under `set -euo pipefail` the failing `SIM_UDID="$(preferans_sim_udid_for_name …)"` assignment aborts the script first, silently.)
2. **Given** `--skip-build` and no previous build, **When** I run `bin/sim`, **Then** it exits 1 (`Could not locate Preferans.app`).
3. **Given** `bin/sim game2 -- -uiTestPoolTarget 30`, **When** launched, **Then** everything after `--` is appended as launch arguments.
4. **Given** any `bin/sim` launch, **When** bots move, **Then** they use the lobby's bot-speed picker, never `BotPacing.testFast` (the script never passes `-uiTestFastBotDelay`).
5. **Given** an unknown flag or a second positional argument, **Then** `bin/sim` exits 64.

---

### User Story 7 – Update structural snapshot baselines deliberately (Priority: P2)

As a contributor, when I intentionally change what a viewer's projection or table-screen contract contains, I can re-record the 9 text baselines and review them as a normal diff.

**Why this priority**: The baselines lock privacy boundaries (hidden hands, talon reveal) and clockwise seat placement.

**Independent Test**: Delete `Tests/PreferansEngineTests/__Snapshots__/TableScreenSnapshotTests/biddingEastViewerKeepsClockwiseTableOrder.east.txt`, run `swift test --filter TableScreenSnapshotTests` twice: the first run records and reports a failure, the second passes; `git diff` shows the file.

**Acceptance Scenarios**:

1. **Given** suites declared with `.snapshots(record: .missing)`, **When** a baseline file is absent, **Then** it is written and the assertion fails once; existing baselines are asserted, never overwritten.
2. **Given** `[PlayerID: Int]` dictionaries encode as alternating arrays, **When** the projection snapshot is produced, **Then** pairs are sorted by `rawValue` and JSON keys are sorted, so baselines are deterministic.
3. **Given** a projection change, **When** the snapshot differs, **Then** the failure is a line diff of a `.txt` file named `<testName>.<viewer>.txt`.

---

### User Story 8 – Exercise online flows locally and across simulators (Priority: P2)

As an online-play developer, I can start a loopback engine + room worker with `bin/dev-online`, run native online UI tests against it, and verify a 3- or 4-player invite flow across real simulators without coordinates or screenshots.

**Why this priority**: Online regressions are the main production risk listed in `README.md`.

**Independent Test**: `bin/dev-online` (terminal 1); `bin/test-ui -only-testing:PreferansUITests/NativeOnlineUITests` (terminal 2) — 4 tests run instead of skipping. Boot 3 simulators and run `bin/verify-online-invite-flow UDID1 UDID2 UDID3`.

**Acceptance Scenarios**:

1. **Given** the loopback worker is not answering `GET http://127.0.0.1:8787/health` with `service == "preferans-room-worker"`, **When** `NativeOnlineUITests` set up, **Then** each test throws `XCTSkip`.
2. **Given** native online tests created peer accounts, **When** a test tears down, **Then** each account is deleted via `DELETE /v2/account`; a deletion failure is a test failure.
3. **Given** `TEST_RUNNER_PREFERANS_OWNER_SERVER_QA=1` on `xcodebuild`, **When** `OwnerOnlineUITests` run, **Then** the 4 inherited tests target the owner production worker; without it they skip before any network call.
4. **Given** 3 or 4 booted simulator UDIDs, **When** `bin/verify-online-invite-flow` runs, **Then** it builds once, launches the host with `-uiTestAutoCreateOnlineRoom -uiTestAutoStartOnlineDealOnJoin`, parses `ONLINE_FLOW event=create roomCode=…`, launches clients with `-uiTestAutoJoinOnlineRoom <code>`, and requires every seat to log `sequence=1 phase=bidding` for its own viewer within 30 s per wait; any other argument count exits 64.

---

### User Story 9 – CI guards every push (Priority: P2)

As a maintainer, every push and pull request runs worker contracts and the portable engine lane on Linux; a separate manual/branch-triggered workflow builds and smoke-tests the server image without deploying.

**Why this priority**: It is the only automated gate; it intentionally holds no deployment credentials.

**Independent Test**: Push any branch; the `Multiplayer contracts` workflow runs jobs `worker` and `portable-engine`.

**Acceptance Scenarios**:

1. **Given** any `push` or `pull_request`, **When** `.github/workflows/multiplayer.yml` runs, **Then** job `worker` (ubuntu-latest, Node 24, Bun) runs `bun install --frozen-lockfile` and `bun run check`, and job `portable-engine` (container `swift:6.3.2-jammy`) runs `PREFERANS_ENGINE_TESTS_ONLY=1 swift test`.
2. **Given** `workflow_dispatch` or a push to `ci/owner-server-build`, **When** `owner-server-build.yml` runs, **Then** it type-checks/tests the worker (60 s timeouts), dry-runs `wrangler deploy`, builds `Dockerfile.server` for `linux/amd64`, smoke-tests `/health` and `POST /v1/games`, and uploads a 14-day artifact with `SHA256SUMS`; permissions are `contents: read`, nothing is deployed. Details: `specs/004-online-multiplayer`.

---

### User Story 10 – Cut and record an App Store / TestFlight build (Priority: P2)

As a release manager, I bump the build number, archive and upload a signed build, verify the package, record provenance, and tag the source, without touching the live store version unintentionally.

**Why this priority**: 29 builds have shipped; history shows App Review rejections (build 19 launch crash) that were traced through this provenance.

**Independent Test**: For build 29: `MARKETING_VERSION = 1.0.3`, `CURRENT_PROJECT_VERSION = 29` in `project.pbxproj`; `AppStore/Release29/package-verification.json` records version/build/Xcode/SDK/signature; tag `testflight/1.0.3-build-29` exists.

**Acceptance Scenarios**:

1. **Given** a new build, **When** preparing it, **Then** `CURRENT_PROJECT_VERSION` increments by one (never reset across marketing versions) and `MARKETING_VERSION` changes only when the ASC version train requires it (`AppStore/BuildHistory.md`).
2. **Given** an exported IPA at `build/export29/Preferans.ipa`, **When** `node AppStore/verify-build29.mjs` runs, **Then** it asserts bundle ID, version/build, Xcode build, URL scheme, strict `codesign` verification, entitlements (`get-task-allow == false`, Sign in with Apple, associated domain), expected backend/privacy strings, and absence of the subscription product ID, then writes `package-verification.json`.
3. **Given** an uploaded build, **When** release is recorded, **Then** a `Release-<version>.md` / `Release<build>/` evidence set and an annotated tag `testflight/<version>-build-<n>` (or `appstore/…`) are created.

---

### User Story 11 – Localize store metadata and keywords safely (Priority: P3)

As a release manager, I can validate 24 store localizations offline, apply them only to a draft version, verify readback, and roll back keyword edits.

**Why this priority**: Store metadata is public; mistakes are visible immediately.

**Independent Test**: `node AppStore/sync-localizations.mjs` (no flags) prints `Validated 24 localizations…`; `node AppStore/Keywords-1.0.3/sync.mjs` prints `Validated 23 keyword-only updates at 100 characters each…` — both without network access.

**Acceptance Scenarios**:

1. **Given** a localization exceeding a limit (name/subtitle 30, promotional text 170, description/what's new 4000, keywords 100 Unicode characters) or a non-https URL or a locale outside the 24 allowed, **When** validating, **Then** the script throws.
2. **Given** `--apply`, **When** the target version or App Info is not `PREPARE_FOR_SUBMISSION`, **Then** the script refuses to edit.
3. **Given** keyword sync, **When** applying, **Then** en-US is never patched, every other locale is exactly 100 characters with no duplicate terms and includes the owner terms `pref` and `tick`; `--apply` and `--rollback` are mutually exclusive.

---

### User Story 12 – Publish legal pages (Priority: P3)

As the app owner, Support, Privacy Policy and Terms of Use are Markdown files in `docs/` rendered by GitHub Pages (Jekyll theme `minima`) and referenced from App Store metadata.

**Why this priority**: Required by App Store Connect; changes rarely.

**Independent Test**: `docs/_config.yml` sets `theme: minima`; `docs/index.md` links the three pages; store metadata points at `https://dmytrogusev.github.io/preferans/…`.

**Acceptance Scenarios**:

1. **Given** the policies, **When** read, **Then** they state: online play processes a server-issued guest ID or Sign in with Apple ID, display name, room/game data and timestamps; local play stays on device; no sale or ad/data-broker sharing; account deletion from Settings removes server profile, sessions, library, room credentials and identity, leaving anonymized seat/score in shared results; the app is not gambling.
2. **Given** build 29, **When** a user opens Settings → Privacy Policy / Terms of Use, **Then** the app links to `https://guruofcards.com/apps/preferans/privacy/` and `/terms/` instead of the GitHub Pages copies (`Preferans/UI/SettingsScreen.swift`).

### Edge Cases

- **Command Line Tools only**: `bin/test-engine` works; `swift test` (default lane) and every Xcode script fail — the latter with exit 69 and an explanatory message.
- **Linux**: only the engine lane (and server lane build) is supported; the default lane contains SwiftUI app code.
- **Ambiguous simulator names**: `DEST_NAME` resolves by name; use `DEST_ID` for an exact runtime (`bin/lib/xcode-sim.sh`).
- **Failing screenshot run**: `bin/screens` still extracts PNGs and writes `capture.json` with `testExitCode`; `bin/screens-latest` does **not** check that exit code, so frames from a failing run are returned as fresh.
- **Run with zero PNGs**: ignored by `bin/screens-latest`; an older matching run may be returned instead.
- **`xcresulttool` without `export attachments`** (pre-Xcode 16): attachments are not extracted; a hint to open the `.xcresult` is printed.
- **Env vars into the UI-test runner** must carry the `TEST_RUNNER_` prefix (`bin/screens` comment); `PREFERANS_SCREEN_DIR` falls back to `$TMPDIR/preferans-screens`.
- **Tap-to-advance gate** would deadlock scripted matches; harness flag `-uiTestSkipTapToAdvance` disables it (and it is disabled automatically when no seat is human).
- **Lazy horizontal choice rail on iPhone**: high bids may not exist in the accessibility tree; the robot swipes the compact rail up to 8 times before tapping.
- **Overlapping card fan**: the robot taps the leading 8% sliver (`dx: 0.08`) of a card, or double-taps to play.
- **Reused simulators**: UI automation bypasses onboarding regardless of persisted state unless `-uiTestShowOnboarding` is passed; language is pinned explicitly.
- **Snapshot record mode**: the suite trait `record: .missing` takes precedence over library-level defaults (see Known Gaps).
- **`HandRecipe` with 4 players**: recipes take the 3 *active* seats per deal; the 4-player scripts rely on rotation computed via `activePlayers(forDealer:)`.
- **ASC credentials absent**: `AppStore/asc.mjs` throws `Set ASC_KEY_PATH to your private key outside the repository.`

## Requirements

### Functional Requirements

**SwiftPM lanes and dependencies**

- **FR-001**: The system MUST select the package graph at manifest-evaluation time: `PREFERANS_SERVER_ONLY=1` (checked first) selects the server lane, else `PREFERANS_ENGINE_TESTS_ONLY=1` selects the engine-test lane, else the default lane. — `Package.swift`
- **FR-002**: The engine-test lane MUST have no package dependencies and contain only `PreferansEngine`, library target `PreferansEngineTestSupport` (path `Tests/PreferansEngineTestSupport`), and test target `PreferansEngineCLITests`. — `Package.swift`
- **FR-003**: The server lane MUST contain `PreferansEngine`, `PreferansServerCore`, executable `PreferansServer`, depend only on `hummingbird` (from 2.22.0), and contain no test targets; `Dockerfile.server` MUST build it with `PREFERANS_SERVER_ONLY=1 swift build -c release --product PreferansServer` on `swift:6.3.2-jammy`. — `Package.swift`, `Dockerfile.server`
- **FR-004**: The default lane MUST declare `swift-snapshot-testing` (from 1.17.0), `swift-dependencies` (from 1.5.0) and `hummingbird` (from 2.22.0), library `PreferansApp` built from `Preferans/` (excluding `PreferansApp.swift`, assets, entitlements, `Info.plist`; processing `Resources/Localizable.xcstrings`), and test targets `PreferansServerCoreTests`, `PreferansEngineCLITests`, `PreferansEngineTests`, `PreferansAppTests` (the latter excluding `__Snapshots__`). Platforms: iOS 16, macOS 14, tvOS 16, watchOS 9; `defaultLocalization: "en"`. — `Package.swift`
- **FR-005**: `Package.resolved` MUST be committed at the root (re-included by `!/Package.resolved` in `.gitignore`) and pins 32 packages, including `swift-snapshot-testing` 1.19.4, `swift-dependencies` 1.17.1, `hummingbird` 2.26.0, `swift-nio` 2.101.3, `swift-syntax` 603.0.2. — `Package.resolved`, `.gitignore`

**Developer scripts**

- **FR-006**: `bin/test-engine` MUST export `PREFERANS_ENGINE_TESTS_ONLY=1`, default `SWIFTPM_MODULECACHE_OVERRIDE=/tmp/preferans-swiftpm-module-cache` and `CLANG_MODULE_CACHE_PATH=/tmp/preferans-clang-module-cache`, add Swift Testing plugin/rpath flags under Command Line Tools, forward arguments, and support `WATCH=1` via `watchexec --exts swift --restart`. — `bin/test-engine`
- **FR-007**: Every Xcode-dependent helper MUST verify `xcodebuild -version` succeeds and otherwise return 69 with the active developer directory. — `bin/lib/xcode-sim.sh` (`preferans_require_xcode`)
- **FR-008**: `preferans_build_for_testing` MUST stamp a pending source manifest, run `xcodebuild build-for-testing -project Preferans.xcodeproj -scheme <scheme> -destination <dest> -derivedDataPath <derived> -quiet`, re-check the manifest, and only then rename it to `<derived>/.preferans-test-build.json`. — `bin/lib/xcode-sim.sh`
- **FR-009**: `preferans_test_without_building` MUST refuse to run when `<derived>/.preferans-test-build.json` does not match current source (exit 3) and MUST pass `-parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 -collect-test-diagnostics ${PREFERANS_TEST_DIAGNOSTICS:-never}`. — `bin/lib/xcode-sim.sh`
- **FR-010**: `bin/test-ui` MUST default to `SCHEME=Preferans`, `DEST_NAME="iPhone 17 Pro"`, `DERIVED=build/DerivedData`, scope `-only-testing:PreferansUITests -skip-testing:PreferansUITests/RedesignScreenshotTests` unless any `-only-testing:` is passed, accept `--no-build`, and pass all other arguments to `xcodebuild` verbatim. — `bin/test-ui`
- **FR-011**: `bin/screens` MUST accept `--keep-runs N` (default 3, env `KEEP_RUNS`), `--no-build`, `--no-open`, repeated `--only-testing <id>` (default `RedesignScreenshotTests` + `OnlineScreensScreenshotTests`), reject unknown flags with 64, export `TEST_RUNNER_PREFERANS_SCREEN_DIR=$(pwd)/build`, write `bin/.screens/<run-id>/{*.png, build-source.json, capture.json}` plus `<run-id>.xcresult`, and exit with the `xcodebuild` status. — `bin/screens`
- **FR-012**: `bin/screens-latest` MUST print the newest `bin/.screens/*` directory that contains a PNG only when `provenance.check(<run>/capture.json)` passes; exit 2 when no such run exists and 3 when provenance is missing or stale. — `bin/screens-latest`
- **FR-013**: The source manifest MUST be SHA-256 of every file under `Preferans/`, `Sources/`, `PreferansUITests/` (except `.DS_Store`), every `project.pbxproj` and `*.xcscheme` under `Preferans.xcodeproj/`, `Package.swift` and `Package.resolved`, with `sourceDigest` = SHA-256 of the sorted JSON map (`schema: 1`); `stamp` adds `builtAt` and `commit`; `capture` adds `capturedAt`, `testExitCode`, `destination`, `tests`; file modification times MUST NOT affect the result. — `bin/lib/screen-provenance.py`, `Tests/Tooling/test_screen_provenance.py`
- **FR-014**: `bin/sim` MUST build Debug for `DEST_NAME` (default `iPhone 17`), boot, install and launch `BUNDLE_ID` (default `com.mixandmatch.preferans`) with `-uiTestViewerFollowsActor` (unless `--no-rotate-viewer`) and `-uiTestDisableAnimations` (unless `--animations`), mapping positional script name → `-uiTestMatchScript`, `--scenario` → `-uiTestDealScenario`, `--dealer` → `-uiTestFirstDealer`, `--seed` → `-uiTestDealSeed`, and arguments after `--` verbatim; `--skip-build` reuses the last build. — `bin/sim`
- **FR-015**: `bin/verify-online-invite-flow` MUST require 3 or 4 simulator UDIDs (else exit 64), build into `PREFERANS_DERIVED_DATA` (default `/tmp/preferans-derived-data`), stream unified logs filtered on subsystem `com.mixandmatch.preferans` category `online-flow`, and fail after 30 s on any missing `ONLINE_FLOW` milestone. It depends on `rg` (ripgrep). — `bin/verify-online-invite-flow`
- **FR-016**: `bin/dev-online` MUST build `Dockerfile.server` as `preferans-engine:local`, run it on `127.0.0.1:18081`, wait up to 30 × 1 s for `/health`, then run `bun install --frozen-lockfile` and `bun run wrangler dev --config wrangler.local.toml --local --port 8787` in `workers/room-worker`, stopping the container on exit. — `bin/dev-online`

**Test harness (app side)**

- **FR-017**: Accessibility identifiers, launch flags and parsed UI strings MUST be defined once in `PreferansEngine` (`UIIdentifiers`, `UITestFlags`, `AccessibilityStrings`); identifiers are ASCII with card encoding `<rank><suit>` (`T` = ten, suits `S C D H`, `NT`). — `Sources/PreferansEngine/UIIdentifiers.swift`
- **FR-018**: The app MUST treat any launch argument starting with `-uiTest` as UI automation; automation MUST skip onboarding unless `-uiTestShowOnboarding`, and `PREFERANS_ROOM_WORKER_URL` MUST be honored only under automation and only for `http://localhost` or `http://127.0.0.1` root URLs without credentials, query or fragment. — `Preferans/Support/TestHarness.swift`
- **FR-019**: The harness MUST support these 23 flags: `-uiTestTheme` (DEBUG only), `-uiTestShowOnboarding`, `-uiTestPreviewSettlement` (DEBUG only), `-uiTestViewerFollowsActor`, `-uiTestFirstDealer <id>`, `-uiTestDealSeed <UInt64>`, `-uiTestDealScenario <sortedDeck|northBidsSpadesSix|northBidsMisere>`, `-uiTestMatchScript <game1|game2|game3|Game…>`, `-uiTestPlayers <a,b,c[,d]>`, `-uiTestPoolTarget <Int>`, `-uiTestRaspasyPolicy <singleShot|sochi|leningrad|geometric and aliases>`, `-uiTestTotusPolicy <asTenTrickGame:<bool>|dedicated:<bool>:<bonus>>`, `-uiTestDisableAnimations`, `-uiTestFastBotDelay`, `-uiTestSkipTapToAdvance`, `-uiTestPinLanguageEn`, `-uiTestPinLanguageRu`, `-uiTestOnlineFlowLogging`, `-uiTestAutoCreateOnlineRoom`, `-uiTestAutoCreateInMemoryRoom`, `-uiTestAutoCreateInMemoryInviteRoom`, `-uiTestAutoJoinOnlineRoom <code>`, `-uiTestAutoStartOnlineDealOnJoin`. — `UIIdentifiers.swift` (`UITestFlags`), `TestHarness.swift`, `Preferans/PreferansApp.swift`
- **FR-020**: Configuration resolution MUST apply, in order: lobby defaults → named match script (players, first dealer, rules, match settings, scripted decks) → per-field overrides (`players`, `firstDealer`, `poolTarget`, `raspasyPolicy`, `totusPolicy`). Without a match script the deal source is `dealScenario` > `dealSeed` > `RandomDealSource`. — `TestHarness.resolveConfiguration`
- **FR-021**: Bot pacing MUST come from `BotPacing`: `interactive` 500 ms (default of `GameViewModel.botMoveDelay` and online coordinators), `normal` 1200 ms (lobby picker default), `slow` 2200 ms, `testFast` 10 ms applied only with `-uiTestFastBotDelay`, `instant` 0 (Watch-bots / Instant). — `Preferans/Support/BotPacing.swift`, `Preferans/UI/LobbyModels.swift`, `Preferans/UI/LobbyViewModel.swift`

**Deterministic fixtures**

- **FR-022**: `HandRecipe` MUST offer `declarerWins`, `declarerFails(declarerWillTake:)`, `cleanMisere`, `totusMakes`, `totusFails`, `raspasyCleanExit(talonLeadSuit:)` and produce, for exactly three unique active seats, a permutation of `Deck.standard32` in the engine's packet layout (5 packets × 2 cards per seat, talon after packet 0). — `Sources/PreferansEngine/HandRecipe.swift`, `HandRecipeTests.swift`
- **FR-023**: `MatchScriptFixtures` MUST expose `game1ClassicSochi` (first dealer north, pool 20, 6 deals), `game2LongSochi` (south, pool 24, 5 deals), `game3RostovDedicatedTotus` (west, pool 32, 6 deals) by long and short names, each closing the pulka on its last deal and documenting the pool-sum trajectory inline. — `Sources/PreferansEngine/MatchScriptFixtures.swift`, `EngineMatchDriverTests.swift`
- **FR-024**: `MatchScriptStepper` MUST replay deals in step order (auction → discard → contract → whists → defender mode → play), expose `beforeDeal`/`afterStartDeal`/`beforeAction` hooks, bound card play to 64 steps, compare cards by rank for greedy/lowest strategies, and throw typed `MatchScriptError`s. — `Sources/PreferansEngine/EngineMatchDriver.swift`
- **FR-025**: `SeededRandomNumberGenerator` MUST be a pure-Swift xoshiro256\*\* seeded through SplitMix64 (seed 0 remapped), so the same seed yields the same deck on Apple platforms and Linux; `SeededDealSource` and `ScriptedDealSource` MUST serialize access with a lock. — `Sources/PreferansEngine/DealSource.swift`, `DealSourceTests.swift`
- **FR-026**: Shared test support MUST provide `CountingDealSource`, `EnginePlayPolicy` (`lowestLegal`, `highestLegal`, `declarerHighestDefendersLowest`), `EngineTestDriver` (auction/discard/contract/whist/play-out, step limit 64) and `BotTestDriver` (step limit 96, stop reasons `phaseCompleted`, `strategyReturnedNoAction`, `engineRejectedAction`, `stepLimitReached`, querying the controlling actor). — `Tests/PreferansEngineTestSupport/EngineTestSupport.swift`

**Unit, generative and snapshot tests**

- **FR-027**: `EngineGenerativeTests` MUST walk 2 configurations (Sochi 3-player, dealer south; `sochiWithTalonLedAllPass` 4-player, dealer west) × seeds 1…18 for up to 180 random legal actions (including settlement proposals with probability 1/6), validating `PreferansEngine.validateInvariants` and JSON round-trip equality at every step. — `Tests/PreferansEngineCLITests/EngineGenerativeTests.swift`
- **FR-028**: Structural snapshot suites MUST use `.snapshots(record: .missing)`, strategy `.lines`, `named: viewer`, and store baselines at `Tests/PreferansEngineTests/__Snapshots__/<SuiteFile>/<test>.<viewer>.txt` (6 projection JSON baselines, 3 table-screen contract baselines). — `ProjectionSnapshotTests.swift`, `TableScreenSnapshotTests.swift`
- **FR-029**: Environment-gated tests MUST skip or shrink by default: `PREFERANS_WORKER_URL` (live worker integration, 3 tests), `PREF_SIM_FULL=1` (50 vs 5 bot matches), `PREFERANS_UPDATE_WIRE_FIXTURE=1` (regenerate worker fixture). — `OnlineWorkerIntegrationTests.swift`, `BotSimulationReportTests.swift`, `AuthoritativeGameServiceTests.swift`
- **FR-030**: Performance baselines MUST be metric-only (`measure(metrics: [XCTClockMetric(), XCTCPUMetric()])`) in `EngineMatchDriverTests` and `ProjectionTests`. — same files

**UI tests**

- **FR-031**: `MatchUIRobot` MUST be the only UI-test code that resolves identifiers, expose one method per engine action and one read per engine query, synchronize via `waitForExistence`/`XCTNSPredicateExpectation` (default 2.0 s, optional reads 0.25 s), and append `phase/viewer/error` context to failures. — `PreferansUITests/MatchUIRobot.swift`
- **FR-032**: `MatchUIDriver` MUST mirror every scripted action into an internal engine oracle and assert game-over presence, deals played, winner and per-player pool/mountain against the engine summary. — `PreferansUITests/MatchUIDriver.swift`
- **FR-033**: UI tests MUST pin English (`-uiTestPinLanguageEn -AppleLanguages (en) -AppleLocale en_US`) unless they test localization, and default to `-uiTestDisableAnimations -uiTestFastBotDelay -uiTestSkipTapToAdvance`. — `MatchUIRobot.swift` (`XCUIApplication` extension)
- **FR-034**: `MatchScreenshotRecorder` MUST skip a capture whose dedupe key equals the previous key unless `force`, optionally write `<prefix>-<NNN>-<name>.png` into a bucket directory, and attach the screenshot with lifetime `.keepAlways`. — `MatchUIRobot.swift`
- **FR-035**: Native online UI tests MUST skip without a healthy loopback worker, delete QA accounts on teardown, and `OwnerOnlineUITests` MUST skip unless `PREFERANS_OWNER_SERVER_QA=1` reaches the runner. — `PreferansUITests/NativeOnlineUITests.swift`

**CI**

- **FR-036**: `.github/workflows/multiplayer.yml` MUST run on every `push` and `pull_request`: job `worker` (`bun run check` = typecheck + node tests + vitest/workerd) and job `portable-engine` (`PREFERANS_ENGINE_TESTS_ONLY=1 swift test` in `swift:6.3.2-jammy`). — `.github/workflows/multiplayer.yml`
- **FR-037**: `.github/workflows/owner-server-build.yml` MUST trigger only on `workflow_dispatch` or push to `ci/owner-server-build`, run with `contents: read`, a 30-minute job timeout and non-cancelling per-ref concurrency, and MUST NOT deploy or push images. — `.github/workflows/owner-server-build.yml`, `docs/SERVER_CI.md`

**Release**

- **FR-038**: The app version MUST be `MARKETING_VERSION` and the build number `CURRENT_PROJECT_VERSION` in both app configurations of `Preferans.xcodeproj/project.pbxproj` (currently 1.0.3 / 29; the UI-test bundle stays 1.0 / 1); bundle ID `com.mixandmatch.preferans`; deployment target iOS 17.0; device family iPhone+iPad. — `project.pbxproj`
- **FR-039**: Each uploaded build MUST be recorded with source commit, changes and verification (`AppStore/BuildHistory.md`, `AppStore/Release-<ver>.md`, `AppStore/Release29/`, `AppStore/ReleaseEvidence/`) and tagged `testflight/<ver>-build-<n>` or `appstore/<ver>-build-<n>` (with legacy `rollback/testflight-1.0-build-<n>` aliases for builds 4–17). — `AppStore/`, git tags
- **FR-040**: Export MUST use `AppStore/ExportOptions-AppStore.plist`: method `app-store-connect`, destination `upload`, automatic signing, `uploadSymbols`, `stripSwiftSymbols`, `manageAppVersionAndBuildNumber`, iCloud environment `Production`. — `AppStore/ExportOptions-AppStore.plist`
- **FR-041**: ASC scripts MUST authenticate with an ES256 JWT built from `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` (key file outside the repo), only call `/v1/` or `/v2/` API paths with a 60 s timeout, refuse to edit versions/App Info not in `PREPARE_FOR_SUBMISSION`, back up the before-state once, and append progress/evidence JSON. — `AppStore/asc.mjs`, `sync-localizations.mjs`, `upload-media.mjs`, `place-creatives.mjs`, `Keywords-1.0.3/sync.mjs`
- **FR-042**: `AppStore/render-media.mjs` MUST run `bin/screens-latest` and `screen-provenance.py check` on each `IPHONE_CAPTURE`/`IPAD_CAPTURE`/`MEDIUM_CAPTURE` run before composing store media. — `AppStore/render-media.mjs`
- **FR-043**: fastlane MUST provide `ios upload_screenshots` (screenshots only) and `ios upload_store_assets` (metadata, categories, content rights, review info, screenshots), never upload a binary and never submit for review. — `fastlane/Fastfile`
- **FR-044**: Secrets and generated artifacts MUST be git-ignored: `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.xcarchive`, `*.ipa`, `build/`, `DerivedData/`, `.build`, `bin/.screens/`, `AppStore/Screenshots/raw/`, `node_modules/`, `.wrangler/`. — `.gitignore`
- **FR-045**: Legal pages MUST live in `docs/` (`index.md`, `support.md`, `privacy-policy.md`, `terms-of-use.md`, `_config.yml` with `theme: minima`) for GitHub Pages. — `docs/`

**Contributor / agent conventions**

- **FR-046**: AI agents MUST respond in English, MUST NOT reason about UI from on-disk screenshots without the `bin/screens-latest` freshness check, and MUST treat long timeouts as a bug signal (shrink the case, emit per-phase progress, dedupe screenshots, reference `BotPacing` constants, bound loops instead of wrappers). — `AGENTS.md`

### Key Entities

- **Lane**: a package graph selected by `PREFERANS_ENGINE_TESTS_ONLY` / `PREFERANS_SERVER_ONLY`; determines products, dependencies and targets.
- **Test target**: SwiftPM `PreferansEngineCLITests`, `PreferansEngineTests`, `PreferansAppTests`, `PreferansServerCoreTests`; Xcode `PreferansUITests` (the only testable in the shared `Preferans` scheme).
- **MatchScript / DealScript**: declarative whole-match fixture (players, first dealer, rules, match settings, deals); each deal = `HandRecipe` + auction + `DiscardChoice` + contract + whists + defender mode + `CardPlayStrategy`.
- **HandRecipe**: named outcome → 32-card deck for 3 active seats.
- **DealScenario**: named single-deal 3-player deck (`sortedDeck`, `northBidsSpadesSix`, `northBidsMisere`) for first dealer `south`.
- **DealSource**: `RandomDealSource`, `SeededDealSource(seed:)`, `ScriptedDealSource(decks:)`, test-only `CountingDealSource`.
- **UITestFlags / UIIdentifiers / AccessibilityStrings**: shared contract between app and UI tests.
- **MatchUIRobot / MatchUIDriver / MatchScreenshotRecorder**: UI-test layers.
- **Source manifest**: `{schema, sourceDigest, files{path: sha256}}` + `builtAt`/`commit` (build) or `capturedAt`/`testExitCode`/`destination`/`tests` (capture); stored as `build/DerivedData/.preferans-test-build.json`, `bin/.screens/<run>/build-source.json`, `bin/.screens/<run>/capture.json`.
- **Screens run**: `bin/.screens/<YYYYmmdd-HHMMSS>/` with PNGs (attachments + `screens*` buckets), sibling `.xcresult`.
- **Snapshot baseline**: `.txt` file under `__Snapshots__`.
- **Release evidence**: JSON readbacks/backups under `AppStore/ReleaseEvidence/`, `AppStore/Release29/`, `AppStore/Keywords-1.0.3/`, `AppStore/Media/1.0.2/provenance.json`.
- **Store localization**: `AppStore/Localizations/<locale>.json` (24 locales).
- **Release tag**: `testflight/…`, `appstore/…`, `rollback/…`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The portable lane executes 47 cases with zero package dependencies on macOS Command Line Tools and in `swift:6.3.2-jammy` (CI).
- **SC-002**: The default SwiftPM lane executes 579 cases; without network configuration exactly 3 skip.
- **SC-003**: No XCUITest can run longer than 90 s (enforced allowance); the default allowance is 60 s.
- **SC-004**: A full 4-player bot match to pool 6 with animations and bot delay disabled completes in well under one minute (`AGENTS.md` target); match-driver UI runs stay within the 30-second budget cited for `-uiTestFastBotDelay` (`UIIdentifiers.swift`). *(Targets stated in code/docs; not re-measured for this document.)*
- **SC-005**: `bin/screens-latest` returns 0 only when every manifest input is byte-identical to the capture's build; 3 Python tests prove content changes, added/removed files and missing records invalidate, while timestamp-only changes do not.
- **SC-006**: 100% of pushes and pull requests run worker contracts and the portable engine lane.
- **SC-007**: The 9 snapshot baselines are byte-stable across runs (sorted keys + normalized player-keyed arrays).
- **SC-008**: Store metadata for 24 locales validates offline; for 1.0.3, 23 locales carry exactly 100-character keyword strings and en-US remains unchanged (99 characters) (`AppStore/Keywords-1.0.3/README.md`).
- **SC-009**: Every build from 27 onward has an annotated git tag pointing at its source commit; build 29's archive matches 142 recorded source hashes (`AppStore/Release29/source-manifest.json`, `docs/OWNER_MULTIPLAYER_BUILD29.md`).

## Known Gaps & Open Questions

Code-vs-doc discrepancies (reality documented above):

1. `docs/TESTING.md` says `bin/test-engine` runs **42** cases; the lane now has **47** (`MisereVisibilityTests`, added in `b2c1d76`, contributes 5).
2. `AGENTS.md` says `bin/screens-latest` exits 3 when frames are "older than any `Preferans/**.swift`" and that screenshots must reflect `HEAD`; the implementation compares a **content digest** of `Preferans/`, `Sources/`, `PreferansUITests/`, project/scheme files and `Package.*` against the **working tree** (uncommitted edits count); mtimes are ignored.
3. `AGENTS.md` calls `BotPacing.interactive` (500 ms) "the production default"; local tables actually use the lobby picker (`BotMoveSpeed.normal` = 1200 ms by default; `slow` 2200 ms). `interactive` is only the fallback default of `GameViewModel.botMoveDelay` and online coordinators.
4. Package platforms say iOS 16 while the Xcode app targets iOS 17.0.
5. The shared Xcode scheme tests only `PreferansUITests`; SwiftPM test targets are not in the scheme and there is no `.xctestplan`.
6. CI has **no macOS job**: the default SwiftPM lane, UI tests, snapshot tests and `Tests/Tooling` Python tests never run in CI. The Python tests have no runner script; the command in this spec is inferred.
7. `bin/screens-latest` ignores `testExitCode` in `capture.json` (failing runs count as fresh) and forwards an unused `${1:-}` argument.
8. `bin/test-ui`'s default scope excludes `RedesignScreenshotTests` but still runs `OnlineScreensScreenshotTests` (a screenshot suite with `continueAfterFailure = true`).
9. `fastlane/Fastfile` is legacy (April 2026): inline en-US description/keywords/promotional text and review notes predate 1.0.1–1.0.3 (e.g. "Account -> Delete account data" vs current "Delete online account"); `fastlane/screenshots/en-US/*` are byte-identical to `AppStore/Screenshots/*`, which `AppStore/Screenshots/README.md` marks historical; both lanes use `overwrite_screenshots: true`. Running `upload_store_assets` today would overwrite newer live metadata/screenshots. `fastlane/README.md` mentions `bundle exec` but no `Gemfile` exists.
10. `fastlane/Fastfile` and `AppStore/asc.mjs` embed fallback defaults for the ASC key ID / issuer ID, a machine-specific key path and personal review-contact data; these should be environment-only. (Values intentionally not reproduced here.)
11. `AppStore/Localizations/*.json` still hold 1.0.2 keywords/what's new and GitHub Pages privacy URLs; re-running `sync-localizations.mjs --apply` against the 1.0.3 draft would revert the 1.0.3 keyword work and the app's Settings legal links differ (guruofcards.com).
12. `AppStore/BuildHistory.md` stops at 1.0.2 (28) and says 1.0.2 was not released; `docs/OWNER_MULTIPLAYER_BUILD29.md` reports 1.0.2 (28) as `READY_FOR_SALE` and documents build 29. Builds 21–26 have no git tags.
13. `README.md` and `AppStore/ReleaseChecklist.md` describe archiving from Xcode; recorded builds used `xcodebuild archive` + `xcodebuild -exportArchive` with an ASC API key. `docs/TESTING.md` ladder step 3 omits `-destination`.
14. `docs/support.md` (last updated 2026-04-27) tells users they must be signed in with Apple; guest accounts exist. The privacy policy states no advertising identifiers are collected, while the app build settings include an ATT usage string for advertising attribution (`INFOPLIST_KEY_NSUserTrackingUsageDescription` in `project.pbxproj`) and `TrackingPermissionCenter.advertisingIdentifierForTracking` exists (no caller found).
15. `AppStore/Assets/README.md` says the folder is documentation-only, but it contains `icon-source/generate_app_icons.swift`. `AppStore/render-media.mjs` requires `sharp` but no `package.json` exists under `AppStore/`.
16. `bin/verify-online-invite-flow` silently depends on `rg`; GitHub Actions are pinned to major tags (`@v4`, `@v2`), not commit SHAs; no toolchain pin file (`.xcode-version`, `.swift-version`, `.nvmrc`) exists.

Open questions:

- [NEEDS CLARIFICATION: Snapshot re-recording — the suites pin `record: .missing` at trait level, which (per swift-snapshot-testing ≥1.17 behaviour) takes precedence over the `SNAPSHOT_TESTING_RECORD` environment variable. Is "delete the baseline and rerun" the intended workflow, or should the trait read the env var?]
- [NEEDS CLARIFICATION: How build 29's IPA at `build/export29/Preferans.ipa` relates to `ExportOptions-AppStore.plist` (`destination: upload` does not leave a local IPA). Which exact export/upload commands are canonical?]
- [NEEDS CLARIFICATION: `manageAppVersionAndBuildNumber: true` allows Xcode to change the build number at export; does that conflict with the manual monotonic `CURRENT_PROJECT_VERSION` convention?]
- [NEEDS CLARIFICATION: Which legal-page host is canonical — GitHub Pages (`docs/`, store metadata) or guruofcards.com (app Settings, build 29 verification)? Are the two texts kept identical?]
- [NEEDS CLARIFICATION: Is fastlane deprecated in favour of `AppStore/*.mjs`? If so, should the lanes be removed to prevent accidental overwrites?]
- [NEEDS CLARIFICATION: Should a macOS CI job run `swift test` and a UI smoke subset, given `AGENTS.md` timing budgets?]
- [NEEDS CLARIFICATION: Branch policy — observed prefixes are `release/<ver>-build-<n>`, `store/*`, `fix/*`, `feature/*`, `ci/*`, with PRs merged into `main`; no written policy or branch protection is checked in.]
