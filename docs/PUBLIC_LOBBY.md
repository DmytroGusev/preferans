# Public online tables

The online lobby offers Find a table and Create a table. Public tables are listed
for authenticated Apple/guest accounts; private invite tables retain their existing
code/link flow. Guests can browse a table's settings and roster before claiming a
seat. There is no spectator access to hands or mid-match seat replacement.

## Conventions and match length

Presentation names change without changing persisted rules identifiers:

| Display name | Persisted variant | Scoring profile | Pool closure |
| --- | --- | --- | --- |
| Vienna | `odesa` | Existing balanced profile | Individual limits, American aid |
| Prague | `wien` | Existing doubled-whist profile | Shared table total |
| Berlin | `thessaloniki` | Existing semi-responsible, fixed all-pass profile | Individual limits, American aid |

The fourth existing local/private agreement remains available outside public tables.
Public creation uses three or four human seats and starts with the short pulka preset.
The API represents the total pool target: three individual limits of 11 are encoded
as 33, and four as 44. Prague displays the actual shared table total explicitly.
The Worker supplies canonical rules and all-pass progression from the preset, so
a creator cannot advertise one convention while sending different scoring rules.
The checked-in JSON profiles are verified against the Swift engine by
`PublicTableRulesTests`.

## Readiness and lifecycle

Each player explicitly confirms Ready after seeing the immutable table settings.
The host can start only when all seats are occupied, all human sockets are connected,
and all players are ready. The server validates this independently of the UI.
A new join clears all confirmations; rejoining clears that player's confirmation;
disconnecting clears disconnected players' confirmations while retaining their seats.
Later deals use the existing match flow and do not require a new readiness vote.

Leaving a public waiting table releases the seat. Remaining players inherit lobby
management; the table closes if no humans remain. Removal from the departing player's
library is a durable retryable outbox, committed after the room membership changes.
Leaving an active game's screen retains its seat and the existing Your games resume
flow. Explicit match abandonment remains a separate action.

## Directory and privacy

`GET /v2/public-tables` requires an account bearer session. It returns at most 50
entries, supports offset pagination and optional variant/player-count/pool/status
filters, and places waiting tables ahead of running games. The app refreshes every
15 seconds while its Find screen is active and also supports manual refresh.

`PublicTableDirectory` receives only display names, readiness/connection flags, pool
settings, room codes, occupancy and lifecycle information. No account IDs, seat tokens,
authenticated socket URLs, engine states, projections, decks or discards enter that
directory. Unseated public room summaries also omit real account identities.
Room mutations and socket events mark a durable publication outbox. Connected rooms
renew their listings every 30 seconds; directory leases expire after 90 seconds.
Empty or fully disconnected tables and completed/abandoned games are not advertised.
Joining always checks the current authoritative room, so a stale listing cannot
grant a seat in an already-started or full game.

## Deployment

Migration `v6-public-directory` adds a new namespace and preserves existing rooms
and accounts. The local configuration adds its own corresponding namespace.
Deploy the Worker and current Swift container before distributing the new client.
Older clients can still use private tables, but do not have the public Ready controls.

Local verification commands:

```sh
cd workers/room-worker
bun install --frozen-lockfile
bun run check
bun run test:public-network
```

The network test requires the loopback Worker on 8787 and the Swift engine on 18081.
It creates isolated accounts, discovers and joins three/four-player public tables,
leaves/rejoins a seat, rejects unauthorized readiness and premature dealing, accepts
the first deal after all confirmations, rejects an outsider after start, and deletes
its accounts. `NativeOnlineUITests/testNativePlayerFindsPublicTableReadiesAndReceivesFirstDeal`
checks the corresponding app path against those same services.

The production container pool remains three instances. Local verification does not
establish production concurrency or cold-start latency. Worker-only bundling can be
checked with `wrangler deploy --dry-run --containers-rollout=none`; the complete
container deployment requires Docker and Cloudflare authentication.
