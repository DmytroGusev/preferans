import {
  type CreateRoomInput,
  type OnlinePeer,
  type PublicRoom,
  type RoomState,
  type WirePlayerID,
  RoomStateError,
  createInitialRoom,
  generateRoomCode,
  joinRoom,
  normalizePeer,
  normalizeRoomCode,
  peerID,
  playerIDValue,
  publicRoom,
  recordRelay,
  routeRecipients
} from "./room-state";

const ROOM_STORAGE_KEY = "room";
const APP_ID = "3WSQ6X9CDT.com.mixandmatch.preferans";

const appleAppSiteAssociation = {
  applinks: {
    details: [
      {
        appIDs: [APP_ID],
        components: [
          {
            "/": "/join/*",
            comment: "Preferans room invite links"
          }
        ]
      }
    ]
  }
};

export interface Env {
  ROOMS: DurableObjectNamespace;
}

interface CreateRoomBody {
  localPeer?: unknown;
}

interface JoinRoomBody {
  localPeer?: unknown;
}

interface RoomWithSocketURL extends PublicRoom {
  websocketURL: string;
}

interface ClientSocketEnvelope {
  type?: "wire" | "ping";
  recipients?: WirePlayerID[];
  reliable?: boolean;
  message?: unknown;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders() });
      }

      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, service: "preferans-room-worker" });
      }

      if (
        request.method === "GET" &&
        (url.pathname === "/.well-known/apple-app-site-association" || url.pathname === "/apple-app-site-association")
      ) {
        return json(appleAppSiteAssociation);
      }

      const inviteMatch = url.pathname.match(/^\/join\/([A-Za-z0-9-]+)$/);
      if (request.method === "GET" && inviteMatch) {
        const roomCode = normalizeRoomCode(inviteMatch[1]);
        return html(invitePage(roomCode));
      }

      if (request.method === "POST" && url.pathname === "/rooms") {
        const body = await readJSON<CreateRoomBody>(request);
        const roomCode = generateRoomCode();
        const room = await roomFetch(env, roomCode, "/create", {
          ...body,
          roomCode
        });
        return json(withSocketURL(request, room, body.localPeer));
      }

      const match = url.pathname.match(/^\/rooms\/([A-Za-z0-9-]+)(?:\/(join|socket))?$/);
      if (!match) {
        return json({ error: "Not found." }, 404);
      }

      const roomCode = normalizeRoomCode(match[1]);
      const action = match[2];

      if (!action && request.method === "GET") {
        const room = await roomFetch(env, roomCode, "/summary");
        return json(room);
      }

      if (action === "join" && request.method === "POST") {
        const body = await readJSON<JoinRoomBody>(request);
        const room = await roomFetch(env, roomCode, "/join", body);
        return json(withSocketURL(request, room, body.localPeer));
      }

      if (action === "socket" && request.method === "GET") {
        const id = env.ROOMS.idFromName(roomCode);
        const stub = env.ROOMS.get(id);
        return stub.fetch(request);
      }

      return json({ error: "Method not allowed." }, 405);
    } catch (error: unknown) {
      return errorResponse(error);
    }
  }
};

export class PreferansRoom {
  private readonly ctx: DurableObjectState;
  private readonly env: Env;

  constructor(ctx: DurableObjectState, env: Env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "POST" && url.pathname === "/create") {
        const body = await readJSON<CreateRoomInput>(request);
        const existing = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
        if (existing) {
          return json(publicRoom(existing));
        }
        const room = createInitialRoom(body);
        await this.ctx.storage.put(ROOM_STORAGE_KEY, room);
        return json(publicRoom(room), 201);
      }

      if (request.method === "POST" && url.pathname === "/join") {
        const body = await readJSON<JoinRoomBody>(request);
        const room = await this.loadRequiredRoom();
        const updated = joinRoom(room, body.localPeer);
        await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);
        await this.broadcastPresence(updated);
        return json(publicRoom(updated));
      }

      if (request.method === "GET" && url.pathname === "/summary") {
        return json(publicRoom(await this.loadRequiredRoom()));
      }

      if (request.method === "GET" && url.pathname.endsWith("/socket")) {
        return this.connectWebSocket(request);
      }

      return json({ error: "Method not allowed." }, 405);
    } catch (error: unknown) {
      return errorResponse(error);
    }
  }

  async connectWebSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ error: "Expected WebSocket upgrade." }, 426);
    }

    const room = await this.loadRequiredRoom();
    const url = new URL(request.url);
    const playerID = playerIDValue(url.searchParams.get("playerID"));
    const peer = room.peers.find((candidate) => peerID(candidate) === playerID);
    if (!peer) {
      throw new RoomStateError("unknown_player", "Player has not joined this room.", 403);
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ playerID, connectedAt: new Date().toISOString() });
    server.send(JSON.stringify({ type: "room", room: publicRoom(room) }));
    await this.broadcastPresence(room);

    return new Response(null, {
      status: 101,
      webSocket: client
    });
  }

  async webSocketMessage(ws: WebSocket, rawMessage: string | ArrayBuffer): Promise<void> {
    try {
      const attachment = ws.deserializeAttachment() as { playerID?: unknown } | undefined ?? {};
      const senderPlayerID = playerIDValue(attachment.playerID);
      const room = await this.loadRequiredRoom();
      const sender = room.peers.find((peer) => peerID(peer) === senderPlayerID);
      if (!sender) {
        throw new RoomStateError("unknown_player", "Sender is no longer in this room.", 403);
      }

      const payload = parseSocketPayload(rawMessage);
      switch (payload.type) {
      case "wire":
        await this.relayWireMessage(room, sender, payload);
        break;
      case "ping":
        ws.send(JSON.stringify({ type: "pong", sentAt: new Date().toISOString() }));
        break;
      default:
        throw new RoomStateError("unknown_socket_message", "Unknown socket message type.");
      }
    } catch (error: unknown) {
      ws.send(JSON.stringify(socketError(error)));
    }
  }

  async webSocketClose(): Promise<void> {
    const room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
    if (room) {
      await this.broadcastPresence(room);
    }
  }

  async webSocketError(): Promise<void> {
    const room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
    if (room) {
      await this.broadcastPresence(room);
    }
  }

  async relayWireMessage(room: RoomState, sender: OnlinePeer, payload: ClientSocketEnvelope): Promise<void> {
    const senderPlayerID = peerID(sender);
    const recipientPlayerIDs = routeRecipients(room, senderPlayerID, payload.recipients);
    const { room: updated, entry } = recordRelay(room, {
      senderPlayerID,
      recipientPlayerIDs,
      message: payload.message
    });
    await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);

    const outbound = JSON.stringify({
      type: "wire",
      sender: normalizePeer(sender),
      message: payload.message,
      serverSequence: entry.serverSequence,
      sentAt: entry.sentAt
    });
    this.sendToPlayers(recipientPlayerIDs, outbound);
  }

  async loadRequiredRoom(): Promise<RoomState> {
    const room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
    if (!room) {
      throw new RoomStateError("room_not_found", "Room does not exist.", 404);
    }
    return room;
  }

  async broadcastPresence(room: RoomState): Promise<void> {
    const message = JSON.stringify({ type: "presence", room: publicRoom(room) });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(message);
      } catch {
        // Ignore dead sockets; Cloudflare will deliver close/error callbacks.
      }
    }
  }

  sendToPlayers(playerIDs: string[], message: string): void {
    const recipients = new Set(playerIDs);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as { playerID?: string } | undefined ?? {};
      if (attachment.playerID && recipients.has(attachment.playerID)) {
        socket.send(message);
      }
    }
  }
}

async function roomFetch(env: Env, roomCode: string, pathname: string, body?: unknown): Promise<PublicRoom> {
  const id = env.ROOMS.idFromName(roomCode);
  const stub = env.ROOMS.get(id);
  const response = await stub.fetch(`https://room${pathname}`, {
    method: body ? "POST" : "GET",
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await response.json() as { code?: string; error?: string } & PublicRoom;
  if (!response.ok) {
    throw new RoomStateError(data.code ?? "room_error", data.error ?? "Room request failed.", response.status);
  }
  return data;
}

function withSocketURL(request: Request, room: PublicRoom, localPeer: unknown): RoomWithSocketURL {
  const url = new URL(request.url);
  const protocol = url.protocol === "https:" ? "wss:" : "ws:";
  const playerID = playerIDValue(peerPlayerID(localPeer));
  return {
    ...room,
    websocketURL: `${protocol}//${url.host}/rooms/${room.roomCode}/socket?playerID=${encodeURIComponent(playerID)}`
  };
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    throw new RoomStateError("invalid_json", "Request body must be JSON.");
  }
}

function parseSocketPayload(rawMessage: string | ArrayBuffer): ClientSocketEnvelope {
  const text = typeof rawMessage === "string"
    ? rawMessage
    : new TextDecoder().decode(rawMessage);
  try {
    return JSON.parse(text) as ClientSocketEnvelope;
  } catch {
    throw new RoomStateError("invalid_socket_json", "Socket message must be JSON.");
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...corsHeaders()
    }
  });
}

function html(markup: string, status = 200): Response {
  return new Response(markup, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      ...corsHeaders()
    }
  });
}

function errorResponse(error: unknown): Response {
  const status = isErrorWithStatus(error) ? Number(error.status) || 500 : 500;
  return json({
    error: error instanceof Error ? error.message : "Internal server error.",
    code: isErrorWithCode(error) ? error.code : "internal_error"
  }, status);
}

function socketError(error: unknown): Record<string, unknown> {
  return {
    type: "error",
    error: error instanceof Error ? error.message : "Socket error.",
    code: isErrorWithCode(error) ? error.code : "socket_error"
  };
}

function peerPlayerID(peer: unknown): unknown {
  if (typeof peer === "object" && peer !== null && "playerID" in peer) {
    return peer.playerID;
  }
  return undefined;
}

function corsHeaders(): HeadersInit {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type"
  };
}

function invitePage(roomCode: string): string {
  const escapedCode = escapeHTML(roomCode);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Join Preferans Table ${escapedCode}</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #063528; color: #f8efd6; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    main { width: min(420px, calc(100vw - 32px)); padding: 28px; border: 1px solid rgba(218, 176, 86, .36); border-radius: 14px; background: rgba(0, 0, 0, .28); box-shadow: 0 24px 60px rgba(0,0,0,.28); }
    h1 { margin: 0 0 10px; font-size: 28px; }
    p { color: rgba(248, 239, 214, .78); line-height: 1.45; }
    .code { display: inline-block; margin: 8px 0 18px; padding: 8px 12px; border-radius: 8px; background: rgba(0,0,0,.24); color: #dab056; font-weight: 700; letter-spacing: .08em; }
  </style>
</head>
<body>
  <main>
    <h1>Join Preferans</h1>
    <p>Your table code is:</p>
    <div class="code">${escapedCode}</div>
    <p>Install the beta, then enter this room code from the lobby.</p>
  </main>
</body>
</html>`;
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    switch (character) {
    case "&": return "&amp;";
    case "<": return "&lt;";
    case ">": return "&gt;";
    case "\"": return "&quot;";
    case "'": return "&#39;";
    default: return character;
    }
  });
}

function isErrorWithStatus(error: unknown): error is { status: number } {
  return typeof error === "object" && error !== null && "status" in error;
}

function isErrorWithCode(error: unknown): error is { code: string } {
  return typeof error === "object" && error !== null && "code" in error && typeof error.code === "string";
}
