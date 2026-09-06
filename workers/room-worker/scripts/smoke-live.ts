import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ROOM_SCHEMA_VERSION } from "../src/room-state.ts";

const baseURL = new URL(process.env.PREFERANS_ROOM_WORKER_URL ?? "http://127.0.0.1:8787");
const fixture = JSON.parse(await readFile(new URL("../fixtures/create-game.json", import.meta.url), "utf8"));
const health = await (await fetch(new URL("/health", baseURL))).json() as any;
assert.equal(health.roomSchemaVersion, ROOM_SCHEMA_VERSION);

async function post(path: string, body: unknown, token?: string): Promise<any> {
  const response = await fetch(new URL(path, baseURL), {
    method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15_000)
  });
  const data = await response.json();
  assert.ok(response.ok, `${path}: HTTP ${response.status} ${JSON.stringify(data)}`);
  return data;
}
function connection(url: string) {
  const socket = new WebSocket(url);
  const frames: any[] = [];
  const listeners = new Set<() => void>();
  socket.addEventListener("message", event => {
    frames.push(JSON.parse(String(event.data))); listeners.forEach(fn => fn());
  });
  function wait(predicate: (frame: any) => boolean): Promise<any> {
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timer); listeners.delete(check); };
      const check = () => { const value = frames.find(predicate); if (value) { finish(); resolve(value); } };
      const timer = setTimeout(() => { finish(); reject(new Error("Timed out waiting for room progress")); }, 8_000);
      listeners.add(check); check();
    });
  }
  return { socket, wait };
}

for (const count of [3, 4]) {
  const seats = ["north", "east", "south", "west"].slice(0, count).map(rawValue => ({ rawValue }));
  const accounts: any[] = [];
  const sockets: ReturnType<typeof connection>[] = [];
  let created: any;
  const started = performance.now();
  try {
    for (const seat of seats) accounts.push(await post("/v2/accounts/guest", { displayName: `Smoke ${seat.rawValue}` }));
    created = await post("/v2/rooms", {
      localPlayerID: seats[0], maxPlayers: count,
      seats: seats.map((playerID, i) => ({ playerID, kind: i ? "open" : "you" })),
      rules: fixture.rules, match: fixture.match
    }, accounts[0].sessionToken);
    const rooms = [created];
    for (let i = 1; i < count; i++) rooms.push(await post(`/v2/rooms/${created.roomCode}/join`, {
      requestedPlayerID: seats[i]
    }, accounts[i].sessionToken));
    rooms.forEach(room => sockets.push(connection(room.websocketURL)));
    await sockets[0].wait(frame => frame.connectedPlayerIDs?.length === count);
    console.log(`SMOKE seats=${count} phase=connected elapsedMs=${Math.round(performance.now() - started)}`);
    const clientNonce = crypto.randomUUID();
    const command = JSON.stringify({ type: "wire", message: { clientAction: { _0: {
      schemaVersion: ROOM_SCHEMA_VERSION, tableID: created.authoritativeTableID,
      actor: seats[0], action: { startDeal: {} }, clientNonce, baseHostSequence: 0,
      sentAt: new Date().toISOString()
    } } } });
    sockets[0].socket.send(command);
    const receipt = await sockets[0].wait(frame => frame.type === "receipt" && frame.receipt.clientNonce === clientNonce);
    assert.equal(receipt.receipt.status, "accepted");
    for (let i = 0; i < count; i++) {
      const frame = await sockets[i].wait(frame => frame.message?.projection?._0.sequence === 1);
      assert.equal(frame.authority, "server");
      assert.equal(frame.message.projection._0.viewer.rawValue, seats[i].rawValue);
      assert.equal(frame.message.projection._0.projection.phase.bidding !== undefined, true);
      assert.equal(frame.message.projection._0.state, undefined);
    }
    sockets[0].socket.send(command); // same ID must not deal twice
    sockets[1].socket.close();
    const resumed = connection(rooms[1].websocketURL); sockets.push(resumed);
    const replay = await resumed.wait(frame => frame.message?.projection?._0.sequence === 1);
    assert.equal(replay.message.projection._0.viewer.rawValue, seats[1].rawValue);
    console.log(`SMOKE seats=${count} phase=resumed revision=1 elapsedMs=${Math.round(performance.now() - started)}`);
  } finally {
    if (created) await post(`/v2/rooms/${created.roomCode}/abandon`, {
      playerID: seats[0], seatToken: created.seatToken
    }, accounts[0].sessionToken);
    sockets.forEach(({ socket }) => socket.close());
    for (const account of accounts) {
      const deleted = await fetch(new URL("/v2/account", baseURL), {
        method: "DELETE", headers: { authorization: `Bearer ${account.sessionToken}` }, signal: AbortSignal.timeout(8_000)
      });
      assert.ok(deleted.ok, "Smoke account cleanup failed");
    }
  }
}
console.log("Authoritative room smoke passed.");
