# Feature Specification: Preferans Rules Engine (game rules and deal state machine)

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `Sources/PreferansEngine/Domain.swift`, `State.swift`, `Rules.swift`, `MatchSettings.swift`, `PreferansEngine.swift`, `PreferansEngine+BiddingReducer.swift`, `PreferansEngine+ExchangeReducer.swift`, `PreferansEngine+WhistReducer.swift`, `PreferansEngine+PlayReducer.swift`, `PreferansEngine+SettlementReducer.swift`, `PreferansEngine+Invariants.swift`, `DealSource.swift`, `DealDeckLayout.swift`, `PreferansError.swift`, `EngineTransition.swift`, `PlayerIdentity.swift`

Companion documents: [data-model.md](./data-model.md) (every type, field, the full state machine, the complete invariant table, wire format) and [research.md](./research.md) (design decisions). Neighbouring areas: [002 scoring and variants](../002-scoring-and-variants/), [003 bots](../003-bots/), [004 online multiplayer](../004-online-multiplayer/), [005 iOS app](../005-ios-app/), [006 testing and release](../006-testing-and-release/).

## Summary

`PreferansEngine` is a pure-Swift, dependency-free, value-type reducer that implements one Preferans match. It deals a 32-card deck to three active seats (a fourth seat, when present, is the dealer and sits the deal out), runs the auction, the talon (prikup) exchange, contract declaration or the "without three" concession, the defenders' whist/pass/half-whist decisions and open/closed choice, trick play for suit, no-trump, misère and all-pass (raspasy) deals, optional early settlement ("claims") of the remaining tricks, and hands every finished deal to the scoring module ([002](../002-scoring-and-variants/)). The match ends (`gameOver`) when the configured pool (pulka) closes.

Every input is a `PreferansAction`; `apply(_:)` either throws a `PreferansError` and leaves the engine untouched, or moves to a new `DealState` and returns the `PreferansEvent`s that describe the move. After every successful action a full structural validator (`validateInvariants`) runs. A failure there traps, because it means an engine bug. The same validator gates rehydration from a `PreferansSnapshot`, which is how the online host recovers state that came across a trust boundary.

### Glossary

| Term | Meaning in this codebase |
|---|---|
| Seat order / `players` | The order of `PreferansEngine.players` is the clockwise seating order. All rotations are cyclic in this array. |
| Active players | The three seats that receive cards in a deal (`activePlayers`, always exactly 3). Index 0 is the **forehand** (senior hand, first to speak and first to lead). |
| Dealer | Deals the cards. At 3 players the dealer is active and is the last seat (index 2). At 4 players the dealer sits out and gets no cards. |
| Talon / prikup | The 2 undealt cards. |
| Discard | The 2 cards the declarer puts away after taking the talon. |
| Declarer | The auction winner. |
| Defenders | The two other active seats, in cyclic order after the declarer. |
| Whister | A defender who chose `whist` (or a half-whister who was overruled into play). |
| Half-whist | When the first defender passed, the second defender may accept half the defence without play on 6- and 7-level contracts. |
| Without three | The declarer gives up before naming a contract and is scored as three tricks short (`concedeWithoutThree`). |
| Passed out (`passedOut`) | **Both defenders passed** after the contract was declared, so the declarer is credited without play. This is **not** the all-pass deal. |
| All-pass / raspasy (`allPass`) | All three active seats passed in the auction. The deal is played with no trump, and everyone tries to take as few tricks as possible. |
| Misère | A contract to take zero tricks. It has no trump and no whist phase. |
| Totus | A 10-trick contract. By default it is just the 10-level of the ladder. Optionally (`TotusPolicy.dedicatedContract`) it is a separate bid that carries a pool bonus. |
| Settlement | The engine's name for a claim: agreeing on the final trick split and stopping play early. |
| Pulka / pool | The match-length target. It is closed through `MatchSettings.poolTarget` and `poolClosure`. |

Source file names given without a directory (for example `PreferansEngine.swift` or `BiddingReducer.swift`, short for `PreferansEngine+BiddingReducer.swift`) live in `Sources/PreferansEngine/`. Test paths in this document are relative to `Tests/`. The SwiftPM target for `Tests/PreferansEngineCoreTests/` is named `PreferansEngineTests`. The target for `Tests/PreferansEngineTests/` is the app test target `PreferansAppTests` (see `Package.swift`).

## User Scenarios & Testing

### User Story 1 – Deal a hand at a 3- or 4-seat table (Priority: P1)

A table host starts a deal, and every active seat receives exactly 10 cards with 2 left in the talon. Dealer duty rotates around the whole table. At 4 seats the dealer sits out.

**Why this priority**: Every other phase depends on a correct deal and rotation.

**Independent Test**: Build an engine with 3 or 4 `PlayerID`s, call `startDeal(deck: Deck.standard32)` and inspect `BiddingState`.

**Acceptance Scenarios**:

1. **Given** players `[north, east, south, west]` and first dealer `north`, **When** a deal starts, **Then** the event is `dealStarted(dealer: north, activePlayers: [east, south, west])`, `north` holds no hand, each active seat holds 10 cards, the talon holds 2, and `nextDealer == east` (`PreferansEngineCoreTests/PreferansEngineTests.swift::testDealUsesDealerRotationAndFourPlayerSitOut`).
2. **Given** players `[north, east, south]` and dealer `north`, **When** a deal starts, **Then** `activePlayers == [east, south, north]` (the dealer is last) and `east` is the first to bid (`PreferansEngineTests.swift::testAllPassLeadStartsWithForehandAtThreePlayersAndDealerAtFour`).
3. **Given** a 4-seat table, **When** four consecutive deals are played, **Then** the dealers are `north, east, south, west` and each deal's sit-out seat equals that deal's dealer (`PreferansEngineTests/ScenarioFlowTests.swift::testFourPlayerDealerAndSitOutRotateAcrossFourConsecutiveDeals`).
4. **Given** two `SeededDealSource(seed: 12345)` instances, **When** each feeds an engine, **Then** both engines deal identical hands and talons (`PreferansEngineCoreTests/DealSourceTests.swift::testSeededDealSourceFeedsTheEngineDeterministically`).
5. **Given** a match whose pulka has closed (`gameOver`), **When** `startDeal` is applied, **Then** `invalidState(expected: "waitingForDeal or dealFinished", actual: "gameOver (match closed)")` is thrown (`MatchSettingsTests.swift::testStartDealFromGameOverThrows`).

### User Story 2 – Run the auction (Priority: P1)

Active seats bid in turn, starting with the forehand, on the ladder 6♠ … 8NT, misère, [totus], 9♠ … 10NT. They may pass (a pass is permanent). The senior hand may hold an equal bid, and misère may only be a player's first bid.

**Why this priority**: The auction decides the contract, the declarer and whether the deal is an all-pass deal.

**Independent Test**: Drive `.bid` actions and inspect `legalBidCalls(for:)` and the resulting state.

**Acceptance Scenarios**:

1. **Given** dealer `north` (rotation `east, south, north`), **When** `east` bids 6♣, `south` bids 6♦ and `north` passes, **Then** `east` (senior) is offered and may bid 6♦ again (a hold). `south` is then not offered 6♦, is offered 6♥ and pass, and gets `illegalBid` for 6♦. After `south` passes the events contain `auctionWon(declarer: east, bid: 6♦)` (`PreferansEngineTests.swift::testSeniorHandMayHoldEqualBidAndJuniorMustRaise`).
2. **Given** `PreferansRules(allowSeniorHandHoldBid: false)` and the same auction, **When** `east` is to call, **Then** 6♦ is not legal and 6♥ and pass are (`::testHoldBidDisabledForcesSeniorHandToRaiseOrPass`).
3. **Given** all three active seats pass, **When** the third pass is applied, **Then** the events contain `allPassed` and `playStarted(.allPass(...))`, and play starts with the forehand to act (`::testAllPassStartsAllPassPlay`).
4. **Given** the Sochi raspasy policy and `consecutiveAllPassDeals` = 0, 1, 2, 8, **When** the forehand's legal calls are listed, **Then** the legal game levels are {6–10}, {7–10}, {8–10}, {8–10}, and misère is legal at every stage (`MatchSettingsTests.swift::testStrictRaspasyExitFiltersSixThenSevenLevelGamesButKeepsMisere`).
5. **Given** `TotusPolicy.dedicatedContract`, **When** a seat may bid, **Then** `.totus` is offered and no 10-level game bid is. Under `asTenTrickGame`, `.totus` is not offered and 10♠ is (`MatchSettingsTests.swift::testTotusBidIsLegalAndTenTrickGamesSuppressedUnderDedicatedPolicy`, `::testTotusBidIsIllegalWhenPolicyIsAsTenTrickGame`).
6. **Given** `north` bid totus in a dedicated-totus match, **When** `east` is to call, **Then** 9♠ is legal. After `east` bids 9♠, `south` may not bid totus (`::testNineSpadesCanOvercallTotusButTotusCannotOvercallNineSpades`).

### User Story 3 – Take the talon, discard, then declare or concede (Priority: P1)

The declarer picks up the talon, discards any 2 of the 12 cards, and then either names the final contract (no lower than the winning bid) or concedes "without three". Misère skips the declaration and goes straight to play.

**Why this priority**: This sets the contract that is played and scored.

**Independent Test**: Win an auction, apply `.discard` and then `.declareContract` or `.concedeWithoutThree`.

**Acceptance Scenarios**:

1. **Given** `east` won with 6♣, **When** `east` discards two cards and concedes without three, **Then** the events contain `contractConcededWithoutThree(declarer: east, bid: 6♣)`. The result kind is `.withoutThree`, `east` gets 6 mountain (value 2 × 3) and 0 pool, no whists are written, every trick count is 0, and `initialHands` equals the dealt hands (`PreferansEngineTests.swift::testDeclarerCanConcedeWithoutThreeBeforeNamingContract`).
2. **Given** a 4-seat table where `east` concedes 6♣ without three, **Then** only `east` is charged (6 mountain), and the sitting-out dealer and both defenders write nothing (`::testWithoutThreeInFourPlayerDealScoresDeclarerTripleAndDealerNothing`).
3. **Given** a recovered `awaitingContract` state whose final bid is misère, **When** `concedeWithoutThree` is applied, **Then** `invalidContract` is thrown and the state is unchanged (`::testConcedeWithoutThreeIsRejectedForMisere`).
4. **Given** a dedicated-totus auction won by `north`, **When** `north` discards, **Then** the state is `awaitingContract` and `legalContractDeclarations` lists exactly the five 10-trick contracts (`MatchSettingsTests.swift::testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin`).
5. **Given** a 10♠ declaration under default Sochi rules, **When** it is declared, **Then** play starts immediately with `whisters == []`, `whistCalls == []`, `defenderPlayMode == .open`, and all three active seats are settlement parties (`PreferansEngineTests.swift::testTenTrickContractUsesOpenCheckByDefault`, `MatchSettingsTests.swift::testTenTrickGameStartsPlayWithoutWhist`).

### User Story 4 – Defenders decide whist, pass or half-whist, then open or closed (Priority: P1)

After a non-ten contract is declared (or a ten under the whist convention), the first defender and then the second defender each choose. The outcome is closed play with two whisters, a choice of open or closed play for a lone whister, an award without play (both pass), or a half-whist award.

**Why this priority**: It decides whether and how the deal is played.

**Independent Test**: Declare a contract, then drive `.whist` and `.chooseDefenderMode`.

**Acceptance Scenarios**:

1. **Given** `east` declared 6♣ and `south` (first defender) passed, **When** `north` half-whists and `south` then passes, **Then** the result is `.halfWhist(declarer: east, contract: 6♣, halfWhister: north)`, `east` gets pool 2, and `north` writes 4 whists on `east` (`PreferansEngineTests.swift::testHalfWhistRequiresFirstDefenderSecondChanceAndScores`).
2. **Given** the same half-whist position, **When** `south` whists instead, **Then** closed play starts with `whisters == [south, north]` (`::testFirstDefenderMayRevokePassByWhistingOverHalfWhist`).
3. **Given** Stalingrad rules (`forceWhistOnSixSpades`) and a 6♠ contract, **When** either defender is to call, **Then** the only legal call is `.whist`, `.pass` throws, and play is closed with both whisters (`::testStalingradSixSpadesForcesClosedWhistFromBothDefenders`). Without Stalingrad, 6♠ offers `[.pass, .whist]` (`::testSixSpadesUsesOrdinaryWhistChoicesWithoutStalingrad`).
4. **Given** Leningrad rules (ten-trick whist convention) and a 10♣ contract, **When** the defenders call, **Then** each is offered `[.pass, .whist]` (never half-whist). Two whists start play with both as whisters (`::testLeningradTenLetsBothDefendersChooseWhistAndPlayClosed`). Two passes give `.passedOut` and 10 pool to the declarer (`::testTenTrickWhistConventionOffersNormalPassAndWhistChoices`).
5. **Given** both defenders pass a 6♣ contract, **Then** the deal finishes as `.passedOut` and the declarer gets 2 pool (`MatchSettingsTests.swift::testUnboundedMatchNeverFiresGameOver`).

### User Story 5 – Play tricks (Priority: P1)

Seats play one card at a time. They must follow suit, must trump when void (in a trump contract), and the trick winner leads next. The deal ends after 10 tricks.

**Why this priority**: This is the core gameplay loop.

**Independent Test**: Use `EngineTestDriver.playOut(engine:policy:)` with `legalCards(for:)`.

**Acceptance Scenarios**:

1. **Given** a seat holding a card of the led suit, **When** it tries to play another suit, **Then** `illegalCardPlay` is thrown (`PreferansEngineTests/ScenarioFlowTests.swift::testEastCannotSluffWhenHoldingALeadSuitCard`).
2. **Given** the lead is the ace of trumps, **When** the trick completes, **Then** the leader wins and leads again (`ScenarioFlowTests.swift::testFirstTrickIsWonByLeadAceOfTrumpsAndRotatesLead`).
3. **Given** a 6♣ contract played closed by two whisters with lowest-legal play from `Deck.standard32`, **When** play completes, **Then** `trickCounts == [east: 3, south: 1, north: 6]` and the result is `.game(declarer: east, contract: 6♣, whisters: [south, north])` (`PreferansEngineTests.swift::testFirstDefenderMayRevokePassByWhistingOverHalfWhist`).
4. **Given** open single-whist play under greedy scoring, **When** it is the passer's turn, **Then** `legalCards(for: whister)` returns the passer's legal cards and `legalCards(for: passer)` is empty. Under closed mode the passer keeps control (`PreferansEngineTests/SingleWhistControlTests.swift`).
5. **Given** a misère where the declarer is forehand, **When** no card has been played, **Then** `misereDefendersAreOpen == false`. After the declarer's first card it is `true` and stays `true` after a snapshot round trip (`PreferansEngineCLITests/MisereVisibilityTests.swift::declarerLeads`).

### User Story 6 – Play an all-pass deal (raspasy) (Priority: P1)

After three passes, everyone plays to avoid tricks. Depending on the talon policy, the two talon cards set the suit of the first two tricks. At 4 seats under the classic policy, the sitting-out dealer "plays" those talon cards and can win the tricks.

**Why this priority**: All-pass deals are frequent, and they drive the raspasy progression.

**Independent Test**: Make all three seats pass, then play out.

**Acceptance Scenarios**:

1. **Given** a 3-seat Sochi table, **When** all pass, **Then** `leader == currentPlayer == forehand`. At 4 seats, `leader == dealer` and `currentPlayer == forehand` (`PreferansEngineTests.swift::testAllPassLeadStartsWithForehandAtThreePlayersAndDealerAtFour`).
2. **Given** a 4-seat Sochi raspasy with talon `[A♠, 7♥]` and a forehand void in spades, **When** trick 1 is played, **Then** the talon suit (♠) stays the required suit for everyone and the dealer `north` wins with A♠. Trick 2 is led by the talon 7♥ with the forehand acting first. Trick 3 is started by the forehand whoever won trick 2. The final trick counts include `north` (`::testFourPlayerRaspasyDealerOwnsTalonTricksAndForehandResets`).
3. **Given** Rostov rules (`allPassTalonPolicy: .ignored`), **When** all pass, **Then** the talon is kept in state but never leads (`currentTalonLead == nil`) and the forehand leads (`::testRostovAllPassKeepsTalonHiddenAndStartsFromForehand`).
4. **Given** two consecutive all-pass deals under Sochi, **When** they are scored, **Then** `consecutiveAllPassDeals` goes 1, then 2 (prices 1 and 2), survives a snapshot round trip, allows an 8-level exit bid, and resets to 0 after a non-all-pass result (`MatchSettingsTests.swift::testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`).

### User Story 7 – Settle the remaining tricks early (claims) (Priority: P2)

In an open game, an open ten-trick check, or a misère, a contesting party may propose a final trick split between tricks. Play stops only when every contesting party accepts.

**Why this priority**: It is a convenience feature. Games are always completable by play.

**Independent Test**: Reach an open game or misère and apply `proposeSettlement`, `acceptSettlement` and `rejectSettlement`.

**Acceptance Scenarios**:

1. **Given** an open game, **Then** the declarer and the whister may offer and the passed defender may not. A misère lets all three offer. Closed games and all-pass deals offer nothing, and proposing in a closed game is rejected (`PreferansEngineTests/SettlementTests.swift`: `openGameSettlementRoleGating`, `misereSettlementRoleGating`, `closedGameOffersNoSettlement`, `allPassOffersNoSettlement`, `proposingInClosedGameRejected`).
2. **Given** a pending proposal, **When** every settlement party has accepted, **Then** the events end `playSettled`, `dealScored` and the result's `trickCounts` equals the agreed split while `completedTricks` keeps only the tricks that were really played (`SettlementTests.swift::unanimousSettlementScoresDeal`).
3. **Given** a pending proposal, **When** any party rejects, **Then** the proposal is cleared and card play resumes (`::rejectingSettlementResumesCardPlay`).
4. **Given** any valid split (not only the suggested anchors), **When** it is proposed and accepted, **Then** it is scored (`::anyValidConfigurationIsAccepted`). Impossible splits are rejected (`::settlementRejectsImpossibleFinalCounts`).
5. **Given** the last trick, **When** suggestions are computed for a defender, **Then** they never depend on the declarer's hidden card unless every possible hidden allocation gives the same outcome (`PreferansEngineCoreTests/SettlementInformationTests.swift`).

### User Story 8 – Close the match (Priority: P2)

Deals continue until the pool closure policy is met. The engine then enters `gameOver` with a ranked `MatchSummary`.

**Why this priority**: Bounded matches are the shipped product mode. Unbounded play is available for practice.

**Independent Test**: Use a small `poolTarget` and drive passed-out contracts.

**Acceptance Scenarios**:

1. **Given** `MatchSettings(poolTarget: 2, poolClosure: .tableTotal)`, **When** a 6♣ contract is passed out (pool +2), **Then** the events contain `matchEnded`, the state is `gameOver`, `dealsPlayed == 1`, and `north` tops the standings while `east` and `south` keep seat order on equal balance (`MatchSettingsTests.swift::testGameOverFiresWhenPoolSumCrossesTargetExactly`, `::testMatchSummaryStandingsAreSortedByBalanceWithDeterministicTiebreak`).
2. **Given** the unbounded default, **Then** `gameOver` never occurs (`::testUnboundedMatchNeverFiresGameOver`).
3. **Given** individual closure with target 6 at 3 seats, **When** three 6-level contracts are passed out by different declarers, **Then** all balances are 0, `leadingPlayers == [north, east, south]`, `soleWinner == nil` and every rank is 1 (`MatchOutcomeTests.swift::testThreeEqualPoolsShareTheLeadAndProjectionNamesNoSoleWinner`).
4. **Given** individual closure at a 3-seat table, **When** the engine is built with `poolTarget: 10` (not divisible by 3), **Then** construction throws `invalidMatch` mentioning "divide evenly" (`MatchSettingsTests.swift::testIndividualClosureRejectsATargetThatCannotDivideAcrossSeats`).

### User Story 9 – Recover a match from a snapshot (Priority: P1)

A host persists `PreferansSnapshot` and later rehydrates it. Corrupted or forged snapshots must be rejected before any action runs.

**Why this priority**: Online rooms recover from storage, and the snapshot crosses a trust boundary.

**Independent Test**: `PreferansEngine(snapshot:)` on valid and single-mutation-invalid snapshots.

**Acceptance Scenarios**:

1. **Given** any position reached by seeded random legal play, **When** the snapshot is validated, JSON-encoded, decoded and rehydrated, **Then** it is accepted and equal to the original. This is checked at every one of up to 180 steps for 2 configurations × 18 seeds (`PreferansEngineCLITests/EngineGenerativeTests.swift::walkPreservesInvariants`).
2. **Given** a bidding snapshot whose `significantBidByPlayer` forgets a real bid (which would reopen misère), **When** it is rehydrated, **Then** an `InvariantViolation` containing "significant bid ledger" is thrown (`InvariantValidatorTests.swift::testSnapshotRehydrationRejectsAuctionLedgerThatWouldReopenMisere`).
3. **Given** a playing snapshot with a forged next actor, a forged trick winner, a historical revoke or negative counts, **Then** rehydration or validation is rejected (see the invariant table in [data-model.md](./data-model.md#invariants)).

### User Story 10 – Reproducible and scripted deals (Priority: P3)

Tests and hosts inject decks through `DealSource`. The decks are random, seeded (deterministic on every platform) or scripted (cycling).

**Why this priority**: It enables deterministic tests, fixtures and server-side seeded shuffles.

**Independent Test**: `DealSourceTests`.

**Acceptance Scenarios**:

1. **Given** seed 42, **Then** two `SeededRandomNumberGenerator`s produce the same first 32 values. Seeds 42 and 43 differ (`DealSourceTests.swift::testSeededRandomNumberGeneratorIsDeterministicForSameSeed`, `::…DivergesForDifferentSeeds`).
2. **Given** `ScriptedDealSource(decks: [A, B])`, **Then** it yields A, B, A, and 100 concurrent requests split exactly 50/50 (`::testScriptedDealSourceCyclesThroughGivenDecks`, `::testScriptedDealSourceSerializesConcurrentRequests`).
3. **Given** `SeededDealSource(seed: 2026)` and 32 concurrent requests, **Then** all 32 decks are distinct valid permutations (`::testSeededDealSourceSerializesConcurrentRequests`).

### Edge Cases

- **A pass is final.** A seat that passed is skipped for the rest of the auction (`nextBidder`) and may not bid again. The ledger invariant rejects any recorded call after a pass.
- **Bidding after two passes.** If two seats pass and the third bids, the third seat wins immediately with that bid. If the third also passes, the deal is all-pass.
- **Misère bidder.** After bidding misère a seat can only pass. Misère can never be held (the hold rule applies to game bids only).
- **Totus is not the top bid.** In dedicated-totus mode the order is … 8NT < misère < totus < 9♠ … 9NT, and the 10-level game bids are removed. A 9-level game bid therefore overcalls totus, and 9NT is the highest legal bid.
- **Declaring above the bid.** Declaration may name any contract ≥ the winning game bid, including 10-level contracts. In a dedicated-totus match this lets a 9-level winner declare a 10-level game without the totus bonus (see Known Gaps).
- **Discarding the talon itself.** The declarer may discard the two talon cards and keep the original hand. The talon stays recorded in state after the exchange.
- **10-trick contracts never allow half-whist** (half-whist needs `tricks ≤ 7`). With the convention off they skip the whist phase and start as an open check that every seat verifies.
- **Two whisters always play closed.** Only a lone whister chooses `.open` or `.closed`.
- **Open single whist under non-greedy scoring** (`ownHandOnly` or `gentleman`, as in Rostov and Leningrad). The passer's hand is exposed, but the passer still plays it. The whister controls the passer's cards only under `greedy`.
- **Talon-led raspasy where nobody can follow the talon suit.** Any card may be played. Because the talon card is not a contender at 3 seats (or under `leadSuitOnly`), the comparator keeps the first played card as the running winner and only a higher card of that same suit replaces it. In effect the highest card in the forehand's suit wins. Under classic 4-seat raspasy the talon card itself is first, so the dealer wins.
- **Forehand reset.** Under `classic` and `leadSuitOnly`, tricks 1, 2 and 3 are all started by the forehand whoever won tricks 1 and 2. From trick 4, the previous winner leads.
- **Settlement proposals** are allowed only between tricks (empty current trick). While one is pending no card may be played, and the clock passes to the first party (in seat order) who has not yet accepted. The proposer is recorded as already accepted. Any party, the proposer included, may reject, which withdraws the proposal.
- **The settlement `target`** must be an active seat whose count matches `targetTricks`, but it is not required to be the declarer. Scoring uses only `finalTrickCounts`.
- **Spoofed `startDeal`.** `startDeal` has `actor == nil` and attacker-controllable `dealer` and `deck`. Hosts must overwrite both before applying it (see FR-069).
- **Saturating counter.** `consecutiveAllPassDeals` saturates at `Int.max`, and the progressions clamp at their last stage.

## Requirements

### Functional Requirements

#### Table setup and seating

- **FR-001**: The system MUST accept exactly 3 or 4 players with unique `PlayerID`s, otherwise throwing `invalidPlayers("PreferansEngine requires exactly 3 or 4 players.")` or `invalidPlayers("PlayerID values must be unique.")`. — `Sources/PreferansEngine/PreferansEngine.swift` `PreferansEngine.validate(players:)`.
- **FR-002**: The system MUST forbid empty `PlayerID`s: a `precondition` in `init(_:)` and a `DecodingError` when decoding. — `Sources/PreferansEngine/Domain.swift` `PlayerID`; test `PreferansEngineTests.swift::testDomainDecodersRejectValuesThatPublicInitializersForbid`.
- **FR-003**: The system MUST use `firstDealer ?? players[0]` as the first dealer and throw `invalidPlayer` if it is not seated. — `PreferansEngine.swift` `PreferansEngine.init(players:rules:match:firstDealer:)`.
- **FR-004**: The system MUST compute the active rotation for dealer *d* at seat index *i* as `players[i+1…] + players[…<i]`, with *d* appended at 3 seats and omitted at 4 seats. Index 0 is the forehand. — `PreferansEngine.swift` `activePlayers(forDealer:)`; tests `::testDealUsesDealerRotationAndFourPlayerSitOut`, `::testAllPassLeadStartsWithForehandAtThreePlayersAndDealerAtFour`.
- **FR-005**: The system MUST set `nextDealer = players.cyclicNext(after: dealer)` on every `startDeal`, whether the dealer was supplied or defaulted. — `PreferansEngine.swift` `reduceStartDeal`; tests `::testDealUsesDealerRotationAndFourPlayerSitOut`, `ScenarioFlowTests.swift::testFourPlayerDealerAndSitOutRotateAcrossFourConsecutiveDeals`.
- **FR-006**: The system MUST validate `PreferansRules.configurationError` and `MatchSettings.configurationError(playerCount:)` at construction and on rehydration, throwing `invalidRules(msg)` or `invalidMatch(msg)`. — `PreferansEngine.swift` `validate(rules:)`, `validate(match:playerCount:)`; tests `PreferansEngineTests.swift::testEngineRejectsRulesMutatedAfterInitialization`, `::testEngineRejectsMutatedAllPassPenaltyMultiplier`, `MatchSettingsTests.swift::testEngineRejectsNegativeDedicatedTotusBonus`.

#### Deck and dealing

- **FR-007**: The system MUST use the 32-card deck of 4 suits × 8 ranks. Suit rank (also the bidding order) is ♠ (0) < ♣ (1) < ♦ (2) < ♥ (3). Card rank is 7 < 8 < 9 < 10 < J < Q < K < A (raw values 7…14). The canonical card order is suit first, then rank (`Deck.standard32` is sorted this way). — `Domain.swift` `Suit`, `Rank`, `Card`, `Deck.standard32`.
- **FR-008**: The system MUST allow `startDeal` only from `waitingForDeal` or `dealFinished`, otherwise throwing `invalidState(expected: "waitingForDeal or dealFinished", actual: <state>)`, where `<state>` is `"gameOver (match closed)"` for `gameOver`. — `PreferansEngine.swift` `reduceStartDeal`, `canStartDeal`; test `MatchSettingsTests.swift::testStartDealFromGameOverThrows`.
- **FR-009**: The system MUST validate a supplied deck in this order: count = 32, else `invalidDeck("Deck must contain 32 cards.")`; no duplicates, else `duplicateCards(sortedDuplicates)`; equal to the standard set, else `invalidDeck("Deck must contain the standard Preferans cards.")`. — `PreferansEngine.swift` `preparedDeck(_:)`.
- **FR-010**: The system MUST shuffle `Deck.standard32` with the system RNG when no deck is supplied. — `PreferansEngine.swift` `preparedDeck(_:)`.
- **FR-011**: The system MUST deal 5 packets of 2 cards to each active seat in rotation order, putting the next 2 cards into the talon right after the first packet. Each hand is then sorted canonically. Deck indices: seat 0 gets {0,1,8,9,14,15,20,21,26,27}, seat 1 gets {2,3,10,11,16,17,22,23,28,29}, seat 2 gets {4,5,12,13,18,19,24,25,30,31}, and the talon is {6,7}. `DealDeckLayout.deck(hands:talon:activePlayers:)` is the exact inverse. — `Sources/PreferansEngine/DealDeckLayout.swift` `DealDeckLayout.deal(deck:activePlayers:)`; test `ScenarioFlowTests.swift::testNorthSpadesSixScenarioDealsTheExpectedHandsAndTalon`.
- **FR-012**: The system MUST provide `DealSource` implementations: `RandomDealSource` (system RNG), `SeededDealSource` (xoshiro256** seeded through SplitMix64, where seed 0 is replaced by `0x9E3779B97F4A7C15`) and `ScriptedDealSource` (cycles through its decks modulo count). The last two serialize access with an `NSLock`. — `Sources/PreferansEngine/DealSource.swift`; tests `DealSourceTests.swift` (all 9).
- **FR-013**: The system MUST enter `bidding` with `currentPlayer = activePlayers[0]` and no calls, and emit `[dealStarted(dealer:activePlayers:)]`. — `PreferansEngine.swift` `reduceStartDeal`.

#### Auction

- **FR-014**: The system MUST order bids strictly by `ContractBid.order`. For game bids this is `GameContract.bidOrder = (tricks−6)·5 + strainOrder`, plus 2 when `tricks ≥ 9`, with strain order ♠0 ♣1 ♦2 ♥3 NT4. Misère is 15 and totus is 16 (full table in [Appendix A](#appendix-a--bidding-ladder)). — `Domain.swift` `GameContract.bidOrder`, `ContractBid.order`; tests `PreferansEngineTests.swift::testContractOrderingPlacesMisereBetweenEightNoTrumpAndNineSpades`, `MatchSettingsTests.swift::testTotusOrderingPlacesItDirectlyAboveMisere`.
- **FR-015**: The system MUST reject a `.bid` action outside `bidding` (`invalidState(expected: "bidding")`) or from anyone but `currentPlayer` (`notPlayersTurn(expected:actual:)`). — `Sources/PreferansEngine/PreferansEngine+BiddingReducer.swift` `reduceBid`.
- **FR-016**: The system MUST treat `.pass` as always legal for the current bidder and permanent: the seat joins `passed` and `nextBidder` skips it from then on. — `BiddingReducer.swift` `reduceBid`; `PreferansEngine.swift` `nextBidder(after:in:)`.
- **FR-017**: The system MUST accept a bid only if it is strictly above `highestBid` (any bid is acceptable when there is none yet), subject to FR-018 to FR-021. Otherwise it throws `illegalBid("<bid> is not legal for <player>.")`. — `PreferansEngine.swift` `isLegalBid(_:by:in:)`.
- **FR-018**: The system MUST allow a bid *equal* to `highestBid` only when all of these hold: `rules.allowSeniorHandHoldBid` is true (the default), the bid is a game bid (not misère or totus), exactly 2 seats have not passed, and the bidder sits earlier in `activePlayers` than `highestBidder`. — `PreferansEngine.swift` `isLegalBid`, `isOlderHand`; tests `PreferansEngineTests.swift::testSeniorHandMayHoldEqualBidAndJuniorMustRaise`, `::testHoldBidDisabledForcesSeniorHandToRaiseOrPass`.
- **FR-019**: The system MUST allow misère only as a seat's first bid (`significantBidByPlayer[player] == nil`) and MUST forbid any further bid from a seat whose recorded bid is misère. — `PreferansEngine.swift` `isLegalBid`; invariant `checkBiddingLedger`; test `InvariantValidatorTests.swift::testSnapshotRehydrationRejectsAuctionLedgerThatWouldReopenMisere`.
- **FR-020**: The system MUST forbid game bids with `tricks < match.raspasy.minimumGameTricks(after: consecutiveAllPassDeals)`. Misère and totus are exempt. — `PreferansEngine.swift` `isLegalBid`; `MatchSettings.swift` `RaspasyPolicy.minimumGameTricks(after:)`; tests `MatchSettingsTests.swift::testStrictRaspasyExitFiltersSixThenSevenLevelGamesButKeepsMisere`, `::testRaspasyProgressionsExposeSupportedPriceAndExitStages`.
- **FR-021**: The system MUST make `.totus` legal only when `match.totus.isDedicated`. In that mode it MUST remove all 10-level `.game` bids from the auction. — `PreferansEngine.swift` `isLegalBid`; tests `MatchSettingsTests.swift::testTotusBidIsIllegalWhenPolicyIsAsTenTrickGame`, `::testTotusBidIsLegalAndTenTrickGamesSuppressedUnderDedicatedPolicy`.
- **FR-022**: The system MUST NOT force any opening bid. The forehand may pass, and the lowest legal game bid is 6♠, or the raspasy minimum level in ♠.
- **FR-023**: The system MUST end the auction as all-pass when no bid exists and every active seat has passed. It enters `playing` with `kind = .allPass(AllPassPlayContext(talonPolicy: rules.allPassTalonPolicy))` and an empty discard, and emits `[bidAccepted, allPassed, playStarted(kind)]`. — `BiddingReducer.swift` `reduceBid`; test `PreferansEngineTests.swift::testAllPassStartsAllPassPlay`.
- **FR-024**: The system MUST end the auction as won when a bid exists and exactly one seat has not passed. It enters `awaitingDiscard(ExchangeState)` with `declarer = highestBidder`, `finalBid = highestBid` and `auction = calls`, and emits `[bidAccepted, auctionWon(declarer:bid:)]`. — `BiddingReducer.swift` `reduceBid`.
- **FR-025**: The system MUST otherwise advance `currentPlayer` to the next seat in `activePlayers` that has not passed, emitting `[bidAccepted]`. `legalBidCalls(for:)` MUST return `[.pass] + every legal ContractBid.allStandard bid in ladder order` for the current bidder, and `[]` for anyone else. — `PreferansEngine.swift` `legalBidCalls(for:)`.

#### Talon exchange, declaration and concession

- **FR-026**: The system MUST accept `.discard` only in `awaitingDiscard` and only from the declarer. Exactly 2 cards are required (`illegalCardPlay("Discard must contain exactly two cards.")`), they must be distinct (`duplicateCards(cards)`) and each must come from hand + talon (`cardNotInHand(player:card:)`). The declarer keeps the remaining 10 cards, sorted. — `Sources/PreferansEngine/PreferansEngine+ExchangeReducer.swift` `reduceDiscard`; test `PreferansEngineTests.swift::testDealResultKeepsOpeningHandsAfterDeclarerKeepsPrikupCards`.
- **FR-027**: The system MUST keep the original `talon` in every later deal state and record the 2-card `discard`, emitting `talonExchanged(declarer:talon:discard:)`. — `ExchangeReducer.swift` `reduceDiscard`.
- **FR-028**: The system MUST start play immediately after a misère discard (`kind = .misere(declarer)`, events `[talonExchanged, playStarted]`), with no declaration and no whist phase. — `ExchangeReducer.swift` `reduceDiscard`; test `ScenarioFlowTests.swift::testMiserePlayOutEndsAtDealFinishedWithMisereResult`.
- **FR-029**: The system MUST move a game or totus auction to `awaitingContract` after the discard (events `[talonExchanged]`). — `ExchangeReducer.swift` `reduceDiscard`.
- **FR-030**: The system MUST accept `.declareContract` only in `awaitingContract` and only from the declarer. For a game final bid the contract must be ≥ the bid (`invalidContract("Declared contract cannot be below the auction bid.")`), with any strain and any level up to 10. For totus the contract must have 10 tricks (`invalidContract("Totus declaration must be a 10-trick contract.")`) and it carries `bonusPoolOnSuccess = match.totus.bonusPool`. Misère must be rejected (`invalidContract("Misere does not enter contract declaration.")`). `legalContractDeclarations(for:)` MUST list exactly these options. — `ExchangeReducer.swift` `reduceDeclareContract`; `PreferansEngine.swift` `legalContractDeclarations(for:)`; test `MatchSettingsTests.swift::testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin`.
- **FR-031**: The system MUST order the defenders as the active seats in cyclic order after the declarer. For example, with active `[e, s, n]` the declarer `s` has defenders `[n, e]`. — `PreferansEngine.swift` `defenders(after:activePlayers:)`; invariant `checkDefendingSide`.
- **FR-032**: The system MUST start a declared 10-trick contract immediately as an **open check** when neither `rules.requireWhistOnTenTrickContracts` nor `match.totus.requireWhistOnTenTricks` is set: `whisters = []`, `whistCalls = []` and `defenderPlayMode = .open`, with events `[contractDeclared, playStarted]`. — `ExchangeReducer.swift` `reduceDeclareContract`; `PreferansEngine.swift` `requiresWhistOnTenTricks`; tests `PreferansEngineTests.swift::testTenTrickContractUsesOpenCheckByDefault`, `MatchSettingsTests.swift::testTenTrickGameStartsPlayWithoutWhist`.
- **FR-033**: The system MUST otherwise enter `awaitingWhist` with `currentPlayer = defenders[0]`, `flow = .normal` and the bonus carried forward (events `[contractDeclared]`). — `ExchangeReducer.swift` `reduceDeclareContract`; tests `PreferansEngineTests.swift::testTenTrickWhistConventionOffersNormalPassAndWhistChoices`, `::testTotusPolicyRequireWhistEnablesWhistDecisionWithoutRulesFlag`.
- **FR-034**: The system MUST let the declarer `concedeWithoutThree` in `awaitingContract` for any final bid except misère (`invalidContract("Misere does not support without-three concession.")`). The deal is scored through `PreferansScoring.withoutThree` (mountain = `finalBid.value × mountainValueMultiplier × 3`) and finalized, with events `[contractConcededWithoutThree, dealScored, (matchEnded)]`. — `ExchangeReducer.swift` `reduceConcedeWithoutThree`; tests `PreferansEngineTests.swift::testDeclarerCanConcedeWithoutThreeBeforeNamingContract`, `::testConcedeWithoutThreeIsRejectedForMisere`, `::testWithoutThreeInFourPlayerDealScoresDeclarerTripleAndDealerNothing`.

#### Whist decisions

- **FR-035**: The system MUST offer whist calls by the matrix in [Appendix B](#appendix-b--whist-decision-matrix) and reject others with `illegalWhist("<call> is not legal for <player>.")`. In short: Stalingrad 6♠ allows only `[.whist]`; the second chance allows `[.pass, .whist]`; the first defender is offered `[.pass, .whist]`; the second defender is offered `[.pass, .halfWhist, .whist]` only if the first passed and `tricks ≤ 7`, otherwise `[.pass, .whist]`. — `PreferansEngine.swift` `legalWhistCalls(in:for:)`; `Sources/PreferansEngine/PreferansEngine+WhistReducer.swift` `reduceWhist`.
- **FR-036**: The system MUST resolve whist calls as follows. Any first-defender call moves to the second defender. Pass + pass → `passedOut` scored. Pass + whist → `awaitingDefenderMode(whister: second)`. Pass + half-whist → back to the first defender with `flow = .firstDefenderSecondChance(halfWhister: second)`. Whist + pass → `awaitingDefenderMode(whister: first)`. Whist + whist → closed play with `whisters [first, second]`. On the second chance, pass → `halfWhist` scored, and whist → closed play with `whisters [first, halfWhister]`. — `WhistReducer.swift` `reduceWhist`; tests `PreferansEngineTests.swift::testHalfWhistRequiresFirstDefenderSecondChanceAndScores`, `::testFirstDefenderMayRevokePassByWhistingOverHalfWhist`.
- **FR-037**: The system MUST, when `rules.forceWhistOnSixSpades` is set and the contract is exactly 6♠, offer only `.whist` to both defenders, which leads to closed two-whister play. — `PreferansEngine.swift` `isStalingradContract`; tests `PreferansEngineTests.swift::testStalingradSixSpadesForcesClosedWhistFromBothDefenders`, `::testSixSpadesUsesOrdinaryWhistChoicesWithoutStalingrad`.
- **FR-038**: The system MUST let only the lone whister choose `.open` or `.closed` in `awaitingDefenderMode` (`notPlayersTurn` for anyone else). Play then starts with `whisters = [whister]` and events `[defenderModeChosen, playStarted]`. Two-whister play MUST always be `.closed`. — `WhistReducer.swift` `reduceChooseDefenderMode`.

#### Trick play (game and misère)

- **FR-039**: The system MUST start every play kind with `currentPlayer = activePlayers[0]` (the forehand). `leader` is also the forehand, except in classic 4-seat raspasy where it is the dealer. — `PreferansEngine.swift` `makePlayingState`.
- **FR-040**: The system MUST accept `.playCard` only in `playing`, only with no pending settlement (`illegalSettlement("A settlement proposal is awaiting responses.")`), only from `currentPlayer` (`notPlayersTurn`), only for a card in that hand (`cardNotInHand`) and only when it is legal (`illegalCardPlay("<card> is not legal for <player>.")`). Play rotates through `activePlayers` cyclically. — `Sources/PreferansEngine/PreferansEngine+PlayReducer.swift` `reducePlayCard`.
- **FR-041**: The system MUST enforce card legality as follows. If a required suit exists and the hand holds it, the card must be of that suit. Else, if there is a trump that differs from the required suit and the hand holds trump, the card must be trump. Otherwise any card is legal. The first card of an ordinary trick is free. There is no obligation to overtake or overtrump. — `PreferansEngine.swift` `isLegal(card:by:in:)`, `PlayingState.requiredSuit`; test `ScenarioFlowTests.swift::testEastCannotSluffWhenHoldingALeadSuitCard`.
- **FR-042**: The system MUST make the trump suit the contract's suit for `.game` with a suit strain, and have no trump for NT, misère and all-pass. — `State.swift` `PlayKind.trumpSuit`.
- **FR-043**: The system MUST award a trick to the highest trump played, otherwise the highest card of the lead suit. Ties between non-competing cards keep the earlier card, because the running maximum only changes on a strict win. — `PreferansEngine.swift` `trickWinner(for:leadSuit:trump:)`, `compare(_:_:leadSuit:trump:)`; test `ScenarioFlowTests.swift::testFirstTrickIsWonByLeadAceOfTrumpsAndRotatesLead`.
- **FR-044**: The system MUST make the winner of each trick the next leader and next current player, except for the talon-led raspasy openings (FR-049). — `PreferansEngine.swift` `completeCurrentTrick(in:)`.
- **FR-045**: The system MUST, after the 10th trick, score the play through `PreferansScoring.completedPlay` and finalize it (events `[cardPlayed, trickCompleted, dealScored, (matchEnded)]`). — `PlayReducer.swift` `reducePlayCard`.
- **FR-046**: The system MUST transfer control of the passer's cards to the lone whister only when all of these hold: kind is `.game`, there is exactly 1 whister and more than 1 defender, the mode is `.open`, `rules.singleWhistScoring == .greedy`, the seat is a defender other than the whister, and no settlement is pending. The engine still names the passer in `.playCard(player:)`. `legalCards(for:)` returns the passer's legal cards to the controller and `[]` to the passer. — `State.swift` `PlayingState.controllingActor(of:rules:)`; `PreferansEngine.swift` `legalCards(for:)`, `controllingActor(of:)`, `controlledSeat(by:)`; tests `PreferansEngineTests/SingleWhistControlTests.swift` (all).
- **FR-047**: The system MUST expose `PlayingState.misereDefendersAreOpen`, which is true for misère unless the declarer is the leader and no card has yet been played in the deal, for visibility consumers. — `State.swift`; tests `PreferansEngineCLITests/MisereVisibilityTests.swift`.

#### All-pass (raspasy) play

- **FR-048**: The system MUST play all-pass with no trump, the same follow-suit duty and `discard = []`, and MUST keep the talon in state under every policy. — `State.swift` `PlayingState`; `BiddingReducer.swift`.
- **FR-049**: The system MUST apply `allPassTalonPolicy` as follows (see [Appendix C](#appendix-c--raspasy-talon-policies)).
  - `ignored`: ordinary play.
  - `classic` and `leadSuitOnly`: `talon[0].suit` and `talon[1].suit` are the required suits of tricks 1 and 2. The forehand acts first in tricks 1, 2 and 3. From trick 4, the previous winner leads.
  - `classic` at 4 seats only: the sitting-out dealer is the leader of tricks 1 and 2. The talon card is recorded as `Trick.talonLead` and competes for the trick, so the dealer can win it. `trickCounts` therefore includes the dealer.
  
  — `State.swift` `usesTalonLeads`, `isClassicFourPlayerAllPass`, `currentTalonLead`, `trickTakingPlayers`; `PreferansEngine.swift` `completeCurrentTrick`; tests `PreferansEngineTests.swift::testFourPlayerRaspasyDealerOwnsTalonTricksAndForehandResets`, `::testRostovAllPassKeepsTalonHiddenAndStartsFromForehand`, `::testAllPassLeadStartsWithForehandAtThreePlayersAndDealerAtFour`.

#### Settlement (claims)

- **FR-050**: The system MUST define the settlement parties (`PlayingState.settlementParties`) as follows: an open ten-trick check (10 tricks, no whisters, no whist calls) → all active seats; an open game → the declarer plus the whisters; a closed game → none; misère → all active seats; all-pass → none. — `State.swift` `settlementParties`; tests `SettlementTests.swift` role-gating tests, `::passedDefenderIsNotASettlementParty`.
- **FR-051**: The system MUST check `.proposeSettlement` in this order: state is `playing`; no proposal is pending (`illegalSettlement("A settlement proposal is already pending.")`); the current trick is empty (`illegalSettlement("Settlements can only be offered between tricks.")`); the proposer is active (`invalidPlayer`); the settlement is valid (FR-052); the proposer is a party (`illegalSettlement("Only the declarer or a whister may offer a settlement, and only in an open game or misère.")`). It then records the proposal with `acceptedBy = [proposer]` and emits `settlementProposed`. — `Sources/PreferansEngine/PreferansEngine+SettlementReducer.swift` `reduceProposeSettlement`; test `SettlementTests.swift::proposingInClosedGameRejected`.
- **FR-052**: The system MUST treat a settlement as valid only if: `target` is active; the `finalTrickCounts` keys equal the active set; `finalTrickCounts[target] == targetTricks`; the counts sum to 10; and each seat's final count lies between its current count and 10. Each failure is an `illegalSettlement` with a specific message. — `PreferansEngine.swift` `validateSettlement(_:in:)`; test `SettlementTests.swift::settlementRejectsImpossibleFinalCounts`.
- **FR-053**: The system MUST let only parties accept (non-party → `invalidPlayer`; no proposal → `illegalSettlement("There is no settlement proposal to accept.")`; already accepted → `illegalSettlement("<p> already accepted this settlement.")`). When `acceptedBy ⊇ settlementParties` it MUST score with `trickCounts := finalTrickCounts` and the real `completedTricks`, then finalize (events `[settlementAccepted, playSettled, dealScored, (matchEnded)]`). — `SettlementReducer.swift` `reduceAcceptSettlement`; `PreferansEngine.swift` `scoreSettlement`; tests `SettlementTests.swift::unanimousSettlementScoresDeal`, `::anyValidConfigurationIsAccepted`.
- **FR-054**: The system MUST let any party, the proposer included, reject. This clears the proposal and emits `settlementRejected` (no proposal → `illegalSettlement("There is no settlement proposal to reject.")`; non-party → `invalidPlayer`). — `SettlementReducer.swift` `reduceRejectSettlement`; test `SettlementTests.swift::rejectingSettlementResumesCardPlay`.
- **FR-055**: The system MUST offer, through `legalSettlements(for:)`, only between tricks, only before the deal is complete, only with no proposal pending and only to parties. The offers are the de-duplicated anchors: the declarer gets 0 of the remaining tricks (the remainder is dealt round-robin to the other active seats in `activePlayers` order); the declarer gets all remaining tricks; and, only at the last trick, the forced split that is provable from the viewer's own knowledge (the declarer sees every hand; a defender enumerates the 3 unseen cards and requires every consistent allocation to agree). Any other valid split is still accepted by FR-052. — `PreferansEngine.swift` `legalSettlements(for:)`, `candidateSettlements`, `settlementGivingDeclarer`, `forcedSettlement(in:knownTo:)`; tests `PreferansEngineCoreTests/SettlementInformationTests.swift`.
- **FR-056**: The system MUST, while a proposal is pending, report `currentActor` as the first seat in `activePlayers` order that is a party and has not accepted, and return `[]` from `legalCards`. — `State.swift` `DealState.currentActor`; `PreferansEngine.swift` `legalCards(for:)`, `canAcceptSettlement`, `canRejectSettlement`.

#### Deal end and match end

- **FR-057**: The system MUST finalize every scored deal (`finalize(_:)`) in this order:
  1. Apply `scoreDelta` via `ScoreSheet.apply(_:closingAtPoolTarget:poolClosure:poolPointWhistValue:)` and store the applied (post-closure) delta in the result.
  2. Increment `dealsPlayed`.
  3. Increment `consecutiveAllPassDeals` (saturating) for `.allPass`, or reset it to 0 for any other kind.
  4. Emit `dealScored(result)`.
  5. If `match.isPoolClosed(score)`, emit `matchEnded(summary)` and enter `gameOver(summary)`; otherwise enter `dealFinished(result)`.
  
  — `PreferansEngine.swift` `finalize(_:)`; tests `MatchSettingsTests.swift::testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`, `::testGameOverFiresWhenPoolSumCrossesTargetExactly`.
- **FR-058**: The system MUST close the pool when `poolTarget != Int.max` and either: (`individualWithAmericanAid`) every player's pool ≥ `poolTarget / playerCount`, where `poolTarget` must divide evenly; or (`tableTotal`) the sum of pools ≥ `poolTarget`. There MUST be no other match-end condition. — `MatchSettings.swift` `isPoolClosed(_:)`, `configurationError(playerCount:)`.
- **FR-059**: The system MUST build `MatchSummary.standings` for every player with the normalized balance from `score.normalizedBalances(poolPointValue:mountainPointValue:)`. Standings are sorted by balance descending, with seat order breaking ties. `leadingPlayers`, `soleWinner` and `rank(of:)` (competition ranking) are derived from them. — `PreferansEngine.swift` `makeMatchSummary`; `MatchSettings.swift` `MatchSummary`; tests `MatchOutcomeTests.swift` (both).
- **FR-060**: The system MUST record in each `DealResult` the kind, active seats, final trick counts, the really played `completedTricks`, the applied `scoreDelta`, `initialHands` (the dealt 10-card hands, reconstructed by the scorer) and any `settlement`. — `State.swift` `DealResult`; `Sources/PreferansEngine/ScoringEngine.swift` `openingHands(from:)`; test `PreferansEngineTests.swift::testDealResultKeepsOpeningHandsAfterDeclarerKeepsPrikupCards`.

#### Atomicity, invariants, recovery

- **FR-061**: The system MUST leave the engine completely unchanged when an action throws. Reducers validate everything before any mutation of `score`, `dealsPlayed`, `consecutiveAllPassDeals` or `nextDealer`, and `state` is assigned only after `reduce` returns. — `PreferansEngine.swift` `dispatch(_:)`; test `PreferansEngineTests.swift::testConcedeWithoutThreeIsRejectedForMisere`.
- **FR-062**: The system MUST run `validateInvariants(snapshot)` after every successful `apply`, and trap through `preconditionFailure` on an `InvariantViolation`. The internal bot fast path `applyRolloutCard` skips this check. — `Sources/PreferansEngine/PreferansEngine+Invariants.swift` `assertInvariants`; `PreferansEngine.swift` `apply(_:)`, `applyRolloutCard`.
- **FR-063**: The system MUST validate players, rules, match, `nextDealer` membership (`invalidPlayer`) and all snapshot invariants (thrown as `InvariantViolation`) in `init(snapshot:)` before adopting any field. — `PreferansEngine.swift` `init(snapshot:)`; tests `InvariantValidatorTests.swift` (72 methods).
- **FR-064**: The system MUST enforce every invariant listed in [data-model.md § Invariants](./data-model.md#invariants). These include the replay of the full card-play history (follow-suit, lead order, winners, next actor) and the ledger consistency of the auction and whist histories. — `PreferansEngine+Invariants.swift`.

#### Serialization and interfaces

- **FR-065**: The system MUST make `PreferansSnapshot`, `PreferansAction`, `PreferansEvent`, `DealState` and every nested type `Codable`. Encode → decode → `init(snapshot:)` MUST round-trip to an equal snapshot. — `State.swift`, `Domain.swift`; tests `PreferansEngineTests.swift::testSnapshotAndActionsAreCodable`, `EngineGenerativeTests.swift::walkPreservesInvariants`.
- **FR-066**: The system MUST decode legacy payloads with these defaults: snapshot `match` → `.unbounded`; `dealsPlayed` and `consecutiveAllPassDeals` → 0; `MatchSettings.poolTarget` → `Int.max` (omitted when unbounded, for JavaScript safety); `poolClosure` → `.individualWithAmericanAid`; `raspasy` → `.singleShot`; `totus` → `.asTenTrickGame(requireWhist: false)`. The rules defaults are listed in [data-model.md](./data-model.md#serialization-format). — `State.swift` `PreferansSnapshot.init(from:)`; `MatchSettings.swift` `init(from:)`; `Rules.swift` `init(from:)`; tests `MatchSettingsTests.swift::testUnboundedWireEncodingAvoidsJavaScriptIntegerOverflow`, `PreferansEngineTests.swift::testStalingradRuleRoundTripsAndOldWireFormatDefaultsOff`.
- **FR-067**: The system MUST reject out-of-domain values at decode time with a `DecodingError`, never a trap. This covers an empty `PlayerID`, `GameContract.tricks ∉ 6…10`, invalid rules scales and a negative totus bonus. — `Domain.swift`, `Rules.swift`, `MatchSettings.swift`; tests `PreferansEngineTests.swift::testRulesDecoderRejectsUnsafeScoringValuesWithoutTrapping`, `MatchSettingsTests.swift::testDecodingRejectsNegativeDedicatedTotusBonus`.
- **FR-068**: The system MUST expose `DealState.currentActor` as the single source of truth for whose turn it is: bidding → `currentPlayer`; discard and contract → declarer; whist → `currentPlayer`; defender mode → whister; playing → `currentPlayer`, or the first pending settlement party; between deals and after the match → `nil`. — `State.swift` `DealState.currentActor`.
- **FR-069**: The system MUST document that `PreferansAction.startDeal` has `actor == nil` and a caller-supplied dealer and deck, so a host MUST overwrite both. `AuthoritativeGameService` uses `nextDealer` and `Deck.shuffled(seed:)`, and `HostGameActor` uses its deal source. `PreferansSnapshot` holds full information and MUST never be sent to clients. — `State.swift` `PreferansAction`, `PreferansSnapshot`; `Sources/PreferansServerCore/AuthoritativeGameService.swift` `authoritativeAction`.
- **FR-070**: The system MUST provide `PlayerIdentity(playerID, gamePlayerID, displayName)` as the app/online mapping from an engine seat to an account identity. The rules never read it. — `Sources/PreferansEngine/PlayerIdentity.swift`.

### Key Entities

Full field-level definitions are in [data-model.md](./data-model.md).

- **PreferansEngine**: the aggregate. It holds `players`, `rules`, `match`, `state`, `score`, `nextDealer`, `dealsPlayed` and `consecutiveAllPassDeals`.
- **DealState**: a 9-case enum (`waitingForDeal`, `bidding`, `awaitingDiscard`, `awaitingContract`, `awaitingWhist`, `awaitingDefenderMode`, `playing`, `dealFinished`, `gameOver`). Each phase carries its own payload struct.
- **PreferansAction** (11 cases) and **PreferansEvent** (18 cases): the input and output vocabulary.
- **Card / Suit / Rank / Deck / Strain / GameContract / ContractBid / BidCall / WhistCall / DefenderPlayMode / Trick / CardPlay**: domain values.
- **PreferansRules**: per-deal rule and scoring options and the named profiles `sochi`, `stalingrad`, `rostov` and `leningrad`.
- **MatchSettings**: `poolTarget`, `poolClosure`, `raspasy` and `totus`.
- **TrickSettlement / TrickSettlementProposal**: the claim payloads.
- **DealResult / DealResultKind / MatchSummary**: the hand-off to scoring and the presentation layers.
- **DealSource / DealDeckLayout / SeededRandomNumberGenerator**: deck supply and layout.
- **PreferansError / InvariantViolation**: recoverable input errors and engine-bug signals.

### Interfaces to neighbouring areas

| Neighbour | What crosses the boundary |
|---|---|
| [002 scoring](../002-scoring-and-variants/) | The engine calls `PreferansScoring(players:rules:match:consecutiveAllPassDeals:)` and its methods `.passedOut(WhistState)`, `.halfWhist(WhistState, halfWhister:)`, `.withoutThree(ContractDeclarationState)` and `.completedPlay(PlayingState, settlement:)`, then `ScoreSheet.apply(...)`, `MatchSettings.isPoolClosed` and `ScoreSheet.normalizedBalances`. All monetary values (pool, mountain, whists, American aid, raspasy prices, dealer talon compensation) live there. The engine supplies only state and the raspasy counter. |
| [003 bots](../003-bots/) | Bots read `legalBidCalls`, `legalWhistCalls`, `legalContractDeclarations`, `legalCards`, `canAcceptSettlement`/`canRejectSettlement` (recovery fallback), `controllingActor` and `forcedSettlement(in:knownTo:)`, and validate every snapshot they act on through `init(snapshot:)` (`validateInvariants`). They never call `legalSettlements` (bots do not propose). They simulate through `applyRolloutCard` (no invariant replay). |
| [004 online](../004-online-multiplayer/) | The projection reads `currentActor`, `declarer`, `misereDefendersAreOpen`, `settlementParties`, `usesTalonLeads` and the `can*`/`legal*` helpers. Visibility as built: the talon is shown to everyone in `awaitingDiscard`; afterwards the discard is shown to the declarer only; open-game defenders are shown; an open ten-check shows every hand; misère defenders are shown once `misereDefendersAreOpen`; raspasy talon cards are revealed one per opening trick. The server authorizes the sender as `controllingActor(of: action.actor)` and rewrites `startDeal`. |
| [005 app](../005-ios-app/) | `PreferansVariant` (in `Preferans/UI/LobbyModels.swift`) maps lobby conventions to engine profiles: `odesa → .sochi` (individual closure, `RaspasyPolicy.sochi`), `wien → .leningrad` (table total, `.leningrad`), `thessaloniki → .rostov` (individual, `.rostov`), `kruty → .stalingrad` (individual, `.sochi`). Neither the lobby nor the worker ever sets `TotusPolicy.dedicatedContract`. |
| [006 testing](../006-testing-and-release/) | `HandRecipe`, `MatchScript`, `MatchScriptFixtures` and `EngineMatchDriver` (in the engine target) build decks through `DealDeckLayout.deck(...)` and drive actions. The engine-only lane is `PREFERANS_ENGINE_TESTS_ONLY=1` (`PreferansEngineCLITests`). |

## Success Criteria

### Measurable Outcomes

- **SC-001**: 36 seeded generative walks (2 configurations: 3-seat Sochi and 4-seat Sochi, seeds 1–18, at most 180 legal actions each, settlements proposed at random) validate every snapshot and JSON round-trip it to an equal value at every step (`PreferansEngineCLITests/EngineGenerativeTests.swift`).
- **SC-002**: `InvariantValidatorTests.swift` has 72 test methods. Apart from 3 happy-path controls and one score-decoding positive test, each breaks exactly one invariant and asserts the violation message fragment. The invariant table in [data-model.md](./data-model.md#invariants) marks which checks have a dedicated negative test. The rest (such as full-deck accounting and player-reference checks) are exercised only positively, by every reducer path and by the generative walks.
- **SC-003**: All 27 entries of `ContractBid.allStandard` have distinct `order` values, totus sits exactly 1 above misère, and 9♠ sits exactly 1 above totus (`MatchSettingsTests.swift::testTotusOrderingPlacesItDirectlyAboveMisere`).
- **SC-004**: The same seed gives identical decks, hands and talon. Concurrent requests to scripted and seeded sources are serialized: 100 → 50/50, and 32 → 32 distinct decks (`DealSourceTests.swift`).
- **SC-005**: The raspasy progression tables match exactly: Sochi `[1,2,3,3]` and `[6,7,8,8]`; geometric `[1,2,4,4]`; capped double `[1,2,2,2]`; single shot `[1,1,1]` and `[6,6,6]`; saturation at `Int.max` (`MatchSettingsTests.swift::testRaspasyProgressions*`).
- **SC-006**: A rejected action never changes engine state (`PreferansEngineTests.swift::testConcedeWithoutThreeIsRejectedForMisere`). The reducer design makes this structural (FR-061).
- **SC-007**: Dealer rotation is verified across 4 consecutive 4-seat deals, and each deal's sit-out seat equals its dealer (`ScenarioFlowTests.swift`).
- **SC-008**: A full 4-seat bot match to pool 6 completes in well under one minute with animations off (performance budget from `AGENTS.md`; enforced in the bot and test lanes, see [006](../006-testing-and-release/)).

## Known Gaps & Open Questions

1. **Stale doc comment on `TotusPolicy.dedicatedContract`.** `Sources/PreferansEngine/MatchSettings.swift` says the declarer "picks the trump strain and starts play immediately" and that `requireWhist` "applies to the standard 10-trick ladder, not this dedicated flow". The code applies `match.totus.requireWhistOnTenTricks` to *every* declared 10-trick contract, dedicated totus included, through `requiresWhistOnTenTricks`, and `MatchSettingsTests.testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin` asserts that the whist phase is entered. The code and tests win, so the comment is wrong.
2. **Stale release note.** `AppStore/BuildHistory.md` (build 25) describes ten-trick contracts with a "mandatory whist". Commit `0319a9b` replaced this with ordinary `[.pass, .whist]` choices, and the property name `requireWhistOnTenTrickContracts` is now historical (the code comment in `Rules.swift` says so).
3. **Raspasy when nobody follows the talon suit** (3 seats, or `leadSuitOnly`). The winner is the highest card in the suit of the first card played, which emerges from `compare`/`max`. [NEEDS CLARIFICATION: is this the intended house rule? No test pins it.]
4. **Settlement `target`** is not required to be the declarer, or the lowest seat in an all-pass deal. Scoring ignores it, but the UI renders "`target` takes `targetTricks` tricks". [NEEDS CLARIFICATION: should `validateSettlement` require `target == declarer` for game and misère?]
5. **Dedicated totus and declaration.** After winning with a 9-level bid in a dedicated-totus match, `legalContractDeclarations` still offers 10-level game contracts (scored without the totus bonus), although such bids are blocked in the auction. [NEEDS CLARIFICATION] Dedicated totus is reachable only through engine and test configuration; the shipped app and worker always use `asTenTrickGame(requireWhist: false)`.
6. **Asymmetric `RaspasyPolicy` defaults.** `MatchSettings()` defaults to `.sochi`, but a decoded `MatchSettings` with no `raspasy` key becomes `.singleShot` (legacy). A snapshot with no `match` key at all becomes `.unbounded`, which uses `.sochi`. This is intentional per the code comments, but easy to trip over.
7. **Two error types from `init(snapshot:)`.** It throws `PreferansError` for players, rules, match and dealer, but throws a raw `InvariantViolation` for structural problems. Hosts must catch both.
8. **Unreachable defensive branches.** These are kept as guards: the deck "standard set" check (32 unique `Card` values are necessarily the full set), `illegalBid("Player is not active in the auction.")`, `illegalBid("No next bidder is available.")`, the half-whist `illegalWhist` branches inside `reduceWhist` (pre-empted by the legality check) and `"Declarer must keep ten cards after discard."`
9. **The engine does not authenticate senders.** `.playCard(player:)` names the seat whose card is played, and checking that the sender is `controllingActor(of:)` is the host's job (`AuthoritativeGameService.authorize`, `HostGameActor`).
10. **No other match-end conditions.** There is no resign/abandon action, no deal cap and no timeout in the engine. An unbounded match never ends (`MatchSettings.unbounded`).
11. **Two whist-quota sources.** `PreferansRules.whistRequirement(for:)` returns 0 for a 10-trick contract unless the *rules* flag is set. It ignores the match totus flag, which `PreferansScoring.effectiveWhistRequirement` adds. Callers outside scoring should use the engine's combined view.
12. **Terminology drift.** `README.md` says "claims", while the code says "settlement". The README lists the lobby names Одеса/Wien/Θεσσαλονίκη/Крути, while the App Store copy and `docs/PUBLIC_LOBBY.md` use Vienna/Prague/Berlin for the same persisted identifiers `odesa`/`wien`/`thessaloniki`. This is presentation only and owned by [005](../005-ios-app/) and [004](../004-online-multiplayer/).
13. **Confusing package names.** The directory `Tests/PreferansEngineCoreTests` is the target `PreferansEngineTests`, and the directory `Tests/PreferansEngineTests` is the target `PreferansAppTests`.
14. **Production traps.** An invariant violation calls `preconditionFailure`, which crashes the host process instead of rejecting the action. This is by design (a reducer bug), but every online command pays for a full history replay (`checkPlayedHistory`).
15. **Seeded-shuffle portability.** `Deck.shuffled(seed:)` relies on the Swift standard library's `shuffled(using:)` algorithm staying stable across toolchains. The comments claim cross-platform determinism, and persisted snapshots do not depend on re-shuffling. [Inferred risk]
16. **4-seat dealer privileges.** The engine gives the sitting-out dealer no view of the hands or the talon. The dealer's only roles are the classic raspasy talon leads and dealer-talon compensation in scoring.

---

## Appendix A – Bidding ladder

`order` comes from `ContractBid.order`. "Value" is `ContractBid.value` (the base used by scoring). "Whist quota" is `PreferansRules.whistRequirement`, the minimum number of defender tricks.

| Order | Bid | Value | Whist quota | Notes |
|---:|---|---:|---:|---|
| 0–4 | 6♠ 6♣ 6♦ 6♥ 6NT | 2 | 4 | Half-whist possible |
| 5–9 | 7♠ 7♣ 7♦ 7♥ 7NT | 4 | 2 | Half-whist possible |
| 10–14 | 8♠ 8♣ 8♦ 8♥ 8NT | 6 | 1 | |
| 15 | Misère | 10 | – | First bid only; no hold; no whist phase |
| 16 | Totus | 10 | 0 (1*) | Legal only with `TotusPolicy.dedicatedContract`; declare any 10-trick strain; +`bonusPool` if made |
| 17–21 | 9♠ 9♣ 9♦ 9♥ 9NT | 8 | 1 | 9♠ overcalls totus |
| 22–26 | 10♠ 10♣ 10♦ 10♥ 10NT | 10 | 0 (1 with convention) | Removed from the auction under dedicated totus. With the convention off: open check, no whist phase |

\* The quota for 10 tricks is 1 when the rules flag or the match totus flag enables ten-trick whisting, as computed in `PreferansScoring.effectiveWhistRequirement`.

Raspasy exit restrictions (FR-020) remove game bids below `minimumGameTricks` at every strain. The table below gives `minimumGameTricks(after: n)` for the n preceding consecutive all-pass deals.

| Exit progression | n=0 | n=1 | n=2 | n≥3 |
|---|---:|---:|---:|---:|
| `singleShot` (policy) | 6 | 6 | 6 | 6 |
| `.simple` | 6 | 6 | 6 | 6 |
| `.constrained` | 6 | 7 | 7 | 7 |
| `.strict` (Sochi, Leningrad defaults) | 6 | 7 | 8 | 8 |

## Appendix B – Whist decision matrix

D1 = `defenders[0]` (the first seat after the declarer); D2 = `defenders[1]`. "≤7" means `contract.tricks ≤ 7`.

| Situation | Seat to act | Legal calls |
|---|---|---|
| Stalingrad (`forceWhistOnSixSpades` and contract == 6♠) | D1, then D2 | `[whist]` |
| `flow == .normal`, no calls yet | D1 | `[pass, whist]` |
| `.normal`, D1 passed, ≤7 | D2 | `[pass, halfWhist, whist]` |
| `.normal`, D1 passed, ≥8 | D2 | `[pass, whist]` |
| `.normal`, D1 whisted | D2 | `[pass, whist]` |
| `.firstDefenderSecondChance(halfWhister: D2)` | D1 | `[pass, whist]` |

| D1 | D2 | D1 (2nd chance) | Next state | Result / play |
|---|---|---|---|---|
| pass | pass | – | `dealFinished` / `gameOver` | `.passedOut`: declarer credited, no play |
| pass | whist | – | `awaitingDefenderMode(whister: D2)` | D2 picks open/closed; `whisters [D2]` |
| pass | halfWhist | pass | `dealFinished` / `gameOver` | `.halfWhist(halfWhister: D2)` |
| pass | halfWhist | whist | `playing` closed | `whisters [D1, D2]` |
| whist | pass | – | `awaitingDefenderMode(whister: D1)` | D1 picks open/closed; `whisters [D1]` |
| whist | whist | – | `playing` closed | `whisters [D1, D2]` |

## Appendix C – Raspasy talon policies

| Policy | Profiles | Tricks 1–2 required suit | Talon card competes? | Leader of tricks 1–2 | Who starts tricks 2 and 3 | Trick takers |
|---|---|---|---|---|---|---|
| `ignored` | Rostov | first card played | – | forehand, then winner | previous winner | 3 active |
| `classic`, 3 seats | Sochi (default), Leningrad, Stalingrad | `talon[i].suit` | no | forehand | forehand | 3 active |
| `classic`, 4 seats | same | `talon[i].suit` | **yes** (`Trick.talonLead`, owned by the dealer) | dealer | forehand | 3 active + dealer |
| `leadSuitOnly` (house) | none shipped | `talon[i].suit` | no | forehand | forehand | 3 active |

## Appendix D – Action legality by phase

✓ means the action is accepted (subject to its own checks). Any other phase throws `invalidState(expected: <phase>, actual: state.description)`.

| Action → / Phase ↓ | startDeal | bid | discard | declareContract | concedeWithoutThree | whist | chooseDefenderMode | playCard | propose / accept / rejectSettlement |
|---|---|---|---|---|---|---|---|---|---|
| waitingForDeal | ✓ | | | | | | | | |
| bidding | | ✓ current bidder | | | | | | | |
| awaitingDiscard | | | ✓ declarer | | | | | | |
| awaitingContract | | | | ✓ declarer | ✓ declarer (not misère) | | | | |
| awaitingWhist | | | | | | ✓ current defender | | | |
| awaitingDefenderMode | | | | | | | ✓ whister | | |
| playing | | | | | | | | ✓ current seat, no pending proposal | ✓ parties only |
| dealFinished | ✓ | | | | | | | | |
| gameOver | ✗ "gameOver (match closed)" | | | | | | | | |

Events emitted per action (in order):

| Action | Events |
|---|---|
| startDeal | `dealStarted(dealer, activePlayers)` |
| bid | `bidAccepted(call)` [+ `allPassed`, `playStarted(.allPass)`] or [+ `auctionWon(declarer, bid)`] |
| discard | `talonExchanged(declarer, talon, discard)` [+ `playStarted(.misere)`] |
| declareContract | `contractDeclared(declarer, contract)` [+ `playStarted(.game)` for an open ten-check] |
| concedeWithoutThree | `contractConcededWithoutThree(declarer, bid)`, `dealScored`, [`matchEnded`] |
| whist | `whistAccepted(record)` [+ `playStarted`] or [+ `dealScored`, [`matchEnded`]] |
| chooseDefenderMode | `defenderModeChosen(whister, mode)`, `playStarted(.game)` |
| playCard | `cardPlayed` [+ `trickCompleted(trick)` [+ `dealScored`, [`matchEnded`]]] |
| proposeSettlement | `settlementProposed(proposal)` |
| acceptSettlement | `settlementAccepted(player)` [+ `playSettled(settlement)`, `dealScored`, [`matchEnded`]] |
| rejectSettlement | `settlementRejected(player)` |

## Appendix E – Error catalogue

| Error | Thrown by | Condition |
|---|---|---|
| `invalidPlayers(String)` | `init`, `init(snapshot:)` | count ∉ {3, 4}; duplicate IDs |
| `invalidRules(String)` | `init`, `init(snapshot:)` | `PreferansRules.configurationError` (non-positive multiplier, divisor, penalty or conversion value; divisor not dividing 2/4/6/8/10; negative zero-trick bonus) |
| `invalidMatch(String)` | `init`, `init(snapshot:)` | pool target ≤ 0 (unless unbounded); negative dedicated-totus bonus; individual target not divisible by player count |
| `invalidPlayer(PlayerID)` | `init` (first dealer), `init(snapshot:)` (next dealer), `startDeal` (dealer), `proposeSettlement` (inactive proposer), `accept`/`rejectSettlement` (non-party) | seat not recognized or not entitled |
| `invalidDeck(String)` | `startDeal` | not 32 cards; not the standard set |
| `duplicateCards([Card])` | `startDeal` (sorted duplicates), `discard` (the submitted cards) | repeated cards |
| `invalidContract(String)` | `declareContract`, `concedeWithoutThree`, `GameContract.init(tricks:strain:) throws` | below the auction bid; totus not 10 tricks; misère declaration or concession; tricks ∉ 6…10 |
| `invalidState(expected:actual:)` | every action | wrong phase |
| `notPlayersTurn(expected:actual:)` | bid, discard, declareContract, concede, whist, chooseDefenderMode, playCard | the actor is not the seat to act |
| `illegalBid(String)` | bid | not legal per FR-017 to FR-021 |
| `illegalWhist(String)` | whist | not in `legalWhistCalls` |
| `illegalSettlement(String)` | playCard (pending), propose, accept, reject | see FR-051 to FR-054 |
| `illegalCardPlay(String)` | discard (wrong count), playCard (revoke or failure to trump) | |
| `cardNotInHand(player:card:)` | discard, playCard | card not held (for a discard: not in hand + talon) |
| `InvariantViolation(message)` | `init(snapshot:)`; traps inside `apply` | structural corruption (see data-model.md) |

## Appendix F – Worked examples

### F.1 Deal layout of the unshuffled deck

`Deck.standard32` (indices 0–7 ♠7…♠A, 8–15 ♣, 16–23 ♦, 24–31 ♥), players `[north, east, south]`, dealer `north`, so active = `[east, south, north]`:

| Seat | Deck indices | Hand (sorted) |
|---|---|---|
| east (forehand) | 0,1,8,9,14,15,20,21,26,27 | ♠7 ♠8 ♣7 ♣8 ♣K ♣A ♦J ♦Q ♥9 ♥10 |
| south | 2,3,10,11,16,17,22,23,28,29 | ♠9 ♠10 ♣9 ♣10 ♦7 ♦8 ♦K ♦A ♥J ♥Q |
| north (dealer) | 4,5,12,13,18,19,24,25,30,31 | ♠J ♠Q ♣J ♣Q ♦9 ♦10 ♥7 ♥8 ♥K ♥A |
| talon | 6,7 | ♠K ♠A |

### F.2 Auction with a hold

With the hands above, the calls are: `east 6♣` → `south 6♦` → `north pass`. Two seats remain and east is older than south, so east may bid `6♦` again. South now cannot repeat 6♦ and must bid ≥ 6♥ or pass. South passes → `auctionWon(east, 6♦)`.

### F.3 Whist with a half-whist revoked

East declares 6♣, so D1 = south and D2 = north. South passes, and north (≤7, D1 passed) half-whists. The flow becomes `.firstDefenderSecondChance(halfWhister: north)` and the turn returns to south, whose options are `[pass, whist]`. South whists → closed play, `whisters [south, north]`. The forehand (east, also the declarer here) leads trick 1. With lowest-legal play the final counts are east 3, south 1, north 6, so the contract fails by 3.

### F.4 3-seat Sochi raspasy opening

With the hands of F.1, everyone passes. Talon = ♠K, ♠A. Trick 1 has required suit ♠ (♠K). East plays ♠7, south ♠9, north ♠J; north wins (the talon card does not compete at 3 seats). Trick 2 has required suit ♠ (♠A) and **east starts again**: ♠8, ♠10, ♠Q; north wins. Trick 3 is started by **east** (the forehand reset), with no required suit. From trick 4 the winner of the previous trick leads. After the deal, `consecutiveAllPassDeals = 1`, so the next auction under `.strict` exit requires game bids of at least 7 tricks.

### F.5 Settlement anchors

Open game, active `[east, south, north]`, declarer east, whister south, passer north. After 6 tricks the counts are east 5, south 1, north 0, so 4 tricks remain. The parties are {east, south}. The anchors offered between tricks are `{east 5, south 3, north 2}` (declarer +0; the defence gets the remaining 4 round-robin: south, north, south, north) and `{east 9, south 1, north 0}` (declarer +4). East proposes `{east 7, south 2, north 1}`, which is valid: the total is 10 and nobody loses tricks already won. The proposal is pending with `acceptedBy {east}` and `currentActor = south`. South accepts → `playSettled`, then the deal is scored with those counts.
