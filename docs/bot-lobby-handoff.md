# Bot Lobby & Bot Play — Handoff

Date: 2026-05-02
Author: Claude (autonomous review pass)

## Scope of this pass

1. Reviewed the new lobby + bot wiring end-to-end ([LobbyView.swift](../Preferans/UI/LobbyView.swift), [GameViewModel.swift](../Preferans/GameViewModel.swift), [Sources/PreferansEngine/Bot](../Sources/PreferansEngine/Bot)).
2. Polished the lobby for a clear bot-vs-human flow.
3. Built a bulk simulation harness that plays 70 full bot-vs-bot matches end-to-end (50 × 3-player + 20 × 4-player, pool target 6) and reports stats + anomalies. Stand-in for sit-down manual play.
4. Reviewed sim output and code for issues.

## What landed

### Lobby polish ([LobbyView.swift](../Preferans/UI/LobbyView.swift))

- **Quick-play CTA**: one-tap "Quick play vs bots" button at the top of the local-table card. Pins roster to `["You", "East", "South"]` with seats 1–2 as bots and starts immediately. Identifier: `UIIdentifiers.lobbyQuickPlayVsBots`.
- **Roster summary line**: live `"1 human · 2 bots"` caption above the seat-count toggle so users don't have to count toggles.
- **Default bot seats fixed**: was `{1, 2, 3}` while default seat count was 3 — index 3 is non-existent at startup. Now `{1, 2}`, matching the visible roster.
- **Growing the table defaults new seats to bots**: switching 3 → 4 used to silently add a *human* "West"; now seat 3 starts as a bot, consistent with the rest of the bot-by-default roster.

### Simulation harness ([BotSimulationReportTests.swift](../Tests/PreferansEngineTests/BotSimulationReportTests.swift))

`swift test --filter BotSimulationReportTests` plays many full matches with `HeuristicStrategy` in every seat, asserts hard correctness invariants (no illegal action attempts, no stalls, no scoring drift), and prints a per-run report:

- result-kind histogram (game / passedOut / allPass / halfWhist / misere)
- contract value histogram
- declarer win/loss split + average tricks taken when game contracts are reached

This gives us a repeatable "did anything regress" knob without needing to drive the iOS UI.

## Hard correctness: clean

Across 70 matches / ~600 deals / thousands of bot decisions:

| Check | Result |
| --- | --- |
| Illegal actions attempted | 0 |
| Stalled deals (no actor / no decision) | 0 |
| Deal-cap (200 deals/match) hit | 0 |
| Scoring inconsistencies | 0 |
| All matches reached `gameOver` | 70 / 70 |

Engine + bot wiring is solid. No crashes, no soft locks.

## Issues found (priority order)

### P1 — Bots over-pass, dramatically (gameplay quality)

The single biggest issue surfaced. From the sim report (3-player x 50 matches):

```
allPass:    368
passedOut:   10
halfWhist:    9
game (all):  32
misere:       0
totus:        0
```

**~86% of deals end in all-pass / passed-out**. Real Preferans is normally 30–50% non-game at most. Matches drag because all-pass deals contribute very little to the pool, and pool target = 6 still required ~9 deals on average to finish.

Likely causes in [HeuristicStrategy.swift](../Sources/PreferansEngine/Bot/HeuristicStrategy.swift):

- **`bidIsAffordable` is too tight at the 6-trick floor.** `margin = 0.0` for 6-tricks contracts means the bot only opens 6♠/6♣/etc. when `expectedDeclarerTricks + 0.75 ≥ 6.0`, i.e. baseline estimate ≥ 5.25. [HandEvaluator.suitTricks](../Sources/PreferansEngine/Bot/HandEvaluator.swift) is conservative (e.g. an unsupported king is only worth 0.5 tricks), so most opening hands score 4–5. Suggest `margin = 0.5` for 6-trick bids and a slightly larger talon bonus (≈1.0) since the bot picks the best 2 of 4 talon-augmented cards.
- **Misère threshold (`≤ 0.5` forced tricks) is essentially unreachable.** [HandEvaluator.misereSuitTricks](../Sources/PreferansEngine/Bot/HandEvaluator.swift:103) charges 0.5 per gap and 1.0 per suit lacking a 7. A typical "good" misère hand has 1–2 forced tricks, so the threshold should be `≤ 1.5`, possibly with a check for "no missing 7 in any non-void suit". Result: bots never open misère, even when the contract is the right call.
- **Totus threshold needs a hand-of-the-decade.** Set to `≥ 9.5` expected tricks; expected trick estimates rarely top 9. Calibrate against simulated trick counts from the sampler instead of the heuristic.

This is the highest-leverage fix: tuning these three thresholds will turn the game from "watch the pot grow on all-passes" into actual Preferans.

### P2 — `selectedViewer` choice can leak info in mixed bot/human tables

In [LobbyView.startLocalTable](../Preferans/UI/LobbyView.swift) the viewer is pinned to the *first* human seat. With `viewerFollowsActor: true` *also* set on the model, the viewer follows the active actor — which means during a bot's turn the human briefly sees the bot's hand. For a "play vs bots" experience the user should not see opponent bots' cards. Decide explicitly: either keep the viewer pinned (recommended for vs-bots), or set `viewerFollowsActor` only when *every* seat is human (hot-seat).

### P3 — Bot pacing is fixed at 500ms

`GameViewModel.botMoveDelay = .milliseconds(500)` is hard-coded. A 10-trick all-bot deal takes ~5 s before the human can do anything. Surface this as a setting (slow / normal / instant) — useful both for users who want faster play and for test runs that want zero delay.

### P4 — `playerNames` not deduplicated / not validated

Lobby sends raw `PlayerID` values built from text fields. Two seats named "You" silently produce two distinct seats with the same ID, which the engine rejects on construction with `PreferansError.invalidPlayer` only via a generic error banner. Suggest validating before `startLocalTable` and showing a targeted message ("Names must be unique").

### P5 — `Quick play` always overwrites custom names

Tapping Quick play wipes whatever the user typed. Acceptable for now, but if we expect users to set names, Quick play could keep the existing roster when it's already 3 seats with at least one bot.

## Suggested next steps (in priority order)

1. **Calibrate bot thresholds** ([HeuristicStrategy.swift](../Sources/PreferansEngine/Bot/HeuristicStrategy.swift) + [HandEvaluator.swift](../Sources/PreferansEngine/Bot/HandEvaluator.swift)). Run the sim harness before/after — target: 35–55% non-game deals, ≥1 misère per 50 deals, ≥1 totus per 200 deals.
2. **Decide on `viewerFollowsActor` in vs-bots mode**. Likely: pin viewer when any seat is a bot; only follow actor in pure hot-seat games.
3. **Expose bot speed in the lobby** (3-state segmented control: instant / normal / slow).
4. **Roster validation** — block Start when names collide / are empty.
5. **Add a "spectator / demo" preset** — all bots, fast pacing — useful for screenshots and onboarding.

## How to reproduce findings

```sh
swift test --filter BotSimulationReportTests
```

The test prints two reports (3-player and 4-player). The asserted invariants will fail loudly if any future change introduces an illegal-action path, a stall, or scoring drift.
