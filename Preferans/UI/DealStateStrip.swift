import SwiftUI
import PreferansEngine

/// Compact, persistent deal-state strip. Two rows in one chip rail:
///   1. Phase row — leading contract / declarer + bid, or auction trail.
///   2. Vzyatki row — tricks won so far, always visible during a deal.
///
/// Replaces the previous "ambient placeholder text" that disappeared as
/// soon as a card was played. Surfaces every preferans data point a
/// player needs at a glance: contract, whisters / passers, vzyatki, last
/// trick winner, dealer.
public struct DealStateStrip: View {
    public var projection: PlayerGameProjection

    public init(projection: PlayerGameProjection) {
        self.projection = projection
    }

    public var body: some View {
        Group {
            switch projection.phase {
            case .waitingForDeal, .gameOver, .dealFinished:
                EmptyView()
            default:
                rows
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: TableTheme.Radius.sm, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TableTheme.Radius.sm, style: .continuous)
                            .strokeBorder(TableTheme.gold.opacity(0.18), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 8)
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 4) {
            phaseRow
            vzyatkiRow
        }
    }

    // MARK: - Phase row

    @ViewBuilder
    private var phaseRow: some View {
        switch projection.phase {
        case .bidding:
            biddingRow
        case .awaitingContract:
            biddingRow
        case .awaitingDiscard, .awaitingWhist, .awaitingDefenderMode:
            contractRow
        case .playing:
            playingRow
        default:
            EmptyView()
        }
    }

    /// Bidding-phase row. Shows the current leader (highest bid + declarer)
    /// and the trail of recent calls, so the user sees how the auction is
    /// climbing.
    private var biddingRow: some View {
        HStack(spacing: 6) {
            if let (declarer, bid) = highestBid() {
                contractChip(declarer: declarer, bid: bid, label: stripLeading)
            } else {
                phaseLabel("Auction")
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                // Most recent calls land on the right; cap to last 5 so
                // the chip rail stays compact mid-auction without needing
                // to scroll on phone widths.
                ForEach(Array(projection.auction.suffix(5).enumerated()), id: \.offset) { _, call in
                    auctionPill(call: call)
                }
            }
        }
    }

    /// Once a contract is named: declarer chip + per-defender whist status
    /// pill so the user sees who's whisting at a glance.
    private var contractRow: some View {
        let summary = wonContractSummary()
        return HStack(spacing: 6) {
            if let (declarer, bid) = summary {
                contractChip(declarer: declarer, bid: bid, label: nil)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(defenderStatuses(declarer: summary?.0), id: \.player) { row in
                    whistPill(row: row)
                }
            }
        }
    }

    /// Trick-play row. Contract chip + last-trick winner.
    private var playingRow: some View {
        let summary = wonContractSummary()
        return HStack(spacing: 6) {
            if let (declarer, bid) = summary {
                contractChip(declarer: declarer, bid: bid, label: nil)
            }
            Spacer(minLength: 4)
            if let last = lastTrickWinner() {
                lastTrickPill(player: last.player, card: last.card)
            }
        }
    }

    // MARK: - Vzyatki row

    /// "Anya 4 • Misha 2 • Lena 1" — the running tricks-per-active-seat
    /// always rendered so the user never has to count cards. Sitting-out
    /// seats are excluded; the declarer (when known) is highlighted gold.
    private var vzyatkiRow: some View {
        let declarer = wonContractSummary()?.0
        return HStack(spacing: 4) {
            ForEach(activeSeats, id: \.player) { seat in
                let isDeclarer = seat.player == declarer
                HStack(spacing: 3) {
                    Text(seat.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                    Text("\(seat.trickCount)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(isDeclarer
                                   ? TableTheme.gold.opacity(0.20)
                                   : Color.black.opacity(0.30))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isDeclarer ? TableTheme.gold.opacity(0.55) : Color.clear,
                        lineWidth: 0.5
                    )
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var stripLeading: String { String(localized: "strip.leading") }
    private var stripLast: String { String(localized: "strip.last") }
    private var stripWhist: LocalizedStringKey { "strip.whist" }
    private var stripPass: LocalizedStringKey { "strip.pass" }

    // MARK: - Building blocks

    private func phaseLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(TableTheme.goldBright)
    }

    /// One pill per auction call. Pass renders as a quiet "—", real bids
    /// render with the suit symbol so the strain reads at a glance.
    private func auctionPill(call: AuctionCall) -> some View {
        HStack(spacing: 3) {
            Text(initials(call.player))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TableTheme.inkCreamSoft)
            Group {
                switch call.call {
                case .pass:
                    Text("—")
                        .foregroundStyle(TableTheme.inkCreamDim)
                case let .bid(bid):
                    bidGlyph(bid: bid)
                }
            }
            .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.black.opacity(0.32), in: Capsule())
    }

    @ViewBuilder
    private func bidGlyph(bid: ContractBid) -> some View {
        switch bid {
        case let .game(contract):
            HStack(spacing: 1) {
                Text("\(contract.tricks)")
                    .foregroundStyle(TableTheme.inkCream)
                if let suit = contract.strain.suit {
                    Text(suit.symbol)
                        .foregroundStyle(suit.color(on: .felt))
                } else {
                    Text("NT")
                        .foregroundStyle(TableTheme.inkCream)
                }
            }
        case .misere:
            Text("MIS")
                .foregroundStyle(TableTheme.goldBright)
        case .totus:
            Text("TOT")
                .foregroundStyle(TableTheme.goldBright)
        }
    }

    /// Per-defender whist status: whist / pass / half-whist or a quiet
    /// "thinking" placeholder when the engine is still waiting on them.
    private func whistPill(row: DefenderRow) -> some View {
        let (foreground, background, label): (Color, Color, LocalizedStringKey) = {
            switch row.status {
            case .whist:
                return (TableTheme.feltDeep, TableTheme.goldBright, stripWhist)
            case .halfWhist:
                return (TableTheme.feltDeep, TableTheme.gold, "½")
            case .pass:
                return (TableTheme.inkCreamSoft, Color.black.opacity(0.30), stripPass)
            case .pending:
                return (TableTheme.inkCreamDim, Color.black.opacity(0.30), "…")
            }
        }()
        return HStack(spacing: 3) {
            Text(initials(row.player))
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(background, in: Capsule())
    }

    /// Last-trick winner, with a tiny representation of the winning card.
    private func lastTrickPill(player: PlayerID, card: Card) -> some View {
        HStack(spacing: 4) {
            Text(stripLast)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.inkCreamSoft)
            Text(initials(player))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TableTheme.inkCream)
            HStack(spacing: 0) {
                Text(card.rank.symbol)
                    .foregroundStyle(card.suit.color(on: .felt))
                Text(card.suit.symbol)
                    .foregroundStyle(card.suit.color(on: .felt))
            }
            .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.black.opacity(0.32), in: Capsule())
    }

    /// "Anya — 6♠" pill highlighting the live contract. Used in both the
    /// whist row (just-named contract) and the play row (live contract).
    private func contractChip(declarer: PlayerID, bid: ContractBid, label: String?) -> some View {
        HStack(spacing: 4) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            Text(projection.displayName(for: declarer))
                .font(.caption.weight(.bold))
                .foregroundStyle(TableTheme.inkCream)
                .lineLimit(1)
            bidGlyph(bid: bid)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(TableTheme.gold.opacity(0.25))
        )
        .overlay(
            Capsule().strokeBorder(TableTheme.gold.opacity(0.55), lineWidth: 0.5)
        )
    }

    // MARK: - Data helpers

    private var activeSeats: [SeatProjection] {
        projection.seats.filter { $0.role != .sittingOut }
    }

    private func initials(_ player: PlayerID) -> String {
        let name = projection.displayName(for: player)
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    private func highestBid() -> (PlayerID, ContractBid)? {
        var best: (PlayerID, ContractBid)?
        for call in projection.auction {
            if case let .bid(bid) = call.call {
                if let (_, current) = best {
                    if bid > current { best = (call.player, bid) }
                } else {
                    best = (call.player, bid)
                }
            }
        }
        return best
    }

    /// Resolve the active deal's declarer + bid. Once the auction lands a
    /// contract the declarer is encoded in the phase itself (the auction
    /// trail keeps `.bid` calls but doesn't follow `.declareContract`); the
    /// auction-walk fallback covers raspasy / mid-bid where the phase
    /// hasn't progressed past `.bidding`.
    private func wonContractSummary() -> (PlayerID, ContractBid)? {
        switch projection.phase {
        case let .awaitingDiscard(declarer, finalBid),
             let .awaitingContract(declarer, finalBid):
            return (declarer, finalBid)
        case let .awaitingWhist(_, declarer, contract):
            return (declarer, .game(contract))
        case let .awaitingDefenderMode(whister, contract):
            // Defender mode happens after a whister has called; the
            // declarer is the seat that won the auction. Walk the auction
            // for that, falling back to the whister's seat (defensive).
            for call in projection.auction.reversed() {
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
            for call in projection.auction.reversed() {
                if case let .bid(bid) = call.call {
                    return (call.player, bid)
                }
            }
            return nil
        }
    }

    /// Last-trick winner inferred from `currentTrick` is not available
    /// post-trick; the projection doesn't carry trick history yet, so fall
    /// back to the per-seat trickCount delta — the seat whose count
    /// matches `completedTrickCount` and whose trickCount jumped most
    /// recently is the most likely winner. When unavailable, return nil.
    private func lastTrickWinner() -> (player: PlayerID, card: Card)? {
        // Without a trick history in the projection there's no clean way to
        // surface the last trick's leading card. For now, return nil — the
        // play row will simply skip the pill until the data flows.
        nil
    }

    private func defenderStatuses(declarer: PlayerID?) -> [DefenderRow] {
        guard let declarer else { return [] }
        let defenders = activeSeats
            .map(\.player)
            .filter { $0 != declarer }
        return defenders.map { player in
            let recorded = projection.whistCalls.first { $0.player == player }
            switch recorded?.call {
            case .whist:     return DefenderRow(player: player, status: .whist)
            case .halfWhist: return DefenderRow(player: player, status: .halfWhist)
            case .pass:      return DefenderRow(player: player, status: .pass)
            case .none:      return DefenderRow(player: player, status: .pending)
            }
        }
    }

    struct DefenderRow {
        var player: PlayerID
        var status: Status
        enum Status { case whist, halfWhist, pass, pending }
    }
}
