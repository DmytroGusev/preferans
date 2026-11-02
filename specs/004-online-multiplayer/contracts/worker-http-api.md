# Contract: Room Worker HTTP API (`/health`, `/v2/*`, invites)

**Implementation**: `workers/room-worker/src/index.ts` (default export `fetch`), Durable Objects `PreferansTable`, `PlayerAccountV2`, `PublicTableDirectory`. **Client**: `Preferans/Online/CloudflareRoomTransport.swift` (`CloudflareAccountClient`, `CloudflareRoomTransport`), `Preferans/Online/OnlineGameLibrary.swift` (`CloudflareGameDirectory`, `CloudflarePublicTableDirectory`).

Base URL: `AppIdentifiers.roomWorkerBaseURL` (the owner's `*.workers.dev` host in release builds; `http://127.0.0.1:8787` locally).

## Conventions

- **Auth**: `Authorization: Bearer <sessionToken>` (`pref2.<b64url accountID>.<secret>`). Missing/invalid → **401** `{"error":"Register again to use online play.","code":"unauthorized"}` (or `account_not_found`, `account_upgrade_required`).
- **Seat proof**: room mutations additionally carry `{playerID, seatToken}` in the body; the Worker always overwrites any body `accountID` with the authenticated account.
- **Body**: JSON, read with a hard cap of 131 072 bytes (128 KiB) → **413** `message_too_large`; unparsable → **400** `invalid_json`; a missing body → **400** `invalid_json` ("Request body is required.").
- **Errors**: `{"error": "<human message>", "code": "<machine code>"}` with the HTTP status carried by the thrown `RoomStateError`/`AccountStateError` (default 400; unknown errors 500 `internal_error`). Router-level 404/405 bodies have no `code`.
- **CORS** on every JSON/HTML response built with the Worker/account `json()`/`html()` helpers (the `/v2/public-tables` body is proxied from `PublicTableDirectory`'s plain `Response.json` and carries none): `access-control-allow-origin: *`, `access-control-allow-methods: GET,POST,DELETE,OPTIONS`, `access-control-allow-headers: authorization,content-type`. `OPTIONS <any>` → **204**.
- **Rate limit**: if binding `REQUEST_LIMIT` exists, every non-GET request under `/v2/` is limited by `CF-Connecting-IP` (configured `limit = 60`, `period = 60` s) → **429** `rate_limited` ("Too many requests. Try again shortly."). GET requests (including the socket upgrade) are not limited. The local config has no limiter.
- **Room code path segment**: `[A-Za-z0-9-]+`, normalized server-side (uppercase, strip non-alphanumerics, 4–12 chars else **400** `invalid_room_code`).
- **Client timeouts**: room POSTs sent through `postRoomRequest` (create, join, ready, leave, fill-bots) 30 s; `/health` 8 s (cache ignored); `/v2/public-tables` 8 s; others (registration, `/abandon`, `/v2/my-games`, `DELETE /v2/account`) `URLSession` default.
- Types `PublicRoom`, `OnlinePeer`, `GameSummaryEntry`, `PublicTableEntry` are defined in [../data-model.md](../data-model.md).

### `PublicRoom` (room summary) fields

| Field | Type | Notes |
| --- | --- | --- |
| `visibility` | `"private"\|"public"` | |
| `readyPlayerIDs` | `PlayerID[]` | |
| `tableSettings` | `{variant?, poolTarget, poolClosure}`? | Present only when `match.poolTarget` exists (absent for unbounded) |
| `schemaVersion` | 4 | |
| `roomCode` | string | |
| `hostPlayerID` | PlayerID | Lobby manager |
| `hostEpoch` | number | |
| `peers` | `OnlinePeer[]` | Never contains `seatToken`. Public rooms: non-caller humans masked as `seat:<CODE>:<seat>`/`dev` |
| `maxPlayers` | 3\|4 | |
| `createdAt`, `updatedAt` | ISO string | |
| `relaySequence` | number | |
| `status` | `lobby\|playing\|finished\|abandoned` | |
| `summary` | `{variant?, lastSequence, phase?, dealNumber?, result?}`? | Ignored by iOS |
| `authoritativeTableID` | UUID string? | |

`RoomWithSocketURL` = `PublicRoom` + `seatToken` (caller's own) + `websocketURL` = `{wss|ws}://<request host>/v2/rooms/<CODE>/socket?playerID=<assigned seat>&seatToken=<token>`.

---

## Endpoints

### `GET /health`

Auth: none. Response **200**:

```json
{"ok": true, "service": "preferans-room-worker", "accountSchemaVersion": 2, "roomSchemaVersion": 4}
```

The app (`CloudflareRoomTransport.checkServerCompatibility`) requires status 200, `ok`, exact `service`, `accountSchemaVersion == 2` and `roomSchemaVersion == 4` before create/join; otherwise it throws `incompatibleServer` without sending any mutation.

### `POST /v2/accounts/guest`

Auth: none (rate-limited). Request:

| Field | Type | Rules |
| --- | --- | --- |
| `displayName` | string | trimmed, non-empty, truncated to 60 |

Response **201**:

```json
{"account": {"schemaVersion": 2, "accountID": "guest:00000000-0000-4000-8000-000000000001", "provider": "guest", "displayName": "Ada"},
 "sessionToken": "pref2.<b64url-account>.<secret>"}
```

Errors: 400 `invalid_display_name`, 400/413 body errors, 429.

### `POST /v2/accounts/apple`

Auth: none (rate-limited). Request:

| Field | Type | Rules |
| --- | --- | --- |
| `identityToken` | string | Apple RS256 JWT |
| `nonce` | string | **raw** nonce; the token's `nonce` claim must equal `sha256hex(nonce)` |
| `displayName` | string | as above |

Verification (`apple-auth.ts`): header `alg == RS256` and `kid` present; key from `https://appleid.apple.com/auth/keys` (`kty == RSA`, cached 6 h per isolate); RSASSA-PKCS1-v1_5/SHA-256 signature; `iss == https://appleid.apple.com`; `aud` (string or array) contains `APPLE_CLIENT_ID` (default `com.mixandmatch.preferans`); `exp` in the future; `sub` non-empty. Account ID = `apple:<sub>`.

Response **201** as for guest (provider `apple`). Re-registration of an existing Apple account keeps the ID, refreshes `displayName` and adds a session.

Errors: 401 `invalid_apple_identity` ("Apple sign-in could not be verified. Try again."), 503 `apple_unavailable` (JWKS fetch failed), 400 `invalid_display_name`, 409 `account_conflict`.

### `GET /v2/my-games`

Auth: Bearer. Response **200** `{"games": GameSummaryEntry[]}` — entries with `roomSchemaVersion == 4`, sorted by `updatedAt` descending. Errors: 401.

### `GET /v2/public-tables`

Auth: Bearer. Query (all optional): `offset` (int, clamped 0…10 000), `variant` (`odesa|wien|thessaloniki`), `players` (3|4, matches `maxPlayers`), `poolTarget` (int), `status` (`lobby|playing`). The iOS client sends only `offset`.

Response **200**:

```json
{"tables": [{"roomCode": "PUBLIC", "variant": "odesa", "poolTarget": 33, "poolClosure": "individualWithAmericanAid",
             "maxPlayers": 3, "players": [{"displayName": "Host", "ready": true, "connected": true}],
             "openSeats": 2, "status": "lobby", "createdAt": "2026-10-02T12:00:00Z"}],
 "nextOffset": null}
```

At most 50 rows; only rows with an unexpired lease (90 s) and a `table`; sort: `lobby` before `playing`, then `createdAt` ascending, then `roomCode`. `nextOffset = offset + 50` if more rows exist, else `null`.

Errors: 401; **503** `lobby_unavailable` if the `LOBBY` binding is missing. The app maps 404/503 to "Public tables are not available on this server yet. You can still invite friends with a room code."

### `DELETE /v2/account`

Auth: Bearer. No body. Steps: read the account's library; for every `roomCode` call the room's internal `/account-deleted`; any room failure other than 404/410 aborts with that room's status/code (`room_cleanup_failed` fallback); then delete all account storage (record, sessions, library).

Response **204** (no body). Errors: 401, room cleanup errors, `account_error`.

### `POST /v2/rooms` — create

Auth: Bearer. Request (`CreateRoomBody`):

| Field | Type | Rules |
| --- | --- | --- |
| `visibility` | `"private"\|"public"`? | other values → 400 `invalid_visibility`; public needs `LOBBY` binding (503 `lobby_unavailable`) |
| `localPlayerID` | PlayerID or string | must equal exactly one seat's `playerID` (400 `invalid_seats`) |
| `seats` | `{playerID, kind}[]` | length 3 or 4 (`invalid_seats`); unique IDs; `kind == "bot"` → `bot:<id>`, otherwise non-local seats → `pending:<id>`. iOS sends `kind ∈ you|open|bot` |
| `maxPlayers` | number | **ignored**; seat count is used |
| `rules` | object | required (400 `invalid_engine_configuration`); opaque `PreferansRules`; replaced for public |
| `match` | object | required; opaque `MatchSettings`; for public only `match.poolTarget` is read |
| `variant` | string? | truncated to 32; public requires `odesa|wien|thessaloniki` (400 `invalid_public_variant`) |

Public-only checks: no bot seats (400 `public_humans_only`); `poolTarget` safe integer in `1…seats×999` and, unless `wien`, divisible by seat count (400 `invalid_pool_target`).

Behavior: up to 5 random codes; per attempt `PreferansTable(CODE)/create` → `createInitialRoom` → engine `/v1/games` → creator library upsert (3 s) → commit. A code already in use returns 409 `room_exists` internally and the Worker retries; after 5 collisions the last 409 `room_exists` is returned (the 503 fallback in code is unreachable).

Response **200** `RoomWithSocketURL` (caller view, creator `seatToken`). Example (abridged):

```json
{"visibility":"private","readyPlayerIDs":[],"schemaVersion":4,"roomCode":"K7M2Q9",
 "hostPlayerID":{"rawValue":"north"},"hostEpoch":1,
 "peers":[{"playerID":{"rawValue":"north"},"accountID":"guest:…","provider":"guest","displayName":"Ada"},
          {"playerID":{"rawValue":"east"},"accountID":"bot:east","provider":"dev","displayName":"Bot 2"},
          {"playerID":{"rawValue":"south"},"accountID":"pending:south","provider":"dev","displayName":"Open seat"}],
 "maxPlayers":3,"createdAt":"…","updatedAt":"…","relaySequence":0,"status":"lobby",
 "summary":{"variant":"odesa","lastSequence":0,"phase":"waitingForDeal","dealNumber":1},
 "authoritativeTableID":"…","seatToken":"<24 chars>",
 "websocketURL":"wss://<host>/v2/rooms/K7M2Q9/socket?playerID=north&seatToken=<24 chars>"}
```

Errors: 400 (`invalid_visibility`, `invalid_seats`, `invalid_player_id`, `invalid_engine_configuration`, `public_humans_only`, `invalid_public_variant`, `invalid_pool_target`, `duplicate_player`, `duplicate_account`, `room_full`, `invalid_max_players`), 401, 409 `room_exists`, 503 `lobby_unavailable`, engine errors (503 `engine_unavailable`, 409/502 `engine_rejected_command`, 502 `engine_invalid_response`, 503 `engine_version_mismatch`), account-index errors (`account_index_failed` or the account DO's code), 429.

Client checks (`CloudflareRoomTransport.createRoom`): `schemaVersion == 4`; for public requests `visibility == "public"` in the reply; the caller's seat present (matched by `accountID`); `seatToken` non-empty; `websocketURL` present; `relaySequence ≥ 0`.

### `POST /v2/rooms/{code}/join`

Auth: Bearer. Request `{"requestedPlayerID": PlayerID}` (optional preference). Behavior (`joinRoom`): held seat → same seat, refreshed display fields, rotated token (+ readiness cleared for that seat); else requested open seat or first open seat (lobby only), new token, all readiness cleared, pending library removal for this account cancelled. Lobby rooms rebuild the engine game at sequence 0. Old sockets of that seat close with 4009 `seat_replaced`.

Response **200** `RoomWithSocketURL` (caller view; caller's token; socket URL for the *assigned* seat).

Errors: 404 `room_not_found`, 410 `room_upgrade_required`, 409 `room_full`, 409 `room_in_progress`, 500 `invalid_join`, engine/account-index errors, 401, 429.

### `GET /v2/rooms/{code}`

Auth: **none**. Response **200** `PublicRoom` with no caller (all humans masked, in public and private rooms). Errors: 404, 410.

### `POST /v2/rooms/{code}/seats/fill-bots`

Auth: Bearer + seat proof. Request `{"playerID": PlayerID, "seatToken": string}`; caller must be the current manager (`authorizeHostSeat`).

Response **200** `PublicRoom` (anonymous view). Converts every `pending:` seat to `bot:<seat>` "Bot N" and rebuilds the game; no-op (same room, no broadcast) if no open seat.

Available at private and public waiting tables. A change clears human readiness.
Errors: 409 `room_in_progress`, 403 `unknown_player` / `seat_credential_invalid` / `forbidden`, 404, 410.

### `POST /v2/rooms/{code}/seats/bot`

Auth: Bearer + current manager seat proof. Request `{playerID, seatToken,
targetPlayerID, difficulty}`. The target must be an open or bot seat in the lobby
at sequence zero. Difficulty is `casual`, `seasoned`, `expert`; explicit null
removes a bot. Omitted/invalid difficulty is rejected. Joined humans cannot be
replaced, even when disconnected. Works at public and invite-only tables.

Response **200** PublicRoom. The chosen difficulty persists as optional
`OnlinePeer.botDifficulty`; legacy bots default to seasoned. The existing Swift
engine is rebuilt with that profile before durable commit. No-op edits preserve
Ready; real edits clear it for all humans. Bots never require Ready themselves.
Engine failure does not save the proposed change. No cards are dealt implicitly.

Errors: 400 `invalid_seat` / `invalid_player_id` / `invalid_bot_difficulty`,
409 `seat_occupied` / `room_in_progress`, 403 invalid host proof; existing engine
errors also apply. All mutations use the same room queue as join and start.

### `POST /v2/rooms/{code}/ready`

Auth: Bearer + seat proof. Request `{"playerID", "seatToken", "ready": boolean}`. Requires a human seat owned by the caller (403 `forbidden`), a public room in `lobby` (409 `table_in_progress`), a boolean (400 `invalid_ready`), and a live socket for that seat (409 `not_connected` "Reconnect before confirming readiness.").

Response **200** `PublicRoom` (anonymous view). The iOS client ignores this body and waits for the ordered `presence` frame.

### `POST /v2/rooms/{code}/leave`

Auth: Bearer + seat proof. Request `{"playerID", "seatToken"}`. Public `lobby` tables only (409 `table_in_progress`). Effects: seat → `pending:` "Open seat", `readyPlayerIDs = []`, account added to `libraryRemovalAccountIDs`, manager re-elected from remaining humans or room abandoned if none, game rebuilt if still lobby, leaver's sockets closed 4011 `seat_left`.

Response **200** `PublicRoom` (anonymous view).

### `POST /v2/rooms/{code}/abandon`

Auth: Bearer + seat proof. Request `{"playerID", "seatToken"}`; caller must own that human seat (any seat, not only manager). Effect: `status = abandoned`, private state and projections dropped; idempotent on terminal rooms.

Response **200** `PublicRoom`. Errors: 403 (`unknown_player`, `seat_credential_invalid`, `forbidden`), 404, 410.

### `GET /v2/rooms/{code}/socket`

WebSocket upgrade; see [realtime-messages.md](realtime-messages.md). Query `playerID`, `seatToken`. Responses: **101**; **426** `{"error":"Expected WebSocket upgrade."}` without `Upgrade: websocket`; **403** credential errors; **404**; **410**.

### Removed routes

| Route | Response |
| --- | --- |
| `POST /v2/rooms/{code}/state` | **410** `{"code":"client_state_removed","error":"Schema-v3 rooms do not accept client-authored game state."}` (no auth) |
| `GET /v2/rooms/{code}/snapshot` | **410** `{"code":"client_snapshot_removed","error":"Schema-v3 rooms resume from server projections, not engine snapshots."}` |
| Any other unmatched path | **404** `{"error":"Not found."}` |
| Matched path, wrong method | **405** `{"error":"Method not allowed."}` |

### `GET /.well-known/apple-app-site-association` and `GET /apple-app-site-association`

Auth: none. **200** `application/json; charset=utf-8`:

```json
{"applinks":{"details":[{"appIDs":["<TEAMID>.com.mixandmatch.preferans"],"components":[{"/":"/join/*","comment":"Preferans room invite links"}]}]}}
```

### `GET /join/{code}`

Auth: none. **200** `text/html` invite landing page; see [invite-links.md](invite-links.md). Invalid code → **400** `invalid_room_code` JSON.

---

## Internal Durable Object routes (not client-reachable)

| DO | Route | Purpose |
| --- | --- | --- |
| `PreferansTable` | `POST /create`, `POST /join`, `POST /seats/fill-bots`, `POST /ready`, `POST /leave`, `POST /abandon`, `POST /account-deleted {accountID}`, `GET /summary`, `GET …/socket`, `POST /state` (410), `GET /snapshot` (410) | Room operations (all via `MutationQueue`) |
| `PlayerAccountV2` | `POST /register {accountID, provider, displayName}` → 201, `POST /authenticate {sessionToken}`, `POST /upsert GameSummaryEntry`, `POST /remove {roomCode}`, `GET /list`, `DELETE /delete` → 204 | Account and library |
| `PublicTableDirectory` | `POST /publish {roomCode, revision, table?}`, `GET /list?…` | Directory |

## Error code index

| Code | HTTP | Raised by |
| --- | --- | --- |
| `unauthorized` | 401 | `bearerToken`, `parseSessionToken`, `authenticateSession` |
| `account_not_found` / `account_upgrade_required` | 401 | `PlayerAccountV2.loadRequired`, `authenticateSession` |
| `account_conflict` | 409 | `/register` |
| `invalid_provider`, `invalid_account`, `invalid_display_name` | 400 | account state |
| `invalid_apple_identity` / `apple_unavailable` | 401 / 503 | `apple-auth.ts` |
| `rate_limited` | 429 (HTTP) / error frame (socket) | router / socket |
| `message_too_large` | 413 | `readJSON`, `parseSocketPayload` |
| `invalid_json`, `invalid_socket_json` | 400 | parsing |
| `invalid_room_code`, `invalid_player_id`, `invalid_peer`, `invalid_seats`, `invalid_visibility`, `invalid_engine_configuration`, `invalid_max_players`, `duplicate_player`, `duplicate_account` | 400 | validation |
| `public_humans_only` | 400 (initial create) | public seat intents |
| `invalid_public_variant`, `invalid_pool_target` | 400 | `publicConfiguration` |
| `lobby_unavailable` | 503 | missing `LOBBY` binding |
| `room_exists` | 409 (after 5 attempts) | create |
| `room_not_found` | 404 | `loadRequiredRoom` |
| `room_upgrade_required` | 410 | `loadRequiredRoom` |
| `room_full`, `room_in_progress` | 409 | `joinRoom`, `fillOpenSeatsWithBots` |
| `invalid_host`, `invalid_join` | 500 | create/join invariants |
| `unknown_player`, `seat_credential_invalid`, `forbidden` | 403 | `authorizeSeat`, `authorizeHostSeat`, seat ownership |
| `table_in_progress`, `readiness_unavailable`, `not_connected` | 409 | ready/leave |
| `invalid_ready` | 400 | ready |
| `invalid_account` | 400 | `/account-deleted` |
| `client_state_removed`, `client_snapshot_removed` | 410 | removed routes |
| `room_busy` | 503 | `MutationQueue` (> 64 pending) |
| `engine_configuration_missing`, `engine_state_missing` | 409 | engine adapter |
| `engine_unavailable` | 503 | `callEngine` (network/timeout) |
| `engine_rejected_command` | 409 (engine 4xx) / 502 (engine 5xx) | `callEngine` |
| `engine_invalid_response` | 502 | `adoptingEngineResponse` |
| `engine_version_mismatch` | 503 | engine adapter |
| `room_cleanup_failed`, `account_error`, `account_index_failed` | varies | account deletion / library |
| `internal_error` | 500 | fallback |

Socket-only codes (`table_closed`, `protocol_mismatch`, `invalid_command`, `command_id_conflict`, `lobby_manager_required`, `room_not_ready`, `players_not_ready`, `client_authority_removed`, `unknown_socket_message`, `relay_sequence_exhausted`) are listed in [realtime-messages.md](realtime-messages.md). `bot_stalled` (503) is raised and swallowed inside `PreferansTable.alarm` (it only bumps `retryCount`) and never reaches a client.
