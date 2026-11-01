# Contract: Table WebSocket (realtime messages)

**Implementation**: `workers/room-worker/src/index.ts` — `PreferansTable.connectWebSocket`, `webSocketMessage`, `webSocketClose`, `webSocketError`, `relayWireMessage`, `sendToPlayers`, `broadcastPresence`, `sendProjectionToPlayer/ToSocket`. **Client**: `Preferans/Online/CloudflareRoomTransport.swift` (`ClientSocketEnvelope`, `ServerSocketEnvelope`, `handleSocketMessage`, `maintainConnection`, `openSocket`).

Transport: a single **WebSocket** per seat per device using Cloudflare's hibernatable WebSocket API (`ctx.acceptWebSocket`, per-socket `serializeAttachment`). There is no SSE and no HTTP polling for game state. All frames are UTF-8 JSON text (the client also accepts binary JSON).

## Connection

`GET {ws|wss}://<host>/v2/rooms/<CODE>/socket?playerID=<seat>&seatToken=<token>` with `Upgrade: websocket`.

- The URL is built by the server (`withSocketURL`) and returned by create/join; the client treats it as opaque.
- Authorization: `authorizeSeat(room, playerID, seatToken)` — unknown seat → 403 `unknown_player`; seat without token, missing token or mismatch → 403 `seat_credential_invalid`.
- Attachment stored on the socket: `{playerID, seatToken, connectedAt, windowStart?, commandCount?}`.

On accept, in order (inside the table's `MutationQueue`):

1. Close every *other* socket attached to the same `playerID` with **4009 `seat_replaced`**.
2. `reconcileHost` — re-elect the manager if the current one has no live socket (commit + presence + library fan-out if changed).
3. Send `room` frame to this socket.
4. Send this seat's stored projection (`wire`, `authority: "server"`) if one exists — no engine call.
5. Broadcast `presence` to all sockets.

## Client → server frames

```ts
{ type: "wire" | "ping", recipients?: PlayerID[], reliable?: boolean, message?: GameWireMessage }
```

| `type` | Fields | Semantics |
| --- | --- | --- |
| `wire` | `message` (required); `recipients`/`reliable` sent by iOS but **ignored** by the server | `message.clientAction._0` → command (below). `message.resyncRequest` (object) → server re-sends the sender's current projection. Any other message → `error` `client_authority_removed` (409) |
| `ping` | — | Server replies `{"type":"pong","sentAt":"<ISO>"}`. The iOS app does **not** send this; it uses WebSocket protocol pings every 15 s |

Example command frame (as produced by `CloudflareRoomTransport.sendToAll(.clientAction(...))`):

```json
{"type":"wire","reliable":true,"message":{"clientAction":{"_0":{
  "schemaVersion":4,"tableID":"6B1C…","actor":{"rawValue":"east"},
  "action":{"bid":{"player":{"rawValue":"east"},"call":{"pass":{}}}},
  "clientNonce":"0F6A…","baseHostSequence":3,"sentAt":"2026-10-31T13:27:40Z"}}}}
```

Start-deal command: `"action":{"startDeal":{}}` (dealer and deck are ignored and replaced by the engine).

### Per-frame checks (in order)

1. Load room (`room_not_found` / `room_upgrade_required`).
2. Re-authorize the socket's attachment against the *current* seat token. Failure → `error` frame; a `seat_credential_invalid` failure additionally closes the socket with **4009**.
3. Rate window: if `now − windowStart > 10 000 ms` reset; `commandCount += 1`; if `> 30` → `error` `rate_limited` (frame dropped).
4. Size ≤ 131 072 bytes (`message_too_large`) and JSON object (`invalid_socket_json`); unknown `type` → `unknown_socket_message`.

### Command processing (`relayWireMessage`)

1. `commandIdentity(sender.accountID, command)`: `clientNonce` must be a UUID (`invalid_command`); key `command:<accountID>:<nonce>`; fingerprint over `{sender, tableID, schemaVersion, actor, action, baseSequence}`.
2. If a stored command exists → send stored receipt (or a *transient* `rejected` receipt with `code: "command_id_conflict"`, `message: "This command ID was used for another action."` when the fingerprint differs), then the sender's current projection. Done.
3. Inside a try block:
   - status `finished`/`abandoned` → `table_closed` (409);
   - `startDeal` → `validateStartDealAuthority`: sender must be manager (`lobby_manager_required`, 403); no `pending:` seat (`room_not_ready`, 409); every non-bot seat connected (`room_not_ready`, 409); public lobby: every seat Ready (`players_not_ready`, 409);
   - `applyAuthoritativeCommand`: engine version (`engine_version_mismatch` 503), state present (`engine_state_missing` 409), `schemaVersion == 4` and `tableID == authoritativeTableID` (`protocol_mismatch` 409), actor/nonce/`baseHostSequence` (`invalid_command` 400), action present; `POST /v1/commands`; validate response;
   - `recordRelay` (relaySequence + 1; `relay_sequence_exhausted` 409 if the counter is not a safe non-negative integer).
4. On `RoomStateError` with status < 500 → store and send `rejected` receipt (`sequence` = current engine sequence) + sender's projection.
5. On any other error → nothing stored; error propagates → `error` frame to the sender.
6. On success → `commitRoom` (alarm + transaction {room, receipt, checkpoint}) → `accepted` receipt to sender → projections to every human seat → presence broadcast.

## Server → client frames

All carry `type`. The iOS decoder (`ServerSocketEnvelope`) accepts exactly `receipt | room | presence | wire | error | pong`; any other `type` fails decoding and the client treats the socket as broken and reconnects.

### `room`

Sent once to the connecting socket.

| Field | Type | Notes |
| --- | --- | --- |
| `room` | `PublicRoom` | Caller view (`publicRoom(activeRoom, peer.accountID)`) |
| `connectedPlayerIDs` | `PlayerID[]` | Seats with an open socket |

Client acceptance: `room.schemaVersion == 4`, `hostEpoch ≥ known`, `relaySequence ≥ lastRelaySequence` → adopt participants, settings, readiness, connected set, host, epoch, and raise the relay floor. `status == "abandoned"` → `tableAbandoned` event regardless.

### `presence`

Broadcast to every socket after joins, connects, closes, commands, bot moves, readiness changes, leaves, abandons and account deletions.

| Field | Type | Notes |
| --- | --- | --- |
| `room` | `PublicRoom` | Per-socket caller view (resolved only when the socket's token is current; otherwise anonymous) |
| `connectedPlayerIDs` | `PlayerID[]` | |

Client acceptance: schema 4 and `hostEpoch ≥ known` (no relay-sequence check, because presence is broadcast while `wire` is targeted). Missing `connectedPlayerIDs` → client assumes only itself is connected (fails closed for Start). Public rooms: each broadcast also bumps `directoryRevision` and marks `directoryDirty`.

### `wire` (server projection)

```json
{"type":"wire","authority":"server",
 "sender": <OnlinePeer: room.peers[0], masked for public rooms>,
 "message":{"projection":{"_0": <ProjectionEnvelope>}},
 "serverSequence": <room.relaySequence>, "sentAt":"<ISO>"}
```

- Sent only to the projection's own seat and only on sockets whose attachment token equals the seat's current token.
- `ProjectionEnvelope` is described in [game-wire-messages.md](game-wire-messages.md). Public rooms re-mask `projection.identities[].gamePlayerID` to `seat:<CODE>:<seat>` at delivery.
- `sender` is informational; trust derives from `authority: "server"`.
- Client: `serverSequence` raises the relay floor (`max`); the frame is forwarded as `ReceivedRoomMessage(authority: .server)`; `ServerGameCoordinator.receive` accepts it if schema 4, matching table and viewer, consistent inner projection, and `sequence ≥ current` (equal sequence only refreshes when it is 0).

### `receipt`

```json
{"type":"receipt","receipt":{"tableID":"UUID","clientNonce":"uuid","sequence":1,"status":"accepted"}}
{"type":"receipt","receipt":{"tableID":"UUID","clientNonce":"uuid","sequence":5,"status":"rejected",
  "code":"engine_rejected_command","message":"Stale command sequence. Expected 5, got 4."}}
```

Sent only to the sender seat. Client: emits `.commandReceipt`; `ServerGameCoordinator` resolves the pending command only if `tableID` and `clientNonce` match.

### `error`

```json
{"type":"error","error":"<message>","code":"<code>"}
```

Client: `seat_credential_invalid` → `.seatTakenOver`; any other → `.serverError(message)` (shown as `errorText`; pending command keeps retrying).

### `pong`

`{"type":"pong","sentAt":"<ISO>"}` — ignored by iOS.

## Close codes

| Code | Reason | Trigger | iOS handling |
| --- | --- | --- | --- |
| 4009 | `seat_replaced` | Another socket connected for the seat; `/join` rotated the seat's token; a frame failed `seat_credential_invalid` | `.seatTakenOver`, "This table was opened on another device.", reconnect loop ends |
| 4010 | `account_deleted` | Seat's account deleted | Treated as a transient drop → reconnect (which then fails 403) |
| 4011 | `seat_left` | Seat owner called `/leave` | Same as above |
| other / network | — | — | `.reconnecting`, backoff |

## Ordering, revisioning and delivery guarantees

- **Serialization**: every frame, HTTP mutation, close/error callback and alarm on a table runs through one FIFO `MutationQueue` (≤ 64 pending). Within a table, effects are totally ordered.
- **Commit-before-deliver**: receipts and projections are sent only after the storage transaction resolves; sends are best-effort (`try { socket.send } catch {}`); recovery is by reconnect (stored projection) and command retry (stored receipt).
- **Counters**: engine `sequence` (+1 per human command and per bot move) is the authoritative revision and the client's acceptance gate; `relaySequence` (+1 per accepted human command) is echoed as `serverSequence`; `hostEpoch` (+1 per manager change) gates roster frames.
- **No replay log**: the room stores no message history (`recordRelay` returns an entry that is discarded); a reconnecting client receives only the latest projection, not intermediate events.
- **One controller per seat**: only the newest socket for a seat stays open; only sockets presenting the current token receive private frames.

## Client connection management (`CloudflareRoomTransport`)

| Behavior | Value |
| --- | --- |
| First socket | opened synchronously on first `messages()`/`participantUpdates()`/send |
| Keepalive | `sendPing` every 15 s; cancel socket if no pong within 10 s |
| `connected` event | on the first frame received on each new socket (resets backoff, clears `lastError`) |
| Reconnect delay | `min(0.5 s × 2^(attempt−1), 8 s)` + uniform 0–30 % jitter (0.5, 1, 2, 4, 8, 8… s) |
| Terminal | close 4009 (`isClosed = true`), explicit `disconnect()` (`goingAway`) |
| Outbound restriction | only `.clientAction` and `.resyncRequest`; anything else throws "Online clients may only send commands or resync requests." |
| Streams | `messages()` (per subscriber), `participantUpdates()` (replays current roster on subscribe), `connectionEvents()` (replays `latestConnectionEvent`) |

`RoomTransportEvent`: `connected`, `reconnecting`, `seatTakenOver`, `serverError(String)`, `commandReceipt(OnlineCommandReceipt)`, `tableAbandoned`.
