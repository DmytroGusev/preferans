# Preferans Room Worker

Cloudflare Worker + Durable Objects backend for authenticated Preferans rooms,
game libraries, resume snapshots, presence, and realtime relay.

API v2 is an intentional clean break. `PreferansRoomV2` and
`PlayerAccountV2` use fresh Durable Object namespaces; v1 rooms, libraries,
client-declared identities, and compatibility access are not imported.

The worker owns account/seat/room authority and durable progress. The Swift host
still validates game actions and generates player projections, so moving the
engine into the Durable Object remains the final server-authority boundary.

## Local run

```sh
cd workers/room-worker
wrangler dev --local --port 8787
```

```sh
curl http://127.0.0.1:8787/health
```

The response reports both `accountSchemaVersion: 2` and
`roomSchemaVersion: 2`.

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

## Create and join

Clients choose only seat IDs and open/bot intent. They never declare account IDs,
providers, or display names for a human seat; those fields come from the
authenticated server account.

```sh
curl -s http://127.0.0.1:8787/v2/rooms \
  -H 'authorization: Bearer <sessionToken>' \
  -H 'content-type: application/json' \
  -d '{"localPlayerID":{"rawValue":"north"},"seats":[{"playerID":{"rawValue":"north"},"kind":"you"},{"playerID":{"rawValue":"east"},"kind":"bot"},{"playerID":{"rawValue":"south"},"kind":"open"}],"maxPlayers":3}'
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

- `PreferansRoomV2`, keyed by room code, stores status, a small readable
  summary, and an opaque latest snapshot. Finished/abandoned rooms drop the
  snapshot.
- `PlayerAccountV2`, keyed by server account ID, stores the account profile,
  up to five active expiring session hashes, and one summary per room.
- `GET /v2/my-games` derives its account from the bearer token. There is no
  account ID query parameter.

```sh
curl -s http://127.0.0.1:8787/v2/my-games \
  -H 'authorization: Bearer <sessionToken>'
```

The host reports progress to `POST /v2/rooms/{code}/state` with its `playerID`
and current `seatToken`. The worker verifies both the bearer account and the
rotating credential own the current host seat; no separate host secret exists.
Snapshots and summaries are monotonic, and terminal lifecycle is immutable, so
a delayed report cannot roll back or resurrect a game. The iOS coordinator
commits this snapshot before publishing the corresponding projections.

Resume and abandon require both layers of proof:

- a valid account bearer session; and
- the token for the claimed room seat.

```sh
curl -s 'http://127.0.0.1:8787/v2/rooms/ABC123/snapshot?playerID=north&seatToken=<seatToken>' \
  -H 'authorization: Bearer <sessionToken>'
```

There is no v1 seat-token compatibility flag. Missing, forged, or legacy
token-less credentials are rejected on every sensitive v2 path.

## Realtime relay

WebSocket clients send `wire` envelopes containing recipient seat IDs and an
opaque `GameWireMessage`. The Durable Object binds the socket to the seat proven
by its URL token, excludes unknown recipients and the sender, sequences frames,
and does not retain relay history. It rejects projection, seat-assignment, and
host-error frames from non-host seats.

The room exposes a monotonic `hostEpoch`. When the current host has no live
socket, the Durable Object elects the first connected human in stable seat
order, advances the epoch, and broadcasts the new authority. The elected iOS
client fetches and validates the durable snapshot before becoming host; a
playing room with a missing or corrupt snapshot fails closed instead of dealing
a new game. Terminal rooms never elect another host.

## Verification

```sh
bun run typecheck
bun test
```

`PREFERANS_WORKER_URL=http://127.0.0.1:8787 swift test --filter OnlineWorkerIntegrationTests`
exercises guest registration, room creation, authenticated state reporting,
token takeover/revocation, live WebSocket host migration, exact snapshot
recovery, former-host rejection, library reads, and abandon across the
Swift/Worker boundary.
