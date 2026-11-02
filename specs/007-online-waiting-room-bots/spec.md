# Feature: Configurable bots in online waiting rooms

Date: 2026-11-02. Status: implemented in source, not deployed or uploaded.

## User Flow

The host creates a three- or four-seat public or invite-only table. A friend can
join normally. Each remaining empty seat offers **Add bot**, with Casual,
Seasoned and Expert strengths. Bot seats show a CPU icon, Bot badge and chosen
strength. **Bot settings** changes strength or removes the bot, reopening that
seat for another friend. Adding a bot never deals cards automatically.

The host taps **Start game** separately. At public tables all seated humans must
confirm Ready after each roster/strength change. Bots do not need a socket or a
Ready tap. No timeout silently replaces a human, including a disconnected one.

## Requirements

- FR-001: Only the current host, authenticated by account bearer and seat token,
  can edit bot seats. Controls are hidden from guests and unavailable offline.
- FR-002: Edits are allowed only in the lobby at engine sequence zero. No bot
  replacement, removal or strength change is allowed during an active match.
- FR-003: Only open or existing bot seats can be edited. Joined human seats are
  protected. Add/join races are serialized by the room's existing mutation queue.
- FR-004: Difficulty is persisted with that seat, delivered in redacted rosters
  and passed to the existing Swift engine as a BotProfile with adaptive style.
  Legacy bot seats lacking the field retain seasoned difficulty.
- FR-005: Changes rebuild the lobby engine before committing/broadcasting. Engine
  failure leaves the previous durable roster and readiness intact. No-op edits
  do not rebuild or reset Ready. Real edits clear all human Ready confirmations.
- FR-006: Public listings count bots as occupied, identify them as bots, and do
  not expose any additional identity, credential or hidden game data.
- FR-007: The client single-flights edits, shows loading/errors and disables Start
  and Ready while editing. A bot's difficulty remains visible to all players.
- FR-008: New copy is translated in en/ru/uk and per-seat menu accessibility IDs
  come from UIIdentifiers. Existing local/in-memory fill-and-start remains intact.

## Contract And Compatibility

`POST /v2/rooms/{code}/seats/bot` takes `{playerID, seatToken,
targetPlayerID, difficulty}`. `difficulty` is `casual|seasoned|expert`; explicit
`null` removes a bot, while a missing/invalid value is rejected. Response is the
existing PublicRoom. The router supplies accountID from the bearer, never the
client. Host proof targets the actor; targetPlayerID selects the editable seat.

Optional `OnlinePeer.botDifficulty` and public listing player `isBot` /
`botDifficulty` fields are backward-compatible additions. Wire schema stays 4.
Initial public creation still uses human/open seat intents; bots are added after
creation. The existing fill-bots endpoint now also accepts public waiting tables.

No engine algorithm or state format changes are needed: the current engine
already accepts all three BotDifficulty values. The Worker must be deployed
before distributing the new client. Build 30 has no per-seat controls; these
changes require a later TestFlight build. No server deploy, build upload or
review submission is implied by this source change.

## Verification

- Worker unit tests: single-seat editing for both visibilities, four-seat partial
  fill, human protection, validation, idempotency, reopen/rejoin, readiness gate,
  listing occupancy and selected profiles reaching the engine.
- Local workerd test: authenticated host, invalid credentials/non-host rejection,
  persisted profile, no-op, active-game rejection and engine-failure rollback.
- Swift tests: legacy/selected profile decoding, no auto-start, readiness only
  for humans and hidden controls for non-hosts.
- Native loopback UI test: real guest registration, public host, second account
  join/connect, add Casual, change Expert, remove, add Seasoned, both humans Ready,
  start and receive ten cards. Uses the local Worker/Swift engine, not production.

See related [online contract](../004-online-multiplayer/contracts/worker-http-api.md).
