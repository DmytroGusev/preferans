import test from "node:test";
import assert from "node:assert/strict";
import {
  applyStateReport,
  createInitialRoom,
  type OnlinePeer
} from "../src/room-state.ts";
import {
  buildSummaryEntry,
  emptyLibrary,
  listGames,
  removeGame,
  upsertGame,
  type GameSummaryEntry
} from "../src/library-state.ts";

const north: OnlinePeer = {
  playerID: { rawValue: "north" },
  accountID: "apple:north",
  provider: "apple",
  displayName: "North"
};

const openEast: OnlinePeer = {
  playerID: { rawValue: "east" },
  accountID: "pending:east",
  provider: "dev",
  displayName: "East"
};

const south: OnlinePeer = {
  playerID: { rawValue: "south" },
  accountID: "apple:south",
  provider: "apple",
  displayName: "South"
};

function playingRoom(now: string): ReturnType<typeof createInitialRoom> {
  const base = createInitialRoom({
    roomCode: "ROOM1",
    localPeer: north,
    seats: [north, openEast, south],
    now
  });
  return applyStateReport(
    base,
    {
      status: "playing",
      summary: { variant: "odesa", lastSequence: 4, phase: "bidding", dealNumber: 1 },
      snapshot: { opaque: true },
      snapshotSequence: 4
    },
    now
  ).room;
}

test("buildSummaryEntry projects the room from a given seat's perspective", () => {
  const room = playingRoom("2026-05-04T00:00:00.000Z");
  const entry = buildSummaryEntry(room, north);

  assert.equal(entry.roomCode, "ROOM1");
  assert.equal(entry.status, "playing");
  assert.equal(entry.variant, "odesa");
  assert.equal(entry.phase, "bidding");
  assert.equal(entry.dealNumber, 1);
  assert.equal(entry.lastSequence, 4);
  assert.deepEqual(entry.youSeat, { rawValue: "north" });
  assert.equal(entry.peers.length, 3);                 // full roster travels with the entry
  assert.deepEqual(entry.hostPlayerID, { rawValue: "north" });
});

test("upsertGame replaces the entry for the same room instead of duplicating it", () => {
  const first = buildSummaryEntry(playingRoom("2026-05-04T00:00:00.000Z"), north);
  const second = buildSummaryEntry(playingRoom("2026-05-04T00:05:00.000Z"), north);

  const state = upsertGame(upsertGame(emptyLibrary(), first), second);
  assert.equal(Object.keys(state.games).length, 1);
  assert.equal(state.games.ROOM1.updatedAt, "2026-05-04T00:05:00.000Z");
});

test("removeGame drops a room and is a no-op for an unknown room", () => {
  const entry = buildSummaryEntry(playingRoom("2026-05-04T00:00:00.000Z"), north);
  const state = upsertGame(emptyLibrary(), entry);

  const removed = removeGame(state, "ROOM1");
  assert.equal(Object.keys(removed.games).length, 0);

  // Unknown room returns the same reference so the DO can skip the write.
  assert.equal(removeGame(state, "GHOST"), state);
});

test("listGames orders games most-recently-updated first", () => {
  const older: GameSummaryEntry = { ...buildSummaryEntry(playingRoom("2026-05-04T00:00:00.000Z"), north), roomCode: "OLD" };
  const newer: GameSummaryEntry = { ...buildSummaryEntry(playingRoom("2026-05-04T01:00:00.000Z"), north), roomCode: "NEW" };

  const state = upsertGame(upsertGame(emptyLibrary(), older), newer);
  assert.deepEqual(listGames(state).map((game) => game.roomCode), ["NEW", "OLD"]);
});
