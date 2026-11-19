# Branch and build status

Source and release evidence reviewed on 19 November 2026. The numbered specs retain the source revisions against which they were originally written. This page maps later source, server and distribution observations.

| Branch or release line | Implemented behavior | Release evidence |
|---|---|---|
| [`release/1.0.2-build-28`](https://github.com/DmytroGusev/preferans/blob/release/1.0.2-build-28/AppStore/Release-1.0.2.md) and [`fix/owner-multiplayer-build29`](https://github.com/DmytroGusev/preferans/blob/fix/owner-multiplayer-build29/docs/OWNER_MULTIPLAYER_BUILD29.md) | Build 28 introduced public-table discovery and readiness, with an invite-only fallback for the older deployment. Build 29 prepared the owner-hosted multiplayer path and its public tables and room recovery. | Historical release records. Check the exact server and build before interpreting either release. |
| [`main` at `c462108`](https://github.com/DmytroGusev/preferans/commit/c4621082a8a36c3cffdbf58d1f7a01faff64cefa), build 30 | Protocol 4. The Worker owns the persisted room, command receipts and private projections. The Swift server engine applies commands. Reconnect and retry use the saved seat and durable client outbox. Build 30 fixes next-deal progress and reconnect feedback, records final balances and masks account IDs in private rooms. | Owner service and engine updated. The delivery record includes native create/join and live three-/four-seat checks. [Build 30](https://github.com/DmytroGusev/preferans/blob/release/1.0.3-build-30/AppStore/BuildHistory.md) |
| [`release/1.0.3-build-31`](https://github.com/DmytroGusev/preferans/blob/release/1.0.3-build-31/AppStore/BuildHistory.md), build 31 | Build 30 gameplay with unused ATT/IDFA paths removed. | TestFlight delivery. Apple privacy questionnaire validation remained open in the release record. |
| [`feature/bots-and-club-info-build32`](https://github.com/DmytroGusev/preferans/blob/feature/bots-and-club-info-build32/AppStore/Release32/README.md), build 32 | The lobby manager can add, remove and tune bots before the deal. Roster changes require readiness again. Settings links to Club information. Club payment and quota enforcement are off. | Native simulator flows and live first deals recorded. The record does not establish physical-device full matches. |
| [`feature/firebase-product-analytics`](https://github.com/DmytroGusev/preferans/tree/ecd112efb9f37ffb4d4d20feee1cad93b2d828b7), builds 33–35 | 33 kept mixed seats and added an explicit non-tracking manifest. 34 added opt-in Firebase usage analytics. 35 added opt-in diagnostics for room admission, readiness, reconnect and the first deal. Neither analytics build requires a new room protocol. | Build 33 was recorded as the Distribution selection. Builds 34 and 35 were processed and recorded as ready for beta testing. The build 35 record shows no group assignment and no confirmed receipt of the new events from a physical device. [33](https://github.com/DmytroGusev/preferans/blob/ecd112e/AppStore/Release33/README.md) · [34](https://github.com/DmytroGusev/preferans/blob/ecd112e/AppStore/Release34/README.md) · [35](https://github.com/DmytroGusev/preferans/blob/ecd112e/AppStore/Release35/README.md) |

[Public App Store listing](https://apps.apple.com/app/id6763581975). Use the release records above for the specific binaries; an editable Distribution selection is not a public release.

## Open acceptance checks and proposed work

| Area | Status and acceptance |
|---|---|
| UI clarity | **Proposed regression coverage.** For auction, whist, trick play and reconnect, verify the phase, acting seat, available action and visible connection status on iPhone and iPad. Use fixtures tied to the exact source and build. |
| Online recovery | **Implemented.** As a release check, play a complete mixed match in the target environment. Interrupt delivery after an accepted command, relaunch one client and verify the same seat, a matching receipt, one applied move and consistent final balances. Record physical-device and hosted-client runs separately. |
| Analytics and release | **Pending candidate acceptance.** For build 35, verify consent off/on/revoked and receipt of an allowed diagnostic event from a physical device. Reconcile Apple App Privacy with the exact package and privacy notice. The 35 record still reports the legacy tracking declaration issue. |

[iOS](005-ios-app/spec.md) · [Online](004-online-multiplayer/spec.md) · [Testing and release](006-testing-and-release/spec.md)
