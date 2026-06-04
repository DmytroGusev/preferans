import {
  type GameResultSummary,
  type GameStatus,
  type OnlinePeer,
  type RoomState,
  type WirePlayerID,
  normalizePeer,
  wirePlayerID
} from "./room-state.ts";

/// One row in a player's game library — everything the lobby needs to render a
/// "Your games" entry and to resume it, without ever decoding the snapshot blob.
/// Rooms fan these out (one per human seat) into each participant's
/// `PlayerLibrary` Durable Object on every material transition.
export interface GameSummaryEntry {
  roomCode: string;
  hostPlayerID: WirePlayerID;
  status: GameStatus;
  maxPlayers: number;
  /// Roster (display names + seats) for the lobby row.
  peers: OnlinePeer[];
  /// The seat this library's account holds at the table.
  youSeat: WirePlayerID;
  variant?: string;
  phase?: string;
  dealNumber?: number;
  lastSequence: number;
  /// Present once the match is `finished`.
  result?: GameResultSummary;
  createdAt: string;
  updatedAt: string;
}

/// Per-account library: a map of roomCode → latest entry. Keyed so a re-report
/// for the same room replaces (never duplicates) the prior entry.
export interface LibraryState {
  games: Record<string, GameSummaryEntry>;
}

export function emptyLibrary(): LibraryState {
  return { games: {} };
}

/// Project a room into the library entry for one of its seats. Pure, so the
/// fan-out shape is unit-testable without a Durable Object.
export function buildSummaryEntry(room: RoomState, seat: OnlinePeer): GameSummaryEntry {
  const summary = room.summary;
  return {
    roomCode: room.roomCode,
    hostPlayerID: wirePlayerID(room.hostPlayerID),
    status: room.status ?? "lobby",
    maxPlayers: room.maxPlayers,
    peers: room.peers.map(normalizePeer),
    youSeat: seat.playerID,
    variant: summary?.variant,
    phase: summary?.phase,
    dealNumber: summary?.dealNumber,
    lastSequence: summary?.lastSequence ?? room.relaySequence ?? 0,
    result: summary?.result,
    createdAt: room.createdAt,
    updatedAt: room.updatedAt
  };
}

export function upsertGame(state: LibraryState, entry: GameSummaryEntry): LibraryState {
  return { games: { ...state.games, [entry.roomCode]: entry } };
}

export function removeGame(state: LibraryState, roomCode: string): LibraryState {
  if (!(roomCode in state.games)) {
    return state;
  }
  const games = { ...state.games };
  delete games[roomCode];
  return { games };
}

/// Most-recently-updated first — the order the lobby lists "Your games".
export function listGames(state: LibraryState): GameSummaryEntry[] {
  return Object.values(state.games).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}
