# Research & Decisions (as-built): Preferans Online Multiplayer

**Spec**: [spec.md](spec.md) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828`

Sources: code comments, `docs/MULTIPLAYER.md`, `docs/PUBLIC_LOBBY.md`, `docs/SERVER_CI.md`, `docs/OWNER_MULTIPLAYER_BUILD29.md`, `workers/room-worker/README.md`, and read-only git history (`git log --oneline -- workers/room-worker`, `-- Preferans/Online`, `-- Sources/PreferansServerCore`). Rationale marked *(inferred)* is reconstructed from code shape rather than stated anywhere.

## Timeline (git)

| Date | Commit | Milestone |
| --- | --- | --- |
| 2026-05-04 | `9e43322` | "Add Cloudflare invite multiplayer" — first Worker room relay (client-hosted engine) |
| 2026-06-02 | `00a34dd` | Bind joins to account ID (seat collisions) |
| 2026-06-03 | `df2f177`, `0426f1f` | Host-driven online bots, waiting room; roster from Durable Object presence; Worker-side fill-bots |
| 2026-06-04 | `2d79025` | "Your games" library via Durable Objects |
| 2026-07-08 | `9f02688` | Per-seat tokens, CSPRNG credentials (security audit) |
| 2026-07-09 | `9bd77c1` | Remove relay message history; input size caps |
| 2026-07-31 | `124bdb8` | Authenticated multiplayer (accounts v2) and host recovery |
| 2026-08-01 | `8e9481b` + ~35 commits | Account deletion; hardening of the peer-host coordinator (durability barrier, recovery runner, inbound policy, roster precedence, stale-action rejection) |
| 2026-09-06 | `110c4ed`, `faff696`, `28b89a1` | **Server authority** + private event boundary; durable commands and client outbox; protocol 4 tooling and deployment config |
| 2026-09-08 | `b55a178`, `f62919c` | Native account validation; separate-account full matches through recovery |
| 2026-10-02 | `f7dbbaf` | Public tables, readiness, European convention names |
| 2026-10-31 | `1fa44c5` | Owner backend (`wrangler.owner.toml`, `.owner-v1` storage, compatibility check, invite host change) — build 29 |

---

## D1. Server-authoritative engine; clean break to protocol 4

- **Decision**: No device hosts a match. A per-table Durable Object stores the private state; a stateless Swift service computes transitions; clients receive only per-viewer projections and may send only commands (`clientAction`) or `resyncRequest`. Old rooms are not migrated (`v5-durable-table` deletes all previous room classes; `PreferansWireSchema.current = 4`).
- **Rationale**: `docs/MULTIPLAYER.md`: "No peer may host a match, supply a deck, upload a snapshot, or publish a player projection." The `9f02688` audit found that the client-host design leaked every hidden hand (`GET /rooms/{code}/snapshot` gated only by a public `playerID`), allowed socket impersonation by room code, and one-request abandonment. A host device necessarily holds all hands (`HostGameActor` owns the full engine). Host migration required uploading full snapshots (`reportState`) and caused split-brain risks that dozens of August-2026 commits tried to contain.
- **Alternatives considered**: (a) Client-hosted authority with Worker-persisted snapshots and host recovery — the previous design, retained only for the in-memory DEBUG room (`RoomOnlineGameCoordinator`, `RoomDurabilityBarrier`, `RoomHostRecoveryRunner`). (b) Game Center match transport — explicitly not substituted ("Durak's Game Center match transport was not substituted for Preferans's authoritative game state", `docs/OWNER_MULTIPLAYER_BUILD29.md`). (c) Compatibility window for old clients — rejected: "There is no room import or old-client fallback" (worker README); `/state` and `/snapshot` return 410.

## D2. Reuse the Swift engine in a stateless Linux container

- **Decision**: Run `PreferansEngine` inside `PreferansServer` (Hummingbird) built with the `PREFERANS_SERVER_ONLY=1` package lane, deployed as a Cloudflare Container (`max_instances = 3`, `sleepAfter = "10m"`); the Worker treats Swift payloads as opaque JSON.
- **Rationale**: One rules implementation for offline and online play ("Shared Swift rules engine for local and online play", README); avoids a TypeScript port drifting from Swift (*inferred*). Statelessness lets any container serve any table and keeps durability in the Durable Object ("Durable room state remains in `PreferansTable`; this class only manages a small warm container pool", `index.ts`).
- **Alternatives considered**: Port rules to TypeScript in the Worker *(inferred, not chosen)*; stateful engine process per table *(inferred, not chosen — would duplicate durability)*. Capacity of 3 instances is "a starting configuration, not a capacity guarantee" (`docs/MULTIPLAYER.md`).

## D3. Opaque private state as a JSON string

- **Decision**: `AuthoritativeGameState` is encoded to a string and stored verbatim (`RoomState.authoritativeState`); unbounded `MatchSettings.poolTarget` (`Int.max`) is omitted on encode.
- **Rationale**: "This remains a string so 64-bit seeds and every hidden hand cross JavaScript without numeric coercion" (`room-state.ts`); "Unbounded matches omit the Swift Int.max sentinel at the JSON boundary to avoid JavaScript integer rounding" (`docs/MULTIPLAYER.md`).
- **Alternatives considered**: Structured JSON parsed by the Worker — would round UInt64 seeds and expose hands to Worker code paths.

## D4. Explicit FIFO mutation queue per Durable Object

- **Decision**: Every HTTP route, socket message, socket close/error and alarm runs through `MutationQueue` (≤ 64 pending, failures do not poison the chain).
- **Rationale**: "Durable Objects may interleave events while one awaits an external container fetch. Keep every room mutation behind an explicit FIFO so two commands can never both advance the same private state and race to store." Proven by `runtime-test/room.test.ts` "socket close cannot overwrite a command while its engine call is suspended".
- **Alternatives considered**: Rely on DO input gates alone *(rejected per comment — gates open during outbound fetch)*; optimistic concurrency on `authoritativeSequence` *(inferred, not chosen)*.

## D5. Durable, payload-bound command receipts; retryable vs permanent failures

- **Decision**: Receipts keyed `command:<accountID>:<nonce>` with a SHA-256 fingerprint of the canonical payload; committed in the same transaction as the room; deterministic rejections stored, infrastructure failures not stored; a different payload under the same ID gets `command_id_conflict`. The engine also remembers 16 nonces.
- **Rationale**: `docs/MULTIPLAYER.md` "Commit boundary": "A command ID is bound to its complete payload and sender. A committed receipt survives reconnects and terminal games. State, receipt, history, and background-work intent commit together before delivery. Delivery failure cannot roll back an accepted move. Transient execution failures leave a command retryable; permanent rejections have an explicit receipt." Canonicalization: "makes retries independent of JSON key ordering" (`command-contract.ts`).
- **Alternatives considered**: Engine-only nonce memory (kept as defense in depth but bounded to 16, lost on lobby rebuild); delivery-coupled acknowledgement *(rejected: delivery is best-effort)*.

## D6. Client write-ahead outbox; one pending command; no optimistic apply

- **Decision**: `OnlineCommandOutbox` writes the envelope to disk before sending; submission is disabled if that fails; the same ID is retried (2→8 s) until a receipt; legal actions are hidden while submitting.
- **Rationale**: "Clients persist one pending command per table and account, retrying the same ID until a durable receipt resolves it. Reconnect refreshes a seat projection; animation is local presentation and never advances game authority." (`docs/MULTIPLAYER.md`). The client has no engine for online tables, so optimistic apply is impossible (*inferred*).
- **Alternatives considered**: In-memory only pending command *(rejected: lost on relaunch — `testPendingMoveSurvivesClientRestartAndReceiptClearsIt`)*; command queue of many moves *(not needed: one actor at a time)*.

## D7. Server bots via durable alarms, one move per alarm

- **Decision**: `botPending` from the engine; `PreferansTable.alarm` calls `/v1/bots` once per alarm, every 500 ms; failures back off to 60 s.
- **Rationale**: "Bots run as durable scheduled actions, independently of a human command's commit" (`docs/MULTIPLAYER.md`); "pacing and continuation belong to the durable room alarm" (`AuthoritativeGameService.advanceBots`); 500 ms "Matches BotPacing.interactive; server-owned presentation cadence" (`index.ts`). The human commit must not wait for bots (`testServerRunsBotSeatsUntilAHumanMustAct`).
- **Alternatives considered**: Run the bot cascade inside the command request (the 512-action guard is a remnant) — rejected for latency and crash safety; host-device bots (old design, `RoomBotMoveScheduler`).

## D8. Account identity + per-seat rotating credentials

- **Decision**: Seats bind to server-issued account IDs; every claimed human seat has a server-minted 24-char token returned only to its owner; `/join` of a held seat rotates it and closes older sockets; host-only HTTP actions need both the account session and the current seat token.
- **Rationale**: `00a34dd`/`joinRoom` comment: "two fresh installs both default to the same roster name, so trusting the declared seat let a joiner collide with — and silently overwrite — an occupied seat (including the host's)". `9f02688`: the room code was the only credential. `authorizeHostSeat`: "an account can have several bearer sessions, while exactly one device may own a live seat." `joinRoom`: "The newest join is the sole active device for that seat; a stale phone can neither reconnect nor keep reporting host state with a copied credential."
- **Alternatives considered**: Room-code-only access (pre-`9f02688`); a separate long-lived host secret (`0426f1f` introduced `hostSecret`; later removed: "there is no second long-lived host secret to leak or synchronize", `/join` comment); a `REQUIRE_SEAT_TOKENS` compatibility flag for builds ≤ 24 (`9f02688`; removed — "The v2 API has no compatibility window").

## D9. Sign in with Apple + server-issued guest accounts; hashed bearer sessions

- **Decision**: Two providers (`apple`, `guest`); Apple tokens verified server-side with nonce binding; sessions `pref2.<b64 accountID>.<secret>` stored as SHA-256, 180-day lifetime, ≤ 5 per account; bearer kept in the Keychain (`ThisDeviceOnly`).
- **Rationale**: README "App Store Notes": Sign in with Apple for optional identity. `OnlineAccountSessionStore` comment: the bearer "grants access to every game owned by the account, so it is kept in Keychain rather than UserDefaults. The service and account names are versioned: old trust-based identities can never be loaded accidentally after the clean break." `AppIdentifiers.onlineAccountSchemaVersion`: "V1 identities are intentionally rejected so every online player registers through the authenticated API."
- **Alternatives considered**: Client-declared identities (v1, rejected); Game Center identity (`gameCenter` provider remains in enums, unused); "In-app email/Gmail test profile" mentioned in README is **not implemented** (only `email` enum case exists).

## D10. Deterministic server-side lobby-manager election with an epoch

- **Decision**: `electLiveHost` picks the first connected human in seat order when the manager has no live socket; `hostEpoch` increments; clients ignore roster frames with an older epoch.
- **Rationale**: "making migration deterministic and split-brain resistant. Terminal tables never migrate because they have no authority left to recover" (`room-state.ts`); "letting clients distinguish a real authority migration from an out-of-order presence frame" (`RoomState.hostEpoch`). Under server authority the manager only starts deals and fills bots ("`isHost` now means lobby manager only").
- **Alternatives considered**: Client-side election (old `chooseHost` in in-memory transport); no migration *(rejected: deals could not be started after manager loss)*.

## D11. No relay message history; caps on input sizes

- **Decision**: `recordRelay` sequences but does not store messages; frames and HTTP bodies ≤ 128 KiB; display names ≤ 60 chars.
- **Rationale**: `9bd77c1`: the 200-entry history "that nothing ever read back" made every relayed frame rewrite "a megabyte-class blob". Names are rebroadcast in every presence frame.
- **Alternatives considered**: Replay log for reconnect *(rejected; reconnect uses the latest stored projection)*.

## D12. Durable library outbox and synchronous creator indexing

- **Decision**: Create/join upsert the actor's library row synchronously before commit; all other library updates are a durable `libraryDirty` flag drained by alarms; removals are a durable list.
- **Rationale**: "Account deletion enumerates this durable membership index. A room must not become visible until its creator can later find and delete it; transition-only refreshes remain best-effort below." (`/create`); "Library updates use a durable outbox with retry" (`docs/MULTIPLAYER.md`); `runtime-test` "failed library delivery stays durable until a later alarm repairs it".
- **Alternatives considered**: Best-effort fan-out in the request path (earlier `fanOutToLibraries`, now only schedules an alarm).

## D13. Public directory: leased, revisioned, privacy-minimized listings

- **Decision**: One `PublicTableDirectory` instance holds `{revision, expiresAt, table?}` per room; rooms publish from alarms; 90 s lease; 30 s renewal; ≤ 50 rows per page; join always re-checks the room.
- **Rationale**: `docs/PUBLIC_LOBBY.md`: only display names, readiness/connection flags, pool settings, codes, occupancy and lifecycle enter the directory; "Joining always checks the current authoritative room, so a stale listing cannot grant a seat"; "A failed publish never undoes a seated move" (`public-directory.ts`).
- **Alternatives considered**: Listing by scanning room objects *(not possible in DO model — inferred)*; directory as authority for seats *(rejected)*.

## D14. Server-enforced public presets and readiness gate

- **Decision**: Public tables use only `odesa`/`wien`/`thessaloniki` with rules from `fixtures/public-rules.json`; humans only; explicit Ready from every connected player before the first deal.
- **Rationale**: "The Worker supplies canonical rules and all-pass progression from the preset, so a creator cannot advertise one convention while sending different scoring rules" and "Each player explicitly confirms Ready after seeing the immutable table settings" (`docs/PUBLIC_LOBBY.md`). Parity verified by `PublicTableRulesTests`.
- **Alternatives considered**: Trusting client-sent rules for public tables *(rejected)*; bots in public tables *(rejected: "Public tables wait for human players")*.

## D15. Room-scoped identities in public rooms

- **Decision**: Non-caller human accounts are replaced with `seat:<CODE>:<seat>` in rosters, library rows, engine identities and delivered projections; stored legacy projections are re-masked on delivery.
- **Rationale**: "Public participant rosters retain only the authenticated caller's own global ID… Previously persisted projections are masked on delivery." (`docs/PUBLIC_LOBBY.md`); "Re-mask at delivery as well: rooms saved before this fix may contain global IDs." (`projectionWireMessage`).
- **Alternatives considered**: Masking in private rooms too — not done (friends' rooms keep real IDs; see spec gap 3).

## D16. Compatibility gate and separate owner backend (build 29)

- **Decision**: The app checks `/health` (service name + both schema versions) before any create/join; credentials use the `.owner-v1` storage suffix; invites are accepted only for the current backend host; a fresh owner Worker (`wrangler.owner.toml`) with a pinned image digest.
- **Rationale**: Root cause in `docs/OWNER_MULTIPLAYER_BUILD29.md`: build 28 required protocol 4 while the configured server returned room protocol 3 and 404 for `/v2/public-tables`; "Successful account registration did not imply compatible room creation." `AppIdentifiers`: "Never send the old server's bearer/seat credentials to the new backend. Preserve legacy storage so this update does not erase old account data." Old/foreign-server invite URLs "are rejected rather than resolving their code against the wrong database."
- **Alternatives considered**: Data migration/proxy from the old account — explicitly not performed ("No D1 import, old-account copy or old-endpoint proxy was performed").

## D17. Keep the legacy peer-host stack for the in-memory room

- **Decision**: `RoomOnlineGameCoordinator`, `HostGameActor`, `InMemoryRoomTransport` and helpers remain, used only by `InMemoryOnlineGameSession` (UI-test launch flags).
- **Rationale** *(inferred)*: Provides a worker-free online waiting-room/table smoke path ("Lands on the same waiting room as a real room — host taps Start and the bot seats play out — without a worker or a second device", `LobbyViewModel.startInMemoryOnlineRoom`) and preserves a large regression suite. "Offline simulation is a separate execution path" (`docs/MULTIPLAYER.md`).
- **Alternatives considered**: Delete the stack *(not done)*; run the in-memory room through `ServerGameCoordinator` with an in-process engine service *(not done)*.

## D18. Build-only server CI without credentials

- **Decision**: `owner-server-build.yml` validates the Worker, builds and smoke-tests the engine image, exports a 14-day artifact with checksum and provenance; no registry push, no deploy, `contents: read`.
- **Rationale**: `docs/SERVER_CI.md`: "No source-account traffic, migration, production deployment… occurs"; "A future deployment must use the verified image or rebuild the exact reviewed commit". Production deployment "is a separate operation from preparing and committing the upgrade" (`docs/MULTIPLAYER.md`).
- **Alternatives considered**: CI deploy to Cloudflare *(rejected; would need credentials and paid plan activation)*.

## D19. Invite links never auto-join

- **Decision**: Opening an invite only fills the code and switches to Online; the user taps Join.
- **Rationale** *(inferred)*: joining requires an account and a compatibility check; avoids silently consuming an open seat from a link preview.
- **Alternatives considered**: Auto-join (exists only behind UI-test flag `-uiTestAutoJoinOnlineRoom`).

## Open research items

- Production cold-start latency and concurrency of the 3-container pool (stated as unmeasured in `docs/MULTIPLAYER.md` and the worker README).
- Retention/TTL for finished rooms, receipts and private checkpoints (none implemented).
- Whether match results (`summary.result`) should be produced by the engine for the library.
