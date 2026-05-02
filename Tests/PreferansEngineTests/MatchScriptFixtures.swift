import Foundation
@testable import PreferansEngine

/// Canonical match scripts used by both `EngineMatchDriverTests` and the
/// future UI tests. Each script designs its deal sequence so that:
///   - The pool-target gate fires on the *last* deal, not earlier.
///   - Every contract type the design lock-in calls for appears at least once
///     (made low, made high, failed, misère, totus, raspasy clean exit).
///   - At least two deals fail (multiple-failures requirement).
///   - The dealer rotates naturally — the script never pins a dealer beyond
///     the initial `firstDealer`.
///
/// Pool-sum trajectories for each script are documented inline. Edits that
/// change a recipe's outcome must update the trajectory comment and re-run
/// `EngineMatchDriverTests`.
enum MatchScriptFixtures {
    static let players: [PlayerID] = ["north", "east", "south", "west"]

    // MARK: - Game 1: Classic Sochi

    /// Pool-sum after each deal: 2 → 2 → 12 → 12 → 13 → 23.
    /// Pool target 20 fires on deal 6.
    /// Mix: 6♠ made, 7♣ failed, misère clean, 8♥ failed, raspasy clean,
    /// 10♠ totus (asTenTrickGame, defenders pass-out → declarer +10).
    static let game1ClassicSochi: MatchScript = {
        let players = MatchScriptFixtures.players
        let firstDealer: PlayerID = "north"
        let rules = PreferansRules.sochi
        let match = MatchSettings(
            poolTarget: 20,
            raspasy: .singleShot,
            totus: .asTenTrickGame(requireWhist: false)
        )
        let deals: [DealScript] = [
            // Deal 1 — dealer north, active [east, south, west]; east makes 6♠.
            .makeGameContract(
                declarer: "east",
                contract: GameContract(6, .suit(.spades))
            ),
            // Deal 2 — dealer east, active [south, west, north]; south fails 7♣ (5 tricks).
            .makeFailedGameContract(
                declarer: "south",
                contract: GameContract(7, .suit(.clubs)),
                declarerWillTake: 5
            ),
            // Deal 3 — dealer south, active [west, north, east]; west cleans misère.
            .makeMisere(declarer: "west"),
            // Deal 4 — dealer west, active [north, east, south]; north fails 8♥ (6 tricks).
            .makeFailedGameContract(
                declarer: "north",
                contract: GameContract(8, .suit(.hearts)),
                declarerWillTake: 6
            ),
            // Deal 5 — dealer north, active [east, south, west]; raspasy, east clean.
            .makeRaspasy(cleaner: "east", talonLeadSuit: nil),
            // Deal 6 — dealer east, active [south, west, north]; south makes 10♠.
            // Under asTenTrickGame(requireWhist: false), defenders may pass and
            // the deal short-circuits as passed-out (declarer credited 10 pool).
            .makePassedOutTenTrickGame(declarer: "south", strain: .suit(.spades))
        ]
        return MatchScript(
            players: players,
            firstDealer: firstDealer,
            rules: rules,
            match: match,
            deals: deals
        )
    }()

    // MARK: - Game 2: Long Sochi totus + lead-suit-only raspasy

    /// Pool-sum after each deal: 0 → 4 → 14 → 15 → 25.
    /// Pool target 25 fires on deal 5.
    /// Mix: 6♣ failed, 7♥ made, 10♠ totus (asTenTrickGame, requireWhist:true,
    /// defenders forced to whist, played out), raspasy with leadSuitOnly
    /// talon constraint, misère clean.
    static let game2LongSochi: MatchScript = {
        let players = MatchScriptFixtures.players
        let firstDealer: PlayerID = "south"
        let rules = PreferansRules.sochiWithTalonLedAllPass
        let match = MatchSettings(
            poolTarget: 25,
            raspasy: .singleShot,
            totus: .asTenTrickGame(requireWhist: true)
        )
        let deals: [DealScript] = [
            // Deal 1 — dealer south, active [west, north, east]; west fails 6♣ (4 tricks).
            .makeFailedGameContract(
                declarer: "west",
                contract: GameContract(6, .suit(.clubs)),
                declarerWillTake: 4
            ),
            // Deal 2 — dealer west, active [north, east, south]; north makes 7♥.
            .makeGameContract(
                declarer: "north",
                contract: GameContract(7, .suit(.hearts))
            ),
            // Deal 3 — dealer north, active [east, south, west]; east makes 10♠
            // with both defenders whisting (requireWhist: true).
            .makeGameContract(
                declarer: "east",
                contract: GameContract(10, .suit(.spades))
            ),
            // Deal 4 — dealer east, active [south, west, north]; raspasy with
            // talon lead-suit constraint, south clean.
            .makeRaspasy(cleaner: "south", talonLeadSuit: .clubs),
            // Deal 5 — dealer south, active [west, north, east]; west cleans misère.
            .makeMisere(declarer: "west")
        ]
        return MatchScript(
            players: players,
            firstDealer: firstDealer,
            rules: rules,
            match: match,
            deals: deals
        )
    }()

    // MARK: - Game 3: Rostov-style dedicated totus

    /// Pool-sum after each deal: 15 → 15 → 17 → 18 → 18 → 33.
    /// Pool target 30 fires on deal 6.
    /// Mix: dedicated totus made twice (with bonus), 9♣ failed, 6♦ made,
    /// raspasy clean, 7♥ failed.
    static let game3RostovDedicatedTotus: MatchScript = {
        let players = MatchScriptFixtures.players
        let firstDealer: PlayerID = "west"
        let rules = PreferansRules.sochi
        let match = MatchSettings(
            poolTarget: 30,
            raspasy: .singleShot,
            totus: .dedicatedContract(requireWhist: true, bonusPool: 5)
        )
        let deals: [DealScript] = [
            // Deal 1 — dealer west, active [north, east, south]; north plays
            // dedicated totus (10♠) with bonus.
            .makeDedicatedTotus(declarer: "north", strain: .suit(.spades)),
            // Deal 2 — dealer north, active [east, south, west]; east fails 9♣ (7).
            .makeFailedGameContract(
                declarer: "east",
                contract: GameContract(9, .suit(.clubs)),
                declarerWillTake: 7
            ),
            // Deal 3 — dealer east, active [south, west, north]; south makes 6♦.
            .makeGameContract(
                declarer: "south",
                contract: GameContract(6, .suit(.diamonds))
            ),
            // Deal 4 — dealer south, active [west, north, east]; raspasy, west clean.
            .makeRaspasy(cleaner: "west", talonLeadSuit: nil),
            // Deal 5 — dealer west, active [north, east, south]; north fails 7♥ (4).
            .makeFailedGameContract(
                declarer: "north",
                contract: GameContract(7, .suit(.hearts)),
                declarerWillTake: 4
            ),
            // Deal 6 — dealer north, active [east, south, west]; east plays
            // dedicated totus (10♣) with bonus, closing the pulka.
            .makeDedicatedTotus(declarer: "east", strain: .suit(.clubs))
        ]
        return MatchScript(
            players: players,
            firstDealer: firstDealer,
            rules: rules,
            match: match,
            deals: deals
        )
    }()
}

// MARK: - DealScript builders

private extension DealScript {
    /// Made game contract, played out greedily by declarer. Defenders
    /// forced into closed-mode whist via two `.whist` calls.
    static func makeGameContract(declarer: PlayerID, contract: GameContract) -> DealScript {
        DealScript(
            recipe: .declarerWins(declarer: declarer, contract: contract),
            auction: [.bid(.game(contract)), .pass, .pass],
            discardChoice: .talon,
            contractDeclaration: contract,
            whists: [.whist, .whist],
            cardPlay: .greedyForDeclarer(declarer: declarer)
        )
    }

    /// Failed game contract — declarer takes `declarerWillTake` < contract.tricks
    /// under greedy play; mountain charged, defenders earn whists.
    static func makeFailedGameContract(declarer: PlayerID, contract: GameContract, declarerWillTake: Int) -> DealScript {
        DealScript(
            recipe: .declarerFails(declarer: declarer, contract: contract, declarerWillTake: declarerWillTake),
            auction: [.bid(.game(contract)), .pass, .pass],
            discardChoice: .talon,
            contractDeclaration: contract,
            whists: [.whist, .whist],
            cardPlay: .greedyForDeclarer(declarer: declarer)
        )
    }

    /// Clean misère: declarer holds the ten lowest cards and dumps every
    /// trick under lowest-legal play.
    static func makeMisere(declarer: PlayerID) -> DealScript {
        DealScript(
            recipe: .cleanMisere(declarer: declarer),
            auction: [.bid(.misere), .pass, .pass],
            discardChoice: .talon,
            cardPlay: .lowestLegal
        )
    }

    /// All-pass deal where `cleaner` takes zero tricks under lowest-legal
    /// play. `talonLeadSuit` constrains the talon for `.leadSuitOnly` rules;
    /// pass `nil` when the talon is ignored.
    static func makeRaspasy(cleaner: PlayerID, talonLeadSuit: Suit?) -> DealScript {
        DealScript(
            recipe: .raspasyCleanExit(cleaner: cleaner, talonLeadSuit: talonLeadSuit),
            auction: [.pass, .pass, .pass],
            cardPlay: .lowestLegal
        )
    }

    /// 10-trick game contract under `.asTenTrickGame(requireWhist: false)`:
    /// defenders pass on whist and the deal short-circuits as passedOut.
    static func makePassedOutTenTrickGame(declarer: PlayerID, strain: Strain) -> DealScript {
        let contract = GameContract(10, strain)
        return DealScript(
            recipe: .totusMakes(declarer: declarer, strain: strain),
            auction: [.bid(.game(contract)), .pass, .pass],
            discardChoice: .talon,
            contractDeclaration: contract,
            whists: [.pass, .pass],
            cardPlay: .none
        )
    }

    /// Dedicated totus bid → discard → strain pick → both defenders whist →
    /// played out greedily by declarer. Bonus pool is credited by the engine
    /// when the play succeeds.
    static func makeDedicatedTotus(declarer: PlayerID, strain: Strain) -> DealScript {
        let contract = GameContract(10, strain)
        return DealScript(
            recipe: .totusMakes(declarer: declarer, strain: strain),
            auction: [.bid(.totus), .pass, .pass],
            discardChoice: .talon,
            contractDeclaration: contract,
            whists: [.whist, .whist],
            cardPlay: .greedyForDeclarer(declarer: declarer)
        )
    }
}
