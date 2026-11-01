# Quickstart: From Clone to Green Tests to a Release Build

Verified against `store/1.0.3-localized-keywords` @ `cd78828` by reading the scripts; commands were **not executed** while writing this document. Run everything from the repository root unless stated otherwise.

## 0. Prerequisites

| Tool | Needed for | Notes |
|---|---|---|
| macOS + **full Xcode** | app build, `swift test` (default lane), all `bin/` simulator scripts | Project last upgraded with Xcode 26.4; build 29 was archived with Xcode 27.1 (`27A9275`). Scripts exit **69** if only Command Line Tools are active. `bin/screens` needs Xcode 16+ for `xcresulttool export attachments`. |
| iOS Simulator runtimes with **iPhone 17 Pro** and **iPhone 17** | `bin/test-ui`, `bin/screens` / `bin/sim` defaults | Override with `DEST_NAME='…'`, or `DEST_ID=<UDID>` (`bin/test-ui`/`bin/screens` only; `bin/sim` ignores it). |
| Swift Command Line Tools *or* Xcode | `bin/test-engine` | Works with CLT alone. |
| Python 3 | provenance checks (`bin/lib/screen-provenance.py`) | stdlib only. |
| Docker | `bin/dev-online`, server image | Image base `swift:6.3.2-jammy`. |
| Bun (+ Node 24 as in CI) | worker, `bin/dev-online` (`bun run wrangler …`) | Wrangler comes from the worker's `devDependencies`. |
| ripgrep (`rg`) | `bin/verify-online-invite-flow` | Undeclared dependency. |
| watchexec | optional `WATCH=1 bin/test-engine` | |
| Node + `sharp` | `AppStore/render-media.mjs` only | No `package.json` under `AppStore/`. |
| fastlane | legacy store lanes only | See the fastlane warning in §12. |

## 1. Clone

```sh
git clone https://github.com/DmytroGusev/preferans.git
cd preferans
git log --oneline -1
```

Nothing needs to be generated: the Xcode project and `Package.resolved` are committed.

## 2. Portable engine tests (≈ first green, no Xcode needed)

```sh
bin/test-engine                                  # 47 Swift Testing cases
bin/test-engine --filter EngineGenerativeTests   # one suite (36 seeded walks)
WATCH=1 bin/test-engine                          # rerun on .swift changes (needs watchexec)
```

Same lane as CI's `portable-engine` job. To reproduce CI exactly on Linux:

```sh
docker run --rm -v "$PWD":/src -w /src swift:6.3.2-jammy \
  bash -c 'PREFERANS_ENGINE_TESTS_ONLY=1 swift test --scratch-path /tmp/.build'
```

(`--scratch-path` keeps the Linux `.build` out of your macOS checkout.)

> **Side effect, observed 2026-11-01:** the engine lane resolves a package graph with **no dependencies**, so SwiftPM **deletes the committed `Package.resolved`** in your working tree (`git status` shows ` D Package.resolved`). Restore it before committing, `git restore Package.resolved`, or the next full-graph build will re-resolve to newer versions. CI is unaffected because it never commits.

## 3. Tooling tests

```sh
python3 Tests/Tooling/test_screen_provenance.py   # 3 unittest cases; not wired into CI
```

## 4. Full SwiftPM graph (full Xcode)

```sh
swift test                                        # 579 cases; 3 skip without PREFERANS_WORKER_URL
swift test --filter PreferansEngineTests          # engine core   (dir Tests/PreferansEngineCoreTests)
swift test --filter PreferansAppTests             # app/integration (dir Tests/PreferansEngineTests)
swift test --filter PreferansServerCoreTests
swift test --filter EngineMatchDriverTests        # canonical match scripts, milliseconds
swift test --filter RoomOnlineGameCoordinatorTests
swift test --filter WireCompatibilityTests
```

Optional switches:

```sh
PREF_SIM_FULL=1 swift test --filter BotSimulationReportTests        # 50 bot matches instead of 5
PREFERANS_UPDATE_WIRE_FIXTURE=1 swift test --filter AuthoritativeGameServiceTests   # rewrites workers/room-worker/fixtures/create-game.json
PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests  # needs a running worker (§8)
```

## 5. Open in Xcode

```sh
open Preferans.xcodeproj
```

- Scheme **Preferans** (only shared scheme). Run = app; Test = `PreferansUITests` only (SwiftPM tests are not in the scheme).
- Bundle ID `com.mixandmatch.preferans`, entitlements `Preferans/Preferans.entitlements` (Sign in with Apple, Game Center, associated domains). On another Apple team, change `DEVELOPMENT_TEAM` locally and do not commit it.
- Compile check without signing, as recorded in `AppStore/BuildHistory.md`:

```sh
xcodebuild build -project Preferans.xcodeproj -scheme Preferans \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

## 6. UI tests on one warm simulator

```sh
bin/test-ui                                       # build-for-testing + all UI tests except RedesignScreenshotTests
bin/test-ui --no-build                            # reuse products (refused with exit 3 if any input changed)
bin/test-ui -only-testing:PreferansUITests/FullGameUITests/testGame1_ClassicSochi
bin/test-ui -only-testing:PreferansUITests/AccessibilityContractTests
DEST_NAME='iPhone 17' bin/test-ui
DEST_ID=<UDID from `xcrun simctl list devices available`> bin/test-ui   # exact runtime when names collide
PREFERANS_TEST_DIAGNOSTICS=on-failure bin/test-ui -only-testing:PreferansUITests/MatchUITests
```

Each test has a 60 s default and 90 s maximum allowance. If a test approaches that, shrink the scenario (one deal, fewer bots, smaller pool target) rather than raising limits (`AGENTS.md`).

## 7. Run the app on a simulator in a known state

```sh
bin/sim                                           # lobby, random deals, iPhone 17
bin/sim game1                                     # canonical match script (game1 | game2 | game3)
bin/sim --scenario northBidsSpadesSix --dealer south
bin/sim --seed 42
bin/sim game2 -- -uiTestPoolTarget 30 -uiTestTheme midnight
bin/sim --no-rotate-viewer --animations game1
bin/sim --skip-build game1                        # reinstall last build
```

`bin/sim` always adds `-uiTestViewerFollowsActor` and `-uiTestDisableAnimations` (unless disabled) and never `-uiTestFastBotDelay`, so bots move at the lobby's picker speed.

## 8. Screenshots you are allowed to look at

```sh
dir="$(bin/screens-latest)" || { bin/screens && dir="$(bin/screens-latest)"; }
echo "$dir"; ls "$dir"
```

| `bin/screens-latest` exit | Meaning | Action |
|---|---|---|
| 0 | prints newest run whose `capture.json` digest equals current sources | read PNGs in that dir |
| 2 | no run with PNGs under `bin/.screens/` | `bin/screens` |
| 3 | newest run has no `capture.json` or sources changed | `bin/screens` |

Other `bin/screens` options: `--no-build`, `--no-open`, `--keep-runs 5`, `--only-testing PreferansUITests/RedesignScreenshotTests/testCaptureRedesignScreens`, `DEST_NAME=…`/`DEST_ID=…`. Note that `capture.json` records `testExitCode`, which `bin/screens-latest` does not check — inspect it if the run might have failed.

## 9. Online development (loopback)

Terminal 1:

```sh
bin/dev-online        # Docker engine on 127.0.0.1:18081, then wrangler dev worker on 127.0.0.1:8787
```

Terminal 2:

```sh
bin/test-ui -only-testing:PreferansUITests/NativeOnlineUITests      # otherwise these 4 tests XCTSkip
PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests
(cd workers/room-worker && bun install --frozen-lockfile && bun run check)   # same as CI job `worker`
```

Multi-simulator invite flow — **not loopback**: per its usage text it verifies the *deployed* Cloudflare invite flow using the worker URL compiled into the Debug app (see `specs/004-online-multiplayer`). Needs 3 or 4 booted simulators and `rg`:

```sh
xcrun simctl list devices available
xcrun simctl boot <UDID1>; xcrun simctl boot <UDID2>; xcrun simctl boot <UDID3>
bin/verify-online-invite-flow <UDID1> <UDID2> <UDID3>            # add a 4th UDID for 4 players
```

Live owner-server UI QA is opt-in and creates/deletes real accounts — only with authorization, on a dedicated simulator:

```sh
TEST_RUNNER_PREFERANS_OWNER_SERVER_QA=1 bin/test-ui -only-testing:PreferansUITests/OwnerOnlineUITests
```

## 10. Write a new deterministic scenario

**Single deal (UI smoke)** — add a case to `DealScenario` in `Preferans/Support/TestHarness.swift` built with `DealDeckLayout.deck(north:east:south:talon:)` (3 players, first dealer `south`, north bids first); launch with `-uiTestDealScenario <name>`; cover the engine flow in `Tests/PreferansEngineTests/ScenarioFlowTests.swift`.

**Whole match (engine + UI)**:

1. If needed, add a `HandRecipe` case in `Sources/PreferansEngine/HandRecipe.swift` (3 active seats, deck must stay a permutation of `Deck.standard32` in the packet layout) and prove its named outcome in `Tests/PreferansEngineCoreTests/HandRecipeTests.swift`.
2. Add `public static let game4… : MatchScript` to `MatchScriptFixtures` using the `DealScript` builders (`makeGameContract`, `makeFailedGameContract`, `makeMisere`, `makeRaspasy`, `makeTenTrickGame`, `makeDedicatedTotus`). Comment the per-deal dealer/active seats and the pool-sum trajectory; make the pool target fire on the **last** deal.
3. Register it in `allCanonical` and in `script(named:)` with a short name (`"game4"`).
4. `swift test --filter EngineMatchDriverTests` — the suite checks game over on the expected deal, contract-type coverage and failure counts across all canonical scripts.
5. Add a UI test: `func testGame4_…() throws { try runScript("game4", expected: MatchScriptFixtures.game4…) }` in `PreferansUITests/FullGameUITests.swift`, then `bin/test-ui -only-testing:PreferansUITests/FullGameUITests/testGame4_…`.
6. Eyeball it: `bin/sim game4`.

Constraints: scripts must not contain settlement actions (the UI driver fails on them); greedy/lowest strategies compare by **rank**, never by `Card`'s suit-first ordering.

**Seeded randomness**: `-uiTestDealSeed <n>` / `SeededDealSource(seed:)` / `Deck.shuffled(seed:)` give identical decks on every platform.

## 11. Update snapshot baselines intentionally

```sh
rm Tests/PreferansEngineTests/__Snapshots__/ProjectionSnapshotTests/midTrickPlay_declarerView.north.txt
swift test --filter ProjectionSnapshotTests      # records the missing baseline and reports a failure
swift test --filter ProjectionSnapshotTests      # passes
git diff --stat Tests/PreferansEngineTests/__Snapshots__
```

The suites pin `record: .missing`, so existing baselines are never overwritten automatically. To regenerate all at once, temporarily change the suite trait to `.snapshots(record: .all)`, run, and revert the trait.

## 12. Release build (authorized release managers only)

> These steps touch signing keys and App Store Connect. They are the as-practiced sequence reconstructed from `AppStore/BuildHistory.md`, `AppStore/Release29/` and the scripts; flags not present in the repository are marked *(standard xcodebuild flag)*.

1. **Branch**: `git switch -c release/<version>-build-<n>` (or `fix/…` for hotfix builds).
2. **Bump** `CURRENT_PROJECT_VERSION` (+1, never reset) and, for a new train, `MARKETING_VERSION` — in the app target's Debug *and* Release configurations of `Preferans.xcodeproj/project.pbxproj` (the UI-test target stays `1.0`/`1`):
   ```sh
   sed -i '' 's/CURRENT_PROJECT_VERSION = 29;/CURRENT_PROJECT_VERSION = 30;/' Preferans.xcodeproj/project.pbxproj
   ```
3. **Verify**: `bin/test-engine && swift test && bin/test-ui`, plus the compile check from §5.
4. **Archive**:
   ```sh
   xcodebuild archive -project Preferans.xcodeproj -scheme Preferans -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/Preferans-30.xcarchive
   ```
5. **Export & upload** with `AppStore/ExportOptions-AppStore.plist` (`destination: upload`, automatic signing). The API key lives outside the repo:
   ```sh
   xcodebuild -exportArchive -archivePath build/Preferans-30.xcarchive \
     -exportOptionsPlist AppStore/ExportOptions-AppStore.plist -exportPath build/export30 \
     -allowProvisioningUpdates \
     -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
     -authenticationKeyIssuerID "$ASC_ISSUER_ID"          # (standard xcodebuild flags)
   ```
   To verify a local IPA before uploading (as done for build 29 with `build/export29/Preferans.ipa`), export with a copy of the plist whose `destination` is `export`, then adapt and run `node AppStore/verify-build29.mjs` (it asserts version/build, Xcode build, `codesign --verify --deep --strict`, entitlements, backend/privacy strings).
6. **Processing**: wait for ASC state `VALID`; complete export compliance; check TestFlight group access. Save readbacks as JSON (pattern: `AppStore/Release29/*.json`, `what-to-test.txt`).
7. **Store metadata** (draft version only):
   ```sh
   node AppStore/sync-localizations.mjs                         # offline validation of 24 locales
   ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_VERSION_ID=… ASC_APP_INFO_ID=… \
     node AppStore/sync-localizations.mjs --apply
   node AppStore/Keywords-1.0.3/sync.mjs                        # keyword plan validation (1.0.3-specific)
   ```
   Do **not** re-apply `AppStore/Localizations/*.json` to the 1.0.3 draft without first copying the 1.0.3 keywords from `AppStore/Keywords-1.0.3/plan.json` — the JSON files still carry 1.0.2 keywords.
8. **Store media** (only from source-verified captures): run `bin/screens` on an iPhone and an iPad simulator, then
   ```sh
   IPHONE_CAPTURE=bin/.screens/<run> IPAD_CAPTURE=bin/.screens/<run> node AppStore/render-media.mjs
   DEST_ID=<iPhone UDID> node AppStore/record-preview.mjs        # app preview video via testRecordAppStorePreview
   ASC_VERSION_ID=… node AppStore/upload-media.mjs
   ```
9. **Record**: add an entry to `AppStore/BuildHistory.md` (date, source commit, changes, verification, ASC state) and a `Release-<version>.md`; commit.
10. **Tag** the exact source commit and push the tag:
    ```sh
    git tag -a testflight/1.0.4-build-30 <source-sha> -m "Preferans 1.0.4 (30): <state and notes>"
    git push origin testflight/1.0.4-build-30
    ```
    Use `appstore/<version>-build-<n>` for builds attached to an App Store version.
11. **Review submission** is a manual, separately authorized step; no script in the repo submits for review.

**fastlane warning**: `fastlane ios upload_screenshots` and `fastlane ios upload_store_assets` (needs `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, optional `APP_REVIEW_FIRST_NAME`, `APP_REVIEW_LAST_NAME`, `APP_REVIEW_EMAIL`, `APP_REVIEW_PHONE`) upload April-2026 en-US metadata and the historical screenshots with `overwrite_screenshots: true`. Do not run them against a current version.

## 13. Legal pages

Edit `docs/support.md`, `docs/privacy-policy.md`, `docs/terms-of-use.md` (update the "Last updated" line); GitHub Pages renders `docs/` with Jekyll `minima` at `https://dmytrogusev.github.io/preferans/`. The app's Settings links point to the guruofcards.com copies (`Preferans/UI/SettingsScreen.swift`) — keep both in sync.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `[preferans] Full Xcode is required…`, exit 69 | Command Line Tools selected | `sudo xcode-select -s /Applications/Xcode.app` |
| `[screens] Source differs from the recorded build/capture`, exit 3 | sources changed since build | drop `--no-build` / run `bin/screens` |
| `bin/sim` exits 1 right after start with no message (its `No available simulator named …` hint is never reached under `set -e`) | no available simulator with that name/runtime | install runtime or `DEST_NAME=…` |
| Native online UI tests skipped | loopback services not running | `bin/dev-online` |
| `Unknown flag`, exit 64 | bad script argument | `bin/sim --help`, `bin/test-ui --help`, `bin/screens --help` print the header comment; `bin/verify-online-invite-flow` prints usage on a wrong argument count |
| `Set ASC_KEY_PATH to your private key outside the repository.` | ASC scripts without credentials | export `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` |
| Snapshot test fails once after deleting a baseline | `record: .missing` auto-recorded | rerun |
