# CloudKit Multiplayer Setup

The app uses the public database in container `iCloud.com.mixandmatch.preferans`.

## Record Types

Create/deploy these record types in CloudKit Dashboard:

- `GameRoom`
- `GameSnapshot`
- `GameEvent`

## Required Fields

`GameRoom`:

- `code` String, queryable
- `hostPlayerID` String
- `playerCount` Int64
- `ruleSet` String
- `participantsJSON` String
- `roomState` String
- `updatedAt` Date

`GameSnapshot`:

- `roomID` String, queryable
- `revision` Int64
- `updatedByPlayerID` String
- `updatedAt` Date
- `snapshotJSON` String

`GameEvent`:

- `roomID` String, queryable
- `revision` Int64, queryable and sortable
- `actorPlayerID` String
- `createdAt` Date
- `actionJSON` String
- `resultingStateJSON` String

## Two-Device Smoke Test

1. Enable iCloud and Associated Domains for app id `3WSQ6X9CDT.com.mixandmatch.preferans`.
2. Sign both devices into iCloud.
3. Install the same build on both devices.
4. On device A, sign in, create an online room, and share the invite.
5. On device B, open `https://preferans.game/join/{ROOM_CODE}`.
6. Confirm device B joins the same room and sees the same roster.
7. Start a hand from the host and make one bid/action on each device.
8. Confirm the other device receives each action without overwriting local state.

If events do not sync, check that `GameEvent.roomID` is queryable and `GameEvent.revision` is sortable in the deployed production schema.
