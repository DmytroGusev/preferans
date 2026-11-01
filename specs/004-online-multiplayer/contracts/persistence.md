# Contract: Persistence (server and device)

**Implementation**: `workers/room-worker/src/index.ts` (`PreferansTable.commitRoom`, `alarm`, `PlayerAccountV2`), `src/public-directory.ts`, `wrangler*.toml` migrations; `Preferans/Online/OnlineCommandOutbox.swift`, `OnlineSeatCredentialStore.swift`; `Preferans/Support/AppIdentifiers.swift`; `Preferans/UI/LobbyViewModel.swift` (account record).

No Workers KV, D1, R2 or external database is used. All server persistence is Durable Object storage (SQLite-backed classes, key/value API: `get/put/delete/list/transaction/setAlarm`).

## Durable Object namespaces

| Binding | Class | Instance naming | Config |
| --- | --- | --- | --- |
| `ROOMS` | `PreferansTable` (prod) / `LocalPreferansTable` (local) | `idFromName(roomCode)` | all configs |
| `ACCOUNTS` | `PlayerAccountV2` | `idFromName(accountID)` | all configs |
| `LOBBY` | `PublicTableDirectory` | `idFromName("public-v1")` (single instance) | optional binding; all configs define it |
| `ENGINE` | `PreferansEngineContainer` (Container) | `getRandom(ENGINE, 3)` | production configs only |

### Migrations (`wrangler.toml`, friend/original account)

| Tag | Change |
| --- | --- |
| `v1` | new `PreferansRoom` |
| `v2` | new `PlayerLibrary` |
| `v3-authenticated-v2` | new `PreferansRoomV2`, `PlayerAccountV2` (clean break: no import of v1 rooms/libraries/identities) |
| `v4-server-authoritative-v3` | new `PreferansRoomV3`, `PreferansEngineContainer` |
| `v5-durable-table` | new `PreferansTable`; **deleted** `PreferansRoom`, `PlayerLibrary`, `PreferansRoomV2`, `PreferansRoomV3` (all older room data dropped) |
| `v6-public-directory` | new `PublicTableDirectory` |

`wrangler.owner.toml` (owner account, fresh destination): single bootstrap tag `owner-v1-bootstrap` creating `PreferansTable`, `PlayerAccountV2`, `PreferansEngineContainer`, `PublicTableDirectory`. `docs/OWNER_MULTIPLAYER_BUILD29.md`: never delete/recreate namespaces to update; adding a class later needs a new tag. `wrangler.local.toml`: `local-v4` (`LocalPreferansTable`, `PlayerAccountV2`), `local-public-v1` (`PublicTableDirectory`); local data lives in the ignored `.wrangler` directory.

## `PreferansTable` keys

| Key | Value | Written | Deleted |
| --- | --- | --- | --- |
| `room` | `RoomState` | `commitRoom` (txn), plus direct `put` for alarm bookkeeping (`retryCount`, `directoryDirty`, `libraryDirty=false`, removal list) and public presence (`directoryRevision`) | never |
| `command:<accountID>:<nonce>` | `{fingerprint, receipt}` | `commitRoom` txn (accepted) or direct `put` (deterministic rejection) | account deletion of that account (`command:<accountID>:` prefix) |
| `history:<12-digit sequence>` | `{command?, receipt?, engineVersion, state}` | `commitRoom` txn when `authoritativeState` exists and (`sequence == 0` or absent) | any seated account's deletion (all `history:` keys of the room) |
| *(alarm)* | timestamp | before every commit (`now + 500 ms`), in `alarm` (5 s safety, then computed), public presence (`now + 500 ms`) | `deleteAlarm` when no work and not listable |

### Commit transaction (`commitRoom(room, key?, command?)`)

1. `setAlarm(now + 500 ms)` **before** the transaction ("an interruption can leave a harmless extra wakeup, but never durable work with no alarm to resume it").
2. `transaction`: read previous `room`; `put room` with `botPending = (status == playing && botPending)`, `libraryDirty = true`, `directoryDirty = (visibility == public)`, `directoryRevision = previous + 1`; `put command key` if provided; `put history:<seq>` (rules above).
3. Delivery happens after the transaction resolves (`runtime-test/room.test.ts` "transaction interruption cannot publish state without its receipt").

### Alarm schedule (`PreferansTable.alarm`)

| Condition after the run | Next alarm |
| --- | --- |
| work pending and `retryCount > 0` | `min(60 000, 1 000 × 2^retryCount)` ms (2 s … 60 s) |
| `botPending` | 500 ms (`BOT_MOVE_DELAY_MS`) |
| library/directory/removal work pending | 5 000 ms |
| public and advertisable (`publicTableEntry` non-null) | 30 000 ms (lease renewal) |
| otherwise | alarm deleted |

At the start of a run with pending work (or any public room) a 5 s safety alarm is set before external calls.

## `PlayerAccountV2` keys

| Key | Value | Notes |
| --- | --- | --- |
| `account` | `PlayerAccountState` (`schemaVersion 2`, identity, `sessions[]`, `games{roomCode: GameSummaryEntry}`) | `DELETE /delete` → `deleteAll()` |

All operations run through a per-instance `MutationQueue`.

## `PublicTableDirectory` keys

| Key | Value | Notes |
| --- | --- | --- |
| `table:<roomCode>` | `{revision, expiresAt, table?}` | Written when `revision ≥ stored`; lease `PUBLIC_TABLE_LEASE_MS = 90 000` |
| *(alarm)* | `now + 90 s` on each accepted publish; sweep deletes expired rows, re-arms while rows remain | |

## Retention summary (as built)

| Data | Retained until |
| --- | --- |
| Room record (incl. projections of finished games) | unfinished: forever. Finished/abandoned: 30 days after `terminalAt`, then the whole Durable Object is wiped (`TERMINAL_ROOM_RETENTION_MS`) |
| Live private engine state | finish (dropped), abandon (dropped), account deletion of a seated player in non-lobby rooms (dropped) |
| Revision checkpoints (complete private states) | until the table ends: deleted by the next alarm after `finished`/`abandoned` (`historyPurged`), or when a participant deletes their account |
| Command receipts | until the 30-day wipe of a terminal table (late retries still get their receipt); per account until that account is deleted |
| Library rows | forever; removed only by `/leave` (public lobby) or account deletion |
| Sessions | 180 days; pruned lazily when a new session is issued; account deletion |
| Directory listings | 90 s lease |

## Device storage

| Store | Key / path | Value | Protection / lifetime |
| --- | --- | --- | --- |
| Keychain | service `com.mixandmatch.preferans.online-account.v2<suffix>`, account `active-session` | bearer session token | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; removed on sign-out/deletion |
| UserDefaults | `settings.onlineRegisteredAccount<suffix>` | `RegisteredOnlineAccount` JSON (`schemaVersion`, `provider`, `accountID`, `displayName`) | discarded on schema/provider mismatch |
| UserDefaults | `settings.onlineDisplayName<suffix>` | display name (300 ms debounced) | |
| UserDefaults | `settings.onlineAnonymousAccountID<suffix>` | legacy v1 debris | deleted on register/clear |
| UserDefaults | `online.seatCredentials<suffix>` | `{"<ROOMCODE>": {"token", "savedAt"}}` | entries older than 90 days pruned on each store; `remove` after abandon; `removeAll` on sign-out/deletion |
| File | `~/Library/Application Support/Preferans/Commands/<TABLE-UUID>-<base64(accountID) with "/"→"_">.json` | one pending `ClientActionEnvelope` (default `JSONEncoder`, atomic write) | removed on matching receipt or `tableAbandoned`; survives relaunch |
| UserDefaults | `settings.onlineVariant`, `settings.pulkaLimit`, `settings.customPulka*`, `settings.raspasy*` | table-creation preferences (shared with local play) | — |

`<suffix>` = `AppIdentifiers.onlineStorageSuffix`: `.owner-v1` normally ("Never send the old server's bearer/seat credentials to the new backend. Preserve legacy storage…"), or `.uiTestLocal.<host>.<port>` when a DEBUG UI-automation build points at a loopback worker. Older un-suffixed keys are intentionally left untouched.

Credentials are never written to the outbox or logs ("Credentials are never stored here; the command is scoped to account + table").
