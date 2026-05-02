import Foundation

/// Recipe-driven deck construction for tests and scripted matches.
///
/// Each case names an outcome ("declarer wins this contract", "raspasy with
/// north going clean") and ``deck(for:)`` produces the 32-card deck that
/// realises that outcome when the engine plays through the script's chosen
/// auction and play strategy.
///
/// Recipes do NOT drive the play — they shape the *hand* so that, when paired
/// with the right ``CardPlayStrategy``, the script's named outcome is the
/// natural result. The pairing is asserted by ``HandRecipeTests``.
///
/// **Construction guarantees**
/// - The returned deck is always a permutation of ``Deck/standard32``.
/// - Card distribution mirrors ``PreferansEngine``'s `dealHands` packet
///   pattern: 5 packets of 2 cards per active seat, with the 2-card talon
///   inserted after packet 0. The seat order in `activePlayers` is preserved.
public enum HandRecipe: Hashable, Sendable {
    /// Declarer's pre-talon hand crushes the contract: top `contract.tricks`
    /// cards of the trump strain plus the highest non-trump cards. Talon
    /// holds two throwaway cards the declarer discards.
    case declarerWins(declarer: PlayerID, contract: GameContract)

    /// Declarer wins exactly `declarerWillTake` tricks (< `contract.tricks`)
    /// when both sides play "highest legal." Pattern: top `declarerWillTake`
    /// trumps + low non-trump filler. Defenders' high non-trump cards punish
    /// declarer once trumps are exhausted.
    case declarerFails(declarer: PlayerID, contract: GameContract, declarerWillTake: Int)

    /// Declarer holds the ten lowest cards globally; defenders hold the high
    /// twenty-two. Talon holds two cards declarer discards. With "lowest
    /// legal" play, declarer takes zero tricks.
    case cleanMisere(declarer: PlayerID)

    /// Declarer makes a 10-trick contract in the named strain. Same shape as
    /// ``declarerWins`` for `GameContract(10, strain)`.
    case totusMakes(declarer: PlayerID, strain: Strain)

    /// Declarer fails a 10-trick contract by `(10 - declarerWillTake)`
    /// undertricks. Same shape as ``declarerFails``.
    case totusFails(declarer: PlayerID, strain: Strain, declarerWillTake: Int)

    /// All-pass deal where `cleaner` takes zero tricks under lowest-legal
    /// play. Cleaner gets the ten lowest cards; the other two split the
    /// twenty-two high cards.
    ///
    /// `talonLeadSuit` constrains the talon to two cards of that suit so the
    /// `AllPassTalonPolicy.leadSuitOnly` rule has valid material for the
    /// first two tricks. Pass `nil` when the talon is ignored by the policy.
    case raspasyCleanExit(cleaner: PlayerID, talonLeadSuit: Suit?)

    /// Builds the deck for the given active-player rotation. The rotation
    /// must contain exactly three seats and include any seat the recipe
    /// names (declarer / cleaner). Crashes (precondition) on malformed input
    /// — recipes are test fixtures, not user input.
    public func deck(for activePlayers: [PlayerID]) -> [Card] {
        precondition(activePlayers.count == 3, "HandRecipe requires exactly three active seats; got \(activePlayers.count).")
        precondition(Set(activePlayers).count == 3, "Active players must be unique.")

        let plan: DeckPlan
        switch self {
        case let .declarerWins(declarer, contract):
            plan = planForDeclarer(winning: contract, declarer: declarer, activePlayers: activePlayers)
        case let .declarerFails(declarer, contract, willTake):
            plan = planForDeclarer(failing: contract, willTake: willTake, declarer: declarer, activePlayers: activePlayers)
        case let .cleanMisere(declarer):
            plan = planForCleanMisere(declarer: declarer, activePlayers: activePlayers)
        case let .totusMakes(declarer, strain):
            plan = planForDeclarer(winning: GameContract(10, strain), declarer: declarer, activePlayers: activePlayers)
        case let .totusFails(declarer, strain, willTake):
            plan = planForDeclarer(failing: GameContract(10, strain), willTake: willTake, declarer: declarer, activePlayers: activePlayers)
        case let .raspasyCleanExit(cleaner, talonLeadSuit):
            plan = planForRaspasyCleanExit(cleaner: cleaner, talonLeadSuit: talonLeadSuit, activePlayers: activePlayers)
        }
        return interleave(plan: plan, activePlayers: activePlayers)
    }

    // MARK: - Plan construction

    /// Per-seat 10-card hand layout plus 2-card talon. All cards are unique
    /// and together form ``Deck/standard32``.
    private struct DeckPlan {
        var hands: [PlayerID: [Card]]
        var talon: [Card]
    }

    private func planForDeclarer(winning contract: GameContract, declarer: PlayerID, activePlayers: [PlayerID]) -> DeckPlan {
        let declarerFinal = topCards(forContract: contract, count: 10)
        return planSplittingLeftover(declarerHand: declarerFinal, declarer: declarer, activePlayers: activePlayers)
    }

    private func planForDeclarer(failing contract: GameContract, willTake: Int, declarer: PlayerID, activePlayers: [PlayerID]) -> DeckPlan {
        precondition((0..<contract.tricks).contains(willTake), "declarerWillTake must be less than contract.tricks (\(contract.tricks)); got \(willTake).")
        // Top `willTake` trumps win exactly that many tricks under rank-greedy
        // play. Remaining slots get the *lowest by rank* non-trump cards so
        // defenders' high non-trump cards punish every filler. Sorting the
        // filler pool by Card's default Comparable (suit-then-rank) instead
        // of by rank silently bunches the filler into one suit and breaks
        // the recipe — declarer ends up holding e.g. 5 low spades + 5 high
        // clubs and trivially makes the contract.
        let topCount = willTake
        let fillerCount = 10 - topCount
        let strainCards = sortedDescending(of: contract.strain).prefix(topCount)
        let nonStrainByRank = nonStrainCards(strain: contract.strain).sorted(by: Card.byRankAscending)
        let filler = nonStrainByRank.prefix(fillerCount)
        let declarerHand = Array(strainCards) + Array(filler)
        return planSplittingLeftover(declarerHand: declarerHand, declarer: declarer, activePlayers: activePlayers)
    }

    private func planForCleanMisere(declarer: PlayerID, activePlayers: [PlayerID]) -> DeckPlan {
        let allByRankAscending = Deck.standard32.sorted(by: Card.byRankAscending)
        // Declarer's *final* hand is the 10 lowest cards. Talon holds two
        // throwaways from the leftover pool that declarer will discard.
        let declarerHand = Array(allByRankAscending.prefix(10))
        return planSplittingLeftover(declarerHand: declarerHand, declarer: declarer, activePlayers: activePlayers)
    }

    private func planForRaspasyCleanExit(cleaner: PlayerID, talonLeadSuit: Suit?, activePlayers: [PlayerID]) -> DeckPlan {
        precondition(activePlayers.contains(cleaner), "Cleaner must be an active player.")
        // Cleaner gets the ten lowest cards globally; with lowest-legal play
        // they cannot win any trick because every other seat outranks them
        // both as leader and as follower.
        let allByRankAscending = Deck.standard32.sorted(by: Card.byRankAscending)
        let cleanerHand = Array(allByRankAscending.prefix(10))
        var leftoverPool = Set(Deck.standard32).subtracting(cleanerHand)

        // If the talon must lead a specific suit, swap material between the
        // cleaner's hand and the leftover pool to ensure two cards of that
        // suit are available as talon.
        var talon: [Card]
        if let suit = talonLeadSuit {
            let suitCardsInLeftover = leftoverPool.filter { $0.suit == suit }.sorted()
            precondition(suitCardsInLeftover.count >= 2, "Need at least two leftover cards of \(suit) for talon lead-suit constraint.")
            talon = Array(suitCardsInLeftover.prefix(2))
            leftoverPool.subtract(talon)
        } else {
            // Talon contents don't matter for `.ignored` policy — pick the
            // two lowest leftover cards deterministically.
            let leftoverSorted = leftoverPool.sorted()
            talon = Array(leftoverSorted.prefix(2))
            leftoverPool.subtract(talon)
        }

        let defenderSeats = activePlayers.filter { $0 != cleaner }
        let leftoverList = leftoverPool.sorted()
        precondition(leftoverList.count == 20, "Expected 20 leftover cards for two defender hands; got \(leftoverList.count).")
        let firstDefenderHand = Array(leftoverList.prefix(10))
        let secondDefenderHand = Array(leftoverList.suffix(10))

        var hands: [PlayerID: [Card]] = [:]
        hands[cleaner] = cleanerHand
        hands[defenderSeats[0]] = firstDefenderHand
        hands[defenderSeats[1]] = secondDefenderHand

        // Sanity check: the union of hands + talon is the full deck.
        precondition(Set(cleanerHand + firstDefenderHand + secondDefenderHand + talon) == Set(Deck.standard32),
                     "raspasy plan must be a permutation of the standard deck.")
        _ = cleanerHand // silence unused warning under some toolchains

        return DeckPlan(hands: hands, talon: talon)
    }

    /// Common shape: the named declarer's 10-card final hand is supplied;
    /// the talon takes two throwaway cards from the leftover pool (declarer
    /// will discard them); the remaining twenty cards split evenly between
    /// the two defender seats.
    private func planSplittingLeftover(declarerHand: [Card], declarer: PlayerID, activePlayers: [PlayerID]) -> DeckPlan {
        precondition(declarerHand.count == 10, "Declarer's final hand must be exactly 10 cards.")
        precondition(Set(declarerHand).count == 10, "Declarer's hand must contain unique cards.")
        precondition(activePlayers.contains(declarer), "Declarer must be an active player.")

        let leftover = Set(Deck.standard32).subtracting(declarerHand).sorted()
        precondition(leftover.count == 22, "Leftover pool must contain exactly 22 cards.")
        let talon = Array(leftover.prefix(2))
        let defenderPool = Array(leftover.dropFirst(2))
        let defenderSeats = activePlayers.filter { $0 != declarer }

        var hands: [PlayerID: [Card]] = [:]
        hands[declarer] = declarerHand
        hands[defenderSeats[0]] = Array(defenderPool.prefix(10))
        hands[defenderSeats[1]] = Array(defenderPool.suffix(10))

        return DeckPlan(hands: hands, talon: talon)
    }

    // MARK: - Card selection helpers

    private func topCards(forContract contract: GameContract, count: Int) -> [Card] {
        switch contract.strain {
        case let .suit(trump):
            // Up to `contract.tricks` pure trumps (capped at 8 — the suit's
            // full size) plus highest pure non-trump cards by rank. Keeping
            // the two pools disjoint avoids duplicate-card bugs around 9-
            // and 10-trick contracts.
            let trumps = Deck.standard32
                .filter { $0.suit == trump }
                .sorted(by: Card.byRankDescending)
                .prefix(contract.tricks)
            let needed = count - trumps.count
            let sideHigh = needed > 0
                ? Deck.standard32
                    .filter { $0.suit != trump }
                    .sorted(by: Card.byRankDescending)
                    .prefix(needed)
                : []
            return Array(trumps) + Array(sideHigh)
        case .noTrump:
            return Array(Deck.standard32.sorted(by: Card.byRankDescending).prefix(count))
        }
    }

    /// Cards sorted with the strain's "winners first" preference: for a suit
    /// strain, cards of that suit come first by rank descending; for noTrump,
    /// all cards by rank descending then suit.
    private func sortedDescending(of strain: Strain) -> [Card] {
        switch strain {
        case let .suit(trump):
            let trumpCards = Deck.standard32.filter { $0.suit == trump }.sorted().reversed()
            let others = Deck.standard32.filter { $0.suit != trump }.sorted(by: Card.byRankDescending)
            return Array(trumpCards) + others
        case .noTrump:
            return Deck.standard32.sorted(by: Card.byRankDescending)
        }
    }

    private func nonStrainCards(strain: Strain) -> [Card] {
        switch strain {
        case let .suit(trump):
            return Deck.standard32.filter { $0.suit != trump }
        case .noTrump:
            return []
        }
    }

    // MARK: - Deck assembly

    private func interleave(plan: DeckPlan, activePlayers: [PlayerID]) -> [Card] {
        var deck: [Card] = []
        for packet in 0..<5 {
            for seat in activePlayers {
                guard let hand = plan.hands[seat] else {
                    preconditionFailure("Plan missing hand for seat \(seat).")
                }
                deck.append(hand[packet * 2])
                deck.append(hand[packet * 2 + 1])
            }
            if packet == 0 {
                deck.append(contentsOf: plan.talon)
            }
        }
        precondition(Set(deck) == Set(Deck.standard32),
                     "HandRecipe deck must be a permutation of the standard 32-card deck.")
        return deck
    }
}
