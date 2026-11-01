# Feature Specification: Preferans — System Overview

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Version**: 1.0.3 (build 29) · **Bundle ID**: `com.mixandmatch.preferans`

Companion documents: [plan.md](plan.md) (architecture), [quickstart.md](quickstart.md) (run it), [glossary.md](glossary.md) (terms). Detailed specs: [001 rules](../001-game-rules/spec.md) · [002 scoring](../002-scoring-and-variants/spec.md) · [003 bots](../003-bots/spec.md) · [004 online](../004-online-multiplayer/spec.md) · [005 app](../005-ios-app/spec.md) · [006 testing & release](../006-testing-and-release/spec.md).

## Summary

Preferans is a native SwiftUI app for iPhone and iPad. It plays **Preferans**, the classic Eastern-European trick-taking card game for three active players with a 32-card deck, an auction, a two-card talon (prikup), whisting defenders, misère, all-pass (raspasy) deals and a running score sheet (pool, mountain and whists).

The app offers two ways to play:

1. **Local tables** against computer opponents, with 3 or 4 seats. At 4 seats the dealer sits out each deal. The human can also watch an all-bot table ("Watch bots"). Local games run entirely on the device.
2. **Online tables** with friends (private rooms joined by invite link or room code) or with strangers (public tables with fixed rule presets and a ready check). Empty seats can be filled by server-side bots. Online play is **server-authoritative**. A Cloudflare Durable Object owns each table and a stateless Swift engine container computes every move. Each device only ever receives its own player's view.

All rules, scoring and bot logic live in one dependency-free Swift module, `PreferansEngine`, which is shared by the app, the server and every test lane.

## Who uses it

| Actor | Goal |
|---|---|
| **Player (offline)** | Learn or practise Preferans against bots with a chosen rule set, pool size and bot speed |
| **Player (online host)** | Create a private table, invite friends, fill empty seats with bots, start deals |
| **Player (online guest)** | Join from an invite link or code, or pick a public table from the lobby, and play from their own device |
| **Spectator** | Watch an all-bot table, including a read-only view of each bot's hand |
| **Contributor** | Change rules, UI or backend safely, guided by the specs, tests and invariants |
| **Release manager** | Build, verify and ship to TestFlight and the App Store, and keep store metadata in 24 locales |

## User Scenarios & Testing

### User Story 1 – Play a local match against bots (Priority: P1)

A player opens the app, picks a rule variant, the pool target and bot speed, and plays a full match against two or three bots until the pool closes, then sees the final balances.

**Why this priority**: This is the core experience and works without any account or network.

**Independent Test**: `PreferansUITests/FullGameUITests` (scripted canonical matches `game1`–`game3`) and `MatchUITests`. The engine part alone: `swift test --filter EngineMatchDriverTests`.

**Acceptance Scenarios**:
1. **Given** a fresh install, **When** the player finishes onboarding and taps play on a 3-seat local table, **Then** cards are dealt (10 each, 2 in the talon) and the auction starts with the forehand.
2. **Given** a deal in progress, **When** the player makes an illegal move, **Then** the UI does not offer it, and the engine would reject it without changing state ([001](../001-game-rules/spec.md)).
3. **Given** a deal finishes, **When** it is scored, **Then** the score sheet updates (pool, mountain, whists) according to the chosen variant ([002](../002-scoring-and-variants/spec.md)).
4. **Given** the pool target is reached, **When** the last deal settles, **Then** the game-over card shows each player's final balance, and the balances sum to zero.

### User Story 2 – Play online with friends (Priority: P1)

A host creates a private table (3 or 4 seats, rules, pool), shares an invite link, friends join from their own devices, empty seats can become bots, and the host starts deals.

**Why this priority**: Social play is the main reason to install on more than one device.

**Independent Test**: Worker runtime tests (`workers/room-worker/runtime-test/room.test.ts`), `OnlineWorkerIntegrationTests` against `bin/dev-online`, and `NativeOnlineUITests`.

**Acceptance Scenarios**:
1. **Given** a signed-in player (guest or Sign in with Apple), **When** they create a table, **Then** the server returns a room code and a per-seat token, and the waiting room shows the invite link.
2. **Given** a guest opens the invite, **When** they join, **Then** they are seated and every connected device receives an updated projection over its WebSocket.
3. **Given** a move is submitted, **When** the network drops before the receipt arrives, **Then** the app resends the same command ID until it gets a receipt, and the server applies it exactly once ([004](../004-online-multiplayer/spec.md)).
4. **Given** a game in progress, **When** a viewer receives a projection, **Then** it contains only that viewer's hand and the publicly revealed cards.

### User Story 3 – Join a public table (Priority: P2)

A player browses public tables in the lobby, joins one, confirms Ready, and the game starts once every human seat is ready.

**Why this priority**: It extends online play to people without friends online. It is newer and has had less real-device QA.

**Independent Test**: `workers/room-worker/runtime-test/public-lobby.test.ts`, `PublicTableLobbyTests`, `bun scripts/public-lobby-network.ts`.

**Acceptance Scenarios**:
1. **Given** a public table, **When** it is listed, **Then** it uses one of the fixed presets (Vienna, Prague or Berlin), and other players' account IDs are masked.
2. **Given** a listing is not refreshed by its table, **When** 90 s pass, **Then** it disappears from the directory.

### User Story 4 – Learn the conventions (Priority: P2)

A newcomer reads onboarding, sees the convention legend and the pool ("pulka") diagram, and follows the deal through banners, an activity log and deal summaries.

**Independent Test**: `OnboardingLocalizationUITests`, `DealSummaryPresentationTests`, `ActivityLogFeedTests`.

### User Story 5 – Ship a build (Priority: P3)

A release manager bumps the build number, runs all test lanes, archives and uploads a build, updates localized store metadata, and records evidence and a git tag.

**Independent Test**: [006 quickstart §12](../006-testing-and-release/quickstart.md).

### Edge Cases

- **All-pass deals** (everyone passes): they are played to take as few tricks as possible, the talon cards set the suit of the first two tricks, and consecutive all-pass deals raise the price and minimum contract ([001](../001-game-rules/spec.md), [002](../002-scoring-and-variants/spec.md)).
- **4-seat tables**: the dealer sits out, but in all-pass deals the sitting-out dealer can win talon-led tricks.
- **Claims (settlement)**: only a side playing with its cards exposed can propose a claim, and everyone involved must accept.
- **Online disconnects**: commands survive app restarts (write-ahead outbox). A seat re-joined on another device closes the old socket (close code 4009).
- **Lobby manager leaves**: the server elects the first connected human in seat order as the new manager.
- **Engine invariant violation**: the process traps (local), or rehydration throws `InvariantViolation` (server).

## Requirements

### Functional Requirements (system level; details in the linked specs)

- **FR-001**: The system MUST implement the full Preferans deal cycle (deal, auction, talon exchange, contract, whist decisions, trick play, settlement) for 3 active seats, with an optional 4th sitting-out dealer. → [001](../001-game-rules/spec.md)
- **FR-002**: The system MUST score deals onto a pool / mountain / whists sheet under four rule sets (Sochi, Leningrad, Rostov, Stalingrad), close the pool at a configurable target, and produce zero-sum final balances. → [002](../002-scoring-and-variants/spec.md)
- **FR-003**: The system MUST provide computer opponents that decide only from information legally visible to their seat, at several difficulty levels, reproducibly. → [003](../003-bots/spec.md)
- **FR-004**: The system MUST offer online private and public tables in which the server alone holds hidden information and applies every command exactly once. → [004](../004-online-multiplayer/spec.md)
- **FR-005**: The system MUST support anonymous guest accounts and Sign in with Apple, keep the session token in the Keychain, and allow account deletion. → [004](../004-online-multiplayer/spec.md)
- **FR-006**: The app MUST render local and online games through one projection-driven table screen, with six themes and English, Russian and Ukrainian UI. → [005](../005-ios-app/spec.md)
- **FR-007**: The repository MUST keep the engine buildable and testable on Linux without third-party dependencies, and run worker and engine checks in CI on every push and PR. → [006](../006-testing-and-release/spec.md)
- **FR-008**: Store metadata MUST be maintained for 24 App Store locales. Legal pages (support, privacy, terms) MUST be publicly hosted. → [006](../006-testing-and-release/spec.md)

### Key Entities

| Entity | Meaning | Defined in |
|---|---|---|
| `PreferansEngine` | Value-type reducer for one match: players, settings, current `DealState`, score, history | [001 data-model](../001-game-rules/data-model.md) |
| `PreferansAction` / `PreferansEvent` | Every input to the engine, and the facts it emits | [001 data-model](../001-game-rules/data-model.md) |
| `MatchSettings` / `PreferansRules` | Seat count, pool target, rule set and options | [001](../001-game-rules/data-model.md), [002](../002-scoring-and-variants/data-model.md) |
| `ScoreSheet` | Per-player pool, mountain and whists written against each opponent | [002 data-model](../002-scoring-and-variants/data-model.md) |
| `PlayerStrategy` / `BotProfile` | Bot decision interface and difficulty and temperament parameters | [003 plan](../003-bots/plan.md) |
| `PlayerGameProjection` | Viewer-safe view of a game (own hand, public cards, legal actions) | [004 data-model](../004-online-multiplayer/data-model.md) |
| Room / Seat / CommandReceipt | Server-side table, seat tokens, exactly-once receipts | [004 data-model](../004-online-multiplayer/data-model.md) |
| Account / Session / Library entry | Identity and "Your games" | [004 contracts/persistence](../004-online-multiplayer/contracts/persistence.md) |
| `LobbyViewModel` / `GameViewModel` | App navigation state and local match driver | [005 data-model](../005-ios-app/data-model.md) |

## Success Criteria

### Measurable Outcomes

- **SC-001**: The portable engine lane (`bin/test-engine`, 47 cases) passes on macOS and on Linux (`swift:6.3.2-jammy`).
- **SC-002**: The full SwiftPM graph (`swift test`, about 579 cases) passes. Live-backend cases skip without `PREFERANS_WORKER_URL`.
- **SC-003**: A full 4-player all-bot match to pool 6 finishes in well under a minute with animations and bot delay disabled (`AGENTS.md`).
- **SC-004**: Every UI test finishes within its 60 s default allowance (90 s maximum).
- **SC-005**: Worker checks (`bun run check`: typecheck, 52 unit tests, 14 runtime tests) pass in CI on every push.
- **SC-006**: No projection sent to a client contains another seat's hidden cards (projection snapshot baselines unchanged unless the change is intended).

## Known Gaps & Open Questions (consolidated)

The full lists live in each spec. These are the items that matter at system level:

| # | Area | Item | Details |
|---|---|---|---|
| 1 | Docs | README names for variants (Одеса/Wien/Θεσσαλονίκη/Крути → Sochi/Leningrad/Rostov/classic) are stale. The app shows **Vienna = Sochi, Prague = Leningrad, Berlin = Rostov, Kruty = Stalingrad**, stored as `odesa`, `wien`, `thessaloniki`, `kruty` | [glossary](glossary.md#rule-variants) |
| 2 | Platform | `Package.swift` declares iOS 16, while the Xcode app target is iOS 17.0 and uses iOS 17 APIs | [005](../005-ios-app/spec.md) |
| 3 | Rules | Local and invite-only tables apply the lobby's raspasy pickers instead of each variant's own progression, so Berlin's flat all-pass price is not kept | [002](../002-scoring-and-variants/spec.md), [005](../005-ios-app/spec.md) |
| 4 | Online | Match results (winner, balances) are never filled in, so "Your games" shows no winner | [004](../004-online-multiplayer/spec.md) |
| 5 | Online | In private rooms, account IDs are visible to anyone with the room code via an unauthenticated summary endpoint | [004](../004-online-multiplayer/spec.md) |
| 6 | Online | Nothing is pruned: rooms, receipts and checkpoints (with full private state) are kept forever | [004](../004-online-multiplayer/contracts/persistence.md) |
| 7 | Online | The iOS client keeps reconnecting after close codes 4010 (account deleted) and 4011 (seat left) | [004](../004-online-multiplayer/spec.md) |
| 8 | Online | Associated domain `preferans.game` is declared but the invite parser rejects it, and the worker, entitlements and `AppStore/UniversalLinks` notes list different domains | [004 invite-links](../004-online-multiplayer/contracts/invite-links.md) |
| 9 | Bots | Online bots always use the Seasoned/Adaptive profile and ignore the lobby's difficulty | [003](../003-bots/spec.md) |
| 10 | App | Game Center and the App Tracking Transparency prompt are wired up but unused. The privacy policy says no advertising identifiers are collected | [005](../005-ios-app/spec.md), [006](../006-testing-and-release/spec.md) |
| 11 | Legal | Store metadata links to GitHub Pages, while the in-app Settings link to guruofcards.com | [006](../006-testing-and-release/spec.md) |
| 12 | CI | No macOS CI: app, UI and snapshot tests, and the server-core tests, are never run automatically | [006](../006-testing-and-release/spec.md) |
| 13 | Release | `fastlane/Fastfile` is stale and would overwrite live metadata and screenshots. `AppStore/Localizations/*.json` still carries 1.0.2 keywords | [006 quickstart §12](../006-testing-and-release/quickstart.md) |
| 14 | Security | `fastlane/Fastfile` and `AppStore/asc.mjs` hard-code fallback App Store Connect key and issuer IDs and a personal key path. The private key is not in the repo, but these fallbacks should be removed (this repository is public) | [006](../006-testing-and-release/spec.md) |
| 15 | Rules | `[NEEDS CLARIFICATION]` In a talon-led all-pass trick where nobody can follow the talon suit, the winner falls out of the card comparator. No test pins this | [001](../001-game-rules/spec.md) |
