# Feature Specification: Computer Players (Bots)

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `Sources/PreferansEngine/Bot/PlayerStrategy.swift`, `Sources/PreferansEngine/Bot/HeuristicStrategy.swift`, `Sources/PreferansEngine/Bot/BotProfile.swift`, `Sources/PreferansEngine/Bot/HandEvaluator.swift`, `Sources/PreferansEngine/Bot/CardPlayPlanner.swift`, `Sources/PreferansEngine/Bot/DealSampler.swift`; drivers in `Preferans/GameViewModel.swift`, `Preferans/Online/RoomBotMoveScheduler.swift`, `Sources/PreferansServerCore/AuthoritativeGameService.swift`; pacing in `Preferans/Support/BotPacing.swift`

Related specs: game phases and legality in [`../001-game-rules`](../001-game-rules/); scoring the bots optimise against in [`../002-scoring-and-variants`](../002-scoring-and-variants/); online bot seats, the room worker and durable bot alarms in [`../004-online-multiplayer`](../004-online-multiplayer/); lobby seat editor, bot speed picker, "Watch bots" demo and `BotPacing` in [`../005-ios-app`](../005-ios-app/); bot simulation lanes in [`../006-testing-and-release`](../006-testing-and-release/). Algorithms in detail: [`plan.md`](./plan.md).

## Summary

Bots are implementations of the `PlayerStrategy` protocol. The only production strategy is `HeuristicStrategy`, parameterised by a `BotProfile` (difficulty × temperament = 9 personalities). For every non-card decision it uses fast deterministic rules over a calibrated hand evaluator (`HandEvaluator`): auction bids, discard, contract declaration, "without three" concession, whist/half-whist/pass, open/closed defence, and settlement accept/reject. For card play it uses perfect-information Monte Carlo (`CardPlayPlanner`): it samples complete deals consistent with what the bot's seat may know (`DealSampler`), plays each candidate card out with a greedy rollout policy for all seats, scores each rollout with the real match balance, and picks the card with the best mean (adjusted by temperament for variance). Sampling uses a fixed-seed xoshiro256** generator recreated per decision, so a bot's decision is a pure function of (snapshot, viewer, profile, planner config).

The same strategy runs in three hosts: the local `GameViewModel` (per-seat profiles chosen in the lobby), the in-app online host (`RoomBotMoveScheduler`, default profile) and the server-authoritative Linux engine (`AuthoritativeGameService.advanceBot`, profiles sent by the worker, currently always seasoned/adaptive). Every host validates the strategy's answer with `BotDecisionRecovery` and falls back to a deterministic legal move if the strategy returns nothing or something illegal.

## User Scenarios & Testing

### User Story 1 – Bots finish any deal and match legally (Priority: P1)

A player sits at a table with one to three bots (or watches four bots); bots act whenever it is their turn, in every phase, until the match ends.

**Why this priority**: A stalled or illegal bot blocks the table for everyone.

**Independent Test**: Drive the engine with `BotTestDriver.drive` and `HeuristicStrategy` until no actor remains (`Tests/PreferansEngineCoreTests/BotTests.swift`, `BotSimulationReportTests.swift`).

**Acceptance Scenarios**:

1. **Given** a stacked strong-spades deal, **When** bots play every seat, **Then** the deal reaches a scored result (`testStrategyDrivesEntireGameDealToFinish`); likewise for misère and all-pass deals (`testStrategyDrivesMisereDealToFinish`, `testStrategyDrivesAllPassDealToFinish`).
2. **Given** five random deals, **When** bots drive each, **Then** every deal finishes without a stall (`testFiveConsecutiveBotDealsAllReachAScoredResult`).
3. **Given** seeded 3-player matches (pool total 6) and 4-player matches (24), **When** bots play to `gameOver`, **Then** there are 0 illegal actions, 0 stalls, 0 scoring inconsistencies, 0 deal-cap hits (200 deals) and no match exceeds 30 s (`testFiftyThreePlayerMatchesAgainstBots`: 5 matches, 50 with `PREF_SIM_FULL=1`; `testTwentyFourPlayerMatchesAgainstBots`: 3 / 20).
4. **Given** every temperament, **When** casual bots play the same fixed deal, **Then** each completes it legally (`testEveryTemperamentCompletesTheSameFixedGameDealLegally`).

---

### User Story 2 – Bots never use cards their seat cannot see (Priority: P1)

**Why this priority**: Fair play; in online rooms bots run where the full state is available.

**Independent Test**: Swap hidden cards between two worlds the bot cannot distinguish and assert identical samples and decisions (`Tests/PreferansEngineCoreTests/BotInformationTests.swift`, `SettlementInformationTests.swift`).

**Acceptance Scenarios**:

1. **Given** an all-pass deal with a hidden talon, **When** a hidden talon card is swapped with an opponent's card, **Then** the sampled worlds and the chosen card are identical (`testHiddenTalonWorldsAndDecisionsIgnoreTheRealHiddenCards`).
2. **Given** a closed game seen by a defender (viewer north; east declares), **When** 64 worlds are sampled, **Then** each keeps the viewer's own hand, places the public talon only in the declarer's hand or discard, rehydrates as a valid engine, and the declarer's hidden hand varies (> 20 distinct) (`testClosedGameSamplesRespectThePublicExchangeAndRehydrate`).
3. **Given** sampling yields no worlds, **When** the planner chooses, **Then** it picks the lowest of its own legal cards, never a card derived from real hidden hands (`testAnEmptySampleSetUsesOnlyTheViewersLegalCards`).
4. **Given** a defender facing a last-trick settlement whose outcome depends on whether the declarer kept Q♥ or A♥, **When** the bot decides, **Then** it rejects in both worlds; **Given** every possible hidden card loses, **Then** it accepts (`testBotRejectsAnUncertainFinalSplitInBothHiddenWorlds`, `testDefenderAcceptsWhenEveryPossibleHiddenCardLoses`).
5. **Given** open defence or an open 10-trick check, **Then** the exposed hands stay fixed in every sample (`testOpenDefenseKeepsBothDefendersVisibleToEverySeat`, `testTenTrickVerificationKeepsEveryHandVisible`).
6. **Given** a player failed to follow a talon-led suit, **Then** no sample gives that player a card of that suit (`testOffSuitForehandIsKnownVoidInTheTalonLeadSuit`).

---

### User Story 3 – Profiles change risk appetite, not legality (Priority: P2)

The lobby lets each bot seat pick difficulty (Casual / Seasoned / Expert) and temperament (Careful / Adaptive / Bold).

**Why this priority**: Gives tables distinct personalities and a difficulty knob.

**Independent Test**: Fixed-hand decision corpora (`BotTests`).

**Acceptance Scenarios**:

1. **Given** a borderline hand (♠AK ♣A98 ♦K7 ♥J109), **When** casual/seasoned/expert adaptive bots open, **Then** casual passes and seasoned/expert bid a 6-level game (`testDifficultyCorpusChangesAuctionRiskWithoutChangingLegality`); careful seasoned passes, bold seasoned bids 6 (`testOpeningDecisionCorpusCoversStrengthStyleAndRaspasyExit`).
2. **Given** difficulty, **Then** planner samples are casual 6, seasoned 16, expert 32 (`testDifficultyControlsPlannerDepth`).
3. **Given** two candidate cards with rollout outcomes stable [4,4,4] vs swing [0,0,10], **Then** careful and adaptive choose the stable card and bold the swing card; vs [0,0,6] all choose stable; on equal [3,3,3] lines careful/adaptive keep the lower card and bold plays the higher (`testCardPlayTemperamentCorpusBalancesReliabilityAndUpside`).
4. **Given** a second defender with a strong hand after the first defender whisted, **Then** careful passes and bold whists (`testTemperamentChangesBorderlineSecondWhist`); **Given** a lone whister, **Then** careful chooses open and bold closed defence (`testTemperamentChangesSingleWhistVisibility`).

---

### User Story 4 – Bot decisions are reproducible (Priority: P2)

**Why this priority**: Online hosts and retries must compute the same move; tests must be stable.

**Independent Test**: `Tests/PreferansEngineCLITests/BotDeterminismTests.swift`.

**Acceptance Scenarios**:

1. **Given** equal seeds, **When** the sampler runs twice, **Then** the 8 samples are equal ("Deal sampler returns equal samples for equal seeds").
2. **Given** one planner, **When** it chooses five times for the same snapshot and viewer, **Then** the card is the same ("Card planner is pure for a snapshot, viewer, and configuration").

---

### User Story 5 – Bots respond sensibly to settlement offers (Priority: P2)

**Why this priority**: A human may propose a claim; a bot must neither block a forced ending nor give away tricks.

**Independent Test**: `Tests/PreferansEngineTests/SettlementTests.swift`.

**Acceptance Scenarios**:

1. **Given** a misère settlement proposed at the opening lead, **When** a bot defender is on the clock, **Then** it rejects ("A bot defends rather than agreeing to a speculative settlement").
2. **Given** the last trick is forced and the proposal equals the forced split, **Then** the bot accepts ("A bot agrees once the remaining trick is determined").
3. **Given** a forced last trick with no proposal, **When** bots drive, **Then** they play the trick out (3 steps) and never propose a settlement ("Bot plays deterministic last trick instead of proposing settlement").

---

### User Story 6 – Bots explain strategic moves without revealing cards (Priority: P2)

After a bot bids, discards, declares, whists or chooses a defence mode, the app can show a short note such as "My defensive estimate cleared the full-whist threshold."

**Why this priority**: Helps learners; must not leak hidden information.

**Independent Test**: `testStrategicDecisionCarriesPublicSafeProfileExplanation`.

**Acceptance Scenarios**:

1. **Given** an expert/bold bot that whists, **When** `decision(snapshot:viewer:)` is called, **Then** the result carries `BotDecisionExplanation(actor:, profile: expert/bold, rationale: .fullWhist)` with category `.whist`.
2. **Given** a card play, **Then** no explanation is attached.

---

### User Story 7 – A stuck or wrong strategy never stalls a table (Priority: P3)

**Why this priority**: Defensive guard for custom strategies, interrupted sessions and online hosts.

**Independent Test**: `BotDecisionRecovery.recover` is exercised by all hosts; the test driver's diagnostics are covered by `Tests/PreferansEngineCLITests/BotTestDriverDiagnosticsTests.swift`.

**Acceptance Scenarios**:

1. **Given** a strategy that returns `nil` or an action the engine rejects, **When** a host runs `BotDecisionRecovery.recover`, **Then** it substitutes a deterministic legal action (first legal bid = pass, first two cards for discard, lowest legal contract, first legal whist call, closed defence, accept-if-possible-else-reject for settlements, first legal card).
2. **Given** the test driver, **When** a strategy refuses, is rejected, or hits the step limit, **Then** the driver reports `strategyReturnedNoAction`, `engineRejectedAction` (with error text) or `stepLimitReached` with both the acting and deciding seat; completing exactly at the limit is not a stall.

### Edge Cases

- **Open single-whist (greedy) play**: when the passer's card is due, the lone whister's strategy decides and the action is sent for the passer (`controllingActor`). Bots therefore are asked for the *controller* seat (`DealState.currentActor` → `engine.controllingActor(of:)`).
- **Settlement pending**: only the party on the clock is asked; bots accept iff the proposal equals `forcedSettlement(in:knownTo:)`, else reject. Bots never propose.
- **Single legal card**: played immediately without sampling.
- **Stalingrad 6♠**: the only legal whist call is whist; the strategy returns it even below its threshold.
- **Totus**: bid only if the match uses `.dedicatedContract` and the best strain estimate + 2 ≥ 9; the app never enables dedicated totus.
- **Raspasy exit progression**: bots only see legal bids, so after raspasy they open at the new minimum level (`strict` 3rd stage → 8♠ for a strong spade hand).
- **High contract after a weak exchange**: for final bids of 8+ tricks (or totus) the bot may concede "without three"; it never concedes 6/7 or misère.
- **Stale decisions**: hosts drop a decision if the engine snapshot changed while the bot was thinking.
- **Sampler failure** (constraints unsatisfiable within 32 attempts or hidden-pool size mismatch): that sample is skipped; if all fail the bot plays its lowest legal card.

## Requirements

### Functional Requirements

#### Architecture

- **FR-001**: The system MUST define `PlayerStrategy` (`Sendable`) with `decide(snapshot:viewer:) async -> PreferansAction?` and `decision(snapshot:viewer:) async -> StrategyDecision?`; the default `decision` wraps `decide` without an explanation. — `PlayerStrategy.swift`.
- **FR-002**: A strategy MUST return `nil` when `viewer` is not the seat expected to decide (not the bidder, declarer, current whister, whister choosing mode, settlement party on the clock, or controller of the current card seat), and for `waitingForDeal`, `dealFinished`, `gameOver`. — `HeuristicStrategy.decide`.
- **FR-003**: Hosts MUST ask the strategy of the *controlling* seat (`engine.controllingActor(of: currentActor)`), and MUST send the card action in the name of the seat that owns the card. — `HeuristicStrategy.decide` (`.playing`), `GameViewModel.scheduleBotIfNeeded`, `AuthoritativeGameService.advanceBots`, `HostGameActor.nextBotDecisionPlan`; `SingleWhistControlTests`.
- **FR-004**: Every host MUST pass the candidate through `BotDecisionRecovery.recover(_:snapshot:viewer:)`, which accepts it only if its actor equals `currentActor`, `controllingActor(of: actor) == viewer`, and applying it to a throwaway engine succeeds; otherwise it MUST return the deterministic fallback listed in User Story 7, or `nil` when nothing awaits `viewer`. — `PlayerStrategy.swift` `BotDecisionRecovery`.

#### Profiles

- **FR-005**: `BotProfile` MUST combine `BotDifficulty` {casual, seasoned, expert} and `BotTemperament` {careful, adaptive, bold}; default/`standard` = seasoned + adaptive. — `BotProfile.swift`.
- **FR-006**: Profile parameters MUST be exactly:

  | Parameter | casual | seasoned | expert | Used by |
  | --- | --- | --- | --- | --- |
  | `plannerSamples` | 6 | 16 | 32 | card play |
  | `bidMarginAdjustment` (difficulty) | −0.25 | 0 | +0.25 | bid affordability |
  | `contractFailurePenalty` | 6 | 5 | 4 | contract choice, concession margin |
  | `misereToleranceAdjustment` (difficulty) | −0.15 | 0 | +0.15 | misère bid |

  | Parameter | careful | adaptive | bold | Used by |
  | --- | --- | --- | --- | --- |
  | `bidMarginAdjustment` (temperament) | −0.35 | 0 | +0.35 | bid affordability |
  | `whistThresholdAdjustment` | +0.35 | 0 | −0.35 | whist / half-whist |
  | `misereToleranceAdjustment` (temperament) | −0.25 | 0 | +0.25 | misère bid |
  | `rolloutRiskWeight` | −0.35 | 0 | +0.35 | card selection, concession margin |

  — `BotProfile.swift`; `testDifficultyControlsPlannerDepth`.

#### Auction

- **FR-007**: A game bid `c` MUST be "affordable" iff `expectedDeclarerTricks(hand, c.strain) + 2.0 ≥ c.tricks − margin(c.tricks) − tempBidAdj − diffBidAdj`, with `margin` = 0.5 (6, 7), 0.75 (8), 1.0 (9), 1.5 (10). Misère is affordable iff `expectedMisereTricks(hand) ≤ 1.5 + tempMisereAdj + diffMisereAdj`. Totus is affordable iff `max over strains(expectedDeclarerTricks) + 2.0 ≥ 9.0`. — `HeuristicStrategy.bidIsAffordable`; `testOpeningDecisionCorpusCoversStrengthStyleAndRaspasyExit`.
- **FR-008**: Among the engine's legal calls the bot MUST choose, in order: misère if affordable; totus if affordable; otherwise the lowest affordable game level, choosing among that level's affordable strains the one with the highest declarer estimate (first in ladder order ♠, ♣, ♦, ♥, NT on ties); otherwise pass. — `HeuristicStrategy.chooseBid`; `testOpeningDecisionCorpusCoversStrengthStyleAndRaspasyExit`.

#### Exchange and declaration

- **FR-009**: The discard MUST be chosen by enumerating all 66 pairs of the 12 cards (hand + talon) and keeping the pair whose remaining 10 cards score best: maximum `expectedDeclarerTricks` for the auction's game strain; maximum over strains for totus; minimum `expectedMisereTricks` for misère; ties → first pair in enumeration order (hand order, then talon). — `HeuristicStrategy.chooseDiscard`, `scoredDiscardPairs`, `keptHandScore`; `testMisereDiscardCorpusDropsTheTwoTalonHonors`, `testGameDiscardScoresAgainstDeclaredTrump`.
- **FR-010**: For a final game bid of ≥ 8 tricks or totus, the bot MUST concede without three iff `max over legal declarations(expectedDeclarerTricks(10-card hand)) + safety < target`, where `safety = 0.75 + (contractFailurePenalty − 4) × 0.2 − rolloutRiskWeight × 0.25`. It MUST never concede misère or 6/7-level bids. — `HeuristicStrategy.shouldConcedeWithoutThree`; `testWeakHighContractUsesWithoutThreeConcession`, `testStrongHighContractStillDeclaresNormally`.
- **FR-011**: Otherwise the bot MUST declare the legal contract maximising `value + (estimate − tricks)` when `estimate ≥ tricks`, else `(estimate − tricks) × contractFailurePenalty` (first maximum in ladder order). Consequently a strong hand may declare above its auction bid. — `HeuristicStrategy.chooseContract`.

#### Defence

- **FR-012**: For a whist decision the bot MUST compute `estimate = expectedDefenderTricks(hand, trump)`, `share = max(1, rules.whistRequirement(contract) / 2)`, threshold `share (+1 if the first defender already whisted and the bot is the second defender) + whistThresholdAdjustment`; it MUST whist if legal and `estimate ≥ threshold`, else half-whist if legal and `estimate ≥ share − 0.75 + whistThresholdAdjustment`, else pass if legal, else the first legal call. — `HeuristicStrategy.chooseWhistCall`; `testSecondDefenderPassesMarginalHandAfterFirstDefenderWhists`, `testSecondDefenderStillWhistsWithStrongHandAfterFirstDefenderWhists`, `testTemperamentChangesBorderlineSecondWhist`.
- **FR-013**: As a lone whister the bot MUST choose open defence for expert or careful profiles; for seasoned + adaptive open only on 6- and 7-level contracts; closed for casual or bold profiles (the first matching rule wins, so expert + bold is open and casual + careful is open). — `HeuristicStrategy.chooseDefenderMode`; `testTemperamentChangesSingleWhistVisibility`.

#### Card play

- **FR-014**: Card play MUST use `CardPlayPlanner.choose`: if ≤ 1 legal card, play it; else sample `samples` worlds with a fresh `SeededRandomNumberGenerator(seed: samplingSeed)` (default seed `0x5052_4546_4552_414E`), roll out every legal card in every world, and select by `mean + rolloutRiskWeight × populationStdDev`; ties → lowest card (careful/adaptive) or highest card (bold) in `Card` order. If no world could be sampled, play the lowest legal card; if the planner returns `nil`, the strategy plays the first legal card. — `CardPlayPlanner.choose`, `selectCard`, `rolloutUtility`; `testCardPlayTemperamentCorpusBalancesReliabilityAndUpside`.
- **FR-015**: Each rollout MUST play the remainder of the deal with `greedyChoice` for every seat and score it as the viewer's `normalizedBalances` value under the table's rules (pulka closing included); a first move illegal in that world scores −1000; an unterminated rollout falls back to a trick-count proxy. — `CardPlayPlanner.rollout`, `score`, `scoreFromPlaying`; `testRolloutCardsMatchValidatedPlayThroughCompleteDeals`.
- **FR-016**: The greedy rollout policy MUST: treat every seat in a game, and misère defenders, as wanting tricks, and the misère declarer and all raspasy players as avoiding them; on lead, cash a non-trump ace (the first in `Card` order) if wanting tricks, else lead the lowest-ranked card, preferring non-trumps; when following and wanting tricks, play the lowest card if a partner (fellow defender) is currently winning, else the cheapest card that beats the current winner, else the lowest card; when following and avoiding tricks, play the highest card that does not beat the current winner, else the highest card. — `CardPlayPlanner.greedyChoice`, `leadCard`, `followCard`; `testDefenderRolloutTakesCheapestWinningCard`, `testDefenderRolloutDoesNotOvertakeWinningPartner`, `testMisereDeclarerRolloutShedsHighestLosingCard`, `testMisereDefenderRolloutTakesCheapestWinningCard`, `testMisereDefenderRolloutDoesNotOvertakeWinningPartner`.

#### Information set

- **FR-017**: Sampled worlds MUST keep fixed: the viewer's hand; hands of seats the viewer controls; both defenders' hands in open defence; every hand in an open 10-trick check (no whisters and no whist calls); misère defenders' hands once the declarer's opening lead has been made (or a defender leads); all played cards; revealed raspasy talon leads; the discard only when the viewer is the declarer (always empty in raspasy). — `DealSampler.samples`, `sampleOnce`; BotInformationTests.
- **FR-018**: Sampled worlds MUST redistribute every other card among hidden seats (same hand sizes), the hidden discard and the unrevealed raspasy talon, subject to: inferred voids (a seat that failed to follow a lead suit is void in it, and also in trump if it neither followed nor trumped a non-trump lead); exchanged talon cards may only go to the declarer or the discard. — `DealSampler.inferredVoids`, `sampleOnce`; `testOffSuitForehandIsKnownVoidInTheTalonLeadSuit`, `testClosedGameSamplesRespectThePublicExchangeAndRehydrate`, `testFirstRaspasyLeadKeepsOnlyTheRevealedTalonCardFixed`, `testRevealedRaspasyLeadsRemainKnownAfterBothOpeningTricks`.
- **FR-019**: Non-card decisions MUST read only the viewer's own cards (plus the talon the declarer receives), public auction/whist history, legal-move lists, rules and profile. Settlement responses MUST use `forcedSettlement(in:knownTo:)`. — `HeuristicStrategy`; `PreferansEngine.forcedSettlement(in:knownTo:)`; SettlementInformationTests.

#### Explanations

- **FR-020**: `HeuristicStrategy.decision` MUST attach `BotDecisionExplanation(actor, profile, rationale)` for strategic actions with rationale: pass → `auctionPass`; game/misère/totus bid → `gameBid`/`misereBid`/`totusBid`; discard → `discardForMisere` (misère) or `discardForContract`; declare → `contractFit`; concede → `contractConcession`; whist/half-whist/pass → `fullWhist`/`halfWhist`/`defensivePass`; defence mode → `openDefense`/`closedDefense`; accept/reject settlement → `forcedSettlement`/`contestSettlement`; none for card play. Rationales carry no card data. — `HeuristicStrategy.rationale`; `testStrategicDecisionCarriesPublicSafeProfileExplanation`.
- **FR-021**: Hosts MUST keep only a bounded window of explanations: the local view model keeps the last 24, the authoritative server state the last 20. — `GameViewModel.scheduleBotIfNeeded`; `AuthoritativeGameService.advanceBots`.

#### Determinism, hosts and pacing

- **FR-022**: Given the same snapshot, viewer, profile and planner configuration, `HeuristicStrategy` MUST return the same action. — `CardPlayPlanner.choose` (RNG recreated per call), `DealSampler` (hidden pool sorted before shuffling); BotDeterminismTests.
- **FR-023**: The local app MUST run at most one pending bot decision, cancel it on any state change, wait `botMoveDelay`, compute off the main actor, and apply the action only if `engine.snapshot` still equals the snapshot it decided on. — `Preferans/GameViewModel.swift` `scheduleBotIfNeeded`.
- **FR-024**: The server-authoritative engine MUST apply at most one bot action per `advanceBot` call (pacing and continuation belong to the room's durable alarm), use the seat's stored `BotProfile`, throw `botStalled` if recovery yields nothing, and guard with `maximumBotActionsPerCommand = 512`. — `Sources/PreferansServerCore/AuthoritativeGameService.swift` `advanceBot`, `advanceBots`.
- **FR-025**: Bot pacing MUST come from `BotPacing`: `interactive` 500 ms (default), lobby speeds `normal` 1200 ms / `slow` 2200 ms / `instant` 0, `testFast` 10 ms only under `-uiTestFastBotDelay`. — `Preferans/Support/BotPacing.swift`; `Preferans/UI/LobbyModels.swift` `BotMoveSpeed` (full UI behaviour in [`../005-ios-app`](../005-ios-app/)).
- **FR-026**: The lobby MUST seed stock bot seats with: Morpheus expert/careful, Trinity seasoned/bold, Agent Smith expert/adaptive, Neo seasoned/adaptive (when Neo is a bot, e.g. "Watch bots"), any other added bot casual/adaptive; the user can change each bot seat's difficulty and temperament. — `Preferans/UI/LobbyModels.swift` `LobbySeat.stockBotProfile`; `Preferans/UI/LobbyView.swift`.

### Key Entities

- **PlayerStrategy / StrategyDecision** — strategy protocol and its result (action + optional explanation).
- **HeuristicStrategy** — the production strategy (`profile`, `planner`).
- **BotProfile, BotDifficulty, BotTemperament** — serializable personality (`{"difficulty":"seasoned","temperament":"adaptive"}`).
- **BotDecisionExplanation, BotDecisionRationale, BotDecisionCategory** — public-safe move notes (15 rationales in 6 categories: auction, contract, discard, whist, defenderMode, settlement).
- **BotDecisionRecovery** — legality gate and deterministic fallback.
- **HandEvaluator** — static trick estimators (declarer, defender, misère; an all-pass estimator exists but is unused).
- **CardPlayPlanner** — PIMC planner (`samples`, `samplingSeed`).
- **DealSampler** — information-set world generator.
- **SeededRandomNumberGenerator** — xoshiro256** seeded via SplitMix64 (`Sources/PreferansEngine/DealSource.swift`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 0 illegal actions, 0 stalls, 0 scoring inconsistencies over the smoke simulation (5 three-seat + 3 four-seat seeded matches) and the full run (50 + 20) — `BotSimulationReportTests`.
- **SC-002**: Every simulated match finishes within 30 s and 200 deals with 4-sample planners — `BotSimulationReportTests`; AGENTS.md target: a 4-player all-bot match to pool 6 completes "well under a minute" with animations and delays disabled.
- **SC-003**: Indistinguishable hidden worlds yield byte-identical samples and identical card choices — `testHiddenTalonWorldsAndDecisionsIgnoreTheRealHiddenCards`.
- **SC-004**: Repeated planner calls on one snapshot return one card — BotDeterminismTests.
- **SC-005**: Rollout card application matches validated engine play for complete game and raspasy deals (30 plays each) — `testRolloutCardsMatchValidatedPlayThroughCompleteDeals`.
- **SC-006**: Each documented profile difference in User Story 3 is pinned by a corpus test in `BotTests`.

## Known Gaps & Open Questions

1. **Information hygiene is by construction, not by type.** Strategies receive the full `PreferansSnapshot` (all hands, talon, discard) in every host; `HeuristicStrategy`, `DealSampler` and `forcedSettlement(knownTo:)` are written and tested not to read hidden cards, but a custom `PlayerStrategy` could. There is no projection-based bot API.
2. **Updated 2026-11-02:** production online bots use the difficulty selected per seat in the waiting room; the Worker forwards it to the existing engine, with adaptive temperament. Legacy bot seats default to seasoned. The in-memory harness still uses its default strategy. See [007](../007-online-waiting-room-bots/spec.md).
3. **Bots never propose settlements** and never use half-whist as a first defender (not legal for them) — by design; documented here for clarity.
4. **Bidding ignores context**: opponents' bids beyond legality, the score, pulka closing, and raspasy cost are not modelled; the final `if hasAffordableMisere` branch in `chooseBid` is unreachable (misère is already chosen earlier whenever affordable).
5. **Whist threshold uses `rules.whistRequirement` only**, so a totus `requireWhist` match without the rules flag treats 10-trick contracts as requirement 0 (share still clamps to 1).
6. **Rollout policy quirks**: `followCard`'s "lowest", "cheapest winner" and "highest loser" use `Card` ordering, which is suit-first (♠ < ♣ < ♦ < ♥) before rank, so off-suit discards are chosen by suit order rather than rank (e.g. a partner-winning defender may discard ♠A before ♥7 in a rollout).
7. **Discard ties** resolve by enumeration order; the evaluator does not value low trumps, so a declarer may discard a trump spot card (pinned by `testGameDiscardScoresAgainstDeclaredTrump`: 6♠ declarer discards ♥7 and ♠7).
8. **`HandEvaluator.expectedAllPassTricks` is unused** by any strategy.
9. **Determinism relies on the Swift standard library's `shuffle(using:)`** algorithm staying stable across toolchains and platforms (iOS, Linux server); the seed and sorted pool are pinned, the shuffle algorithm is not.
10. README says "Three- or four-seat bot spectator tables" — consistent with the lobby "Watch bots" path; the full spectator UI is documented in [`../005-ios-app`](../005-ios-app/).
