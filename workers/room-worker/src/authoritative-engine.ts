import {
  BOT_ACCOUNT_PREFIX,
  PENDING_ACCOUNT_PREFIX,
  type OnlinePeer,
  type RoomState,
  RoomStateError,
  peerID
} from "./room-state.ts";

export interface AuthoritativeProjectionEnvelope {
  tableID: string;
  sequence: number;
  viewer: { rawValue: string };
  projection: unknown;
  [key: string]: unknown;
}

export const ENGINE_VERSION = "preferans-1";

export interface AuthoritativeGameResponse {
  engineVersion: string;
  botPending: boolean;
  state: string;
  sequence: number;
  projections: AuthoritativeProjectionEnvelope[];
  status: "lobby" | "playing" | "finished";
  dealNumber: number;
  phase: string;
}

export interface EngineCommandEnvelope {
  schemaVersion?: unknown;
  tableID?: unknown;
  actor?: unknown;
  action?: unknown;
  clientNonce?: unknown;
  baseHostSequence?: unknown;
}

export interface AuthoritativeEngineBinding {
  fetch(path: string, body: unknown): Promise<Response>;
}

export async function createAuthoritativeGame(
  room: RoomState,
  engine: AuthoritativeEngineBinding
): Promise<RoomState> {
  const configuration = room.engineConfiguration;
  if (configuration?.rules === undefined || configuration.match === undefined) {
    throw new RoomStateError(
      "engine_configuration_missing",
      "This room does not contain a server engine configuration.",
      409
    );
  }
  const response = await callEngine(engine, "/v1/games", {
    tableID: room.authoritativeTableID ?? null,
    identities: room.peers.map(playerIdentity),
    rules: configuration.rules,
    match: configuration.match,
    firstDealer: room.peers[0]?.playerID ?? null,
    botProfiles: botProfiles(room.peers)
  });
  return adoptingEngineResponse(room, response);
}

export async function applyAuthoritativeCommand(
  room: RoomState,
  sender: OnlinePeer,
  envelope: EngineCommandEnvelope,
  engine: AuthoritativeEngineBinding
): Promise<RoomState> {
  if (room.engineVersion !== ENGINE_VERSION) {
    throw new RoomStateError("engine_version_mismatch", "The saved table requires another engine version.", 503);
  }
  if (!room.authoritativeState) {
    throw new RoomStateError("engine_state_missing", "The server game has not been initialized.", 409);
  }
  if (envelope.schemaVersion !== room.schemaVersion || envelope.tableID !== room.authoritativeTableID) {
    throw new RoomStateError("protocol_mismatch", "Update the app or reopen this table.", 409);
  }
  const actor = playerIDValue(envelope.actor);
  const nonce = String(envelope.clientNonce ?? "").trim();
  const baseSequence = numberValue(envelope.baseHostSequence, "baseHostSequence");
  if (!nonce) {
    throw new RoomStateError("invalid_command", "Client command nonce is required.");
  }
  if (envelope.action === undefined) {
    throw new RoomStateError("invalid_command", "Client command action is required.");
  }
  const response = await callEngine(engine, "/v1/commands", {
    state: room.authoritativeState,
    sender: sender.playerID,
    actor: { rawValue: actor },
    action: envelope.action,
    clientNonce: nonce,
    baseSequence
  });
  return adoptingEngineResponse(room, response);
}

export function adoptingEngineResponse(
  room: RoomState,
  response: AuthoritativeGameResponse,
  now = new Date().toISOString()
): RoomState {
  if (response.engineVersion !== ENGINE_VERSION) {
    throw new RoomStateError("engine_version_mismatch", "The table engine version is unavailable.", 503);
  }
  if (typeof response.botPending !== "boolean" || !["lobby", "playing", "finished"].includes(response.status)) {
    throw new RoomStateError("engine_invalid_response", "Invalid engine status.", 502);
  }
  if (typeof response.state !== "string" || !response.state) {
    throw new RoomStateError("engine_invalid_response", "Engine response omitted private state.", 502);
  }
  if (!Number.isSafeInteger(response.sequence) || response.sequence < 0) {
    throw new RoomStateError("engine_invalid_response", "Engine returned an invalid sequence.", 502);
  }
  const projections: Record<string, unknown> = {};
  let tableID: string | undefined;
  for (const envelope of response.projections ?? []) {
    const viewer = playerIDValue(envelope.viewer);
    if (!room.peers.some((peer) => peerID(peer) === viewer)) {
      throw new RoomStateError("engine_invalid_response", "Engine projected an unknown seat.", 502);
    }
    if (envelope.sequence !== response.sequence || typeof envelope.tableID !== "string") {
      throw new RoomStateError("engine_invalid_response", "Engine projection metadata is inconsistent.", 502);
    }
    tableID = tableID ?? envelope.tableID;
    if (tableID !== envelope.tableID) {
      throw new RoomStateError("engine_invalid_response", "Engine returned multiple table identities.", 502);
    }
    if (projections[viewer] !== undefined) {
      throw new RoomStateError("engine_invalid_response", "Duplicate projection seat.", 502);
    }
    projections[viewer] = envelope;
  }
  if (Object.keys(projections).length !== room.peers.length || !tableID) {
    throw new RoomStateError("engine_invalid_response", "Engine did not return one projection per seat.", 502);
  }
  if (room.authoritativeTableID && tableID !== room.authoritativeTableID) {
    throw new RoomStateError("engine_invalid_response", "Engine changed the table identity.", 502);
  }
  if (room.status !== "lobby" && response.sequence < (room.authoritativeSequence ?? 0)) {
    throw new RoomStateError("engine_invalid_response", "Engine revision moved backwards.", 502);
  }
  const status = response.status;
  const phase = typeof response.phase === "string" ? response.phase : undefined;
  return {
    ...room,
    engineVersion: response.engineVersion,
    botPending: response.botPending,
    authoritativeState: status === "finished" ? undefined : response.state,
    authoritativeSequence: response.sequence,
    authoritativeTableID: tableID,
    authoritativeProjections: projections,
    status,
    summary: {
      ...room.summary,
      variant: room.engineConfiguration?.variant,
      lastSequence: response.sequence,
      phase,
      dealNumber: response.dealNumber
    },
    updatedAt: now
  };
}

export function clientActionFromWireMessage(message: unknown): EngineCommandEnvelope | undefined {
  if (!isRecord(message) || !isRecord(message.clientAction)) return undefined;
  const payload = message.clientAction._0;
  return isRecord(payload) ? payload : undefined;
}

export function isStartDealCommand(envelope: EngineCommandEnvelope): boolean {
  return isRecord(envelope.action)
    && isRecord(envelope.action.startDeal);
}

export function validateStartDealAuthority(
  room: RoomState,
  sender: OnlinePeer,
  connectedPlayerIDs: ReadonlySet<string>
): void {
  if (peerID(sender) !== room.hostPlayerID) {
    throw new RoomStateError(
      "lobby_manager_required",
      "Only the current lobby manager can start a deal.",
      403
    );
  }
  if (room.peers.some((peer) => peer.accountID.startsWith(PENDING_ACCOUNT_PREFIX))) {
    throw new RoomStateError(
      "room_not_ready",
      "Every seat must be claimed or filled by a bot before dealing.",
      409
    );
  }
  if (room.peers.some((peer) =>
    !peer.accountID.startsWith(BOT_ACCOUNT_PREFIX)
      && !connectedPlayerIDs.has(peerID(peer)))) {
    throw new RoomStateError(
      "room_not_ready",
      "Every human seat must be connected before dealing.",
      409
    );
  }
}

export function projectionWireMessage(projection: unknown): Record<string, unknown> {
  return { projection: { _0: projection } };
}

function playerIdentity(peer: OnlinePeer): Record<string, unknown> {
  return {
    playerID: peer.playerID,
    gamePlayerID: peer.accountID,
    displayName: peer.displayName
  };
}

function botProfiles(peers: OnlinePeer[]): unknown[] {
  const encoded: unknown[] = [];
  for (const peer of peers) {
    if (!peer.accountID.startsWith(BOT_ACCOUNT_PREFIX)) continue;
    encoded.push(peer.playerID, { difficulty: "seasoned", temperament: "adaptive" });
  }
  return encoded;
}

export async function callEngine(
  engine: AuthoritativeEngineBinding,
  path: string,
  body: unknown
): Promise<AuthoritativeGameResponse> {
  let response: Response;
  try {
    response = await engine.fetch(path, body);
  } catch {
    throw new RoomStateError("engine_unavailable", "The authoritative game engine is unavailable.", 503);
  }
  const data = await response.json().catch(() => undefined) as
    | (Partial<AuthoritativeGameResponse> & { message?: string; error?: string })
    | undefined;
  if (!response.ok || !data) {
    throw new RoomStateError(
      "engine_rejected_command",
      engineErrorMessage(data),
      response.status >= 400 && response.status < 500 ? 409 : 502
    );
  }
  return data as AuthoritativeGameResponse;
}

function playerIDValue(value: unknown): string {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (isRecord(value) && typeof value.rawValue === "string" && value.rawValue.trim()) {
    return value.rawValue.trim();
  }
  throw new RoomStateError("invalid_command", "Command actor is required.");
}

function numberValue(value: unknown, name: string): number {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return value;
  throw new RoomStateError("invalid_command", `${name} must be a non-negative integer.`);
}

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function engineErrorMessage(data: unknown): string {
  if (isRecord(data)) {
    if (typeof data.message === "string") return data.message;
    if (typeof data.error === "string") return data.error;
    if (isRecord(data.error) && typeof data.error.message === "string") return data.error.message;
  }
  return "The authoritative engine rejected the command.";
}
