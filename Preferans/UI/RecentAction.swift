import SwiftUI
import PreferansEngine

/// A render-ready snapshot of "what a player just did", derived from the
/// engine event stream. Drives the centered action banner (the most recent
/// event) and the per-seat last-action badge (the latest event per seat,
/// reset between deals and cleared when trick play starts).
///
/// Card plays are intentionally excluded — the trick on the felt already
/// shows who played what, so a redundant per-seat pill just clutters the
/// chrome. Persistent role information ("Declarer" / "Whist" / "Pass") is
/// surfaced via `SeatRoleBadge` on the seat name chip instead.
///
/// `id` is monotonically increasing across the deal so SwiftUI can key
/// transitions off it — even when two identical actions fire in a row, the
/// banner re-animates because the id changed.
public struct RecentAction: Equatable, Identifiable {
    public var id: Int
    public var player: PlayerID
    public var label: Label

    public enum Label: Equatable {
        case bid(ContractBid)
        case pass
        case whist
        case halfWhist
        case whistPass
        case declared(GameContract)
        case discarded
        case defenderMode(DefenderPlayMode)
    }
}

public enum RecentActionFeed {
    /// Most recent banner-worthy action since the last deal started.
    /// Card plays are excluded — the card landing on the felt already
    /// serves as the banner. Trick-completion / deal-scored / match
    /// events are excluded too; those have their own UI surfaces.
    public static func banner(from events: [PreferansEvent]) -> RecentAction? {
        let scoped = scopedToCurrentDeal(events)
        for (offset, event) in scoped.enumerated().reversed() {
            if let label = bannerLabel(for: event) {
                return RecentAction(id: offset, player: label.player, label: label.label)
            }
        }
        return nil
    }

    /// Per-seat latest action since the deal started, clipped to the
    /// pre-play window. Once `.playStarted` fires the per-seat pill clears
    /// — the seat's persistent role badge ("Declarer" / "Whist" / "Pass")
    /// takes over the same screen real estate, so a stale "6♠" pill from
    /// the auction trail doesn't hover next to the live trick area.
    public static func perSeat(from events: [PreferansEvent]) -> [PlayerID: RecentAction] {
        var result: [PlayerID: RecentAction] = [:]
        for (offset, event) in scopedToPreplay(events).enumerated() {
            guard let resolved = bannerLabel(for: event) else { continue }
            result[resolved.player] = RecentAction(id: offset, player: resolved.player, label: resolved.label)
        }
        return result
    }

    /// Trim to events at or after the most recent `dealStarted`. Anything
    /// older is from a prior deal and shouldn't surface as "what just
    /// happened" in the live deal.
    private static func scopedToCurrentDeal(_ events: [PreferansEvent]) -> [PreferansEvent] {
        if let lastDealStart = events.lastIndex(where: { if case .dealStarted = $0 { return true } else { return false } }) {
            return Array(events[lastDealStart...])
        }
        return events
    }

    /// Subset of the current deal that ends at — but does not include —
    /// the first `.playStarted` event. Drives the per-seat pill, which is
    /// only meaningful during the auction / discard / whist run-up.
    private static func scopedToPreplay(_ events: [PreferansEvent]) -> [PreferansEvent] {
        let scoped = scopedToCurrentDeal(events)
        if let playIdx = scoped.firstIndex(where: { if case .playStarted = $0 { return true } else { return false } }) {
            return Array(scoped[..<playIdx])
        }
        return scoped
    }

    private struct Resolved {
        var player: PlayerID
        var label: RecentAction.Label
    }

    private static func bannerLabel(for event: PreferansEvent) -> Resolved? {
        switch event {
        case let .bidAccepted(call):
            switch call.call {
            case .pass:           return Resolved(player: call.player, label: .pass)
            case let .bid(bid):   return Resolved(player: call.player, label: .bid(bid))
            }
        case let .whistAccepted(record):
            switch record.call {
            case .pass:      return Resolved(player: record.player, label: .whistPass)
            case .whist:     return Resolved(player: record.player, label: .whist)
            case .halfWhist: return Resolved(player: record.player, label: .halfWhist)
            }
        case let .contractDeclared(declarer, contract):
            return Resolved(player: declarer, label: .declared(contract))
        case let .talonExchanged(declarer, _, _):
            return Resolved(player: declarer, label: .discarded)
        case let .defenderModeChosen(whister, mode):
            return Resolved(player: whister, label: .defenderMode(mode))
        case .cardPlayed,
             .dealStarted,
             .auctionWon,
             .allPassed,
             .playStarted,
             .trickCompleted,
             .dealScored,
             .matchEnded:
            return nil
        }
    }
}

// MARK: - Rendering

extension RecentAction.Label {
    /// The render hint used by both the center banner and the seat badge.
    /// Returns a small view that already encodes suit color so callers don't
    /// have to reason about strain → color themselves.
    @ViewBuilder
    func glyph(emphasis: Emphasis = .seat) -> some View {
        switch self {
        case let .bid(bid):
            BidGlyph(bid: bid, emphasis: emphasis)
        case .pass:
            Text("Pass")
                .foregroundStyle(emphasis.dimColor)
        case .whist:
            Text("Whist")
                .foregroundStyle(emphasis.accentColor)
        case .halfWhist:
            Text("Half-whist")
                .foregroundStyle(emphasis.accentColor)
        case .whistPass:
            Text("Pass")
                .foregroundStyle(emphasis.dimColor)
        case let .declared(contract):
            BidGlyph(bid: .game(contract), emphasis: emphasis, prefix: "Declared")
        case .discarded:
            Text("Discarded")
                .foregroundStyle(emphasis.bodyColor)
        case let .defenderMode(mode):
            Text(Localized.defenderMode(mode))
                .foregroundStyle(emphasis.accentColor)
        }
    }

    enum Emphasis {
        case banner
        case seat

        var bodyColor: Color {
            switch self {
            case .banner: return TableTheme.inkCream
            case .seat:   return TableTheme.inkCream
            }
        }
        var accentColor: Color {
            switch self {
            case .banner: return TableTheme.goldBright
            case .seat:   return TableTheme.goldBright
            }
        }
        var dimColor: Color {
            switch self {
            case .banner: return TableTheme.inkCreamSoft
            case .seat:   return TableTheme.inkCreamDim
            }
        }
    }
}

private struct BidGlyph: View {
    let bid: ContractBid
    let emphasis: RecentAction.Label.Emphasis
    var prefix: LocalizedStringKey? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let prefix {
                Text(prefix)
                    .foregroundStyle(emphasis.bodyColor)
            }
            switch bid {
            case let .game(contract):
                HStack(spacing: 1) {
                    Text("\(contract.tricks)")
                        .foregroundStyle(emphasis.bodyColor)
                    if let suit = contract.strain.suit {
                        Text(suit.symbol)
                            .foregroundStyle(suit.color(on: .felt))
                    } else {
                        Text("NT")
                            .foregroundStyle(emphasis.bodyColor)
                    }
                }
            case .misere:
                Text("Misère")
                    .foregroundStyle(emphasis.accentColor)
            case .totus:
                Text("Totus")
                    .foregroundStyle(emphasis.accentColor)
            }
        }
    }
}

// MARK: - Persistent role badge

/// Persistent "what is this seat doing in the deal" marker. Replaces the
/// transient `.played(card)` per-seat pill that used to bloom every trick;
/// this one is derived from the projection's role + whist call records, so
/// the same gold capsule sticks on the declarer's seat for the whole hand.
public enum SeatRoleBadge: Equatable {
    case declarer
    case whist
    case halfWhist
    case pass

    var label: LocalizedStringKey {
        switch self {
        case .declarer:  return "Declarer"
        case .whist:     return "Whist"
        case .halfWhist: return "½"
        case .pass:      return "Pass"
        }
    }

    /// Accent badges read as "is meaningfully participating" — declarer,
    /// whisters, half-whisters. The pass badge stays muted so a passing
    /// defender doesn't visually compete with the live whisters.
    var isAccent: Bool {
        switch self {
        case .declarer, .whist, .halfWhist: return true
        case .pass:                          return false
        }
    }
}

public extension PlayerGameProjection {
    /// Resolve the seat-role pill the screen renders inline on the name
    /// chip. Returns `nil` while the auction is still running and after
    /// the deal/match concludes — the badge is only meaningful from the
    /// moment a contract is on the table through the end of trick play.
    func roleBadge(for player: PlayerID) -> SeatRoleBadge? {
        switch phase {
        case .waitingForDeal,
             .bidding,
             .dealFinished,
             .gameOver:
            return nil
        default:
            break
        }
        if let call = whistCalls.first(where: { $0.player == player })?.call {
            switch call {
            case .whist:     return .whist
            case .halfWhist: return .halfWhist
            case .pass:      return .pass
            }
        }
        if let seat = seats.first(where: { $0.player == player }) {
            switch seat.role {
            case .declarer:    return .declarer
            case .whister:     return .whist
            case .halfWhister: return .halfWhist
            default:            return nil
            }
        }
        return nil
    }
}
