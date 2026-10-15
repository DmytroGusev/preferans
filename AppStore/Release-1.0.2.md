# Preferans 1.0.2 (28)

Prepared on 2026-10-15. Distribution target: internal TestFlight, not App Review.

## Uploaded build

- App: `6763581975`, bundle `com.mixandmatch.preferans`.
- Build: `eca4773c-36c9-4ef4-936f-dd7b353fb08e`, processing state `VALID`.
- Draft version: `98378d13-7f10-4728-85bc-a501b9698373`, manual release.
- Existing internal groups Testers and Pediki have access to all builds; build 28
  was verified in the Testers group's build list. No new testers were invited.
- External testing still requires Apple's beta review. No beta review or App
  Review submission was created in this release session.
- Source baseline: `f7dbbaf` (public-lobby PR), based on `b2c1d76` (misere fix).
- The signed iOS archive includes the legacy-server fallback described below.
- Rollback baseline remains published version 1.0.1 (27); it was not changed.

## Production blocker

The configured backend is still
`https://preferans-room-worker.ontofractal.workers.dev`. There is no available
Cloudflare authorization for that account and Docker is not installed. No Worker,
Durable Object migration or engine container was deployed.

Public tables must NOT be advertised as production-ready yet. Build 28 defaults
to invite-only creation; the public option is available only after directory
discovery succeeds. Missing/503 public endpoints explain that private room codes
still work. A public-create response without explicit public visibility is rejected
instead of silently accepting a private room from an old Worker.

Before review: deploy the Worker with migration `v6-public-directory` and the
matching current Swift engine, then test public tables on two physical devices.
If switching to another Cloudflare account, existing accounts/rooms do not migrate
automatically and older app versions still use the original endpoint. That needs a
separate migration decision, not a silent endpoint change.

## Store metadata and media

24 locales are saved on the editable version and draft App Information:
`ca`, `cs`, `da`, `de-DE`, `el`, `en-GB`, `en-US`, `es-ES`, `fi`, `fr-FR`, `hr`,
`hu`, `it`, `nl-NL`, `no`, `pl`, `pt-PT`, `ro`, `ru`, `sk`, `sl-SI`, `sv`, `tr`, `uk`.
They include name/subtitle, promotional text, description, what's new, keywords
and support/privacy URLs. The app UI remains English, Russian and Ukrainian;
descriptions disclose this. Unsupported European metadata languages use Apple's
storefront fallback; country availability is separate from metadata localization.

Current game screenshots for iPhone and iPad, an 18-second real app recording, and
two 5244×2950 universal creative images are in `Media/1.0.2`. English interface
captures are used as primary images for localized pages. No fake public player
population or working production directory is shown.

Header A (navy card fan) and organic Search Results A are placed on all 24 draft
localizations. Header B uses the actual current auction UI.

## Product page optimization

Draft experiment: `03cc13ca-b31e-4d47-aaa4-63efc1bf7064`.
Treatment: `a5cebae0-de05-4c28-b789-8abf9ec185fa`.
Planned allocation: original Header A 50%, Header B 50%; keep other assets fixed.

The experiment is NOT running and has NOT been submitted for review. Apple binds
experiment locales to the released version, which currently has only en-US.
The other 23 languages can be attached after version 1.0.2 is released. Publish
1.0.2 with Header A before starting so the comparison is truly A versus B, not the
old page without a header versus B. New assets/treatments need Apple approval.

## Verification

- Worker type checks, 52 unit tests and 14 workerd tests passed.
- Public-table network scenarios passed for three and four players, including
  discovery, join, leave/rejoin, readiness and the first deal.
- Selected Swift public-table, localization and transport-security tests passed.
- Native current-UI screenshot tests passed on iPhone and iPad.
- iOS Release archive and App Store Connect upload succeeded.
- Actual App Store Connect IDs, before-state backups and upload results are in
  `ReleaseEvidence/`; no API private keys are stored in the repository.

## References

- [Supported locales](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes)
- [Screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [Product page optimization](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization)
