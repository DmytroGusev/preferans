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
        case .waitingForDeal:       return "Ready"
        case .bidding:              return "Bidding"
        case .awaitingDiscard:      return "Prikup exchange"
        case .awaitingContract:     return "Contract"
        case .awaitingWhist:        return "Whist"
        case .awaitingDefenderMode: return "Defense"
        case .playing:              return "Play"
        case .dealFinished:         return "Deal complete"
        case .gameOver:             return "Game over"
        }
    }

    /// Empty-felt placeholder for a phase. Companion to `phaseTitle`:
    /// the title is the noun ("Bidding"), the felt placeholder is the
    /// scene ("The auction"). Co-located so translators see the pair.
    public static func feltPlaceholder(_ phase: ProjectedPhase) -> LocalizedStringKey {
        switch phase {
        case .bidding:                   return "The auction"
        case .awaitingContract:          return "Naming the contract"
        case .awaitingWhist:             return "Calling whist"
        case .awaitingDefenderMode:      return "Open or closed?"
        case .playing:                   return "Next trick"
        case .waitingForDeal:            return "Tap Deal to begin"
        case .dealFinished, .gameOver:   return "Deal complete"
        case .awaitingDiscard:           return "The prikup"
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
        in projection: PlayerGameProjection
    ) -> Text {
        dealResultHeadline(result, displayName: projection.displayName(for:))
    }

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
                    ? Text("\(declarerName) made \(contractLabel) — \(tricks) tricks")
                    : Text("\(declarerName) went down on \(contractLabel) — \(tricks) tricks")
            }
            let names = whisters.map(displayName).joined(separator: " + ")
            return made
                ? Text("\(declarerName) made \(contractLabel) — \(tricks) tricks. Whisting: \(names)")
                : Text("\(declarerName) went down on \(contractLabel) — \(tricks) tricks. Whisting: \(names)")
        case let .misere(declarer):
            let tricks = result.trickCounts[declarer] ?? 0
            let declarerName = displayName(declarer)
            return tricks == 0
                ? Text("\(declarerName) made misère")
                : Text("\(declarerName) broke misère — \(tricks) tricks taken")
        case let .halfWhist(declarer, contract, halfWhister):
            return Text("\(displayName(declarer)) takes \(renderedGameContract(contract)) — \(displayName(halfWhister)) half-whists")
        case .passedOut:
            return Text("Defenders passed — contract uncontested")
        case .allPass:
            return Text("Raspasy — no contract")
        }
    }

    /// Localized status text for the felt-band tag and the action-bar
    /// no-actor fallback. The projection emits a typed `ProjectedStatus`
    /// so this helper is the single place that turns an actor + phase
    /// kind into a localized phrase — call sites no longer build the
    /// English sentence themselves.
    public static func statusText(_ projection: PlayerGameProjection) -> Text {
        statusText(projection.status, displayName: projection.displayName(for:))
    }

    public static func statusText(
        _ status: ProjectedStatus,
        displayName: (PlayerID) -> String
    ) -> Text {
        switch status {
        case .readyToDeal:
            return Text("Tap Deal to start")
        case let .bidding(currentPlayer):
            return Text("\(displayName(currentPlayer)) to call")
        case let .takingPrikup(declarer):
            return Text("\(displayName(declarer)) takes the prikup")
        case let .namingContract(declarer, pickingTotusStrain):
            return pickingTotusStrain
                ? Text("\(displayName(declarer)) picks the totus strain")
                : Text("\(displayName(declarer)) names the contract")
        case let .callingWhist(currentPlayer):
            return Text("\(displayName(currentPlayer)) to call whist")
        case let .choosingDefenderMode(whister):
            return Text("\(displayName(whister)) — open or closed?")
        case let .playingTrick(currentPlayer, trickNumber):
            return Text("Trick \(trickNumber): \(displayName(currentPlayer))")
        case .dealScored:
            return Text("Deal scored")
        case let .matchOver(winner):
            if let winner {
                return Text("\(displayName(winner)) takes the pulka")
            } else {
                return Text("Match over")
            }
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
