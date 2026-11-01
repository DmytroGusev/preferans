# Contract: Room Codes, Invite Links and Universal Links

**Implementation**: `Preferans/Online/PreferansInviteLink.swift`, `Preferans/Support/AppIdentifiers.swift` (`roomWorkerBaseURL`, `inviteBaseURL`), `Preferans/UI/LobbyView.swift` (`onOpenURL`, `onContinueUserActivity`), `Preferans/UI/LobbyViewModel.swift` (`handleInviteURL`, `pendingJoinRoomCode`), `Preferans/Info.plist` (`CFBundleURLTypes`), `Preferans/Preferans.entitlements`, `workers/room-worker/src/index.ts` (`appleAppSiteAssociation`, `invitePage`, `normalizeRoomCode`), `workers/room-worker/src/room-state.ts` (`generateRoomCode`), `AppStore/UniversalLinks/`.

## Room code

| Property | Value |
| --- | --- |
| Generated length | 6 |
| Alphabet | `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (32 symbols; no `I`, `O`, `0`, `1`) — ~1.07 × 10⁹ codes |
| Randomness | `crypto.getRandomValues` (CSPRNG) |
| Accepted input (server) | any string → trim, uppercase, strip non-`[A-Z0-9]`, length 4–12, else 400 `invalid_room_code` |
| Accepted input (client) | `^[A-Za-z0-9-]+$` → uppercase, keep letters/digits, length 4–12 (`normalizedRoomCode`) |
| Uniqueness | Durable Object per code; create retries ≤ 5 on collision |
| Secrecy | The code alone lets anyone read the room summary (`GET /v2/rooms/{code}`) and, while a seat is open in the lobby, claim it after registering. It never grants an occupied seat (seat tokens) |

## Invite URL formats

| Form | Example | Produced by | Accepted by `roomCode(from:)` |
| --- | --- | --- | --- |
| Web / Universal Link | `https://<worker-host>/join/K7M2Q9` | `PreferansInviteLink.inviteURL` (`inviteBaseURL = roomWorkerBaseURL`) | yes, iff scheme `https` and host == `AppIdentifiers.inviteBaseURL.host` |
| App scheme | `com.mixandmatch.preferans://table/join/K7M2Q9` | Worker landing page "Open Preferans" link | yes, iff host `table` |
| Pasted path | `join/k7-m2`, `/join/k7-m2`, `<worker-host>/join/k7-m2` | user | yes |
| Bare code | `k7m2q9` | user | yes |

URL rules: no user, password or fragment; exactly two path components with the first `join` (case-insensitive); query strings are ignored (`…/join/k7-m2?q=1` → `K7M2`). Rejected: other hosts (older `workers.dev` backends, lookalikes), extra path segments, embedded credentials, invalid characters (`AB!CD`). Tests: `PreferansInviteLinkTests` (`testParsesUniversalInviteURL`, `testParsesPastedInviteURLText`, `testParsesPastedInvitePathText`, `testRejectsNonInviteURL`, `testParsesAppLinkAndRejectsOldBackendOrLookalikeLinks`).

## App handling

1. `LobbyView.onOpenURL` (custom scheme) and `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` (Universal Link) call `LobbyViewModel.handleInviteURL(url)`.
2. If a code is extracted: `lobbyMode = .online`, `onlineJoinRoomCode = code`, clear errors, info "Invite \(code) is ready — tap Join to take a seat." The app does **not** auto-join; the user taps Join (which still requires a registered account and runs the server compatibility check).
3. Unrecognized URLs are ignored silently.

URL scheme registration (`Info.plist`): `CFBundleURLName = com.mixandmatch.preferans.invites`, `CFBundleURLSchemes = [com.mixandmatch.preferans]`.

Associated domains (`Preferans/Preferans.entitlements`): `applinks:preferans.game`, an older `preferans-room-worker.*.workers.dev` host, and the current owner `preferans-room-worker.*.workers.dev` host. Only the host equal to `inviteBaseURL` yields a code (see spec gap 13).

## Apple App Site Association

Served by the Worker (`GET /.well-known/apple-app-site-association` and `/apple-app-site-association`, `application/json`) and checked in at `AppStore/UniversalLinks/apple-app-site-association`:

```json
{"applinks":{"details":[{"appIDs":["<TEAMID>.com.mixandmatch.preferans"],
  "components":[{"/":"/join/*","comment":"Preferans room invite links"}]}]}}
```

`AppStore/UniversalLinks/README.md` requirements: serve as `application/json`, no `.json` extension, keep the Team-ID-prefixed app ID, keep the applinks entitlements enabled. (It documents `preferans.game` and the older beta host, not the current owner host.)

## Landing page (`GET /join/<code>`)

HTML (`text/html; charset=utf-8`) with:

- `<meta name="apple-itunes-app" content="app-id=…">` (Smart App Banner), `<meta name="robots" content="noindex,nofollow">`, `<meta name="referrer" content="no-referrer">`;
- title "Join Preferans Table CODE", the HTML-escaped normalized code;
- link "Open Preferans" → `com.mixandmatch.preferans://table/join/CODE`;
- instructions: "Open Play online, sign in or continue as a guest, then paste this code in Join a table. You need version 1.0.3 or newer to join this server.";
- App Store link.

The page does not look up the room; any syntactically valid code renders.

## Seat assignment on join (summary)

The join request carries only `requestedPlayerID` (the joiner's preferred seat, by default the composition's "you" slot). The server binds by account: an existing seat for that account is reused (token rotated); otherwise the requested seat if still open, else the first open seat; otherwise `room_full`. The app adopts whatever seat the server returns.
