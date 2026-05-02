import Foundation

/// Single source of truth for accessibility identifiers used by the SwiftUI
/// views and queried by XCUITest. Lives in `PreferansEngine` so the app
/// target and any test harness can share the exact same encoders — a UI
/// test never spells an identifier as a string literal.
///
/// **Encoding rules**
/// - All identifiers are ASCII so `XCUIApplication.descendants(matching:)`
///   queries don't depend on Unicode normalization.
/// - Suits are encoded as one character: `S, C, D, H` plus `NT` for
///   no-trump. Ranks are encoded as their face value with `T` for the ten:
///   `7, 8, 9, T, J, Q, K, A`.
/// - Cards encode as `<rank><suit>` (e.g. `AS`, `TC`, `9H`).
/// - Game contracts encode as `<tricks><strain>` (e.g. `6S`, `10NT`).
/// - Bid calls encode as `pass`, the contract encoding, `misere`, or `totus`.
/// - Players use `playerID.rawValue` directly — callers control player names.
public enum UIIdentifiers {
    // MARK: - Encoders

    public static func encode(_ suit: Suit) -> String {
        switch suit {
        case .spades:   return "S"
        case .clubs:    return "C"
        case .diamonds: return "D"
        case .hearts:   return "H"
        }
    }

    public static func encode(_ rank: Rank) -> String {
        switch rank {
        case .seven:    return "7"
        case .eight:    return "8"
        case .nine:     return "9"
        case .ten:      return "T"
        case .jack:     return "J"
        case .queen:    return "Q"
        case .king:     return "K"
        case .ace:      return "A"
        }
    }

    public static func encode(_ strain: Strain) -> String {
        switch strain {
        case let .suit(suit): return encode(suit)
        case .noTrump:        return "NT"
        }
    }

    public static func encode(_ card: Card) -> String {
        encode(card.rank) + encode(card.suit)
    }

    public static func encode(_ contract: GameContract) -> String {
        "\(contract.tricks)\(encode(contract.strain))"
    }

    public static func encode(_ bid: ContractBid) -> String {
        switch bid {
        case let .game(contract): return encode(contract)
        case .misere:             return "misere"
        case .totus:              return "totus"
        }
    }

    public static func encode(_ call: BidCall) -> String {
        switch call {
        case .pass:           return "pass"
        case let .bid(bid):   return encode(bid)
        }
    }

    public static func encode(_ call: WhistCall) -> String {
        switch call {
        case .pass:       return "pass"
        case .whist:      return "whist"
        case .halfWhist:  return "halfWhist"
        }
    }

    public static func encode(_ mode: DefenderPlayMode) -> String {
        switch mode {
        case .closed: return "closed"
        case .open:   return "open"
        }
    }

    /// Region a card is rendered in, used as part of the card identifier so
    /// queries can target a specific copy unambiguously.
    public enum CardRegion: Hashable, Sendable {
        case hand(seat: PlayerID)
        case talon
        case discard
        case discardSelect
        case trick(seat: PlayerID)

        var token: String {
            switch self {
            case let .hand(seat):  return "hand.\(seat.rawValue)"
            case .talon:           return "talon"
            case .discard:         return "discard"
            case .discardSelect:   return "discardSelect"
            case let .trick(seat): return "trick.\(seat.rawValue)"
            }
        }
    }

    // MARK: - Lobby

    public static let lobbyTitle               = "lobby.title"
    public static let lobbyStartLocalTable     = "button.startLocalTable"
    public static let lobbyPlayerCountThree    = "button.playerCount.3"
    public static let lobbyPlayerCountFour     = "button.playerCount.4"
    public static func lobbyPlayerNameField(index: Int) -> String { "lobby.playerName.\(index)" }
    public static func lobbyBotToggle(index: Int) -> String       { "lobby.botToggle.\(index)" }
    public static let lobbyError               = "lobby.error"
    public static let lobbyValidationError     = "lobby.validationError"
    public static let lobbyQuickPlayVsBots     = "button.quickPlayVsBots"

    // MARK: - Game screen — header / structure

    public static let phaseTitle               = "phase.title"
    public static let phaseMessage             = "phase.message"
    public static let viewerLabel              = "viewer.label"
    public static let errorBanner              = "error.banner"

    public enum Panel: String {
        case bidding         = "panel.bidding"
        case discard         = "panel.discard"
        case contract        = "panel.contract"
        case whist           = "panel.whist"
        case defenderMode    = "panel.defenderMode"
        case playing         = "panel.playing"
        case dealFinished    = "panel.dealFinished"
        case gameOver        = "panel.gameOver"
        case score           = "panel.score"
        case currentTrick    = "panel.currentTrick"
        case talon           = "panel.talon"
        case discardArea     = "panel.discardArea"
        case table           = "panel.table"
        case eventLog        = "panel.eventLog"
    }

    // MARK: - Action buttons

    public static let buttonStartDeal          = "button.startDeal"
    public static let buttonDiscardSelected    = "button.discardSelected"

    public static func bidButton(_ call: BidCall) -> String  { "bid.\(encode(call))" }
    public static func contractButton(_ c: GameContract) -> String { "contract.\(encode(c))" }
    public static func whistButton(_ call: WhistCall) -> String { "whist.\(encode(call))" }
    public static func defenderModeButton(_ mode: DefenderPlayMode) -> String { "defenderMode.\(encode(mode))" }

    // MARK: - Cards

    /// Identifier for a known card in a specific region.
    public static func card(_ card: Card, in region: CardRegion) -> String {
        "card.\(region.token).\(encode(card))"
    }

    /// Identifier for a hidden card placeholder in a hand. `index` is the
    /// card's position in the rendered row (0-based); needed because a
    /// hidden hand has no per-card identity to disambiguate by.
    public static func hiddenCard(in seat: PlayerID, index: Int) -> String {
        "card.hand.\(seat.rawValue).hidden.\(index)"
    }

    // MARK: - Score board

    public static func scorePlayer(_ player: PlayerID) -> String   { "score.player.\(player.rawValue)" }
    public static func scorePool(_ player: PlayerID) -> String     { "score.pool.\(player.rawValue)" }
    public static func scoreMountain(_ player: PlayerID) -> String { "score.mountain.\(player.rawValue)" }
    public static func scoreBalance(_ player: PlayerID) -> String  { "score.balance.\(player.rawValue)" }
    public static func scoreWhists(writer: PlayerID, on target: PlayerID) -> String {
        "score.whists.\(writer.rawValue).on.\(target.rawValue)"
    }

    // MARK: - Per-seat indicators

    public static func seatRole(_ player: PlayerID) -> String         { "seat.\(player.rawValue).role" }
    public static func seatDealer(_ player: PlayerID) -> String       { "seat.\(player.rawValue).dealer" }
    public static func seatCurrentActor(_ player: PlayerID) -> String { "seat.\(player.rawValue).actor" }
    public static func seatTrickCount(_ player: PlayerID) -> String   { "seat.\(player.rawValue).trickCount" }
    public static func seatContainer(_ player: PlayerID) -> String    { "seat.\(player.rawValue)" }

    // MARK: - Deal finished

    public static let dealResultKind     = "dealResult.kind"
    public static let dealResultDeclarer = "dealResult.declarer"
    public static let dealResultContract = "dealResult.contract"
    public static let dealResultTricks   = "dealResult.tricks"

    // MARK: - Game over

    public static let gameOverTitle      = "gameOver.title"
    public static let gameOverWinner     = "gameOver.winner"
    public static let gameOverDealsPlayed = "gameOver.dealsPlayed"
    public static func gameOverStandingPlayer(rank: Int) -> String  { "gameOver.standing.\(rank).player" }
    public static func gameOverStandingPool(rank: Int) -> String    { "gameOver.standing.\(rank).pool" }
    public static func gameOverStandingMountain(rank: Int) -> String { "gameOver.standing.\(rank).mountain" }
    public static func gameOverStandingBalance(rank: Int) -> String { "gameOver.standing.\(rank).balance" }

    // MARK: - Event log

    public static func eventLogEntry(index: Int) -> String { "eventLog.entry.\(index)" }

    // MARK: - Match settings status (visible affordance)

    public static let matchPoolTarget = "match.poolTarget"
    public static let matchTotusPolicy = "match.totusPolicy"
    public static let matchRaspasyPolicy = "match.raspasyPolicy"
}

// MARK: - Result-kind encoding

public extension UIIdentifiers {
    /// Stable string encoding of a deal result kind. Used as the value of
    /// the `dealResult.kind` text so the UI test can assert on a specific
    /// outcome without parsing localized prose.
    static func encode(_ kind: DealResultKind) -> String {
        switch kind {
        case .passedOut:
            return "passedOut"
        case let .halfWhist(declarer, contract, halfWhister):
            return "halfWhist.\(declarer.rawValue).\(encode(contract)).\(halfWhister.rawValue)"
        case let .game(declarer, contract, whisters):
            let w = whisters.map(\.rawValue).joined(separator: "+")
            return "game.\(declarer.rawValue).\(encode(contract)).\(w)"
        case let .misere(declarer):
            return "misere.\(declarer.rawValue)"
        case .allPass:
            return "allPass"
        }
    }
}

/// Launch-argument flags consumed by the app's `TestHarness` and produced
/// by the UI test target. Single source of truth so the producer (UI tests)
/// and the consumer (running app) can't drift on a flag string.
public enum UITestFlags {
    public static let viewerFollowsActor = "-uiTestViewerFollowsActor"
    public static let firstDealer        = "-uiTestFirstDealer"
    public static let dealSeed           = "-uiTestDealSeed"
    public static let dealScenario       = "-uiTestDealScenario"
    public static let matchScript        = "-uiTestMatchScript"
    public static let players            = "-uiTestPlayers"
    public static let poolTarget         = "-uiTestPoolTarget"
    public static let raspasyPolicy      = "-uiTestRaspasyPolicy"
    public static let totusPolicy        = "-uiTestTotusPolicy"
    public static let disableAnimations  = "-uiTestDisableAnimations"
}
