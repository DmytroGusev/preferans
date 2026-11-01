# Preferans Constitution

> Drafted on 2026-11-01 from the code base at `store/1.0.3-localized-keywords` @ `cd78828`, `AGENTS.md`, CI configuration and git history. Every principle below already holds in the code (the evidence is cited). Maintainers should ratify the draft or amend it. Once ratified, this file overrides habits and convenience. Feature specs under [`specs/`](../../specs/README.md) MUST be checked against it.

## Core Principles

### I. One Rules Engine, Everywhere

`Sources/PreferansEngine` is the single implementation of Preferans rules, scoring and bots. Local play, the online engine container and every test lane link the same module. No other component (SwiftUI views, view models, the Cloudflare worker, scripts) may re-implement a rule, legality check or score calculation. They call the engine, or consume its projections.

- The engine has **no third-party dependencies** and must keep building and passing its tests on Linux (`PREFERANS_ENGINE_TESTS_ONLY=1`, CI job `portable-engine`).
- The engine is a value-type reducer. A rejected action throws a `PreferansError` and leaves state untouched.
- *Evidence*: `Package.swift` lanes, `.github/workflows/multiplayer.yml`, `PreferansEngine.apply(_:)`, `workers/room-worker/src/authoritative-engine.ts` (the worker delegates every rule to the Swift container).

### II. Invariants Are Executable

Every state transition is followed by full structural validation (`PreferansEngine+Invariants.swift`). An invariant failure is an engine bug: it traps in-process and throws `InvariantViolation` when state is rehydrated across a trust boundary. A new rule MUST come with the invariants that pin it and with tests that break them on purpose (`InvariantValidatorTests`).

### III. Private Information Never Leaves Its Owner

Hidden cards (hands, talon, discard) are private until the rules reveal them. The authoritative state lives only on the server (Durable Object + engine container). Clients receive per-viewer `PlayerGameProjection`s and redacted events. Snapshots are never sent to clients. Bots get the full state from their host but MUST make decisions only from information their seat may legally know (`DealSampler`, `BotInformationTests`).

- Changes to what a viewer can see MUST update the projection snapshot baselines (`Tests/PreferansEngineTests/__Snapshots__/ProjectionSnapshotTests`) in the same change.
- *Evidence*: `Sources/PreferansEngine/Projection/*`, `ProjectionTests`, `MisereVisibilityTests`, worker message `client_authority_removed`.

### IV. Server Authority and Exactly-Once Commands

Online games are server-authoritative: clients only submit commands and request resyncs. Each command carries an ID bound to its exact payload. The server applies a command at most once, persists state, receipt and checkpoint atomically before fan-out, and serializes all mutations of a table through one queue. Clients write commands ahead to disk and resend the same ID until a receipt arrives.

- Wire changes MUST bump `PreferansWireSchema.current` (currently **4**) when they are not backward compatible. Swift⇄TypeScript compatibility is pinned by fixtures (`workers/room-worker/fixtures/*.json`, `WireCompatibilityTests`).

### V. Determinism and Reproducibility

Randomness is always seeded and injectable (`DealSource`, `SeededDealSource`, `Deck.shuffled(seed:)`). Bot decisions are reproducible for the same position. App tests run on a fixed clock and fixed UUIDs (swift-dependencies). Every interesting scenario can be scripted (`HandRecipe`, `MatchScript`, `MatchScriptFixtures`) and replayed in both the engine and the UI.

### VI. Bounded, Observable Tests

- A test that needs a long timeout is a bug signal: shrink the scenario (one deal, fewer bots, smaller pool) instead of raising limits. UI tests have a 60 s default and 90 s maximum.
- Don't fix test races with sleeps. Bot pacing comes only from `BotPacing` constants (`normal` 1.2 s, `slow` 2.2 s, `interactive` 0.5 s, `testFast` 10 ms, `instant` 0). Do not inline raw durations.
- Loops report progress per phase or deal, and dumps deduplicate.
- *Evidence*: `AGENTS.md`, `bin/lib/xcode-sim.sh`, `Preferans/Support/BotPacing.swift`.

### VII. Evidence Must Match the Source

Screenshots, build products and release evidence are trusted only when they are provably derived from the current sources: `bin/screens-latest` refuses stale captures (exit 2/3), and `bin/test-ui --no-build` refuses stale products. Never reason about UI from images whose provenance is unknown. Every shipped build is recorded (`AppStore/BuildHistory.md`, release evidence JSON, `testflight/…` or `appstore/…` tag).

### VIII. No Secrets, No Unauthorized Side Effects

Signing material, App Store Connect keys, Apple private keys and Cloudflare credentials never enter the repository. Code refers to them only by environment variable (`ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, …). CI holds no deploy credentials. Deploying the backend, uploading builds, changing App Store metadata and submitting for review are separate, explicitly authorized actions. A code change never implies any of them. Tests that touch live services are opt-in (`TEST_RUNNER_PREFERANS_OWNER_SERVER_QA=1`, `PREFERANS_WORKER_URL`) and clean up what they create.

## Technology Constraints

| Area | Constraint |
|---|---|
| Language | Swift 6 (`swift-tools-version: 6.0`, strict concurrency); TypeScript (ES2022) for the Cloudflare worker |
| App | SwiftUI, iOS 17.0 app target (the package declares iOS 16 / macOS 14 for the libraries), iPhone + iPad |
| App dependencies | `swift-dependencies` (clock/UUID injection only), `swift-snapshot-testing` (tests only) |
| Backend | Cloudflare Workers + Durable Objects (SQLite-backed) + Containers running `PreferansServer` (Hummingbird 2) on `swift:6.3.2-jammy` |
| Persistence | Server: Durable Object storage only (no KV/D1/R2). Device: Keychain (session token), UserDefaults (preferences, account record), Application Support (command outbox) |
| Localization | String catalog `Preferans/Resources/Localizable.xcstrings` (en, ru, uk). User-facing text MUST go through the catalog (`LocalizationCatalogTests`) |
| Accessibility contract | Identifiers live in one place, `Sources/PreferansEngine/UIIdentifiers.swift`, shared by the app and UI tests |

## Development Workflow

1. **Branches**: work on `feature/*`, `fix/*`, `ci/*`. Release and store work happens on `release/*` and `store/*`. `main` is the integration branch.
2. **Before pushing**: `bin/test-engine` (portable lane) and the relevant SwiftPM suites (`swift test --filter …`). Run worker checks with `bun run check` in `workers/room-worker` when the worker or wire format changes, and `bin/test-ui` when UI flows change.
3. **Specs**: any change to rules, scoring, the wire protocol, projections or user-visible flows MUST update the matching `specs/NNN-*/` documents in the same change. New capabilities get a new numbered spec folder (spec.md first, then plan/data-model/contracts as needed).
4. **Releases** follow [`specs/006-testing-and-release/quickstart.md`](../../specs/006-testing-and-release/quickstart.md) §12. Build numbers only ever increase.
5. **AI agents** follow `AGENTS.md`: respond in English, follow the screenshot provenance rules, keep test loops tight.

## Governance

- This constitution overrides conflicting conventions. When a spec or the code conflicts with it, either the code is fixed or the constitution is amended. Silent drift is not an option.
- Amendments go through a PR that updates this file, bumps the version (MAJOR: a principle is removed or redefined; MINOR: a principle or section is added; PATCH: wording) and lists the affected specs.
- Reviewers check new work against Principles I–VIII. Any deviation is recorded in that spec's "Known Gaps & Open Questions" with a reason.

**Version**: 1.0.0-draft | **Ratified**: pending maintainer approval | **Last Amended**: 2026-11-01
