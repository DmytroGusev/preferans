import test from "node:test";
import assert from "node:assert/strict";
import {
  applyStateReport,
  createInitialRoom,
  fillOpenSeatsWithBots,
  isHumanAccount,
  joinRoom,
  normalizeGameStatus,
  type OnlinePeer,
  playerIDValue,
  publicRoom,
  recordRelay,
  routeRecipients
} from "../src/room-state.ts";

const north: OnlinePeer = {
  playerID: { rawValue: "north" },
  accountID: "email:north@example.test",
  provider: "email",
  displayName: "North"
};

const east: OnlinePeer = {
  playerID: { rawValue: "east" },
  accountID: "dev:east",
  provider: "dev",
  displayName: "East"
};

const south: OnlinePeer = {
  playerID: { rawValue: "south" },
  accountID: "dev:south",
  provider: "dev",
  displayName: "South"
};

// Seats the host reserves for friends who haven't joined yet.
const openEast: OnlinePeer = {
  playerID: { rawValue: "east" },
  accountID: "pending:east",
  provider: "dev",
  displayName: "East"
};

const openSouth: OnlinePeer = {
  playerID: { rawValue: "south" },
  accountID: "pending:south",
  provider: "dev",
  displayName: "South"
};

test("creates a room with Swift-compatible player IDs", () => {
  const room = createInitialRoom({
    roomCode: "ab-12",
    localPeer: north,
    seats: [north, east, south],
    now: "2026-05-04T00:00:00.000Z"
  });

  assert.equal(room.roomCode, "AB12");
  assert.equal(room.hostPlayerID, "north");
  assert.deepEqual(publicRoom(room).hostPlayerID, { rawValue: "north" });
  assert.deepEqual(publicRoom(room).peers.map((peer: OnlinePeer) => peer.playerID), [
    { rawValue: "north" },
    { rawValue: "east" },
    { rawValue: "south" }
  ]);
});

test("join updates an existing peer instead of duplicating a seat", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const updated = joinRoom(room, {
    ...east,
    displayName: "East Reconnected"
  });

  assert.equal(updated.peers.length, 3);
  assert.equal(updated.peers[1].displayName, "East Reconnected");
});

test("joiners with the same declared seat land on distinct open seats", () => {
  // Two fresh installs both default to the host's own seat name ("north").
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });

  const afterAnn = joinRoom(room, {
    playerID: { rawValue: "north" },
    accountID: "anonymous:north:aaa",
    provider: "dev",
    displayName: "Ann"
  });
  const afterBob = joinRoom(afterAnn, {
    playerID: { rawValue: "north" },
    accountID: "anonymous:north:bbb",
    provider: "dev",
    displayName: "Bob"
  });

  const seatFor = (accountID: string) =>
    afterBob.peers.find((peer: OnlinePeer) => peer.accountID === accountID)?.playerID.rawValue;

  // The host keeps its seat — nobody overwrote it.
  assert.equal(seatFor(north.accountID), "north");
  // The two joiners took the two reserved seats: different seats, no collision.
  assert.deepEqual([seatFor("anonymous:north:aaa"), seatFor("anonymous:north:bbb")].sort(), ["east", "south"]);
  assert.equal(afterBob.peers.length, 3);
});

test("a joiner is placed in the open seat it asks for when that seat is free", () => {
  // The invite-flow verifier relies on this: each simulator asks for its own
  // seat and must land there, not on whichever open seat happens to be first.
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const joined = joinRoom(room, {
    playerID: { rawValue: "south" },   // asks for south — the second open seat, not the first (east)
    accountID: "apple:zoe",
    provider: "apple",
    displayName: "Zoe"
  });

  assert.equal(joined.peers.find((peer: OnlinePeer) => peer.accountID === "apple:zoe")?.playerID.rawValue, "south");
  // East stays open for the next joiner.
  assert.equal(joined.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "east")?.accountID, "pending:east");
});

test("rejoining with the same account reclaims the same seat", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const joined = joinRoom(room, {
    playerID: { rawValue: "whatever" },
    accountID: "apple:abc",
    provider: "apple",
    displayName: "Amy"
  });
  const seatFor = (state: typeof joined) =>
    state.peers.find((peer: OnlinePeer) => peer.accountID === "apple:abc")?.playerID.rawValue;

  const rejoined = joinRoom(joined, {
    playerID: { rawValue: "different" },
    accountID: "apple:abc",
    provider: "apple",
    displayName: "Amy on a new phone"
  });

  assert.equal(seatFor(rejoined), seatFor(joined));   // same seat reclaimed on reconnect
  assert.equal(rejoined.peers.length, 3);             // no fresh slot consumed
  assert.equal(
    rejoined.peers.find((peer: OnlinePeer) => peer.accountID === "apple:abc")?.displayName,
    "Amy on a new phone"
  );
});

test("a join is rejected once every reserved seat is taken", () => {
  let room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth], maxPlayers: 3 });
  room = joinRoom(room, { playerID: { rawValue: "p" }, accountID: "apple:one", provider: "apple", displayName: "One" });
  room = joinRoom(room, { playerID: { rawValue: "q" }, accountID: "apple:two", provider: "apple", displayName: "Two" });

  assert.throws(
    () => joinRoom(room, { playerID: { rawValue: "r" }, accountID: "apple:three", provider: "apple", displayName: "Three" }),
    /Room is full/
  );
});

test("a bot seat is not claimable — a joiner is routed to an open seat instead", () => {
  // A host fills `south` with a server-side bot and leaves `east` open.
  const botSouth: OnlinePeer = {
    playerID: { rawValue: "south" },
    accountID: "bot:south",
    provider: "dev",
    displayName: "Bot 3"
  };
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, botSouth], maxPlayers: 3 });

  // Even when the joiner declares the bot's seat, the bot seat is occupied, so
  // they land on the only open (`pending:`) seat — east.
  const joined = joinRoom(room, { playerID: { rawValue: "south" }, accountID: "apple:guest", provider: "apple", displayName: "Guest" });
  assert.equal(joined.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "south")?.accountID, "bot:south");
  assert.equal(joined.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "east")?.accountID, "apple:guest");

  // With east now taken and south held by the bot, the next joiner is rejected.
  assert.throws(
    () => joinRoom(joined, { playerID: { rawValue: "south" }, accountID: "apple:second", provider: "apple", displayName: "Second" }),
    /Room is full/
  );
});

test("recipient routing excludes the sender and unknown seats", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });

  assert.deepEqual(routeRecipients(room, "north", undefined), ["east", "south"]);
  assert.deepEqual(routeRecipients(room, "north", [{ rawValue: "south" }, { rawValue: "ghost" }]), ["south"]);
});

test("relay records are sequenced and capped", () => {
  let room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  for (let index = 0; index < 205; index += 1) {
    const result = recordRelay(room, {
      senderPlayerID: "north",
      recipientPlayerIDs: ["east"],
      message: { ping: { tableID: null, sentAt: "2026-05-04T00:00:00.000Z" } }
    });
    room = result.room;
  }

  assert.equal(room.relaySequence, 205);
  assert.equal(room.recentMessages.length, 200);
  assert.equal(room.recentMessages[0].serverSequence, 6);
});

test("mints a host secret that publicRoom never exposes", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });

  assert.ok(typeof room.hostSecret === "string" && room.hostSecret.length >= 16);
  // The secret authenticates host-only mutations, so it must never leak to the
  // payload guests receive over summary/join/presence.
  assert.ok(!("hostSecret" in publicRoom(room)));
});

test("fill-bots converts every open seat to a bot and leaves the rest", () => {
  // North (host) + a claimed east + a still-open south.
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, openSouth] });
  const filled = fillOpenSeatsWithBots(room, "2026-05-04T00:00:01.000Z");

  const southPeer = filled.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "south");
  assert.equal(southPeer?.accountID, "bot:south");
  assert.equal(southPeer?.displayName, "Bot 3");
  // The host and the already-claimed seat are untouched.
  assert.equal(filled.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "north")?.accountID, north.accountID);
  assert.equal(filled.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === "east")?.accountID, east.accountID);
  assert.equal(filled.updatedAt, "2026-05-04T00:00:01.000Z");
});

test("fill-bots is a no-op when no seat is open", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  // Same reference back signals the caller to skip the storage write + broadcast.
  assert.equal(fillOpenSeatsWithBots(room), room);
});

test("a seat converted to a bot can no longer be claimed by a late joiner", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, openSouth], maxPlayers: 3 });
  const filled = fillOpenSeatsWithBots(room);

  // South is now a bot; east is the only human seat and it is already claimed,
  // so a late human has nowhere to sit.
  assert.throws(
    () => joinRoom(filled, { playerID: { rawValue: "south" }, accountID: "apple:late", provider: "apple", displayName: "Late" }),
    /Room is full/
  );
});

test("accepts raw string player IDs for HTTP query parameters", () => {
  assert.equal(playerIDValue("north"), "north");
});

test("a fresh room starts in the lobby and exposes status, never the snapshot", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  assert.equal(room.status, "lobby");

  const projected = publicRoom(room);
  assert.equal(projected.status, "lobby");
  // The opaque resume blob and host secret stay server-side only.
  assert.ok(!("latestSnapshot" in projected));
  assert.ok(!("hostSecret" in projected));
});

test("a state report records status, summary, and the resume snapshot", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const { room: updated, changed } = applyStateReport(
    room,
    {
      status: "playing",
      summary: { variant: "odesa", lastSequence: 4, phase: "bidding", dealNumber: 1 },
      snapshot: { opaque: "deal-1-state" },
      snapshotSequence: 4
    },
    "2026-05-04T00:00:05.000Z"
  );

  assert.equal(changed, true);                 // lobby → playing is material: fan out
  assert.equal(updated.status, "playing");
  assert.equal(updated.summary?.phase, "bidding");
  assert.equal(updated.summary?.dealNumber, 1);
  assert.deepEqual(updated.latestSnapshot, { opaque: "deal-1-state" });
  assert.equal(updated.lastSnapshotSequence, 4);
  assert.equal(updated.updatedAt, "2026-05-04T00:00:05.000Z");
});

test("a stale (out-of-order) snapshot never clobbers a newer one", () => {
  const base = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const { room: ahead } = applyStateReport(base, {
    status: "playing",
    summary: { lastSequence: 10, phase: "playing", dealNumber: 2 },
    snapshot: { seq: 10 },
    snapshotSequence: 10
  });

  const { room: afterStale } = applyStateReport(ahead, {
    status: "playing",
    summary: { lastSequence: 7, phase: "playing", dealNumber: 2 },
    snapshot: { seq: 7 },
    snapshotSequence: 7
  });

  // The newer snapshot (seq 10) survives the late-arriving seq-7 report.
  assert.deepEqual(afterStale.latestSnapshot, { seq: 10 });
  assert.equal(afterStale.lastSnapshotSequence, 10);
});

test("a same-phase snapshot refresh updates the blob but is not a material change", () => {
  const base = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const { room: playing } = applyStateReport(base, {
    status: "playing",
    summary: { lastSequence: 10, phase: "playing", dealNumber: 2 },
    snapshot: { seq: 10 },
    snapshotSequence: 10
  });

  const { room: refreshed, changed } = applyStateReport(playing, {
    status: "playing",
    summary: { lastSequence: 11, phase: "playing", dealNumber: 2 },
    snapshot: { seq: 11 },
    snapshotSequence: 11
  });

  // Snapshot advances for an exact resume, but status/deal/phase are unchanged,
  // so fan-out to player libraries is skipped (bounded chatter).
  assert.deepEqual(refreshed.latestSnapshot, { seq: 11 });
  assert.equal(changed, false);
});

test("finishing a game keeps the result summary but drops the snapshot", () => {
  const base = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const { room: playing } = applyStateReport(base, {
    status: "playing",
    summary: { lastSequence: 40, phase: "playing", dealNumber: 6 },
    snapshot: { seq: 40 },
    snapshotSequence: 40
  });

  const { room: finished, changed } = applyStateReport(playing, {
    status: "finished",
    summary: {
      lastSequence: 42,
      result: { winner: { rawValue: "north" }, finalScores: { north: 6, east: 2, south: 1 } }
    }
  });

  assert.equal(changed, true);
  assert.equal(finished.status, "finished");
  assert.equal(finished.summary?.result?.winner?.rawValue, "north");
  assert.deepEqual(finished.summary?.result?.finalScores, { north: 6, east: 2, south: 1 });
  // A finished game is never resumed, so the heavy blob is released.
  assert.equal(finished.latestSnapshot, undefined);
});

test("an unknown status is rejected and isHumanAccount excludes pending/bot seats", () => {
  assert.equal(normalizeGameStatus("playing"), "playing");
  assert.equal(normalizeGameStatus("garbage"), undefined);

  assert.equal(isHumanAccount("apple:abc"), true);
  assert.equal(isHumanAccount("anonymous:north:aaa"), true);
  assert.equal(isHumanAccount("pending:east"), false);
  assert.equal(isHumanAccount("bot:south"), false);
});
