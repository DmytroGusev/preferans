# Research: Preferans Rules Engine – design decisions (as-built)

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828` · **Primary code**: `Sources/PreferansEngine/` (engine, domain, state, rules, invariants, deal sources)

This document reconstructs the design decisions behind the rules engine from the code, the doc comments, the tests and the git history (`git log -- Sources/PreferansEngine/`, 127 commits touching the directory, from `ed331ce` "Reimplement Preferans around engine package" on 2026-05-01 to `b2c1d76` on 2026-09-23). Many commits have only a subject line. Where the rationale is not written down anywhere it is marked **(inferred)**.

Related: [spec.md](./spec.md), [data-model.md](./data-model.md); neighbouring areas [002](../002-scoring-and-variants/), [003](../003-bots/), [004](../004-online-multiplayer/), [006](../006-testing-and-release/).

---

## 1. One value-type aggregate with pure, throwing reducers

**Decision**: `PreferansEngine` is a `Sendable` struct. The whole match lives in its fields (`players`, `rules`, `match`, `state`, `score`, `nextDealer`, `dealsPlayed`, `consecutiveAllPassDeals`). `apply(_:)` dispatches to a reducer that returns `EngineTransition { state, events }`. `dispatch` assigns `state` only after the reducer returns, and reducers validate every input before they touch match-level fields.

**Rationale**:
- A value type can be copied freely. This is how bots run rollouts (`applyRolloutCard` on a copy), how the host takes snapshots, and how tests fork positions.
- A struct with no references is trivially `Sendable` under Swift 6 strict concurrency (adopted in `eb7f5cb`, "Adopt Swift 6 language mode across all targets").
- Errors are atomic: a throw leaves the engine untouched, which `PreferansEngineTests.testConcedeWithoutThreeIsRejectedForMisere` asserts.
- The same engine runs unchanged inside the iOS app, the Linux `PreferansServer` (Hummingbird) and the engine-only test lane. The `DealSource.swift` doc comment mentions Linux and WebAssembly portability.

**Alternatives considered**:
- (a) A reference-type game object mutated in place. Rejected **(inferred)** because copying and forking would need deep copies, and the type would fight `Sendable`.
- (b) A Swift `actor` engine. Rejected **(inferred)**: isolation belongs to the hosts (`HostGameActor`, `AuthoritativeGameService`), which serialize commands, while the engine stays synchronous and deterministic.
- (c) Pure event sourcing, rebuilding state from events. Partly present: events are emitted and the app has `GameLogReplayer`. Snapshots stay the source of truth, because events alone do not carry hidden information such as hands.

**Evidence**: `PreferansEngine.swift` (`apply`, `dispatch`, `reduce`); `EngineTransition.swift`; commit `d64a8ce` "Split engine phase reducers" (2026-05-04). Before that commit, reducers such as the 10-trick branch added in `493dc86` assigned `state = …` directly and returned events. The split moved them to returned transitions.

---

## 2. Phase-per-case state enum with copied-forward payloads

**Decision**: `DealState` has 9 cases. Each in-deal case carries its own struct (`BiddingState`, `ExchangeState`, `ContractDeclarationState`, `WhistState`, `DefenderModeState`, `PlayingState`), and each reducer builds the next struct by copying the fields it needs forward (`dealer`, `activePlayers`, `hands`, `talon`, `discard`, `declarer`, …).

**Rationale (inferred)**: Illegal combinations become unrepresentable. For example, there is no "discard" before the exchange and no `whistCalls` during bidding. Exhaustive `switch`es make the compiler point at every place a new phase must be handled. The invariants file says "Adding new state arms or new mutators? Add the matching invariant". Every payload keeps `talon` after the exchange "for projections and replay" (comment on `checkExchangedTalon`).

**Alternatives considered**: One flat state struct with optionals and a `phase` tag. That would need runtime checks for every field/phase combination, which the per-case design gets from the type system **(inferred)**.

---

## 3. Split reducers by phase into extension files

**Decision**: There is one file per phase: `+BiddingReducer`, `+ExchangeReducer` (discard, declare, concede), `+WhistReducer` (whist, defender mode), `+PlayReducer` and `+SettlementReducer`. Cross-phase helpers (`isLegalBid`, `legalWhistCalls`, `makePlayingState`, `completeCurrentTrick`, `finalize`, the settlement validation) stay in `PreferansEngine.swift`.

**Rationale**: Readability and change isolation. Commit `d64a8ce` moved about 450 lines out of `PreferansEngine.swift`. Commit `7b7bdd4` ("Refactor engine internals per audit") later moved the invariant validator (then 384 lines, "~55% of PreferansEngine.swift") into `PreferansEngine+Invariants.swift` verbatim, so the engine file holds only its logic.

**Alternatives considered**: Separate reducer types per phase with their own state. Not taken **(inferred)**, because the reducers need shared engine context (`rules`, `match`, `consecutiveAllPassDeals`, scoring), which extensions get for free.

---

## 4. Two error channels: recoverable `PreferansError` vs trapping `InvariantViolation`

**Decision**: Bad input (wrong turn, illegal card, bad deck, bad configuration) throws `PreferansError`, which callers can recover from. Structural corruption is an `InvariantViolation`. After every successful `apply`, `assertInvariants()` runs the full validator and calls `preconditionFailure` if it fails. The validator itself throws, so tests can assert which invariant fired.

**Rationale**: From commit `866cbc6` ("Enforce DealState invariants explicitly on every transition"): "The validator throws `InvariantViolation` so tests can assert each rule fires; the wrapper traps via `precondition` so production violations are loud." The same commit replaced `?? 0` trick-count defaults in scoring with the trapping `tricks(_:in:)` helper, because "those defaults previously masked missing trickCounts keys as silent zeros."

**Alternatives considered**:
- Silent defaults: removed by `866cbc6`.
- Debug-only `assert`: not used, because `preconditionFailure` also fires in release builds **(inferred: loudness in production was the stated goal)**.

**Consequence**: A reducer bug crashes the host instead of rejecting one command (see spec Known Gap 14).

---

## 5. Snapshot rehydration is a trust boundary, so invariants replay the whole history

**Decision**: `init(snapshot:)` runs the snapshot validator before it adopts any field. The validator grew from shape checks into full derivations:
- the auction ledger is rederived from `calls` (`checkBiddingLedger`);
- the whist history must sit at one of three reducer-owned checkpoints (`checkWhistDecisionFlow`, `checkDefenderModeFlow`);
- the talon must be traceable to the declarer's hand, the discard or played cards (`checkExchangedTalon`);
- the card-play history is replayed from reconstructed opening hands, checking lead order, follow-suit and trump duty, winners and the next actor (`checkPlayedHistory`);
- the raspasy counter must match the last result (`checkRaspasySeriesCounter`);
- the ten-trick defence form must match the rules (`checkTenTrickDefenseState`);
- the score must be consistent with the match closure policy.

**Rationale**: The doc comments say so directly. "A recovered multiplayer snapshot crosses a trust boundary and must prove the same facts" (`checkPlayedHistory`). "The auction's derived fields are security-relevant recovery state, not disposable UI caches … so a malformed host snapshot cannot reopen a bid that was already forfeited" (`checkBiddingLedger`). "Recovery must not reinterpret one form as the other" (`checkTenTrickDefenseState`). The hardening commits follow the server-authoritative rebuild (`124bdb8` "Rebuild authenticated multiplayer and host recovery", 2026-07-31): `3c7061a` auction history, `3151587` whist decisions, `780f4a6` trick accounting, `413fae8` card-play history, `41b93bd` talon provenance, `1716596` score ledgers, `f2ee50e` raspasy lifecycle, `0319a9b` ten-trick form, all from 2026-08-01.

**Alternatives considered**:
- (a) Trust the host's persisted state. Rejected, because persisted state reaches the Linux server and Cloudflare storage and may be tampered with or corrupted.
- (b) Replay the action log instead of validating a snapshot. That would need the deck/seed and every action. The app keeps a log (`GameLogReplayer`) but recovery uses snapshots **(inferred)**.

**Cost**: Full history replay on every `apply`. `ff414f5` ("perf(bots): avoid repeated history assertions in private rollouts") added `applyRolloutCard`, which skips `assertInvariants` for bot simulations that start from an already validated snapshot. Its comment says replaying history after every simulated card "makes Debug bot matches spend most of their time in assertions."

---

## 6. Deterministic, portable deck supply that the engine does not own

**Decision**: The engine takes a deck through `startDeal(dealer:deck:)` and falls back to the system RNG only when no deck is supplied. Hosts get decks from a `DealSource`: `RandomDealSource`, `SeededDealSource` (pure-Swift xoshiro256** seeded through SplitMix64) or `ScriptedDealSource` (cycles fixtures). `Deck.shuffled(seed:)` exposes seeded shuffles directly. The server derives one seed per deal (`AuthoritativeGameService.authoritativeAction`: `dealSeed &+ generatedDealCount &* 0x9E3779B97F4A7C15`).

**Rationale**: From `d6df8b1` ("Add deterministic deal sources and scenario-driven test suite"): a DealSource abstraction "plumbed through GameViewModel and a TestHarness that turns launch arguments into pinned dealer + reproducible deck". From the `DealSource.swift` comment: "Keeping this in pure Swift lets the exact same engine run on Apple devices, Linux servers, and WebAssembly without depending on Apple-only GameplayKit." `74aaaf1` ("Synchronize deal sources across actors") added the `NSLock`s, because sources cross actor boundaries ("Stateful implementations serialize their RNG/index mutation internally").

**Alternatives considered**:
- GameplayKit's `GKMersenneTwisterRandomSource`: rejected as Apple-only (stated).
- Letting the engine own a source: not done **(inferred)**, so that the engine stays a value type and the host stays authoritative over the deck.

**Risk**: Byte-for-byte reproducibility of `shuffled(using:)` depends on the Swift standard library's shuffle algorithm (inferred). Persisted snapshots carry the dealt hands, so recovery does not depend on it.

---

## 7. Canonical packet deal layout with an exact inverse for fixtures

**Decision**: `DealDeckLayout.deal` deals 5 packets of 2 cards per active seat and inserts the 2-card talon after the first packet. `DealDeckLayout.deck(hands:talon:activePlayers:)` is the exact inverse, and `HandRecipe` and the scenario fixtures use it.

**Rationale**: "Test fixtures and scripted decks use the inverse operation here so their desired per-seat hands stay tied to the same packet layout the engine consumes" (type doc comment). `d6df8b1` describes the fixtures as "constructed via the same 5-packet pattern the engine deals with."

**Alternatives considered**: Dealing by contiguous blocks (as the invariant-test fixtures do by hand). Rejected for real deals **(inferred)**, to mirror the traditional two-card dealing rhythm.

---

## 8. A fixed integer bid ladder with reserved gaps

**Decision**: `ContractBid.order` is a static, strict total order. Games use `(tricks−6)·5 + strain` with +2 from the 9-level upward, misère is 15 and totus is 16, so the order runs … 8NT (14) < misère < totus < 9♠ (17) … 10NT (26). Match policy filters legality (dedicated totus, raspasy exit minimum) without changing the order.

**Rationale**: From `23a42e2` ("Give Totus a distinct auction rank") and the comment in `GameContract.bidOrder`: "Totus may be disabled by match policy, but the static Comparable order must still remain strict and transitive." Before that commit the offset was +1, so totus (16) tied with 9♠ (16). `MatchSettingsTests.testTotusOrderingPlacesItDirectlyAboveMisere` now asserts that all 27 orders are distinct and that 9♠ overcalls totus.

**Alternatives considered**: A per-match dynamic ordering, for example totus at the top. Not taken. The tests deliberately keep 9♠ above totus.

---

## 9. Separate `PreferansRules` (one deal) from `MatchSettings` (the match)

**Decision**: `PreferansRules` holds rule and scoring conventions for a single deal: the hold bid, the ten-trick whist convention, Stalingrad, the single-whist control and scoring, the raspasy talon policy and scoring scales. `MatchSettings` holds whole-match behaviour: `poolTarget`, `poolClosure`, the raspasy price and exit progression, and the totus model. The raspasy streak counter (`consecutiveAllPassDeals`) is engine match state, not deal state.

**Rationale**: From `b9e44d9` ("Add match-level settings, totus contract, and game-over terminal state") and the `MatchSettings` doc comment: "`rules` configures *one deal*; `MatchSettings` configures the match those deals are accumulating into." The field comment on `consecutiveAllPassDeals` says: "This is match state, not deal state: it drives the next all-pass price and the minimum ordinary contract allowed in the next auction." Pool closure became a match-level policy rather than a scoring multiplier (doc comment on `PoolClosurePolicy`).

**Alternatives considered**: A single configuration object. Not taken **(inferred)**, because the lobby combines a rules profile with independently chosen pulka length, closure and raspasy options (`PreferansVariant.rules`, `.poolClosure`, `.raspasy`, plus the user-selected progressions in `LobbyViewModel.selectedMatchSettings`).

---

## 10. Ten-trick contracts: from "skip whist" via "forced whist" to "open check or ordinary whist"

**Decision**: A declared 10-trick contract starts immediately as an **open check**: all hands open, no whisters, and every active seat may settle. It goes through the ordinary `[pass, whist]` decision (never half-whist) only when `rules.requireWhistOnTenTrickContracts` (Leningrad/"Wien") or `match.totus.requireWhistOnTenTricks` is set. Invariants stop a recovered state from mixing the two forms.

**History**:
1. `493dc86` (2026-05-04) "Make ten-trick contracts skip whist": play started immediately, with *closed* mode.
2. `1b69609` (2026-07-09) "Implement mandatory whist on ten-trick contracts": the rules flag had had no effect, so with the flag on, each defender's only legal call became `.whist`, "mirroring the existing Stalingrad forced-whist precedent."
3. `0319a9b` (2026-08-01) "Correct ten-trick checking and whist choices": removed the forced `.whist`, made the unwhisted ten `.open`, and added the `checkTenTrickDefenseState` invariants. The comments now say the property name is historical: "this does not force a defender to whist."

**Rationale**: The current code comment explains it: "Without the optional whist convention, a ten-trick contract is checked with all hands open and no defensive risk." The projection reveals all hands for an open check ("A non-whisted ten is checked, not defended: every seat sees the complete layout").

**Alternatives considered**: Both earlier behaviours, which are recorded above. `AppStore/BuildHistory.md` (build 25) still describes the intermediate "mandatory whist" behaviour.

---

## 11. Stalingrad as an explicit opt-in convention

**Decision**: Forced closed whisting on 6♠ is active only with `PreferansRules.forceWhistOnSixSpades` (the profile `PreferansRules.stalingrad`, lobby `kruty`).

**Rationale**: `b562220` ("Make Stalingrad an explicit whist convention"). Before it, `isStalingradContract` was `contract == 6♠` unconditionally. The `Rules.swift` comment says: "This is a table agreement, not an intrinsic part of either the Sochi or Leningrad profile," and "Keeping it as a named profile prevents the lobby from silently reconstructing a subtly different set of rules." The wire format writes the key only when it is true, so old payloads decode as `false`.

---

## 12. Settlement: one source of truth for who may offer and who must approve

**Decision**: `PlayingState.settlementParties` is the only definition. It covers the declarer plus the whisters in an open game, every active seat in an open ten-check or a misère, and nobody in closed or all-pass play. Offers, the `currentActor` clock, `canAccept`/`canReject`, the reducer's unanimity check and the projection all read from it. Any `validateSettlement`-valid split may be proposed. `legalSettlements` offers only anchors (concede all, claim all, and the forced split at the last trick), and that forced split is computed only from information the viewer has.

**Rationale**: From `a66597b` ("Fix settlement: one approval authority across all paths"): "Settlement had three halves that each encoded a different rule, so they never agreed … Make PlayingState.settlementParties the single source of truth." From `f1f42f3`: only sides "whose cards are on the table may settle" (open games and misère). `a38857d` replaced preset offers with a tug-of-war composer, so the engine "never has to enumerate the continuum" (`candidateSettlements` comment). `14fafcb` ("prove settlement outcomes from visible information") added `forcedSettlement(in:knownTo:)`, which enumerates the 3 unseen cards for a defender and "never consult[s] which allocation really occurred."

**Alternatives considered**:
- Gating settlement only on forced remaining play: the original `a765d0c`, replaced by `f1f42f3`.
- Requiring all active seats, the passer included, to approve: replaced in `a66597b`.

---

## 13. Controlling actor for open single-whist (greedy) play

**Decision**: When exactly one defender whists, plays **open**, and scoring is `greedy`, the whister plays the passer's cards. `PlayingState.controllingActor(of:rules:)` resolves this. Actions still name the seat whose card is played, and the host checks that the *sender* is the controller.

**Rationale**: From `7efd0ae` ("Let lone whister pull the passer's cards in single-whist play"): "the passer's tricks are credited to the whister anyway — but the whister could not actually play those cards … Introduce a controlling-actor concept the engine, projection, bot dispatcher, and multiplayer host all share." Later, `c259c90` ("Fix closed single-whist control leak") and `b544e70` ("Keep closed single-whist hands player-controlled") limited the transfer to open mode. The `greedy` requirement ties control to who is credited with the tricks **(inferred from the doc comment)**. A pending settlement short-circuits control, because "settlement proposals are individual agreements."

**Alternatives considered**: Letting the passer keep playing an exposed hand that someone else is credited for. That was the original behaviour, and it is still what happens under `ownHandOnly` and `gentleman` scoring.

---

## 14. Four-player raspasy: the dealer owns the talon leads

**Decision**: Under the `classic` talon policy at a 4-seat table, the sitting-out dealer is the leader of tricks 1–2 with `talon[0]` and `talon[1]`. The card is stored as `Trick.talonLead` (not in `plays`, because it stays in `talon`), it competes for the trick, and the dealer becomes a trick taker. Under every talon-led policy the forehand starts tricks 1, 2 and 3. At 3 seats (or under `leadSuitOnly`) the talon only sets the suit.

**Rationale**: From `18069a9` ("Fix dealer-owned four-player raspasy leads") and the `Rules.swift` comment: "At a four-player table the sitting-out dealer owns those cards and may win either of the first two tricks." `leadSuitOnly` is kept as "House-rule compatibility". The `talonLead` doc comment explains why it is not repeated in `plays`: "it remains part of `talon` in the enclosing deal state," which keeps the full-deck accounting (hands + played + talon = 32) exact.

**Alternatives considered**: Treating the talon card as an ordinary play by a fourth seat. That would break the "one play per active seat" and hand-size invariants **(inferred)**.

---

## 15. Misère visibility is a rules-level fact exposed by the engine

**Decision**: A misère has no whist phase, every active seat is a settlement party, and the defenders' hands are open, but only after the opening lead when the declarer is on lead (`PlayingState.misereDefendersAreOpen`). The declarer's hand stays hidden. The projection layer decides what to show based on that flag.

**Rationale**: `4dc2fa5` ("Fix misère hand leak: conceal declarer, open defenders") switched to "closed-misère semantics". `b2c1d76` added "a declarer who leads must choose the opening card blind" (doc comment), and `MisereVisibilityTests` checks this at 3 and 4 seats, across snapshot round trips, and for bot information sets (`DealSampler`).

---

## 16. "Without three" concession only before declaration

**Decision**: `concedeWithoutThree` is legal only in `awaitingContract` (after the discard, before naming a contract) and never for misère. Scoring charges `finalBid.value × mountainValueMultiplier × 3` to the declarer.

**Rationale**: Added in `f05642b` ("Add without-three concession option"). The concession is priced on the *auction* bid because no contract has been named yet (`DealResultKind.withoutThree(declarer:bid:)` stores a `ContractBid`). Misère is excluded because it never reaches `awaitingContract` (`testConcedeWithoutThreeIsRejectedForMisere` reaches that state through a snapshot to pin the guard).

---

## 17. Stable, validated wire format

**Decision**:
- Synthesized `Codable` throughout, with targeted custom coders:
  - `PlayerID` and `GameContract` validate on decode;
  - `WhistResponsibility` keeps the string form for its original three cases;
  - `PreferansRules` encodes only non-default optional fields and accepts the legacy `scoringMultiplier`;
  - `MatchSettings` omits `poolTarget == Int.max` ("Int.max is not representable in JavaScript");
  - `PreferansSnapshot` defaults the newer fields.
- Decoding validates through `configurationError` and throws `DecodingError` instead of hitting `precondition`.

**Rationale**: From the comments: "Keep the pre-Rostov wire format stable", "Keep the default Sochi wire format compact", and "persisted network data must fail as a normal decoding error, never trap." Commits: `2b22b5e` ("Validate domain values at the wire boundary"), `890fba9` ("Reject malformed scoring configurations"), `a520acb` ("Reject invalid Totus bonuses"). The Cloudflare worker builds `MatchSettings` JSON by hand in the synthesized shape (`workers/room-worker/src/public-tables.ts`), so the shapes are a cross-language contract.

---

## 18. `startDeal` accepts a dealer and a deck, and hosts must overwrite them

**Decision**: `PreferansAction.startDeal(dealer:deck:)` lets trusted code (tests, fixtures, the host's own deal source) choose the dealer and the deck. Its `actor` is `nil`. Hosts rewrite every incoming `startDeal`: `HostGameActor` uses `engine.nextDealer` plus its deal source, and `AuthoritativeGameService` uses `snapshot.nextDealer` plus `Deck.shuffled(seed:)`.

**Rationale**: `7b7bdd4` documented "the two wire foot-guns": `startDeal` "carries an attacker-controllable dealer/deck with actor == nil", and `PreferansSnapshot` "is full-information and must never be sent to clients raw."

**Alternatives considered**: Removing the parameters from the action. Not done **(inferred)**, because scripted decks are essential for deterministic tests and replays.

---

## 19. Raspasy progression is clamped, and the counter saturates

**Decision**: `scoreMultiplier` and `minimumGameTricks` clamp the stage (`min(stage, 2)`), and `finalize` increments `consecutiveAllPassDeals` only while it is below `Int.max`.

**Rationale**: `249f7f7` ("Saturate raspasy progression stages"). `MatchSettingsTests.testRaspasyProgressionsSaturateForAnUnboundedSeriesCounter` pins the behaviour at `Int.max`. The snapshot invariant `consecutiveAllPassDeals ≤ dealsPlayed` stops a forged streak, and an all-pass result may keep a decoded zero for legacy snapshots ("deliberately remains permissive", `checkRaspasySeriesCounter`).

---

## 20. Deal results keep the opening hands and the real play history

**Decision**: `DealResult.initialHands` holds the dealt 10-card hands, which the scorer reconstructs by undoing the exchange and play. `completedTricks` holds only tricks that were really played. After a settlement, `trickCounts` holds the agreed counts and `settlement` records the agreement.

**Rationale**: `d5c7e33` ("Show opening hands at deal end"). The `settlement` field comment says: "`completedTricks` remains the real played history, while `trickCounts` carries the accepted final counts used for scoring." `initialHands` is optional because "Older archived results may omit this payload."

---

## 21. Testing strategy as a design input

**Decision**: Three layers of evidence guard the rules:
1. **Scenario unit tests** with hand-built decks: `PreferansEngineTests`, `MatchSettingsTests`, `ScenarioFlowTests`.
2. **Single-violation negative tests** for each invariant: `InvariantValidatorTests`, 72 methods.
3. **Seeded generative walks**: `EngineGenerativeTests`, 2 configurations × 18 seeds × ≤ 180 actions. They choose random legal actions, occasionally propose settlements, and validate plus JSON round-trip every snapshot.

The `PREFERANS_ENGINE_TESTS_ONLY=1` lane builds only the engine and the CLI tests (`Package.swift`).

**Rationale**: `866cbc6` added "18 new negative tests cover one violation per invariant arm." `1b69609` notes that the generative walk found two latent bugs: settlement responders were drawn from `activePlayers` instead of `settlementParties`, and card choices queried the seat instead of its controlling actor. Details are in [006](../006-testing-and-release/).

---

## Open research questions

- Should `validateSettlement` require `target == declarer` for game and misère (spec Known Gap 4)?
- Is the comparator-derived winner rule for talon-led raspasy, when nobody can follow the talon suit, the intended house rule (spec Known Gap 3)?
- Should `legalContractDeclarations` exclude 10-level games when totus is dedicated (spec Known Gap 5)? The shipped app never enables dedicated totus.
- Should the `TotusPolicy.dedicatedContract` doc comment be corrected to match the code (whist decision when `requireWhist` is set)?
