# Contract: Game Wire Messages (`GameWireMessage`, schema 4)

**Implementation**: `Sources/PreferansEngine/Online/GameWireMessage.swift`, `Sources/PreferansEngine/Projection/*`. **Encoders**: `PreferansJSONCoder` (app, ISO-8601 dates), `AuthoritativeGameService` (server, ISO-8601), Hummingbird default (server responses). **Worker view**: opaque JSON except the fields named below (`authoritative-engine.ts` `clientActionFromWireMessage`, `isStartDealCommand`, `projectionWireMessage`).

`PreferansWireSchema.current = 4` ("Server-authoritative online protocol. Version 4 is a clean break from the client-hosted v2 room model"). Every envelope carries `schemaVersion` and the decoders for `SeatAssignmentEnvelope` and `ProjectionEnvelope` **require** it (no default), so pre-v4 frames fail to decode (`WireCompatibilityTests.testSeatAssignmentRequiresTheCurrentWireSchema`, `testProjectionEnvelopeRequiresTheCurrentWireSchema`). Other envelopes use synthesized `Codable`, where the defaulted `schemaVersion` property is still a required key on decode.

Swift synthesized enum encoding: `GameWireMessage.clientAction(x)` ⇄ `{"clientAction": {"_0": x}}`.

## Message catalogue

| Case | Direction (production) | Direction (legacy in-memory room) | Worker handling |
| --- | --- | --- | --- |
| `clientAction(ClientActionEnvelope)` | client → server | client → host | Command (`relayWireMessage`) |
| `resyncRequest(ResyncRequestEnvelope)` | client → server (accepted; current iOS production client does not send it) | client → host | Re-send sender's projection (only the presence of an object is checked) |
| `projection(ProjectionEnvelope)` | server → client | host → client | Produced by the Worker from stored projections |
| `hello(HelloEnvelope)` | — | client → host | Rejected `client_authority_removed` |
| `seatAssignment(SeatAssignmentEnvelope)` | — | host → clients | Rejected |
| `hostError(HostErrorEnvelope)` | — | host → client | Rejected |
| `ping(PingEnvelope)` | — | client ⇄ host (heartbeat) | Rejected (socket-level `{"type":"ping"}` is different) |

## `ClientActionEnvelope`

| Field | Type | Required | Semantics |
| --- | --- | --- | --- |
| `schemaVersion` | Int | yes | Must equal room schema 4 (`protocol_mismatch`) |
| `tableID` | UUID | yes | Must equal `authoritativeTableID` (`protocol_mismatch`) |
| `actor` | PlayerID | yes | Seat the action speaks for (`action.actor ?? localSeat`) |
| `action` | `PreferansAction` | yes | See below |
| `clientNonce` | UUID | yes | Command ID; idempotency key (Worker: per account; engine: last 16) |
| `baseHostSequence` | Int ≥ 0 | yes | Revision the client saw; engine requires equality with its `sequence` (`staleSequence`) |
| `sentAt` | Date (ISO-8601) | yes (Swift decode) | Not used by the server; excluded from fingerprint |

`PreferansAction` cases (owned by [`../../001-game-rules`](../../001-game-rules)): `startDeal(dealer?, deck?)`, `bid(player, call)`, `discard(player, cards)`, `declareContract(player, contract)`, `concedeWithoutThree(player)`, `whist(player, call)`, `chooseDefenderMode(player, mode)`, `playCard(player, card)`, `proposeSettlement(player, settlement)`, `acceptSettlement(player)`, `rejectSettlement(player)`.

Authorization (engine, `AuthoritativeGameService.authorize`): if `action.actor` exists it must equal `actor` (`duplicateActor`); the authenticated `sender` (seat derived by the Worker from the socket, never from the message) must equal `engine.controllingActor(of: action.actor ?? actor)` (`unauthorizedActor`). `startDeal` has no actor; it is additionally restricted to the lobby manager by the Worker and its `dealer`/`deck` are replaced by the server.

## `ProjectionEnvelope`

| Field | Type | Semantics |
| --- | --- | --- |
| `schemaVersion` | Int (required) | 4 |
| `tableID` | UUID | |
| `sequence` | Int | Engine revision; equals `projection.sequence` |
| `viewer` | PlayerID | Seat this projection is for; equals `projection.viewer` |
| `projection` | `PlayerGameProjection` | Redacted per [../data-model.md § Visibility matrix](../data-model.md#visibility-matrix) |
| `eventSummaries` | [String] (default `[]`) | Server always sends `[]` |
| `events` | [`PreferansEvent`] (default `[]`) | Events emitted by *this* transition, redacted by `OnlineEventProjection` (`[]` for create; a stored projection re-sent on reconnect or for a duplicate command still carries the events of the transition that produced it) |
| `botInsights` | [`BotDecisionExplanation`] (default `[]`) | Rolling window (≤ 20) of public-safe bot rationale; same for every viewer |

Client acceptance (`ServerGameCoordinator.receive`): `authority == .server`; `schemaVersion == 4`; `tableID == attached tableID`; `viewer == localPeer.playerID`; `projection.tableID == tableID`; `projection.viewer == viewer`; `projection.sequence == sequence`; `sequence ≥ current`. Newer → replace projection, append events (keep last 100), replace `botInsights`, start a 2.4 s completed-trick hold if applicable. Equal and 0 → replace (lobby rebuild). Equal and > 0 → ignored.

Legacy policy (`RoomInboundMessagePolicy.projectionDecision`): `reject` / `refresh` (same sequence: replace insights, append activity once per frame) / `advance`.

## `ResyncRequestEnvelope`

`{schemaVersion, tableID, requester: PlayerID, lastSeenSequence: Int}`. Worker ignores the contents (only checks that `message.resyncRequest` is an object) and re-sends the socket seat's projection. Legacy host validates schema, `lastSeenSequence ≥ 0`, table and `requester == sender`.

## Legacy-only envelopes (in-memory room)

| Envelope | Fields | Legacy semantics |
| --- | --- | --- |
| `HelloEnvelope` | `schemaVersion, tableID?, player: PlayerIdentity, lastSeenSequence` | Client announces itself; host answers with `seatAssignment` + full projection |
| `SeatAssignmentEnvelope` | `schemaVersion (required), tableID, hostPlayerID, seats: [PlayerIdentity], rules, match (decodeIfPresent → .unbounded)` | Host roster; accepted only from the elected host, 3–4 unique seats including local and host, non-empty unique `gamePlayerID`s and display names |
| `HostErrorEnvelope` | `schemaVersion, tableID, sequence, recipient?, clientNonce?, message` | Host rejection; accepted if table matches, `sequence ≥ current`, recipient nil or local |
| `PingEnvelope` | `schemaVersion, tableID?, sentAt` | Heartbeat every 3 s; host echoes; client marks host unreachable after 10 s of silence |

## Compatibility rules

1. Room/wire schema and account schema are independent: wire/room **4**, account **2** (`AppIdentifiers.gameWireSchemaVersion`, `onlineAccountSchemaVersion`).
2. The app checks `GET /health` before every create/join and validates `schemaVersion == 4` in every room payload and `room`/`presence` frame.
3. The Worker refuses rooms stored with another schema (`room_upgrade_required` 410) and commands with another schema (`protocol_mismatch`).
4. The Worker pins `ENGINE_VERSION = "preferans-1"`; engine responses with another version are rejected and saved tables with another version fail closed (503). "New incompatible rules require a new engine version and explicit room routing" (`docs/MULTIPLAYER.md`).
5. `MatchSettings.poolTarget == Int.max` (unbounded) is omitted on encode and defaults to unbounded on decode (`Sources/PreferansEngine/MatchSettings.swift`), so no unsafe JavaScript integer crosses the Worker.
6. The private engine state crosses the Worker only as a JSON **string** so 64-bit seeds are not coerced to JavaScript numbers (`RoomState.authoritativeState` comment).
7. The Swift⇄Worker create payload is pinned by `workers/room-worker/fixtures/create-game.json` and `AuthoritativeGameServiceTests.testCheckedInWireFixtureMatchesSwiftCodec`; public rule presets by `fixtures/public-rules.json` and `PublicTableRulesTests` (`odesa == .sochi`, `wien == .leningrad`, `thessaloniki == .rostov`).
8. `WireCompatibilityTests.testEveryWireMessageRoundTripsThroughConfiguredJSONCoder` round-trips every case through `PreferansJSONCoder`.
