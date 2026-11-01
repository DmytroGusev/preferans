# Research: Scoring, Rule Variants, and Match Settlement

**Status**: Implemented (as-built) · **Verified against**: `store/1.0.3-localized-keywords` @ `cd78828`

Each block records a design decision visible in the code. "Rationale" quotes or paraphrases code comments, commit messages and tests; where the reason is reconstructed rather than written down it is marked **(inferred)**. History comes from read-only `git log` / `git log -S` over `Sources/PreferansEngine` (the repository has a single author for these files).

---

## R-01 Separate pool, mountain and whist recording scales

**Decision**: `PreferansRules` carries three independent multipliers (`poolValueMultiplier`, `mountainValueMultiplier`, `whistValueMultiplier`) plus a `whistValueDivisor`, instead of one scoring multiplier.

**Rationale**: Code comment in `Rules.swift`: "Recording scales are deliberately separate. In Leningrad a made contract keeps the standard 2/4/6/8/10 pool value, while direct whists and declarer remise mountain entries are doubled." A single multiplier (`scoringMultiplier`) existed in older snapshots; the decoder still maps it onto all three fields so old matches keep their behaviour (`PreferansRules.init(from:)`). Introduced in `a266056` "Correct Preferans scoring conventions and invariants" (2026-07-31); Leningrad corrections followed in `20b1774` and `083fd01`.

**Alternatives considered**: One global multiplier (the legacy shape) — rejected because it doubled Leningrad pool entries and therefore halved match length. Hard-coding Leningrad as a separate scorer — rejected (inferred) to keep one scorer for all variants.

---

## R-02 Pulka closing is a match-level policy, not a score multiplier

**Decision**: `MatchSettings.poolClosure` selects `individualWithAmericanAid` (Sochi family) or `tableTotal` (Leningrad); `poolTarget` is always stored as the *table total* (per-player limit × seats for individual closure).

**Rationale**: `MatchSettings.swift`: "Pulka-closing conventions are deliberately match-level rather than score multipliers. Sochi closes every player's individual pool and redirects surplus via American aid; Leningrad never closes an individual pool and simply stops once the table's combined pool reaches the agreed total." Storing a total lets one integer serve both policies and lets the worker validate a bounded number (`publicConfiguration` caps at `seats × 999`). `isPoolClosed` lives next to the policy "to prevent scoring, game-over transitions, and snapshot invariants from growing subtly different definitions of 'closed'". `tableTotal` arrived in `a266056`; American aid in `50e554b` "Fix pulka closing score calculations" (2026-06-13).

**Alternatives considered**: Per-player target field (rejected — the lobby/UI would need two representations; the app keeps a separate `customPulkaTableTotal` only for UI input). Closing on any single player reaching the limit (classic "first to close ends the pulka") — not implemented; the engine waits until *every* individual pool is full, made possible by American aid (inferred).

---

## R-03 American aid writes whists back and overflows into mountain relief

**Decision**: Surplus pool goes to the open opponent with the highest pool (ties → earlier seat), the earner writes `aid × poolPointWhistValue` whists on each recipient, and any remainder after all pools are full is subtracted from the earner's mountain.

**Rationale**: `ScoreSheet.apply` doc comment: "Individual closure first fills the earner, then aids the highest open opponent and writes equivalent whists back to the earner. Once everyone is closed, leftover value reduces the earner's mountain so final equal pool totals can be ignored." The whist write-back keeps the earner's economic value (a pool point is worth `poolPointWhistValue` whists at settlement) while forcing pools toward equality so the match can end. `apply` returns the *applied* delta so the deal summary and `MatchSummary.lastDeal` show what really happened (`testEngineDealAppliesPulkaClosingToDealResultAndMatchSummary`). `applyRaw` is `private` so callers cannot bypass closing.

**Alternatives considered**: Capping pool and discarding surplus (loses value) or letting pools exceed the target (breaks "all pools equal at the end"). Aiding the *lowest* open pool — rejected (inferred) because the traditional rule helps the player closest to closing.

---

## R-04 Final balance = centred whist-equivalents

**Decision**: `normalizedBalances` computes `pool × P − mountain × M + net whists` per player and subtracts the table mean; no pairwise ledger is produced.

**Rationale**: Mathematically identical to the textbook procedure (mountain differences amortised `× 10 / N` between every pair, whists netted pairwise), but simpler and zero-sum by construction (see spec E19). Variant conversion rates come from rules: Leningrad values a pool point at 20 whists and a mountain point at 10 (`Rules.swift` comment "Leningrad values one pool point at 20 whists while a recorded mountain point remains worth 10"). `normalizedBalances` dates from the first engine (`ed331ce`); variant rates were added in `a266056`/`7861d7d`. Tied leaders share rank and no sole winner is named (`4af1167` "make match results readable and share tied standings").

**Alternatives considered**: Pairwise settlement table (would show who pays whom) — not implemented (gap). Ranking by raw pool — rejected because it ignores mountain and whists.

---

## R-05 Raspasy progression is negotiated match state with a persistent counter

**Decision**: `RaspasyPolicy.progressive(penalties:exit:)` with four price curves and three exit curves; the engine stores `consecutiveAllPassDeals` in snapshots; any non-raspasy result resets it; stages saturate at 2.

**Rationale**: `MatchSettings.swift`: "Raspasy price and exit progressions are negotiated options in both named conventions; the lobby transports the selected pair in MatchSettings." The counter is "match state, not deal state" (`PreferansEngine.swift`) and must survive host recovery (`testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract`). Snapshot invariants bound it by `dealsPlayed` and force 0 after non-raspasy results (`f2ee50e` "enforce raspasy snapshot lifecycle invariants"). Saturation: `249f7f7` "Saturate raspasy progression stages" (an `Int.max` streak must not overflow array indexing). The legacy `singleShot` case remains the decode default "for old fixtures and decoded snapshots".

**Alternatives considered**: Hard-wiring the progression into the rule profile — rejected (comment: these are "match settings rather than properties of the named scoring convention", `AppIdentifiers.swift`). Unbounded growth — rejected (saturation).

---

## R-06 Clean-exit pool follows the progression, not the penalty multiplier

**Decision**: In `perTrick` raspasy the clean-exit pool is `bonus × progression`, while mountain is `tricks × multiplier × progression`.

**Rationale**: `ScoringEngine.swift`: "A clean exit is a pool credit, not an all-pass mountain penalty. Leningrad doubles mountain/whist recording while keeping pool entries at their normal value; only the raspasy progression changes the clean-exit pool credit." Fixed in `083fd01` "Correct Leningrad clean-exit pool scoring"; pinned by `testLeningradRaspasyDoublesMountainSeriesButKeepsPoolExitAtProgressionPrice`.

**Alternatives considered**: Scaling the clean exit by the Leningrad doubling (2–4–6) — the previous behaviour, rejected.

---

## R-07 No amnesty by default

**Decision**: `allPassPenaltyPolicy` defaults to `perTrick(multiplier: 1, amnesty: false)`; amnesty remains available.

**Rationale**: `Rules.swift` initializer comment: "Canonical Sochi/Leningrad raspasy charge every trick in the mountain. Amnesty remains an explicit house-rule option, but it must not be the production default." Fixed in `7f018eb` "Fix canonical raspasy mountain scoring".

**Alternatives considered**: Amnesty (charge only tricks above the table minimum) as default — rejected.

---

## R-08 Rostov as configuration, not a separate scorer

**Decision**: Rostov is expressed with `declarerRemisePolicy: .directWhistsPerDefender(10)`, `allPassPenaltyPolicy: .directWhistsToLowest(5)`, `allPassTalonPolicy: .ignored`, `singleWhistScoring: .gentleman`, `whistResponsibility: .semiResponsible`, `failedDeclarerConsolation: .none`.

**Rationale**: Implemented in `8ccc460`, then corrected in three follow-ups on 2026-08-01: `bbfa335` "Correct Rostov scoring direction and values" (raspasy winners now write on losers; the undertrick consolation became a fixed 10 whists rather than `value × k`), `04ab5d3` "Align Rostov whist responsibility rules" (moved from `.directWhists(5)` + greedy to `.semiResponsible` + gentleman), `5c9c48c` "Keep Rostov misere scoring canonical" (misère ignores the direct-remise policy: "Misère keeps its canonical ten-mountain-point penalty in every profile, including Rostov"). The worker's public presets are pinned to the Swift profiles by `PublicTableRulesTests`.

**Alternatives considered**: The earlier `.directWhists(pointsPerMountainPoint: 5)` responsibility — abandoned; the enum case remains for wire compatibility but has no production user (see spec Known Gap 3 on its sign).

---

## R-09 Gentleman whist splits only on declarer failure

**Decision**: `.gentleman` behaves greedily when the contract is made, and on failure splits the defenders' trick whists equally between both defenders whatever the number of whisters.

**Rationale**: `Rules.swift`: "When the declarer fails, the lone whister and their passing partner split the defender-trick whists equally. A made contract remains greedy, and remise consolation is still written in full by each defender." `ScoringEngine.swift` comment repeats that it applies "regardless of whether one or both defenders originally said whist". Corrected in `20b1774` "Correct Leningrad gentleman whist scoring" and `51f724b` "fix scoring for gentleman whist remises".

**Alternatives considered**: Splitting only with a single whister (would let two whisters keep own-trick attribution on failure) — rejected by `testRostovGentlemanWhistSplitsRemiseTricksWhenBothDefendersWhist`.

---

## R-10 Two-whister responsibility follows half-quotas, with the 1-trick quota on the second whister

**Decision**: If the partnership meets the quota, nobody pays. Otherwise each whister pays for every trick missing from `R / 2`; for `R == 1` only the second whister pays.

**Rationale**: `ScoringEngine.swift`: "Two whisters defend as one partnership. If their combined tricks meet the contract quota, neither is penalized…" and "A six-game therefore charges two mountain units to a whister who takes no tricks, rather than collapsing the shortfall to a single unit." Fixed in `364c5cd` "fix two-whister responsibility scoring". The second-whister rule for 8+ contracts matches the traditional convention that the player who whists second (after a first whist) carries the single-trick obligation (inferred).

**Alternatives considered**: Charging the whole partnership shortfall once — rejected by `testFailedJointWhistChargesEachPartnerForTheirOwnHalfShare`.

---

## R-11 Four-player dealer talon compensation is explicit and on by default

**Decision**: `DealerTalonCompensation.classic` (default in all profiles) makes the sitting-out dealer write whists on the declarer for talon aces / A-K / K-Q (games, passed out, half-whist) and sevens (misère).

**Rationale**: `Rules.swift`: "It is a table agreement in some circles, so it remains explicit even though the canonical app profiles enable it." Added in `3fac808` (2026-07-31). Combination precedence is documented in `dealerGameTalonTricks` ("Higher combinations take precedence because a two-card talon can satisfy more than one lower condition"); "A suited seven-eight combination is conventionally valued as twenty even though it contains one seven."

**Alternatives considered**: No dealer score at four seats (the `.none` option) — kept as a configurable house rule; not exposed in the app.

---

## R-12 Executable rulebook instead of prose constants

**Decision**: The rules screen renders `PreferansRulebook.examples`, which runs the production scorer on synthetic deals.

**Rationale**: `ScoringEngine.swift`: "Keeping these values in the engine lets the in-app rulebook explain the active convention without reimplementing its arithmetic in SwiftUI." `ConventionLegendSheet` header: "…rather than a parallel list of prose constants that can silently drift." Pinned by `testExecutableRulebookUsesTheProductionScorer`.

**Alternatives considered**: Localized prose tables — rejected as drift-prone.

---

## R-13 House names decoupled from persisted identifiers

**Decision**: Persisted variant ids stay `odesa`, `wien`, `thessaloniki`, `kruty`; displayed names come from `Localizable.xcstrings` and are now Vienna / Prague / Berlin / Kruty.

**Rationale**: `LobbyModels.swift`: "Persisted identifiers stay stable so saved tables retain their rules." `docs/PUBLIC_LOBBY.md`: "Presentation names change without changing persisted rules identifiers." The European names were introduced in `f7dbbaf` "Add public online tables, readiness flow and European convention names" (2026-10-02), after README's Одеса/Wien/Θεσσαλονίκη/Крути wording (`ed44765`). Kruty is the house name for Stalingrad ("drawn from Ukrainian rather than Soviet history", `convention.kruty.summary`). The motivation for replacing the Soviet-era standard names is **(inferred)** from that string.

**Alternatives considered**: Renaming persisted ids (would break saved tables and worker presets).

---

## R-14 Stalingrad as a named profile

**Decision**: `.stalingrad` = Sochi + `forceWhistOnSixSpades`.

**Rationale**: `Rules.swift`: "Keeping it as a named profile prevents the lobby from silently reconstructing a subtly different set of rules." `78603ff` "Expose Stalingrad convention in lobby": "…so the lobby cannot silently fall back to ordinary Sochi." Kept out of public tables (worker `PUBLIC_VARIANTS`).

**Alternatives considered**: A free-standing lobby toggle — rejected (inferred) in favour of a fixed, nameable convention.

---

## R-15 Ten-trick contracts: open check by default, optional ordinary whist

**Decision**: Without the convention, a 10-trick contract is played open with no whist phase (`R = 0`); with `requireWhistOnTenTrickContracts` (Leningrad) or `totus.requireWhist`, defenders choose pass/whist normally and `R = 1`.

**Rationale**: `1b69609` first made the flag effective but forced whist; `0319a9b` "Correct ten-trick checking and whist choices" changed it to an ordinary choice. `Rules.swift`: "Despite the historical property name, this does not force a defender to whist; only the separate Stalingrad agreement does that."

**Alternatives considered**: Mandatory whist on 10 (the `1b69609` behaviour) — superseded.

---

## R-16 Without-three is a flat triple of the bid value

**Decision**: `concedeWithoutThree` (after the discard, before naming a contract) records `finalBid.value × Mm × 3` mountain and nothing else.

**Rationale**: Added in `f05642b` (2026-06-13). Tests pin "declarer triple and dealer nothing" at three and four seats. The choice to ignore consolation and the Rostov direct-remise policy is not documented **(inferred: simplicity / traditional "без трёх" entry)**; see spec Known Gap 4.

**Alternatives considered**: Scoring as a played contract with three undertricks — not implemented.

---

## R-17 Trick settlement: unanimity of contesting parties, information-safe suggestions

**Decision**: Only sides whose cards are exposed (open game, misère, open 10-trick check) may settle; every contesting party must accept; suggestions are anchors plus a forced last-trick split proven from the viewer's information.

**Rationale**: `PlayingState.settlementParties` doc: "the contesting sides, and only them … This is the single source of truth for settlement participation" (fix `a66597b` "one approval authority across all paths"). `forcedSettlement(in:knownTo:)` enumerates every hidden allocation consistent with public play "Never consult which allocation really occurred" (`14fafcb` "prove settlement outcomes from visible information"). Settled results keep the real `completedTricks` and carry agreed `trickCounts` so history is never fabricated.

**Alternatives considered**: Allowing closed-game or raspasy settlements (rejected — hidden hands make claims unverifiable); a fixed menu of offers (rejected — "the reducer accepts any validateSettlement-valid configuration, so the engine never has to enumerate the continuum").

---

## R-18 Fail-closed validation that never traps on persisted data

**Decision**: Programmer errors use `precondition`; engine construction and snapshots use `configurationError` strings → `PreferansError.invalidRules/invalidMatch`; decoders throw `DecodingError`.

**Rationale**: `Rules.swift`: "persisted network data must fail as a normal decoding error, never trap." Commits `890fba9` "Reject malformed scoring configurations", `a520acb` "Reject invalid Totus bonuses", `781fb71` "Reject invalid all-pass penalty multipliers", `1716596` "Validate recovered score ledgers".

**Alternatives considered**: Clamping invalid values (rejected — would silently change a table's rules).

---

## R-19 Unbounded match encoded by omission

**Decision**: `poolTarget == Int.max` is not written to JSON; absence decodes as unbounded.

**Rationale**: `MatchSettings.encode`: "Int.max is not representable in JavaScript; absence decodes as unbounded." Pinned by `testUnboundedWireEncodingAvoidsJavaScriptIntegerOverflow` — required because match settings pass through the TypeScript worker.

**Alternatives considered**: `null` or a sentinel such as 0 (0 is rejected by validation).
