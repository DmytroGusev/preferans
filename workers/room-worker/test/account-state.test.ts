import test from "node:test";
import assert from "node:assert/strict";
import {
  ACCOUNT_SCHEMA_VERSION,
  authenticateSession,
  createAccountState,
  guestAccountID,
  issueSession,
  normalizeDisplayName,
  parseSessionToken
} from "../src/account-state.ts";
import { validateAppleClaims } from "../src/apple-auth.ts";

const now = new Date("2026-07-31T12:00:00.000Z");

test("server-issued guest identity and bearer session round-trip", async () => {
  const accountID = guestAccountID(() => "00000000-0000-4000-8000-000000000001");
  const initial = createAccountState(accountID, "guest", "  Ann  ");
  const issued = await issueSession(initial, now, "s".repeat(43));
  const parsed = parseSessionToken(issued.sessionToken);
  const authenticated = await authenticateSession(issued.state, issued.sessionToken, now);

  assert.equal(accountID, "guest:00000000-0000-4000-8000-000000000001");
  assert.equal(parsed.accountID, accountID);
  assert.equal(authenticated.schemaVersion, ACCOUNT_SCHEMA_VERSION);
  assert.equal(authenticated.displayName, "Ann");
  assert.equal(issued.state.sessions.length, 1);
  assert.notEqual(issued.state.sessions[0].secretHash, parsed.secret);
});

test("forged, cross-account, and expired sessions are rejected", async () => {
  const first = createAccountState("guest:first", "guest", "First");
  const issued = await issueSession(first, now, "a".repeat(43));
  await assert.rejects(
    authenticateSession(issued.state, issued.sessionToken.slice(0, -1) + "b", now),
    /Register again/
  );

  const second = { ...issued.state, accountID: "guest:second" };
  await assert.rejects(authenticateSession(second, issued.sessionToken, now), /Register again/);
  await assert.rejects(
    authenticateSession(issued.state, issued.sessionToken, new Date("2027-02-01T00:00:00.000Z")),
    /Register again/
  );
});

test("display names are required and bounded", () => {
  assert.throws(() => normalizeDisplayName("   "), /required/);
  assert.equal(normalizeDisplayName("x".repeat(100)).length, 60);
});

test("Apple claims require issuer, audience, expiry, subject, and hashed nonce", async () => {
  const rawNonce = "nonce-value";
  const expectedNonce = "efb4e26c3deb3dd5e04408769d1b6b371ae1e7acbe1e32332550b06f784780f2";
  const valid = {
    iss: "https://appleid.apple.com",
    aud: "com.mixandmatch.preferans",
    exp: now.getTime() / 1_000 + 300,
    sub: "apple-subject",
    nonce: expectedNonce
  };

  await validateAppleClaims(valid, rawNonce, "com.mixandmatch.preferans", now);
  await assert.rejects(
    validateAppleClaims({ ...valid, aud: "forged.app" }, rawNonce, "com.mixandmatch.preferans", now),
    /could not be verified/
  );
  await assert.rejects(
    validateAppleClaims({ ...valid, exp: now.getTime() / 1_000 - 1 }, rawNonce, "com.mixandmatch.preferans", now),
    /could not be verified/
  );
  await assert.rejects(
    validateAppleClaims({ ...valid, nonce: "wrong" }, rawNonce, "com.mixandmatch.preferans", now),
    /could not be verified/
  );
});
