import test from "node:test";
import assert from "node:assert/strict";
import {
  createInitialRoom,
  joinRoom,
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

test("accepts raw string player IDs for HTTP query parameters", () => {
  assert.equal(playerIDValue("north"), "north");
});
