import SwiftUI
import PreferansEngine

/// Tug-of-war settlement composer. The proposer drags a single divider to
/// split the *remaining* tricks between the declarer and the defending side;
/// a live verdict shows whether the declarer still makes the contract. One
/// expressive control replaces the old dropdown of up-to-eleven near-identical
/// "Declarer: N tricks" rows — the choice is one number, so it reads as one
/// gesture.
struct SettlementComposer: View {
    /// What "the declarer succeeds" means for the live verdict.
    enum Goal: Equatable {
        /// A positive contract: the declarer needs `needs` total tricks in a
        /// `strain` (nil strain == no-trump).
        case contract(needs: Int, tricks: Int, strain: Suit?)
        /// Misère: the declarer succeeds by taking zero tricks.
        case misere
    }

    let declarerName: String
    let defenseName: String
    /// Unplayed tricks — the pot being divided. Always > 0 when shown.
    let remaining: Int
    let currentDeclarerTricks: Int
    let goal: Goal
    let onOffer: (Int) -> Void
    let onCancel: () -> Void

    /// The declarer's share of the `remaining` pot (0...remaining).
    @State private var share: Int

    init(
        declarerName: String,
        defenseName: String,
        remaining: Int,
        currentDeclarerTricks: Int,
        goal: Goal,
        initialShare: Int,
        onOffer: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.declarerName = declarerName
        self.defenseName = defenseName
        self.remaining = remaining
        self.currentDeclarerTricks = currentDeclarerTricks
        self.goal = goal
        self.onOffer = onOffer
        self.onCancel = onCancel
        _share = State(initialValue: min(max(initialShare, 0), max(remaining, 0)))
    }

    private var declarerTotal: Int { currentDeclarerTricks + share }
    // Totals always sum to ten — the defending side gets the rest.
    private var defenseTotal: Int { 10 - declarerTotal }

    private var declarerSucceeds: Bool {
        switch goal {
        case let .contract(needs, _, _): return declarerTotal >= needs
        case .misere:                    return declarerTotal == 0
        }
    }

    private var verdictColor: Color {
        declarerSucceeds ? TableTheme.goldBright : Self.danger
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            endpointLabels
            splitBar
            verdict
            buttons
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Rectangle().fill(TableTheme.gold.opacity(0.30)).frame(height: 0.5)
            Text("Split \(remaining) \(remaining == 1 ? "trick" : "tricks")")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TableTheme.goldBright)
                .fixedSize()
            Rectangle().fill(TableTheme.gold.opacity(0.30)).frame(height: 0.5)
        }
    }

    private var endpointLabels: some View {
        HStack(alignment: .firstTextBaseline) {
            sideLabel(declarerName, count: declarerTotal, tint: TableTheme.goldBright, alignment: .leading)
            Spacer(minLength: 12)
            sideLabel(defenseName, count: defenseTotal, tint: TableTheme.inkCream, alignment: .trailing)
        }
    }

    private func sideLabel(_ name: String, count: Int, tint: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .lineLimit(1)
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    /// The bar spans all ten tricks, so the divider lines up with the big
    /// totals above it. Won tricks sit locked at each end; the proposer drags
    /// the divider only across the unplayed tricks bracketed by the two
    /// markers — exactly what is being divided.
    private var splitBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = w / 10
            let declarerWidth = min(max(unit * Double(declarerTotal), 0), w)
            let lowFloor = unit * Double(currentDeclarerTricks)
            let highFloor = unit * Double(currentDeclarerTricks + remaining)
            let knobX = min(max(declarerWidth, 2.5), w - 2.5)
            let track = RoundedRectangle(cornerRadius: 9, style: .continuous)
            ZStack(alignment: .leading) {
                // Two-tone fill — gold for the declarer's total, dim for the
                // defending side — clipped to the track so only the divider
                // edge is square.
                ZStack(alignment: .leading) {
                    Rectangle().fill(TableTheme.inkCream.opacity(0.12))
                    Rectangle()
                        .fill(TableTheme.gold.opacity(declarerSucceeds ? 0.90 : 0.50))
                        .frame(width: declarerWidth)
                }
                .frame(height: 26)
                .clipShape(track)
                .overlay(track.strokeBorder(TableTheme.inkCream.opacity(0.14), lineWidth: 0.5))

                // Range markers: everything outside them is already won, locked.
                floorMarker.offset(x: lowFloor - 1)
                floorMarker.offset(x: min(highFloor, w) - 1)

                // Divider handle.
                Capsule()
                    .fill(TableTheme.inkCream)
                    .frame(width: 5, height: 32)
                    .overlay(Capsule().strokeBorder(TableTheme.feltEdge.opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.40), radius: 2.5, y: 1)
                    .offset(x: knobX - 2.5)
            }
            .frame(height: 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard unit > 0 else { return }
                        let trick = Int((value.location.x / unit).rounded())
                        let total = min(max(trick, currentDeclarerTricks), currentDeclarerTricks + remaining)
                        let next = total - currentDeclarerTricks
                        if next != share { share = next }
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel("\(declarerName)'s share of the remaining tricks")
        .accessibilityValue("\(share) of \(remaining)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: share = min(remaining, share + 1)
            case .decrement: share = max(0, share - 1)
            @unknown default: break
            }
        }
    }

    private var floorMarker: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(TableTheme.inkCream.opacity(0.55))
            .frame(width: 2, height: 30)
    }

    @ViewBuilder
    private var verdict: some View {
        HStack(spacing: 5) {
            Image(systemName: declarerSucceeds ? "checkmark.seal.fill" : "xmark.seal")
                .font(.caption)
            verdictText
        }
        .foregroundStyle(verdictColor)
        .animation(.easeOut(duration: 0.15), value: declarerSucceeds)
    }

    @ViewBuilder
    private var verdictText: some View {
        switch goal {
        case let .contract(needs, tricks, strain):
            if declarerTotal >= needs {
                (Text("makes ") + contractGlyph(tricks: tricks, strain: strain))
                    .font(.caption.weight(.semibold))
            } else {
                let short = needs - declarerTotal
                (Text("\(short) short of ") + contractGlyph(tricks: tricks, strain: strain))
                    .font(.caption.weight(.semibold))
            }
        case .misere:
            Text(declarerTotal == 0 ? "clean misère" : "misère set — takes \(declarerTotal)")
                .font(.caption.weight(.semibold))
        }
    }

    /// "6♠" / "7NT" with the suit pip tinted for the felt.
    private func contractGlyph(tricks: Int, strain: Suit?) -> Text {
        let lead = Text("\(tricks)")
        if let strain {
            return lead + Text(strain.symbol).foregroundColor(strain.color(on: .felt))
        }
        return lead + Text("NT")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel").fontWeight(.semibold)
            }
            .buttonStyle(.feltDim)
            .accessibilityIdentifier(UIIdentifiers.buttonCancelSettlement)

            Spacer(minLength: 8)

            Button { onOffer(share) } label: {
                Label("Offer", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.feltPrimary)
            .accessibilityIdentifier(UIIdentifiers.buttonOfferSettlement)
        }
    }

    /// Muted terracotta that reads as "failure" against the felt without the
    /// alarm of system red — matched to the felt suit-red palette.
    private static let danger = Color(red: 0.92, green: 0.46, blue: 0.40)
}

#if DEBUG
/// Live-runtime gallery of composer states. Rooted by the `-previewSettlement`
/// launch flag (see `PreferansApp`) so the real view can be screenshotted in
/// the simulator without driving a whole game to a settle-able position.
struct SettlementPreviewGallery: View {
    var body: some View {
        ZStack {
            TableTheme.feltMid.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    state("Open game — makes", remaining: 3, won: 5,
                          goal: .contract(needs: 6, tricks: 6, strain: .spades), share: 1)
                    state("Open game — short", remaining: 3, won: 5,
                          goal: .contract(needs: 6, tricks: 6, strain: .spades), share: 0)
                    state("Misère — clean", remaining: 4, won: 0, goal: .misere, share: 0)
                    state("Opening lead (10)", remaining: 10, won: 0,
                          goal: .contract(needs: 6, tricks: 6, strain: .hearts), share: 6)
                }
                .padding(.vertical, 24)
            }
        }
    }

    @ViewBuilder
    private func state(_ title: String, remaining: Int, won: Int,
                       goal: SettlementComposer.Goal, share: Int) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(TableTheme.goldBright)
            SettlementComposer(
                declarerName: "Olga", defenseName: "Defense",
                remaining: remaining, currentDeclarerTricks: won,
                goal: goal, initialShare: share, onOffer: { _ in }, onCancel: {}
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .feltBand()
        }
    }
}
#endif

#Preview("Settle — open game") {
    SettlementComposer(
        declarerName: "Olga",
        defenseName: "Defense",
        remaining: 3,
        currentDeclarerTricks: 5,
        goal: .contract(needs: 6, tricks: 6, strain: .spades),
        initialShare: 1,
        onOffer: { _ in },
        onCancel: {}
    )
    .padding()
    .background(TableTheme.feltMid)
}

#Preview("Settle — misère") {
    SettlementComposer(
        declarerName: "Anna",
        defenseName: "Defense",
        remaining: 4,
        currentDeclarerTricks: 0,
        goal: .misere,
        initialShare: 0,
        onOffer: { _ in },
        onCancel: {}
    )
    .padding()
    .background(TableTheme.feltMid)
}
