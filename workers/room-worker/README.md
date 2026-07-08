# Preferans Room Worker

Cloudflare Worker + Durable Object backend for Preferans room invites and realtime relay.

This first version is intentionally transport-focused: it creates rooms, lets peers join, accepts WebSocket connections, tracks presence, and relays opaque `GameWireMessage` JSON between peers. The existing Swift host actor still owns game validation. That makes it useful for beta multiplayer and end-to-end transport work, while leaving the later server-authoritative engine move explicit.

## Run Locally

```sh
cd workers/room-worker
wrangler dev --local --port 8787
```

Health check:

```sh
curl http://127.0.0.1:8787/health
```

Create a room:

```sh
curl -s http://127.0.0.1:8787/rooms \
  -H 'content-type: application/json' \
  -d '{"localPeer":{"playerID":{"rawValue":"north"},"accountID":"email:north@example.test","provider":"email","displayName":"North"},"seats":[{"playerID":{"rawValue":"north"},"accountID":"email:north@example.test","provider":"email","displayName":"North"},{"playerID":{"rawValue":"east"},"accountID":"dev:east","provider":"dev","displayName":"East"},{"playerID":{"rawValue":"south"},"accountID":"dev:south","provider":"dev","displayName":"South"}]}'
```

Join a room:

```sh
curl -s http://127.0.0.1:8787/rooms/ABC123/join \
  -H 'content-type: application/json' \
  -d '{"localPeer":{"playerID":{"rawValue":"east"},"accountID":"email:east@example.test","provider":"email","displayName":"East"}}'
```

WebSocket client messages:

```json
{
  "type": "wire",
  "recipients": [{ "rawValue": "east" }],
  "reliable": true,
  "message": { "ping": { "schemaVersion": 1, "tableID": null, "sentAt": "2026-05-04T00:00:00Z" } }
}
```

Server WebSocket messages:

```json
{
  "type": "wire",
  "sender": {
    "playerID": { "rawValue": "north" },
    "accountID": "email:north@example.test",
    "provider": "email",
    "displayName": "North"
  },
  "message": {}
}
```

## Durable Game Library (resume + history)

Beyond live relay, the worker is the durable home for a player's games so the
lobby can list **Continue** (in-progress) and **History** (finished) games and
resume an unfinished table from any device. Two pieces back this:

- **`PreferansRoom`** (per room, key = room code) additionally stores a
  lifecycle `status` (`lobby` | `playing` | `finished` | `abandoned`), a small
  worker-readable `summary` (variant, deal/phase, final result), and an opaque
  `latestSnapshot` blob (the authoritative engine state the resuming host
  hydrates from — the worker never decodes it, and it is dropped once the game
  is finished/abandoned).
- **`PlayerLibrary`** (per account, key = `accountID`) holds one
  `GameSummaryEntry` per room the account is in. Rooms fan their summary into
  every human participant's library on each material transition, so the lobby
  lists a player's games with a single read.

### State report (host-only)

The host pushes progress after each validated action, authenticated with the
host secret. The secret is minted at `/create`, and `/join` hands it back when
the joining account holds the host seat — so a host that resumes a game (same
account, any device) regains its authority instead of silently losing the
ability to report state and fill bot seats. The snapshot is stored
monotonically (a late, lower-sequence report can't clobber a newer snapshot),
and only material changes (status/deal/phase) trigger a presence push + library
fan-out — per-action snapshot refreshes are silent.

```sh
curl -s http://127.0.0.1:8787/rooms/ABC123/state \
  -H 'content-type: application/json' \
  -d '{"hostSecret":"<from /create>","status":"playing","summary":{"variant":"odesa","lastSequence":4,"phase":"bidding","dealNumber":1},"snapshot":{ /* opaque */ },"snapshotSequence":4}'
```

### List a player's games

```sh
curl -s "http://127.0.0.1:8787/my-games?accountID=apple:north"
# → { "games": [ GameSummaryEntry, ... ] }   # most-recently-updated first
```

### Fetch the resume snapshot (seated participant only)

The snapshot reveals hidden hands, so it is gated on proving ownership of a
human seat (a `pending:`/`bot:` seat is rejected) via the seat token.

```sh
curl -s "http://127.0.0.1:8787/rooms/ABC123/snapshot?playerID=north&seatToken=<from /create or /join>"
# → { "roomCode", "status", "summary", "lastSnapshotSequence", "snapshot" }
```

## Seat tokens

Every claimed human seat carries a server-minted `seatToken`, returned only to
the seat's owner in its `/create`/`/join` response and never included in any
broadcast payload. It proves seat ownership on three surfaces:

- **WebSocket connect** — always enforced. The socket URL is server-built and
  embeds the token, so every client (including pre-token builds, which treat
  the URL as opaque) presents it. Without this, the room code alone let anyone
  attach as any seat and act as that player.
- **`GET /rooms/{code}/snapshot`** and **`POST /rooms/{code}/abandon`** —
  a wrong token is always rejected; a *missing* token is tolerated until the
  `REQUIRE_SEAT_TOKENS` var (wrangler.toml) flips to `"true"`, closing the
  compatibility window for clients that predate tokens.

Room codes, host secrets, and seat tokens are all generated from the platform
CSPRNG. A `/create` that collides with an existing room code retries with a
fresh code — it never replies with (or leaks the credentials of) the existing
room.

## Launch Boundary

This worker is the correct room/transport foundation, but it is not yet a public-launch authoritative game server. For public multiplayer, move Preferans validation/projection generation into the Durable Object, either by porting the engine to TypeScript or compiling a shared core to WASM.
