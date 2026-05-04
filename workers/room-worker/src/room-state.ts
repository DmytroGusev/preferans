export const ROOM_SCHEMA_VERSION = 1;
export const DEFAULT_MAX_PLAYERS = 4;
export const MAX_RECENT_MESSAGES = 200;

const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const ACCOUNT_PROVIDERS = new Set<OnlineAccountProvider>(["gameCenter", "apple", "email", "dev"]);

export type OnlineAccountProvider = "gameCenter" | "apple" | "email" | "dev";

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
  peers: OnlinePeer[];
  maxPlayers: number;
  createdAt: string;
  updatedAt: string;
  relaySequence: number;
  recentMessages: RelayEntry[];
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

export function generateRoomCode(random: () => number = Math.random): string {
  let code = "";
  for (let index = 0; index < 6; index += 1) {
    const alphabetIndex = Math.floor(random() * ROOM_CODE_ALPHABET.length);
    code += ROOM_CODE_ALPHABET[alphabetIndex] ?? ROOM_CODE_ALPHABET[0];
  }
  return code;
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
    relaySequence: room.relaySequence ?? 0
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

  return {
    schemaVersion: ROOM_SCHEMA_VERSION,
    roomCode: normalizedRoomCode,
    hostPlayerID: peerID(peers[0]),
    peers,
    maxPlayers: normalizedMaxPlayers,
    createdAt: now,
    updatedAt: now,
    relaySequence: 0,
    recentMessages: []
  };
}

export function joinRoom(room: RoomState, localPeer: unknown, now = new Date().toISOString()): RoomState {
  const peer = normalizePeer(localPeer);
  const id = peerID(peer);
  const existingIndex = room.peers.findIndex((candidate) => peerID(candidate) === id);
  const peers = [...room.peers];

  if (existingIndex >= 0) {
    peers[existingIndex] = peer;
  } else {
    if (peers.length >= room.maxPlayers) {
      throw new RoomStateError("room_full", "Room is full.", 409);
    }
    peers.push(peer);
  }

  return {
    ...room,
    hostPlayerID: room.hostPlayerID || id,
    peers,
    updatedAt: now
  };
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
