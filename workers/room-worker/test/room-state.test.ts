import test from "node:test";
import assert from "node:assert/strict";
import {
  applyStateReport,
  authorizeHostSeat,
  authorizeRelayMessage,
  authorizeSeat,
  createInitialRoom,
  fillOpenSeatsWithBots,
  electLiveHost,
  isHostAccount,
  isHumanAccount,
  joinRoom,
  normalizeGameStatus,
  type OnlinePeer,
  peerID,
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
  assert.equal(room.hostEpoch, 1);
  assert.deepEqual(publicRoom(room).hostPlayerID, { rawValue: "north" });
  assert.equal(publicRoom(room).hostEpoch, 1);
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

test("relay rejects authoritative frames from a non-host seat", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });

  assert.doesNotThrow(() => authorizeRelayMessage(room, "north", { projection: { _0: {} } }));
  assert.doesNotThrow(() => authorizeRelayMessage(room, "east", { clientAction: { _0: {} } }));
  assert.throws(
    () => authorizeRelayMessage(room, "east", { seatAssignment: { _0: {} } }),
    /Only the current host/
  );
  assert.throws(
    () => authorizeRelayMessage(room, "south", { hostError: { _0: {} } }),
    /Only the current host/
  );
});

test("relay entries are sequenced and the room stores no message history", () => {
  let room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  let lastEntry;
  for (let index = 0; index < 205; index += 1) {
    const result = recordRelay(room, {
      senderPlayerID: "north",
      recipientPlayerIDs: ["east"],
      message: { ping: { tableID: null, sentAt: "2026-05-04T00:00:00.000Z" } }
    });
    room = result.room;
    lastEntry = result.entry;
  }

  assert.equal(room.relaySequence, 205);
  assert.equal(lastEntry?.serverSequence, 205);
  // Deliberately no stored history: nothing ever read it back, and keeping
  // it meant every relayed frame rewrote a room blob holding 200 projections.
  assert.ok(!("recentMessages" in room) || (room as Record<string, unknown>).recentMessages === undefined);
});

test("seat tokens: minted for claimed human seats, never exposed publicly", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, openSouth] });

  // Claimed human seats are born with a credential; the open seat waits for
  // its claimant.
  const seat = (id: string) => room.peers.find((peer: OnlinePeer) => peer.playerID.rawValue === id);
  assert.ok((seat("north")?.seatToken?.length ?? 0) >= 16);
  assert.ok((seat("east")?.seatToken?.length ?? 0) >= 16);
  assert.equal(seat("south")?.seatToken, undefined);

  // The credential must never ride along on join/summary/presence payloads.
  for (const peer of publicRoom(room).peers) {
    assert.ok(!("seatToken" in peer), `public peer ${peer.playerID.rawValue} leaks a seatToken`);
  }
});

test("seat tokens: a fresh claim mints one and the latest rejoin rotates it", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const guest = { playerID: { rawValue: "east" }, accountID: "apple:guest", provider: "apple" as const, displayName: "Guest" };

  const joined = joinRoom(room, guest);
  const minted = joined.peers.find((peer: OnlinePeer) => peer.accountID === "apple:guest")?.seatToken;
  assert.ok((minted?.length ?? 0) >= 16);

  // Rejoining (same account, e.g. a new device) revokes the old room
  // credential so two devices cannot both control one seat.
  const rejoined = joinRoom(joined, { ...guest, displayName: "Guest again" });
  const rotated = rejoined.peers.find((peer: OnlinePeer) => peer.accountID === "apple:guest")?.seatToken;
  assert.ok(rotated);
  assert.notEqual(rotated, minted);
  assert.throws(() => authorizeSeat(rejoined, "east", minted), /does not match/);
  assert.equal(peerID(authorizeSeat(rejoined, "east", rotated)), "east");
});

test("seat authorization is strict for every v2 room", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const token = room.peers[0].seatToken;
  assert.ok(token);

  assert.equal(peerID(authorizeSeat(room, "north", token)), "north");

  // A wrong token is rejected even while enforcement is off — a caller never
  // downgrades a bad credential into legacy access.
  assert.throws(() => authorizeSeat(room, "north", "forged-token"), /does not match/);

  assert.throws(() => authorizeSeat(room, "north", undefined), /required/);

  // An unknown seat is rejected regardless.
  assert.throws(() => authorizeSeat(room, "ghost", token), /has not joined/);

  // A token-less legacy seat cannot cross the v2 boundary.
  const legacy = {
    ...room,
    peers: room.peers.map((peer: OnlinePeer) => ({ ...peer, seatToken: undefined }))
  };
  assert.throws(() => authorizeSeat(legacy, "north", undefined), /no valid v2 credential/);
});

test("converting an open seat to a bot leaves it without a credential", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const filled = fillOpenSeatsWithBots(room);
  const bot = filled.peers.find((peer: OnlinePeer) => peer.accountID === "bot:east");
  assert.ok(bot);
  assert.equal(bot?.seatToken, undefined);
});

test("a returning host account is recognized; guests and placeholder seats are not", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, openEast, openSouth] });
  const joined = joinRoom(room, {
    playerID: { rawValue: "east" },
    accountID: "apple:guest",
    provider: "apple",
    displayName: "Guest"
  });

  // The creator's account holds the host seat even after taking the seat over
  // from a new device with a newly rotated room credential.
  const rejoined = joinRoom(joined, { ...north, displayName: "North's new phone" });
  assert.equal(isHostAccount(rejoined, north.accountID), true);

  // A guest never matches the host seat, and pending/bot prefixes can never
  // impersonate one.
  assert.equal(isHostAccount(rejoined, "apple:guest"), false);
  assert.equal(isHostAccount(rejoined, "pending:north"), false);
  assert.equal(isHostAccount(rejoined, "bot:north"), false);
});

test("host-only mutations require the current host account and rotating seat credential", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const northToken = room.peers.find((peer) => peerID(peer) === "north")?.seatToken;
  const eastToken = room.peers.find((peer) => peerID(peer) === "east")?.seatToken;
  assert.ok(northToken);
  assert.ok(eastToken);

  assert.equal(peerID(authorizeHostSeat(room, north.accountID, "north", northToken)), "north");
  assert.throws(
    () => authorizeHostSeat(room, north.accountID, "north", "stale-token"),
    /does not match/
  );
  assert.throws(
    () => authorizeHostSeat(room, east.accountID, "east", eastToken),
    /Only the current host/
  );
  assert.throws(
    () => authorizeHostSeat(room, "email:impostor@example.test", "north", northToken),
    /does not own/
  );
});

test("host election is deterministic, monotonic, and limited to connected humans", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });

  // The current host remains authoritative while any of its sockets is live.
  assert.equal(electLiveHost(room, ["north", "south"]), room);

  // Once north is absent, stable seat order selects east before south.
  const eastHost = electLiveHost(room, ["east", "south"], "2026-05-04T00:00:10.000Z");
  assert.equal(eastHost.hostPlayerID, "east");
  assert.equal(eastHost.hostEpoch, 2);
  assert.equal(eastHost.updatedAt, "2026-05-04T00:00:10.000Z");

  const southHost = electLiveHost(eastHost, ["south"], "2026-05-04T00:00:11.000Z");
  assert.equal(southHost.hostPlayerID, "south");
  assert.equal(southHost.hostEpoch, 3);

  // No socket and non-human-only sockets cannot fabricate an authority.
  assert.equal(electLiveHost(southHost, []), southHost);
  const withBot = fillOpenSeatsWithBots(createInitialRoom({
    roomCode: "ROOM2",
    localPeer: north,
    seats: [north, openEast, openSouth]
  }));
  assert.equal(electLiveHost(withBot, ["east", "south"]), withBot);

  // Terminal history is immutable and never elects a fresh runtime host.
  const finished = applyStateReport(southHost, { status: "finished" }).room;
  assert.equal(electLiveHost(finished, ["north"]), finished);
});

test("the authenticated local peer is host even when not first in seat order", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: east, seats: [north, east, south] });
  assert.equal(room.hostPlayerID, "east");
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

test("an oversized display name is truncated on the way in", () => {
  const room = createInitialRoom({
    roomCode: "ROOM1",
    localPeer: { ...north, displayName: "N".repeat(500) }
  });
  assert.equal(room.peers[0].displayName.length, 60);
});

test("a fresh room starts in the lobby and exposes status, never the snapshot", () => {
  const room = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  assert.equal(room.status, "lobby");

  const projected = publicRoom(room);
  assert.equal(projected.status, "lobby");
  // The opaque resume blob stays server-side only.
  assert.ok(!("latestSnapshot" in projected));
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
  assert.equal(afterStale.summary?.lastSequence, 10);
  assert.equal(afterStale.summary?.dealNumber, 2);
});

test("terminal lifecycle cannot be resurrected by a delayed host report", () => {
  const base = createInitialRoom({ roomCode: "ROOM1", localPeer: north, seats: [north, east, south] });
  const { room: playing } = applyStateReport(base, {
    status: "playing",
    summary: { lastSequence: 10, phase: "playing", dealNumber: 2 },
    snapshot: { seq: 10 },
    snapshotSequence: 10
  });
  const { room: finished } = applyStateReport(playing, {
    status: "finished",
    summary: { lastSequence: 11, phase: "finished", dealNumber: 2 }
  });
  const result = applyStateReport(finished, {
    status: "playing",
    summary: { lastSequence: 12, phase: "playing", dealNumber: 3 },
    snapshot: { seq: 12 },
    snapshotSequence: 12
  });

  assert.equal(result.room, finished);
  assert.equal(result.changed, false);
  assert.equal(result.room.status, "finished");
  assert.equal(result.room.latestSnapshot, undefined);
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
