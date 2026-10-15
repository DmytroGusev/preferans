import assert from "node:assert/strict";
import test from "node:test";
import { createInitialRoom, joinRoom, publicRoom, removeAccountFromRoom, type RoomState } from "../src/room-state.ts";
import { publicConfiguration, publicTableEntry, setPlayerReady } from "../src/public-tables.ts";
import { validateStartDealAuthority } from "../src/authoritative-engine.ts";

const peer = (id: string, accountID = `guest:${id}`) => ({ playerID: { rawValue: id }, accountID, provider: "guest", displayName: id });
function room(): RoomState {
  return createInitialRoom({ roomCode: "PUBLIC", localPeer: peer("north"), maxPlayers: 3,
    seats: [peer("north"), peer("east", "pending:east"), peer("south", "pending:south")],
    visibility: "public", ...publicConfiguration("odesa", 33, 3) });
}

test("public listings expose no account, credential, projection or hidden engine state", () => {
  const state = { ...room(), authoritativeState: "PRIVATE_HANDS", authoritativeProjections: { north: "PRIVATE" } };
  const listing = publicTableEntry(state, new Set(["north"]))!;
  assert.equal(listing.openSeats, 2);
  assert.equal(listing.poolTarget, 33);
  assert.deepEqual(listing.players, [{ displayName: "north", ready: false, connected: true }]);
  const json = JSON.stringify(listing);
  for (const secret of ["accountID", "seatToken", "PRIVATE", "pending:", "guest:"]) assert.ok(!json.includes(secret));
  assert.equal(publicTableEntry({ ...state, visibility: "private" }, new Set(["north"])), undefined);
  assert.equal(publicTableEntry(state, new Set()), undefined);
  assert.equal(publicTableEntry({ ...state, status: "abandoned" }, new Set(["north"])), undefined);
  assert.equal(publicTableEntry({ ...state, status: "playing" }, new Set(["north"]))?.openSeats, 0);
});

test("a new player invalidates readiness; only ready and connected tables may start", () => {
  let state = setPlayerReady(room(), "north", true);
  state = joinRoom(state, peer("east"));
  assert.deepEqual(state.readyPlayerIDs, []);
  state = joinRoom(state, peer("south"));
  const connected = new Set(["north", "east", "south"]);
  assert.throws(() => validateStartDealAuthority(state, state.peers[0], connected), /confirm Ready/);
  for (const id of connected) state = setPlayerReady(state, id, true);
  assert.doesNotThrow(() => validateStartDealAuthority(state, state.peers[0], connected));
  assert.throws(() => validateStartDealAuthority(state, state.peers[0], new Set(["north", "east"])), /connected/);
  state = joinRoom(state, peer("east"));
  assert.ok(!state.readyPlayerIDs?.includes("east"));
  assert.throws(() => setPlayerReady({ ...state, status: "playing" }, "north", false), /waiting public/);
  assert.throws(() => joinRoom({ ...state, status: "playing" }, peer("stranger")), /full/);
});

test("public presets enforce finite truthful pool targets and immutable scoring", () => {
  assert.equal(publicConfiguration("odesa", 33, 3).match.poolClosure, "individualWithAmericanAid");
  assert.equal(publicConfiguration("wien", 33, 3).match.poolClosure, "tableTotal");
  assert.deepEqual(publicConfiguration("thessaloniki", 44, 4).match.raspasy, { progressive: { penalties: "flat", exit: "simple" } });
  for (const target of [undefined, Infinity, -1, 0, 0.5, 4000]) {
    assert.throws(() => publicConfiguration("odesa", target, 3));
  }
  assert.throws(() => publicConfiguration("odesa", 11, 3), /divide evenly/);
  assert.throws(() => publicConfiguration("unrecognized", 33, 3), /Choose Vienna/);
});

test("public rosters mask other accounts but preserve the authenticated caller and seat kinds", () => {
  const state = joinRoom(room(), peer("north", "apple:private-subject"));
  const caller = publicRoom(state, "apple:private-subject");
  const own = caller.peers.find(peer => peer.accountID === "apple:private-subject")!;
  assert.equal(own.playerID.rawValue, "east");
  assert.equal(caller.peers[0].accountID, "seat:PUBLIC:north");
  assert.equal(caller.peers[0].provider, "dev");
  assert.equal(caller.peers[2].accountID, "pending:south");
  for (const peer of caller.peers) assert.equal(peer.seatToken, undefined);
  const anonymous = publicRoom(state);
  assert.ok(!JSON.stringify(anonymous).includes("apple:private-subject"));
  assert.ok(!JSON.stringify(anonymous).includes("guest:north"));
  const rejoined = joinRoom(state, peer("south", "apple:private-subject"));
  assert.equal(publicRoom(rejoined).peers[1].accountID, anonymous.peers[1].accountID);
  assert.notEqual(publicRoom({ ...state, roomCode: "OTHER1" }).peers[1].accountID, anonymous.peers[1].accountID);
  assert.equal(publicRoom({ ...state, visibility: "private" }).peers[0].accountID, "guest:north");
  assert.equal(state.peers[1].accountID, "apple:private-subject");
});

test("claim and held-seat rejoin cancel only the joining account's pending library removal", () => {
  const guest = peer("east");
  const joined = joinRoom(room(), guest);
  const left = { ...removeAccountFromRoom(joined, guest.accountID).room,
    libraryRemovalAccountIDs: [guest.accountID, "guest:other"] };
  const reclaimed = joinRoom(left, guest);
  assert.deepEqual(reclaimed.libraryRemovalAccountIDs, ["guest:other"]);
  const held = joinRoom({ ...reclaimed, libraryRemovalAccountIDs: [guest.accountID, "guest:other"] }, guest);
  assert.deepEqual(held.libraryRemovalAccountIDs, ["guest:other"]);
  assert.deepEqual(left.libraryRemovalAccountIDs, [guest.accountID, "guest:other"]);
});
