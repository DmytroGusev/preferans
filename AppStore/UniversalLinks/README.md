# Universal Links

Host `apple-app-site-association` at:

```text
https://preferans.game/.well-known/apple-app-site-association
```

The beta Worker also serves the same file at:

```text
https://preferans-room-worker.ontofractal.workers.dev/.well-known/apple-app-site-association
```

Requirements:

- Serve with `Content-Type: application/json`.
- Do not add a `.json` file extension.
- Keep the app ID as `3WSQ6X9CDT.com.mixandmatch.preferans`.
- Keep `applinks:preferans.game` enabled in Apple Developer and Xcode.
- Keep `applinks:preferans-room-worker.ontofractal.workers.dev` enabled for public beta invites until the production domain is live.

Invite links use:

```text
https://preferans.game/join/{ROOM_CODE}
```

Public beta invite links may use:

```text
https://preferans-room-worker.ontofractal.workers.dev/join/{ROOM_CODE}
```
