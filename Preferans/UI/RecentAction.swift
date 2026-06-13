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
        // Once trick play starts the per-seat pill's job is done — the
        // persistent role badge carries declarer/whist/pass from here on.
        // Without this the pre-play snapshot lingered through the whole
        // play phase and the viewer plate showed "Pass" twice (role badge
        // + stale action pill).
        let scoped = scopedToCurrentDeal(events)
        let playStarted = scoped.contains { if case .playStarted = $0 { return true } else { return false } }
        if playStarted { return [:] }

        var result: [PlayerID: RecentAction] = [:]
        for (offset, event) in scopedToPreplay(events).enumerated() {
            // Once a contract is declared the auction is settled, and a
            // seat still wearing "Passed" from the bidding reads as a
            // whist-pass during the whist round. Drop auction passes at
            // that boundary; a real whist-pass re-adds the pill with the
            // correct meaning. The winning bid stays — "6♠" on the
            // declarer is still the headline of the deal.
            if case .contractDeclared = event {
                result = result.filter { $0.value.label != .pass }
            }
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
             .settlementProposed,
             .settlementAccepted,
             .settlementRejected,
             .playSettled,
             .dealScored,
             .matchEnded:
            return nil
        }
    }
}

// MARK: - Activity log

public struct ActivityLogEntry: Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var detail: String?
    public var kind: Kind

    public enum Kind: Equatable {
        case deal
        case auction
        case contract
        case defense
        case play
        case settlement
        case scoring

        var label: String {
            switch self {
            case .deal:       return String(localized: "Deal")
            case .auction:    return String(localized: "Auction")
            case .contract:   return String(localized: "Contract")
            case .defense:    return String(localized: "Defense")
            case .play:       return String(localized: "Play")
            case .settlement: return String(localized: "Settlement")
            case .scoring:    return String(localized: "Score")
            }
        }
    }
}

public enum ActivityLogFeed {
    public static func entries(
        from events: [PreferansEvent],
        displayName: (PlayerID) -> String
    ) -> [ActivityLogEntry] {
        events.enumerated().map { offset, event in
            let summary = summary(for: event, displayName: displayName)
            return ActivityLogEntry(
                id: offset,
                title: summary.title,
                detail: summary.detail,
                kind: summary.kind
            )
        }
    }

    public static func summaries(for events: [PreferansEvent]) -> [String] {
        events.map { event in
            let summary = summary(for: event) { $0.rawValue }
            if let detail = summary.detail {
                return "\(summary.title) · \(detail)"
            }
            return summary.title
        }
    }

    private static func summary(
        for event: PreferansEvent,
        displayName: (PlayerID) -> String
    ) -> (title: String, detail: String?, kind: ActivityLogEntry.Kind) {
        switch event {
        case let .dealStarted(dealer, activePlayers):
            return (
                String(localized: "\(displayName(dealer)) deals"),
                String(localized: "Playing: \(playerList(activePlayers, displayName: displayName))"),
                .deal
            )
        case let .bidAccepted(call):
            switch call.call {
            case .pass:
                return (String(localized: "\(displayName(call.player)) passed"), nil, .auction)
            case let .bid(bid):
                return (String(localized: "\(displayName(call.player)) bid \(renderedBid(bid))"), nil, .auction)
            }
        case let .auctionWon(declarer, bid):
            return (
                String(localized: "\(displayName(declarer)) won the auction"),
                renderedBid(bid),
                .auction
            )
        case .allPassed:
            return (String(localized: "Everyone passed"), String(localized: "Raspasy"), .auction)
        case let .talonExchanged(declarer, _, _):
            return (
                String(localized: "\(displayName(declarer)) took the prikup"),
                String(localized: "Discard hidden"),
                .contract
            )
        case let .contractDeclared(declarer, contract):
            return (
                String(localized: "\(displayName(declarer)) declared \(Localized.renderedGameContract(contract))"),
                nil,
                .contract
            )
        case let .whistAccepted(record):
            switch record.call {
            case .pass:
                return (String(localized: "\(displayName(record.player)) passed whist"), nil, .defense)
            case .whist:
                return (String(localized: "\(displayName(record.player)) whisted"), nil, .defense)
            case .halfWhist:
                return (String(localized: "\(displayName(record.player)) half-whisted"), nil, .defense)
            }
        case let .defenderModeChosen(whister, mode):
            return (
                String(localized: "\(displayName(whister)) chose \(renderedDefenderMode(mode)) defense"),
                nil,
                .defense
            )
        case let .playStarted(kind):
            return playStartedSummary(kind, displayName: displayName)
        case let .cardPlayed(play):
            return (
                String(localized: "\(displayName(play.player)) played \(play.card.description)"),
                nil,
                .play
            )
        case let .trickCompleted(trick):
            return (
                String(localized: "\(displayName(trick.winner)) took the trick"),
                String(localized: "\(trick.plays.count) cards played"),
                .play
            )
        case let .settlementProposed(proposal):
            return (
                String(localized: "\(displayName(proposal.proposer)) proposed a settlement"),
                String(localized: "\(displayName(proposal.settlement.target)) takes \(proposal.settlement.targetTricks) tricks"),
                .settlement
            )
        case let .settlementAccepted(player):
            return (String(localized: "\(displayName(player)) accepted the settlement"), nil, .settlement)
        case let .settlementRejected(player):
            return (String(localized: "\(displayName(player)) rejected the settlement"), nil, .settlement)
        case let .playSettled(settlement):
            return (
                String(localized: "Settlement agreed"),
                String(localized: "\(displayName(settlement.target)) takes \(settlement.targetTricks) tricks"),
                .settlement
            )
        case let .dealScored(result):
            return (String(localized: "Deal scored"), dealResultSummary(result, displayName: displayName), .scoring)
        case let .matchEnded(summary):
            if let winner = summary.standings.first?.player {
                return (String(localized: "Match over"), String(localized: "\(displayName(winner)) wins"), .scoring)
            }
            return (String(localized: "Match over"), nil, .scoring)
        }
    }

    private static func playStartedSummary(
        _ kind: PlayKind,
        displayName: (PlayerID) -> String
    ) -> (title: String, detail: String?, kind: ActivityLogEntry.Kind) {
        switch kind {
        case let .game(context):
            let detail: String
            if context.whisters.isEmpty {
                detail = String(localized: "\(displayName(context.declarer)) plays \(Localized.renderedGameContract(context.contract)), uncontested")
            } else {
                detail = String(localized: "\(displayName(context.declarer)) plays \(Localized.renderedGameContract(context.contract)); whist: \(playerList(context.whisters, displayName: displayName))")
            }
            return (String(localized: "Play started"), detail, .play)
        case let .misere(context):
            return (
                String(localized: "Play started"),
                String(localized: "\(displayName(context.declarer)) plays misère"),
                .play
            )
        case .allPass:
            return (String(localized: "Raspasy started"), nil, .play)
        }
    }

    private static func dealResultSummary(
        _ result: DealResult,
        displayName: (PlayerID) -> String
    ) -> String {
        switch result.kind {
        case .passedOut:
            return String(localized: "Defenders passed")
        case let .halfWhist(declarer, contract, halfWhister):
            return String(localized: "\(displayName(declarer)) scores \(Localized.renderedGameContract(contract)); \(displayName(halfWhister)) half-whists")
        case let .game(declarer, contract, whisters):
            let tricks = result.trickCounts[declarer] ?? 0
            let outcome = tricks >= contract.tricks
                ? String(localized: "\(displayName(declarer)) made \(Localized.renderedGameContract(contract))")
                : String(localized: "\(displayName(declarer)) went down on \(Localized.renderedGameContract(contract))")
            if whisters.isEmpty {
                return String(localized: "\(outcome) with \(tricks) tricks")
            }
            return String(localized: "\(outcome) with \(tricks) tricks; whist: \(playerList(whisters, displayName: displayName))")
        case let .misere(declarer):
            let tricks = result.trickCounts[declarer] ?? 0
            return tricks == 0
                ? String(localized: "\(displayName(declarer)) made misère")
                : String(localized: "\(displayName(declarer)) broke misère with \(tricks) tricks")
        case .allPass:
            return String(localized: "Raspasy scored")
        }
    }

    private static func renderedBid(_ bid: ContractBid) -> String {
        switch bid {
        case let .game(contract):
            return Localized.renderedGameContract(contract)
        case .misere:
            return String(localized: "Misère")
        case .totus:
            return String(localized: "Totus")
        }
    }

    private static func renderedDefenderMode(_ mode: DefenderPlayMode) -> String {
        switch mode {
        case .open:   return String(localized: "open")
        case .closed: return String(localized: "closed")
        }
    }

    private static func playerList(
        _ players: [PlayerID],
        displayName: (PlayerID) -> String
    ) -> String {
        players.map(displayName).joined(separator: ", ")
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
    /// Active contract, when the deal has moved beyond pure bidding. Kept
    /// in one place so the strip, table layout, and seat labels describe
    /// the same contract without each walking the projection differently.
    func activeContractSummary() -> (declarer: PlayerID, bid: ContractBid)? {
        switch phase {
        case let .awaitingDiscard(declarer, finalBid),
             let .awaitingContract(declarer, finalBid):
            return (declarer, finalBid)
        case let .awaitingWhist(_, declarer, contract):
            return (declarer, .game(contract))
        case let .awaitingDefenderMode(whister, _):
            for call in auction.reversed() {
                if case let .bid(bid) = call.call, call.player != whister {
                    return (call.player, bid)
                }
            }
            return nil
        case let .playing(_, _, kind):
            switch kind {
            case let .game(declarer, contract, _, _, _):
                return (declarer, .game(contract))
            case let .misere(declarer):
                return (declarer, .misere)
            case .allPass:
                return nil
            }
        default:
            return nil
        }
    }

    func activeContractBid(for player: PlayerID) -> ContractBid? {
        guard let summary = activeContractSummary(),
              summary.declarer == player else {
            return nil
        }
        return summary.bid
    }

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
