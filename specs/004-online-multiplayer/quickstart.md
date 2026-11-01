# Quickstart: Online Multiplayer Backend and Tests

**Spec**: [spec.md](spec.md) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828`

All commands are taken from the repository (`bin/dev-online`, `workers/room-worker/package.json`, `.github/workflows/*.yml`, `docs/*.md`, worker README). They were documented, not executed, while writing this spec.

## 0. Prerequisites

| Tool | Used for |
| --- | --- |
| Docker | building/running the Linux engine image (`Dockerfile.server`, base `swift:6.3.2-jammy`) |
| Bun (`oven-sh/setup-bun@v2` in CI) and Node 24 | Worker deps, Wrangler, `node --test`, network scripts |
| Swift 6 toolchain / Xcode | Swift packages, server-core and app tests, iOS app |
| An iOS Simulator | native online UI tests |

## 1. Run the backend locally

From the repository root:

```sh
bin/dev-online
```

What it does:

1. `docker build -f Dockerfile.server -t preferans-engine:local .` (inside: `PREFERANS_SERVER_ONLY=1 swift build -c release --product PreferansServer`).
2. `docker run --rm -d --name preferans-development-<pid> -p 127.0.0.1:18081:8080 preferans-engine:local`.
3. Polls `http://127.0.0.1:18081/health` up to 30 × 1 s.
4. `cd workers/room-worker && bun install --frozen-lockfile && bun run wrangler dev --config wrangler.local.toml --local --port 8787`.

Stop with Ctrl-C (the trap stops the engine container). Local Durable Object data persists in `workers/room-worker/.wrangler` (gitignored). The local config (`wrangler.local.toml`, entry `src/local.ts`) binds `ROOMS` to `LocalPreferansTable`, which calls the engine at `http://127.0.0.1:18081`; it has no `ENGINE` container binding, no rate limiter and no `APPLE_CLIENT_ID` (defaults to `com.mixandmatch.preferans`).

Sanity checks:

```sh
curl -s http://127.0.0.1:18081/health   # {"ok":true,"service":"preferans-authoritative-engine","stateSchemaVersion":2}
curl -s http://127.0.0.1:8787/health    # {"ok":true,"service":"preferans-room-worker","accountSchemaVersion":2,"roomSchemaVersion":4}
curl -s -X POST http://127.0.0.1:8787/v2/accounts/guest \
     -H 'content-type: application/json' -d '{"displayName":"Local QA"}'   # 201 {account, sessionToken}
```

Run only the engine server without Docker:

```sh
PREFERANS_SERVER_ONLY=1 swift build --product PreferansServer
PORT=18081 .build/debug/PreferansServer
```

## 2. Worker tests

```sh
cd workers/room-worker
bun install --frozen-lockfile
bun run check          # = typecheck (tsc ×2) + test (node --test test/*.test.ts, 52 tests) + test:runtime (vitest, 14 workerd tests)
```

Individual steps: `bun run typecheck`, `bun run test`, `bun run test:runtime`. The runtime tests use `vitest.config.ts` with `@cloudflare/vitest-plugin` (real SQLite-backed `ROOMS`, `ACCOUNTS`, `LOBBY` Durable Objects; engine calls are stubbed per test; 10 s test timeout).

## 3. Swift server-core and client tests

```sh
# Server core (default package graph includes PreferansServerCoreTests)
swift test --filter AuthoritativeGameServiceTests
swift test --filter PublicTableRulesTests

# Online client logic, projections and wire format (PreferansAppTests target, path Tests/PreferansEngineTests)
swift test --filter ServerAuthoritativeCoordinatorTests
swift test --filter OnlineTransportSecurityTests
swift test --filter WireCompatibilityTests
swift test --filter ProjectionTests
swift test --filter PreferansInviteLinkTests
swift test --filter PublicTableLobbyTests
swift test --filter OnlineGameLibraryTests

# Legacy peer-host path (in-memory room)
swift test --filter RoomOnlineGameCoordinatorTests
swift test --filter OnlineBotSeatTests
swift test --filter EventSourcingTests

# Portable engine lane used by CI (does NOT include server-core tests)
PREFERANS_ENGINE_TESTS_ONLY=1 swift test
```

Regenerate the Swift⇄Worker create fixture (only when intentionally changing the wire format):

```sh
PREFERANS_UPDATE_WIRE_FIXTURE=1 swift test --filter testCheckedInWireFixtureMatchesSwiftCodec
```

Live Swift-to-Worker contract tests (skipped unless the variable is set; note the variable name differs from the scripts):

```sh
PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests
```

## 4. End-to-end validation against the local stack

With `bin/dev-online` running, from `workers/room-worker`:

```sh
bun run smoke:live           # 3- and 4-seat: register guests, create, join, connect, deal, duplicate-ID check, reconnect, abandon, delete accounts
bun run test:network         # full matches through independent clients: 30 cards in deal 1, dropped/replayed pending move,
                             # manager disconnect/migration, impersonation rejection, privacy assertions every revision;
                             # bounded to 128 commands / 30 s per table size
bun run test:public-network  # public discovery, join, leave/rejoin, unauthorized readiness, premature start rejected,
                             # first deal after all Ready, outsider rejected after start, QA account cleanup
```

All three default to `http://127.0.0.1:8787`; `PREFERANS_ROOM_WORKER_URL` selects another (explicitly chosen) environment. `public-lobby-network.ts` only allows the loopback URL or the owner worker URL. Each script creates temporary guest accounts and deletes them.

Expected progress lines: `SMOKE seats=3 phase=connected …`, `SMOKE seats=3 phase=resumed revision=1 …`, `NETWORK seats=3 phase=manager-recovered revision=…`, `[public-network] 3 players: create, discover, join, leave, ready, deal`.

## 5. Native app against the local stack

```sh
bin/screens --no-open --only-testing PreferansUITests/NativeOnlineUITests
```

The UI tests set `PREFERANS_ROOM_WORKER_URL=http://127.0.0.1:8787` in the app's launch environment. DEBUG UI-automation builds accept only a loopback `http` root URL and switch all credential storage to a `.uiTestLocal.<host>.<port>` suffix; release builds always use the production endpoint. Missing local services cause an explicit `XCTSkip`. Tests: `testNativeHostCreatesStartsLeavesAndResumesAfterRelaunch`, `testNativeGuestJoinsAnInviteAndReceivesServerPlay`, `testNativePlayerFindsPublicTableReadiesAndReceivesFirstDeal`, `testNativeHostCreatesDiscoverablePublicTable`.

Opt-in live owner-server QA (dedicated simulator; creates and deletes QA accounts):

```sh
TEST_RUNNER_PREFERANS_OWNER_SERVER_QA=1 xcodebuild test -project Preferans.xcodeproj -scheme Preferans \
  -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:PreferansUITests/OwnerOnlineUITests
```

Manual check with two simulators: register a guest on each (Online → name → Register), create a 3-seat private table with one bot on the first, paste the room code on the second, Join, Start on the first; both should show a `bidding` table at sequence 1 with only their own cards face up. UI-test launch flags for scripted runs (`docs/TESTING.md`): `-uiTestOnlineFlowLogging`, `-uiTestAutoCreateOnlineRoom`, `-uiTestAutoJoinOnlineRoom <code>`, `-uiTestAutoStartOnlineDealOnJoin`, `-uiTestDisableAnimations`, `-uiTestPinLanguageEn`. (`bin/verify-online-invite-flow` wraps these for 3–4 simulators; see spec gap 14 before relying on it.)

## 6. Deployment checks (no deployment)

```sh
cd workers/room-worker
bun run deploy:check                                   # wrangler deploy --dry-run (wrangler.toml) → /tmp/preferans-worker-bundle
bunx wrangler deploy --config wrangler.toml --dry-run --containers-rollout none --outdir /tmp/preferans-worker-ci   # as in CI
```

Real deployments (`bun run deploy` → `wrangler deploy` with `wrangler.toml`; owner backend uses `wrangler.owner.toml` explicitly per `docs/OWNER_MULTIPLAYER_BUILD29.md`) require Docker, Cloudflare authentication and Workers Paid; they are separate, explicitly authorized operations. Never delete or recreate Durable Object namespaces as part of an update or rollback.

## 7. CI

| Workflow | Trigger | Steps |
| --- | --- | --- |
| `.github/workflows/multiplayer.yml` ("Multiplayer contracts") | every push and pull request | job `worker`: Node 24 + Bun, `bun install --frozen-lockfile`, `bun run check`; job `portable-engine` (container `swift:6.3.2-jammy`): `PREFERANS_ENGINE_TESTS_ONLY=1 swift test` |
| `.github/workflows/owner-server-build.yml` ("Owner server image (build only)") | push to `ci/owner-server-build`, `workflow_dispatch` | worker typecheck/test/runtime (60 s timeouts each); Wrangler dry-run with `--containers-rollout none`; `docker build --platform linux/amd64 -f Dockerfile.server`; run on `127.0.0.1:18081`, poll `/health` (20 × 1 s), POST `fixtures/create-game.json` to `/v1/games` and assert `engineVersion == "preferans-1"`, `status == "lobby"`, 3 projections; export `preferans-engine-linux-amd64.tar.gz`, `SHA256SUMS`, `image-id.txt`, `source-commit.txt`, `health.json` as a 14-day artifact; permissions `contents: read`, no secrets |

Verify a downloaded artifact (`docs/SERVER_CI.md`): `sha256sum -c SHA256SUMS`, then `docker load -i preferans-engine-linux-amd64.tar.gz`, and confirm the source commit and image ID before any separately authorized deployment.

## 8. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| App: "The online server needs an update before this app can open tables." | `/health` service name or schema versions differ (e.g. room schema 3 server) |
| App: "Public tables are not available on this server yet…" | `/v2/public-tables` 404/503 (no `LOBBY` binding or old Worker) |
| 410 `room_upgrade_required` | room stored with another schema |
| 503 `engine_unavailable` / `error` frames during play | engine container down or > 8 s; pending move is kept and retried |
| `bin/dev-online`: "Engine did not become healthy." | Docker build/run failed or port 18081 busy |
| Socket closes with 4009 | the same account re-joined the seat from another device/session |
| `players_not_ready` / `room_not_ready` / `lobby_manager_required` receipts | start-deal preconditions (manager, full roster, all humans connected, public Ready) |
