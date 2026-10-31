# Owner multiplayer release: 1.0.3 (29)

31 October 2026. The owner approved a separate new server and client build;
the friend's server must remain untouched. This is not a data migration.

## Root Cause

The production build 28 requires wire/room protocol 4. The configured friend's
server returned room protocol 3 from `/health`, and `/v2/public-tables` returned
404. Successful account registration did not imply compatible room creation.
No new Preferans client had been uploaded after build 28; Durak build 12 is a
different app.

## New Infrastructure

- Account: `df302a84563143eb92fc75a7277079ec`, the owner's Cloudflare account.
- URL: <https://preferans-room-worker.dmytro-gusev.workers.dev>.
- Worker version: `d0199534-c9c0-4942-a340-d05e76062d93`.
- Container application: `a032d1ae-1fb4-4259-b62b-4cfa10bead7a`.
- Immutable engine image:
  `registry.cloudflare.com/df302a84563143eb92fc75a7277079ec/preferans-engine@sha256:2aef1184f568365af0d18f0054193590cbf44ef389a128a964add72ba9b091bf`.
- Engine source: `89e90e4ac00607ccce9673271bf1779088846fcc`; successful CI run
  <https://github.com/DmytroGusev/preferans/actions/runs/39782536569>.
- Separate persistent SQLite Durable Objects: accounts, tables, public directory
  and engine container. The config pins the owner account, image digest and a
  maximum of three container instances. This does not establish a spending cap.
- No D1 import, old-account copy or old-endpoint proxy was performed.

Do not deploy `wrangler.toml` to the friend's account. Owner deployments use
`wrangler.owner.toml` explicitly. New deployments must retain these namespaces
and migrations; do not delete/recreate state to update the Worker.

## Client Changes

The clean source baseline is current GitHub main `89e90e4`. The 65 local draft
files in `PreferansRelease20261015` were preserved and not bundled into this
release. In particular, Firebase and Club/quota drafts are not shipped here.

The client selects the new endpoint, uses `.owner-v1` for account/seat storage
without erasing legacy storage, validates server compatibility before create/join,
shows creation progress and inline errors, defaults to public creation after
successful discovery, handles Universal Links and a bundle-specific URL scheme,
and opens online mode when receiving an invite. Old/foreign-server invite URLs
are rejected rather than resolving their code against the wrong database.

Public tables retain the existing authoritative Swift engine, authenticated
seats, private projections, durable command receipts, lobby discovery and Ready
gate. Durak's Game Center match transport was not substituted for Preferans's
authoritative game state.

Legal links in Settings use the verified Guru of Cards Preferans pages. The
invitation landing page includes an Open Preferans fallback, code instructions
and the required minimum app version.

## Verification

- Worker type checking; 52 unit tests and 14 real-workerd tests passed.
- 42 focused Swift tests passed, including incompatible-server rejection before
  mutations, invite parsing and public-create setup.
- Public-network tests passed for three and four humans: creation, discovery,
  join, leave/rejoin, authorization, Ready and first deal, with QA account cleanup.
- Complete independent-client matches passed for three and four seats, with
  private-hand assertions, 30 played cards in the first deal, pending-command
  replay, manager recovery, consistent terminal scores and account cleanup.
  Elapsed times: 11.6s and 10.8s.
- The live-network match harness now reads the actual elected manager rather
  than assuming north wins a simultaneous connection race.
- Native public-join UI test passed: find a table, take a seat, Ready, first
  auction with ten private cards, leave and delete the QA account.
- Native public-host test created a discoverable table. Its first run failed
  only in cleanup because the test expected the active-game leave message for
  a pre-deal public waiting table. The expectation was corrected to seat release;
  the rerun result is recorded separately below.
- The final public-host UI rerun passed, including seat release and QA-account
  deletion. Discovery is awaited with a bounded 3-second condition poll because
  room publication is a durable asynchronous outbox, not part of the create reply.
- iOS simulator build and Release device archive passed using Xcode 27.1
  (27A9275). Package verification/upload results are recorded under
  `AppStore/Release29/`.

These checks do not replace testing Sign in with Apple and invitations on two
physical devices. Apple may cache AASA records; manual room codes and the
bundle-specific scheme are available as fallbacks.

## Delivery And Rollback

The TestFlight upload does not replace published 1.0.2 (28), change its metadata,
or submit a new App Review. All test participants need the new build and must
register on the new server. Do not claim old rooms or subscriptions migrated.

Roll back the client using the previous TestFlight build if needed; it still
connects to the old backend. For a new-owner Worker regression, retain the new
account data and roll back the Worker version with a compatible protocol-4
engine. Never erase namespaces as a rollback step.
