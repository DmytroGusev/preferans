import assert from "node:assert/strict";

interface WirePlayerID {
  rawValue: string;
}

interface OnlinePeer {
  playerID: WirePlayerID;
  accountID: string;
  provider: "dev" | "email";
  displayName: string;
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
  const peers = seatOrder
    .slice(0, playerCount)
    .map((seat, index) => peer(
      seat,
      titleCase(seat),
      index === 0 ? `email:${seat}@example.test` : `dev:${seat}`,
      index === 0 ? "email" : "dev"
    ));

  const created = await postJSON<RoomResponse>("/rooms", {
    localPeer: peers[0],
    seats: peers,
    maxPlayers: playerCount
  });
  assert.match(created.roomCode, /^[A-Z0-9]{4,12}$/);
  assert.equal(created.peers.length, playerCount);
  assert.match(created.websocketURL, /^wss:\/\//);

  const joinedRooms: RoomResponse[] = [];
  for (const peer of peers.slice(1)) {
    const joined = await postJSON<RoomResponse>(`/rooms/${created.roomCode}/join`, {
      localPeer: { ...peer, displayName: `${peer.displayName} Live Smoke` }
    });
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
    peers.slice(1).forEach((recipient) => {
      sockets[0].send(JSON.stringify({
        type: "wire",
        recipients: [recipient.playerID],
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
      assert.deepEqual(relayed.sender?.playerID, peers[0].playerID);
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

function peer(
  rawValue: string,
  displayName: string,
  accountID: string,
  provider: OnlinePeer["provider"]
): OnlinePeer {
  return {
    playerID: { rawValue },
    accountID,
    provider,
    displayName
  };
}

function titleCase(value: string): string {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}

async function postJSON<T>(path: string, body: unknown): Promise<T> {
  const response = await fetch(new URL(path, baseURL), {
    method: "POST",
    headers: { "content-type": "application/json" },
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
