# Quickstart: Preferans in 15 Minutes

The short path from `git clone` to a running app. Each step links to the detailed quickstart for its area. The commands come from the repository's scripts at `cd78828`.

## 1. Prerequisites

- macOS with **full Xcode** selected (`sudo xcode-select -s /Applications/Xcode.app`). The project was last archived with Xcode 27.1. Scripts exit 69 if only the Command Line Tools are active.
- An iOS Simulator runtime with **iPhone 17 Pro** / **iPhone 17**, or override with `DEST_NAME=…`.
- Online work only: **Docker**, **Bun** (Node 24 in CI).

Full table: [006 quickstart §0](../006-testing-and-release/quickstart.md#0-prerequisites).

## 2. Clone and get the first green check (about 1 minute)

```sh
git clone https://github.com/DmytroGusev/preferans.git
cd preferans
bin/test-engine            # portable engine lane: 47 cases, no Xcode required
git restore Package.resolved   # the engine lane deletes the committed pins file (see 006 quickstart §2)
```

## 3. Run the whole Swift test graph

```sh
swift test                 # ≈579 cases; 3 live-backend cases skip without PREFERANS_WORKER_URL
```

Single suites (`--filter EngineMatchDriverTests`, `ProjectionSnapshotTests`, …): [006 quickstart §4](../006-testing-and-release/quickstart.md#4-full-swiftpm-graph-full-xcode).

## 4. Run the app

```sh
open Preferans.xcodeproj   # scheme "Preferans" → Run on an iPhone simulator
# or, from the terminal, into a known state:
bin/sim                    # lobby with random deals
bin/sim game1              # replay a canonical scripted match
```

The first launch shows onboarding and the tracking prompt, and the UI starts in Ukrainian; change the language in Settings and restart. Any `-uiTest…` launch flag (which `bin/sim` adds) skips onboarding. App internals: [005 quickstart](../005-ios-app/quickstart.md).

## 5. UI tests

```sh
bin/test-ui                                                            # all UI tests except screenshot capture
bin/test-ui -only-testing:PreferansUITests/FullGameUITests/testGame1_ClassicSochi
```

Each UI test should finish in under 60 s. If it doesn't, shrink the scenario; don't raise the timeout (`AGENTS.md`).

## 6. Online play on your machine

```sh
bin/dev-online             # terminal 1: engine container on :18081, worker on :8787
bin/test-ui -only-testing:PreferansUITests/NativeOnlineUITests          # terminal 2
PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests
(cd workers/room-worker && bun install --frozen-lockfile && bun run check)
```

Full backend guide, env vars and deployment notes: [004 quickstart](../004-online-multiplayer/quickstart.md).

## 7. Before you open a PR

- [ ] `bin/test-engine` is green. CI runs the same lane on Linux.
- [ ] `swift test --filter` on the suites you touched is green. Snapshot baselines changed only on purpose ([006 §11](../006-testing-and-release/quickstart.md#11-update-snapshot-baselines-intentionally)).
- [ ] If the worker or wire format changed, `bun run check` passes in `workers/room-worker`.
- [ ] The matching `specs/NNN-*/` documents are updated ([constitution](../../.specify/memory/constitution.md), Development Workflow §3).
- [ ] No secrets, signing material or personal paths were added.

## 8. Where to go next

| I want to… | Read |
|---|---|
| understand a rule or why a move is illegal | [001 spec](../001-game-rules/spec.md) and its appendices |
| check a score calculation | [002 spec](../002-scoring-and-variants/spec.md) (21 worked examples) |
| tune a bot | [003 plan](../003-bots/plan.md) |
| add an endpoint or message | [004 contracts](../004-online-multiplayer/contracts/) |
| change a screen | [005 spec](../005-ios-app/spec.md) (screen inventory, navigation map) |
| ship a build | [006 quickstart §12](../006-testing-and-release/quickstart.md#12-release-build-authorized-release-managers-only) |
