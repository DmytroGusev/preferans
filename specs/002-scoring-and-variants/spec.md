# Feature Specification: Scoring, Rule Variants, and Match Settlement

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `Sources/PreferansEngine/ScoringEngine.swift`, `Sources/PreferansEngine/Score.swift`, `Sources/PreferansEngine/MatchSettings.swift`, `Sources/PreferansEngine/Rules.swift`, `Sources/PreferansEngine/PreferansEngine.swift` (`finalize`, `makeMatchSummary`, settlement helpers), `Sources/PreferansEngine/PreferansEngine+SettlementReducer.swift`, `Sources/PreferansEngine/State.swift`, `Sources/PreferansEngine/Domain.swift`, `Preferans/UI/LobbyModels.swift` (house-name mapping)

Related specs: phases, bidding, exchange, whist decisions and trick play live in [`../001-game-rules`](../001-game-rules/); room/worker transport of rules and match settings in [`../004-online-multiplayer`](../004-online-multiplayer/); score sheet, pulka diagram, settlement composer and game-over UI in [`../005-ios-app`](../005-ios-app/); test lanes in [`../006-testing-and-release`](../006-testing-and-release/). Entity details: [`data-model.md`](./data-model.md). Design rationale: [`research.md`](./research.md).

## Summary

Every finished Preferans deal produces a `DealResult` whose `ScoreDelta` records three kinds of entries per player:

| Column | Russian | Engine field | Meaning | Direction |
| --- | --- | --- | --- | --- |
| Pool / bullet | пуля / пулька | `ScoreSheet.pool[player]` | Points for fulfilled contracts and clean raspasy exits | Higher is better; never negative |
| Mountain | гора | `ScoreSheet.mountain[player]` | Penalty points | Lower is better; may become negative after pulka closing |
| Whists | висты | `ScoreSheet.whists[writer][target]` | Points `writer` has "written on" `target` | Writer gains, target pays; never negative, never on self |

The pure scorer `PreferansScoring` (`ScoringEngine.swift`) turns a terminal deal state into a raw delta; `ScoreSheet.apply(_:closingAtPoolTarget:poolClosure:poolPointWhistValue:)` (`Score.swift`) applies it under the match's pulka-closing convention (individual pools with "American aid", or a shared table total); `PreferansEngine.finalize` (`PreferansEngine.swift`) advances the raspasy series counter and decides whether the match is over. At match end, `ScoreSheet.normalizedBalances` converts pool and mountain into whists at variant-specific rates, adds net whists, and subtracts the table mean, producing a zero-sum per-player balance (`MatchSummary.standings`).

Scoring is configured by two values that travel together everywhere (engine, snapshots, online worker): `PreferansRules` (per-deal recording conventions) and `MatchSettings` (pool target, pulka closing, raspasy progression, totus policy). Four named profiles exist in the engine — `.sochi`, `.stalingrad`, `.leningrad`, `.rostov` — and the app exposes them under house names (persisted ids `odesa`, `kruty`, `wien`, `thessaloniki`; displayed in English as Vienna, Kruty, Prague, Berlin).

The engine also supports **trick settlement** (claims): during an open game or a misère, the contesting parties may agree on the final trick split; unanimous agreement scores the deal from the agreed counts.

## User Scenarios & Testing

### User Story 1 – A played contract is recorded on the score sheet (Priority: P1)

A declarer plays a contract against one or two whisters; when the tenth trick completes (or a settlement is agreed), the sheet shows the declarer's pool or mountain, every defender's whists on the declarer, any whister penalty, and (four players) the sitting-out dealer's talon compensation.

**Why this priority**: Recording deals correctly is the core value of the score sheet; every other number derives from it.

**Independent Test**: Build a `PlayingState` with fixed trick counts and call `PreferansScoring(...).completedPlay(_:)`; compare the `ScoreDelta` (pattern used by `Tests/PreferansEngineCoreTests/ScoringCalculationTests.swift`).

**Acceptance Scenarios**:

1. **Given** Sochi rules and 6♣ with both defenders whisting, **When** the tricks end 6/2/2, **Then** the declarer gets pool +2 and each whister writes 4 whists on the declarer (`testMadeContractCreditsPoolAndEachWhistersOwnTricks`).
2. **Given** Sochi rules and 7♥ with two whisters, **When** the tricks end 5/3/2, **Then** the declarer gets mountain +8, east writes 20 and south writes 16 whists on the declarer (own tricks × 4 plus 2 undertricks × 4 consolation) (`testFailedDeclarerPaysMountainAndEachDefenderConsolationWhists`).
3. **Given** Sochi rules and 6♦ with a single (greedy) whister, **When** the tricks end 7/1/2, **Then** the declarer gets pool +2, the whister writes 6 whists (all three defender tricks) and receives mountain +2 for being one trick short of the 4-trick quota (`testSingleGreedyWhisterScoresAllDefenderTricksAndOwnResponsibility`).
4. **Given** 8♠ with two whisters, **When** the declarer takes all ten tricks, **Then** only the second whister is charged (mountain +6) (`testOddOneTrickResponsibilityFallsOnSecondWhister`).
5. **Given** Leningrad rules and 6♣ with two whisters, **When** the declarer fails 5/3/2, **Then** declarer mountain +4 and each defender writes 14 whists (doubled 20 trick-whists split 10/10 plus 4 consolation) (`testLeningradKeepsPoolBaseValueAndDoublesMountainAndWhists`).
6. **Given** Rostov rules and 7♥ with two whisters, **When** the declarer fails 6/2/2, **Then** declarer mountain stays 0 and each defender writes 18 whists (8 split trick-whists + 10 direct remise whists) (`testRostovDeclarerRemisePaysEachDefenderDirectWhists`).

---

### User Story 2 – The pulka closes and the match is settled (Priority: P1)

Players agree on a pool target. When the target is reached the engine stops dealing, converts every column into whists, and shows zero-sum standings with a winner or shared lead.

**Why this priority**: Without a match end and a final balance there is no winner.

**Independent Test**: Rehydrate an engine from a `PreferansSnapshot` whose pools are near the target, play one passed-out contract, and inspect `engine.score` and the `.gameOver(MatchSummary)` state (`Tests/PreferansEngineCoreTests/PulkaClosingTests.swift`).

**Acceptance Scenarios**:

1. **Given** individual closure with total target 33 (11 each) and pools 10/7/3, **When** north earns 4 pool points, **Then** north's pool becomes 11, east receives 3 points of American aid (pool 10) and north writes 30 whists on east (`testSurplusPoolAidsHighestOpenPlayerAndWritesWhists`).
2. **Given** pools 10/10/8 and target 33, **When** north earns 6, **Then** pools become 11/11/11, north writes 10 on east and 30 on south, and north's mountain becomes −1 (`testSurplusPoolCascadesAcrossPlayersThenReducesMountainWhenEveryoneIsClosed`).
3. **Given** an engine with pools 10/10/10 and target 33, **When** north's 7♣ is passed out (+4), **Then** pools become 11/11/11, north writes 10 on east and 10 on south, north's mountain is −1, the emitted `dealScored` delta is the *applied* delta, and the engine enters `.gameOver` (`testEngineDealAppliesPulkaClosingToDealResultAndMatchSummary`).
4. **Given** Leningrad table-total closure with target 21 and pools 20/0/0, **When** north passes out 6♣, **Then** north's pool is 22 (no cap, no aid) and the match ends (`testLeningradMatchClosesOnSharedTotalAndAllowsTheWinnerToOvershoot`).
5. **Given** a Sochi match to total 6, **When** three passed-out 6-level contracts give every player pool 2, **Then** every balance is 0, all three share rank 1 and there is no sole winner (`testThreeEqualPoolsShareTheLeadAndProjectionNamesNoSoleWinner`).
6. **Given** a closed match, **When** anyone calls `startDeal`, **Then** the engine throws `invalidState` mentioning `gameOver` (`testStartDealFromGameOverThrows`).

---

### User Story 3 – All-pass deals (raspasy) are penalised and progress (Priority: P1)

When everyone passes, the hand is played with no trump; each trick taken costs mountain (or, in Rostov, direct whists to the lowest-trick player), a clean exit earns pool, and consecutive raspasy deals get more expensive and raise the minimum contract for the next auction.

**Why this priority**: Raspasy happens frequently and dominates scores when bots or cautious players pass.

**Independent Test**: Score an `.allPass` `PlayingState` with `consecutiveAllPassDeals = k` (`Tests/PreferansEngineCoreTests/ScoringVariantTests.swift`), and play consecutive all-pass deals through the engine (`MatchSettingsTests.testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`).

**Acceptance Scenarios**:

1. **Given** Sochi rules and the default `.sochi` progression, **When** a 0/4/6 raspasy is the 1st/2nd/3rd/4th consecutive one, **Then** the price is 1/2/3/3: clean-exit pool 1/2/3/3 and mountain 4p and 6p (`testSochiRaspasyPriceProgressesOneTwoThreeAndCaps`).
2. **Given** Leningrad rules at the third stage, **When** tricks are 0/4/6, **Then** pool +3 for the clean exit and mountain 24/36 (`testLeningradRaspasyDoublesMountainSeriesButKeepsPoolExitAtProgressionPrice`).
3. **Given** Rostov rules, **When** tricks are 0/4/6 (any stage), **Then** the zero-trick player gets pool +1 and writes 20 whists on the 4-trick player and 30 on the 6-trick player; no mountain (`testRostovRaspasyUsesFixedDirectWhistsAndHiddenTalon`).
4. **Given** two consecutive raspasy deals under strict exit, **When** the next auction opens, **Then** only 8-, 9-, 10-level game bids and misère are legal (`testStrictRaspasyExitFiltersSixThenSevenLevelGamesButKeepsMisere`).
5. **Given** a raspasy streak, **When** any non-raspasy result is scored, **Then** `consecutiveAllPassDeals` resets to 0 (`testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`).

---

### User Story 4 – Players pick a scoring convention and can read its rules (Priority: P2)

In the lobby the player chooses Vienna / Prague / Berlin / Kruty, a pulka length, and (private/local tables) the raspasy price and exit progressions. The rules screen shows numbers computed by the real scorer.

**Why this priority**: Scoring conventions vary between Preferans circles; showing the exact active rules prevents disputes.

**Independent Test**: `PreferansRulebook.examples(rules:match:)` returns engine-computed tables (`ScoringVariantTests.testExecutableRulebookUsesTheProductionScorer`); worker presets equal Swift profiles (`Tests/PreferansServerCoreTests/PublicTableRulesTests.swift`).

**Acceptance Scenarios**:

1. **Given** the Sochi profile, **When** the rulebook is generated, **Then** contracts 6–10 show made pool 2/4/6/8/10, one-undertrick mountain 2/4/6/8/10, whist per defender trick 2/4/6/8/10; misère 10 pool / 10 mountain per trick; raspasy price 1–2–3, clean exit 1–2–3, exit minimum 6–7–8.
2. **Given** the Leningrad profile, **Then** made pool 2/4/6/8/10, undertrick mountain 4/8/12/16/20, whist per trick 4/8/12/16/20, misère failure 20 per trick, raspasy price 2–4–6, clean exit 1–2–3.
3. **Given** the Rostov profile with its canonical raspasy policy, **Then** undertrick mountain 0, undertrick direct whists 20 (10 per defender), raspasy 5 direct whists per trick at every stage.
4. **Given** a public online table, **When** the creator picks a variant, **Then** the worker substitutes the canonical rules and raspasy progression for that variant (see `workers/room-worker/src/public-tables.ts` `publicConfiguration`).

---

### User Story 5 – Unplayed outcomes: passed out, half-whist, without-three, misère (Priority: P2)

**Why this priority**: These short-circuit outcomes are common and must not require trick play.

**Independent Test**: Drive the engine to each terminal and read `engine.score` (`PreferansEngineTests` in `Tests/PreferansEngineCoreTests/PreferansEngineTests.swift`).

**Acceptance Scenarios**:

1. **Given** a declared 6♣, **When** both defenders pass, **Then** the deal ends `passedOut` with declarer pool +2 and no whists (`MatchSettingsTests.testUnboundedMatchNeverFiresGameOver`).
2. **Given** a declared 6♣ where the first defender passed and the second called half-whist, **When** the first defender passes again, **Then** the deal ends `halfWhist` with declarer pool +2 and the half-whister writes 4 whists (`testHalfWhistRequiresFirstDefenderSecondChanceAndScores`).
3. **Given** a 6♣ auction win, **When** the declarer concedes "without three" after the discard, **Then** declarer mountain +6, no pool, no whists (`testDeclarerCanConcedeWithoutThreeBeforeNamingContract`); at four players the dealer also writes nothing (`testWithoutThreeInFourPlayerDealScoresDeclarerTripleAndDealerNothing`).
4. **Given** a misère, **When** the declarer takes 0 tricks, **Then** pool +10; **When** the declarer takes 3 tricks, **Then** mountain +30 and defenders write nothing (`testFailedMisereChargesTenMountainPerDeclarerTrick`).

---

### User Story 6 – Contesting parties settle the remaining tricks (Priority: P2)

In an open game or misère, the declarer or a whister (misère: any active seat) proposes a final split between tricks; play pauses until every contesting party accepts (deal scored) or any party rejects (play resumes).

**Why this priority**: Saves playing out obvious endings; must never leak hidden cards or let bystanders block.

**Independent Test**: `Tests/PreferansEngineTests/SettlementTests.swift` and `Tests/PreferansEngineCoreTests/SettlementInformationTests.swift`.

**Acceptance Scenarios**:

1. **Given** a misère at the opening lead, **When** north proposes and east and south accept, **Then** the deal is scored from the agreed counts, `result.settlement` is set and `completedTricks` is empty ("Unanimous settlement scores the deal without fabricating tricks").
2. **Given** an open single-whist game, **When** the declarer proposes, **Then** only the whister's acceptance is needed; the passed defender can neither accept nor reject ("Only the contesting parties approve — a passed defender is excluded").
3. **Given** a closed game or an all-pass deal, **When** anyone proposes, **Then** the engine throws `illegalSettlement` ("Proposing a settlement in a closed game is rejected", "All-pass deals are played out, never settled").
4. **Given** a proposal whose counts do not total 10, **Then** the engine throws `illegalSettlement("Settlement final trick counts must total 10.")`.

---

### User Story 7 – Four-player table specifics (Priority: P3)

The dealer sits out each deal; their score still moves through talon compensation, raspasy participation, and American aid.

**Why this priority**: Only affects 4-seat tables.

**Independent Test**: `ScoringVariantTests` four-player helpers and `PulkaClosingTests.testFourPlayerMatchClosesAndAidsSittingOutDealer`.

**Acceptance Scenarios**:

1. **Given** a sitting-out dealer and a 6♣ game, **When** the talon held two aces / suited A-K / one ace / suited K-Q / nothing, **Then** the dealer writes 6 / 4 / 2 / 2 / 0 whists on the declarer (`testClassicDealerTalonCombinationsWriteContractWhists`).
2. **Given** a misère and a talon with suited 7-8 or two sevens, **Then** the dealer writes 20 whists on the declarer (Leningrad: 40) (`testMisereDealerTalonCompensationUsesTheVariantWhistScale`).
3. **Given** classic four-player raspasy, **When** the dealer takes 0 or 1 talon-led tricks, **Then** the dealer receives the clean-exit pool or a mountain point like any other trick taker (`testFourPlayerRaspasyDealerParticipatesInPenaltyAndCleanExit`).
4. **Given** Rostov four-player raspasy, **Then** the sitting-out dealer always receives the clean-exit pool point (`testRostovFourPlayerRaspasyCreditsTheSittingOutDealer`).

---

### User Story 8 – Dedicated totus (Priority: P3, engine-only)

**Why this priority**: Supported by the engine and fixtures but not exposed in the app lobby.

**Independent Test**: `MatchSettingsTests.testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin`.

**Acceptance Scenarios**:

1. **Given** `TotusPolicy.dedicatedContract(requireWhist: true, bonusPool: 5)`, **When** the totus declarer makes 10♠ against two whisters who take nothing, **Then** declarer pool +15 (10 + 5) and the second whister gets mountain +10.
2. **Given** `.asTenTrickGame`, **Then** `.totus` is not a legal bid; under `.dedicatedContract`, 10-level game bids are not legal (`testTotusBidIsIllegalWhenPolicyIsAsTenTrickGame`, `testTotusBidIsLegalAndTenTrickGamesSuppressedUnderDedicatedPolicy`).

### Edge Cases

- **Ten-trick contract without the whist convention**: the game starts immediately with `whisters == []`, open hands; it is scored like any game (pool 10 if made). On failure the declarer takes mountain + consolation (Sochi) and, under `.gentleman`, defenders additionally split `W × D` even though nobody whisted (see Known Gaps).
- **Both defenders pass a 10-trick contract under the whist convention**: `passedOut`, declarer credited pool 10 (+ totus bonus).
- **Totus "without three"**: mountain = 10 × mountain multiplier × 3 = 30 (Sochi).
- **Several clean exits in one raspasy** (e.g. 0/0/10): each zero-trick player receives the clean-exit pool; in Rostov the loser's payment is split among tied winners (25/25 for 10 tricks) with remainders going to the earlier seat.
- **Pool earned when already closed** (individual closure): flows to the open opponent with the highest pool (ties → earlier seat in `players`), earner writes `aid × poolPointWhistValue` whists on each recipient; any leftover after every pool is full reduces the earner's mountain, which can go negative.
- **Pool target not divisible by seat count** under individual closure: rejected at engine construction (`invalidMatch`) and at snapshot validation; `isPoolClosed` would return `false` forever.
- **Unbounded match** (`poolTarget == Int.max`): never ends; `poolTarget` is omitted from JSON.
- **Settlement while a trick is in progress**: rejected ("Settlements can only be offered between tricks."). A second concurrent proposal is rejected. The proposer is auto-accepted and can only cancel by rejecting.
- **Settlement that takes back tricks already won** or names a non-active target: rejected.
- **Equal balances at match end**: `leadingPlayers` lists all tied leaders; `soleWinner == nil`; `rank(of:)` returns the 1-based index of the first equal balance; ordering among equals is seat order.
- **Raspasy counter overflow**: increments saturate at `Int.max`; multipliers and exit minimums saturate at stage 2.
- **Legacy snapshots**: missing `match` → `.unbounded`; missing `consecutiveAllPassDeals` → 0; missing `raspasy` inside `match` → `.singleShot`; legacy `scoringMultiplier` → applied to pool, mountain and whist multipliers.

## Requirements

### Functional Requirements

#### Notation used below

`c` = declared `GameContract`; `v(c) = (c.tricks − 5) × 2` ∈ {2, 4, 6, 8, 10} (`GameContract.value`, `Domain.swift`); `Pm`, `Mm`, `Wm`, `Wd` = `poolValueMultiplier`, `mountainValueMultiplier`, `whistValueMultiplier`, `whistValueDivisor`; pool unit `P = v × Pm`; mountain unit `M = v × Mm`; whist unit `W = v × Wm / Wd` (`PreferansRules.recordedWhistValue`); `T_d` = declarer tricks; `D` = total tricks of both defenders (whisters and passer); `u = c.tricks − T_d` undertricks; `R` = effective whist requirement (FR-014). "X writes n on Y" = `whists[X][Y] += n`.

#### Score sheet and delta

- **FR-001**: The system MUST keep, per match, a `ScoreSheet` with an ordered `players` list and per-player `pool: Int`, `mountain: Int`, and a whist matrix `whists[writer][target]: Int`, initialised to zero for every seat (including the seat that sits out). — `Score.swift` `ScoreSheet.init(players:)`; `testFourPlayerMatchClosesAndAidsSittingOutDealer`.
- **FR-002**: The system MUST reject (precondition in code, `DecodingError` on decode) any score storage whose keys differ from the player set, whose pool or whist entries are negative, or that writes whists on oneself; mountain MAY be negative. — `Score.swift` `ScoreStorageValidator.validate`.
- **FR-003**: `ScoreDelta.addWhists` MUST ignore zero amounts and writer == target; `addPool`/`addMountain` MUST ignore zero amounts. — `Score.swift` `ScoreDelta`.
- **FR-004**: The only public mutator for applying a deal MUST be `ScoreSheet.apply(_:closingAtPoolTarget:poolClosure:poolPointWhistValue:)`, which returns the delta *as actually applied*; the engine MUST store that applied delta in the `DealResult` it emits. — `Score.swift` `apply`; `PreferansEngine.finalize`; `testEngineDealAppliesPulkaClosingToDealResultAndMatchSummary`.

#### Contract games (`scoreGame`)

- **FR-005**: If `T_d ≥ c.tricks`, the declarer MUST receive `pool += P + bonusPoolOnSuccess` (bonus non-zero only for a dedicated-totus win). — `ScoringEngine.swift` `PreferansScoring.scoreGame`; `testMadeContractCreditsPoolAndEachWhistersOwnTricks`, `testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin`.
- **FR-006**: If `T_d < c.tricks` and `declarerRemisePolicy == .mountainAndConsolation`, the declarer MUST receive `mountain += M × u`, and, when `failedDeclarerConsolation == .eachDefender`, **each defender** (whister or not) MUST write `W × u` on the declarer. With `.none` no consolation is written. — `scoreGame`, `applyDeclarerRemiseConsolation`; `testFailedDeclarerPaysMountainAndEachDefenderConsolationWhists`, `testFailedContractWithConsolationDisabledPaysNoDefenderConsolation`.
- **FR-007**: If `T_d < c.tricks` and `declarerRemisePolicy == .directWhistsPerDefender(k)`, the declarer MUST receive no mountain and each defender MUST write `k × u` on the declarer (Rostov: k = 10). — `scoreGame`; `testRostovDeclarerRemisePaysEachDefenderDirectWhists`.
- **FR-008**: Trick whists MUST be written according to `singleWhistScoring` and the number of whisters, evaluated in this order — `scoreGame` switch; tests listed per row:

  | Condition | Trick whists | Test |
  | --- | --- | --- |
  | `.greedy`, exactly 1 whister (made or failed) | whister writes `W × D` | `testSingleGreedyWhisterScoresAllDefenderTricksAndOwnResponsibility` |
  | `.gentleman`, exactly 1 whister, contract made | whister writes `W × D` | `testLeningradGentlemanWhistIsGreedyWhenDeclarerMakesContract` |
  | `.gentleman`, any whister count (0, 1, 2), contract failed | `W × D` split equally across **both defenders** (integer division; remainder +1 to the earliest defenders in `defenders` order) | `testRostovGentlemanWhistSplitsRemiseTricksAndConsolation`, `testRostovGentlemanWhistSplitsRemiseTricksWhenBothDefendersWhist`, `testLeningradScoringDoublesContractAndSplitsGentlemanWhist` |
  | otherwise (`.greedy` with 0 or 2 whisters, `.ownHandOnly` always, `.gentleman` made with 0 or 2 whisters) | each whister writes `W × own tricks` | `testOwnHandOnlySingleWhisterDoesNotScorePassedDefenderTricks`, `testJointWhistSuccessDoesNotPenalizeUnevenPartners` |

- **FR-009**: When `whistResponsibility != .none`, whisters exist and `R > 0`, the system MUST charge whister responsibility — `applyWhistResponsibility`:
  - one whister: `missing = max(0, R − D)` charged to that whister (`testSingleGreedyWhisterScoresAllDefenderTricksAndOwnResponsibility`);
  - two whisters with `D ≥ R`: no charge to either, even if one took fewer than half (`testJointWhistSuccessDoesNotPenalizeUnevenPartners`);
  - two whisters, `R == 1`, `D == 0`: `missing = 1` charged to the **second** whister only (`whisters.last`, i.e. `defenders[1]`) (`testOddOneTrickResponsibilityFallsOnSecondWhister`);
  - two whisters, `R ≥ 2`, `D < R`: quota `R / 2` per whister; each whister charged `max(0, quota − own tricks)` (`testFailedJointWhistChargesEachPartnerForTheirOwnHalfShare`, `testTwoWhistersEachPayEveryTrickMissingFromTheirHalfQuota`).
- **FR-010**: A charge of `missing` tricks MUST be recorded as — `applyWhistRemise`:
  - `.responsible`: whister `mountain += missing × M`;
  - `.semiResponsible`: whister `mountain += missing × M / 2` (integer division; exact for canonical values) (`testRostovWhistQuotaRemiseWritesHalfGameValueToMountain`);
  - `.directWhists(k)`: whister writes `(missing × M / 2) × k` on the declarer and on the other defender (see Known Gaps — sign);
  - `.none`: nothing (`testWhistResponsibilityNoneChargesNoQuotaMountainToWhisters`, `testWhistResponsibilityNoneLetsSingleWhisterMissQuotaFreely`).
- **FR-011**: Responsibility MUST be evaluated after declarer success/failure and trick whists, and is independent of whether the declarer made the contract. — `scoreGame` ordering.
- **FR-012**: Open vs closed defence (`DefenderPlayMode`) MUST NOT change any scoring arithmetic; it only affects who controls/sees the passer's hand and whether settlement is allowed. — `scoreGame` does not read `defenderPlayMode`; `State.swift` `PlayingState.controllingActor`, `settlementParties`.
- **FR-013**: Whist requirement by level MUST be: 6 → 4, 7 → 2, 8 → 1, 9 → 1, 10 → 0, except 10 → 1 when `rules.requireWhistOnTenTrickContracts` or `match.totus.requireWhist` is true. — `Rules.swift` `whistRequirement(for:)`; `ScoringEngine.swift` `effectiveWhistRequirement`.
- **FR-014**: `R` used by scoring MUST be `effectiveWhistRequirement` (FR-013, including the totus flag). — `effectiveWhistRequirement`; `testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin`.

#### Unplayed outcomes

- **FR-015**: **Passed out** (both defenders pass the whist decision; a single whister instead leads to the defender-mode choice): declarer `pool += P + bonusPoolOnSuccess`; no whists; four-player dealer talon compensation still applies; `trickCounts` are all zero. — `PreferansScoring.passedOut`; `testDealerTalonCompensationSurvivesPassOutAndHalfWhist`.
- **FR-016**: **Half-whist** (legal only for the second defender after the first passed, on contracts of ≤ 7 tricks; resolved when the first defender passes on the second chance): declarer `pool += P` (no bonus), half-whister writes `W × (R / 2)` on the declarer (6-level: `2W`; 7-level: `1W`); dealer compensation applies. If the first defender instead whists, play proceeds closed with whisters `[first, halfWhister]`. — `PreferansScoring.halfWhist`; `PreferansEngine+WhistReducer.swift`; `testHalfWhistRequiresFirstDefenderSecondChanceAndScores`.
- **FR-017**: **Without three** (declarer concedes in `awaitingContract`, i.e. after the discard and before naming a contract; illegal for misère): declarer `mountain += finalBid.value × Mm × 3`; no pool, no whists, no consolation, no dealer compensation, regardless of `declarerRemisePolicy`. — `PreferansScoring.withoutThree`; `PreferansEngine+ExchangeReducer.swift` `reduceConcedeWithoutThree`; `testDeclarerCanConcedeWithoutThreeBeforeNamingContract`, `testConcedeWithoutThreeIsRejectedForMisere`, `testWithoutThreeInFourPlayerDealScoresDeclarerTripleAndDealerNothing`.

#### Misère

- **FR-018**: Misère MUST score `pool += 10 × Pm` when the declarer takes 0 tricks, else `mountain += 10 × Mm × T_d`; defenders write nothing; `declarerRemisePolicy` is ignored (Rostov keeps the mountain penalty). — `PreferansScoring.scoreMisere`; `testFailedMisereChargesTenMountainPerDeclarerTrick`, `testRostovFailedMisereKeepsCanonicalMountainPenalty`, `testLeningradMisereKeepsTenPoolButDoublesRemise`, `testMisereDeclarerForcedToTakeEveryTrickMountainsOneHundred`.

#### Four-player dealer talon compensation

- **FR-019**: When `dealerTalonCompensation == .classic`, the table has 4 players and the dealer is not active, then for game, passed-out and half-whist results the dealer MUST write `W × t` on the declarer, where `t` is: two aces → 3; suited A-K → 2; one ace or suited K-Q → 1; otherwise 0 (first matching rule wins; talon must have exactly 2 cards). — `applyDealerGameTalonCompensation`, `dealerGameTalonTricks`; `testClassicDealerTalonCombinationsWriteContractWhists`, `testDealerTalonCompensationCanBeDisabled`.
- **FR-020**: Under the same conditions, a misère (made or failed) MUST make the dealer write `w × Wm` on the declarer, where `w` = 20 for a suited 7-8, else 10 per seven in the talon. — `applyDealerMisereTalonCompensation`; `testMisereDealerTalonCompensationUsesTheVariantWhistScale`.

#### All-pass (raspasy)

- **FR-021**: Let `k` = `consecutiveAllPassDeals` before this deal and `g = match.raspasy.scoreMultiplier(precededBy: k)`. Under `allPassPenaltyPolicy == .perTrick(m, amnesty)`, for every trick-taking player (`PlayingState.trickTakingPlayers`): if tricks == 0 and `zeroTricksAllPassPoolBonus > 0` then `pool += bonus × g` (not × m); `mountain += chargeable × m × g`, where `chargeable = tricks`, or `tricks − min(tricks of all trick takers)` with amnesty. — `scoreMountainAllPass`; `testCanonicalSochiRaspasyUsesTalonLeadAndChargesEveryTrick`, `testAllPassAmnestyChargesOnlyTricksAboveTableMinimum`, `testAllPassAmnestyWithZeroMinimumChargesFullTricksAndPaysCleanExitBonus`, `testAllPassPenaltyMultiplierDoublesMountainButNotPoolExitBonus`, `testZeroTricksAllPassPoolBonusZeroGrantsNoCleanExitPool`, `testSochiRaspasyPriceProgressesOneTwoThreeAndCaps`.
- **FR-022**: Under `.directWhistsToLowest(p)`: winners = trick takers with the minimum trick count; (4 players, dealer not active, bonus > 0) → dealer `pool += bonus`; each winner with 0 tricks → `pool += bonus` (no progression scaling); each non-winner pays `p × tricks`, split equally across winners in seat order (remainder +1 to the earliest winners), written as **winner writes on loser**. The raspasy progression multiplier MUST NOT apply. — `scoreDirectWhistAllPass`; `testRostovRaspasyUsesFixedDirectWhistsAndHiddenTalon`, `testRostovRaspasySplitsOpponentPaymentAcrossTiedWinners`, `testRostovFourPlayerRaspasyCreditsTheSittingOutDealer`.
- **FR-023**: Trick takers MUST be the three active seats, plus the sitting-out dealer in four-player raspasy with `allPassTalonPolicy == .classic` (the dealer owns the two talon-led opening tricks). — `State.swift` `PlayingState.trickTakingPlayers`, `isClassicFourPlayerAllPass`; `testFourPlayerRaspasyDealerParticipatesInPenaltyAndCleanExit`.
- **FR-024**: Raspasy price multipliers MUST be (stage = preceding consecutive raspasy deals, saturating at 2): `.flat` 1,1,1; `.arithmetic` 1,2,3; `.cappedDouble` 1,2,2; `.geometric` 1,2,4; `.singleShot` always 1. — `MatchSettings.swift` `RaspasyPolicy.scoreMultiplier`; `testRaspasyProgressionsExposeSupportedPriceAndExitStages`, `testRaspasyProgressionsSaturateForAnUnboundedSeriesCounter`.
- **FR-025**: The minimum game-contract level in the next auction MUST be: `.simple` 6,6,6; `.constrained` 6,7,7; `.strict` 6,7,8; `.singleShot` always 6; misère and dedicated totus remain legal at every stage. — `RaspasyPolicy.minimumGameTricks`; `PreferansEngine.isLegalBid`; `testStrictRaspasyExitFiltersSixThenSevenLevelGamesButKeepsMisere`.
- **FR-026**: After each scored deal the engine MUST increment `consecutiveAllPassDeals` (saturating at `Int.max`) for an all-pass result and reset it to 0 for every other result kind; the counter MUST persist in snapshots. — `PreferansEngine.finalize`; `PreferansSnapshot`; `testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`.

#### Pulka closing and match end

- **FR-027**: With `poolTarget == Int.max` or `poolClosure == .tableTotal`, the delta MUST be applied verbatim (no caps, aid or mountain relief). — `ScoreSheet.apply`, `applyRaw`; `testLeningradTableTotalLeavesIndividualPoolsOpenWithoutAmericanAid`, `testTableTotalAppliesPoolWithoutRequiringPlayerDivisibility`.
- **FR-028**: With `.individualWithAmericanAid`, the per-player target MUST be `poolTarget / players.count`; the delta MUST be applied in the order mountain → whists → pool (pool processed per player in seat order), and each positive pool award MUST: (1) fill the earner up to the target; (2) repeatedly give `min(remaining, room)` to the open opponent (pool < target) with the highest pool (ties → earlier seat in `players`), crediting the recipient's pool and making the earner write `aid × rules.poolPointWhistValue` on the recipient; (3) subtract any leftover from the earner's mountain. — `ScoreSheet.apply`, `applyPool`, `americanAidRecipient`; `testSurplusPoolAidsHighestOpenPlayerAndWritesWhists`, `testAidRecipientTieBreaksTowardEarlierSeatOrder`, `testSurplusPoolCascadesAcrossPlayersThenReducesMountainWhenEveryoneIsClosed`, `testFourPlayerMatchClosesAndAidsSittingOutDealer`.
- **FR-029**: The match MUST be closed when: individual closure → every player's pool ≥ `poolTarget / N`; table total → `Σ pool ≥ poolTarget`; unbounded → never. — `MatchSettings.isPoolClosed`; `testGameOverFiresWhenPoolSumCrossesTargetExactly`, `testGameOverDoesNotFireWhenPoolStaysBelowTarget`, `testUnboundedMatchNeverFiresGameOver`.
- **FR-030**: `finalize` MUST apply the delta, increment `dealsPlayed`, update the raspasy counter, emit `.dealScored(result)`, and, if the pool is closed, emit `.matchEnded(summary)` and enter `.gameOver(summary)`; otherwise enter `.dealFinished(result)`. `startDeal` from `.gameOver` MUST throw. — `PreferansEngine.finalize`, `reduceStartDeal`; `testStartDealFromGameOverThrows`.
- **FR-031**: Engine construction and snapshot rehydration MUST reject: `poolTarget ≤ 0` (unless `Int.max`), an individual target not divisible by the player count, a negative dedicated-totus bonus, and invalid rules values (non-positive multipliers/point values/penalty values, negative clean-exit bonus, a whist divisor that does not divide 2,4,6,8,10). — `MatchSettings.configurationError`, `PreferansRules.configurationError`, `PreferansEngine.validate`; `testIndividualClosureRejectsATargetThatCannotDivideAcrossSeats`, `testEngineRejectsNegativeDedicatedTotusBonus`, `testEngineRejectsRulesMutatedAfterInitialization`, `testRulesDecoderRejectsUnsafeScoringValuesWithoutTrapping`.
- **FR-032**: Snapshot invariants MUST require: individual pools never exceed the per-player target; `.dealFinished`/open states have an unclosed pool; `.gameOver` has a closed pool and a summary equal to the recomputed score, deals played and balances; `0 ≤ consecutiveAllPassDeals ≤ dealsPlayed`, and 0 after any non-raspasy result. — `PreferansEngine+Invariants.swift` `validateInvariants(_ snapshot:)`, `checkScoreAgainstMatch`, `checkGameOverSummary`, `checkRaspasySeriesCounter`.

#### Final balance

- **FR-033**: The final (and live) balance MUST be `raw_i = pool_i × P_pt − mountain_i × M_pt + Σ_j whists[i][j] − Σ_j whists[j][i]`, with `P_pt = rules.poolPointWhistValue`, `M_pt = rules.mountainPointWhistValue`, then `balance_i = raw_i − mean(raw)` (Double, zero-sum). — `ScoreSheet.normalizedBalances`; `PreferansEngine.makeMatchSummary`; `testLeningradFinalBalanceUsesDifferentPoolAndMountainRates`, `testAmericanAidProducesASoleWinnerIndependentOfLastDeclarer`.
- **FR-034**: `MatchSummary.standings` MUST be sorted by balance descending with seat order as the tie-break; `leadingPlayers` = all players with exactly the top balance; `soleWinner` only when exactly one leader; `rank(of:)` = 1 + index of the first standing with an equal balance; `nil` for unknown players. — `MatchSettings.swift` `MatchSummary`; `testMatchSummaryStandingsAreSortedByBalanceWithDeterministicTiebreak`, `testThreeEqualPoolsShareTheLeadAndProjectionNamesNoSoleWinner`.
- **FR-035**: The app MUST display balances with one decimal (POSIX locale), a leading `+` for positive values, and values with |x| < 0.05 shown as `0.0`. — `Preferans/UI/ScoreFormatting.swift` `ScoreFormatting.balance`.

#### Trick settlement (claims)

- **FR-036**: Settlement parties MUST be: 10-trick game with no whisters and no whist calls → all active seats; open game → declarer + whisters; closed game → none; misère → all active seats; all-pass → none. The same set governs who may propose, who must accept and who may reject. — `State.swift` `PlayingState.settlementParties`; SettlementTests "Open game lets the declarer and whisters offer…", "Misère lets the declarer and every defender offer", "Closed game never offers a settlement".
- **FR-037**: A proposal MUST be rejected unless the state is `.playing`, no proposal is pending, the current trick is empty, the proposer is an active settlement party, the target is active, final counts cover exactly the active seats, `finalTrickCounts[target] == targetTricks`, counts total 10, and each final count ≥ tricks already won. — `PreferansEngine+SettlementReducer.swift` `reduceProposeSettlement`; `PreferansEngine.validateSettlement`; "Settlement rejects impossible final counts".
- **FR-038**: The proposer MUST be recorded as accepted; while a proposal is pending no card may be played and `currentActor` MUST be the first active seat (seat order) that is a party and has not accepted. When the accepted set covers all parties, the deal MUST be scored with `trickCounts = finalTrickCounts`, `result.settlement` set, `completedTricks` = tricks physically played, emitting `settlementAccepted`, `playSettled`, `dealScored` (and `matchEnded`). Any party's rejection clears the proposal and resumes play. — `reduceAcceptSettlement`, `reduceRejectSettlement`, `scoreSettlement`; `DealState.currentActor`; "Unanimous settlement scores the deal without fabricating tricks", "Rejecting settlement resumes card play".
- **FR-039**: Suggested settlements (`legalSettlements(for:)`) MUST be: declarer gets 0 of the remaining tricks (remainder dealt round-robin to defenders in seat order), declarer gets all remaining, and — only at an empty 10th trick — the forced split provable from the viewer's own information; any other valid split MAY be proposed. — `PreferansEngine.candidateSettlements`, `forcedSettlement(in:knownTo:)`; "Any valid trick configuration may be agreed…", `testLastTrickSuggestionsDoNotExposeTheDeclarersHiddenCard`, `testDeclarerCanUseEveryExposedHandAndTheirOwnDiscard`.

#### Variants and presentation

- **FR-040**: The engine MUST provide the named rule profiles `.sochi` (= `PreferansRules()`), `.stalingrad`, `.leningrad`, `.rostov` (and alias `.sochiWithTalonLedAllPass == .sochi`) with the exact field values in the Variant Comparison table below. — `Rules.swift`; `testCanonicalSochiRaspasyUsesTalonLeadAndChargesEveryTrick`, `testRostovRaspasyUsesFixedDirectWhistsAndHiddenTalon`.
- **FR-041**: The app MUST map house variants to profiles: `odesa` → `.sochi` + individual closure + `.sochi` raspasy; `wien` → `.leningrad` + table total + `.leningrad` raspasy; `thessaloniki` → `.rostov` + individual closure + `.rostov` raspasy; `kruty` → `.stalingrad` + individual closure + `.sochi` raspasy; only the first three are offered for public tables. — `Preferans/UI/LobbyModels.swift` `PreferansVariant`; `Tests/PreferansServerCoreTests/PublicTableRulesTests.swift`.
- **FR-042**: The lobby MUST build `MatchSettings(poolTarget:, poolClosure: variant.poolClosure, raspasy: .progressive(penalties: <user choice>, exit: <user choice>))` with `poolTarget = perPlayer × seatCount` (presets 11 and 21 per player; custom 1…999 per player), except for a table-total variant with a custom limit, which uses the custom table total (default 63, 1…3996). Totus is never configured by the app (defaults to `.asTenTrickGame(requireWhist: false)`). — `Preferans/UI/LobbyViewModel.swift` `selectedMatchSettings`, `totalPulkaTarget`; `Preferans/UI/LobbyModels.swift` `PulkaLimit`.
- **FR-043**: The rules reference MUST display numbers produced by `PreferansRulebook.examples(rules:match:)` (contracts 6–10 made/failed-by-one/whist-per-trick, misère made/failed-by-one, raspasy stages 1–3 for a 0/4/6 split). — `ScoringEngine.swift` `PreferansRulebook`; `Preferans/UI/ConventionLegendSheet.swift`; `testExecutableRulebookUsesTheProductionScorer`.

### Key Entities

- **ScoreSheet / ScoreDelta** — cumulative and per-deal pool/mountain/whist ledgers (`Score.swift`).
- **DealResult / DealResultKind** — terminal deal record: `passedOut`, `withoutThree`, `halfWhist`, `game`, `misere`, `allPass`, plus trick counts, completed tricks, applied delta, opening hands and optional settlement (`State.swift`).
- **PreferansRules** — per-deal recording conventions and conversion rates (`Rules.swift`).
- **MatchSettings** — `poolTarget`, `PoolClosurePolicy`, `RaspasyPolicy`, `TotusPolicy` (`MatchSettings.swift`).
- **MatchSummary / Standing** — final score, deals played, last deal, sorted standings (`MatchSettings.swift`).
- **TrickSettlement / TrickSettlementProposal** — agreed final trick split and its acceptance set (`State.swift`).
- **PreferansRulebook examples** — engine-computed presentation tables (`ScoringEngine.swift`).
- **PreferansVariant / PulkaLimit** (app) — house-named convention and pulka length (`Preferans/UI/LobbyModels.swift`).

Field-level definitions, invariants, state machines and JSON shapes: [`data-model.md`](./data-model.md).

## Scoring Reference (normative tables and worked examples)

### Contract values per level

| Level | `v` | Whist requirement `R` | Sochi P / M / W | Leningrad P / M / W | Rostov P / M / W | Half-whist whists (Sochi / Len.) |
| --- | --- | --- | --- | --- | --- | --- |
| 6 | 2 | 4 (2 per whister) | 2 / 2 / 2 | 2 / 4 / 4 | 2 / 2 / 2 | 4 / 8 |
| 7 | 4 | 2 (1 per whister) | 4 / 4 / 4 | 4 / 8 / 8 | 4 / 4 / 4 | 4 / 8 |
| 8 | 6 | 1 (second whister) | 6 / 6 / 6 | 6 / 12 / 12 | 6 / 6 / 6 | — |
| 9 | 8 | 1 (second whister) | 8 / 8 / 8 | 8 / 16 / 16 | 8 / 8 / 8 | — |
| 10 | 10 | 0, or 1 with the 10-trick whist convention (Leningrad: 1) | 10 / 10 / 10 | 10 / 20 / 20 | 10 / 10 / 10 | — |
| Misère | 10 | — | pool 10 / 10 mtn per trick | pool 10 / 20 per trick | pool 10 / 10 per trick | — |

Per-trick penalty for a short whister (`missing × …`): Sochi/Stalingrad (responsible) `M` = 2/4/6/8/10; Leningrad (semi, doubled mountain) `M/2` = 2/4/6/8/10; Rostov (semi) `M/2` = 1/2/3/4/5.

Declarer undertrick, per undertrick: Sochi mountain `M` + each defender writes `W`; Leningrad mountain `2v` + each defender writes `2v`; Rostov no mountain, each defender writes 10.

### Variant comparison

| Setting | Sochi (`odesa`, "Vienna") | Stalingrad (`kruty`, "Kruty") | Leningrad (`wien`, "Prague") | Rostov (`thessaloniki`, "Berlin") |
| --- | --- | --- | --- | --- |
| `allowSeniorHandHoldBid` | true | true | true | true |
| `requireWhistOnTenTrickContracts` | false | false | **true** | false |
| `forceWhistOnSixSpades` | false | **true** (both defenders must whist 6♠, closed) | false | false |
| `singleWhistScoring` | greedy | greedy | gentleman | gentleman |
| `failedDeclarerConsolation` | eachDefender | eachDefender | eachDefender | none |
| `whistResponsibility` | responsible | responsible | semiResponsible | semiResponsible |
| `declarerRemisePolicy` | mountainAndConsolation | mountainAndConsolation | mountainAndConsolation | directWhistsPerDefender(10) |
| `allPassTalonPolicy` | classic | classic | classic | ignored (hidden talon) |
| `allPassPenaltyPolicy` | perTrick(1, no amnesty) | perTrick(1, no amnesty) | perTrick(2, no amnesty) | directWhistsToLowest(5) |
| `zeroTricksAllPassPoolBonus` | 1 | 1 | 1 | 1 |
| `dealerTalonCompensation` | classic | classic | classic | classic |
| `pool/mountain/whist ValueMultiplier` | 1 / 1 / 1 | 1 / 1 / 1 | 1 / **2** / **2** | 1 / 1 / 1 |
| `whistValueDivisor` | 1 | 1 | 1 | 1 |
| `poolPointWhistValue` / `mountainPointWhistValue` | 10 / 10 | 10 / 10 | **20** / 10 | 10 / 10 |
| Pool closure (app) | individual + American aid | individual + American aid | **table total** | individual + American aid |
| Canonical raspasy (`RaspasyPolicy`) | `.sochi` = arithmetic / strict | `.sochi` | `.leningrad` = arithmetic / strict | `.rostov` = flat / simple |
| Raspasy price, stages 1–3 | 1–2–3 | 1–2–3 | 2–4–6 | 5 direct whists, fixed |
| Clean-exit pool, stages 1–3 | 1–2–3 | 1–2–3 | 1–2–3 | 1 (fixed) |
| Exit minimum, stages 1–3 | 6–7–8 | 6–7–8 | 6–7–8 | 6–6–6 |
| Public table | yes | no (local/private only) | yes | yes |

"Classic" in the README is not a separate profile: the engine default `PreferansRules()` is Sochi, and `.classic` is only a value of `AllPassTalonPolicy` and `DealerTalonCompensation`.

Other `MatchSettings` options and defaults: `poolTarget` = `Int.max` (unbounded); `poolClosure` = `.individualWithAmericanAid`; `raspasy` = `.sochi` (constructor) but `.singleShot` when absent from decoded JSON; `totus` = `.asTenTrickGame(requireWhist: false)`. Lobby defaults: pulka 21 per player (online creation resets to 11), raspasy price `.arithmetic`, exit `.strict` (persisted in `UserDefaults`).

### House names shown to users

| Persisted id | English title | Ukrainian | Russian | Subtitle (en, `variant.*.standard`) | Summary (en) |
| --- | --- | --- | --- | --- | --- |
| `odesa` | Vienna | Відень | Вена | Balanced scoring | Balanced house default. |
| `wien` | Prague | Прага | Прага | Double whists, shared pool | Double whists, hard all-pass, and one shared table pool. |
| `thessaloniki` | Berlin | Берлін | Берлин | Semi-responsible whist, hidden talon on all-pass | Standard trick whists, semi-responsible defense, gentleman remise, and fixed-price hidden-talon raspasy. |
| `kruty` | Kruty | Крути | Круты | Kruty · Stalingrad | Both defenders must whist on 6♠ with closed hands. |

The rules sheet (`ConventionLegendSheet`) shows, per convention: an "At a glance" grid (pool closing per player vs shared table total; whist Responsible/Semi-responsible; four-player dealer talon compensation on/off; raspasy price sequence; exit minimum sequence), the contract table (made pool, undertrick mountain — or direct whists for Rostov — and whist per defender trick), misère made/one-trick pills, three raspasy stage cards (price, exit minimum, clean exit, 0/4/6 mountain or direct whists) and prose for pool closing, whist style, Stalingrad on/off, talon lead and dealer talon. Opened in-game it is locked to the table's actual `rules` and `match` (so a local Berlin table shows its user-chosen exit progression); opened from the lobby it shows the canonical variant match settings. The UI surfaces (score sheet, pulka "envelope" diagram, game-over card) are documented in [`../005-ios-app`](../005-ios-app/).

### Worked examples (3 players: north declarer, east and south defenders, unless stated)

| # | Situation | Result |
| --- | --- | --- |
| E1 | Sochi 6♣, both whist, 6/2/2 | N pool +2; E→N 4; S→N 4 |
| E2 | Sochi 7♥, both whist, 5/3/2 (u = 2) | N mountain +8; E→N 3·4 + 2·4 = 20; S→N 2·4 + 8 = 16 |
| E3 | Sochi 6♦, E whists alone (greedy), 7/1/2 | N pool +2; E→N 2·3 = 6; E mountain +2 (R 4 − D 3 = 1 × M 2) |
| E4 | Same with `.ownHandOnly` | E→N 2; E mountain +2 |
| E5 | Sochi 8♠, both whist, 10/0/0 | N pool +6; S (second whister) mountain +6 |
| E6 | Sochi 6♣, both whist, 7/0/3 | N pool +2; S→N 6; E mountain +4 (quota 2, took 0); S 0 |
| E7 | Leningrad 6♣, E whists alone, 4/4/2 (u = 2) | N mountain 4·2 = 8; split 4·6 = 24 → 12 each, + consolation 4·2 = 8 → E→N 20, S→N 20 |
| E8 | Rostov 7♥, both whist, 6/2/2 (u = 1) | N mountain 0; split 4·4 = 16 → 8 each, + direct 10 → E→N 18, S→N 18 |
| E9 | Rostov 6♦, E whists alone, 7/1/2 | N pool +2; E→N 6; E mountain 1·2/2 = 1 |
| E10 | Sochi half-whist on 6♣ / 7♠ | N pool +2 / +4; half-whister → N 4 / 4 |
| E11 | Without three on 6-level / 8-level / totus (Sochi); 6-level Leningrad | N mountain 6 / 18 / 30; 12 |
| E12 | Sochi misère 0 tricks / 3 tricks; Leningrad 1 trick | pool +10 / mountain +30; mountain +20 |
| E13 | 4 players, dealer west, 6♣, talon A♠ A♥ | W→N 2·3 = 6 (on top of the normal game score) |
| E14 | Sochi raspasy 0/4/6 at stage 1 / 2 / 3 | N pool +1/+2/+3; E mountain 4/8/12; S mountain 6/12/18 |
| E15 | Leningrad raspasy 0/4/6 at stage 3 | N pool +3; E mountain 24; S mountain 36 |
| E16 | Rostov raspasy 0/4/6; and 0/0/10 | N pool +1, N→E 20, N→S 30; N and E pool +1 each, N→S 25, E→S 25 |
| E17 | Rostov raspasy 1/1/8 (no clean exit) | no pool; S pays 5·8 = 40 split between the tied winners: N→S 20, E→S 20 |
| E18 | Individual target 33 (11 each), pools 10/10/10, N passes out 7♣ (+4) | N +1 (11); aid E +1 (tie with S → earlier seat; N→E 10); aid S +1 (N→S 10); leftover 1 → N mountain −1; pools 11/11/11 → match over |
| E19 | Final balance, Sochi, pools 11/11/11, mountains N 4, E 10, S 0, whists N→E 20, E→N 8, S→N 12, S→E 6 | raw N = 110 − 40 + 20 − 20 = 70; E = 110 − 100 + 8 − 26 = −8; S = 110 + 18 = 128; mean 63.33 → N +6.7, E −71.3, S +64.7 |
| E20 | Leningrad final, pool N 1, mountain E 1, nothing else | raw 20 / −10 / 0 → +16.67 / −13.33 / −3.33 |
| E21 | Sochi target 6, N passes 7♠ then E passes 6♠ (MatchOutcomeTests) | N→E 20 (aid), E→S 20 (aid), pools 2/2/2 → balances +20 / 0 / −20 |

E19 equals the classical pairwise conversion: mountain differences amortised as `(m_j − m_i) × 10 / N` whists per pair sum to `10 × (mean(m) − m_i)` per player, so centring by the mean (FR-033) reproduces the textbook settlement. The engine produces only per-player net balances; it does not emit a pairwise payment ledger.

### Rounding

All deal scoring is integer arithmetic. Integer divisions occur in: semi-responsible penalty `missing × M / 2`; half-whist `R / 2`; two-whister quota `R / 2`; gentleman split and Rostov tied-winner split (base + remainder to earlier seats); `W = v × Wm / Wd` (the divisor is validated to divide every contract value). With canonical profiles every division is exact: `W` is always even, so a gentleman split of `W × D` between two defenders is exact, and in three-seat Rostov raspasy two tied winners always face a loser with an even trick count (`10 − 2a`). Remainders (+1 to the earlier seat) only appear with house values such as `whistValueDivisor = 2` or an odd `pointsPerTrick`. Final balances are `Double` (thirds/quarters possible); the UI rounds to 0.1.

### Three- vs four-player differences

| Aspect | 3 players | 4 players |
| --- | --- | --- |
| Active seats | all three; rotation starts after the dealer, dealer bids last | the three seats after the dealer; dealer sits out |
| Score sheet | 3 rows | 4 rows; the sitting-out dealer can still gain/lose |
| Individual pool target | `poolTarget / 3` (lobby: 33 or 63) | `poolTarget / 4` (lobby: 44 or 84); dealer can receive American aid |
| Dealer talon compensation | n/a | dealer writes whists on the declarer for talon aces/A-K/K-Q (games, passed out, half-whist) and sevens (misère); not on without-three |
| Raspasy | three trick takers; classic talon only sets the lead suit of tricks 1–2 | classic: dealer owns talon cards, leads tricks 1–2 and can win them → is a trick taker (mountain/clean exit); Rostov (hidden talon): dealer always gets the clean-exit pool point |
| Balance mean | over 3 | over 4 |

## Success Criteria

### Measurable Outcomes

- **SC-001**: Worked examples E1–E9, E12–E16, E18, E20 and E21 are asserted verbatim by existing tests or by `PreferansRulebook.examples` (test names in FR-005…FR-034 and `testExecutableRulebookUsesTheProductionScorer`); E10 (7-level), E11 (8-level, totus, Leningrad), E17 and E19 are hand-derived from the same formulas and are not separately pinned by a test.
- **SC-002**: For any finished match, `Σ standings.balance = 0` within 1e-8 (`BotSimulationReportTests` checks every simulated match; `checkGameOverSummary` re-derives balances on rehydration).
- **SC-003**: No individual pool exceeds `poolTarget / N` after any applied deal (`checkScoreAgainstMatch`; every `PulkaClosingTests` case).
- **SC-004**: The worker's public presets decode to exactly `.sochi`, `.leningrad`, `.rostov` (`PublicTableRulesTests.testWorkerPublicPresetsMatchTheActualSwiftScoringRules`).
- **SC-005**: Invalid persisted rules or match settings fail as `DecodingError`, never as a trap (`testRulesDecoderRejectsUnsafeScoringValuesWithoutTrapping`, `testDecodingRejectsNegativeDedicatedTotusBonus`).
- **SC-006**: Raspasy multipliers and exit minimums match FR-024/FR-025 for stages 0–3 and `Int.max` (`testRaspasyProgressionsExposeSupportedPriceAndExitStages`, `testRaspasyProgressionsSaturateForAnUnboundedSeriesCounter`).
- **SC-007**: Settlement suggestions are identical across hidden-card worlds that a viewer cannot distinguish (`testLastTrickSuggestionsDoNotExposeTheDeclarersHiddenCard`).

## Known Gaps & Open Questions

1. **README is stale on house names.** README lists "Одеса, Wien, Θεσσαλονίκη, Крути with hover/tap hints back to Sochi/Leningrad/Rostov/classic". The shipped strings are Vienna/Prague/Berlin/Kruty (en), Відень/Прага/Берлін/Крути (uk), Вена/Прага/Берлин/Круты (ru); hints describe the scoring ("Balanced scoring", "Double whists, shared pool", …) and only Kruty names its standard (Stalingrad). Kruty maps to Stalingrad, not "classic". The persisted ids (`odesa`, `wien`, `thessaloniki`, `kruty`) are unchanged (`docs/PUBLIC_LOBBY.md` is accurate).
2. **Comment vs code — Leningrad whist scale.** `Rules.swift` (`whistValueDivisor` doc) says "Canonical Sochi, Leningrad, and Rostov profiles all record ordinary trick whists at the contract's normal value", but `.leningrad` sets `whistValueMultiplier: 2`, and tests pin doubled trick whists (`testLeningradKeepsPoolBaseValueAndDoublesMountainAndWhists`). `AppStore/BuildHistory.md` says Leningrad has "doubled contract values"; in code only mountain and whists double — pool keeps 2/4/6/8/10.
3. **`.directWhists(pointsPerMountainPoint:)` responsibility is unused and its direction looks inverted.** The whister *writes* whists on the declarer and the other defender, which credits the penalised whister. Rostov switched to `.semiResponsible` (commit `04ab5d3`); the analogous raspasy direction bug was fixed in `bbfa335`. [NEEDS CLARIFICATION: remove the case, or flip writer/target?]
4. **Without-three ignores the remise convention.** It always charges `3 × value × Mm` mountain and pays no consolation, also under Rostov (where a played 3-undertrick failure would instead cost 30 direct whists per defender and no mountain). [NEEDS CLARIFICATION: intended house rule?]
5. **Gentleman split with zero whisters.** In Rostov, a failed 10-trick open check (no whist phase) still splits `W × D` between both defenders. [NEEDS CLARIFICATION]
6. **Lobby raspasy controls override the convention's canonical progression for local and private tables.** A local Berlin (Rostov) table uses the user's persisted pair (default arithmetic/strict): the price is ignored by `.directWhistsToLowest`, but the strict exit (6–7–8) applies, unlike public Berlin tables (flat/simple) and the lobby rules sheet. Public tables hide the controls and the worker substitutes canonical values.
7. **Dedicated totus is engine-only** (not configurable in the app). Its bid order (16) sits between misère (15) and 9♠ (17), so 9♠ overcalls a 10-trick totus (`testNineSpadesCanOvercallTotusButTotusCannotOvercallNineSpades`) — deliberate per the test, but unusual.
8. **Half-whist never adds `bonusPoolOnSuccess`** — unreachable today (half-whist requires ≤ 7 tricks), but commit `b9e44d9`'s message claims the bonus is credited on the half-whist path.
9. **No pairwise settlement output.** Users see per-opponent whists written and a net balance; there is no "who pays whom" breakdown.
10. **`ConventionLegendSheet` labels** any responsibility other than `.semiResponsible` as "Responsible" (would mislabel `.none`/`.directWhists` house rules — not reachable from the app).
11. Decoder default for a missing `raspasy` key is `.singleShot`, while the Swift initializer default is `.sochi`; both intentional for legacy data but easy to confuse.
