import assert from "node:assert/strict";

interface WirePlayerID {
  rawValue: string;
}

interface OnlinePeer {
  playerID: WirePlayerID;
  accountID: string;
  provider: "dev" | "apple" | "guest";
  displayName: string;
}

interface Registration {
  account: Omit<OnlinePeer, "playerID"> & { schemaVersion: number };
  sessionToken: string;
}

interface RoomResponse {
  roomCode: string;
  peers: OnlinePeer[];
  websocketURL: string;
}

const baseURL = new URL(process.env.PREFERANS_ROOM_WORKER_URL ?? "https://preferans-room-worker.ontofractal.workers.dev");
const seatOrder = ["north", "east", "south", "west"] as const;

const results = [];
for (const playerCount of [3, 4] as const) {
  results.push(await smokeRoom(playerCount));
}

console.log(JSON.stringify({
  ok: true,
  rooms: results
}, null, 2));

async function smokeRoom(playerCount: 3 | 4) {
  const seats = seatOrder
    .slice(0, playerCount)
    .map((seat) => ({ rawValue: seat }));
  const registrations = await Promise.all(seats.map((seat) =>
    postJSON<Registration>("/v2/accounts/guest", { displayName: `${titleCase(seat.rawValue)} Live Smoke` })
  ));

  const created = await postJSON<RoomResponse>("/v2/rooms", {
    localPlayerID: seats[0],
    seats: seats.map((playerID, index) => ({ playerID, kind: index === 0 ? "you" : "open" })),
    maxPlayers: playerCount
  }, registrations[0].sessionToken);
  assert.match(created.roomCode, /^[A-Z0-9]{4,12}$/);
  assert.equal(created.peers.length, playerCount);
  assert.match(created.websocketURL, /^wss:\/\//);

  const joinedRooms: RoomResponse[] = [];
  for (let index = 1; index < seats.length; index += 1) {
    const joined = await postJSON<RoomResponse>(`/v2/rooms/${created.roomCode}/join`, {
      requestedPlayerID: seats[index]
    }, registrations[index].sessionToken);
    assert.equal(joined.roomCode, created.roomCode);
    assert.equal(joined.peers.length, playerCount);
    joinedRooms.push(joined);
  }

  const sockets = [
    await openSocket(created.websocketURL),
    ...await Promise.all(joinedRooms.map((room) => openSocket(room.websocketURL)))
  ];

  try {
    const relays = sockets.slice(1).map((socket) => waitForMessage(socket, (message) => message.type === "wire"));
    seats.slice(1).forEach((recipient) => {
      sockets[0].send(JSON.stringify({
        type: "wire",
        recipients: [recipient],
        reliable: true,
        message: {
          ping: {
            tableID: null,
            sentAt: new Date().toISOString()
          }
        }
      }));
    });

    const relayedMessages = await Promise.all(relays);
    for (const relayed of relayedMessages) {
      assert.deepEqual(relayed.sender?.playerID, seats[0]);
      assert.equal(relayed.message?.ping?.tableID, null);
    }

    return {
      playerCount,
      roomCode: created.roomCode,
      relayType: relayedMessages[0]?.type,
      relayedMessages: relayedMessages.length,
      lastServerSequence: relayedMessages.at(-1)?.serverSequence
    };
  } finally {
    for (const socket of sockets) {
      socket.close();
    }
  }
}

function titleCase(value: string): string {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}

async function postJSON<T>(path: string, body: unknown, sessionToken?: string): Promise<T> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (sessionToken) headers.authorization = `Bearer ${sessionToken}`;
  const response = await fetch(new URL(path, baseURL), {
    method: "POST",
    headers,
    body: JSON.stringify(body)
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${JSON.stringify(data)}`);
  }
  return data as T;
}

function openSocket(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error(`Timed out opening ${url}`));
    }, 5_000);
    socket.addEventListener("open", () => {
      clearTimeout(timeout);
      resolve(socket);
    }, { once: true });
    socket.addEventListener("error", () => {
      clearTimeout(timeout);
      reject(new Error(`Failed opening ${url}`));
    }, { once: true });
  });
}

function waitForMessage(
  socket: WebSocket,
  predicate: (message: Record<string, any>) => boolean
): Promise<Record<string, any>> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Timed out waiting for WebSocket message."));
    }, 5_000);
    const onMessage = (event: MessageEvent) => {
      const text = typeof event.data === "string"
        ? event.data
        : new TextDecoder().decode(event.data as ArrayBuffer);
      const message = JSON.parse(text) as Record<string, any>;
      if (predicate(message)) {
        cleanup();
        resolve(message);
      }
    };
    const onError = () => {
      cleanup();
      reject(new Error("WebSocket emitted an error while waiting for a message."));
    };
    const cleanup = () => {
      clearTimeout(timeout);
      socket.removeEventListener("message", onMessage);
      socket.removeEventListener("error", onError);
    };
    socket.addEventListener("message", onMessage);
    socket.addEventListener("error", onError);
  });
}
