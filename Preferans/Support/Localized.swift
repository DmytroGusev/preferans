import SwiftUI
import PreferansEngine

/// Display-time localization for engine value types.
///
/// The engine package emits English strings via `description` for debug and
/// transport convenience. UI layers that want a translated label should call
/// these helpers instead of `.description`, since the engine intentionally has
/// no SwiftUI dependency and can't return `LocalizedStringKey` itself.
///
/// All catalog keys live in `Localizable.xcstrings`. Adding a translation is
/// a catalog edit, not a code change.
public enum Localized {
    /// Title for a projection phase. Static; varies only by `phase` case.
    public static func phaseTitle(_ phase: ProjectedPhase) -> LocalizedStringKey {
        switch phase {
        case .waitingForDeal:       return "Waiting for deal"
        case .bidding:              return "Bidding"
        case .awaitingDiscard:      return "Talon exchange"
        case .awaitingContract:     return "Declare contract"
        case .awaitingWhist:        return "Whist"
        case .awaitingDefenderMode: return "Defender mode"
        case .playing:              return "Playing"
        case .dealFinished:         return "Deal finished"
        case .gameOver:             return "Game over"
        }
    }

    public static func bidCall(_ call: BidCall) -> LocalizedStringKey {
        switch call {
        case .pass:           return "Pass"
        case let .bid(bid):   return contractBid(bid)
        }
    }

    public static func contractBid(_ bid: ContractBid) -> LocalizedStringKey {
        switch bid {
        case let .game(contract): return gameContractLabel(contract)
        case .misere:             return "Misere"
        case .totus:              return "Totus"
        }
    }

    /// Game-contract label as it should appear standalone (e.g. "6♠", "10NT").
    /// Suit symbols are universal Unicode so they're embedded directly; only
    /// the `NT` strain has a translated form (e.g. Russian `БК`).
    public static func gameContractLabel(_ contract: GameContract) -> LocalizedStringKey {
        switch contract.strain {
        case let .suit(suit):
            return LocalizedStringKey("\(contract.tricks)\(suit.symbol)")
        case .noTrump:
            // Two-segment composition keeps the catalog key stable as "NT"
            // while the visual label is "10NT" / "10БК" / "10БК".
            return LocalizedStringKey("\(contract.tricks)\(NSLocalizedString("NT", comment: "Strain — no trump."))")
        }
    }

    public static func whistCall(_ call: WhistCall) -> LocalizedStringKey {
        switch call {
        case .pass:      return "Pass"
        case .whist:     return "Whist"
        case .halfWhist: return "Half-whist"
        }
    }

    /// Strain label (suit symbol or `NT`) as a localizable key. Suit symbols
    /// fall through unchanged — they're universal — but `NT` translates.
    public static func strain(_ strain: Strain) -> LocalizedStringKey {
        switch strain {
        case let .suit(suit): return LocalizedStringKey(suit.symbol)
        case .noTrump:        return "NT"
        }
    }

    public static func defenderMode(_ mode: DefenderPlayMode) -> LocalizedStringKey {
        switch mode {
        case .open:   return "Open"
        case .closed: return "Closed"
        }
    }

    /// One-line result headline rendered as a SwiftUI `Text` so each branch
    /// can use a stable, translator-friendly catalog key while still
    /// composing player names and contracts at runtime.
    ///
    /// The contract label is rendered into a `String(localized:)` first so
    /// that its `NT`-vs-suit-symbol substitution happens through the
    /// catalog before being substituted into the outer template (otherwise
    /// the suit/NT key would be opaque to translators looking at the outer
    /// sentence in isolation).
    public static func dealResultHeadline(
        _ result: DealResult,
        displayName: (PlayerID) -> String
    ) -> Text {
        switch result.kind {
        case let .game(declarer, contract, whisters):
            let tricks = result.trickCounts[declarer] ?? 0
            let made = tricks >= contract.tricks
            let declarerName = displayName(declarer)
            let contractLabel = renderedGameContract(contract)
            if whisters.isEmpty {
                return made
                    ? Text("\(declarerName) made \(contractLabel) (\(tricks) tricks)")
                    : Text("\(declarerName) failed \(contractLabel) (\(tricks) tricks)")
            }
            let names = whisters.map(displayName).joined(separator: " + ")
            return made
                ? Text("\(declarerName) made \(contractLabel) (\(tricks) tricks) · whisters: \(names)")
                : Text("\(declarerName) failed \(contractLabel) (\(tricks) tricks) · whisters: \(names)")
        case let .misere(declarer):
            let tricks = result.trickCounts[declarer] ?? 0
            let declarerName = displayName(declarer)
            return tricks == 0
                ? Text("\(declarerName) made misère (\(tricks) tricks taken)")
                : Text("\(declarerName) failed misère (\(tricks) tricks taken)")
        case let .halfWhist(declarer, contract, halfWhister):
            return Text("\(displayName(declarer)) granted \(renderedGameContract(contract)) – \(displayName(halfWhister)) half-whisted")
        case .passedOut:
            return Text("All defenders passed – declarer awarded the contract")
        case .allPass:
            return Text("Hand passed out (raspasy)")
        }
    }

    /// Resolve a game contract to its display string ("6♠", "10БК", etc.)
    /// in the current locale. Used to inject pre-localized contract text
    /// into outer sentence templates.
    public static func renderedGameContract(_ contract: GameContract) -> String {
        switch contract.strain {
        case let .suit(suit):
            return "\(contract.tricks)\(suit.symbol)"
        case .noTrump:
            return "\(contract.tricks)\(String(localized: "NT", comment: "Strain — no trump."))"
        }
    }
}
