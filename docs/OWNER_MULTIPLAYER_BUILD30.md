# Owner multiplayer release: 1.0.3 (30)

1 November 2026. The owner authorized all of latest main, the new engine image
and an update of only the owner's Worker. No reset or migration was performed.

## Source And Scope

- Baseline: `c4621082a8a36c3cffdbf58d1f7a01faff64cefa` (main, PR #7).
- PR #6 (`0bfe2d5`, Vitaly Kushnir) fixes next-deal progress with an offline
  manager, foreground reconnect, terminal seat errors and unacknowledged moves.
- PR #7 (`672bd41`, Vitaly Kushnir) records authoritative match balances in
  player history, masks other players' account identifiers and cleans ended rooms.
- Release preparation by Codex at the owner's request: build number 30, the
  standard-encryption declaration, pinned owner engine image and QA evidence.
- Functional app sources match main apart from the version and encryption plist.
  `AppStore/Release30/source-manifest.json` records the archived source hashes.
- Uncommitted Club/Firebase drafts in `PreferansRelease20261015` remain untouched
  and are not included. This release does not add Firebase or subscriptions.

## Deployment And Data

Owner endpoint: <https://preferans-room-worker.dmytro-gusev.workers.dev>.
Worker version: `057ca688-8fb1-4f89-a057-4eea2ce36091`.
Container app: `a032d1ae-1fb4-4259-b62b-4cfa10bead7a`.

Engine image:
`registry.cloudflare.com/df302a84563143eb92fc75a7277079ec/preferans-engine@sha256:90d5da73d8fc8cd677e3e4047174b46c03cfd8539005d685a8274c16b1e456dc`.

Built from the exact baseline by successful CI run
<https://github.com/DmytroGusev/preferans/actions/runs/41339653980>.
The verified image was published with temporary registry credentials; credentials
are not stored in release evidence. All three live instances report version 2.

Existing namespaces and account/active-game state are retained. Cleanup removes
private checkpoints of ended games and purges finished/abandoned tables after
30 days, after their outboxes drain. It does not delete accounts or unfinished
games. This approved cleanup is not a transfer of data from the friend's server.

The friend's `ontofractal.workers.dev` service was read only, never deployed.

## Verification

- CI Linux engine build, Worker checks and engine smoke test passed.
- Portable engine suite passed; Worker typecheck, 54 unit tests and 18 runtime
  tests passed.
- Full Swift tests passed on rerun. The initial run hit the existing
  `testHostActionQueueCancellationDropsQueuedMutations` scheduling-sensitive
  assertion; isolated rerun and full rerun passed without changing the test.
  Three live-backend Swift integration tests were skipped as designed.
- Native iOS public-host and public-join/Ready/first-deal tests both passed on
  the dedicated simulator, using the real owner backend and disposable accounts.
- Live public-directory create/discover/join/leave/Ready/first-deal regressions
  also passed independently for three and four players after deployment.
- Enhanced live complete matches passed with three and four players, including
  offline-manager next-deal progress, reconnect, pending-command replay, private
  projections, 30 first-deal card plays and matching history balances for everyone.
  The first four-seat post-deployment attempt did not receive history results
  within its three-second poll; the unchanged rerun passed both seat counts.
  Container rollout was still provisioning during the initial attempt; this is
  a possible explanation, not a demonstrated root cause. Do not erase this caveat.
- Signed Release archive/export passed with Xcode 27.1 (`27A9275`). IPA signature,
  build 30, owner URL, invite scheme and entitlements were verified before upload.
- Apple upload completed at 19:11:32 UTC; processing reached `VALID`.
  Build ID: `eef9c00f-9198-43a7-a3a6-4ed12d3ed52a`.

Physical-device Sign in with Apple and two-phone invitation/reconnect checks still
need owner testing. Automated network checks do not prove every gameplay scenario.

## Delivery And Rollback

TestFlight only: no external beta review, App Review submission, new screenshots,
keyword edits or public release. The draft 1.0.3 stays on build 29 and published
1.0.2 stays on build 28. `store-after.json` verifies protected metadata unchanged.

Both existing internal TestFlight groups are linked, but have zero testers.
Build state is `READY_FOR_BETA_TESTING`; an Apple ID email/group membership is
still needed for an actual invitation. Do not describe this as delivered access.

For client rollback, select build 29 in TestFlight; it uses the same owner backend.
For a server regression, redeploy the prior owner configuration/image using the
same namespaces, never the friend's config and never a database reset:

- Previous Worker: `d0199534-c9c0-4942-a340-d05e76062d93`.
- Previous engine digest:
  `sha256:2aef1184f568365af0d18f0054193590cbf44ef389a128a964add72ba9b091bf`.
- Previous pinned config is in main `c462108` at
  `workers/room-worker/wrangler.owner.toml`.

A code rollback does not restore checkpoints already removed by retention.
No rollback was executed. Release evidence and reproducible package checks are
under `AppStore/Release30/`; generated archives and credentials are excluded.
