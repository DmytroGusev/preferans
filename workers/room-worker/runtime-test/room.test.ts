import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { expect, test } from "vitest";
import { createInitialRoom, type RoomState, peerID } from "../src/room-state";
import { adoptingEngineResponse, type AuthoritativeGameResponse } from "../src/authoritative-engine";
import { commandIdentity } from "../src/command-contract";

const bindings = env as unknown as { ROOMS: DurableObjectNamespace };
const tableID = "00000000-0000-0000-0000-000000000001";
const peers = ["north", "east", "south"].map(id => ({
  playerID: { rawValue: id }, accountID: `guest:${id}`, provider: "guest" as const, displayName: id
}));
function response(sequence: number, botPending = false): AuthoritativeGameResponse {
  return { engineVersion: "preferans-1", state: `private-${sequence}`, sequence,
    botPending, status: sequence ? "playing" : "lobby", dealNumber: 1, phase: "bidding",
    projections: peers.map(peer => ({ tableID, sequence, viewer: peer.playerID, projection: { viewer: peer.playerID } })) };
}
function initial(): RoomState {
  return adoptingEngineResponse(createInitialRoom({ roomCode: "TEST1", localPeer: peers[0],
    seats: peers, maxPlayers: 3, rules: {}, match: {} }), response(0));
}
function command(nonce = crypto.randomUUID()) {
  return { schemaVersion: 3, tableID, actor: peers[0].playerID,
    action: { bid: { player: peers[0].playerID, call: { pass: {} } } },
    clientNonce: nonce, baseHostSequence: 0 };
}
const stub = () => bindings.ROOMS.get(bindings.ROOMS.newUniqueId());

// These tests run the production callbacks with real workerd storage. Only the
// stateless Swift network boundary is substituted to place failures precisely.
test("receipt and room commit together; retry does not invoke engine twice", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial();
    await state.storage.put("room", room);
    let calls = 0;
    instance.engine = () => ({ fetch: async () => { calls++; return Response.json(response(1)); } });
    const cmd = command();
    await instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } });
    const committed = await state.storage.get<RoomState>("room");
    const identity = await commandIdentity(room.peers[0].accountID, cmd);
    expect((await state.storage.get<any>(identity.key)).receipt.status).toBe("accepted");
    expect(committed?.authoritativeSequence).toBe(1);
    await instance.relayWireMessage(committed, room.peers[0], { message: { clientAction: { _0: cmd } } });
    expect(calls).toBe(1);
    expect(await state.storage.getAlarm()).not.toBeNull();
    await state.storage.deleteAlarm();
  });
});

test("engine outage leaves no acceptance; exact command can succeed on retry", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); const cmd = command();
    await state.storage.put("room", room);
    instance.engine = () => ({ fetch: async () => { throw new Error("network lost"); } });
    await expect(instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } })).rejects.toThrow();
    const id = await commandIdentity(room.peers[0].accountID, cmd);
    expect(await state.storage.get(id.key)).toBeUndefined();
    expect((await state.storage.get<RoomState>("room"))?.authoritativeSequence).toBe(0);
    instance.engine = () => ({ fetch: async () => Response.json(response(1)) });
    await instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } });
    expect((await state.storage.get<any>(id.key)).receipt.status).toBe("accepted");
    await state.storage.deleteAlarm();
  });
});

test("socket close cannot overwrite a command while its engine call is suspended", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); await state.storage.put("room", room);
    let release!: () => void;
    const engineGate = new Promise<void>(resolve => { release = resolve; });
    let started!: () => void;
    const engineStarted = new Promise<void>(resolve => { started = resolve; });
    instance.engine = () => ({ fetch: async () => { started(); await engineGate; return Response.json(response(1)); } });
    const pair = new WebSocketPair();
    state.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ playerID: "north", seatToken: room.peers[0].seatToken });
    const move = instance.webSocketMessage(pair[1], JSON.stringify({ type: "wire", message: { clientAction: { _0: command() } } }));
    await engineStarted;
    const close = instance.webSocketClose(pair[1]);
    release();
    await Promise.all([move, close]);
    expect((await state.storage.get<RoomState>("room"))?.authoritativeSequence).toBe(1);
    pair[1].close(); await state.storage.deleteAlarm();
  });
});

test("failed library delivery stays durable until a later alarm repairs it", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    await state.storage.put("room", { ...initial(), libraryDirty: true });
    instance.upsertLibraryEntry = async () => { throw new Error("account offline"); };
    await instance.alarm();
    expect((await state.storage.get<RoomState>("room"))?.libraryDirty).toBe(true);
    expect(await state.storage.getAlarm()).not.toBeNull();
    instance.upsertLibraryEntry = async () => {};
    await instance.alarm();
    expect((await state.storage.get<RoomState>("room"))?.libraryDirty).toBe(false);
    expect(await state.storage.getAlarm()).toBeNull();
  });
});

test("bot alarm commits one revision and retains continuation", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    await state.storage.put("room", adoptingEngineResponse(initial(), response(1, true)));
    instance.engine = () => ({ fetch: async () => Response.json(response(2, true)) });
    instance.upsertLibraryEntry = async () => {};
    await instance.alarm();
    expect((await state.storage.get<RoomState>("room"))?.authoritativeSequence).toBe(2);
    expect(await state.storage.getAlarm()).not.toBeNull();
    await state.storage.deleteAlarm();
  });
});

test("lost delivery after commit remains accepted when the table has finished", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); await state.storage.put("room", room);
    let calls = 0;
    instance.engine = () => ({ fetch: async () => {
      calls++; return Response.json({ ...response(1), status: "finished" });
    } });
    instance.sendReceipt = () => { throw new Error("socket lost after commit"); };
    const cmd = command();
    await expect(instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } })).rejects.toThrow();
    const terminal = await state.storage.get<RoomState>("room");
    expect(terminal?.authoritativeState).toBeUndefined();
    const receipts: any[] = [];
    instance.sendReceipt = (_room: any, _seat: any, receipt: any) => receipts.push(receipt);
    await instance.relayWireMessage(terminal, room.peers[0], { message: { clientAction: { _0: cmd } } });
    expect(receipts[0].status).toBe("accepted");
    expect(calls).toBe(1);
    await state.storage.deleteAlarm();
  });
});

test("different payload under the same ID is rejected without another transition", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); await state.storage.put("room", room);
    instance.engine = () => ({ fetch: async () => Response.json(response(1)) });
    const receipts: any[] = [];
    instance.sendReceipt = (_room: any, _seat: any, receipt: any) => receipts.push(receipt);
    const cmd = command();
    await instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } });
    const committed = await state.storage.get<RoomState>("room");
    await instance.relayWireMessage(committed, room.peers[0], { message: { clientAction: { _0: { ...cmd, baseHostSequence: 1 } } } });
    expect(receipts[1].code).toBe("command_id_conflict");
    expect((await state.storage.get<RoomState>("room"))?.authoritativeSequence).toBe(1);
    await state.storage.deleteAlarm();
  });
});

test("fresh socket resumes from storage without calling Swift", async () => {
  const roomStub = stub();
  const token = await runInDurableObject(roomStub, async (_instance: any, state) => {
    const room = adoptingEngineResponse(initial(), response(8));
    await state.storage.put("room", room);
    return room.peers[0].seatToken!;
  });
  const responseSocket = await roomStub.fetch(`https://room/socket?playerID=north&seatToken=${token}`, {
    headers: { Upgrade: "websocket" }
  });
  expect(responseSocket.status).toBe(101);
  const socket = responseSocket.webSocket!;
  const projection = new Promise<any>(resolve => {
    socket.addEventListener("message", event => {
      const frame = JSON.parse(event.data as string);
      if (frame.type === "wire") resolve(frame);
    });
  });
  socket.accept();
  const frame = await projection;
  expect(frame.message.projection._0.sequence).toBe(8);
  expect(frame.message.projection._0.viewer.rawValue).toBe("north");
  expect(JSON.stringify(frame)).not.toContain("private-8");
  socket.close();
});

test("transaction interruption cannot publish state without its receipt", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); await state.storage.put("room", room);
    instance.engine = () => ({ fetch: async () => Response.json(response(1)) });
    const transaction = state.storage.transaction.bind(state.storage);
    state.storage.transaction = (async (operation: any) => transaction(async txn => {
      await operation(txn);
      throw new Error("injected interruption before transaction commit");
    })) as typeof state.storage.transaction;
    const cmd = command();
    await expect(instance.relayWireMessage(room, room.peers[0], { message: { clientAction: { _0: cmd } } })).rejects.toThrow();
    state.storage.transaction = transaction;
    expect((await state.storage.get<RoomState>("room"))?.authoritativeSequence).toBe(0);
    const identity = await commandIdentity(room.peers[0].accountID, cmd);
    expect(await state.storage.get(identity.key)).toBeUndefined();
    await state.storage.deleteAlarm();
  });
});

test("join rotates credentials and immediately closes the previous controller", async () => {
  await runInDurableObject(stub(), async (instance: any, state) => {
    const room = initial(); await state.storage.put("room", room);
    instance.engine = () => ({ fetch: async () => Response.json(response(0)) });
    instance.upsertLibraryEntry = async () => {};
    const pair = new WebSocketPair();
    state.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ playerID: "north", seatToken: room.peers[0].seatToken });
    const joined = await instance.fetch(new Request("https://room/join", {
      method: "POST", body: JSON.stringify({ localPeer: peers[0] })
    }));
    expect(joined.status).toBe(200);
    const next = await state.storage.get<RoomState>("room");
    expect(next!.peers[0].seatToken).not.toBe(room.peers[0].seatToken);
    expect(pair[1].readyState).not.toBe(WebSocket.OPEN);
    const forbidden = await instance.fetch(new Request(`https://room/socket?playerID=north&seatToken=${room.peers[0].seatToken}`, {
      headers: { Upgrade: "websocket" }
    }));
    expect(forbidden.status).toBe(403);
    await state.storage.deleteAlarm();
  });
});
