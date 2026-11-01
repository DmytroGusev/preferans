# Glossary

The words used across the specs and the code. For the precise rule semantics, follow the links.

## Game terms

| Term (ru) | In code | Meaning |
|---|---|---|
| Preferans (преферанс) | `PreferansEngine` | Trick-taking game for 3 active players with a 32-card deck (7 through Ace in four suits) |
| Seat / active players | `players`, `activePlayers` | `players` is the clockwise seating order. Each deal has exactly 3 active players. At a 4-seat table the dealer sits out. [001](../001-game-rules/spec.md) |
| Forehand (первая рука) | `activePlayers[0]` | Speaks first in the auction and leads the first trick |
| Dealer (сдающий) | `dealer` | Deals 5 packets of 2 cards, with the 2-card talon placed after the first packet. At 3 seats the dealer plays last; at 4 seats they get no cards |
| Talon / prikup (прикуп) | `talon` | The 2 undealt cards. The declarer takes them in a contract deal. In all-pass deals they set the suit of the first two tricks (except under Rostov's hidden-talon policy, `AllPassTalonPolicy.ignored`) |
| Discard (снос) | `discard` | The 2 cards the declarer puts away after taking the talon |
| Auction / bid (торговля) | `bid` actions | Ladder 6♠ < 6♣ < 6♦ < 6♥ < 6NT < … < 8NT < misère < (totus, optional) < 9♠ … 10NT. [001 appendix](../001-game-rules/spec.md) |
| Declarer (разыгрывающий) | `declarer` | The auction winner, who plays the contract |
| Contract / game (игра) | `GameContract` (bid: `ContractBid`) | Number of tricks (6–10) and a trump suit or no-trump |
| Misère (мизер) | `.misere` | Contract to take zero tricks: no trump, no whist phase |
| Totus (тотус) | `TotusPolicy` | A 10-trick contract. By default it is just the 10-level; optionally (`.dedicatedContract`) it is a separate bid with a pool bonus |
| Without three (без трёх) | `concedeWithoutThree` | The declarer gives up before naming the contract and is scored three tricks short |
| Whist / pass (вист / пас) | `WhistCall` | Each defender decides whether to defend ("whist") against the contract |
| Half-whist (полвиста) | `.halfWhist` | On 6- and 7-level contracts, after the first defender passed, the second may take half the defence's whists without playing |
| Open / closed whist (в светлую / в тёмную) | `DefenderPlayMode` | Whether defenders play with their cards exposed |
| Passed out | `passedOut` | Both defenders passed, so the declarer is credited without play. **Not** the same as all-pass |
| All-pass / raspasy (распасы) | `allPass` | Everyone passed in the auction. Each player tries to take as few tricks as possible. Consecutive raspasy raise the price and the minimum contract |
| Claim (settlement) | `settlement` actions | Early agreement on the remaining tricks. Only a side playing open can propose it, and everyone involved must accept. The README says "claims"; the code says "settlement" |
| Pool / pulka (пуля) | `pool` | Points earned for successful contracts. The match ends when the pool closes at the target |
| Mountain / gora (гора) | `mountain` | Penalty points for failed contracts and raspasy tricks |
| Whists (висты) | `whists[writer][target]` | Points written against a specific opponent. Final settlement nets them pairwise |
| Pool closing / American aid | `PoolClosurePolicy` | How a player's surplus pool spills to others: `individualWithAmericanAid` or `tableTotal`. [002](../002-scoring-and-variants/spec.md) |
| Final balance | `ScoreSheet.normalizedBalances`, `MatchSummary.standings` | Per-player result in whists, relative to the table average. Always sums to zero |

## Rule variants

The app shows **display names** that differ from both the **stored IDs** and the **classical rule-set names**. The README's older names are stale.

| Display name (en) | Stored ID (`PreferansVariant`) | Engine rule set (`PreferansRules`) | Pool closing | Public-table preset | In-app tagline |
|---|---|---|---|---|---|
| **Vienna** | `odesa` | `.sochi` | individual + American aid | yes | "Balanced scoring" |
| **Prague** | `wien` | `.leningrad` | table total | yes | "Double whists, shared pool" |
| **Berlin** | `thessaloniki` | `.rostov` | individual + American aid | yes | "Semi-responsible whist, hidden talon on all-pass" |
| **Kruty** | `kruty` | `.stalingrad` | individual + American aid | no | "Kruty · Stalingrad" |

Source: `Preferans/UI/LobbyModels.swift` (`PreferansVariant.rules`, `.poolClosure`, `.publicCases`) and `Preferans/Resources/Localizable.xcstrings` (`variant.*.title`, `variant.*.standard`). The scoring differences between the four rule sets are tabulated in [002 spec](../002-scoring-and-variants/spec.md).

## Engineering terms

| Term | Meaning |
|---|---|
| Projection | `PlayerGameProjection`: a viewer-safe snapshot of the game (own hand, public cards, roles, legal actions). The only thing the UI renders. [004](../004-online-multiplayer/data-model.md) |
| Private state | The opaque engine snapshot that only the server (`PreferansTable` + container) ever holds |
| Command / receipt | A client's intended action with a unique ID bound to its payload, and the server's proof that it was applied exactly once |
| Outbox | On-device write-ahead file of pending online commands (`OnlineCommandOutbox`) |
| Manager (host) | In online rooms, the first connected human in seat order. Only they can start deals. "Host" no longer means game authority |
| Seat token | 24-character secret proving occupancy of a seat. Rotated on re-join |
| Lane | A `Package.swift` mode selected by environment variable: default, `PREFERANS_ENGINE_TESTS_ONLY=1`, `PREFERANS_SERVER_ONLY=1` |
| `BotPacing` | Delay between bot moves: `normal` 1.2 s (default), `slow` 2.2 s, `interactive` 0.5 s, `testFast` 10 ms, `instant` 0 |
| Tap-to-advance | The local table pauses after a trick or a revealed talon until the player taps. Online, it releases after 2.4 s |
| HandRecipe / MatchScript | Deterministic deck and whole-match fixtures used by engine tests, UI tests and `bin/sim`. [006](../006-testing-and-release/quickstart.md) |
| Screen provenance | Proof that screenshots were captured from the current sources (`bin/screens-latest`) |
