# Research: Quality Engineering & Release Decisions (as-built)

Verified against `store/1.0.3-localized-keywords` @ `cd78828`. Each block records a decision visible in code, its rationale (quoted or paraphrased from code comments, docs and commit messages), and the alternatives that were considered or are implied. Rationale marked **(inferred)** is not stated in the repository and is reconstructed from the code.

---

## R-01 One manifest, three SwiftPM lanes selected by environment variables

**Decision**: `Package.swift` reads `PREFERANS_SERVER_ONLY` and `PREFERANS_ENGINE_TESTS_ONLY` via `Context.environment` and emits a different products/dependencies/targets set for the server lane, the portable engine-test lane, and the default lane.

**Rationale**:
- `bin/test-engine` header: portable engine tests "prove seeded rules/invariants without compiling the SwiftUI app or requiring XCTest". The engine lane has zero package dependencies, so it resolves offline and builds under Command Line Tools and on Linux (`swift:6.3.2-jammy` in CI).
- The server lane exists so `Dockerfile.server` builds only `PreferansEngine` + `PreferansServerCore` + Hummingbird for Linux, without the SwiftUI app library or test-only packages. `.dockerignore` further excludes the Xcode project and UI tests.
- `docs/TESTING.md`: "Keep fast, deterministic checks near the engine and reserve simulator runs for behavior that genuinely needs iOS."

**Alternatives considered**:
- Separate packages / nested `Package.swift` per component — more manifests and duplicated target definitions **(inferred)**.
- A single graph everywhere — would force Linux CI to resolve snapshot-testing/dependencies and fail on SwiftUI code.
- Swift package traits — not used; the env-var switch predates/avoids them **(inferred)**.

---

## R-02 Swift Testing for the portable lane, XCTest elsewhere

**Decision**: `Tests/PreferansEngineCLITests` uses Swift Testing (`@Suite`, parameterized `@Test(arguments:)`); engine-core, app and server suites use XCTest; new app-layer suites (`SettlementTests`, snapshot suites) also use Swift Testing.

**Rationale**: `docs/TESTING.md` — "Prefer Swift Testing for portable engine coverage and XCTest/XCUIAutomation for app and UI automation." Parameterization expresses 36 seeded walks as one function with per-case reporting (`CustomTestStringConvertible` labels `sochi-3p`, `sochi4p-talonLed`). `bin/test-engine` injects the Swift Testing macro plugin path when only Command Line Tools are installed.

**Alternatives considered**: XCTest loops over seeds (one failure hides the rest; weaker reporting) **(inferred)**; migrating the 508 existing XCTest functions wholesale — not undertaken.

---

## R-03 Seeded generative walks instead of exhaustive scenario tables

**Decision**: `EngineGenerativeTests` performs random legal-action walks (2 configs × seeds 1–18, ≤180 steps), occasionally proposing settlements (1 in 6), and after every step validates invariants and JSON round-trip equality.

**Rationale**: Comments in the test: "Occasionally offer a settlement so the propose/accept/reject and early-scoring paths get generative coverage alongside card play." Using the in-repo `SeededRandomNumberGenerator` (xoshiro256\*\*) makes each failure reproducible from `seed`/`step`, and identical on Linux and Apple platforms (`DealSource.swift`: "Keeping this in pure Swift lets the exact same engine run on Apple devices, Linux servers, and WebAssembly without depending on Apple-only GameplayKit").

**Alternatives considered**: Unseeded fuzzing (non-reproducible); a property-testing library (extra dependency in the dependency-free lane) **(inferred)**.

---

## R-04 Structural text snapshots, not pixel snapshots

**Decision**: `ProjectionSnapshotTests` snapshot the JSON of `PlayerGameProjection`; `TableScreenSnapshotTests` snapshot a line-based "screen contract" (viewer, clockwise seats, auction order, talon visibility, trick offsets). Both use `.lines` and `.snapshots(record: .missing)`; files are named per viewer.

**Rationale**: Commit `19cbcfc`: baselines catch "regressions to projection visibility, legal-action gating, role badges, and talon/discard reveal — the privacy boundaries that the existing predicate-based ProjectionTests only spot-check"; "Suite trait pins recording to .missing so first runs auto-record and subsequent runs assert"; "Pixel-level SwiftUI snapshots remain a follow-up — the swift-snapshot-testing image strategy is iOS-only, and wiring the SPM test target into the Xcode iOS scheme proved too brittle." The test header adds: "the projection is the source of truth for what those views render, so locking it down here is the higher-leverage win." A normalizer sorts `[PlayerID: Int]` alternating arrays because Codable output order "tracks Dictionary iteration — non-deterministic per run."

**Alternatives considered**: Image snapshots on an iOS simulator (rejected as brittle); predicate-only assertions (insufficient coverage).

**Consequence**: Re-recording = delete the baseline and rerun (first run records and fails, second passes), or temporarily change the trait to `record: .all`. The `SNAPSHOT_TESTING_RECORD` environment variable is expected to be overridden by the trait **(inferred from library behaviour; not executed)**.

---

## R-05 One shared contract for identifiers, flags and parsed strings — inside the engine module

**Decision**: `UIIdentifiers`, `UITestFlags` and `AccessibilityStrings` live in `Sources/PreferansEngine/UIIdentifiers.swift`; the app and the UI-test bundle both import `PreferansEngine` (the UI-test target links the local package product).

**Rationale**: File header — "Lives in `PreferansEngine` so the app target and any test harness can share the exact same encoders — a UI test never spells an identifier as a string literal." `UITestFlags` — "Single source of truth so the producer (UI tests) and the consumer (running app) can't drift on a flag string." ASCII-only encodings avoid Unicode normalization issues in XCUI queries. Commit `6932cc8` wired `PreferansEngine` into the UI-test target for this purpose.

**Alternatives considered**: A separate shared test-support module for the app and UI tests **(inferred)** — would still need to be linked by the app to set identifiers; string literals in tests (drift-prone).

**Trade-off**: test-only types ship in the production binary; mitigated by runtime gating (R-11).

---

## R-06 Robot / driver / oracle UI-test architecture

**Decision**: `MatchUIRobot` is the only UI-test code that knows identifier strings and exposes the app "in terms of engine values" (one method per `PreferansAction`, one read per engine query). `MatchUIDriver` replays a `MatchScript` via `MatchScriptStepper` hooks, tapping through the robot **and** applying the same action to an internal engine, then cross-checks the game-over panel against the engine's `MatchSummary`.

**Rationale**: `MatchUIDriver.swift` — the oracle provides `legalCards(for:)` for play strategies ("Re-deriving this from the UI alone would mean parsing the visible 'playable' highlights — slower and more fragile") and catches divergences "immediately, with a useful error message. Without the oracle the test would hit the *next* unrelated failure several actions later." Robot: "Robot calls are synchronous and synchronise on the next expected UI element so the caller never needs `sleep` or polling." Device-specific navigation (iPhone lazy choice rail swipes, card-fan sliver taps, score sheet sheet on compact layouts, scroll-into-view above the pinned start bar) is contained in the robot.

**Alternatives considered**: Recorded/coordinate-based UI scripts (ruled out by `docs/TESTING.md`: "Avoid coordinate taps"); page objects per screen without an engine oracle **(inferred)**.

---

## R-07 Recipes and match scripts instead of literal decks

**Decision**: Decks are generated from named outcomes (`HandRecipe`) against the active rotation the engine will compute; whole pulkas are `MatchScript` values (`game1ClassicSochi`, `game2LongSochi`, `game3RostovDedicatedTotus`) consumed by `EngineMatchDriver`, the UI driver, `TestHarness` and `bin/sim`. Single-deal UI scenarios use three named `DealScenario` decks: `sortedDeck` (`Deck.standard32`) and two hand-built via `DealDeckLayout` (`northBidsSpadesSix`, `northBidsMisere`).

**Rationale**: `MatchScript.swift` — "the same script value is intended to drive `MatchUIDriver` against the SwiftUI surface so the UI test never re-derives the auction or play sequence." Fixtures are designed so the pool target fires on the last deal, every contract type appears, at least two deals fail, and dealer rotation is natural; trajectories are documented inline. `EngineMatchDriverTests`: "the cheapest way to catch a broken script (10ms vs ~60s in the simulator)." Commit `4d00322` records a real bug class this caught: sorting by `Card`'s suit-then-rank comparator silently turned a "fail by 2" recipe into a winning hand; recipes and greedy play now compare by rank.

**Alternatives considered**: Seeded random decks for UI tests (outcome not controllable); literal 32-card arrays per deal (unreadable, brittle to packet layout changes).

---

## R-08 One warm simulator, build once, strict time allowances

**Decision**: `bin/test-ui` and `bin/screens` use `build-for-testing` + `test-without-building` on a single named simulator with parallel testing disabled, `-default-test-execution-time-allowance 60`, `-maximum-test-execution-time-allowance 90`, and system diagnostics collection off by default.

**Rationale**: `bin/test-ui` — "cloning the destination sim costs one cold boot per worker (10–30s each) and is flaky … For a ~10-test suite the parallelism gains don't beat the boot overhead." `docs/TESTING.md` — "shrink or fix a slow scenario instead of increasing those limits"; diagnostics "can outlast the test by minutes" (`PREFERANS_TEST_DIAGNOSTICS=on-failure` to opt in). `AGENTS.md` — "A 10-minute test timeout is a smell, not a workaround." Different default simulators (`iPhone 17 Pro` for tests, `iPhone 17` for `bin/sim`) avoid fighting an interactive session.

**Alternatives considered**: Parallel clones (rejected above); `xcodebuild test` each time (slower iteration); raising timeouts (explicitly rejected).

---

## R-09 Content-hash provenance for build products and screenshots

**Decision**: `bin/lib/screen-provenance.py` hashes every input that can change rendered pixels (app sources/resources, engine sources, UI tests, project/scheme files, `Package.swift`, `Package.resolved`). The digest is stamped before `build-for-testing`, re-checked after, checked before every `test-without-building`, copied into each screenshot run and re-checked by `bin/screens-latest` (exit 2 = none, 3 = stale/legacy).

**Rationale**: `AGENTS.md` — "Pixels that predate the `.swift` files they depict are worse than no pixels: they look authoritative and quietly mislead." `bin/screens-latest` — "Exporting an old xcresult gives its PNGs a fresh modification time; that cannot establish which source produced the pixels. Legacy runs fail closed." `xcode-sim.sh` — "Record exact inputs so reusable products cannot silently predate the source." `docs/TESTING.md` — "new PNG modification times cannot make an old build pass the freshness check." The Python suite proves mtime-preserving content edits invalidate and timestamp-only changes do not. Introduced in `eb44c89` ("bind simulator captures to source and bound test runs"); `AppStore/render-media.mjs` reuses it for store media.

**Alternatives considered**: mtime comparison (the earlier rule still described in `AGENTS.md`; defeated by xcresult export); git commit SHA (ignores uncommitted edits); trusting DerivedData incremental builds.

---

## R-10 Non-zero test bot pacing

**Decision**: `BotPacing.testFast = 10 ms`, applied only with `-uiTestFastBotDelay`; production uses the lobby picker (`normal` 1200 ms default, `slow` 2200 ms, `instant` 0) or the 500 ms `interactive` default; `bin/sim` never sets the flag.

**Rationale**: `BotPacing.swift` — a literal `.zero` "collapses multi-action bot stretches into a single SwiftUI tick and the user-visible UI never updates between them"; the action banner and auction trail "need at least one tick to land before the next event re-keys them." `UIIdentifiers.swift` — 10 ms keeps "match-driver runs under the 30-second budget." `AGENTS.md` forbids inlining raw durations.

**Alternatives considered**: zero delay (rejected above); disabling animations only (does not bound bot time — hence two separate flags, `-uiTestDisableAnimations` and `-uiTestFastBotDelay`).

---

## R-11 Automation affordances gated at runtime

**Decision**: `TestHarness.isUIAutomation` is true only when a `-uiTest…` argument is present; it gates invisible automation affordances, onboarding bypass and the loopback worker override (`PREFERANS_ROOM_WORKER_URL` limited to `http://localhost|127.0.0.1` root URLs without credentials). `-uiTestTheme` and `-uiTestPreviewSettlement` compile only under `#if DEBUG`.

**Rationale**: `TestHarness.swift` — "in a shipping build they were still in the accessibility tree, and a VoiceOver user could land on an unlabeled 1×1 button that started a real table or online room"; loopback override: "Reject all remote hosts, credentials, and non-root URLs; shipping builds never consult it." Onboarding: "First-run routing must not depend on whatever UserDefaults happen to remain on a reused simulator." Language pins avoid "terminating and relaunching inside the same XCUITest (a pattern that can wedge iPad runners)."

**Alternatives considered**: Compile-time-only (`#if DEBUG`) gating for everything — UI tests do run Debug builds, but `TestHarness` (app target) and `UITestFlags` (engine module) compile into Release too, and the multi-simulator invite flow launches the app with harness flags; only the theme/preview flags were made DEBUG-only **(inferred)**.

---

## R-12 Live-network tests are opt-in and self-cleaning

**Decision**: `OnlineWorkerIntegrationTests` skip without `PREFERANS_WORKER_URL`; `NativeOnlineUITests` skip unless the loopback worker reports `service == "preferans-room-worker"`; `OwnerOnlineUITests` skip unless `TEST_RUNNER_PREFERANS_OWNER_SERVER_QA=1`; all delete created QA accounts. Routine runs use the loopback stack from `bin/dev-online`; multi-device checks use structured `ONLINE_FLOW` log lines.

**Rationale**: `docs/TESTING.md` — "Keep live-network validation small and bounded … without playing a full match"; prefer "structured test probes" to screenshots. `docs/OWNER_MULTIPLAYER_BUILD29.md` — "Live UI tests are opt-in … Without this flag they skip before contacting the server. Keep routine CI on loopback." `NativeOnlineUITests.setUp` throws rather than failing so async tests "unwind and clean up immediately".

**Alternatives considered**: Running live tests by default (network flakiness, production data pollution); screenshot-based multi-sim verification (rejected: "without coordinates or screenshots").

---

## R-13 Linux-only, credential-free CI

**Decision**: CI runs worker contracts and the portable engine lane on every push/PR; the server image workflow is build-only (dry-run Wrangler, local smoke test, artifact with checksums, `contents: read`). There is no macOS runner.

**Rationale**: `docs/SERVER_CI.md` — "No Cloudflare credentials are needed or should be added for this build-only job"; the artifact's "SHA identifies exactly which code the image contains"; "A future deployment must use the verified image or rebuild the exact reviewed commit." The absence of macOS jobs is **(inferred)** to be cost/complexity-driven; simulator suites are run locally with the scripts above and their results recorded in release notes.

**Alternatives considered**: macOS runners for `swift test`/UI tests (not adopted); automatic deploys from `main` (explicitly excluded).

---

## R-14 Release via `xcodebuild` + guarded ASC API scripts with JSON evidence

**Decision**: Builds are archived/exported with `xcodebuild` and `AppStore/ExportOptions-AppStore.plist`; store metadata, media, creatives, PPO experiments and keywords are managed by small Node ES-module scripts calling the ASC REST API with a short-lived ES256 JWT. Every mutating script refuses non-draft versions, backs up the before-state once, writes per-item progress (resumable), and a verification script re-reads the server state into evidence JSON.

**Rationale**: `AppStore/Release-1.0.2.md` — "Actual App Store Connect IDs, before-state backups and upload results are in `ReleaseEvidence/`; no API private keys are stored in the repository." `Keywords-1.0.3/README.md` — the sync "checks the draft state, build selection and concurrent keyword edits before applying; backs up progress; verifies readback; and does not attempt to undo other changes." `asc.mjs` restricts calls to `/v1/` and `/v2/` paths. Keyword selection is "editorial localization, not search-volume research."

**Alternatives considered**: fastlane `deliver` (the April 2026 approach still in `fastlane/Fastfile`; no draft guard, en-US only, overwrites screenshots); manual ASC web edits (no evidence trail).

---

## R-15 Monotonic build numbers, tags per build, written build history

**Decision**: `CURRENT_PROJECT_VERSION` increases by one per uploaded build across all marketing versions (now 29); `MARKETING_VERSION` advances when ASC closes a train or for a feature release; each build is documented (`BuildHistory.md`, `Release-*.md`, `Release29/`) and tagged (`testflight/…`, `appstore/…`, earlier `rollback/…` aliases).

**Rationale**: `BuildHistory.md` — "records App Store/TestFlight build provenance and review-facing changes"; 1.0.1 was created "because App Store Connect closed the `1.0` upload train"; the build-19 rejection was traced to a launch crash and fixed in build 20 with documented verification. Build 29 records 142 source hashes so the archive can be matched to source after the fact.

**Alternatives considered**: Resetting build numbers per marketing version (Apple allows it; not used, **inferred** for unambiguous build references); relying on `manageAppVersionAndBuildNumber` only (the export option is enabled but the repo bumps explicitly — see spec open question).

---

## R-16 Legal pages as Markdown on GitHub Pages; app links moved to the owner domain

**Decision**: `docs/` holds `index.md`, `support.md`, `privacy-policy.md`, `terms-of-use.md` with `_config.yml` (`theme: minima`) for GitHub Pages; store metadata uses those URLs. Build 29's Settings screen links to `guruofcards.com/apps/preferans/{privacy,terms}/`.

**Rationale**: `README.md` — "intended to be published through GitHub Pages for App Store Connect URLs." `docs/OWNER_MULTIPLAYER_BUILD29.md` — "Legal links in Settings use the verified Guru of Cards Preferans pages."

**Policy summary** (from `docs/privacy-policy.md`, `docs/terms-of-use.md`, `AppStore/PrivacyChecklist.md`): online play processes a server-issued guest ID or Sign in with Apple user ID, display name, room/game data and timestamps; Apple identity tokens are verified server-side with a nonce and not used as ongoing credentials; account session in Keychain, limited profile in local storage; no sale of data, no advertisers or data brokers; ATT is requested before any future tracking; in-app **Delete online account** removes server profile, sessions, game library, room credentials and identity, while shared results keep an anonymized seat and score; not intended for children under 13; no real-money gambling.

**Alternatives considered**: Hosting on the worker domain or a marketing site — adopted later for in-app links, leaving two copies (see spec Known Gaps).

---

## R-17 Deterministic app-layer dependencies

**Decision**: `AppTestCase` wraps every test with `ImmediateClock()` and `.incrementing` UUIDs (swift-dependencies); timing-sensitive runners (`RoomDurabilityRetryRunner`, `RoomHostRecoveryRunner`) inject a `sleep` closure that tests record.

**Rationale**: `AppTestCase.swift` — the default `testValue` for `\.continuousClock` is `unimplemented`, "so unmodified tests would fail the moment a bot task or idle-hint timer schedules a sleep"; tests that need time semantics override with `TestClock()`.

**Alternatives considered**: Real `Task.sleep` with small durations (slow, flaky).

---

## R-18 Conventions written for AI agents

**Decision**: `AGENTS.md` is the only contributor-facing rules file (no `CONTRIBUTING.md`, `CODEOWNERS`, PR template or lint config). It mandates English responses, the screenshot freshness protocol, bounded loops, per-phase progress output, deduplicated screenshot dumps and `BotPacing` constants. `AppStore/BuildHistory.md` records that much release work was performed by an AI agent (Codex) at the owner's request.

**Rationale**: The repository is maintained with heavy AI-agent involvement; the rules target failure modes those agents exhibited (reading stale PNGs, inflating timeouts, `usleep` padding) **(inferred from the wording of `AGENTS.md`)**.

**Alternatives considered**: Human-oriented contributor guide — not present.
