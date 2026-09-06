# Authoritative multiplayer contract

The online runtime is a clean break. No peer may host a match, supply a deck,
upload a snapshot, or publish a player projection. The lobby manager only manages
seats and requests deals. Offline simulation is a separate execution path.

## Commit boundary

A table Durable Object serializes all durable mutations, including membership,
device takeover, socket lifecycle, abandonment, commands, and alarms. Commands
carry a protocol version, table ID, unique ID, actor, expected revision, and action.
The authenticated seat supplies identity. A command ID is bound to its complete
payload and sender. A committed receipt survives reconnects and terminal games.
State, receipt, history, and background-work intent commit together before delivery.
Delivery failure cannot roll back an accepted move. Transient execution failures
leave a command retryable; permanent rejections have an explicit receipt.

## Visibility

Private snapshots and random seeds never cross a client boundary. Both projections
and events are filtered by viewer. Discards are visible only to the declarer during
play. Completed deals reveal initial hands for the existing post-deal review UX.
Seat credentials and private state must never appear in logs or public summaries.

## Lifecycle

Disconnecting preserves the seat and pauses at that human's turn. There is no
automatic forfeiture or silent replacement. Rejoin rotates the controlling seat
credential. Only its newest socket can receive private projections or issue moves.
Leaving the screen disconnects; explicitly abandoning terminates the match for all
players. Account deletion anonymizes membership and abandons active matches.
Bots run as durable scheduled actions, independently of a human command's commit.

## Recovery and deployment

Clients persist one pending command per table and account, retrying the same ID
until a durable receipt resolves it. Reconnect refreshes a seat projection; animation
is local presentation and never advances game authority. Library updates use a
durable outbox with retry. Engine/state versions are checked before adopting a
transition. New incompatible rules require a new engine version and explicit room
routing; deployments must never silently reinterpret saved state.

## Acceptance gates

Fast engine and wire tests; actual Durable Object runtime tests covering interrupted
engine requests and reconnects; a bounded multi-client complete match; container
health and cold/warm latency measurements; and an iOS build. Production deployment
is a separate operation from preparing and committing the upgrade.

## Implementation and verification (2026-09-06)

1. Server authority and private event filtering; payload-bound command IDs.
2. Serialized durable commands, atomic receipts/checkpoints, bot alarms, library
   outbox, and a dedicated iOS ServerGameCoordinator with local command persistence.
3. Ten workerd tests covering rollback, lost delivery, duplicate/conflicting commands,
   lifecycle races, retry, takeover, and a real WebSocket resume; Swift tests cover
   persisted pending moves and complete three/four-seat matches.
4. Fresh protocol-4 table namespace, obsolete library filtering, request/message
   bounds, connection heartbeat, local development launcher, CI, wire fixture, and
   production deployment dry run. Unbounded matches omit the Swift Int.max sentinel
   at the JSON boundary to avoid JavaScript integer rounding.

Verified locally: 45 Worker unit tests; 10 workerd tests; 19 focused Swift client,
security, and wire tests; three live Swift-to-Worker integration tests; the unbounded
integer regression; both full server match sizes; iOS simulator build; Linux container
build; Worker/container deployment dry run; and 3/4-seat real-network create/join/deal/
retry/resume smoke with temporary-account cleanup. These are scoped checks, not a
claim that every repository test or every production failure mode has been exercised.

No production deployment was performed. Cloudflare cold starts, geographical latency,
and concurrent-table capacity still require measurements in a deployed environment.
The current pool limit of three is a starting configuration, not a capacity guarantee.
