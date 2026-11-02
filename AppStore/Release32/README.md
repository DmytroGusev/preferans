# Preferans 1.0.3 (32): Online Bot Seats And Club Information

2 November 2026. The owner authorized updating only the owner's Worker and
uploading build 32 to the existing external TestFlight group. The current
engine image, namespaces, player data and friend's server must be preserved.
No public App Review submission, payment activation or subscription rollout.

## Source And Behavior

Base: build 31 branch, including its non-tracking/privacy correction and Guru
metadata migration. Integrates bot feature 9864885 (PR #9) as ef40496 without
merging any GitHub PR or changing main. Main remains c462108.

- Host gets Add bot on each empty seat of a public or private waiting table.
- Casual, Seasoned and Expert; change/remove a bot before the first deal.
- Two humans plus one bot at a three-seat table or two bots at a four-seat table.
- Never replace a joined human, even when disconnected. Only the host can edit.
- Adding bots does not start a game. Real roster/difficulty changes clear Ready;
  all humans reconfirm at public tables, then the host starts separately.
- New localized explanation makes this Ready reset explicit.
- Settings starts with Club & online access, linked to the maintained website.
  Terms, Privacy and Support have stable accessibility IDs under Help & Legal.
- Online access is still free. Club, StoreKit purchase UI, quotas and ads are NOT
  activated. The website describes a proposed three-pulkas/month, US $4.99 plan.

## Deployment Safety

Only deploy workers/room-worker with wrangler.owner.toml. Before rollout the live
Worker is 057ca688-8fb1-4f89-a057-4eea2ce36091; engine app is
a032d1ae-1fb4-4259-b62b-4cfa10bead7a, version 2, three healthy instances.
The config is updated to retain the already-deployed image, not to change it:

registry.cloudflare.com/df302a84563143eb92fc75a7277079ec/preferans-engine@sha256:90d5da73d8fc8cd677e3e4047174b46c03cfd8539005d685a8274c16b1e456dc

No new migrations, namespaces or engine image build are needed. Do not deploy
the default wrangler.toml or the older Club bootstrap draft. Source rollback is
the prior live Worker version with the same image/namespaces, not a state reset.

## Verification And Delivery

Record final receipts here. Initial checks: Worker 59 unit and 19 runtime tests,
typecheck; real local Swift/Worker public/private three/four-seat bot starts;
native two-humans-Ready-then-bot flow and Settings links; app test suite.
Native bot test passed in 56.828 seconds. The first Settings test queried Link
as Button and failed; corrected element-type coverage passed in 16.029 seconds.
Do not claim physical-device QA or complete-match bot QA from first-deal tests.

Build 31's unresolved App Privacy editor validation is separate from this bot
rollout. Build 32 retains the removal of ATT/IDFA; no tracking is added. Keep the
public Store draft and its metadata/build selection unchanged in this task.
