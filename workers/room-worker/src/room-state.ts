export const ROOM_SCHEMA_VERSION = 1;
export const DEFAULT_MAX_PLAYERS = 4;
export const MAX_RECENT_MESSAGES = 200;

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

const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const HOST_SECRET_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
const ACCOUNT_PROVIDERS = new Set<OnlineAccountProvider>(["gameCenter", "apple", "email", "dev"]);
const GAME_STATUSES = new Set<GameStatus>(["lobby", "playing", "finished", "abandoned"]);

export type OnlineAccountProvider = "gameCenter" | "apple" | "email" | "dev";

/// Lifecycle of a table, mirrored from the Swift client's `PreferansGameStatus`.
/// The worker treats it as an opaque-but-validated label the host reports; it
/// drives the lobby's Continue (`playing`/`lobby`) vs History (`finished`)
/// split and lets a stale room be swept to `abandoned`.
export type GameStatus = "lobby" | "playing" | "finished" | "abandoned";

/// Tiny, worker-readable result kept for finished games so the History list can
/// render a winner + final pool without decoding the (dropped) snapshot blob.
export interface GameResultSummary {
  /// Seat that won the match, when there is a single winner.
  winner?: WirePlayerID;
  /// Final pool score per seat (`playerID.rawValue` → points).
  finalScores?: Record<string, number>;
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
}

export interface RoomState {
  schemaVersion: number;
  roomCode: string;
  hostPlayerID: string;
  /// Secret minted at creation and handed back only in the `/create` response.
  /// Required to authenticate host-only mutations. Never included in `publicRoom`,
  /// so it is never broadcast to guests over presence/summary/join.
  hostSecret: string;
  peers: OnlinePeer[];
  maxPlayers: number;
  createdAt: string;
  updatedAt: string;
  relaySequence: number;
  recentMessages: RelayEntry[];
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
  /// Optional override for the generated host secret (tests pin it for
  /// determinism; production lets `createInitialRoom` mint a random one).
  hostSecret?: string;
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

export function generateRoomCode(random: () => number = Math.random): string {
  let code = "";
  for (let index = 0; index < 6; index += 1) {
    const alphabetIndex = Math.floor(random() * ROOM_CODE_ALPHABET.length);
    code += ROOM_CODE_ALPHABET[alphabetIndex] ?? ROOM_CODE_ALPHABET[0];
  }
  return code;
}

export function generateHostSecret(random: () => number = Math.random): string {
  let secret = "";
  for (let index = 0; index < 24; index += 1) {
    const alphabetIndex = Math.floor(random() * HOST_SECRET_ALPHABET.length);
    secret += HOST_SECRET_ALPHABET[alphabetIndex] ?? HOST_SECRET_ALPHABET[0];
  }
  return secret;
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
  const displayName = String(input.displayName ?? id).trim() || id;

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
  now = new Date().toISOString(),
  hostSecret
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

  return {
    schemaVersion: ROOM_SCHEMA_VERSION,
    roomCode: normalizedRoomCode,
    hostPlayerID: peerID(peers[0]),
    hostSecret: hostSecret && hostSecret.length > 0 ? hostSecret : generateHostSecret(),
    peers,
    maxPlayers: normalizedMaxPlayers,
    createdAt: now,
    updatedAt: now,
    relaySequence: 0,
    recentMessages: [],
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
      displayName: `Bot ${index + 1}`
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

  // Rejoin: this account already holds a seat. Refresh its display fields but
  // keep the seat it was assigned, so a reconnecting client lands back where it
  // was instead of consuming a fresh slot.
  const heldIndex = peers.findIndex((candidate) => candidate.accountID === peer.accountID);
  if (heldIndex >= 0) {
    peers[heldIndex] = { ...peer, playerID: peers[heldIndex].playerID };
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
    peers[openIndex] = { ...peer, playerID: peers[openIndex].playerID };
    return { ...room, peers, updatedAt: now };
  }

  // Every seat is claimed or reserved by another account — the table is full.
  throw new RoomStateError("room_full", "Room is full.", 409);
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

export function recordRelay(room: RoomState, { senderPlayerID, recipientPlayerIDs, message }: RelayInput, now = new Date().toISOString()): { room: RoomState; entry: RelayEntry } {
  const serverSequence = (room.relaySequence ?? 0) + 1;
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
      updatedAt: now,
      recentMessages: [...(room.recentMessages ?? []), entry].slice(-MAX_RECENT_MESSAGES)
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
  const status = normalizeGameStatus(input.status) ?? room.status ?? "lobby";
  const summary = normalizeGameSummary(input.summary) ?? room.summary;
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
  return !accountID.startsWith(PENDING_ACCOUNT_PREFIX) && !accountID.startsWith(BOT_ACCOUNT_PREFIX);
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
  if (isRecord(value.finalScores)) {
    const scores: Record<string, number> = {};
    for (const [seat, raw] of Object.entries(value.finalScores)) {
      const score = Number(raw);
      if (Number.isFinite(score)) {
        scores[seat] = score;
      }
    }
    result.finalScores = scores;
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
