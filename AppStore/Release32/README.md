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

Exact archived app/Worker source: f4b65759eb107c87592e71a84a63307bd43046c0.
Final receipts are stored here. Checks: Worker 59 unit and 19 runtime tests,
typecheck; real local Swift/Worker public/private three/four-seat bot starts;
native two-humans-Ready-then-bot flow and Settings links; app test suite.
Native bot test passed in 56.828 seconds. The first Settings test queried Link
as Button and failed; corrected element-type coverage passed in 16.029 seconds.
On iPad the bot flow passed in 46.552 seconds and Settings links in 16.931.
App coverage: 272 XCTest cases, three gated skips, zero failures; 24 Swift
Testing cases, zero failures. QA accounts were cleaned up and local services
stopped after testing.
Do not claim physical-device QA or complete-match bot QA from first-deal tests.

The live owner Worker is now 58c7f8e0-eb14-43cd-a5dc-46e72f0fba58. All four
real-network public/private three/four-seat cases passed, including private
projections and both humans Ready before and after adding bots. Container
configuration, version 2 and namespace were read back unchanged; Wrangler
reported no container changes. There was no account/game reset or friend deploy.

Apple processing: VALID. Build ID: 8535d1ba-3fa4-4086-8ff7-3b4d59f80213.
External state: IN_BETA_TESTING, Beta App Review APPROVED, existing six testers,
unchanged membership/public-link settings, automatic notification enabled.
Protected readback proves Store version selections, all 24 localizations and
public review notes unchanged. Draft 1.0.3 still selects build 31; update/select
the public release separately after testing and resolving its privacy gate.

## Guru Of Cards

The Club page is live at <https://guruofcards.com/apps/preferans/club/> with
Russian/Ukrainian versions. It is linked from every Preferans website page and
from Settings. Source: ca3dd79d8745d77bbe29a461129ec2afa8c39bf2 in the existing
masti-card-encyclopedia repo/PR #1. All 19 public HTML/CSS checks returned 200
with exact source hashes; scoped Apache config returned 403. No other website
paths were changed. Backup is outside public_html:
/home/gurujtkn/.guru-cards-releases/preferans-pages-before.uOiN0w.

The page explains the future offer, not currently purchasable access. The old
uncommitted Club draft still uses five free entries and must not be deployed
unchanged: future implementation needs the agreed three-entry rule, current
protocol integration, safe new ledger migration and real purchase verification.

Minor UI follow-up: the generic Support link title currently uses the English
fallback in ru/uk. The destination and the new Club/Ready explanations work;
the dedicated website pages are available in all three languages.

Client rollback can use build 31, but it has no bot editing controls. A Worker
rollback retains data/image, but the old code lacks public-bot admission/Ready
behavior; coordinate it with clients rather than assuming full bot compatibility.
No rollback was executed. No GitHub PR was merged by this rollout.

Build 31's unresolved App Privacy editor validation is separate from this bot
rollout. Build 32 retains the removal of ATT/IDFA; no tracking is added. Keep the
public Store draft and its metadata/build selection unchanged in this task.
