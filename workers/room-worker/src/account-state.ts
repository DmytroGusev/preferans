import type { LibraryState } from "./library-state.ts";

export const ACCOUNT_SCHEMA_VERSION = 2;
export const SESSION_TOKEN_PREFIX = "pref2";
export const MAX_DISPLAY_NAME_LENGTH = 60;
export const MAX_ACTIVE_SESSIONS = 5;
export const SESSION_LIFETIME_MS = 180 * 24 * 60 * 60 * 1_000;

export type AccountProvider = "apple" | "guest";

export interface PublicAccount {
  schemaVersion: number;
  accountID: string;
  provider: AccountProvider;
  displayName: string;
}

export interface AccountSession {
  secretHash: string;
  createdAt: string;
  expiresAt: string;
}

export interface PlayerAccountState extends LibraryState {
  schemaVersion: number;
  accountID: string;
  provider: AccountProvider;
  displayName: string;
  sessions: AccountSession[];
}

export class AccountStateError extends Error {
  public readonly code: string;
  public readonly status: number;

  constructor(code: string, message: string, status = 400) {
    super(message);
    this.name = "AccountStateError";
    this.code = code;
    this.status = status;
  }
}

export function normalizeDisplayName(value: unknown): string {
  const displayName = String(value ?? "").trim().slice(0, MAX_DISPLAY_NAME_LENGTH);
  if (!displayName) {
    throw new AccountStateError("invalid_display_name", "A display name is required.");
  }
  return displayName;
}

export function createAccountState(
  accountID: string,
  provider: AccountProvider,
  displayName: unknown
): PlayerAccountState {
  if (!accountID || !accountID.includes(":")) {
    throw new AccountStateError("invalid_account", "A server account ID is required.");
  }
  return {
    schemaVersion: ACCOUNT_SCHEMA_VERSION,
    accountID,
    provider,
    displayName: normalizeDisplayName(displayName),
    sessions: [],
    games: {}
  };
}

export function publicAccount(state: PlayerAccountState): PublicAccount {
  return {
    schemaVersion: ACCOUNT_SCHEMA_VERSION,
    accountID: state.accountID,
    provider: state.provider,
    displayName: state.displayName
  };
}

export async function issueSession(
  state: PlayerAccountState,
  now = new Date(),
  secret = randomSecret()
): Promise<{ state: PlayerAccountState; sessionToken: string }> {
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + SESSION_LIFETIME_MS).toISOString();
  const active = state.sessions
    .filter((session) => Date.parse(session.expiresAt) > now.getTime())
    .slice(-(MAX_ACTIVE_SESSIONS - 1));
  const session: AccountSession = {
    secretHash: await sha256Hex(secret),
    createdAt,
    expiresAt
  };
  return {
    state: { ...state, sessions: [...active, session] },
    sessionToken: `${SESSION_TOKEN_PREFIX}.${base64URLEncode(state.accountID)}.${secret}`
  };
}

export interface ParsedSessionToken {
  accountID: string;
  secret: string;
}

export function parseSessionToken(value: unknown): ParsedSessionToken {
  if (typeof value !== "string") {
    throw unauthorized();
  }
  const parts = value.split(".");
  if (parts.length !== 3 || parts[0] !== SESSION_TOKEN_PREFIX || !parts[1] || !parts[2]) {
    throw unauthorized();
  }
  let accountID: string;
  try {
    accountID = base64URLDecode(parts[1]);
  } catch {
    throw unauthorized();
  }
  if (!accountID.includes(":") || parts[2].length < 32) {
    throw unauthorized();
  }
  return { accountID, secret: parts[2] };
}

export function bearerToken(request: Request): string {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw unauthorized();
  }
  return match[1];
}

export async function authenticateSession(
  state: PlayerAccountState,
  token: unknown,
  now = new Date()
): Promise<PublicAccount> {
  if (state.schemaVersion !== ACCOUNT_SCHEMA_VERSION) {
    throw new AccountStateError("account_upgrade_required", "Register again to use online play.", 401);
  }
  const parsed = parseSessionToken(token);
  if (parsed.accountID !== state.accountID) {
    throw unauthorized();
  }
  const hash = await sha256Hex(parsed.secret);
  const valid = state.sessions.some(
    (session) => Date.parse(session.expiresAt) > now.getTime() && constantTimeEqual(session.secretHash, hash)
  );
  if (!valid) {
    throw unauthorized();
  }
  return publicAccount(state);
}

export function guestAccountID(randomUUID: () => string = () => crypto.randomUUID()): string {
  return `guest:${randomUUID().toLowerCase()}`;
}

function randomSecret(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64URLFromBytes(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function base64URLEncode(value: string): string {
  return base64URLFromBytes(new TextEncoder().encode(value));
}

function base64URLFromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64URLDecode(value: string): string {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return new TextDecoder().decode(Uint8Array.from(binary, (character) => character.charCodeAt(0)));
}

function unauthorized(): AccountStateError {
  return new AccountStateError("unauthorized", "Register again to use online play.", 401);
}
