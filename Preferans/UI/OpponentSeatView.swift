import SwiftUI
import PreferansEngine

/// Opponent seat rendered as a real face-down hand fan + a quiet name
/// chip — no dark box. The fan shows one card back per card the opponent
/// actually holds, so a 10-card hand reads as ten cards and a 1-card
/// late-trick hand reads as one. Hands wider than ~5 cards wrap to a
/// second row so the seat footprint stays compact and readable from the
/// viewer's perspective regardless of where the seat sits at the table.
public struct OpponentSeatView: View {
    public var seat: SeatProjection
    /// Position relative to the viewer. Drives a tiny visual offset (no
    /// rotation any more — every opponent's hand reads horizontally from
    /// the viewer's POV so cards never rotate vertically and clip the
    /// trick area).
    public var orientation: Orientation
    /// Presentation-only suit order used for face-up hands.
    public var cardSuitOrder: CardSuitDisplayOrder
    /// Contract carried by this seat when it is the declarer. Lets the
    /// label say "Declarer 6♥" instead of a context-free role chip.
    public var contractBid: ContractBid?
    /// True when another opponent has an open hand and this closed hand
    /// should yield space. Keeps hidden piles from visually competing
    /// with revealed cards.
    public var isDeemphasized: Bool
    /// Latest auction-trail action this seat took during the current deal.
    /// When non-nil the seat's name chip carries an inline pill ("Pass",
    /// "6♠", "Whist") so the user can see at a glance what the seat just
    /// did without scanning the trail. Cleared once trick play starts —
    /// the persistent `roleBadge` takes over from then on.
    public var lastAction: RecentAction?
    /// Persistent contract-role pill ("Declarer" / "Whist" / "½" / "Pass").
    /// Visible from the moment a contract is named through the end of
    /// the deal so a glance at any seat answers "who is playing what".
    public var roleBadge: SeatRoleBadge?

    public enum Orientation: Equatable {
        case top
        case left
        case right
    }

    public init(
        seat: SeatProjection,
        orientation: Orientation = .top,
        cardSuitOrder: CardSuitDisplayOrder = .default,
        contractBid: ContractBid? = nil,
        isDeemphasized: Bool = false,
        lastAction: RecentAction? = nil,
        roleBadge: SeatRoleBadge? = nil
    ) {
        self.seat = seat
        self.orientation = orientation
        self.cardSuitOrder = cardSuitOrder
        self.contractBid = contractBid
        self.isDeemphasized = isDeemphasized
        self.lastAction = lastAction
        self.roleBadge = roleBadge
    }

    public var body: some View {
        if seat.role == .sittingOut {
            sittingOutChip
        } else {
            VStack(spacing: isDeemphasized ? 4 : 6) {
                nameChip
                fan
                if !isDeemphasized {
                    trickCounter
                }
            }
            .opacity(seat.isActive ? (isDeemphasized ? 0.82 : 1) : 0.55)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
        }
    }

    /// True when at least one card in the seat's projected hand is
    /// visible. Drives the "open" rendering mode — bigger cards, sorted
    /// by suit, wider step — so face-up contracts (misère, open whist)
    /// are actually readable.
    private var isOpenHand: Bool {
        seat.hand.contains { $0.knownCard != nil }
    }

    /// Single-line chip for the 4-player sitting-out dealer. The full seat
    /// tile (name + action pill + face-down fan) wastes a slot's worth of
    /// real estate on a player who isn't dealing in this hand, so the
    /// sitting-out seat collapses to a quiet name + "OUT" pill that the
    /// table can tuck into a corner.
    private var sittingOutChip: some View {
        HStack(spacing: 5) {
            Text(seat.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            Text("OUT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(TableTheme.feltDeep)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(TableTheme.inkCreamSoft, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .opacity(0.65)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    /// Player plate with one readable subtitle. This replaces stacked
    /// micro-pills so role and open-hand state read as words instead of
    /// clipped abbreviations.
    private var nameChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            if seat.isCurrentActor {
                Text("Acting")
                    .frame(width: 0, height: 0)
                    .clipped()
                    .opacity(0)
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font((isDeemphasized ? Font.caption : Font.subheadline).weight(.semibold))
                    .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                    .accessibilityHidden(true)
                Text(seat.displayName)
                    .font((isDeemphasized ? Font.caption : Font.subheadline).weight(.semibold))
                    .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            }
            if let subtitle = seatSubtitle {
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright.opacity(0.90) : TableTheme.inkCreamSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .accessibilityIdentifier(UIIdentifiers.seatRoleBadge(seat.player))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isDeemphasized ? 8 : 10)
        .padding(.vertical, isDeemphasized ? 5 : 7)
        .feltSurface(seat.isCurrentActor ? .seatActive : .seat, radius: TableTheme.Radius.sm)
        .shadow(color: seat.isCurrentActor ? TableTheme.goldBright.opacity(0.25) : .clear,
                radius: seat.isCurrentActor ? 8 : 0)
    }

    private var seatSubtitle: String? {
        var parts: [String] = []
        if isOpenHand {
            parts.append(String(localized: "Open hand"))
        }
        if let role = roleDescription {
            parts.append(role)
        } else if seat.isDealer {
            parts.append(String(localized: "Dealer"))
        } else if let action = lastActionDescription {
            parts.append(action)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var roleDescription: String? {
        guard let roleBadge else { return nil }
        switch roleBadge {
        case .declarer:
            if let contractBid {
                return "\(String(localized: "Declarer")) \(renderedBid(contractBid))"
            }
            return String(localized: "Declarer")
        case .whist:
            return String(localized: "Whist")
        case .halfWhist:
            return String(localized: "Half-whist")
        case .pass:
            return String(localized: "Passed")
        }
    }

    private var lastActionDescription: String? {
        guard let lastAction else { return nil }
        switch lastAction.label {
        case let .bid(bid):
            return renderedBid(bid)
        case .pass, .whistPass:
            return String(localized: "Passed")
        case .whist:
            return String(localized: "Whist")
        case .halfWhist:
            return String(localized: "Half-whist")
        case let .declared(contract):
            return "\(String(localized: "Declared")) \(Localized.renderedGameContract(contract))"
        case .discarded:
            return String(localized: "Discarded")
        case let .defenderMode(mode):
            switch mode {
            case .open:
                return String(localized: "Open")
            case .closed:
                return String(localized: "Closed")
            }
        }
    }

    private func renderedBid(_ bid: ContractBid) -> String {
        switch bid {
        case let .game(contract):
            return Localized.renderedGameContract(contract)
        case .misere:
            return String(localized: "Misère")
        case .totus:
            return String(localized: "Totus")
        }
    }

    private var trickCounter: some View {
        Text("\(seat.trickCount) tricks")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(TableTheme.inkCreamSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.20), in: Capsule())
            .overlay(
                Capsule().strokeBorder(TableTheme.inkCream.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityLabel("\(seat.trickCount) tricks")
            .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
    }

    /// Persistent contract-role pill rendered inline next to the seat
    /// name once a contract is on the table. Accent variants (Declarer,
    /// Whist, ½) get a gold-tinted capsule; the muted Pass variant uses
    /// a quiet dark capsule so passing defenders don't visually compete
    /// with whisters.
    @ViewBuilder
    private var rolePill: some View {
        if let badge = roleBadge {
            Text(badge.label)
                .font(.caption2.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(badge.isAccent ? TableTheme.feltDeep : TableTheme.inkCreamSoft)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(
                        badge.isAccent
                            ? TableTheme.goldBright
                            : Color.black.opacity(0.30)
                    )
                )
                .accessibilityIdentifier(UIIdentifiers.seatRoleBadge(seat.player))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if seat.role == .sittingOut {
            Text("OUT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(TableTheme.feltDeep)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(TableTheme.inkCreamSoft, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
        } else if seat.isDealer {
            Text("Dealer")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TableTheme.feltDeep)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(TableTheme.goldBright, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
        }
    }

    /// Render the opponent's hand. Hidden hands get the compact face-down
    /// pile (5 per row, tight overlap). Open hands — where the projection
    /// has revealed at least one card (misère, open whist, etc.) — get a
    /// bigger card size, suit-grouped rows, and a wider step so each
    /// rank/pip is fully readable from the viewer's seat.
    @ViewBuilder
    private var fan: some View {
        if isOpenHand {
            openFan
        } else {
            hiddenFan
        }
    }

    private var hiddenFan: some View {
        let count = seat.hand.count
        let size: CardView.Size = isDeemphasized ? .compact : .standard
        let dims = size.dimensions
        let cardsPerRow = 5
        let rows = splitIntoRows(seat.hand, perRow: cardsPerRow)
        return VStack(spacing: -dims.height * 0.55) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                fanRow(cards: row, size: size, stepFactor: isDeemphasized ? 0.62 : 0.50)
            }
        }
        .frame(height: count == 0 ? 0 : rowsHeight(rowCount: rows.count, cardHeight: dims.height, overlap: 0.55))
    }

    /// Face-up layout used when the projection has revealed the hand. Open
    /// hands get two readable rows, bigger cards, and a wider step so every
    /// rank+pip remains visible without claiming four rows of vertical space.
    private var openFan: some View {
        let dims = CardView.Size.large.dimensions
        let rows = openHandRows(seat.hand)
        let rowHeight = dims.height + 12
        return VStack(spacing: -rowHeight * 0.55) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                CardFanView(
                    cards: row,
                    seat: seat.player,
                    size: .large
                )
            }
        }
        .frame(height: rows.isEmpty ? 0 : rowsHeight(rowCount: rows.count, cardHeight: rowHeight, overlap: 0.55))
    }

    /// One horizontal row. `stepFactor` is the fraction of card width the
    /// next card overlaps the previous — 0.50 keeps a face-down pile
    /// compact, 0.32 leaves enough of each face card to read rank+pip.
    private func fanRow(cards: [ProjectedCard], size: CardView.Size, stepFactor: CGFloat) -> some View {
        let dims = size.dimensions
        let step: CGFloat = -dims.width * stepFactor
        return HStack(spacing: step) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                CardView(
                    card: card,
                    size: size,
                    region: .hand(seat: seat.player),
                    indexInRow: index
                )
            }
        }
    }

    /// Two-row split for hands wider than `perRow`. Top row gets the
    /// remainder, bottom row gets the full row — that way 10 cards split
    /// 5+5, 9 cards split 4+5, etc.
    private func splitIntoRows(_ cards: [ProjectedCard], perRow: Int) -> [[ProjectedCard]] {
        guard !cards.isEmpty else { return [] }
        if cards.count <= perRow { return [cards] }
        let topCount = cards.count - perRow
        let top = Array(cards.prefix(topCount))
        let bottom = Array(cards.suffix(perRow))
        return [top, bottom]
    }

    /// Sort revealed cards for table display, then split into readable rows
    /// of five. Unknown cards ride along at the end so the seat still
    /// renders all `seat.hand.count` slots.
    private func openHandRows(_ cards: [ProjectedCard]) -> [[ProjectedCard]] {
        guard !cards.isEmpty else { return [] }
        let known = cards.compactMap { $0.knownCard }
        let hidden = cards.filter { $0.knownCard == nil }
        let sorted = known
            .sortedForTableDisplay(order: cardSuitOrder)
            .map { ProjectedCard.known($0) } + hidden
        return splitIntoRows(sorted, perRow: 5)
    }

    private func rowsHeight(rowCount: Int, cardHeight: CGFloat, overlap: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        // Each subsequent row contributes only the visible (1 - overlap)
        // slice on top of the first.
        return cardHeight + CGFloat(rowCount - 1) * cardHeight * (1 - overlap)
    }
}
