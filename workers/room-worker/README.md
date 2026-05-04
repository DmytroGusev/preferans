# Preferans Room Worker

Cloudflare Worker + Durable Object backend for Preferans room invites and realtime relay.

This first version is intentionally transport-focused: it creates rooms, lets peers join, accepts WebSocket connections, tracks presence, and relays opaque `GameWireMessage` JSON between peers. The existing Swift host actor still owns game validation. That makes it useful for beta multiplayer and end-to-end transport work, while leaving the later server-authoritative engine move explicit.

## Run Locally

```sh
cd workers/room-worker
wrangler dev --local --port 8787
```

Health check:

```sh
curl http://127.0.0.1:8787/health
```

Create a room:

```sh
curl -s http://127.0.0.1:8787/rooms \
  -H 'content-type: application/json' \
  -d '{"localPeer":{"playerID":{"rawValue":"north"},"accountID":"email:north@example.test","provider":"email","displayName":"North"},"seats":[{"playerID":{"rawValue":"north"},"accountID":"email:north@example.test","provider":"email","displayName":"North"},{"playerID":{"rawValue":"east"},"accountID":"dev:east","provider":"dev","displayName":"East"},{"playerID":{"rawValue":"south"},"accountID":"dev:south","provider":"dev","displayName":"South"}]}'
```

Join a room:

```sh
curl -s http://127.0.0.1:8787/rooms/ABC123/join \
  -H 'content-type: application/json' \
  -d '{"localPeer":{"playerID":{"rawValue":"east"},"accountID":"email:east@example.test","provider":"email","displayName":"East"}}'
```

WebSocket client messages:

```json
{
  "type": "wire",
  "recipients": [{ "rawValue": "east" }],
  "reliable": true,
  "message": { "ping": { "schemaVersion": 1, "tableID": null, "sentAt": "2026-05-04T00:00:00Z" } }
}
```

Server WebSocket messages:

```json
{
  "type": "wire",
  "sender": {
    "playerID": { "rawValue": "north" },
    "accountID": "email:north@example.test",
    "provider": "email",
    "displayName": "North"
  },
  "message": {}
}
```

## Launch Boundary

This worker is the correct room/transport foundation, but it is not yet a public-launch authoritative game server. For public multiplayer, move Preferans validation/projection generation into the Durable Object, either by porting the engine to TypeScript or compiling a shared core to WASM.
