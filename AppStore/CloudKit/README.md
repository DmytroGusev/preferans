# CloudKit Multiplayer Setup

The app uses the private database in container `iCloud.com.mixandmatch.preferans`.

## Event-Sourced Persistence Model

The authoritative game history is the append-only `PreferansValidatedAction`
stream. Each record stores the validated command, idempotency nonce, sequence,
and structured `PreferansEvent` payloads emitted by the engine. Host snapshots
and completed-deal records are read/cache projections only; they must be
rebuildable from the validated action stream.

## Record Types

Create/deploy these record types in CloudKit Dashboard:

- `PreferansTableSummary`
- `PreferansValidatedAction`
- `PreferansCompletedDeal`
- `PreferansHostSnapshot`

## Required Fields

`PreferansTableSummary`:

- `tableID` String, queryable
- `schemaVersion` Int64
- `status` String
- `hostPlayerID` String
- `seatsData` Bytes
- `rulesData` Bytes
- `lastSequence` Int64
- `createdAt` Date
- `updatedAt` Date
- `publicProjectionData` Bytes

`PreferansValidatedAction`:

- `tableID` String, queryable
- `schemaVersion` Int64
- `sequence` Int64, queryable and sortable
- `actor` String
- `actionData` Bytes
- `clientNonce` String, queryable
- `baseHostSequence` Int64
- `createdAt` Date
- `eventsData` Bytes
- `eventSummariesData` Bytes
- `parentTable` Reference

`PreferansCompletedDeal`:

- `tableID` String, queryable
- `schemaVersion` Int64
- `sequence` Int64, queryable and sortable
- `resultData` Bytes
- `scoreData` Bytes
- `completedAt` Date
- `parentTable` Reference

`PreferansHostSnapshot`:

- `tableID` String, queryable
- `schemaVersion` Int64
- `sequence` Int64
- `snapshotData` Bytes or encrypted Bytes

## Two-Device Smoke Test

1. Enable iCloud and Associated Domains for app id `3WSQ6X9CDT.com.mixandmatch.preferans`.
2. Sign both devices into iCloud.
3. Install the same build on both devices.
4. On device A, sign in, create an online room, and share the invite.
5. On device B, open `https://preferans.game/join/{ROOM_CODE}`.
6. Confirm device B joins the same room and sees the same roster.
7. Start a hand from the host and make one bid/action on each device.
8. Confirm the other device receives each action without overwriting local state.

If events do not sync, check that `PreferansValidatedAction.tableID` is queryable and `PreferansValidatedAction.sequence` is sortable in the deployed production schema.
