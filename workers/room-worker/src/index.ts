import { commandIdentity, MutationQueue, type StoredCommand, type CommandReceipt } from "./command-contract";
import {
  type CreateRoomInput,
  type OnlinePeer,
  type PublicRoom,
  type RoomState,
  type WirePlayerID,
  BOT_ACCOUNT_PREFIX,
  DELETED_ACCOUNT_PREFIX,
  MAX_SOCKET_MESSAGE_BYTES,
  PENDING_ACCOUNT_PREFIX,
  ROOM_SCHEMA_VERSION,
  RoomStateError,
  abandonRoom,
  authorizeHostSeat,
  authorizeRelayMessage,
  authorizeSeat,
  createInitialRoom,
  fillOpenSeatsWithBots,
  electLiveHost,
  generateRoomCode,
  isHumanAccount,
  joinRoom,
  normalizePeer,
  normalizeRoomCode,
  peerID,
  playerIDValue,
  publicRoom,
  recordRelay,
  removeAccountFromRoom,
  humanPeers,
  wirePlayerID
} from "./room-state";
import {
  type GameSummaryEntry,
  buildSummaryEntry,
  listGames,
  removeGame,
  upsertGame
} from "./library-state";
import {
  ACCOUNT_SCHEMA_VERSION,
  type AccountProvider,
  type PlayerAccountState,
  type PublicAccount,
  AccountStateError,
  authenticateSession,
  bearerToken,
  createAccountState,
  guestAccountID,
  issueSession,
  normalizeDisplayName,
  parseSessionToken,
  publicAccount
} from "./account-state";
import { verifyAppleIdentityToken } from "./apple-auth";
import { Container, getRandom } from "@cloudflare/containers";
import {
  type AuthoritativeEngineBinding,
  applyAuthoritativeCommand,
  callEngine,
  adoptingEngineResponse,
  clientActionFromWireMessage,
  createAuthoritativeGame,
  isStartDealCommand,
  projectionWireMessage,
  validateStartDealAuthority
} from "./authoritative-engine";

const ROOM_STORAGE_KEY = "room";
const ACCOUNT_STORAGE_KEY = "account";
const APP_ID = "3WSQ6X9CDT.com.mixandmatch.preferans";
const DEFAULT_APPLE_AUDIENCE = "com.mixandmatch.preferans";

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
  /// Authenticated account + game index, keyed by the server-issued accountID.
  ACCOUNTS: DurableObjectNamespace;
  ENGINE: DurableObjectNamespace<PreferansEngineContainer>;
  APPLE_CLIENT_ID?: string;
}

interface CreateRoomBody {
  localPlayerID?: unknown;
  seats?: unknown;
  maxPlayers?: unknown;
  rules?: unknown;
  match?: unknown;
  variant?: unknown;
}

interface JoinRoomBody {
  requestedPlayerID?: unknown;
}

interface FillBotsBody {
  accountID?: unknown;
  playerID?: unknown;
  seatToken?: unknown;
}

/// A seated participant gives up an unfinished game. Authorized by holding the
/// seat (`playerID` + its `seatToken`), not current-host authority — abandoning is any
/// participant's right, and the originating host may be long gone.
interface AbandonBody {
  accountID?: unknown;
  playerID?: unknown;
  seatToken?: unknown;
}

interface GuestRegistrationBody {
  displayName?: unknown;
}

interface AppleRegistrationBody extends GuestRegistrationBody {
  identityToken?: unknown;
  nonce?: unknown;
}

/// A `PublicRoom` plus the caller's own rotating room credential.
type RoomWithSecret = PublicRoom & { seatToken?: string };

interface RoomWithSocketURL extends PublicRoom {
  websocketURL: string;
  seatToken?: string;
}

interface ClientSocketEnvelope {
  type?: "wire" | "ping";
  recipients?: WirePlayerID[];
  reliable?: boolean;
  message?: unknown;
}

interface SocketAttachment {
  playerID?: string;
  seatToken?: string;
  connectedAt?: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders() });
      }

      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return json({
          ok: true,
          service: "preferans-room-worker",
          accountSchemaVersion: ACCOUNT_SCHEMA_VERSION,
          roomSchemaVersion: ROOM_SCHEMA_VERSION
        });
      }

      if (request.method === "POST" && url.pathname === "/v2/accounts/guest") {
        const body = await readJSON<GuestRegistrationBody>(request);
        return json(await registerAccount(
          env,
          guestAccountID(),
          "guest",
          normalizeDisplayName(body.displayName)
        ), 201);
      }

      if (request.method === "POST" && url.pathname === "/v2/accounts/apple") {
        const body = await readJSON<AppleRegistrationBody>(request);
        const identity = await verifyAppleIdentityToken(
          body.identityToken,
          body.nonce,
          env.APPLE_CLIENT_ID ?? DEFAULT_APPLE_AUDIENCE
        );
        return json(await registerAccount(
          env,
          `apple:${identity.subject}`,
          "apple",
          normalizeDisplayName(body.displayName)
        ), 201);
      }

      if (request.method === "GET" && url.pathname === "/v2/my-games") {
        const account = await authenticateAccount(request, env);
        const id = env.ACCOUNTS.idFromName(account.accountID);
        return env.ACCOUNTS.get(id).fetch("https://account/list");
      }

      if (request.method === "DELETE" && url.pathname === "/v2/account") {
        return deleteAuthenticatedAccount(request, env);
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

      if (request.method === "POST" && url.pathname === "/v2/rooms") {
        const account = await authenticateAccount(request, env);
        const body = await readJSON<CreateRoomBody>(request);
        // A code collision (~1 in a billion per attempt, but inevitable at
        // scale) retries with a fresh code instead of replying with the
        // existing room — an idempotent reply would expose room metadata and
        // the caller-scoped credential boundary to a stranger.
        let collision: RoomStateError | undefined;
        for (let attempt = 0; attempt < 5; attempt += 1) {
            const roomCode = generateRoomCode();
            try {
            const input = createRoomInput(roomCode, body, account);
            const room = await roomFetch(env, roomCode, "/create", input);
            return json(withSocketURL(request, room, input.localPeer));
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

      const fillBotsMatch = url.pathname.match(/^\/v2\/rooms\/([A-Za-z0-9-]+)\/seats\/fill-bots$/);
      if (fillBotsMatch && request.method === "POST") {
        const account = await authenticateAccount(request, env);
        const body = await readJSON<FillBotsBody>(request);
        const roomCode = normalizeRoomCode(fillBotsMatch[1]);
        const room = await roomFetch(env, roomCode, "/seats/fill-bots", {
          ...body,
          accountID: account.accountID
        });
        return json(room);
      }

      const match = url.pathname.match(/^\/v2\/rooms\/([A-Za-z0-9-]+)(?:\/(join|socket|state|snapshot|abandon))?$/);
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
        const account = await authenticateAccount(request, env);
        const body = await readJSON<JoinRoomBody>(request);
        const localPeer = authenticatedPeer(account, body.requestedPlayerID);
        const room = await roomFetch(env, roomCode, "/join", { localPeer });
        return json(withSocketURL(request, room, localPeer));
      }

      if (action === "state" && request.method === "POST") {
        return json({
          code: "client_state_removed",
          error: "Schema-v3 rooms do not accept client-authored game state."
        }, 410);
      }

      if (action === "snapshot" && request.method === "GET") {
        return json({
          code: "client_snapshot_removed",
          error: "Schema-v3 rooms resume from server projections, not engine snapshots."
        }, 410);
      }

      if (action === "abandon" && request.method === "POST") {
        const account = await authenticateAccount(request, env);
        const body = await readJSON<AbandonBody>(request);
        const room = await roomFetch(env, roomCode, "/abandon", { ...body, accountID: account.accountID });
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

/// Stateless Linux Swift transition service. Durable room state remains in
/// `PreferansRoomV2`; this class only manages a small warm container pool.
export class PreferansEngineContainer extends Container<Env> {
  defaultPort = 8080;
  sleepAfter = "10m";
}

export class PreferansRoomV2 {
  private readonly ctx: DurableObjectState;
  private readonly env: Env;
  private mutations = new MutationQueue();

  constructor(ctx: DurableObjectState, env: Env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    return this.serializeMutation(() => this.fetchUnlocked(request));
  }

  private async fetchUnlocked(request: Request): Promise<Response> {
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
        const creator = room.peers.find((peer) => peerID(peer) === room.hostPlayerID);
        if (!creator) {
          throw new RoomStateError("invalid_host", "Room creator does not own a seat.", 500);
        }
        // Account deletion enumerates this durable membership index. A room
        // must not become visible until its creator can later find and delete
        // it; transition-only refreshes remain best-effort below.
        const initialized = await createAuthoritativeGame(room, this.engine());
        await this.upsertLibraryEntry(initialized, creator);
        await this.commitRoom(initialized);
        return json(createResult(initialized), 201);
      }

      if (request.method === "POST" && url.pathname === "/join") {
        const body = await readJSON<{ localPeer?: unknown }>(request);
        const room = await this.loadRequiredRoom();
        const joiner = normalizePeer(body.localPeer);
        let updated = joinRoom(room, joiner);
        if (updated.status === "lobby") {
          updated = await createAuthoritativeGame(updated, this.engine());
        }
        const joinedSeat = updated.peers.find((peer) => peer.accountID === joiner.accountID);
        if (!joinedSeat) {
          throw new RoomStateError("invalid_join", "Joined account does not own a seat.", 500);
        }
        // Make membership durable before publishing the roster. This is the
        // account's authoritative room index for resume and later deletion.
        await this.upsertLibraryEntry(updated, joinedSeat);
        await this.commitRoom(updated);
        this.closeSocketsForPlayers([peerID(joinedSeat)], 4009, "seat_replaced");
        await this.broadcastPresence(updated);
        this.broadcastAuthoritativeProjections(
          updated,
          updated.relaySequence,
          new Date().toISOString()
        );
        // A join changes the roster — refresh every participant's library entry
        // (and seed the new joiner's) so the game shows up under "Your games".
        await this.fanOutToLibraries(updated, new Set([joiner.accountID]));
        // The joiner gets only its own seat credential. Host-only HTTP actions
        // are authorized by the authenticated account session, so there is no
        // second long-lived host secret to leak or synchronize.
        const seat = updated.peers.find((peer) => peer.accountID === joiner.accountID);
        const result: RoomWithSecret = { ...publicRoom(updated), seatToken: seat?.seatToken };
        return json(result);
      }

      if (request.method === "POST" && url.pathname === "/seats/fill-bots") {
        const body = await readJSON<FillBotsBody>(request);
        const room = await this.loadRequiredRoom();
        authorizeHostSeat(room, String(body.accountID ?? ""), body.playerID, body.seatToken);
        let updated = fillOpenSeatsWithBots(room);
        if (updated !== room) {
          updated = await createAuthoritativeGame(updated, this.engine());
        }
        if (updated !== room) {
          await this.commitRoom(updated);
          await this.broadcastPresence(updated);
          this.broadcastAuthoritativeProjections(
            updated,
            updated.relaySequence,
            new Date().toISOString()
          );
          await this.fanOutToLibraries(updated);
        }
        return json(publicRoom(updated));
      }

      if (request.method === "POST" && url.pathname === "/state") {
        throw new RoomStateError(
          "client_state_removed",
          "Schema-v3 rooms do not accept client-authored game state.",
          410
        );
      }

      if (request.method === "GET" && url.pathname === "/snapshot") {
        throw new RoomStateError(
          "client_snapshot_removed",
          "Schema-v3 rooms resume from server projections, not engine snapshots.",
          410
        );
      }

      if (request.method === "POST" && url.pathname === "/abandon") {
        const body = await readJSON<AbandonBody>(request);
        const room = await this.loadRequiredRoom();
        const peer = authorizeSeat(room, body.playerID, body.seatToken);
        if (peer.accountID !== String(body.accountID ?? "")) {
          throw new RoomStateError("forbidden", "This account does not own that seat.", 403);
        }
        if (!isHumanAccount(peer.accountID)) {
          throw new RoomStateError("forbidden", "Only a seated player can abandon this game.", 403);
        }
        const updated = abandonRoom(room);
        if (updated !== room) {
          await this.commitRoom(updated);
          await this.broadcastPresence(updated);
          await this.fanOutToLibraries(updated);
        }
        return json(publicRoom(updated));
      }

      if (request.method === "POST" && url.pathname === "/account-deleted") {
        const body = await readJSON<{ accountID?: unknown }>(request);
        const accountID = String(body.accountID ?? "");
        if (!accountID || accountID.startsWith(DELETED_ACCOUNT_PREFIX)) {
          throw new RoomStateError("invalid_account", "A current account ID is required.");
        }
        const room = await this.loadRequiredRoom();
        const { room: scrubbed, removedPlayerIDs } = removeAccountFromRoom(room, accountID);
        if (removedPlayerIDs.length === 0) {
          return json(publicRoom(room));
        }

        const remainingLivePlayers = this.activePlayerIDs()
          .filter((playerID) => !removedPlayerIDs.includes(playerID));
        const updated = electLiveHost(scrubbed, remainingLivePlayers);
        await this.commitRoom(updated);
        this.closeSocketsForPlayers(removedPlayerIDs, 4010, "account_deleted");
        await this.broadcastPresence(updated);
        await this.fanOutToLibraries(updated);
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
    const peer = authorizeSeat(room, url.searchParams.get("playerID"), url.searchParams.get("seatToken"));
    const playerID = peerID(peer);

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({
      playerID,
      seatToken: peer.seatToken,
      connectedAt: new Date().toISOString()
    });
    this.closeOtherSocketsForSeat(playerID, server);
    const activeRoom = await this.reconcileHost(room);
    server.send(JSON.stringify({
      type: "room",
      room: publicRoom(activeRoom),
      connectedPlayerIDs: this.activePlayerIDs().map(wirePlayerID)
    }));
    this.sendProjectionToSocket(server, activeRoom, playerID);
    await this.broadcastPresence(activeRoom);

    return new Response(null, {
      status: 101,
      webSocket: client
    });
  }

  async webSocketMessage(ws: WebSocket, rawMessage: string | ArrayBuffer): Promise<void> {
    await this.serializeMutation(() => this.webSocketMessageUnlocked(ws, rawMessage));
  }

  private async webSocketMessageUnlocked(
    ws: WebSocket,
    rawMessage: string | ArrayBuffer
  ): Promise<void> {
    try {
      const attachment = ws.deserializeAttachment() as SocketAttachment | undefined ?? {};
      const room = await this.loadRequiredRoom();
      const sender = authorizeSeat(room, attachment.playerID, attachment.seatToken);

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
      if (error instanceof RoomStateError && error.code === "seat_credential_invalid") {
        ws.close(4009, "seat_replaced");
      }
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    return this.serializeMutation(() => this.disconnectSocket(ws));
  }

  private async disconnectSocket(ws: WebSocket): Promise<void> {
    const room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
    if (room) {
      const activeRoom = await this.reconcileHost(room, ws);
      await this.broadcastPresence(activeRoom);
    }
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    return this.serializeMutation(() => this.disconnectSocket(ws));
  }

  async relayWireMessage(room: RoomState, sender: OnlinePeer, payload: ClientSocketEnvelope): Promise<void> {
    const senderPlayerID = peerID(sender);
    const command = clientActionFromWireMessage(payload.message);
    if (command) {
      const identity = await commandIdentity(sender.accountID, command);
      const stored = await this.ctx.storage.get<StoredCommand>(identity.key);
      if (stored) {
        if (stored.fingerprint !== identity.fingerprint) {
          this.sendReceipt(room, senderPlayerID, {
            ...stored.receipt, status: "rejected", code: "command_id_conflict",
            message: "This command ID was used for another action."
          });
        } else {
          this.sendReceipt(room, senderPlayerID, stored.receipt);
        }
        this.sendProjectionToPlayer(room, senderPlayerID, room.relaySequence, new Date().toISOString());
        return;
      }
      let updated: RoomState;
      try {
        if (room.status === "abandoned" || room.status === "finished") {
          throw new RoomStateError("table_closed", "This table has ended.", 409);
        }
        if (isStartDealCommand(command)) {
          validateStartDealAuthority(room, sender, new Set(this.activePlayerIDs()));
        }
        const transitioned = await applyAuthoritativeCommand(room, sender, command, this.engine());
        updated = recordRelay(transitioned, {
          senderPlayerID, recipientPlayerIDs: humanPeers(transitioned).map(peerID), message: payload.message
        }).room;
      } catch (error) {
        // Infrastructure failures are uncertain/retryable, never permanent rejections.
        if (!(error instanceof RoomStateError) || error.status >= 500) throw error;
        const receipt: CommandReceipt = {
          tableID: room.authoritativeTableID!, clientNonce: identity.nonce,
          sequence: room.authoritativeSequence ?? 0, status: "rejected",
          code: error.code, message: error.message
        };
        await this.ctx.storage.put(identity.key, { fingerprint: identity.fingerprint, receipt });
        this.sendReceipt(room, senderPlayerID, receipt);
        this.sendProjectionToPlayer(room, senderPlayerID, room.relaySequence, new Date().toISOString());
        return;
      }
      const receipt: CommandReceipt = {
        tableID: updated.authoritativeTableID!, clientNonce: identity.nonce,
        sequence: updated.authoritativeSequence!, status: "accepted"
      };
      await this.commitRoom(updated, identity.key, { fingerprint: identity.fingerprint, receipt });
      this.sendReceipt(updated, senderPlayerID, receipt);
      this.broadcastAuthoritativeProjections(updated, updated.relaySequence, new Date().toISOString());
      await this.broadcastPresence(updated);
      return;
    }

    if (isResyncRequest(payload.message)) {
      this.sendProjectionToPlayer(room, senderPlayerID, room.relaySequence, new Date().toISOString());
      return;
    }

    // Schema v3 has no peer-authored state, identity, or projection messages.
    // Keeping this rejection at the relay boundary prevents an old client from
    // silently recreating the client-host architecture inside a v3 room.
    authorizeRelayMessage(room, senderPlayerID, payload.message);
    throw new RoomStateError(
      "client_authority_removed",
      "Online rooms accept game commands only; state is produced by the server.",
      409
    );
  }

  private engine(): AuthoritativeEngineBinding {
    return {
      fetch: async (path, body) => {
        const container = await getRandom(this.env.ENGINE, 3);
        return container.fetch(`http://engine${path}`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(8_000)
        });
      }
    };
  }

  /// Durable Objects may interleave events while one awaits an external
  /// container fetch. Keep every room mutation behind an explicit FIFO so two
  /// commands can never both advance the same private state and race to store.
  private async serializeMutation<T>(operation: () => Promise<T>): Promise<T> {
    return this.mutations.run(operation);
  }

  private sendReceipt(room: RoomState, playerID: string, receipt: CommandReceipt): void {
    this.sendToPlayers(room, [playerID], JSON.stringify({ type: "receipt", receipt }));
  }

  private async commitRoom(room: RoomState, key?: string, command?: StoredCommand): Promise<void> {
    // Schedule before commit: an interruption can leave a harmless extra wakeup,
    // but never durable work with no alarm to resume it.
    await this.ctx.storage.setAlarm(Date.now() + 500);
    await this.ctx.storage.transaction(async txn => {
      await txn.put(ROOM_STORAGE_KEY, { ...room, botPending: room.status === "playing" && room.botPending, libraryDirty: true });
      if (key && command) await txn.put(key, command);
      if (command) await txn.put(`history:${String(room.authoritativeSequence).padStart(12, "0")}`, {
        receipt: command.receipt, fingerprint: command.fingerprint, engineVersion: room.engineVersion
      });
    });
  }

  async alarm(): Promise<void> {
    await this.serializeMutation(async () => {
      let room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
      if (!room) return;
      // The next alarm is installed before any external work. Crashes and exhausted
      // automatic alarm retries therefore cannot strand the durable outbox.
      if (room.libraryDirty || room.botPending) await this.ctx.storage.setAlarm(Date.now() + 5_000);
      if (room.botPending && room.status === "playing" && room.authoritativeState) {
        try {
          const response = await callEngine(this.engine(), "/v1/bots", { state: room.authoritativeState });
          if (response.sequence !== (room.authoritativeSequence ?? 0) + 1) {
            throw new RoomStateError("bot_stalled", "Bot did not advance the table.", 503);
          }
          room = adoptingEngineResponse(room, response);
          await this.commitRoom(room);
          this.broadcastAuthoritativeProjections(room, room.relaySequence, new Date().toISOString());
          await this.broadcastPresence(room);
        } catch {
          console.warn(JSON.stringify({ event: "bot_retry", room: room.roomCode, revision: room.authoritativeSequence }));
        }
      }
      room = await this.loadRequiredRoom();
      if (room.libraryDirty) {
        const results = await Promise.allSettled(humanPeers(room).map(peer => this.upsertLibraryEntry(room!, peer)));
        if (results.every(result => result.status === "fulfilled")) {
          room = { ...room, libraryDirty: false };
          await this.ctx.storage.put(ROOM_STORAGE_KEY, room);
        }
      }
      if (room.botPending || room.libraryDirty) {
        await this.ctx.storage.setAlarm(Date.now() + (room.botPending ? 500 : 5_000));
      } else {
        await this.ctx.storage.deleteAlarm();
      }
    });
  }

  private broadcastAuthoritativeProjections(room: RoomState, serverSequence: number, sentAt: string): void {
    for (const peer of humanPeers(room)) {
      this.sendProjectionToPlayer(room, peerID(peer), serverSequence, sentAt);
    }
  }

  private sendProjectionToPlayer(
    room: RoomState,
    playerID: string,
    serverSequence: number,
    sentAt: string
  ): void {
    const projection = room.authoritativeProjections?.[playerID];
    if (projection === undefined) return;
    const authorityPeer = room.peers[0];
    if (!authorityPeer) return;
    const outbound = JSON.stringify({
      type: "wire",
      authority: "server",
      sender: normalizePeer(authorityPeer),
      message: projectionWireMessage(projection),
      serverSequence,
      sentAt
    });
    this.sendToPlayers(room, [playerID], outbound);
  }

  private sendProjectionToSocket(ws: WebSocket, room: RoomState, playerID: string): void {
    const projection = room.authoritativeProjections?.[playerID];
    const authorityPeer = room.peers[0];
    if (projection === undefined || !authorityPeer) return;
    ws.send(JSON.stringify({
      type: "wire",
      authority: "server",
      sender: normalizePeer(authorityPeer),
      message: projectionWireMessage(projection),
      serverSequence: room.relaySequence,
      sentAt: new Date().toISOString()
    }));
  }

  async loadRequiredRoom(): Promise<RoomState> {
    const room = await this.ctx.storage.get<RoomState>(ROOM_STORAGE_KEY);
    if (!room) {
      throw new RoomStateError("room_not_found", "Room does not exist.", 404);
    }
    if (room.schemaVersion !== ROOM_SCHEMA_VERSION) {
      throw new RoomStateError("room_upgrade_required", "This room belongs to an older app version.", 410);
    }
    return room;
  }

  async broadcastPresence(room: RoomState): Promise<void> {
    const message = JSON.stringify({
      type: "presence",
      room: publicRoom(room),
      connectedPlayerIDs: this.activePlayerIDs().map(wirePlayerID)
    });
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
  async fanOutToLibraries(
    room: RoomState,
    excludingAccountIDs: ReadonlySet<string> = new Set()
  ): Promise<void> {
    // The write path has already persisted libraryDirty. Delivery happens in alarm().
    await this.ctx.storage.setAlarm(Date.now() + 500);
  }

  private async upsertLibraryEntry(room: RoomState, peer: OnlinePeer): Promise<void> {
    const entry = buildSummaryEntry(room, peer);
    const id = this.env.ACCOUNTS.idFromName(peer.accountID);
    const response = await this.env.ACCOUNTS.get(id).fetch("https://account/upsert", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(entry)
    });
    if (!response.ok) {
      const data = await response.json() as { code?: string; error?: string };
      throw new AccountStateError(
        data.code ?? "account_index_failed",
        data.error ?? "Could not index the room for this account.",
        response.status
      );
    }
  }

  sendToPlayers(room: RoomState, playerIDs: string[], message: string): void {
    const recipients = new Set(playerIDs);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as SocketAttachment | undefined ?? {};
      if (socket.readyState === 1 && attachment.playerID && recipients.has(attachment.playerID)
          && room.peers.some(peer => peerID(peer) === attachment.playerID && peer.seatToken === attachment.seatToken)) {
        try { socket.send(message); } catch { /* committed state survives delivery failure */ }
      }
    }
  }

  private closeOtherSocketsForSeat(playerID: string, current: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === current) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | undefined ?? {};
      if (attachment.playerID === playerID) {
        socket.close(4009, "seat_replaced");
      }
    }
  }

  private closeSocketsForPlayers(playerIDs: string[], code: number, reason: string): void {
    const removed = new Set(playerIDs);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as SocketAttachment | undefined ?? {};
      if (attachment.playerID && removed.has(attachment.playerID)) {
        socket.close(code, reason);
      }
    }
  }

  private activePlayerIDs(excluding?: WebSocket): string[] {
    const active = new Set<string>();
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === excluding || socket.readyState !== 1) continue;
      const attachment = socket.deserializeAttachment() as SocketAttachment | undefined ?? {};
      if (typeof attachment.playerID === "string") {
        active.add(attachment.playerID);
      }
    }
    return [...active];
  }

  private async reconcileHost(room: RoomState, excluding?: WebSocket): Promise<RoomState> {
    const updated = electLiveHost(room, this.activePlayerIDs(excluding));
    if (updated === room) {
      return room;
    }
    await this.commitRoom(updated);
    await this.broadcastPresence(updated);
    await this.fanOutToLibraries(updated);
    return updated;
  }
}

function libraryProgressSignature(room: RoomState): string {
  const summary = room.summary;
  return JSON.stringify({
    status: room.status,
    variant: summary?.variant,
    phase: summary?.phase,
    dealNumber: summary?.dealNumber,
    result: summary?.result
  });
}

/// Account identity, active sessions, and game index share one serialization
/// boundary per account. That makes room/library access impossible until the
/// presented bearer token has been checked against the same durable record.
export class PlayerAccountV2 {
  private readonly ctx: DurableObjectState;

  constructor(ctx: DurableObjectState, _env: Env) {
    this.ctx = ctx;
  }

  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "POST" && url.pathname === "/register") {
        const body = await readJSON<{
          accountID?: unknown;
          provider?: unknown;
          displayName?: unknown;
        }>(request);
        const accountID = String(body.accountID ?? "");
        const provider = body.provider === "apple" || body.provider === "guest"
          ? body.provider
          : undefined;
        if (!provider) {
          throw new AccountStateError("invalid_provider", "Unsupported account provider.");
        }
        const existing = await this.ctx.storage.get<PlayerAccountState>(ACCOUNT_STORAGE_KEY);
        if (existing && (existing.accountID !== accountID || existing.provider !== provider)) {
          throw new AccountStateError("account_conflict", "Account identity does not match this record.", 409);
        }
        const base = existing ?? createAccountState(accountID, provider, body.displayName);
        const refreshed: PlayerAccountState = {
          ...base,
          schemaVersion: ACCOUNT_SCHEMA_VERSION,
          displayName: normalizeDisplayName(body.displayName)
        };
        const issued = await issueSession(refreshed);
        await this.ctx.storage.put(ACCOUNT_STORAGE_KEY, issued.state);
        return json({ account: publicAccount(issued.state), sessionToken: issued.sessionToken }, 201);
      }

      if (request.method === "POST" && url.pathname === "/authenticate") {
        const body = await readJSON<{ sessionToken?: unknown }>(request);
        const state = await this.loadRequired();
        return json({ account: await authenticateSession(state, body.sessionToken) });
      }

      if (request.method === "POST" && url.pathname === "/upsert") {
        const entry = await readJSON<GameSummaryEntry>(request);
        const state = await this.loadRequired();
        await this.ctx.storage.put(ACCOUNT_STORAGE_KEY, {
          ...state,
          games: upsertGame(state, entry).games
        });
        return json({ ok: true });
      }

      if (request.method === "POST" && url.pathname === "/remove") {
        const body = await readJSON<{ roomCode?: unknown }>(request);
        const roomCode = String(body.roomCode ?? "").trim();
        const state = await this.loadRequired();
        const nextLibrary = removeGame(state, roomCode);
        if (nextLibrary.games !== state.games) {
          await this.ctx.storage.put(ACCOUNT_STORAGE_KEY, {
            ...state,
            games: nextLibrary.games
          });
        }
        return json({ ok: true });
      }

      if (request.method === "GET" && url.pathname === "/list") {
        return json({ games: listGames(await this.loadRequired()) });
      }

      if (request.method === "DELETE" && url.pathname === "/delete") {
        await this.loadRequired();
        await this.ctx.storage.deleteAll();
        return new Response(null, { status: 204 });
      }

      return json({ error: "Method not allowed." }, 405);
    } catch (error: unknown) {
      return errorResponse(error);
    }
  }

  private async loadRequired(): Promise<PlayerAccountState> {
    const state = await this.ctx.storage.get<PlayerAccountState>(ACCOUNT_STORAGE_KEY);
    if (!state || state.schemaVersion !== ACCOUNT_SCHEMA_VERSION) {
      throw new AccountStateError("account_not_found", "Register again to use online play.", 401);
    }
    return state;
  }
}

// Keep the historical exports present so Cloudflare's old migration records
// remain valid. New bindings use the v2 classes below and therefore receive
// completely fresh Durable Object namespaces.
export class PreferansRoom extends PreferansRoomV2 {}
export class PlayerLibrary extends PlayerAccountV2 {}
/// Fresh schema-v3 room namespace: no v2 client-host snapshots are imported.
export class PreferansRoomV3 extends PreferansRoomV2 {}

interface RegistrationResult {
  account: PublicAccount;
  sessionToken: string;
}

async function registerAccount(
  env: Env,
  accountID: string,
  provider: AccountProvider,
  displayName: string
): Promise<RegistrationResult> {
  const id = env.ACCOUNTS.idFromName(accountID);
  const response = await env.ACCOUNTS.get(id).fetch("https://account/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ accountID, provider, displayName })
  });
  const data = await response.json() as RegistrationResult & { code?: string; error?: string };
  if (!response.ok) {
    throw new AccountStateError(data.code ?? "account_error", data.error ?? "Account registration failed.", response.status);
  }
  return data;
}

async function authenticateAccount(request: Request, env: Env): Promise<PublicAccount> {
  const sessionToken = bearerToken(request);
  const parsed = parseSessionToken(sessionToken);
  const id = env.ACCOUNTS.idFromName(parsed.accountID);
  const response = await env.ACCOUNTS.get(id).fetch("https://account/authenticate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ sessionToken })
  });
  const data = await response.json() as { account?: PublicAccount; code?: string; error?: string };
  if (!response.ok || !data.account) {
    throw new AccountStateError(data.code ?? "unauthorized", data.error ?? "Register again to use online play.", 401);
  }
  return data.account;
}

async function deleteAuthenticatedAccount(request: Request, env: Env): Promise<Response> {
  const account = await authenticateAccount(request, env);
  const id = env.ACCOUNTS.idFromName(account.accountID);
  const accountStub = env.ACCOUNTS.get(id);
  const listResponse = await accountStub.fetch("https://account/list");
  const library = await listResponse.json() as { games?: Array<{ roomCode?: unknown }> };
  if (!listResponse.ok) {
    throw new AccountStateError("account_error", "Could not read the account game index.", listResponse.status);
  }

  for (const entry of library.games ?? []) {
    let roomCode: string;
    try {
      roomCode = normalizeRoomCode(entry.roomCode);
    } catch {
      continue;
    }
    const roomID = env.ROOMS.idFromName(roomCode);
    const response = await env.ROOMS.get(roomID).fetch("https://room/account-deleted", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ accountID: account.accountID })
    });
    // A stale library row must not make an otherwise valid account impossible
    // to delete. Current rooms, however, must be scrubbed successfully before
    // the account record and its sessions disappear.
    if (!response.ok && response.status !== 404 && response.status !== 410) {
      const data = await response.json() as { code?: string; error?: string };
      throw new RoomStateError(
        data.code ?? "room_cleanup_failed",
        data.error ?? "Could not remove the account from an active room.",
        response.status
      );
    }
  }

  const deleteResponse = await accountStub.fetch("https://account/delete", { method: "DELETE" });
  if (!deleteResponse.ok) {
    throw new AccountStateError("account_error", "Could not delete the account.", deleteResponse.status);
  }
  return new Response(null, { status: 204, headers: corsHeaders() });
}

function authenticatedPeer(account: PublicAccount, playerID: unknown): OnlinePeer {
  return normalizePeer({
    playerID,
    accountID: account.accountID,
    provider: account.provider,
    displayName: account.displayName
  });
}

function createRoomInput(roomCode: string, body: CreateRoomBody, account: PublicAccount): CreateRoomInput {
  if (!Array.isArray(body.seats) || (body.seats.length !== 3 && body.seats.length !== 4)) {
    throw new RoomStateError("invalid_seats", "A Preferans room must have 3 or 4 seats.");
  }
  const localID = playerIDValue(body.localPlayerID);
  const seen = new Set<string>();
  let hasLocalSeat = false;
  const seats = body.seats.map((value, index): OnlinePeer => {
    if (typeof value !== "object" || value === null || !("playerID" in value)) {
      throw new RoomStateError("invalid_seats", "Every room seat needs a player ID.");
    }
    const playerID = playerIDValue(value.playerID);
    if (seen.has(playerID)) {
      throw new RoomStateError("invalid_seats", "Room seat IDs must be unique.");
    }
    seen.add(playerID);
    if (playerID === localID) {
      hasLocalSeat = true;
      return authenticatedPeer(account, playerID);
    }
    const kind = "kind" in value ? value.kind : undefined;
    const isBot = kind === "bot";
    return normalizePeer({
      playerID,
      accountID: `${isBot ? BOT_ACCOUNT_PREFIX : PENDING_ACCOUNT_PREFIX}${playerID}`,
      provider: "dev",
      displayName: isBot ? `Bot ${index + 1}` : "Open seat"
    });
  });
  if (!hasLocalSeat) {
    throw new RoomStateError("invalid_seats", "The authenticated player must occupy one room seat.");
  }
  return {
    roomCode,
    localPeer: authenticatedPeer(account, localID),
    seats,
    maxPlayers: body.seats.length,
    rules: requiredEngineConfiguration(body.rules, "rules"),
    match: requiredEngineConfiguration(body.match, "match"),
    variant: typeof body.variant === "string" ? body.variant.slice(0, 32) : undefined
  };
}

function requiredEngineConfiguration(value: unknown, name: string): unknown {
  if (typeof value !== "object" || value === null) {
    throw new RoomStateError("invalid_engine_configuration", `Room ${name} are required.`);
  }
  return value;
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

/// The `/create` response: the public room plus the creator's seat token.
/// `/join` hands back the joiner's token the same way; broadcasts omit it.
function createResult(room: RoomState): RoomWithSecret {
  const hostSeat = room.peers.find((peer) => peerID(peer) === room.hostPlayerID);
  return { ...publicRoom(room), seatToken: hostSeat?.seatToken };
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
    websocketURL: `${protocol}//${url.host}/v2/rooms/${room.roomCode}/socket?playerID=${encodeURIComponent(playerID)}${token}`
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
  // size. The v3 client socket carries commands and redacted projections only.
  if (text.length > MAX_SOCKET_MESSAGE_BYTES) {
    throw new RoomStateError("message_too_large", "Socket message exceeds the size limit.", 413);
  }
  try {
    return JSON.parse(text) as ClientSocketEnvelope;
  } catch {
    throw new RoomStateError("invalid_socket_json", "Socket message must be JSON.");
  }
}

function isResyncRequest(message: unknown): boolean {
  return typeof message === "object"
    && message !== null
    && "resyncRequest" in message
    && typeof message.resyncRequest === "object"
    && message.resyncRequest !== null;
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
    "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
    "access-control-allow-headers": "authorization,content-type"
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
