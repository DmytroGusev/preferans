import {
  type CreateRoomInput,
  type OnlinePeer,
  type PublicRoom,
  type RoomState,
  type WirePlayerID,
  MAX_SOCKET_MESSAGE_BYTES,
  RoomStateError,
  applyStateReport,
  authorizeSeat,
  createInitialRoom,
  fillOpenSeatsWithBots,
  generateRoomCode,
  isHostAccount,
  isHumanAccount,
  joinRoom,
  normalizePeer,
  normalizeRoomCode,
  peerID,
  playerIDValue,
  publicRoom,
  recordRelay,
  routeRecipients,
  humanPeers
} from "./room-state";
import {
  type GameSummaryEntry,
  type LibraryState,
  buildSummaryEntry,
  emptyLibrary,
  listGames,
  removeGame,
  upsertGame
} from "./library-state";

const ROOM_STORAGE_KEY = "room";
const LIBRARY_STORAGE_KEY = "library";
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
  /// Per-account game index, keyed by `accountID`. Rooms fan their summaries
  /// into it so the lobby can list a player's games with a single read.
  ACCOUNTS: DurableObjectNamespace;
  /// "true" once pre-seat-token clients have aged out: flips `/snapshot` and
  /// `/abandon` from "reject only a wrong token" to "require the token". The
  /// WebSocket path enforces unconditionally — its URL is server-built, so
  /// every client, old or new, already carries its token there.
  REQUIRE_SEAT_TOKENS?: string;
}

interface CreateRoomBody {
  localPeer?: unknown;
}

interface JoinRoomBody {
  localPeer?: unknown;
}

interface FillBotsBody {
  hostSecret?: unknown;
}

/// Host-authored progress report. Carries the lifecycle status, worker-readable
/// summary, and the opaque resume snapshot. Authenticated with the host secret.
interface StateReportBody {
  hostSecret?: unknown;
  status?: unknown;
  summary?: unknown;
  snapshot?: unknown;
  snapshotSequence?: unknown;
}

/// A seated participant gives up an unfinished game. Authorized by holding the
/// seat (`playerID` + its `seatToken`), not the host secret — abandoning is any
/// participant's right, and the originating host may be long gone.
interface AbandonBody {
  playerID?: unknown;
  seatToken?: unknown;
}

/// A `PublicRoom` plus the caller's own credentials: the seat token minted for
/// the seat the caller holds (`/create` and `/join`), and the host secret
/// (`/create`, or `/join` when the joiner is the returning host account).
type RoomWithSecret = PublicRoom & { hostSecret?: string; seatToken?: string };

interface RoomWithSocketURL extends PublicRoom {
  websocketURL: string;
  hostSecret?: string;
  seatToken?: string;
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

      if (request.method === "GET" && url.pathname === "/my-games") {
        const accountID = (url.searchParams.get("accountID") ?? "").trim();
        if (!accountID) {
          throw new RoomStateError("invalid_account", "An accountID query parameter is required.");
        }
        const id = env.ACCOUNTS.idFromName(accountID);
        return env.ACCOUNTS.get(id).fetch("https://account/list");
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
        // A code collision (~1 in a billion per attempt, but inevitable at
        // scale) retries with a fresh code instead of replying with the
        // existing room — the old idempotent reply handed a stranger that
        // room's host secret.
        let collision: RoomStateError | undefined;
        for (let attempt = 0; attempt < 5; attempt += 1) {
          const roomCode = generateRoomCode();
          try {
            const room = await roomFetch(env, roomCode, "/create", {
              ...body,
              roomCode
            });
            return json(withSocketURL(request, room, body.localPeer));
          } catch (error: unknown) {
            if (error instanceof RoomStateError && error.code === "room_exists") {
              collision = error;
              continue;
            }
            throw error;
          }
        }
        throw collision ?? new RoomStateError("room_exists", "Could not allocate a room code.", 503);
      }

      const fillBotsMatch = url.pathname.match(/^\/rooms\/([A-Za-z0-9-]+)\/seats\/fill-bots$/);
      if (fillBotsMatch && request.method === "POST") {
        const roomCode = normalizeRoomCode(fillBotsMatch[1]);
        const body = await readJSON<FillBotsBody>(request);
        const room = await roomFetch(env, roomCode, "/seats/fill-bots", body);
        return json(room);
      }

      const match = url.pathname.match(/^\/rooms\/([A-Za-z0-9-]+)(?:\/(join|socket|state|snapshot|abandon))?$/);
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

      if (action === "state" && request.method === "POST") {
        const body = await readJSON<StateReportBody>(request);
        const room = await roomFetch(env, roomCode, "/state", body);
        return json(room);
      }

      if (action === "snapshot" && request.method === "GET") {
        // Forward the participant's seat + token as query params; the DO
        // authorizes them.
        const playerID = url.searchParams.get("playerID") ?? "";
        const seatToken = url.searchParams.get("seatToken") ?? "";
        return roomStubFetch(
          env,
          roomCode,
          `/snapshot?playerID=${encodeURIComponent(playerID)}&seatToken=${encodeURIComponent(seatToken)}`
        );
      }

      if (action === "abandon" && request.method === "POST") {
        const body = await readJSON<AbandonBody>(request);
        const room = await roomFetch(env, roomCode, "/abandon", body);
        return json(room);
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

  /// Whether `/snapshot` and `/abandon` demand the seat token outright, or only
  /// reject a mismatched one (the compatibility window for pre-token clients).
  private get requireSeatTokens(): boolean {
    return this.env.REQUIRE_SEAT_TOKENS === "true";
  }

  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "POST" && url.pathname === "/create") {
        const body = await readJSON<CreateRoomInput>(request);
        const existing = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
        if (existing) {
          // Never reply with the existing room: this caller is a stranger who
          // happened to draw the same code, and the create payload carries the
          // room's credentials. The worker retries with a fresh code.
          throw new RoomStateError("room_exists", "Room code is already in use.", 409);
        }
        const room = createInitialRoom(body);
        await this.ctx.storage.put(ROOM_STORAGE_KEY, room);
        await this.fanOutToLibraries(room);
        return json(createResult(room), 201);
      }

      if (request.method === "POST" && url.pathname === "/join") {
        const body = await readJSON<JoinRoomBody>(request);
        const room = await this.loadRequiredRoom();
        const joiner = normalizePeer(body.localPeer);
        const updated = joinRoom(room, joiner);
        await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);
        await this.broadcastPresence(updated);
        // A join changes the roster — refresh every participant's library entry
        // (and seed the new joiner's) so the game shows up under "Your games".
        await this.fanOutToLibraries(updated);
        // The joiner gets its own seat credential back — and, when the joining
        // account holds the host seat (a resuming host), the host secret too.
        // Without the secret a resumed host could relay moves but never push
        // state reports or fill bot seats — the durable snapshot would freeze
        // at the pre-resume state. Guests never match the host seat, so the
        // secret still never reaches them.
        const seat = updated.peers.find((peer) => peer.accountID === joiner.accountID);
        const result: RoomWithSecret = { ...publicRoom(updated), seatToken: seat?.seatToken };
        if (isHostAccount(updated, joiner.accountID)) {
          result.hostSecret = updated.hostSecret;
        }
        return json(result);
      }

      if (request.method === "POST" && url.pathname === "/seats/fill-bots") {
        const body = await readJSON<FillBotsBody>(request);
        const room = await this.loadRequiredRoom();
        // Host-only: the caller must present the secret minted at `/create`.
        if (!room.hostSecret || String(body.hostSecret ?? "") !== room.hostSecret) {
          throw new RoomStateError("forbidden", "Only the host can fill open seats with bots.", 403);
        }
        const updated = fillOpenSeatsWithBots(room);
        if (updated !== room) {
          await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);
          await this.broadcastPresence(updated);
          await this.fanOutToLibraries(updated);
        }
        return json(publicRoom(updated));
      }

      if (request.method === "POST" && url.pathname === "/state") {
        const body = await readJSON<StateReportBody>(request);
        const room = await this.loadRequiredRoom();
        // Host-only: progress reports must present the secret minted at `/create`.
        if (!room.hostSecret || String(body.hostSecret ?? "") !== room.hostSecret) {
          throw new RoomStateError("forbidden", "Only the host can report game state.", 403);
        }
        const { room: updated, changed } = applyStateReport(room, body);
        await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);
        // Only a material change (status/deal/phase) is worth a presence push
        // and a library fan-out; per-action snapshot refreshes stay silent to
        // avoid socket churn and DO-to-DO chatter.
        if (changed) {
          await this.broadcastPresence(updated);
          await this.fanOutToLibraries(updated);
        }
        return json(publicRoom(updated));
      }

      if (request.method === "GET" && url.pathname === "/snapshot") {
        return json(this.resumePayload(await this.loadRequiredRoom(), url));
      }

      if (request.method === "POST" && url.pathname === "/abandon") {
        const body = await readJSON<AbandonBody>(request);
        const room = await this.loadRequiredRoom();
        // Kills the game for everyone, so it takes the seat token (strict once
        // REQUIRE_SEAT_TOKENS flips) — otherwise the room code alone was
        // enough to grief any table.
        const peer = authorizeSeat(room, body.playerID, body.seatToken, this.requireSeatTokens);
        if (!isHumanAccount(peer.accountID)) {
          throw new RoomStateError("forbidden", "Only a seated player can abandon this game.", 403);
        }
        const { room: updated, changed } = applyStateReport(room, { status: "abandoned" });
        await this.ctx.storage.put(ROOM_STORAGE_KEY, updated);
        if (changed) {
          await this.broadcastPresence(updated);
          await this.fanOutToLibraries(updated);
        }
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
    // Always enforced: the socket URL is server-built (see `withSocketURL`),
    // so every client — including pre-token builds — already carries its seat
    // token here. Without this check, the room code alone let an attacker
    // attach as any seat and act as that player.
    const peer = authorizeSeat(room, url.searchParams.get("playerID"), url.searchParams.get("seatToken"), true);
    const playerID = peerID(peer);

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

  /// The resume payload for a seated participant: the opaque authoritative
  /// snapshot plus the worker-readable status/summary. The snapshot reveals
  /// every hidden hand, so the caller must prove seat ownership with its seat
  /// token (strict once `REQUIRE_SEAT_TOKENS` flips; until then a wrong token
  /// is still rejected, and pre-token clients pass on the seat alone).
  resumePayload(room: RoomState, url: URL): Record<string, unknown> {
    const peer = authorizeSeat(
      room,
      url.searchParams.get("playerID"),
      url.searchParams.get("seatToken"),
      this.requireSeatTokens
    );
    if (!isHumanAccount(peer.accountID)) {
      throw new RoomStateError("forbidden", "Only a seated player can fetch the resume snapshot.", 403);
    }
    return {
      roomCode: room.roomCode,
      status: room.status ?? "lobby",
      summary: room.summary ?? null,
      lastSnapshotSequence: room.lastSnapshotSequence ?? 0,
      snapshot: room.latestSnapshot ?? null
    };
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

  /// Push this room's current summary into every human participant's
  /// `PlayerLibrary`, one entry per seat. Bots and reserved (`pending:`) seats
  /// are skipped — only real accounts get a "Your games" row. Failures are
  /// swallowed per-account so one unreachable index never blocks the others.
  async fanOutToLibraries(room: RoomState): Promise<void> {
    await Promise.all(
      humanPeers(room).map(async (peer) => {
        const entry = buildSummaryEntry(room, peer);
        try {
          const id = this.env.ACCOUNTS.idFromName(peer.accountID);
          await this.env.ACCOUNTS.get(id).fetch("https://account/upsert", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(entry)
          });
        } catch {
          // Best-effort index update; the room state remains the source of truth.
        }
      })
    );
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

/// Per-account game index, keyed by `accountID`. Holds one `GameSummaryEntry`
/// per room the account participates in; rooms upsert into it on every material
/// transition. The lobby reads `/list` (via the worker's `/my-games`) to render
/// a player's Continue + History without scanning rooms.
export class PlayerLibrary {
  private readonly ctx: DurableObjectState;

  constructor(ctx: DurableObjectState, _env: Env) {
    this.ctx = ctx;
  }

  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "POST" && url.pathname === "/upsert") {
        const entry = await readJSON<GameSummaryEntry>(request);
        const state = await this.load();
        await this.ctx.storage.put(LIBRARY_STORAGE_KEY, upsertGame(state, entry));
        return json({ ok: true });
      }

      if (request.method === "POST" && url.pathname === "/remove") {
        const body = await readJSON<{ roomCode?: unknown }>(request);
        const roomCode = String(body.roomCode ?? "").trim();
        const state = await this.load();
        const next = removeGame(state, roomCode);
        if (next !== state) {
          await this.ctx.storage.put(LIBRARY_STORAGE_KEY, next);
        }
        return json({ ok: true });
      }

      if (request.method === "GET" && url.pathname === "/list") {
        return json({ games: listGames(await this.load()) });
      }

      return json({ error: "Method not allowed." }, 405);
    } catch (error: unknown) {
      return errorResponse(error);
    }
  }

  private async load(): Promise<LibraryState> {
    return (await this.ctx.storage.get<LibraryState>(LIBRARY_STORAGE_KEY)) ?? emptyLibrary();
  }
}

async function roomFetch(env: Env, roomCode: string, pathname: string, body?: unknown): Promise<RoomWithSecret> {
  const id = env.ROOMS.idFromName(roomCode);
  const stub = env.ROOMS.get(id);
  const response = await stub.fetch(`https://room${pathname}`, {
    method: body ? "POST" : "GET",
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await response.json() as { code?: string; error?: string } & RoomWithSecret;
  if (!response.ok) {
    throw new RoomStateError(data.code ?? "room_error", data.error ?? "Room request failed.", response.status);
  }
  return data;
}

/// Pass a Durable Object's response straight back to the caller, untouched. Used
/// for payloads (e.g. the resume snapshot) that don't fit the `RoomWithSecret`
/// shape `roomFetch` parses, where re-decoding would be wasteful.
async function roomStubFetch(env: Env, roomCode: string, pathname: string): Promise<Response> {
  const id = env.ROOMS.idFromName(roomCode);
  const stub = env.ROOMS.get(id);
  return stub.fetch(`https://room${pathname}`);
}

/// The `/create` response: the public room plus the creator's credentials (host
/// secret + the host seat's token). `/join` hands back the joiner's seat token
/// the same way; every broadcast surface uses `publicRoom`, which omits both.
function createResult(room: RoomState): RoomWithSecret {
  const hostSeat = room.peers.find((peer) => peerID(peer) === room.hostPlayerID);
  return { ...publicRoom(room), hostSecret: room.hostSecret, seatToken: hostSeat?.seatToken };
}

function withSocketURL(request: Request, room: RoomWithSecret, localPeer: unknown): RoomWithSocketURL {
  const url = new URL(request.url);
  const protocol = url.protocol === "https:" ? "wss:" : "ws:";
  const playerID = assignedSeatID(room, localPeer);
  // Embed the caller's seat token so the socket authenticates for every
  // client: the app treats this URL as opaque, so even pre-token builds
  // present the credential.
  const token = room.seatToken ? `&seatToken=${encodeURIComponent(room.seatToken)}` : "";
  return {
    ...room,
    websocketURL: `${protocol}//${url.host}/rooms/${room.roomCode}/socket?playerID=${encodeURIComponent(playerID)}${token}`
  };
}

// The seat the server bound to this caller's account. The socket must attach as
// the assigned seat, not the `playerID` the client declared in its join body —
// the server ignores that when assigning seats, so they can differ. Matching on
// the normalized `accountID` keeps the socket identity in step with `joinRoom`.
function assignedSeatID(room: PublicRoom, localPeer: unknown): string {
  let accountID: string | undefined;
  try {
    accountID = normalizePeer(localPeer).accountID;
  } catch {
    accountID = undefined;
  }
  if (accountID) {
    const seat = room.peers.find((candidate) => candidate.accountID === accountID);
    if (seat) {
      return peerID(seat);
    }
  }
  return playerIDValue(peerPlayerID(localPeer));
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
  // Reject oversized frames before parsing: relayed messages are persisted
  // work for every recipient, and no legitimate wire message approaches this
  // size (snapshots travel over HTTP /state, not the socket).
  if (text.length > MAX_SOCKET_MESSAGE_BYTES) {
    throw new RoomStateError("message_too_large", "Socket message exceeds the size limit.", 413);
  }
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
