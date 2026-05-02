import Foundation

/// Declarative description of a full Preferans match (one pulka).
///
/// A `MatchScript` is the test-side dual of `PreferansEngine`'s runtime: each
/// ``DealScript`` lists exactly the actions the engine should see in exactly
/// the order they should arrive, plus the ``HandRecipe`` that produces the
/// deck for that deal. ``EngineMatchDriver`` replays the script through a
/// real engine; the same script value is intended to drive ``MatchUIDriver``
/// against the SwiftUI surface so the UI test never re-derives the auction
/// or play sequence.
public struct MatchScript: Hashable, Sendable {
    public let players: [PlayerID]
    public let firstDealer: PlayerID
    public let rules: PreferansRules
    public let match: MatchSettings
    public let deals: [DealScript]

    public init(
        players: [PlayerID],
        firstDealer: PlayerID,
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        deals: [DealScript]
    ) {
        self.players = players
        self.firstDealer = firstDealer
        self.rules = rules
        self.match = match
        self.deals = deals
    }
}

/// One deal's worth of script: the deck recipe and the actions to apply.
///
/// Steps are applied in order: auction → discard → contract declaration →
/// whists → defender mode → card play. Steps that don't apply for a given
/// outcome (e.g., misère skips contract declaration and whist) should leave
/// their fields empty / `.none` — the driver checks engine state and only
/// applies steps the engine is currently waiting on.
public struct DealScript: Hashable, Sendable {
    public let recipe: HandRecipe
    /// One call per active seat in bidding order. Length must equal the
    /// number of active players. Driver applies each call to the engine's
    /// `currentPlayer` at that step.
    public let auction: [BidCall]
    public let discardChoice: DiscardChoice
    /// Declared contract for game and totus paths. `nil` for misère and
    /// all-pass. For totus this also names the trump strain (10-trick).
    public let contractDeclaration: GameContract?
    /// One call per defender in defender order. Empty when no whist phase.
    public let whists: [WhistCall]
    /// Set when exactly one defender whists and is asked to choose a mode.
    public let defenderMode: DefenderPlayMode?
    public let cardPlay: CardPlayStrategy

    public init(
        recipe: HandRecipe,
        auction: [BidCall],
        discardChoice: DiscardChoice = .none,
        contractDeclaration: GameContract? = nil,
        whists: [WhistCall] = [],
        defenderMode: DefenderPlayMode? = nil,
        cardPlay: CardPlayStrategy = .none
    ) {
        self.recipe = recipe
        self.auction = auction
        self.discardChoice = discardChoice
        self.contractDeclaration = contractDeclaration
        self.whists = whists
        self.defenderMode = defenderMode
        self.cardPlay = cardPlay
    }
}

public enum DiscardChoice: Hashable, Sendable {
    /// Declarer discards the two talon cards (most common — talon is built
    /// as throwaways by ``HandRecipe``).
    case talon
    /// Declarer discards the named cards. Useful when the recipe puts
    /// keepers in the talon and the declarer should drop two specific cards
    /// from the original hand.
    case specific([Card])
    /// No discard step (all-pass).
    case none
}

public enum CardPlayStrategy: Hashable, Sendable {
    /// Step out of card play immediately (passed-out paths, all-pass paths
    /// the script intentionally short-circuits).
    case none
    /// Apply the listed cards in order. Driver assigns each card to the
    /// engine's `currentPlayer` at that step. Length should equal
    /// `activePlayers.count * 10` for a full deal.
    case exact([Card])
    /// Declarer plays the highest legal card; defenders play the lowest
    /// legal. Drives `declarerWins` and `declarerFails` recipes through to
    /// the assertion the recipe was designed for.
    case greedyForDeclarer(declarer: PlayerID)
    /// Every seat plays the lowest legal card. Drives misère and raspasy
    /// recipes — the cleaner / declarer can never beat the others.
    case lowestLegal
}
