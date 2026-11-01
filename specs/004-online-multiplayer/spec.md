# Feature Specification: Preferans Online Multiplayer (server-authoritative tables)

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `workers/room-worker/src/`, `Sources/PreferansServerCore/AuthoritativeGameService.swift`, `Sources/PreferansServer/main.swift`, `Sources/PreferansEngine/Online/`, `Sources/PreferansEngine/Projection/`, `Preferans/Online/`

Related specs: engine phases/actions → [`../001-game-rules`](../001-game-rules); scoring/variants/pool closure → [`../002-scoring-and-variants`](../002-scoring-and-variants); bot strategies (`HeuristicStrategy`, `BotProfile`, insights) → [`../003-bots`](../003-bots); SwiftUI lobby / waiting room / online table screens → [`../005-ios-app`](../005-ios-app); test lanes & release → [`../006-testing-and-release`](../006-testing-and-release).

Companion documents: [plan.md](plan.md) · [data-model.md](data-model.md) · [research.md](research.md) · [quickstart.md](quickstart.md) · contracts: [worker-http-api](contracts/worker-http-api.md), [realtime-messages](contracts/realtime-messages.md), [game-wire-messages](contracts/game-wire-messages.md), [engine-server-api](contracts/engine-server-api.md), [persistence](contracts/persistence.md), [invite-links](contracts/invite-links.md).

## Summary

Online Preferans is a **server-authoritative** system with three tiers:

1. **iOS client** (`Preferans/Online/`): registers an account (guest or Sign in with Apple), creates/joins/resumes rooms over HTTPS, holds one WebSocket per table, submits commands through a **durable on-device outbox**, and renders only the **per-viewer projection** pushed by the server (`ServerGameCoordinator`). It never constructs an engine for an online table.
2. **Cloudflare Worker + Durable Objects** (`workers/room-worker/`): the routing, identity, membership, durability and fan-out tier. One SQLite-backed Durable Object per table (`PreferansTable`) serializes every mutation, stores the opaque private engine state, durable command receipts and revision checkpoints, drives server bots by alarm, and delivers filtered projections. `PlayerAccountV2` holds accounts, bearer sessions and the "Your games" library; `PublicTableDirectory` holds public-table listings.
3. **Swift engine server** (`Sources/PreferansServer`, Hummingbird, Linux container `PreferansEngineContainer`): a **stateless** transition function. It receives the opaque state blob, validates/apply one command (or one bot move), and returns the new blob plus one redacted projection per seat. It reuses the same `PreferansEngine` as offline play.

The Durable Object is the system of record; the Swift container is the only component that interprets game rules; the client is a projection consumer. The wire protocol is **schema 4** (`PreferansWireSchema.current`, `ROOM_SCHEMA_VERSION`), a clean break from the earlier client-hosted (v2) and v3 designs; accounts use **account schema 2**. A legacy peer-hosted coordinator (`RoomOnlineGameCoordinator` + `HostGameActor`) remains in the app only for the in-memory DEBUG/UI-test room; it refuses server-authoritative transports.

## User Scenarios & Testing

### User Story 1 – Get an online identity (Priority: P1)

A player who wants to play online registers either as a guest (display name only) or with Sign in with Apple. The server issues a stable account ID and a bearer session token that the device keeps in the Keychain.

**Why this priority**: Every room, library and seat operation is authenticated by the account bearer session; nothing online works without it.

**Independent Test**: `workers/room-worker/test/account-state.test.ts` (session round trip, forged/expired sessions, Apple claim validation); `OnlineTransportSecurityTests.testGuestRegistrationUsesV2AndAcceptsOnlyServerIssuedIdentity`; `WireCompatibilityTests.testOnlineAccountV2RoundTripsAndLegacyIdentityCannotDecode`.

**Acceptance Scenarios**:

1. **Given** a non-empty display name, **When** the app calls `POST /v2/accounts/guest`, **Then** the server creates `guest:<uuid>` with a fresh session and returns `{account, sessionToken}` (HTTP 201) and the app stores the token in the Keychain and the account record in UserDefaults.
2. **Given** a Sign in with Apple credential whose identity token `nonce` claim equals SHA-256(hex) of the raw nonce the app generated, **When** the app calls `POST /v2/accounts/apple` with the raw nonce, **Then** the Worker verifies the RS256 signature against Apple's JWKS, issuer, audience (`APPLE_CLIENT_ID`), expiry and nonce and returns the account `apple:<sub>`.
3. **Given** the same Apple subject signs in on a second device, **When** registration completes, **Then** the same account ID is returned with an additional session (max 5 active) so the second device sees the same "Your games".
4. **Given** a tampered, cross-account or expired token, **When** any authenticated route is called, **Then** the Worker answers 401 `unauthorized` ("Register again to use online play.").
5. **Given** a stored account record whose `schemaVersion` ≠ 2 or provider not in {apple, guest}, **When** the lobby loads, **Then** the record is discarded and the player must register again.

### User Story 2 – Create a private table and invite friends (Priority: P1)

The host chooses 3 or 4 seats, a variant and pool settings, marks each non-host seat as *invite* (open) or *bot*, creates a room, shares the room code/link, optionally fills empty seats with bots, and starts the first deal.

**Why this priority**: The primary social flow of the product.

**Independent Test**: `OnlineTransportSecurityTests.testCreateRoomSendsSeatIntentButNoClientDeclaredHumanIdentity`, `testLegacyServerIsRejectedBeforeCreateOrJoinMutatesAnything`; `test/room-state.test.ts` (seat tokens, fill-bots); `test/authoritative-engine.test.ts` ("only the connected lobby manager can start with a complete roster"); `bun run smoke:live`.

**Acceptance Scenarios**:

1. **Given** a registered account, **When** the app creates a room, **Then** it first checks `GET /health` (service `preferans-room-worker`, `accountSchemaVersion` 2, `roomSchemaVersion` 4) and refuses with "The online server needs an update…" before any mutation if incompatible.
2. **Given** a compatible server, **When** `POST /v2/rooms` succeeds, **Then** the response carries the public room, the creator's own `seatToken`, a server-built `websocketURL`, and an `authoritativeTableID`; the creator is the lobby manager (`hostPlayerID`), seat identity comes from the bearer session (never from the client body).
3. **Given** open (`pending:`) seats in the lobby, **When** the manager calls fill-bots, **Then** every open seat becomes `bot:<seat>` named "Bot N" and the engine game is rebuilt at sequence 0.
4. **Given** all seats claimed or bots and every human seat connected, **When** the manager sends `startDeal`, **Then** the server deals (server-chosen dealer and server-shuffled deck) and every human receives a sequence-1 bidding projection with only their own cards face up.
5. **Given** any open seat or a disconnected human seat, **When** the manager sends `startDeal`, **Then** a rejected receipt `room_not_ready` is returned and no deal occurs.

### User Story 3 – Join a table by code or link (Priority: P1)

A friend opens an invite link (Universal Link or `com.mixandmatch.preferans://table/join/CODE`) or pastes a code, registers if needed, and joins.

**Why this priority**: Required for any multi-human table.

**Independent Test**: `PreferansInviteLinkTests` (all five tests); `test/room-state.test.ts` ("joiners with the same declared seat land on distinct open seats", "a join is rejected once every reserved seat is taken", "a late account cannot claim a pending seat in a live room").

**Acceptance Scenarios**:

1. **Given** an invite URL on the configured worker host or the app scheme, **When** the app opens it, **Then** the lobby switches to Online and pre-fills the code ("Invite CODE is ready — tap Join to take a seat."); joining is a separate explicit tap.
2. **Given** a requested seat that is still open, **When** `POST /v2/rooms/{code}/join` runs, **Then** the joiner gets that seat; otherwise the first open seat; the response contains only the joiner's own `seatToken`.
3. **Given** no open seat, **When** a new account joins, **Then** HTTP 409 `room_full`; **Given** the room left the lobby with open seats, **Then** 409 `room_in_progress`.
4. **Given** an invite link for another backend host (e.g. an older `workers.dev` host) or a lookalike host, **When** opened, **Then** it is ignored (no code extracted).

### User Story 4 – Play a move exactly once despite failures (Priority: P1)

A seated player taps a legal action. The move must be applied exactly once even if the network drops, the app is killed, or the Swift engine is briefly unavailable.

**Why this priority**: Correctness of the shared game.

**Independent Test**: `runtime-test/room.test.ts` (all 10 tests, real workerd storage); `ServerAuthoritativeCoordinatorTests.testPendingMoveSurvivesClientRestartAndReceiptClearsIt`, `testUnrelatedReceiptCannotClearPendingMoveAndTakeoverStopsSubmission`; `AuthoritativeGameServiceTests.testDuplicateNonceIsIdempotent`, `testNonceCannotBeReusedForDifferentPayload`.

**Acceptance Scenarios**:

1. **Given** a connected table, **When** the player acts, **Then** the client writes the `ClientActionEnvelope` (UUID `clientNonce`, `baseHostSequence` = displayed projection sequence) to the outbox file *before* sending, disables all actions, and re-sends the identical envelope every 2, 4, 6, 8, 8… s until a receipt for that nonce arrives.
2. **Given** a committed command, **When** the same nonce/payload is re-sent (retry, reconnect, after match end), **Then** the Worker returns the original stored receipt and the current projection without calling the engine again.
3. **Given** the same nonce with a different payload, **Then** a `rejected` receipt with code `command_id_conflict` is sent and no transition happens.
4. **Given** the engine is unreachable or returns 5xx, **Then** no receipt is stored, an `error` frame is sent, and the same command can succeed later.
5. **Given** the app is relaunched with a pending command, **When** the table is reattached, **Then** the pending command is loaded from disk and re-sent with the same ID as soon as the socket is connected.
6. **Given** a stale `baseHostSequence` or illegal action, **Then** the engine rejects it and the Worker stores and returns a `rejected` receipt with code `engine_rejected_command` and the engine message.

### User Story 5 – Hidden information stays hidden (Priority: P1)

Each device sees only what its seat may see in Preferans: its own hand, public table state, and phase-specific reveals.

**Why this priority**: Cheating prevention is the reason for server authority.

**Independent Test**: `ProjectionTests` (14 tests), `ProjectionSnapshotTests`, `AuthoritativeGameServiceTests.testExchangeEventsDoNotExposeDiscardToOtherSeats`, `testServerCreatesAndAdvancesAnAuthoritativeGame`; `runtime-test/room.test.ts` "fresh socket resumes from storage without calling Swift" (no private state in frames); `bun run test:network` (`assertPrivacy` at every revision).

**Acceptance Scenarios**:

1. **Given** bidding, **When** any viewer's projection is built, **Then** only the viewer's 10 cards are `known`; other hands and the 2-card talon are `hidden` with correct counts.
2. **Given** the declarer is exchanging (`awaitingDiscard`), **Then** the talon is `known` to every viewer; after the discard, the discard is `known` only to the declarer.
3. **Given** a talon exchange event, **Then** non-declarer viewers receive `talonExchanged` with empty `talon` and `discard`.
4. **Given** open defence, a non-whisted ten-trick contract, or opened misère defenders, **Then** the corresponding hands are revealed to all viewers per the rules in [data-model.md § Visibility](data-model.md#visibility-matrix).
5. **Given** a completed deal, **Then** `DealResult.initialHands` (pre-exchange hands) is visible to every viewer for post-deal review.

### User Story 6 – Reconnect and resume (Priority: P1)

A player loses connectivity, backgrounds the app, or relaunches it, and returns to the same seat and the same game state.

**Why this priority**: Mobile networks are unreliable; matches last long.

**Independent Test**: `runtime-test/room.test.ts` "fresh socket resumes from storage without calling Swift", "join rotates credentials and immediately closes the previous controller"; `bun run smoke:live` (reconnect step); `NativeOnlineUITests.testNativeHostCreatesStartsLeavesAndResumesAfterRelaunch`.

**Acceptance Scenarios**:

1. **Given** a dropped socket, **When** the transport reconnects (0.5, 1, 2, 4, 8 s cap, +0–30 % jitter), **Then** the Durable Object sends a `room` frame, the stored redacted projection (no engine call), and a `presence` broadcast; the client re-sends any pending command.
2. **Given** a game in "Your games", **When** the player taps Continue, **Then** the app re-joins (`POST /join`), the server rotates the seat token, closes every older socket for that seat with code 4009, and the new socket receives the latest projection.
3. **Given** a socket closed with 4009, **Then** the old device shows "This table was opened on another device." and stops reconnecting/submitting.

### User Story 7 – Find or host a public table (Priority: P2)

Signed-in players browse public tables (Vienna/Prague/Berlin presets), inspect settings and roster, take a seat, confirm Ready; the host starts once everyone is ready and connected.

**Why this priority**: Matchmaking without friends; added in `f7dbbaf` (2026-10-02).

**Independent Test**: `runtime-test/public-lobby.test.ts` (4 tests); `test/public-tables.test.ts` (5 tests); `PublicTableLobbyTests`; `OnlineTransportSecurityTests.testPublicCreationRejectsLegacyServerSilentlyCreatingPrivateRoom`, `testPublicDirectoryExplainsMissingProductionDeployment`; `bun run test:public-network`; `NativeOnlineUITests.testNativePlayerFindsPublicTableReadiesAndReceivesFirstDeal`.

**Acceptance Scenarios**:

1. **Given** a bearer session, **When** the Find screen is active, **Then** the app loads `GET /v2/public-tables?offset=N` (≤ 50 rows, waiting tables first) and refreshes every 15 s while the scene is active.
2. **Given** a public create request, **Then** the Worker rejects bot seats (`public_humans_only`), unknown variants (`invalid_public_variant`) and non-divisible/unbounded pool targets (`invalid_pool_target`), and substitutes canonical rules/match settings from `fixtures/public-rules.json`.
3. **Given** a public waiting table, **When** a new player claims a seat, **Then** all readiness is cleared; a rejoin clears only that player's readiness; a disconnect clears readiness of disconnected players.
4. **Given** not all players Ready, **When** the manager starts, **Then** rejected receipt `players_not_ready`.
5. **Given** a stale listing, **When** someone joins a started/full table, **Then** the authoritative room still rejects with 409.
6. **Given** an old server that ignores `visibility`, **When** the app creates a public table, **Then** the app fails with "Public tables are not available on this server yet…" because the response lacks `visibility: "public"`.

### User Story 8 – Lobby manager migration (Priority: P2)

If the lobby manager disconnects, another connected human becomes manager so the table can still be started or advanced between deals.

**Why this priority**: Only the manager may start deals; without migration a table would stall.

**Independent Test**: `test/room-state.test.ts` "host election is deterministic, monotonic, and limited to connected humans"; `OnlineWorkerIntegrationTests.testDisconnectedLobbyManagerMigratesWithoutEngineAuthority` (live, gated); `bun run test:network` (manager recovery during trick play).

**Acceptance Scenarios**:

1. **Given** the manager's socket closes while another human is connected, **Then** the first connected human in seat order becomes `hostPlayerID` and `hostEpoch` increments by 1.
2. **Given** a finished or abandoned table, **Then** no election occurs.
3. **Given** a migrated manager, **Then** it gains no engine authority (cannot upload state; `reportState` throws "Online game state is owned by the server.").

### User Story 9 – Server-driven bot seats (Priority: P2)

Bot seats play automatically at a readable pace without any client hosting them.

**Independent Test**: `runtime-test/room.test.ts` "bot alarm commits one revision and retains continuation"; `AuthoritativeGameServiceTests.testServerRunsBotSeatsUntilAHumanMustAct`, `testCompleteThreeAndFourSeatMatchesThroughServerBoundary`.

**Acceptance Scenarios**:

1. **Given** a committed state whose current actor is controlled by a bot seat (`botPending`), **Then** the table alarm fires after 500 ms and applies exactly one bot move via `/v1/bots`, commits, and broadcasts.
2. **Given** the engine fails during a bot step, **Then** `retryCount` increments (cap 6) and the next alarm is delayed `min(60 s, 1 s × 2^retryCount)`.

### User Story 10 – Leave, abandon, delete account (Priority: P2)

Players can leave a public waiting table, abandon an unfinished game for everyone, or delete their account.

**Independent Test**: `runtime-test/public-lobby.test.ts` "leave/rejoin retains the library entry…"; `test/room-state.test.ts` "deleting an account reopens its lobby seat…", "deleting a player abandons an active room…", "abandonment drops server-private state and is terminal"; `OnlineWorkerIntegrationTests.testAccountDeletionRevokesSessionAndScrubsLobbySeat`; `OnlineTransportSecurityTests.testAccountDeletionUsesAuthenticatedV2Endpoint`.

**Acceptance Scenarios**:

1. **Given** a seated human at a public lobby table, **When** they call `/leave`, **Then** their seat reopens, all readiness clears, their sockets close with 4011, a durable library-removal is queued, and if no humans remain the table is abandoned.
2. **Given** any seated human (not necessarily manager), **When** they call `/abandon` with their seat token, **Then** the table becomes `abandoned`, private state and projections are dropped, and every library shows the status (the app hides abandoned games).
3. **Given** account deletion, **Then** every room in the account's library is scrubbed first (lobby seats reopen; active tables are abandoned with a `deleted:` tombstone; finished tables keep a tombstone), the room's `history:*` checkpoints and that account's receipts are deleted, sockets close with 4010, then the account record and all sessions are deleted (HTTP 204).

### User Story 11 – Operate the backend (Priority: P3)

A developer runs the Linux engine and local Durable Objects, executes worker/server/client tests, and builds the engine image in CI without deploying.

**Independent Test**: `bin/dev-online`; `bun run check`; `.github/workflows/multiplayer.yml`; `.github/workflows/owner-server-build.yml` (container `/health` and `/v1/games` smoke). See [quickstart.md](quickstart.md).

**Acceptance Scenarios**:

1. **Given** Docker and Bun, **When** `bin/dev-online` runs, **Then** the engine is healthy on `127.0.0.1:18081` within 30 attempts and the local worker serves `127.0.0.1:8787` using `wrangler.local.toml` (`LocalPreferansTable` calls the loopback engine).
2. **Given** a push to `ci/owner-server-build` or manual dispatch, **Then** CI typechecks/tests the worker, dry-runs the Wrangler bundle, builds `Dockerfile.server` for linux/amd64, smoke-tests it, and uploads a 14-day image artifact with SHA-256 — with no Cloudflare credentials and no deployment.

### Edge Cases

- **Room-code collision** on create: up to 5 fresh codes are tried; the existing room is never returned (`room_exists`).
- **Two devices, one account**: the newest `/join` rotates the seat token; the older socket is closed (4009) and its frames are rejected (`seat_credential_invalid` → `error` frame + close 4009). A plain socket reconnect with the *same* token does not rotate but closes other sockets for the seat with 4009.
- **Socket close vs. in-flight command**: close is queued behind the command in the per-table FIFO; the command still commits (`runtime-test/room.test.ts` "socket close cannot overwrite a command…").
- **Receipt lost after commit** (socket dies after commit): retry returns the stored `accepted` receipt even after the match finished.
- **Transaction interrupted**: neither room state nor receipt is persisted ("transaction interruption cannot publish state without its receipt").
- **Lobby roster change** (join, fill-bots, leave, lobby account deletion): the Swift game is recreated at sequence 0 with the same `tableID`; the client accepts a same-sequence-0 projection as a refresh.
- **Unbounded match**: `MatchSettings.poolTarget == Int.max` is omitted from JSON (JavaScript integer safety); absence decodes as unbounded; the room's `tableSettings` is then omitted.
- **Engine returns inconsistent projections** (unknown seat, duplicate seat, mixed table IDs, wrong count, sequence regression, changed table ID): Worker throws `engine_invalid_response` (502) and nothing is committed.
- **Saved table with another engine version**: `engine_version_mismatch` (503); the room fails closed.
- **Room saved by an older schema**: any access returns 410 `room_upgrade_required`.
- **Mutation queue saturation**: more than 64 queued operations on one table → 503 `room_busy`.
- **Socket flood**: more than 30 frames per 10 s on one socket → `error` frame `rate_limited`, frame dropped.
- **HTTP flood**: more than 60 non-GET `/v2/*` requests per 60 s per client IP (when `REQUEST_LIMIT` is bound) → 429 `rate_limited`.
- **Non-manager taps "Next deal"**: accepted. After the first deal any seated human may deal, even while others are offline. If two players tap together, the second command is stale, and its rejection is suppressed on the client because the receipt's sequence is past the command's base (`ServerGameCoordinator.rejectionMessage`).
- **Leaver later deletes their account**: queued library removal returns 401 and is retried indefinitely (see Known Gaps).
- **Unknown server frame type**: the iOS decoder throws, the socket is treated as failed and reconnects.
- **Invalid seat token on (re)connect** (e.g. after account deletion or leave): HTTP 403 on upgrade; the client keeps reconnecting with capped backoff (only 4009 stops it).

## Requirements

### Functional Requirements

#### Topology and authority

- **FR-001**: The system MUST keep the authoritative private game state only in the table Durable Object, as an opaque JSON string (`RoomState.authoritativeState`) that is never sent to any client. — `workers/room-worker/src/room-state.ts` `RoomState`; `index.ts` `PreferansTable.sendProjectionToPlayer`. Test: `runtime-test/room.test.ts` "fresh socket resumes from storage without calling Swift".
- **FR-002**: The system MUST compute every transition (create, human command, bot move) in the stateless Swift engine service, never in the Worker or the client. — `src/authoritative-engine.ts` `createAuthoritativeGame`, `applyAuthoritativeCommand`, `callEngine`; `Sources/PreferansServerCore/AuthoritativeGameService.swift`. Test: `test/authoritative-engine.test.ts` "create sends identities/configuration…".
- **FR-003**: The iOS client MUST NOT construct an engine, elect a game authority, upload state, or publish projections for a Cloudflare table; it MUST only send `clientAction` and `resyncRequest` wire messages. — `Preferans/Online/ServerGameCoordinator.swift`; `CloudflareRoomTransport.send/sendToAll`, `reportState`, `hostRecoveryContext`. Test: `ServerAuthoritativeCoordinatorTests.testCloudAuthorityNeverCreatesAClientHostAndAcceptsServerProjection`, `OnlineTransportSecurityTests.testClientAuthoredStateReportsAreDisabled`.
- **FR-004**: The Worker MUST reject any other client wire message with 409 `client_authority_removed`, and reject `POST /v2/rooms/{code}/state` (410 `client_state_removed`) and `GET …/snapshot` (410 `client_snapshot_removed`). — `index.ts` `relayWireMessage`, router.
- **FR-005**: The legacy peer-host coordinator MUST refuse server-authoritative transports ("Use ServerGameCoordinator for online tables."). — `Preferans/Online/RoomOnlineGameCoordinator.swift` `attach`.
- **FR-006**: The Worker MUST call the engine container through `getRandom(env.ENGINE, 3)` with an 8 s timeout per request; the local configuration MUST call `http://127.0.0.1:18081` instead. — `index.ts` `PreferansTable.engine`; `src/local.ts` `LocalPreferansTable`.

#### Identity, sessions and accounts

- **FR-007**: Registration MUST be the only unauthenticated mutating API: `POST /v2/accounts/guest` (display name) and `POST /v2/accounts/apple` (identity token + raw nonce + display name), both returning 201 `{account, sessionToken}`. — `index.ts` router, `registerAccount`; `CloudflareAccountClient`. Test: `OnlineTransportSecurityTests.testGuestRegistrationUsesV2AndAcceptsOnlyServerIssuedIdentity`.
- **FR-008**: Guest account IDs MUST be server-generated `guest:<lowercase UUID>`; Apple account IDs MUST be `apple:<sub>`. — `account-state.ts` `guestAccountID`; `index.ts`.
- **FR-009**: Apple identity tokens MUST be verified as RS256 JWTs against `https://appleid.apple.com/auth/keys` (cached 6 h), with `iss == https://appleid.apple.com`, `aud` containing `APPLE_CLIENT_ID` (default `com.mixandmatch.preferans`), unexpired `exp`, non-empty `sub`, and `nonce == sha256hex(rawNonce)`; failures → 401 `invalid_apple_identity`, JWKS fetch failure → 503 `apple_unavailable`. — `src/apple-auth.ts`. Test: `test/account-state.test.ts` "Apple claims require issuer, audience, expiry, subject, and hashed nonce".
- **FR-010**: The app MUST generate a fresh raw nonce (lowercased UUID) per Apple request, send `SHA256(raw)` as hex in the Apple request, and send the raw value to the Worker; it MUST request only the `.fullName` scope. — `Preferans/UI/LobbyOnlineSetupCard.swift` `configureAppleSignIn`, `handleAppleSignIn`.
- **FR-011**: Display names MUST be trimmed, non-empty (`invalid_display_name`) and truncated to 60 characters. — `account-state.ts` `normalizeDisplayName`; `room-state.ts` `MAX_DISPLAY_NAME_LENGTH`. Test: "display names are required and bounded", "an oversized display name is truncated on the way in".
- **FR-012**: Session tokens MUST have the form `pref2.<base64url(accountID)>.<base64url(32 random bytes)>`; only the SHA-256 hex of the secret is stored; tokens expire after 180 days; at most 5 unexpired sessions are retained per account (oldest dropped); comparison is constant-time. — `account-state.ts` `issueSession`, `parseSessionToken`, `authenticateSession`. Test: "server-issued guest identity and bearer session round-trip", "forged, cross-account, and expired sessions are rejected".
- **FR-013**: Every authenticated route MUST derive the account from `Authorization: Bearer <token>` by routing to the account Durable Object named by the token's embedded account ID and re-checking the hash there; failures → 401. — `index.ts` `authenticateAccount`. Test: `OnlineTransportSecurityTests.testGameLibraryDerivesAccountFromBearerWithoutAccountQuery`.
- **FR-014**: Re-registering an existing account MUST keep its ID/provider, refresh its display name and issue an additional session; a provider/ID mismatch MUST return 409 `account_conflict`. — `index.ts` `PlayerAccountV2` `/register`.
- **FR-015**: The client MUST store the bearer token in the Keychain (service `com.mixandmatch.preferans.online-account.v2` + storage suffix, account `active-session`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and refuse to proceed if the Keychain write fails ("Could not securely save the online session."). — `Preferans/Online/OnlineSeatCredentialStore.swift` `OnlineAccountSessionStore`; `LobbyViewModel.registerOnlineAccount`.
- **FR-016**: The client MUST accept a registration only if `account.schemaVersion == 2` and the token is non-empty, and MUST discard locally stored accounts with another schema or a provider other than apple/guest. — `CloudflareAccountClient.register`; `LobbyViewModel.loadRegisteredOnlineAccount`. Test: `WireCompatibilityTests.testOnlineAccountV2RoundTripsAndLegacyIdentityCannotDecode`.
- **FR-017**: Release builds MUST use the production worker base URL and the `.owner-v1` storage suffix; DEBUG UI-automation builds MAY override the base URL only with a loopback `http://localhost|127.0.0.1[:port]` root URL from `PREFERANS_ROOM_WORKER_URL`, which switches every credential key to a `.uiTestLocal.<host>.<port>` suffix. — `Preferans/Support/AppIdentifiers.swift`; `Preferans/Support/TestHarness.swift` `localRoomWorkerURL`.

#### Rooms, seats and membership

- **FR-018**: Create MUST require 3 or 4 seats with unique player IDs, exactly one of which equals `localPlayerID`; that seat MUST be bound to the authenticated account; other seats become `bot:<id>` ("Bot N", N = 1-based seat index) when `kind == "bot"`, else `pending:<id>` ("Open seat"). — `index.ts` `createRoomInput`. Test: `OnlineTransportSecurityTests.testCreateRoomSendsSeatIntentButNoClientDeclaredHumanIdentity`.
- **FR-019**: `maxPlayers` MUST equal the number of seats (the body's `maxPlayers` is ignored) and be 3 or 4 (`invalid_max_players`). — `createRoomInput`, `room-state.ts` `clampMaxPlayers`.
- **FR-020**: Room codes MUST be 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` drawn from the platform CSPRNG; inputs are normalized by uppercasing and stripping non-alphanumerics and MUST be 4–12 characters (`invalid_room_code`). — `room-state.ts` `generateRoomCode`, `normalizeRoomCode`.
- **FR-021**: Create MUST retry with a fresh code up to 5 times on collision and never return the existing room. — `index.ts` `POST /v2/rooms`, `PreferansTable` `/create`.
- **FR-022**: Every claimed human seat MUST carry a server-minted 24-character seat token (alphabet without `I O l o 0 1`); bot and open seats MUST carry none; tokens MUST be stripped from every public payload and returned only to the seat owner in its create/join response. — `room-state.ts` `generateSeatToken`, `createInitialRoom`, `normalizePeer`; `index.ts` `createResult`, `/join`. Test: "seat tokens: minted for claimed human seats, never exposed publicly".
- **FR-023**: Joining MUST bind by account ID: an account already seated keeps its seat (display fields refreshed) and receives a rotated token; a new account claims the requested open seat if open, else the first open seat; occupied and bot seats are never claimable. — `room-state.ts` `joinRoom`. Test: "rejoining with the same account reclaims the same seat", "a bot seat is not claimable…", "joiners with the same declared seat land on distinct open seats".
- **FR-024**: A new account MUST NOT claim a seat after the room leaves the lobby (`room_in_progress` 409) and MUST get `room_full` 409 when no open seat exists. — `joinRoom`. Test: "a late account cannot claim a pending seat in a live room".
- **FR-025**: On join the Durable Object MUST upsert the joiner's library entry before committing, close any older socket for that seat (4009 `seat_replaced`), broadcast presence and projections, and schedule library fan-out. — `index.ts` `/join`. Test: `runtime-test/room.test.ts` "join rotates credentials and immediately closes the previous controller".
- **FR-026**: The client MUST adopt the seat the server assigned (matched by account ID) for `localPeer` and the socket identity, and fail if the response omits the caller's seat. — `CloudflareRoomTransport.createRoom/joinRoom`. Test: `OnlineTransportSecurityTests.testRoomMutationRejectsAResponseWithoutTheCallersSeat`.
- **FR-027**: Fill-bots MUST be allowed only for private rooms (`public_humans_only` 409), only in the lobby (`room_in_progress` 409), and only for the current manager proven by account session + current seat token (`authorizeHostSeat`). — `index.ts` `/seats/fill-bots`; `room-state.ts` `fillOpenSeatsWithBots`. Test: "fill-bots converts every open seat…", "host-only mutations require the current host account and rotating seat credential".
- **FR-028**: Every lobby roster change MUST recreate the engine game at sequence 0 reusing `authoritativeTableID`. — `index.ts` `/join`, `/seats/fill-bots`, `/leave`, `/account-deleted`; `createAuthoritativeGame` (`tableID: room.authoritativeTableID`).
- **FR-029**: The engine identities MUST be `{playerID, gamePlayerID, displayName}` per seat in seat order; in public rooms `gamePlayerID` MUST be the room-scoped `seat:<ROOMCODE>:<seat>`; in private rooms it is the account ID. The first seat MUST be the first dealer; bot seats MUST be sent with profile `{difficulty: "seasoned", temperament: "adaptive"}`. — `authoritative-engine.ts` `createAuthoritativeGame`, `playerIdentity`, `botProfiles`. Test: "public engine identities and legacy projections use stable room-scoped IDs…".
- **FR-030**: The unauthenticated `GET /v2/rooms/{code}` MUST return only the public room summary (no seat tokens, no engine state). — `index.ts` `/summary`, `publicRoom`.

#### Public tables, readiness and directory

- **FR-031**: Public creation MUST accept only variants `odesa`, `wien`, `thessaloniki`, a safe-integer `match.poolTarget` in `1…playerCount×999` that (except `wien`) divides by the player count, and MUST replace rules and match settings with the canonical preset (`poolClosure` `tableTotal` for `wien`, else `individualWithAmericanAid`; raspasy progressive `flat/simple` for `thessaloniki`, else `arithmetic/strict`; `totus.asTenTrickGame.requireWhist = false`). — `src/public-tables.ts` `publicConfiguration`; `fixtures/public-rules.json`. Test: "public presets enforce finite truthful pool targets…", `PublicTableRulesTests.testWorkerPublicPresetsMatchTheActualSwiftScoringRules`.
- **FR-032**: Readiness changes MUST be allowed only at a waiting public table, for the seat owner (account + seat token, human), only while that seat has a live socket (`not_connected`), with a boolean `ready` (`invalid_ready`). — `index.ts` `/ready`; `setPlayerReady`. Test: `runtime-test/public-lobby.test.ts` "readiness is authenticated by account and seat token…".
- **FR-033**: A new seat claim MUST clear all readiness; a held-seat rejoin MUST clear only that seat; a socket close at a public lobby table MUST drop readiness of seats without a live socket; `/leave` MUST clear all readiness. — `joinRoom`, `disconnectSocket`, `/leave`. Test: "a new player invalidates readiness…".
- **FR-034**: The first deal at a public table MUST require every seat Ready (`players_not_ready`); later deals MUST NOT require readiness. — `validateStartDealAuthority`.
- **FR-035**: The directory listing MUST contain only roomCode, variant, poolTarget, poolClosure, maxPlayers, per-human `{displayName, ready, connected}`, openSeats (0 unless lobby), status (`lobby|playing`), dealNumber, createdAt; tables with no connected human, or finished/abandoned, MUST NOT be listed. — `public-tables.ts` `publicTableEntry`. Test: "public listings expose no account, credential, projection or hidden engine state".
- **FR-036**: Rooms MUST publish to the directory from the alarm with a monotonically increasing `directoryRevision`; the directory MUST ignore older revisions, keep a 90 s lease, and sweep expired rows by alarm; listed public rooms MUST re-publish every 30 s. — `index.ts` `alarm`, `commitRoom`, `broadcastPresence`; `public-directory.ts`. Test: "directory persists listings, ignores older publication, filters and expires leases".
- **FR-037**: `GET /v2/public-tables` MUST require a bearer session, support `offset` (clamped 0…10 000) and optional exact-match filters `variant`, `players`, `poolTarget`, `status`, sort waiting tables first then by `createdAt` then `roomCode`, return ≤ 50 rows and `nextOffset` (or `null`). — `public-directory.ts` `/list`.
- **FR-038**: In **every** room (public and private, since `fix/online-play`), rosters, library rosters, engine identities and delivered projections MUST mask every human account except the authenticated caller's own as `seat:<ROOMCODE>:<seat>` with provider `dev`; previously persisted unmasked projections MUST be re-masked on delivery. — `room-state.ts` `publicPeer`; `authoritative-engine.ts` `publicProjection`, `projectionWireMessage`. Test: `runtime-test/public-lobby.test.ts` "public create/join and socket frames expose only the caller's global identity…".
- **FR-039**: The app MUST default to private creation unless the directory has loaded successfully, and MUST fail a public create whose response lacks `visibility: "public"`. — `LobbyViewModel.prepareOnlineTableCreation`; `CloudflareRoomTransport.createRoom`. Test: `OnlineTransportSecurityTests.testPublicCreationRejectsLegacyServerSilentlyCreatingPrivateRoom`.
- **FR-040**: The app MUST treat directory 404/503 as "Public tables are not available on this server yet…" and refresh the list every 15 s while active. — `CloudflarePublicTableDirectory`; `LobbyPublicTablesSection`. Test: `testPublicDirectoryExplainsMissingProductionDeployment`.

#### Command submission and durability

- **FR-041**: Every command MUST carry `schemaVersion` (=4), `tableID`, `actor`, `action`, `clientNonce` (UUID), `baseHostSequence` (non-negative safe integer); the Worker MUST reject a schema/table mismatch with `protocol_mismatch`, a non-UUID nonce or missing action with `invalid_command`. — `authoritative-engine.ts` `applyAuthoritativeCommand`; `command-contract.ts` `commandIdentity`.
- **FR-042**: The command identity MUST be keyed `command:<senderAccountID>:<lowercase nonce>` and bound to the SHA-256 of the canonical (key-sorted) JSON of `{sender, tableID, schemaVersion, actor, action, baseSequence}` (`sentAt` excluded). — `command-contract.ts`.
- **FR-043**: A repeated identity MUST return the stored receipt (or a non-stored `rejected`/`command_id_conflict` receipt if the fingerprint differs) followed by the sender's current projection, without calling the engine. — `index.ts` `relayWireMessage`. Test: `runtime-test/room.test.ts` "receipt and room commit together; retry does not invoke engine twice", "different payload under the same ID is rejected…".
- **FR-044**: Commands on a finished or abandoned table MUST get a stored rejected receipt `table_closed`. — `relayWireMessage`.
- **FR-045**: Deterministic rejections (`RoomStateError` with status < 500, including engine 4xx mapped to 409 `engine_rejected_command`) MUST be stored as `rejected` receipts with `code` and `message`; infrastructure failures (≥ 500 or non-`RoomStateError`) MUST NOT create receipts and MUST surface as an `error` frame. — `relayWireMessage`. Test: "engine outage leaves no acceptance; exact command can succeed on retry".
- **FR-046**: An accepted transition MUST commit room state, the receipt (`{fingerprint, receipt}`) and a revision checkpoint in one storage transaction, after scheduling an alarm, and only then deliver the receipt and projections; delivery failure MUST NOT roll back. — `index.ts` `commitRoom`, `sendToPlayers`. Test: "transaction interruption cannot publish state without its receipt", "lost delivery after commit remains accepted when the table has finished".
- **FR-047**: All table mutations — HTTP routes, socket messages, socket close/error and alarms — MUST run through one FIFO `MutationQueue` per Durable Object instance (at most 64 pending; further operations are rejected with `RoomStateError("room_busy", 503)`, which callers outside the Durable Object may observe as a generic failure), and a failed operation MUST NOT block later ones. — `command-contract.ts` `MutationQueue`. Test: "socket close cannot overwrite a command while its engine call is suspended".
- **FR-048**: The engine MUST authorize the sender as `controllingActor(of: action.actor ?? actor)`, reject `action.actor ≠ actor` (`duplicateActor`), reject `baseSequence ≠ state.sequence` (`staleSequence`), and remember the last 16 applied nonces, returning the unchanged state for an identical replay and `commandIDConflict` for a different payload. — `AuthoritativeGameService.apply`, `authorize`. Test: `testAuthenticatedSenderCannotClaimAnotherActor`, `testDuplicateNonceIsIdempotent`, `testNonceCannotBeReusedForDifferentPayload`.
- **FR-049**: The engine MUST replace every `startDeal` with `startDeal(dealer: snapshot.nextDealer, deck: Deck.shuffled(seed: dealSeed &+ generatedDealCount &* 0x9E3779B97F4A7C15))` and increment `generatedDealCount`; client-supplied dealer/deck MUST be ignored. — `AuthoritativeGameService.authoritativeAction`; `dealSeed` from `UInt64.random` in `main.swift`. Test: `testServerCreatesAndAdvancesAnAuthoritativeGame`.
- **FR-050**: The **first** `startDeal` (room `status: "lobby"`) MUST be accepted only from the current manager, with no open seat (`room_not_ready`), every non-bot seat connected (`room_not_ready`), and (public lobby only) everyone Ready. **Later** deals (`status: "playing"`) MUST be accepted from any seated human, and MUST NOT wait for disconnected players. A bot or vacated seat gets `forbidden`. — `authoritative-engine.ts` `validateStartDealAuthority`. Tests: "only the connected lobby manager can start with a complete roster", "any seated human can start a later deal without waiting for absent players", runtime "any seated player starts a later deal even while others are offline".
- **FR-051**: The client MUST persist the pending command to `Application Support/Preferans/Commands/<tableUUID>-<base64(accountID) with "/"→"_">.json` (atomic write) before sending, refuse to submit if the write fails, allow at most one pending command per table+account, and keep it until a receipt with matching `tableID` and `clientNonce` arrives. — `Preferans/Online/OnlineCommandOutbox.swift`; `ServerGameCoordinator.send`, `connection(.commandReceipt)`. Test: `ServerAuthoritativeCoordinatorTests.testPendingMoveSurvivesClientRestartAndReceiptClearsIt`.
- **FR-052**: The client MUST build commands only from a projection whose sequence ≥ the highest receipt sequence seen, only while connected and not submitting, and MUST hide all legal actions while submitting or disconnected. — `ServerGameCoordinator.send`, `displayProjection`.
- **FR-053**: The client MUST re-send the identical pending envelope on every `connected` event and then every `min(attempt×2, 8)` s until resolved, and MUST stop retrying on `reconnecting`, `seatTakenOver` or `tableAbandoned` (the last also deletes the outbox file). — `ServerGameCoordinator.scheduleRetry`, `connection`. Test: `testUnrelatedReceiptCannotClearPendingMoveAndTakeoverStopsSubmission`.
- **FR-054**: A rejected receipt MUST clear the pending command and show its `message` (fallback "The move was rejected."). — `ServerGameCoordinator.connection`.
- **FR-055**: Each committed engine state MUST be checkpointed under `history:<sequence zero-padded to 12 digits>` with `{command?, receipt?, engineVersion, state}`; sequence 0 is overwritten on lobby rebuilds, later keys are written once. Checkpoints have no client endpoint. — `index.ts` `commitRoom`.

#### Realtime transport, ordering and reconnect

- **FR-056**: The socket URL MUST be server-built as `{ws|wss}://<host>/v2/rooms/<CODE>/socket?playerID=<seat>&seatToken=<token>`, and upgrade MUST require `Upgrade: websocket` (else 426) and a matching seat token (else 403). — `index.ts` `withSocketURL`, `connectWebSocket`.
- **FR-057**: On connect the Durable Object MUST attach `{playerID, seatToken, connectedAt}`, close other sockets of that seat (4009), reconcile the manager, send a `room` frame (caller-masked), the stored projection (if any) and broadcast `presence`. — `connectWebSocket`.
- **FR-058**: Every socket frame MUST be re-authorized against the current seat token; failures MUST produce an `error` frame and, for `seat_credential_invalid`, close 4009. — `webSocketMessageUnlocked`.
- **FR-059**: Socket frames MUST be ≤ 128 KiB (`message_too_large` 413), JSON objects (`invalid_socket_json`), of type `wire` or `ping` (`unknown_socket_message`); `ping` MUST be answered with `pong`. — `parseSocketPayload`, `webSocketMessageUnlocked`.
- **FR-060**: Private frames (receipts, projections) MUST be sent only to open sockets whose attachment token equals the seat's current token. — `sendToPlayers`, `sendProjectionToSocket`.
- **FR-061**: Each accepted human command MUST increment `relaySequence` (safe-integer guarded); projection frames MUST carry `serverSequence = relaySequence` and `authority: "server"`; the engine `sequence` (revision) MUST increment on every human or bot transition. — `room-state.ts` `recordRelay`; `index.ts` `sendProjectionToPlayer`. Test: "relay sequence rejects negative, fractional, and exhausted counters".
- **FR-062**: The client MUST accept a projection only if `authority == server`, schema 4, `tableID`/`viewer` match the attachment, envelope and inner projection agree on table/viewer/sequence, and `sequence ≥` the current one; a newer sequence replaces the projection and appends events (rolling 100), sequence 0 at equal value refreshes the lobby projection. — `ServerGameCoordinator.receive`.
- **FR-063**: The client MUST accept `room`/`presence` frames only with schema 4 and `hostEpoch ≥` the known epoch (`room` additionally `relaySequence ≥` the floor) and MUST treat a missing `connectedPlayerIDs` as "only this device connected". — `CloudflareRoomTransport.handleSocketMessage`, `adoptConnectedPlayerIDs`.
- **FR-064**: The client MUST reconnect after any socket failure with delays 0.5, 1, 2, 4, 8 s (cap) plus 0–30 % jitter, resetting after the first frame on a new socket, and MUST stop permanently on close code 4009 (`seatTakenOver`). — `CloudflareRoomTransport.maintainConnection`, `reconnectDelay`.
- **FR-065**: The client MUST send a WebSocket protocol ping every 15 s and cancel the socket if no pong within 10 s. — `CloudflareRoomTransport.openSocket`.
- **FR-066**: Reconnect MUST NOT require an engine call: the Durable Object resends the latest stored redacted projection. — `sendProjectionToSocket`. Test: "fresh socket resumes from storage without calling Swift".

#### Lobby manager (host) election

- **FR-067**: When the current manager has no live socket, the Durable Object MUST elect the first connected human seat in seat order and increment `hostEpoch`; it MUST do so on socket connect, close and error; finished/abandoned tables never migrate. — `room-state.ts` `electLiveHost`; `index.ts` `reconcileHost`. Test: "host election is deterministic, monotonic, and limited to connected humans".
- **FR-068**: The table creator MUST be the initial manager regardless of seat position. — `createInitialRoom`. Test: "the authenticated local peer is host even when not first in seat order".
- **FR-069**: On `/leave` the next manager MUST be the first remaining human seat (connected or not); with no humans left the room MUST be abandoned. On account deletion the successor MUST be a connected remaining human. — `index.ts` `/leave`, `/account-deleted`.
- **FR-070**: The client MUST derive `isHost` (lobby manager only) from the latest `hostPlayerID` and enable Start only if manager, connected, not submitting, no disconnected human, no open seat, `legal.canStartDeal`, and (public, sequence 0) every participant Ready. — `ServerGameCoordinator.refreshRoster`, `updateStartAvailability`.

#### Server bots

- **FR-071**: The engine response MUST set `botPending` when the current actor's controlling seat has a bot profile; the human command response MUST NOT run any bot move. — `AuthoritativeGameService.response`, `apply`. Test: `testServerRunsBotSeatsUntilAHumanMustAct`.
- **FR-072**: Each alarm MUST apply at most one bot move via `/v1/bots`, require `response.sequence == authoritativeSequence + 1` (`bot_stalled`), reset `retryCount` on success, and re-arm 500 ms later while `botPending`. — `index.ts` `alarm`; `BOT_MOVE_DELAY_MS`. Test: "bot alarm commits one revision and retains continuation".
- **FR-073**: Bot failures MUST increment `retryCount` (max 6), log only `{event: "bot_retry", room, revision}`, and delay the next alarm `min(60 000, 1 000 × 2^retryCount)` ms. — `alarm`.
- **FR-074**: Bot decisions MUST pass through `BotDecisionRecovery.recover` and throw `botStalled` if no legal move; a single call MUST NOT exceed 512 bot actions (`botActionLimit`). — `AuthoritativeGameService.advanceBots`.
- **FR-075**: Public-safe bot explanations MUST be kept as a rolling window of 20 in the engine state and copied into every viewer's `ProjectionEnvelope.botInsights`. — `advanceBots`, `response`.

#### Per-player projections (privacy)

- **FR-076**: The engine MUST produce exactly one projection per seat per transition with `ProjectionPolicy.online` (`revealAllHands=false`, `revealOpenDefenderHandsToAll=true`, `revealDeclarerDiscardToDeclarer=true`), and the Worker MUST validate one-per-seat, consistent `tableID` and sequence. — `AuthoritativeGameService.response`; `adoptingEngineResponse`.
- **FR-077**: A seat's hand MUST be `known` (sorted) to the viewer iff the viewer owns it, or the hand is in the frame's reveal set; otherwise `hidden` with the correct count. — `PlayerProjectionBuilder+Visibility.swift` `projectedHand`. Test: `ProjectionTests.testBiddingProjectionDoesNotLeakOtherHandsOrTalon`.
- **FR-078**: The talon MUST be `known` to every viewer during `awaitingDiscard`; during talon-led raspasy play it MUST reveal card *i* while `i ≤ completedTricks` for the first two tricks; otherwise `hidden`. — `projectTalon`. Test: `testTalonRevealedToAllViewersDuringExchange`, `testClassicAllPassProjectionOpensTalonOneCardAtATime`, `testRostovAllPassKeepsTalonHiddenForEveryViewer`.
- **FR-079**: The discard MUST be `known` only to the declarer. — `projectDiscard`.
- **FR-080**: During play, open-defence defender hands, all active hands for a non-whisted ten-trick contract with no whist calls, and opened misère defenders (`misereDefendersAreOpen`) MUST be revealed to all viewers; a seat controlled by the viewer (open single-whist dummy) MUST be revealed to that viewer and reported as `legal.playableCardsOwner`. — `PlayerProjectionBuilder+Phase.swift` `applyPlayRolesAndVisibility`, `playingFrame`. Test: `testUnwhistedTenCheckRevealsEveryHandToEverySeat`, `testClosedMisereHidesDeclarerHandButOpensDefenders`, `testStalingradProjectionKeepsForcedWhistHandsClosed`.
- **FR-081**: Legal actions MUST be computed per viewer (`legalBidCalls`, `legalWhistCalls`, `legalCards`, `legalSettlements`, contract options/defender modes/discard only for the acting seat); `canStartDeal` MUST be true in `waitingForDeal` and `dealFinished`. — `phaseFrame`.
- **FR-082**: The only online event boundary MUST be `OnlineEventProjection.events`: `talonExchanged` carries `talon`/`discard` only for the declarer; all other events pass unchanged; the switch is exhaustive. — `OnlineEventProjection.swift`. Test: `testExchangeEventsDoNotExposeDiscardToOtherSeats`.
- **FR-083**: Projections MUST never include the deck, deal seed, engine snapshot, other seats' tokens or private state; delivered frames MUST not contain `authoritativeState`. — `PlayerGameProjection`; worker frames. Test: "fresh socket resumes…" (`not.toContain("private-8")`); `scripts/match-network.ts` `assertPrivacy`.
- **FR-084**: The client MUST hold a completed trick on screen for 2.4 s via `pendingAdvance` without affecting authority. — `ServerGameCoordinator.receive` (`AdvancePresentation.completedTrickHold`).

#### End of life: finish, abandon, leave, account deletion

- **FR-085**: When the engine reports `finished`, the Worker MUST drop `authoritativeState` (keeping projections and receipts) and set status `finished`. — `adoptingEngineResponse`. Test: "lost delivery after commit remains accepted when the table has finished".
- **FR-086**: `/abandon` MUST be allowed for any seated human proving account + seat token, MUST set `abandoned`, drop private state and projections, broadcast presence and schedule library fan-out; it MUST be a no-op on terminal tables. — `index.ts` `/abandon`; `room-state.ts` `abandonRoom`. Test: "abandonment drops server-private state and is terminal".
- **FR-087**: The client MUST emit `tableAbandoned` when a `room`/`presence` frame has status `abandoned`, clear the pending command, and show "This table was abandoned…". — `CloudflareRoomTransport.handleSocketMessage`; `ServerGameCoordinator.connection`.
- **FR-088**: `/leave` MUST be allowed only at a waiting public table for the seat owner, reopen the seat, queue a durable library removal, close the leaver's sockets (4011) and re-elect or abandon. — `index.ts` `/leave`.
- **FR-089**: Account deletion MUST scrub every room in the account library (404/410 tolerated, other failures abort), then delete the account record; lobby seats reopen as `pending:`, other statuses use a `deleted:<seat>` "Deleted player" tombstone, an active (`playing`) table is abandoned, all `history:*` keys and that account's `command:` receipts are deleted, non-lobby rooms drop projections and state, sockets close 4010. — `index.ts` `deleteAuthenticatedAccount`, `/account-deleted`; `removeAccountFromRoom`. Test: "deleting an account reopens its lobby seat…", "deleting a player abandons an active room…".
- **FR-090**: Client account deletion MUST call authenticated `DELETE /v2/account` and then clear the Keychain token, seat-token cache and stored account/name. — `LobbyViewModel.deleteRegisteredOnlineAccount`, `clearOnlineAccountData`. Test: `testAccountDeletionUsesAuthenticatedV2Endpoint`.

#### Library ("Your games")

- **FR-091**: Every commit MUST mark `libraryDirty`; the alarm MUST upsert one `GameSummaryEntry` per human seat into that account's Durable Object (3 s timeout each) and clear the flag only when all succeed; create and join MUST upsert synchronously before commit. — `commitRoom`, `alarm`, `upsertLibraryEntry`. Test: "failed library delivery stays durable until a later alarm repairs it".
- **FR-092**: Library removals MUST be retried by alarm, skipped for accounts that are seated again, and treat 404/410 as done. — `alarm`. Test: "leave/rejoin retains the library entry and alarms discard stale removals for current seats".
- **FR-093**: `GET /v2/my-games` MUST return only entries with `roomSchemaVersion == 4`, most recently updated first. — `library-state.ts` `listGames`. Test: "listGames orders games most-recently-updated first".
- **FR-094**: The app MUST show `lobby`/`playing` as Continue, `finished` as History and hide `abandoned`, and ignore results of superseded refreshes. — `OnlineGameLibrary.refresh`. Test: `OnlineGameLibraryTests` (6 tests).
- **FR-095**: Resume MUST re-join with the summary's `youSeat` and the current account; abandon from the list MUST use the cached seat token for that room. — `LobbyViewModel.resumeCloudflareOnlineRoom`, `abandonOnlineGame`.

#### Invites and universal links

- **FR-096**: Invite URLs MUST be `<inviteBaseURL>/join/<CODE>` where `inviteBaseURL == roomWorkerBaseURL`. — `PreferansInviteLink.inviteURL`; `AppIdentifiers.inviteBaseURL`.
- **FR-097**: The app MUST accept only `https://<inviteBaseURL host>/join/<code>` and `com.mixandmatch.preferans://table/join/<code>` with no user/password/fragment and exactly two path components, plus pasted `join/<code>`, `/join/<code>`, `<host>/join/<code>` or a bare code; codes must match `^[A-Za-z0-9-]+$` and normalize to 4–12 alphanumerics. — `PreferansInviteLink.roomCode(from:)`. Test: `PreferansInviteLinkTests`.
- **FR-098**: The Worker MUST serve the Apple App Site Association JSON at `/.well-known/apple-app-site-association` and `/apple-app-site-association` (paths `/join/*`) and an HTML landing page at `GET /join/<code>` with an `Open Preferans` scheme link, App Store link, `noindex,nofollow`, `no-referrer`, and HTML-escaped code. — `index.ts` `appleAppSiteAssociation`, `invitePage`.

#### Versioning and compatibility

- **FR-099**: Client and server MUST agree on wire/room schema 4 and account schema 2; the client MUST verify `/health` before create/join (8 s timeout, no auth header) and validate `schemaVersion == 4` and `relaySequence ≥ 0` in every room response. — `CloudflareRoomTransport.checkServerCompatibility`, `postRoomRequest`, `init`. Test: `testLegacyServerIsRejectedBeforeCreateOrJoinMutatesAnything`, `testRoomMutationRejectsAnIncompatibleSchemaVersion`, `testRoomMutationRejectsAnInvalidRelaySequence`.
- **FR-100**: Every wire envelope MUST require `schemaVersion` on decode (no default), so pre-v4 frames fail to decode. — `GameWireMessage.swift` custom `init(from:)`. Test: `WireCompatibilityTests.testSeatAssignmentRequiresTheCurrentWireSchema`, `testProjectionEnvelopeRequiresTheCurrentWireSchema`.
- **FR-101**: The Worker MUST reject engine responses whose `engineVersion ≠ "preferans-1"` and refuse commands on rooms saved with another engine version (503). The engine MUST reject state blobs with `schemaVersion ≠ 2`. — `authoritative-engine.ts` `ENGINE_VERSION`; `AuthoritativeGameState.schemaVersion`.
- **FR-102**: The checked-in `fixtures/create-game.json` MUST decode to the Swift `CreateAuthoritativeGameRequest` (regenerated only with `PREFERANS_UPDATE_WIRE_FIXTURE=1`). — Test: `AuthoritativeGameServiceTests.testCheckedInWireFixtureMatchesSwiftCodec`.

#### Security limits

- **FR-103**: HTTP bodies MUST be read with a 128 KiB cap (`message_too_large` 413) and parsed as JSON (`invalid_json`). — `index.ts` `readJSON`.
- **FR-104**: When `REQUEST_LIMIT` is bound, non-GET `/v2/*` requests MUST be limited per `CF-Connecting-IP` (60 per 60 s in both production configs) → 429 `rate_limited`. — router; `wrangler.toml` `[[ratelimits]]`.
- **FR-105**: Each socket MUST be limited to 30 frames per 10 s window. — `webSocketMessageUnlocked`.
- **FR-106**: Credentials and private state MUST NOT be logged; the Worker logs only bot-retry metadata; the client logs online-flow lines only under `-uiTestOnlineFlowLogging`. — `index.ts` `alarm`; `CloudflareOnlineGameSession.logOnlineFlow`.
- **FR-107**: Responses MUST carry permissive CORS (`*`, methods `GET,POST,DELETE,OPTIONS`, headers `authorization,content-type`); `OPTIONS` → 204. As built, the `/v2/public-tables` listing (proxied from `PublicTableDirectory`'s `Response.json`) carries no CORS headers. — `corsHeaders`.

#### Deployment and configuration

- **FR-108**: The engine image MUST be built from `Dockerfile.server` with `PREFERANS_SERVER_ONLY=1 swift build -c release --product PreferansServer` on `swift:6.3.2-jammy`, run on `swift:6.3.2-jammy-slim`, listening on `PORT` (default 8080). — `Dockerfile.server`, `Package.swift`, `main.swift`.
- **FR-109**: Production Worker configs MUST bind `ROOMS`→`PreferansTable`, `ACCOUNTS`→`PlayerAccountV2`, `ENGINE`→`PreferansEngineContainer` (max 3 instances, `sleepAfter` 10 m, port 8080), `LOBBY`→`PublicTableDirectory`, `APPLE_CLIENT_ID`, `REQUEST_LIMIT`, observability on. — `wrangler.toml`, `wrangler.owner.toml`, `index.ts` `PreferansEngineContainer`.

#### Legacy in-process simulation (DEBUG / UI tests only)

- **FR-110**: The in-memory room (`InMemoryOnlineGameSession`) MUST run the full peer-host protocol (hello, seatAssignment, projection, hostError, resyncRequest, ping) in-process with `HostGameActor` as engine owner and is reachable only via UI-test launch flags. — `Preferans/Online/InMemoryOnlineGameSession.swift`, `RoomOnlineGameCoordinator.swift`, `HostGameActor.swift`; `LobbyView` harness. Test: `RoomOnlineGameCoordinatorTests` (36 tests), `OnlineBotSeatTests`, `EventSourcingTests`.
- **FR-111**: In that path the host MUST publish a projection only after `reportState` succeeds (durability barrier, retry 500 ms doubling to 8 s), serialize host mutations, recover authority with 250 ms→4 s backoff, pace bots at the configured delay and never apply a bot decision computed against a stale snapshot, and clients MUST flag the host unreachable after 10 s without contact (probe every 3 s). — `RoomDurabilityRetryRunner`, `RoomHostActionQueue`, `RoomHostRecoveryRunner`, `RoomBotMoveScheduler`, `RoomHostLiveness`, `HeartbeatConfig.default`. Tests: `RoomDurabilityRetryRunnerTests`, `RoomHostRecoveryRunnerTests`, `RoomBotMoveSchedulerTests`, `testHostLivenessExpiresAtTheConfiguredDeadline`.

### Key Entities

- **Account** (`PlayerAccountState`, DO `PlayerAccountV2`): server-issued identity (`guest:*`/`apple:*`), provider, display name, hashed sessions, library map.
- **Session token**: opaque bearer `pref2.<b64url accountID>.<secret>`; account-wide credential kept in the device Keychain.
- **Room / table** (`RoomState`, DO `PreferansTable`): code, visibility, seats (`OnlinePeer[]`), manager (`hostPlayerID`, `hostEpoch`), status, readiness, engine configuration, opaque engine state, per-seat projections, counters and outbox flags.
- **Seat** (`OnlinePeer`): `playerID` (`north|east|south|west`), `accountID` (human, `pending:`, `bot:`, `deleted:`, or masked `seat:`), provider, display name, private `seatToken`.
- **Seat token**: per-seat room credential, rotated on every `/join` of a held seat; authorizes the socket, abandon, ready, leave, fill-bots.
- **Command** (`ClientActionEnvelope`) and **Receipt** (`CommandReceipt` / `OnlineCommandReceipt`).
- **Authoritative game state** (`AuthoritativeGameState`): Swift snapshot, identities, bot profiles, nonce memory, deal seed, bot insights.
- **Projection** (`ProjectionEnvelope` → `PlayerGameProjection`): per-viewer redacted view.
- **Library entry** (`GameSummaryEntry` / `OnlineGameSummary`).
- **Public listing** (`PublicTableEntry` / `PublicOnlineTable`).
- **Pending command file** (`OnlineCommandOutbox`) and **seat-token cache** (`OnlineSeatCredentialStore`).

See [data-model.md](data-model.md) for fields, invariants and state machines.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A command retried any number of times invokes the engine exactly once and yields the same receipt (`runtime-test/room.test.ts`, engine call count = 1).
- **SC-002**: A complete 3-seat and 4-seat match runs to `finished` through the server boundary within 2 000 service steps (`testCompleteThreeAndFourSeatMatchesThroughServerBoundary`).
- **SC-003**: A bounded network match (independent authenticated clients, pool 6 table-total) finishes within 128 commands and 30 s per table size, including a dropped/replayed pending move and a manager migration during trick play (`bun run test:network`); recorded at 11.6 s / 10.8 s in `docs/OWNER_MULTIPLAYER_BUILD29.md`.
- **SC-004**: At every revision of that match, no viewer receives another seat's closed hand, the discard before deal end, a non-empty foreign `talonExchanged` payload, `state`, `deck` or `dealSeed` (`assertPrivacy`).
- **SC-005**: Bot seats advance at one revision per 500 ms alarm while healthy; after engine failure, the retry delay never exceeds 60 s.
- **SC-006**: A reconnecting socket receives its seat's latest projection with zero engine calls.
- **SC-007**: Public listings disappear within 90 s (lease) after a table stops being advertisable or its room stops publishing; live tables re-publish every 30 s.
- **SC-008**: Every HTTP room mutation from the app is preceded by a compatibility check and makes zero mutating requests against a schema-3 server (`testLegacyServerIsRejectedBeforeCreateOrJoinMutatesAnything`, `mutations == 0`).
- **SC-009**: The worker test suite comprises 52 unit tests (`node --test`) and 14 real-workerd tests (`vitest`), all run by `bun run check` in CI on every push/PR.
- **SC-010**: Client reconnect delay is bounded by 8 s × 1.3 = 10.4 s between attempts; keepalive detects a dead socket within 25 s (15 s ping interval + 10 s deadline).

## Known Gaps & Open Questions

1. ~~**Match result never reaches the library.**~~ **Fixed on `fix/online-play`.** When the match ends, the Swift server returns `result {winner?, finalBalances}` from `MatchSummary` (`AuthoritativeGameResult`). The worker validates it with `matchResult`: every seat present, finite balances, and the winner must be a seat. It is stored in `summary.result` and fanned out to every library, where the app's existing `OnlineGameResult` / `winnerName` UI shows it. A malformed result is dropped instead of failing the final move.
2. ~~**"Next deal" offered to non-managers.**~~ **Fixed on `fix/online-play`.** Later deals may be started by any seated human without waiting for absent players (FR-050), and superseded rejections are silent on the client. The first deal remains manager-only, with every human connected.
3. ~~**Private-room identities are visible.**~~ **Fixed on `fix/online-play`.** `publicPeer` and `publicProjection` now mask every human account except the caller's own in private rooms too. That covers room summaries (including the unauthenticated `GET /v2/rooms/{code}`), presence frames, library rosters, engine identities and delivered projections. Bot and open seats keep their `bot:` / `pending:` IDs. That summary endpoint is still not rate-limited.
4. ~~**Close codes 4010/4011 and 403 on reconnect are not terminal on iOS.**~~ **Fixed on `fix/online-play`.** Close codes 4010/4011 and socket-upgrade statuses 401/403/404/410 now end the reconnect loop with `RoomTransportEvent.seatLost(message)`. The coordinator then drops the pending command, goes `.disconnected` and shows the message (`CloudflareRoomTransport.terminalDisconnectMessage`).
5. **Unbounded retry of infrastructure failures.** The outbox still retries for as long as the table is open (2→8 s). Since `fix/online-play`, a move without a receipt after the fifth send (~20 s) shows "Your move hasn't been confirmed yet. Still trying…". There is still no automatic give-up, and engine outages surface only as `error` frame text.
6. **Retention** (implemented on `fix/online-play` for terminal tables). When a table becomes `finished`/`abandoned`, `commitRoom` stamps `terminalAt`. The next alarm deletes every `history:*` checkpoint in 128-key pages (`historyPurged`). After `TERMINAL_ROOM_RETENTION_MS` (30 days), once the library and directory outbox is empty, the alarm closes any sockets (1000 `table_expired`) and wipes the Durable Object (`deleteAll`); reconnecting clients then get 404. Receipts survive until that wipe, so late retries still get their receipt. Rooms that ended before this change age from `updatedAt`, but are only cleaned once something wakes their object. Still open: unfinished lobbies that are never used, and library rows, are not pruned.
7. ~~**Library removal for deleted accounts loops.**~~ **Fixed on `fix/online-play`.** Library upserts and removals now treat 401/404/410 from the account object as "account gone" (`GONE_ACCOUNT_STATUSES`), so they no longer retry forever or block retention.
8. **`retryCount` is reset only by a successful bot move**, so after a bot failure non-bot outbox work (library/directory) also uses the exponential delay until the next bot success.
9. **Server `eventSummaries` is always `[]`**; the online `eventLog` stays empty (structured `events` are used instead). `ServerGameCoordinator` never sends `resyncRequest` and never reports `hostUnreachable` (liveness is `connecting`/`live` only).
10. **Bot strength online is fixed** to `seasoned/adaptive`; the client's bot profile choice is not transmitted (`RoomSeatIntent` carries only `you|open|bot`).
11. **The worker ignores `CreateRoomBody.maxPlayers`**, deriving it from the seat count; `POST /v2/rooms` returns HTTP 200 (the Durable Object's 201 is re-wrapped).
12. **Swift `/v1/bots` errors are not wrapped** in `HTTPError(.badRequest)` like `/v1/games` and `/v1/commands`, so they surface as 500 (treated as retryable 502 by the Worker).
13. **Universal-link domains disagree.** `Preferans.entitlements` lists `preferans.game`, an older beta `workers.dev` host and the current owner `workers.dev` host; `AppStore/UniversalLinks/README.md` documents only the first two; `PreferansInviteLink` accepts only the owner host (`AppIdentifiers.inviteBaseURL`), so links on the other two domains open the app but are ignored. Root `README.md` still says universal links "need a real hosted domain".
14. **`bin/verify-online-invite-flow` appears stale**: it expects auto-create/join without an explicit registration step and waits for `ONLINE_FLOW event=projection` lines in the `online-flow` unified-log category, but `ServerGameCoordinator` only `print`s that line. [NEEDS CLARIFICATION: is the script still expected to pass against the server-authoritative client?]
15. **CI coverage**: `multiplayer.yml` runs the Worker suite and the `PREFERANS_ENGINE_TESTS_ONLY` Swift lane; `PreferansServerCoreTests` (wire fixture, public-rule parity, full server matches) run only in the full local `swift test` graph. `owner-server-build.yml` runs only on `ci/owner-server-build` or manual dispatch.
16. **Doc counts are stale**: `docs/MULTIPLAYER.md` cites 45 worker unit / 10 workerd tests; the tree has 52 / 14.
17. **Env-var naming**: the live Swift integration tests read `PREFERANS_WORKER_URL`, while scripts and the app's UI-test override read `PREFERANS_ROOM_WORKER_URL`.
18. **`bun run deploy` deploys `wrangler.toml`** (no pinned account), while `docs/OWNER_MULTIPLAYER_BUILD29.md` requires owner deployments to use `wrangler.owner.toml` explicitly. [NEEDS CLARIFICATION: which config is canonical for production going forward?]
19. **Sign-out is local only**: there is no session-revocation endpoint; a cleared device token remains valid server-side until expiry (180 d) or eviction by newer sessions (> 5).
20. **Game Center** entitlement and `GameCenterService` exist but play no role in online tables; `OnlineAccountProvider.gameCenter/email` are accepted in room peers but never issued by the account API. `Preferans/Support/Preferans.entitlements.example` is obsolete (Game Center, iCloud/CloudKit and APNs keys only; no Sign in with Apple or associated domains).
21. **No production capacity data**: `docs/MULTIPLAYER.md` and the worker README state that cold-start latency and concurrent-table capacity of the 3-instance container pool are unmeasured.
22. **README identity claims**: root `README.md` lists an "In-app email/Gmail test profile"; the code implements only server-issued **guest** accounts and Sign in with Apple (the `email` provider exists only as an enum case).
23. **Variant naming**: `docs/PUBLIC_LOBBY.md` and the Worker error text name the public presets Vienna/Prague/Berlin (`odesa`/`wien`/`thessaloniki`), while the root README lists house names Одеса/Wien/Θεσσαλονίκη/Крути; persisted identifiers are unchanged either way (presentation owned by [`../005-ios-app`](../005-ios-app) and [`../002-scoring-and-variants`](../002-scoring-and-variants)).
24. **Legacy wire surface**: `GameWireMessage.hello/seatAssignment/hostError/ping` and `RoomRealtimeTransport.reportState/hostRecoveryContext` remain in the shared protocol solely for the in-memory room; any client sending them to the Worker gets `client_authority_removed`.
