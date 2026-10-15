import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { expect, test } from "vitest";
import { createInitialRoom, removeAccountFromRoom, type RoomState } from "../src/room-state";
import { publicConfiguration } from "../src/public-tables";
import { adoptingEngineResponse } from "../src/authoritative-engine";

const bindings = env as unknown as {
  ROOMS: DurableObjectNamespace; LOBBY: DurableObjectNamespace; ACCOUNTS: DurableObjectNamespace
};
const listing = { roomCode: "PUBLIC", variant: "odesa", poolTarget: 33, poolClosure: "individualWithAmericanAid",
  maxPlayers: 3, players: [{ displayName: "Host", ready: false, connected: true }], openSeats: 2,
  status: "lobby", createdAt: new Date().toISOString() };

test("directory persists listings, ignores older publication, filters and expires leases", async () => {
  const stub = bindings.LOBBY.get(bindings.LOBBY.newUniqueId());
  const publish = (revision: number, table?: unknown) => stub.fetch("https://lobby/publish", {
    method: "POST", body: JSON.stringify({ roomCode: "PUBLIC", revision, table })
  });
  await publish(2, listing);
  expect((await (await stub.fetch("https://lobby/list?players=3")).json() as any).tables).toHaveLength(1);
  expect((await (await stub.fetch("https://lobby/list?variant=wien")).json() as any).tables).toHaveLength(0);
  await publish(3);
  await publish(2, listing);
  expect((await (await stub.fetch("https://lobby/list")).json() as any).tables).toHaveLength(0);
  await publish(4, listing);
  await runInDurableObject(stub, async (instance: any, state) => {
    const saved = await state.storage.get<any>("table:PUBLIC");
    await state.storage.put("table:PUBLIC", { ...saved, expiresAt: 0 });
    await instance.alarm();
    expect(await state.storage.get("table:PUBLIC")).toBeUndefined();
    await state.storage.deleteAlarm();
  });
});

test("readiness is authenticated by account and seat token, persisted and cleared on disconnect", async () => {
  const stub = bindings.ROOMS.get(bindings.ROOMS.newUniqueId());
  await runInDurableObject(stub, async (instance: any, state) => {
    const host = { playerID: { rawValue: "north" }, accountID: "guest:host", provider: "guest", displayName: "Host" };
    const room = createInitialRoom({ roomCode: "READY1", localPeer: host, maxPlayers: 3, seats: [host],
      visibility: "public", ...publicConfiguration("odesa", 33, 3) });
    await state.storage.put("room", room);
    const pair = new WebSocketPair();
    state.acceptWebSocket(pair[1]);
    pair[1].serializeAttachment({ playerID: "north", seatToken: room.peers[0].seatToken });
    const change = (accountID: string, seatToken = room.peers[0].seatToken) => instance.fetch(new Request("https://room/ready", {
      method: "POST", body: JSON.stringify({ playerID: host.playerID, seatToken, accountID, ready: true })
    }));
    expect((await change("guest:other")).status).toBe(403);
    expect((await change("guest:host", "wrong")).status).toBe(403);
    expect((await change("guest:host")).status).toBe(200);
    expect((await state.storage.get<RoomState>("room"))?.readyPlayerIDs).toEqual(["north"]);
    await instance.webSocketClose(pair[1]);
    expect((await state.storage.get<RoomState>("room"))?.readyPlayerIDs).toEqual([]);
    pair[1].close();
    await state.storage.deleteAlarm();
  });
});

function engineResponse(identities: any[], tableID = "00000000-0000-0000-0000-000000000123") {
  return { engineVersion: "preferans-1", state: "private-engine-state", sequence: 0,
    botPending: false, status: "lobby" as const, dealNumber: 0, phase: "waitingForDeal",
    projections: identities.map(identity => ({ tableID, sequence: 0, viewer: identity.playerID,
      projection: { viewer: identity.playerID, identities }
    })) };
}

test("public create/join and socket frames expose only the caller's global identity, including legacy projections", async () => {
  const stub = bindings.ROOMS.get(bindings.ROOMS.newUniqueId());
  const joined = await runInDurableObject(stub, async (instance: any, state) => {
    const host = { playerID: { rawValue: "north" }, accountID: "apple:private-host", provider: "apple", displayName: "Host" };
    const guest = { playerID: { rawValue: "north" }, accountID: "guest:private-joiner", provider: "guest", displayName: "Guest" };
    instance.engine = () => ({ fetch: async (_path: string, body: any) => Response.json(engineResponse(body.identities)) });
    instance.upsertLibraryEntry = async () => {};
    const created = await instance.fetch(new Request("https://room/create", { method: "POST",
      body: JSON.stringify({ roomCode: "MASKED", localPeer: host, maxPlayers: 3, visibility: "public",
        seats: [host, { ...guest, playerID: { rawValue: "east" }, accountID: "pending:east" },
          { ...guest, playerID: { rawValue: "south" }, accountID: "pending:south" }],
        ...publicConfiguration("odesa", 33, 3) })
    }));
    expect(created.status).toBe(201);
    const creator = await created.json() as any;
    expect(creator.peers.find((peer: any) => peer.accountID === host.accountID).playerID.rawValue).toBe("north");
    expect(creator.seatToken).toBeTruthy();
    expect(creator.peers.every((peer: any) => peer.seatToken === undefined)).toBe(true);
    const result = await instance.fetch(new Request("https://room/join", {
      method: "POST", body: JSON.stringify({ localPeer: guest })
    }));
    expect(result.status).toBe(200);
    const body = await result.json() as any;
    expect(body.peers.find((peer: any) => peer.accountID === guest.accountID).playerID.rawValue).toBe("east");
    expect(body.peers[0].accountID).toBe("seat:MASKED:north");
    expect(body.peers[0].provider).toBe("dev");
    expect(JSON.stringify(body)).not.toContain(host.accountID);
    const summary = await instance.fetch(new Request("https://room/summary"));
    const summaryText = await summary.text();
    expect(summaryText).not.toContain(host.accountID);
    expect(summaryText).not.toContain(guest.accountID);
    const room = (await state.storage.get<RoomState>("room"))!;
    // Simulate a room persisted before the privacy fix; reconnect must not leak it.
    const legacy = engineResponse(room.peers.map(peer => ({ playerID: peer.playerID,
      gamePlayerID: peer.accountID, displayName: peer.displayName })));
    await state.storage.put("room", { ...room,
      authoritativeProjections: Object.fromEntries(legacy.projections.map(envelope => [envelope.viewer.rawValue, envelope])) });
    await state.storage.deleteAlarm();
    return { token: body.seatToken, hostToken: creator.seatToken };
  });
  const response = await stub.fetch(`https://room/socket?playerID=east&seatToken=${joined.token}`, {
    headers: { Upgrade: "websocket" }
  });
  expect(response.status).toBe(101);
  const socket = response.webSocket!;
  const frames = new Promise<any[]>(resolve => {
    const received: any[] = [];
    socket.addEventListener("message", event => {
      received.push(JSON.parse(event.data as string));
      if (received.length === 3) resolve(received);
    });
  });
  socket.accept();
  const received = await frames;
  expect(received.map(frame => frame.type).sort()).toEqual(["presence", "room", "wire"]);
  for (const frame of received) {
    expect(JSON.stringify(frame)).not.toContain("apple:private-host");
    expect(JSON.stringify(frame)).not.toContain(joined.hostToken);
    expect(JSON.stringify(frame)).not.toContain("private-engine-state");
    if (frame.room) {
      expect(frame.room.peers[1].accountID).toBe("guest:private-joiner");
      expect(frame.room.peers[0].accountID).toBe("seat:MASKED:north");
    } else {
      expect(frame.sender.accountID).toBe("seat:MASKED:north");
      expect(frame.message.projection._0.projection.identities[1].gamePlayerID).toBe("seat:MASKED:east");
      expect(JSON.stringify(frame)).not.toContain("guest:private-joiner");
    }
  }
  // Exercise the broadcast/resync projection path as well as initial socket delivery.
  const broadcast = new Promise<any>(resolve => {
    socket.addEventListener("message", event => {
      const frame = JSON.parse(event.data as string);
      if (frame.type === "wire") resolve(frame);
    });
  });
  await runInDurableObject(stub, async (instance: any, state) => {
    const room = (await state.storage.get<RoomState>("room"))!;
    instance.broadcastAuthoritativeProjections(room, room.relaySequence, new Date().toISOString());
    await state.storage.deleteAlarm();
  });
  const frame = await broadcast;
  expect(JSON.stringify(frame)).not.toContain("apple:private-host");
  expect(JSON.stringify(frame)).not.toContain("guest:private-joiner");
  const hostResponse = await stub.fetch(`https://room/socket?playerID=north&seatToken=${joined.hostToken}`, {
    headers: { Upgrade: "websocket" }
  });
  expect(hostResponse.status).toBe(101);
  const hostSocket = hostResponse.webSocket!;
  const hostFrames = new Promise<any[]>(resolve => {
    const received: any[] = [];
    hostSocket.addEventListener("message", event => {
      received.push(JSON.parse(event.data as string));
      if (received.length === 3) resolve(received);
    });
  });
  hostSocket.accept();
  for (const frame of await hostFrames) {
    expect(JSON.stringify(frame)).not.toContain("guest:private-joiner");
    expect(JSON.stringify(frame)).not.toContain(joined.token);
    if (frame.room) {
      expect(frame.room.peers[0].accountID).toBe("apple:private-host");
      expect(frame.room.peers[1].accountID).toBe("seat:MASKED:east");
    } else {
      expect(JSON.stringify(frame)).not.toContain("apple:private-host");
    }
  }
  hostSocket.close();
  socket.close();
});

test("leave/rejoin retains the library entry and alarms discard stale removals for current seats", async () => {
  const stub = bindings.ROOMS.get(bindings.ROOMS.newUniqueId());
  await runInDurableObject(stub, async (instance: any, state) => {
    const peers = ["north", "east", "south"].map(id => ({ playerID: { rawValue: id },
      accountID: `guest:leave-rejoin-${id}`, provider: "guest" as const, displayName: id }));
    const account = (accountID: string) => bindings.ACCOUNTS.get(bindings.ACCOUNTS.idFromName(accountID));
    const games = async (accountID: string) => (await (await account(accountID).fetch("https://account/list")).json() as any).games;
    for (const peer of peers) {
      const registered = await account(peer.accountID).fetch("https://account/register", {
        method: "POST", body: JSON.stringify(peer)
      });
      expect(registered.status).toBe(201);
    }
    instance.engine = () => ({ fetch: async (_path: string, body: any) => Response.json(engineResponse(body.identities)) });
    const room = adoptingEngineResponse(createInitialRoom({ roomCode: "REJOIN", localPeer: peers[0],
      seats: peers, maxPlayers: 3, visibility: "public", ...publicConfiguration("odesa", 33, 3) }),
      engineResponse(peers.map(peer => ({ ...peer, gamePlayerID: peer.accountID }))));
    await state.storage.put("room", room);
    for (const peer of room.peers) await instance.upsertLibraryEntry(room, peer);
    const left = await instance.fetch(new Request("https://room/leave", { method: "POST",
      body: JSON.stringify({ accountID: peers[1].accountID, playerID: peers[1].playerID, seatToken: room.peers[1].seatToken })
    }));
    expect(left.status).toBe(200);
    expect((await state.storage.get<RoomState>("room"))?.libraryRemovalAccountIDs).toEqual([peers[1].accountID]);
    const rejoined = await instance.fetch(new Request("https://room/join", {
      method: "POST", body: JSON.stringify({ localPeer: peers[1] })
    }));
    expect(rejoined.status).toBe(200);
    expect((await state.storage.get<RoomState>("room"))?.libraryRemovalAccountIDs).toEqual([]);
    await instance.alarm();
    const rejoinedGames = await games(peers[1].accountID);
    expect(rejoinedGames.map((game: any) => game.roomCode)).toContain("REJOIN");
    expect(JSON.stringify(rejoinedGames)).not.toContain(peers[0].accountID);
    expect(JSON.stringify(rejoinedGames)).not.toContain(peers[2].accountID);
    const current = (await state.storage.get<RoomState>("room"))!;
    // Defensive guard covers stale queues already persisted by older Worker versions.
    await state.storage.put("room", { ...removeAccountFromRoom(current, peers[2].accountID).room,
      libraryDirty: true, libraryRemovalAccountIDs: [peers[1].accountID, peers[2].accountID] });
    await instance.alarm();
    expect((await games(peers[1].accountID)).map((game: any) => game.roomCode)).toContain("REJOIN");
    expect(await games(peers[2].accountID)).toEqual([]);
    expect((await state.storage.get<RoomState>("room"))?.libraryRemovalAccountIDs).toEqual([]);
    await state.storage.deleteAlarm();
  });
});
