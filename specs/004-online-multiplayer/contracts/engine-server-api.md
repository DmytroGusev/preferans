# Contract: Swift Authoritative Engine Server (`PreferansServer`)

**Implementation**: `Sources/PreferansServer/main.swift` (Hummingbird router), `Sources/PreferansServerCore/AuthoritativeGameService.swift`. **Caller**: `workers/room-worker/src/authoritative-engine.ts` (`callEngine`, `createAuthoritativeGame`, `applyAuthoritativeCommand`, `adoptingEngineResponse`) and `PreferansTable.alarm` (`/v1/bots`). Not reachable by clients.

- Process: Hummingbird `Application` bound to `0.0.0.0:$PORT` (default **8080**). Image: `Dockerfile.server`.
- Deployment: Cloudflare Container class `PreferansEngineContainer` (`defaultPort = 8080`, `sleepAfter = "10m"`, `max_instances = 3`); the Worker picks an instance with `getRandom(env.ENGINE, 3)` and posts to `http://engine<path>` with `content-type: application/json` and an **8 s** abort timeout. Locally `LocalPreferansTable` posts to `http://127.0.0.1:18081<path>`.
- Statelessness: every request carries the complete opaque state; the server keeps nothing between requests. Any instance can serve any table.
- Errors: `/v1/games` and `/v1/commands` wrap every thrown error as `HTTPError(.badRequest, message: error.localizedDescription)` → **400** (Hummingbird error JSON; the Worker reads `message`, `error`, or `error.message`). `/v1/bots` does not wrap engine errors → **500** (body decode failures are 400).
- Worker mapping (`callEngine`): network failure/timeout → `engine_unavailable` 503 (retryable); non-2xx or non-JSON → `engine_rejected_command` with **409** if the engine status was 4xx (deterministic → durable rejected receipt) else **502** (retryable).

## `GET /health`

**200** `{"ok": true, "service": "preferans-authoritative-engine", "stateSchemaVersion": 2}`. Used by `bin/dev-online` (30 × 1 s) and `owner-server-build.yml` (20 × 1 s).

## `POST /v1/games` — create a table

Request `CreateAuthoritativeGameRequest`:

| Field | Type | Notes |
| --- | --- | --- |
| `tableID` | UUID \| null | Reused on lobby rebuilds; new UUID when null |
| `identities` | `[PlayerIdentity]` | `{playerID, gamePlayerID, displayName}` in seat order (3–4). Public rooms: `gamePlayerID = "seat:<CODE>:<seat>"` |
| `rules` | `PreferansRules` | Client-chosen (private) or preset (public) |
| `match` | `MatchSettings` | `poolTarget` omitted = unbounded |
| `firstDealer` | PlayerID \| null | Worker sends `peers[0].playerID` |
| `botProfiles` | `[PlayerID: BotProfile]` encoded as `[PlayerID, BotProfile, …]` | Worker sends `{difficulty:"seasoned", temperament:"adaptive"}` for each `bot:` seat |

Fixture: `workers/room-worker/fixtures/create-game.json` (3 seats, `poolTarget 6`, `tableTotal`, Sochi-equivalent rules).

Behavior: `PreferansEngine(players:rules:match:firstDealer:)`; state at `sequence 0`, `dealSeed = UInt64.random(in: .min ... .max)`.

Response **200** `AuthoritativeGameResponse` (below) with `status: "lobby"`, `phase: "waitingForDeal"`, `dealNumber: 1`, `events: []` in every projection.

## `POST /v1/commands` — apply one human command

Request `AuthoritativeCommandRequest`:

| Field | Type | Notes |
| --- | --- | --- |
| `state` | string | Previous opaque `AuthoritativeGameState` JSON |
| `sender` | PlayerID | Seat derived by the Durable Object from the authenticated socket |
| `actor` | PlayerID | From the client envelope |
| `action` | `PreferansAction` | From the client envelope |
| `clientNonce` | UUID | |
| `baseSequence` | Int | Client's `baseHostSequence` |

Algorithm (`AuthoritativeGameService.apply`):

1. Decode state; `schemaVersion == 2` else `invalidSchema`.
2. `actor ∈ engine.players` else `unknownPlayer`.
3. `authorize`: `action.actor` (if any) == `actor` else `duplicateActor`; `sender == controllingActor(of: action.actor ?? actor)` else `unauthorizedActor`.
4. If `clientNonce` is among the last 16 applied nonces: identical `{sender, actor, action, baseSequence}` → return the unchanged state with no events; otherwise `commandIDConflict`.
5. `baseSequence == state.sequence` else `staleSequence(expected, actual)`.
6. `startDeal` → `startDeal(dealer: snapshot.nextDealer, deck: Deck.shuffled(seed: dealSeed &+ generatedDealCount &* 0x9E3779B97F4A7C15))`, `generatedDealCount += 1`.
7. `engine.apply(action)` (illegal moves throw the engine's error), `sequence += 1`, append nonce (trim to 16), store snapshot.
8. **No bot moves are run** here; `botPending` signals the Worker.

Errors (all 400): `"Unsupported authoritative game schema N."`, `"Unknown player X."`, `"Command actor mismatch. Expected A, got B."`, `"Authenticated sender B cannot control A."`, `"Command ID was already used for a different command."`, `"Stale command sequence. Expected E, got A."`, plus engine rule errors (see [`../../001-game-rules`](../../001-game-rules)).

## `POST /v1/bots` — advance exactly one bot move

Request `{"state": "<opaque>"}`.

Algorithm (`advanceBot`/`advanceBots`): if the current actor's controlling seat has a bot profile, run `HeuristicStrategy(profile:).decision(snapshot:viewer:)`, repair via `BotDecisionRecovery.recover` (else `botStalled`), apply it, `sequence += 1`, append the explanation to `botInsights` (keep 20), and **stop after one action** ("pacing and continuation belong to the durable room alarm"). Guard `maximumBotActionsPerCommand = 512` → `botActionLimit`. If no bot is on turn the state is returned unchanged; the Worker then raises `bot_stalled` because `sequence` did not advance by exactly 1.

Response **200** `AuthoritativeGameResponse`.

## `AuthoritativeGameResponse`

| Field | Type | Notes |
| --- | --- | --- |
| `engineVersion` | string | `"preferans-1"`; Worker rejects others (`engine_version_mismatch`) |
| `botPending` | Bool | Current actor's controller has a bot profile |
| `state` | string | New opaque state (non-empty) |
| `sequence` | Int ≥ 0 | New revision |
| `projections` | `[ProjectionEnvelope]` | Exactly one per seat, built with `ProjectionPolicy.online`, `eventSummaries: []`, `events` redacted per viewer, `botInsights` |
| `status` | `"lobby" \| "playing" \| "finished"` | `waitingForDeal` & sequence 0 → lobby; `gameOver` → finished; else playing |
| `dealNumber` | Int | `engine.dealsPlayed + 1` |
| `phase` | string | `projections.first.projection.phase.token` (fallback `waitingForDeal`) |
| `result` | `{winner?: PlayerID, finalBalances: {seat: Double}}`? | Only when `status == finished`: `MatchSummary.soleWinner` (absent on a shared lead) and every seat's final normalized balance (`AuthoritativeGameResult`) |

Worker validation (`adoptingEngineResponse`) — any failure → `engine_invalid_response` 502, nothing committed:

- `botPending` boolean, `status` ∈ {lobby, playing, finished}, `state` non-empty string, `sequence` non-negative safe integer;
- every projection's `viewer` is a room seat, no duplicates, count == seat count;
- every projection's `sequence == response.sequence` and all share one string `tableID`;
- `tableID` equals the stored `authoritativeTableID` (if any);
- outside the lobby `sequence ≥ authoritativeSequence`.

On adoption: `authoritativeState = (status == finished ? undefined : state)`, `authoritativeSequence`, `authoritativeTableID`, `authoritativeProjections` (masked in every room), `status`, `botPending`, `summary {variant, lastSequence, phase, dealNumber, result}` (`result` only when finished and valid, `matchResult`).

## Test evidence

`Tests/PreferansServerCoreTests/AuthoritativeGameServiceTests.swift`: `testCheckedInWireFixtureMatchesSwiftCodec`, `testCompleteThreeAndFourSeatMatchesThroughServerBoundary`, `testExchangeEventsDoNotExposeDiscardToOtherSeats`, `testNonceCannotBeReusedForDifferentPayload`, `testServerCreatesAndAdvancesAnAuthoritativeGame`, `testAuthenticatedSenderCannotClaimAnotherActor`, `testDuplicateNonceIsIdempotent`, `testServerRunsBotSeatsUntilAHumanMustAct`; `PublicTableRulesTests.testWorkerPublicPresetsMatchTheActualSwiftScoringRules`; Worker `test/authoritative-engine.test.ts`; CI container smoke in `.github/workflows/owner-server-build.yml` (expects `engineVersion == "preferans-1"`, `status == "lobby"`, non-empty `state`, 3 projections for the fixture).
