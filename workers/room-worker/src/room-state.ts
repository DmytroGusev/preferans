export const ROOM_SCHEMA_VERSION = 2;
export const DEFAULT_MAX_PLAYERS = 4;
/// Longest accepted display name; anything longer is truncated on the way in
/// so a client can't grow the stored room (and every presence broadcast)
/// without bound.
export const MAX_DISPLAY_NAME_LENGTH = 60;
/// Largest accepted relay frame. Projections are a few KB; the resume
/// snapshot travels over HTTP `/state`, never the socket — so anything this
/// large is abuse, not gameplay.
export const MAX_SOCKET_MESSAGE_BYTES = 128 * 1024;

/// Account-ID prefix the host stamps on a seat it has reserved but nobody has
/// claimed yet. `joinRoom` binds a joiner to the first such seat. Kept in sync
/// with the Swift client's `OnlinePeer.pendingAccountPrefix`.
///
/// The Swift client also uses a `bot:` prefix (`OnlinePeer.botAccountPrefix`)
/// for seats the host fills with a server-side bot. The worker needs no special
/// case for it: only `pending:` accounts are "open" (see `joinRoom`), so a
/// `bot:` seat — like any non-`pending:` account — is treated as occupied and a
/// late human can never claim it.
export const PENDING_ACCOUNT_PREFIX = "pending:";

/// Account-ID prefix for a seat the host fills with a server-side bot it drives
/// itself. Kept in sync with the Swift client's `OnlinePeer.botAccountPrefix`.
/// A `bot:` seat is not `pending:`, so — like any claimed seat — it can never be
/// taken by a late joiner.
export const BOT_ACCOUNT_PREFIX = "bot:";

/// Tombstone used after an account is permanently deleted. Unlike an open
/// `pending:` seat it cannot be claimed in a completed/abandoned game, and it
/// is excluded from account-library fan-out just like bots and open seats.
export const DELETED_ACCOUNT_PREFIX = "deleted:";

const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const SEAT_TOKEN_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
const ACCOUNT_PROVIDERS = new Set<OnlineAccountProvider>(["gameCenter", "apple", "email", "guest", "dev"]);
const GAME_STATUSES = new Set<GameStatus>(["lobby", "playing", "finished", "abandoned"]);

export type OnlineAccountProvider = "gameCenter" | "apple" | "email" | "guest" | "dev";

/// Lifecycle of a table, mirrored from the Swift client's `PreferansGameStatus`.
/// The worker treats it as an opaque-but-validated label the host reports; it
/// drives the lobby's Continue (`playing`/`lobby`) vs History (`finished`)
/// split and lets a stale room be swept to `abandoned`.
export type GameStatus = "lobby" | "playing" | "finished" | "abandoned";

/// Tiny, worker-readable result kept for finished games so the History list can
/// render a winner + final balance without decoding the dropped snapshot blob.
export interface GameResultSummary {
  /// Seat that won the match, when there is a single winner.
  winner?: WirePlayerID;
  /// Final normalized whist balance per seat (`playerID.rawValue` → points).
  finalBalances?: Record<string, number>;
}

/// Host-authored, worker-readable metadata about a table's progress. Fanned out
/// to each participant's `PlayerLibrary` so the lobby can describe a game
/// ("Odesa · deal 3 · bidding") without ever decoding the opaque snapshot.
export interface GameSummary {
  /// Rules variant identifier (`"odesa"` | `"wien"`), opaque to the worker.
  variant?: string;
  /// Authoritative action sequence at the time of the report.
  lastSequence: number;
  /// Coarse phase label for the lobby row (e.g. `"bidding"`, `"playing"`).
  phase?: string;
  /// 1-based deal number within the match.
  dealNumber?: number;
  /// Present once `status === "finished"`.
  result?: GameResultSummary;
}

export interface WirePlayerID {
  rawValue: string;
}

export interface OnlinePeer {
  playerID: WirePlayerID;
  accountID: string;
  provider: OnlineAccountProvider;
  displayName: string;
  /// Server-minted credential proving the caller owns this seat. Present on
  /// every claimed human seat; handed to exactly one caller (the seat's owner,
  /// in its `/create` or `/join` response) and stripped from every public
  /// payload by `normalizePeer` — see the `publicRoom` seat-token test.
  seatToken?: string;
}

export interface RoomState {
  schemaVersion: number;
  roomCode: string;
  hostPlayerID: string;
  /// Monotonic generation of server-elected host authority. It starts at one
  /// and advances whenever the live host changes, letting clients distinguish
  /// a real authority migration from an out-of-order presence frame.
  hostEpoch: number;
  peers: OnlinePeer[];
  maxPlayers: number;
  createdAt: string;
  updatedAt: string;
  relaySequence: number;
  /// Lifecycle status, host-reported. Defaults to `lobby` at creation.
  status: GameStatus;
  /// Latest host-reported progress metadata (worker-readable). `undefined`
  /// until the host sends its first state report.
  summary?: GameSummary;
  /// Opaque authoritative engine snapshot the resuming host hydrates from. The
  /// worker never decodes it; dropped once the game is finished/abandoned.
  latestSnapshot?: unknown;
  /// Action sequence the stored `latestSnapshot` was taken at, so an
  /// out-of-order report can't clobber a newer snapshot with an older one.
  lastSnapshotSequence?: number;
}

export interface PublicRoom {
  schemaVersion: number;
  roomCode: string;
  hostPlayerID: WirePlayerID;
  hostEpoch: number;
  peers: OnlinePeer[];
  maxPlayers: number;
  createdAt: string;
  updatedAt: string;
  relaySequence: number;
  /// Live status so guests can tell a still-forming room from one in play.
  status: GameStatus;
  /// Progress metadata (no snapshot blob — that stays server-only).
  summary?: GameSummary;
}

export interface CreateRoomInput {
  roomCode: string;
  localPeer: unknown;
  seats?: unknown[];
  maxPlayers?: number;
  now?: string;
}

export interface RelayEntry {
  serverSequence: number;
  senderPlayerID: string;
  recipientPlayerIDs: string[];
  message: unknown;
  sentAt: string;
}

export interface RelayInput {
  senderPlayerID: unknown;
  recipientPlayerIDs: unknown[];
  message: unknown;
}

export class RoomStateError extends Error {
  public readonly code: string;
  public readonly status: number;

  constructor(code: string, message: string, status = 400) {
    super(message);
    this.name = "RoomStateError";
    this.code = code;
    this.status = status;
  }
}

/// Uniform random in [0, 1) from the platform CSPRNG. Room codes gate who can
/// find a table and secrets/tokens gate who can act at it, so none of them may
/// come from the predictable `Math.random`. Tests keep injecting deterministic
/// generators through the `random` parameters below.
function secureRandom(): number {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return buffer[0] / 2 ** 32;
}

export function generateRoomCode(random: () => number = secureRandom): string {
  let code = "";
  for (let index = 0; index < 6; index += 1) {
    const alphabetIndex = Math.floor(random() * ROOM_CODE_ALPHABET.length);
    code += ROOM_CODE_ALPHABET[alphabetIndex] ?? ROOM_CODE_ALPHABET[0];
  }
  return code;
}

export function generateSeatToken(random: () => number = secureRandom): string {
  let token = "";
  for (let index = 0; index < 24; index += 1) {
    const alphabetIndex = Math.floor(random() * SEAT_TOKEN_ALPHABET.length);
    token += SEAT_TOKEN_ALPHABET[alphabetIndex] ?? SEAT_TOKEN_ALPHABET[0];
  }
  return token;
}

export function normalizeRoomCode(value: unknown): string {
  const code = String(value ?? "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  if (code.length < 4 || code.length > 12) {
    throw new RoomStateError("invalid_room_code", "Room code must be 4-12 letters or numbers.");
  }
  return code;
}

export function playerIDValue(value: unknown): string {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed) return trimmed;
  }
  if (isRecord(value) && typeof value.rawValue === "string") {
    const trimmed = value.rawValue.trim();
    if (trimmed) return trimmed;
  }
  throw new RoomStateError("invalid_player_id", "Player ID is required.");
}

export function wirePlayerID(value: unknown): WirePlayerID {
  return { rawValue: playerIDValue(value) };
}

export function normalizePeer(input: unknown): OnlinePeer {
  if (!isRecord(input)) {
    throw new RoomStateError("invalid_peer", "Peer is required.");
  }

  const playerID = wirePlayerID(input.playerID);
  const id = playerID.rawValue;
  const accountID = String(input.accountID ?? `dev:${id}`).trim();
  const provider = isOnlineAccountProvider(input.provider) ? input.provider : "dev";
  const displayName =
    (String(input.displayName ?? id).trim() || id).slice(0, MAX_DISPLAY_NAME_LENGTH);

  return {
    playerID,
    accountID,
    provider,
    displayName
  };
}

export function peerID(peer: Pick<OnlinePeer, "playerID">): string {
  return playerIDValue(peer.playerID);
}

export function publicRoom(room: RoomState): PublicRoom {
  return {
    schemaVersion: ROOM_SCHEMA_VERSION,
    roomCode: room.roomCode,
    hostPlayerID: wirePlayerID(room.hostPlayerID),
    hostEpoch: room.hostEpoch ?? 1,
    peers: room.peers.map(normalizePeer),
    maxPlayers: room.maxPlayers,
    createdAt: room.createdAt,
    updatedAt: room.updatedAt,
    relaySequence: room.relaySequence ?? 0,
    status: room.status ?? "lobby",
    summary: room.summary
  };
}

export function createInitialRoom({
  roomCode,
  localPeer,
  seats,
  maxPlayers = DEFAULT_MAX_PLAYERS,
  now = new Date().toISOString()
}: CreateRoomInput): RoomState {
  const normalizedRoomCode = normalizeRoomCode(roomCode);
  const normalizedMaxPlayers = clampMaxPlayers(maxPlayers);
  const peers = uniquePeers((seats?.length ? seats : [localPeer]).map(normalizePeer));
  const local = normalizePeer(localPeer);

  if (!peers.some((peer) => peerID(peer) === peerID(local))) {
    peers.unshift(local);
  }
  if (peers.length > normalizedMaxPlayers) {
    throw new RoomStateError("room_full", "Room has more seats than its maximum player count.");
  }

  // Every claimed human seat gets its ownership credential at birth. Open
  // (`pending:`) and bot seats get theirs when — if ever — a human claims them
  // in `joinRoom`. Only the creator's own token leaves the server in the
  // `/create` response; a pre-seated friend receives theirs on `/join`.
  for (let index = 0; index < peers.length; index += 1) {
    if (isHumanAccount(peers[index].accountID)) {
      peers[index] = { ...peers[index], seatToken: generateSeatToken() };
    }
  }

  return {
    schemaVersion: ROOM_SCHEMA_VERSION,
    roomCode: normalizedRoomCode,
    // The authenticated local peer is the creator even when its requested
    // table position is not the first item in seat order.
    hostPlayerID: peerID(local),
    hostEpoch: 1,
    peers,
    maxPlayers: normalizedMaxPlayers,
    createdAt: now,
    updatedAt: now,
    relaySequence: 0,
    status: "lobby"
  };
}

/// Convert every still-open (`pending:`) seat into a host-driven bot, binding the
/// bot's account to its seat (`bot:<playerID>`). Claimed and already-bot seats are
/// left untouched. Returns the same room reference when nothing was open, so the
/// caller can skip the storage write and presence broadcast.
export function fillOpenSeatsWithBots(room: RoomState, now = new Date().toISOString()): RoomState {
  let changed = false;
  const peers = room.peers.map((peer, index) => {
    if (!peer.accountID.startsWith(PENDING_ACCOUNT_PREFIX)) {
      return peer;
    }
    changed = true;
    return {
      ...peer,
      accountID: `${BOT_ACCOUNT_PREFIX}${peerID(peer)}`,
      provider: "dev" as OnlineAccountProvider,
      displayName: `Bot ${index + 1}`,
      // A bot seat is driven by the host over the host's own socket; it never
      // authenticates itself, so it carries no credential to steal.
      seatToken: undefined
    };
  });
  if (!changed) {
    return room;
  }
  return { ...room, peers, updatedAt: now };
}

export function joinRoom(room: RoomState, localPeer: unknown, now = new Date().toISOString()): RoomState {
  const peer = normalizePeer(localPeer);
  const peers = [...room.peers];

  // Identity is the globally-unique account, never the self-declared seat
  // `playerID`: two fresh installs both default to the same roster name, so
  // trusting the declared seat let a joiner collide with — and silently
  // overwrite — an occupied seat (including the host's). Binding on `accountID`
  // and letting the server own the seat token makes that impossible.

  // Rejoin: this account already holds a seat. Refresh its display fields and
  // keep the seat, but rotate its room credential. The newest join is the sole
  // active device for that seat; a stale phone can neither reconnect nor keep
  // reporting host state with a copied credential.
  const heldIndex = peers.findIndex((candidate) => candidate.accountID === peer.accountID);
  if (heldIndex >= 0) {
    peers[heldIndex] = {
      ...peer,
      playerID: peers[heldIndex].playerID,
      seatToken: generateSeatToken()
    };
    return { ...room, peers, updatedAt: now };
  }

  // New account: claim an open (reserved-but-unclaimed) seat. Honor the seat the
  // joiner asked for when it's still open, otherwise fall back to the first open
  // seat. Only *open* seats are ever claimable, so a joiner can never overwrite
  // an occupied seat (e.g. the host): two fresh installs that both default to the
  // same seat name are redirected to different open seats instead of colliding.
  const isOpenSeat = (candidate: OnlinePeer) => candidate.accountID.startsWith(PENDING_ACCOUNT_PREFIX);
  const declaredID = peerID(peer);
  const requestedIndex = peers.findIndex((candidate) => isOpenSeat(candidate) && peerID(candidate) === declaredID);
  const openIndex = requestedIndex >= 0 ? requestedIndex : peers.findIndex(isOpenSeat);
  if (openIndex >= 0) {
    // A fresh claim mints a fresh token: whatever placeholder credential the
    // open seat may have carried never belonged to this account.
    peers[openIndex] = { ...peer, playerID: peers[openIndex].playerID, seatToken: generateSeatToken() };
    return { ...room, peers, updatedAt: now };
  }

  // Every seat is claimed or reserved by another account — the table is full.
  throw new RoomStateError("room_full", "Room is full.", 409);
}

export interface AccountRemovalResult {
  room: RoomState;
  removedPlayerIDs: string[];
}

/// Remove every durable identity and credential owned by an account. Lobby
/// seats reopen for another invitee; an in-progress table is abandoned because
/// its engine snapshot can no longer have a complete authenticated roster.
/// Finished history keeps seat/result facts but anonymizes the deleted player.
export function removeAccountFromRoom(
  room: RoomState,
  accountID: string,
  now = new Date().toISOString()
): AccountRemovalResult {
  const removedPlayerIDs = room.peers
    .filter((peer) => peer.accountID === accountID)
    .map(peerID);
  if (removedPlayerIDs.length === 0) {
    return { room, removedPlayerIDs };
  }

  const lobby = (room.status ?? "lobby") === "lobby";
  const peers = room.peers.map((peer): OnlinePeer => {
    if (peer.accountID !== accountID) return peer;
    const playerID = peerID(peer);
    return {
      playerID: peer.playerID,
      accountID: `${lobby ? PENDING_ACCOUNT_PREFIX : DELETED_ACCOUNT_PREFIX}${playerID}`,
      provider: "dev",
      displayName: lobby ? "Open seat" : "Deleted player"
    };
  });
  let updated: RoomState = { ...room, peers, updatedAt: now };
  if (room.status === "playing") {
    updated = applyStateReport(updated, { status: "abandoned" }, now).room;
  }
  return { room: updated, removedPlayerIDs };
}

export function routeRecipients(room: RoomState, senderPlayerID: unknown, recipients?: unknown[]): string[] {
  const sender = playerIDValue(senderPlayerID);
  const known = new Set(room.peers.map(peerID));
  const requested = recipients?.length
    ? recipients.map(playerIDValue)
    : room.peers.map(peerID);

  return [...new Set(requested)]
    .filter((id) => id !== sender)
    .filter((id) => known.has(id));
}

/// Reject wire frames whose message kind is host-authoritative when they come
/// from any other seat. Clients also validate the sender, but enforcing this in
/// the relay closes the split-brain window during host migration and avoids
/// forwarding known forgeries at all.
export function authorizeRelayMessage(room: RoomState, senderPlayerID: unknown, message: unknown): void {
  const sender = playerIDValue(senderPlayerID);
  if (!isRecord(message)) {
    throw new RoomStateError("invalid_wire_message", "Wire message must be an object.");
  }
  const hostOnly = ["seatAssignment", "projection", "hostError"];
  if (hostOnly.some((kind) => Object.hasOwn(message, kind)) && sender !== room.hostPlayerID) {
    throw new RoomStateError("forbidden", "Only the current host can send authoritative frames.", 403);
  }
}

/// Sequence a relayed message. The entry is delivered to live sockets and then
/// discarded — the room deliberately stores no message history. It used to keep
/// the last 200 entries (each carrying a full projection JSON) that nothing
/// ever read back, so every relayed frame rewrote a megabyte-class room blob.
export function recordRelay(room: RoomState, { senderPlayerID, recipientPlayerIDs, message }: RelayInput, now = new Date().toISOString()): { room: RoomState; entry: RelayEntry } {
  const currentSequence = room.relaySequence ?? 0;
  if (!Number.isSafeInteger(currentSequence) || currentSequence < 0 || currentSequence >= Number.MAX_SAFE_INTEGER) {
    throw new RoomStateError(
      "relay_sequence_exhausted",
      "Room relay sequence is invalid or exhausted.",
      409
    );
  }
  const serverSequence = currentSequence + 1;
  const entry = {
    serverSequence,
    senderPlayerID: playerIDValue(senderPlayerID),
    recipientPlayerIDs: recipientPlayerIDs.map(playerIDValue),
    message,
    sentAt: now
  };
  return {
    room: {
      ...room,
      relaySequence: serverSequence,
      updatedAt: now
    },
    entry
  };
}

export interface StateReportInput {
  status?: unknown;
  summary?: unknown;
  snapshot?: unknown;
  snapshotSequence?: unknown;
}

export interface StateReportResult {
  room: RoomState;
  /// True when a material change (status / deal / phase / result) means the
  /// participants' library entries should be refreshed. Per-action snapshot
  /// pushes that don't move the phase return false, keeping fan-out bounded.
  changed: boolean;
}

/// Fold a host state report into the room: validate the status/summary, store
/// the latest snapshot monotonically (an older out-of-order report can't clobber
/// a newer one), and drop the snapshot once the game is finished/abandoned (it
/// is never resumed). Pure so it can be unit-tested without a Durable Object.
export function applyStateReport(
  room: RoomState,
  input: StateReportInput,
  now: string = new Date().toISOString()
): StateReportResult {
  // Terminal history is immutable. A delayed request from a demoted/old host
  // must never resurrect a finished or abandoned table.
  if (room.status === "finished" || room.status === "abandoned") {
    return { room, changed: false };
  }

  const normalizedStatus = normalizeGameStatus(input.status);
  if (input.status !== undefined && normalizedStatus === undefined) {
    throw new RoomStateError("invalid_state_report", "State report has an invalid status.", 400);
  }
  const requestedStatus = normalizedStatus ?? room.status ?? "lobby";
  const currentStatus = room.status ?? "lobby";
  const validLifecycleTransition = requestedStatus === currentStatus
    || requestedStatus === "abandoned"
    || (currentStatus === "lobby" && requestedStatus === "playing")
    || (currentStatus === "playing" && requestedStatus === "finished");
  if (!validLifecycleTransition) {
    throw new RoomStateError(
      "invalid_state_report",
      `State report cannot move a room from ${currentStatus} to ${requestedStatus}.`,
      409
    );
  }
  const candidateSummary = normalizeGameSummary(input.summary);
  if (requestedStatus !== "abandoned") {
    if (candidateSummary === undefined) {
      throw new RoomStateError("invalid_state_report", "State report requires a summary.", 400);
    }
    const rawSummarySequence = isRecord(input.summary) ? input.summary.lastSequence : undefined;
    const rawSnapshotSequence = input.snapshotSequence;
    if (typeof rawSummarySequence !== "number"
        || !Number.isSafeInteger(rawSummarySequence)
        || rawSummarySequence < 0) {
      throw new RoomStateError("invalid_state_report", "Summary sequence must be a non-negative integer.", 400);
    }
    if (typeof rawSnapshotSequence !== "number"
        || !Number.isSafeInteger(rawSnapshotSequence)
        || rawSnapshotSequence !== rawSummarySequence) {
      throw new RoomStateError(
        "invalid_state_report",
        "Snapshot and summary sequences must match.",
        400
      );
    }
    if (requestedStatus !== "finished" && (input.snapshot === undefined || input.snapshot === null)) {
      throw new RoomStateError(
        "invalid_state_report",
        "A nonterminal state report requires its recoverable snapshot.",
        400
      );
    }
  }
  const currentSequence = room.summary?.lastSequence ?? room.lastSnapshotSequence ?? 0;
  const staleSummary = candidateSummary !== undefined && candidateSummary.lastSequence < currentSequence;
  const summary = staleSummary ? room.summary : candidateSummary ?? room.summary;
  // Abandonment is an explicit participant action and carries no summary. All
  // other stale reports preserve the newer lifecycle alongside the summary.
  const status = staleSummary && requestedStatus !== "abandoned"
    ? room.status ?? "lobby"
    : requestedStatus;
  const terminal = status === "finished" || status === "abandoned";

  let latestSnapshot = room.latestSnapshot;
  let lastSnapshotSequence = room.lastSnapshotSequence ?? 0;
  if (input.snapshot !== undefined && !terminal) {
    const raw = Number(input.snapshotSequence ?? summary?.lastSequence ?? 0);
    const seq = Number.isFinite(raw) ? raw : 0;
    if (seq >= lastSnapshotSequence) {
      latestSnapshot = input.snapshot;
      lastSnapshotSequence = seq;
    }
  }
  if (terminal) {
    latestSnapshot = undefined;
  }

  const updated: RoomState = {
    ...room,
    status,
    summary,
    latestSnapshot,
    lastSnapshotSequence,
    updatedAt: now
  };
  return { room: updated, changed: summarySignature(room) !== summarySignature(updated) };
}

export function normalizeGameStatus(value: unknown): GameStatus | undefined {
  return typeof value === "string" && GAME_STATUSES.has(value as GameStatus)
    ? (value as GameStatus)
    : undefined;
}

export function normalizeGameSummary(value: unknown): GameSummary | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const lastSequenceRaw = Number(value.lastSequence ?? 0);
  const summary: GameSummary = {
    lastSequence: Number.isFinite(lastSequenceRaw) ? lastSequenceRaw : 0
  };
  if (typeof value.variant === "string") {
    summary.variant = value.variant;
  }
  if (typeof value.phase === "string") {
    summary.phase = value.phase;
  }
  const dealNumber = Number(value.dealNumber);
  if (Number.isFinite(dealNumber) && dealNumber > 0) {
    summary.dealNumber = dealNumber;
  }
  const result = normalizeGameResult(value.result);
  if (result) {
    summary.result = result;
  }
  return summary;
}

/// A participant the lobby should list a game for: any seat that is neither a
/// reserved-but-unclaimed (`pending:`) seat nor a host-driven bot (`bot:`).
export function isHumanAccount(accountID: string): boolean {
  return !accountID.startsWith(PENDING_ACCOUNT_PREFIX)
    && !accountID.startsWith(BOT_ACCOUNT_PREFIX)
    && !accountID.startsWith(DELETED_ACCOUNT_PREFIX);
}

/// Authorize a caller claiming `playerID`'s seat, returning the seat on
/// success. The rules, in order:
///
/// - an unknown seat is always rejected;
/// - a presented token that does not match the seat's is always rejected —
///   a caller never gets to "downgrade" a wrong credential into legacy access;
/// - a v2 human seat without a stored token is invalid and rejected;
/// - a missing token is always rejected. The v2 API has no compatibility
///   window: clean-break clients must prove seat ownership on every sensitive
///   path.
export function authorizeSeat(
  room: RoomState,
  playerID: unknown,
  token: unknown
): OnlinePeer {
  const id = playerIDValue(playerID);
  const peer = room.peers.find((candidate) => peerID(candidate) === id);
  if (!peer) {
    throw new RoomStateError("unknown_player", "Player has not joined this room.", 403);
  }
  const expected = peer.seatToken;
  const presented = typeof token === "string" && token.length > 0 ? token : undefined;
  if (expected === undefined) {
    throw new RoomStateError("seat_credential_invalid", "This seat has no valid v2 credential.", 403);
  }
  if (presented !== undefined && presented !== expected) {
    throw new RoomStateError("seat_credential_invalid", "Seat token does not match this seat.", 403);
  }
  if (presented === undefined) {
    throw new RoomStateError("seat_credential_invalid", "A seat token is required.", 403);
  }
  return peer;
}

/// Authorize a host-only mutation with both account and current room
/// credential. Account authentication alone is insufficient: an account can
/// have several bearer sessions, while exactly one device may own a live seat.
export function authorizeHostSeat(
  room: RoomState,
  accountID: string,
  playerID: unknown,
  token: unknown
): OnlinePeer {
  const peer = authorizeSeat(room, playerID, token);
  if (peer.accountID !== accountID) {
    throw new RoomStateError("forbidden", "This account does not own that seat.", 403);
  }
  if (peerID(peer) !== room.hostPlayerID) {
    throw new RoomStateError("forbidden", "Only the current host can perform this operation.", 403);
  }
  return peer;
}

/// Elect the first connected human in stable seat order when the current host
/// has no live socket. The Durable Object calls this after connect/close/error,
/// making migration deterministic and split-brain resistant. Terminal tables
/// never migrate because they have no authority left to recover.
export function electLiveHost(
  room: RoomState,
  connectedPlayerIDs: Iterable<string>,
  now = new Date().toISOString()
): RoomState {
  if (room.status === "finished" || room.status === "abandoned") {
    return room;
  }
  const connected = new Set(connectedPlayerIDs);
  if (connected.has(room.hostPlayerID)) {
    return room;
  }
  const successor = room.peers.find(
    (peer) => isHumanAccount(peer.accountID) && connected.has(peerID(peer))
  );
  if (!successor) {
    return room;
  }
  return {
    ...room,
    hostPlayerID: peerID(successor),
    hostEpoch: (room.hostEpoch ?? 1) + 1,
    updatedAt: now
  };
}

/// True when `accountID` holds the room's current server-elected host seat.
/// Sensitive mutations additionally require ``authorizeHostSeat`` so another
/// bearer session for the same account cannot impersonate the active device.
export function isHostAccount(room: RoomState, accountID: string): boolean {
  if (!isHumanAccount(accountID)) {
    return false;
  }
  const hostSeat = room.peers.find((peer) => peerID(peer) === room.hostPlayerID);
  return hostSeat !== undefined && hostSeat.accountID === accountID;
}

export function humanPeers(room: RoomState): OnlinePeer[] {
  return room.peers.filter((peer) => isHumanAccount(peer.accountID));
}

function normalizeGameResult(value: unknown): GameResultSummary | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const result: GameResultSummary = {};
  if (value.winner !== undefined) {
    try {
      result.winner = wirePlayerID(value.winner);
    } catch {
      // Ignore an unparseable winner — the rest of the result still stands.
    }
  }
  if (isRecord(value.finalBalances)) {
    const balances: Record<string, number> = {};
    for (const [seat, raw] of Object.entries(value.finalBalances)) {
      const balance = Number(raw);
      if (seat && Number.isFinite(balance)) {
        balances[seat] = balance;
      }
    }
    result.finalBalances = balances;
  }
  return Object.keys(result).length > 0 ? result : undefined;
}

function summarySignature(room: RoomState): string {
  return [
    room.status ?? "lobby",
    room.summary?.dealNumber ?? "",
    room.summary?.phase ?? "",
    room.summary?.result ? "done" : ""
  ].join("|");
}

function uniquePeers(peers: OnlinePeer[]): OnlinePeer[] {
  const seen = new Set<string>();
  const result: OnlinePeer[] = [];
  for (const peer of peers) {
    const id = peerID(peer);
    if (seen.has(id)) {
      throw new RoomStateError("duplicate_player", `Duplicate player ID: ${id}.`);
    }
    seen.add(id);
    result.push(peer);
  }
  return result;
}

function clampMaxPlayers(value: unknown): number {
  const maxPlayers = Number(value);
  if (!Number.isInteger(maxPlayers) || maxPlayers < 3 || maxPlayers > 4) {
    throw new RoomStateError("invalid_max_players", "Preferans rooms support 3 or 4 players.");
  }
  return maxPlayers;
}

function isOnlineAccountProvider(value: unknown): value is OnlineAccountProvider {
  return typeof value === "string" && ACCOUNT_PROVIDERS.has(value as OnlineAccountProvider);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}
