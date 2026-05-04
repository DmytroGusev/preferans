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
        lastAction: RecentAction? = nil,
        roleBadge: SeatRoleBadge? = nil
    ) {
        self.seat = seat
        self.orientation = orientation
        self.lastAction = lastAction
        self.roleBadge = roleBadge
    }

    public var body: some View {
        if seat.role == .sittingOut {
            sittingOutChip
        } else {
            VStack(spacing: 6) {
                nameChip
                fan
                trickCounter
            }
            .opacity(seat.isActive ? 1 : 0.55)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
        }
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

    /// One-line player chip: avatar + name + dealer/role badges. Trick
    /// counts live below the fan so the name chip has one job: identity.
    private var nameChip: some View {
        HStack(spacing: 8) {
            if seat.isCurrentActor {
                Text("Acting")
                    .frame(width: 0, height: 0)
                    .clipped()
                    .opacity(0)
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Image(systemName: "person.crop.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                .accessibilityHidden(true)
            Text(seat.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))

            statusBadge
            rolePill
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .feltSurface(seat.isCurrentActor ? .seatActive : .seat, radius: TableTheme.Radius.sm)
        .shadow(color: seat.isCurrentActor ? TableTheme.goldBright.opacity(0.25) : .clear,
                radius: seat.isCurrentActor ? 8 : 0)
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

    /// Render one card back per card the opponent really holds, wrapping
    /// to a second row once the hand is wider than `cardsPerRow`. Every
    /// row is horizontal — even side seats — so cards never rotate
    /// vertically into the trick area. The first row gets the leading
    /// half; the second row stacks above it slightly inset so the fan
    /// reads as a held hand rather than two separate piles.
    private var fan: some View {
        let count = seat.hand.count
        let dims = CardView.Size.standard.dimensions
        let cardsPerRow = 5
        let rows = splitIntoRows(seat.hand, perRow: cardsPerRow)
        return VStack(spacing: -dims.height * 0.55) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                fanRow(cards: row, cardSize: dims)
            }
        }
        .frame(height: count == 0 ? 0 : rowsHeight(rowCount: rows.count, cardHeight: dims.height))
    }

    /// One horizontal row. Cards overlap by ~50% so a 5-card row stays
    /// narrow enough that three opponent fans fit on the upper third of
    /// an iPhone width without collisions. Each card renders face-up or
    /// face-down based on its `ProjectedCard` value, so open-whist hands
    /// (and any other revealed opponent cards) show their actual faces.
    private func fanRow(cards: [ProjectedCard], cardSize dims: CGSize) -> some View {
        let step: CGFloat = -dims.width * 0.50
        return HStack(spacing: step) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                CardView(
                    card: card,
                    size: .standard,
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

    private func rowsHeight(rowCount: Int, cardHeight: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        // Each subsequent row contributes only the visible 45% slice
        // (since the rows overlap by 55%).
        return cardHeight + CGFloat(rowCount - 1) * cardHeight * 0.45
    }
}
