import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { expect, test } from "vitest";
import { createInitialRoom, type RoomState } from "../src/room-state";
import { publicConfiguration } from "../src/public-tables";

const bindings = env as unknown as { ROOMS: DurableObjectNamespace; LOBBY: DurableObjectNamespace };
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
