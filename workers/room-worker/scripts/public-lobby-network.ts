// Real Worker + shared Swift engine check. Uses only isolated loopback services.
import profiles from "../fixtures/public-rules.json";

const base = "http://127.0.0.1:8787";
const tokens: string[] = [];
const sockets: WebSocket[] = [];
function require(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
async function request(method: string, path: string, token?: string, body?: unknown, expected = 200): Promise<any> {
  const response = await fetch(`${base}${path}`, { method, signal: AbortSignal.timeout(3_000),
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  require(response.status === expected, `${method} ${path} expected ${expected}, received ${response.status}`);
  return response.status === 204 ? {} : response.json();
}
async function guest(name: string) {
  const registered = await request("POST", "/v2/accounts/guest", undefined, { displayName: name }, 201);
  tokens.push(registered.sessionToken);
  return registered.sessionToken as string;
}
async function connect(room: any) {
  return new Promise<WebSocket>((resolve, reject) => {
    const ws = new WebSocket(room.websocketURL);
    sockets.push(ws);
    const timeout = setTimeout(() => reject(new Error("Socket did not connect")), 3_000);
    ws.addEventListener("message", function initial(event) {
      const frame = JSON.parse(String(event.data));
      if (frame.type === "room") { clearTimeout(timeout); ws.removeEventListener("message", initial); resolve(ws); }
    });
    ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("QA socket failed")); });
  });
}
async function poll<T>(read: () => Promise<T>, accepts: (result: T) => boolean): Promise<T> {
  const deadline = Date.now() + 3_000;
  do {
    const result = await read();
    if (accepts(result)) return result;
    await new Promise(resolve => setTimeout(resolve, 50));
  } while (Date.now() < deadline);
  throw new Error("Expected public-lobby update did not arrive");
}
async function start(ws: WebSocket, room: any, actor: any, expected: string) {
  const nonce = crypto.randomUUID();
  const receipt = new Promise<any>((resolve, reject) => {
    const timeout = setTimeout(() => { ws.removeEventListener("message", receive); reject(new Error("No command receipt")); }, 3_000);
    function receive(event: MessageEvent) {
      const frame = JSON.parse(String(event.data));
      if (frame.type === "receipt" && frame.receipt.clientNonce === nonce) {
        clearTimeout(timeout); ws.removeEventListener("message", receive); resolve(frame.receipt);
      }
    }
    ws.addEventListener("message", receive);
  });
  ws.send(JSON.stringify({ type: "wire", message: { clientAction: { _0: {
    schemaVersion: 4, tableID: room.authoritativeTableID, actor, clientNonce: nonce,
    baseHostSequence: 0, action: { startDeal: {} }
  } } } }));
  const result = await receipt;
  require(result.status === expected, `Start should be ${expected}; received ${result.status}`);
  return result;
}

try {
  await request("GET", "/v2/public-tables", undefined, undefined, 401);
  for (const count of [3, 4]) {
    console.log(`[public-network] ${count} players: create, discover, join, leave, ready, deal`);
    const players = ["north", "east", "south", "west"].slice(0, count);
    const accounts = await Promise.all(players.map(id => guest(`Public QA ${count} ${id}`)));
    const created = await request("POST", "/v2/rooms", accounts[0], {
      visibility: "public", variant: count === 3 ? "odesa" : "wien", localPlayerID: { rawValue: players[0] },
      seats: players.map((id, index) => ({ playerID: { rawValue: id }, kind: index ? "open" : "you" })),
      rules: profiles.odesa, match: { poolTarget: count * 11 }
    }, 200);
    const ws = await connect(created);
    const code = created.roomCode;
    const listing = await poll(() => request("GET", "/v2/public-tables", accounts[0]),
      result => result.tables.some((table: any) => table.roomCode === code));
    const publicTable = listing.tables.find((table: any) => table.roomCode === code);
    require(publicTable.openSeats === count - 1, "Wrong initial seat count");
    require(!JSON.stringify(publicTable).includes("accountID"), "Directory leaked accounts");
    await request("POST", `/v2/rooms/${code}/seats/fill-bots`, accounts[0], {
      playerID: players[0], seatToken: created.seatToken
    }, 409);
    const joined = [created, ...await Promise.all(players.slice(1).map((id, index) =>
      request("POST", `/v2/rooms/${code}/join`, accounts[index + 1], { requestedPlayerID: { rawValue: id } })))];
    for (const room of joined.slice(1)) await connect(room);
    const lastIndex = count - 1;
    await request("POST", `/v2/rooms/${code}/leave`, accounts[lastIndex], {
      playerID: players[lastIndex], seatToken: joined[lastIndex].seatToken
    });
    await poll(() => request("GET", "/v2/my-games", accounts[lastIndex]), result => result.games.length === 0);
    joined[lastIndex] = await request("POST", `/v2/rooms/${code}/join`, accounts[lastIndex], {
      requestedPlayerID: { rawValue: players[lastIndex] }
    });
    await connect(joined[lastIndex]);
    await request("POST", `/v2/rooms/${code}/ready`, accounts[1], {
      playerID: players[0], seatToken: created.seatToken, ready: true
    }, 403);
    for (let i = 0; i < count - 1; i++) await request("POST", `/v2/rooms/${code}/ready`, accounts[i], {
      playerID: players[i], seatToken: joined[i].seatToken, ready: true
    });
    const rejected = await start(ws, created, { rawValue: players[0] }, "rejected");
    require(rejected.code === "players_not_ready", "Start did not enforce readiness");
    await request("POST", `/v2/rooms/${code}/ready`, accounts[lastIndex], {
      playerID: players[lastIndex], seatToken: joined[lastIndex].seatToken, ready: true
    });
    await start(ws, created, { rawValue: players[0] }, "accepted");
    await poll(() => request("GET", "/v2/public-tables", accounts[0]), result =>
      result.tables.some((table: any) => table.roomCode === code && table.status === "playing" && table.openSeats === 0));
    const outsider = await guest(`Public QA outsider ${count}`);
    await request("POST", `/v2/rooms/${code}/join`, outsider, { requestedPlayerID: { rawValue: "east" } }, 409);
    console.log(`[public-network] ${count} players passed`);
  }
} finally {
  sockets.forEach(ws => ws.close());
  const cleanup = await Promise.allSettled(tokens.map(token => request("DELETE", "/v2/account", token, undefined, 204)));
  require(cleanup.every(result => result.status === "fulfilled"), "Could not clean up all QA accounts");
}
