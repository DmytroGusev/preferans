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
const peers: OnlinePeer[] = [
  peer("north", "North", "email:north@example.test", "email"),
  peer("east", "East", "dev:east", "dev"),
  peer("south", "South", "dev:south", "dev")
];

const created = await postJSON<RoomResponse>("/rooms", {
  localPeer: peers[0],
  seats: peers,
  maxPlayers: 3
});
assert.match(created.roomCode, /^[A-Z0-9]{4,12}$/);
assert.equal(created.peers.length, 3);
assert.match(created.websocketURL, /^wss:\/\//);

const joined = await postJSON<RoomResponse>(`/rooms/${created.roomCode}/join`, {
  localPeer: { ...peers[1], displayName: "East Live Smoke" }
});
assert.equal(joined.roomCode, created.roomCode);
assert.equal(joined.peers.length, 3);

const northSocket = await openSocket(created.websocketURL);
const eastSocket = await openSocket(joined.websocketURL);

try {
  const relayedMessage = waitForMessage(eastSocket, (message) => message.type === "wire");
  northSocket.send(JSON.stringify({
    type: "wire",
    recipients: [peers[1].playerID],
    reliable: true,
    message: {
      ping: {
        tableID: null,
        sentAt: new Date().toISOString()
      }
    }
  }));

  const relayed = await relayedMessage;
  assert.deepEqual(relayed.sender?.playerID, peers[0].playerID);
  assert.equal(relayed.message?.ping?.tableID, null);

  console.log(JSON.stringify({
    ok: true,
    roomCode: created.roomCode,
    relayType: relayed.type,
    serverSequence: relayed.serverSequence
  }, null, 2));
} finally {
  northSocket.close();
  eastSocket.close();
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
