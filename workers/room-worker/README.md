# Preferans Room Worker

Cloudflare Worker + Durable Objects backend for authenticated Preferans rooms,
game libraries, presence, command routing, and seat-redacted projections.

Room schema v3 is an intentional clean break. `PreferansRoomV3` uses a fresh
Durable Object namespace; peer-hosted v2 state is not imported.

The Worker owns account and seat identity. One room Durable Object serializes
commands and durably owns the opaque private state. A stateless Linux Swift
container validates transitions, runs bots, and returns one redacted projection
per seat. No client hosts an online game or uploads an engine snapshot.

## Local run

```sh
cd workers/room-worker
wrangler dev --local --port 8787
```

```sh
curl http://127.0.0.1:8787/health
```

The response reports `accountSchemaVersion: 2` and `roomSchemaVersion: 3`.

## Register

Guest registration creates a random server-owned account. The response contains
the public account profile and a bearer session. The raw session is returned
once; only its SHA-256 digest is stored.

```sh
curl -s http://127.0.0.1:8787/v2/accounts/guest \
  -H 'content-type: application/json' \
  -d '{"displayName":"North"}'
```

Apple registration uses `POST /v2/accounts/apple` with `identityToken`, the raw
nonce used by the app, and `displayName`. The worker verifies the RS256
signature against Apple's current JWKS and validates issuer, audience, expiry,
subject, and the SHA-256 nonce before deriving the account identity.

All remaining HTTP examples use:

```sh
-H 'authorization: Bearer <sessionToken>'
```

## Delete an account

`DELETE /v2/account` permanently deletes the authenticated account, its active
sessions, and game library. The worker also removes its identity and room
credential from every indexed room before deleting the account record: lobby
seats reopen, active games are abandoned and lose their private engine state, and
shared terminal history retains only an anonymized seat. A later Apple sign-in
or guest registration creates a fresh account state.

```sh
curl -i -X DELETE http://127.0.0.1:8787/v2/account \
  -H 'authorization: Bearer <sessionToken>'
```

## Create and join

Clients choose only seat IDs and open/bot intent. They never declare account IDs,
providers, or display names for a human seat; those fields come from the
authenticated server account.

```sh
curl -s http://127.0.0.1:8787/v2/rooms \
  -H 'authorization: Bearer <sessionToken>' \
  -H 'content-type: application/json' \
  -d '{"localPlayerID":{"rawValue":"north"},"seats":[{"playerID":{"rawValue":"north"},"kind":"you"},{"playerID":{"rawValue":"east"},"kind":"bot"},{"playerID":{"rawValue":"south"},"kind":"open"}],"maxPlayers":3,"rules":{...},"match":{...}}'
```

```sh
curl -s http://127.0.0.1:8787/v2/rooms/ABC123/join \
  -H 'authorization: Bearer <sessionToken>' \
  -H 'content-type: application/json' \
  -d '{"requestedPlayerID":{"rawValue":"south"}}'
```

Create/join returns the caller's `seatToken` and a server-built `websocketURL`.
The URL embeds that room-scoped token. Public room, presence, and library
payloads never expose a seat token. Rejoining an already-held seat rotates its
token: the newest device becomes the only controller, existing sockets receive
close code `4009` (`seat_replaced`), and stale HTTP/socket credentials fail.

## Authenticated durable game library

- `PreferansRoomV3`, keyed by room code, stores status, a small readable
  summary, opaque private Swift state, and the latest redacted projection for
  each seat. The private state is never returned by a room endpoint.
- `PlayerAccountV2`, keyed by server account ID, stores the account profile,
  up to five active expiring session hashes, and one summary per room.
- `GET /v2/my-games` derives its account from the bearer token. There is no
  account ID query parameter.

```sh
curl -s http://127.0.0.1:8787/v2/my-games \
  -H 'authorization: Bearer <sessionToken>'
```

`POST /v2/rooms/{code}/state` is retired and returns `410`. Progress is derived
only from successful Swift engine responses. The room keeps private state as an
opaque JSON string so hidden cards and 64-bit random seeds are never coerced by
JavaScript or sent to a player device.

Resume/reconnect sends only the caller's cached redacted projection. Both
`POST /state` and `GET /snapshot` return `410`; private engine state has no
client HTTP boundary. Abandon still requires both layers of proof:

- a valid account bearer session; and
- the token for the claimed room seat.

There is no v1 seat-token compatibility flag. Missing, forged, or legacy
token-less credentials are rejected on every sensitive v2 path.

## Realtime relay

WebSocket clients may send `clientAction` and `resyncRequest` wire messages.
The Durable Object derives the sender from the socket's server-minted seat
token, ignores client-selected recipients, and forwards the command with its
private state to the Swift service. Every projection frame is explicitly marked
`authority: "server"`; peer-authored hello, assignment, projection, and state
messages are rejected.

The legacy `hostPlayerID`/`hostEpoch` fields now identify only the human allowed
to manage lobby operations such as filling open seats. They grant no engine or
projection authority.

## Container image

`Dockerfile.server` builds the same `PreferansEngine` package used for offline
play into the `PreferansServer` Linux executable. `wrangler.toml` binds a pool
of three `PreferansEngineContainer` instances; containers sleep after ten idle
minutes and hold no game state.

## Verification

```sh
bun run typecheck
bun test
```

`PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests`
exercises guest registration, room creation, retired client-state boundaries,
token takeover/revocation, lobby-manager migration without engine authority,
library reads, and abandon across the Swift/Worker boundary.
