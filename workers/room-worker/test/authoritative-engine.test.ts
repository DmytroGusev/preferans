import assert from "node:assert/strict";
import test from "node:test";
import {
  adoptingEngineResponse,
  applyAuthoritativeCommand,
  clientActionFromWireMessage,
  createAuthoritativeGame,
  isStartDealCommand,
  projectionWireMessage,
  validateStartDealAuthority,
  type AuthoritativeEngineBinding,
  type AuthoritativeGameResponse
} from "../src/authoritative-engine.ts";
import { createInitialRoom, type OnlinePeer } from "../src/room-state.ts";

const north: OnlinePeer = {
  playerID: { rawValue: "north" },
  accountID: "guest:north",
  provider: "guest",
  displayName: "North"
};
const east: OnlinePeer = {
  playerID: { rawValue: "east" },
  accountID: "guest:east",
  provider: "guest",
  displayName: "East"
};
const south: OnlinePeer = {
  playerID: { rawValue: "south" },
  accountID: "bot:south",
  provider: "dev",
  displayName: "Bot 3"
};

function room() {
  return createInitialRoom({
    roomCode: "ROOM1",
    localPeer: north,
    seats: [north, east, south],
    maxPlayers: 3,
    rules: { singleWhistScoring: "greedy" },
    match: { poolTarget: 30 },
    variant: "odesa"
  });
}

function response(sequence = 0): AuthoritativeGameResponse {
  return {
    engineVersion: "preferans-1",
    botPending: false,
    state: `opaque-${sequence}`,
    sequence,
    status: sequence === 0 ? "lobby" : "playing",
    dealNumber: 1,
    phase: sequence === 0 ? "waitingForDeal" : "bidding",
    projections: ["north", "east", "south"].map((viewer) => ({
      tableID: "00000000-0000-0000-0000-000000000001",
      sequence,
      viewer: { rawValue: viewer },
      projection: { phase: sequence === 0 ? "waitingForDeal" : "bidding", viewer }
    }))
  };
}

test("create sends identities/configuration and stores only opaque state plus redacted projections", async () => {
  let captured: unknown;
  const engine: AuthoritativeEngineBinding = {
    async fetch(path, body) {
      assert.equal(path, "/v1/games");
      captured = body;
      return Response.json(response(), { status: 200 });
    }
  };

  const created = await createAuthoritativeGame(room(), engine);
  assert.equal(created.authoritativeState, "opaque-0");
  assert.equal(created.authoritativeTableID, "00000000-0000-0000-0000-000000000001");
  assert.deepEqual(Object.keys(created.authoritativeProjections ?? {}).sort(), ["east", "north", "south"]);
  assert.equal(created.summary?.variant, "odesa");

  const request = captured as Record<string, any>;
  assert.equal(request.identities[0].gamePlayerID, "guest:north");
  assert.deepEqual(request.botProfiles, [
    { rawValue: "south" },
    { difficulty: "seasoned", temperament: "adaptive" }
  ]);
});

test("command sender is derived from the authenticated socket seat", async () => {
  const initialized = adoptingEngineResponse(room(), response());
  let captured: Record<string, any> | undefined;
  const engine: AuthoritativeEngineBinding = {
    async fetch(path, body) {
      assert.equal(path, "/v1/commands");
      captured = body as Record<string, any>;
      return Response.json(response(1), { status: 200 });
    }
  };

  await applyAuthoritativeCommand(initialized, east, {
    schemaVersion: initialized.schemaVersion,
    tableID: initialized.authoritativeTableID,
    actor: { rawValue: "east" },
    action: { bid: { _0: { player: { rawValue: "east" }, bid: "pass" } } },
    clientNonce: "00000000-0000-0000-0000-000000000002",
    baseHostSequence: 0
  }, engine);

  assert.deepEqual(captured?.sender, { rawValue: "east" });
  assert.equal(captured?.state, "opaque-0");
  assert.equal(captured?.baseSequence, 0);
});

test("wire helpers recognize commands and wrap server projections", () => {
  const envelope = { actor: { rawValue: "north" }, baseHostSequence: 4 };
  assert.deepEqual(clientActionFromWireMessage({ clientAction: { _0: envelope } }), envelope);
  assert.equal(clientActionFromWireMessage({ projection: { _0: {} } }), undefined);
  assert.equal(isStartDealCommand({ action: { startDeal: { _0: {} } } }), true);
  assert.equal(isStartDealCommand({ action: { bid: { _0: {} } } }), false);
  assert.deepEqual(projectionWireMessage({ sequence: 5 }), {
    projection: { _0: { sequence: 5 } }
  });
});

test("only the connected lobby manager can start with a complete roster", () => {
  const complete = room();
  assert.doesNotThrow(() => validateStartDealAuthority(
    complete,
    north,
    new Set(["north", "east"])
  ));
  assert.throws(() => validateStartDealAuthority(
    complete,
    east,
    new Set(["north", "east"])
  ), /lobby manager/);
  assert.throws(() => validateStartDealAuthority(
    complete,
    north,
    new Set(["north"])
  ), /human seat must be connected/);

  const pending = createInitialRoom({
    roomCode: "ROOM2",
    localPeer: north,
    seats: [north, east, { ...south, accountID: "pending:south" }],
    maxPlayers: 3,
    rules: {},
    match: {}
  });
  assert.throws(() => validateStartDealAuthority(
    pending,
    north,
    new Set(["north", "east"])
  ), /claimed or filled/);
});
