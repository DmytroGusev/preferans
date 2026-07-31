import { AccountStateError, sha256Hex } from "./account-state.ts";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const KEY_CACHE_MS = 6 * 60 * 60 * 1_000;

interface AppleJWTHeader {
  alg?: unknown;
  kid?: unknown;
}

export interface AppleIdentityClaims {
  iss?: unknown;
  aud?: unknown;
  exp?: unknown;
  sub?: unknown;
  nonce?: unknown;
}

type AppleJWK = { kid?: string; kty?: string; [key: string]: unknown };

interface JWKImporter {
  importKey(
    format: "jwk",
    keyData: AppleJWK,
    algorithm: { name: string; hash: string },
    extractable: boolean,
    keyUsages: string[]
  ): Promise<CryptoKey>;
}

interface AppleKeySet {
  keys?: AppleJWK[];
}

let cachedKeys: { expiresAt: number; keys: AppleJWK[] } | undefined;

export async function verifyAppleIdentityToken(
  identityToken: unknown,
  rawNonce: unknown,
  audience: string,
  fetcher: typeof fetch = fetch,
  now = new Date()
): Promise<{ subject: string }> {
  if (typeof identityToken !== "string" || typeof rawNonce !== "string" || !rawNonce) {
    throw invalidAppleToken();
  }
  const parts = identityToken.split(".");
  if (parts.length !== 3) throw invalidAppleToken();

  const header = decodeJSON<AppleJWTHeader>(parts[0]);
  const claims = decodeJSON<AppleIdentityClaims>(parts[1]);
  if (header.alg !== "RS256" || typeof header.kid !== "string") throw invalidAppleToken();

  const keys = await appleKeys(fetcher, now);
  const key = keys.find((candidate) => candidate.kid === header.kid && candidate.kty === "RSA");
  if (!key) throw invalidAppleToken();
  const cryptoKey = await (crypto.subtle as unknown as JWKImporter).importKey(
    "jwk",
    key,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const signature = decodeBase64URL(parts[2]);
  const signatureBuffer = signature.buffer.slice(
    signature.byteOffset,
    signature.byteOffset + signature.byteLength
  ) as ArrayBuffer;
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    signatureBuffer,
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!verified) throw invalidAppleToken();

  await validateAppleClaims(claims, rawNonce, audience, now);
  return { subject: String(claims.sub) };
}

export async function validateAppleClaims(
  claims: AppleIdentityClaims,
  rawNonce: string,
  audience: string,
  now = new Date()
): Promise<void> {
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  const expiresAtSeconds = Number(claims.exp);
  const expectedNonce = await sha256Hex(rawNonce);
  if (
    claims.iss !== APPLE_ISSUER ||
    !audiences.includes(audience) ||
    !Number.isFinite(expiresAtSeconds) ||
    expiresAtSeconds * 1_000 <= now.getTime() ||
    typeof claims.sub !== "string" ||
    !claims.sub ||
    claims.nonce !== expectedNonce
  ) {
    throw invalidAppleToken();
  }
}

async function appleKeys(fetcher: typeof fetch, now: Date): Promise<AppleJWK[]> {
  if (cachedKeys && cachedKeys.expiresAt > now.getTime()) return cachedKeys.keys;
  const response = await fetcher(APPLE_KEYS_URL, { headers: { accept: "application/json" } });
  if (!response.ok) {
    throw new AccountStateError("apple_unavailable", "Apple sign-in could not be verified. Try again.", 503);
  }
  const keySet = await response.json() as AppleKeySet;
  const keys = Array.isArray(keySet.keys) ? keySet.keys : [];
  if (keys.length === 0) throw invalidAppleToken();
  cachedKeys = { expiresAt: now.getTime() + KEY_CACHE_MS, keys };
  return keys;
}

function decodeJSON<T>(value: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBase64URL(value))) as T;
  } catch {
    throw invalidAppleToken();
  }
}

function decodeBase64URL(value: string): Uint8Array {
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw invalidAppleToken();
  }
}

function invalidAppleToken(): AccountStateError {
  return new AccountStateError("invalid_apple_identity", "Apple sign-in could not be verified. Try again.", 401);
}
