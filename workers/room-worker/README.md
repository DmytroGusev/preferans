# Preferans authoritative tables

Cloudflare Workers route authenticated accounts to one SQLite-backed Durable Object
per table. A stateless Linux Swift container evaluates moves using the same
PreferansEngine as offline play. Clients receive only their own filtered projection
and events. Protocol 4 is a clean break; old room namespaces are deleted at deployment.
Account authentication remains account schema 2, independently of table protocol 4.

## Development

From the repository root, run `bin/dev-online` (Docker and Bun required). It builds
and starts the Linux engine on localhost:18081 and runs real local Durable Objects on
localhost:8787. The local-only entry point is not part of the production bundle.
Stop it with Ctrl-C; the engine container is cleaned up. Persistent local room data
lives in Wrangler's ignored `.wrangler` directory.

From this directory:

- `bun run check`: TypeScript checks, pure tests, and real workerd lifecycle tests.
- `bun run smoke:live`: create 3/4-player tables, deal, reconnect, and clean up.
  Defaults to localhost. Set `PREFERANS_ROOM_WORKER_URL` for an explicitly selected
  deployed environment. It creates temporary guest accounts and deletes them.
- `bun run deploy:check`: bundle/validate the production Worker without deploying.
- `bun run deploy`: deploy the production Worker and container configuration.

The fixture in `fixtures/create-game.json` is verified by the Swift server test
suite. Regenerate intentionally with `PREFERANS_UPDATE_WIRE_FIXTURE=1 swift test
--filter testCheckedInWireFixtureMatchesSwiftCodec` from the repository root.

## Wire contract

HTTP account and room routes are under `/v2`; payload `schemaVersion` is 4. Register
through `/v2/accounts/guest` or `/v2/accounts/apple`. Create and join derive seat
identity from the account bearer session. Their responses contain only the caller's
seat credential and WebSocket URL. Rejoining rotates the credential and immediately
closes the previous controller. Sensitive outbound frames re-check the current seat
credential. Never log connection URLs or private snapshots.

Clients send only `clientAction` and `resyncRequest` messages. A command requires
`schemaVersion`, `tableID`, `actor`, `clientNonce` (UUID), `baseHostSequence`, and
`action`. Swift's codec defines the JSON action shape. Receipts are outer frames:

```json
{"type":"receipt","receipt":{"tableID":"UUID","clientNonce":"UUID","sequence":1,"status":"accepted"}}
```

Rejected receipts include `code` and `message`. Retrying an identical command ID
returns the original result, including after match completion. Reusing it for another
payload is rejected. Infrastructure errors do not create permanent rejection receipts.
The iOS outbox persists a move before transmission and reuses its ID until resolved.

All room writes, WebSocket lifecycle handlers, and alarms use the same bounded
mutation queue. Room state, accepted receipts, and private revision checkpoints commit
in one transaction. Delivery follows commit. A checkpoint retains the exact opaque
Swift state and, for human moves, the input command; it has no client HTTP endpoint.
Account deletion removes private checkpoints and the deleted account's receipts.

Bots advance one revision per durable alarm, at the interactive cadence. Library
refresh intent is persisted with room state and retried by alarms. Engine errors back
off to one minute. Human disconnects preserve seats and wait at that player's turn.
Abandoning explicitly ends the whole match. Finishing retains receipts and player
projections but drops the live engine snapshot.

## Release

The final migration creates `PreferansTable` and deletes obsolete room classes.
There is no room import or old-client fallback. Deploy the matching container/Worker
and client together. `preferans-1` is the pinned engine version; changing it requires
an explicit policy for existing tables. Incompatible saved tables fail closed.

The pool currently permits three engine containers. Local tests do not establish
production capacity: measure cold/warm latency and simultaneous rooms on Cloudflare
before increasing traffic. Observability is enabled; private state and credentials
must stay out of logs. See `docs/MULTIPLAYER.md` in the repository for invariants.
