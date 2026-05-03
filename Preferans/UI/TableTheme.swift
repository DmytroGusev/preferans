import SwiftUI
import PreferansEngine

/// Visual language for the card table. Everything that lives on the felt
/// — surfaces, status pills, action buttons — pulls its tokens from here
/// so the table reads as one continuous environment instead of an ad-hoc
/// stack of opacity-modified blacks. Hierarchy comes from layered surface
/// lightness, not drop shadows.
public enum TableTheme {
    // MARK: - Felt

    public static let feltDeep = Color(red: 0.04, green: 0.16, blue: 0.10)
    public static let feltMid  = Color(red: 0.07, green: 0.24, blue: 0.16)
    public static let feltHigh = Color(red: 0.12, green: 0.36, blue: 0.24)
    public static let feltEdge = Color(red: 0.02, green: 0.09, blue: 0.06)

    // MARK: - Inks

    public static let inkCream     = Color(red: 0.95, green: 0.92, blue: 0.83)
    public static let inkCreamSoft = Color(red: 0.95, green: 0.92, blue: 0.83).opacity(0.65)
    public static let inkCreamDim  = Color(red: 0.95, green: 0.92, blue: 0.83).opacity(0.42)

    // MARK: - Accents

    public static let gold       = Color(red: 0.83, green: 0.67, blue: 0.34)
    public static let goldBright = Color(red: 0.96, green: 0.82, blue: 0.46)
    public static let wine       = Color(red: 0.62, green: 0.13, blue: 0.16)

    // MARK: - Background

    public static let feltGradient = LinearGradient(
        colors: [feltHigh, feltMid, feltDeep],
        startPoint: .topLeading,
        endPoint: .bottom
    )

    // MARK: - Surfaces
    //
    // Single source of truth for "how does a chip on the felt look". Every
    // chip — opponent seat, phase pill, action bar, overflow menu — uses
    // one of these tokens so the screen reads as one consistent material
    // instead of three competing styles.

    public enum Surface: Equatable {
        /// A quiet seat on the felt — opponents who aren't acting.
        case seat
        /// The seat that's currently acting; gold ring, slightly warmer fill.
        case seatActive
        /// A floating chip (phase, viewer, overflow). Smaller, lower contrast.
        case chip
        /// The deal-summary card / inline modal surface. Slightly heavier.
        case card
    }

    /// Base fill for a surface. Layered over the felt — never pure black.
    public static func surfaceFill(_ surface: Surface) -> Color {
        switch surface {
        case .seat:       return Color.black.opacity(0.18)
        case .seatActive: return Color.black.opacity(0.26)
        case .chip:       return Color.black.opacity(0.22)
        case .card:       return Color.black.opacity(0.30)
        }
    }

    /// Hairline border. Active seats get a real gold ring; quiet surfaces
    /// get a barely-there cream stroke that just defines the edge.
    public static func surfaceBorder(_ surface: Surface) -> Color {
        switch surface {
        case .seat:       return inkCream.opacity(0.06)
        case .seatActive: return goldBright.opacity(0.55)
        case .chip:       return inkCream.opacity(0.08)
        case .card:       return gold.opacity(0.30)
        }
    }

    /// Border thickness in points.
    public static func surfaceStroke(_ surface: Surface) -> CGFloat {
        switch surface {
        case .seatActive: return 1
        default:          return 0.5
        }
    }

    // MARK: - Radius scale
    //
    // Three steps. Don't introduce new ones — pick the closest.

    public enum Radius {
        /// Buttons, badges, tight chips. Capsule-ish.
        public static let pill: CGFloat = 999
        /// Small inline tiles (phase pill, trick tally cell).
        public static let xs: CGFloat = 10
        /// Standard chips (seats, action bar, hand rail).
        public static let sm: CGFloat = 14
        /// Larger surfaces (deal summary card).
        public static let md: CGFloat = 20
    }
}

// MARK: - Surface modifier

extension View {
    /// Apply a `TableTheme.Surface` style: layered fill + hairline border at
    /// the chosen corner radius. Replaces ad-hoc `RoundedRectangle.fill`
    /// stacks scattered through the views.
    public func feltSurface(
        _ surface: TableTheme.Surface,
        radius: CGFloat = TableTheme.Radius.sm
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(TableTheme.surfaceFill(surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    TableTheme.surfaceBorder(surface),
                    lineWidth: TableTheme.surfaceStroke(surface)
                )
        )
    }

    /// Full-screen felt + soft vignette. Use as the screen background so the
    /// felt extends behind every UI layer including the safe areas.
    public func feltBackground() -> some View {
        background {
            ZStack {
                TableTheme.feltGradient
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.32)],
                    center: .center,
                    startRadius: 140,
                    endRadius: 720
                )
            }
            .ignoresSafeArea()
        }
    }

    /// Translucent darker-felt band — used for the action bar so it reads
    /// as embroidered onto the felt rather than as system chrome.
    public func feltBand() -> some View {
        background(
            LinearGradient(
                colors: [Color.black.opacity(0.24), Color.black.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.14))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Buttons

/// Pill button style for actions on the felt. Three emphases:
/// - `.primary`   — solid gold pill, used for the single CTA per phase.
/// - `.secondary` — dark-felt pill with cream label, used for choice rows.
/// - `.dim`       — quiet variant for "pass" and disabled-feeling actions.
///
/// Flat fills, hairline borders, no drop shadows. Press state is a
/// scale + brightness change, not a shadow softening.
public struct FeltButtonStyle: ButtonStyle {
    public enum Emphasis { case primary, secondary, dim }

    public var emphasis: Emphasis
    public var tint: Color?

    public init(emphasis: Emphasis = .primary, tint: Color? = nil) {
        self.emphasis = emphasis
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(background(pressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(border, lineWidth: 0.75)
            )
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch emphasis {
        case .primary:
            (tint ?? TableTheme.goldBright)
                .opacity(pressed ? 0.86 : 1.0)
        case .secondary:
            Color.black.opacity(pressed ? 0.36 : 0.24)
        case .dim:
            Color.black.opacity(pressed ? 0.24 : 0.14)
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .primary:   return TableTheme.feltDeep
        case .secondary: return tint ?? TableTheme.inkCream
        case .dim:       return TableTheme.inkCream.opacity(0.7)
        }
    }

    private var border: Color {
        switch emphasis {
        case .primary:   return TableTheme.feltDeep.opacity(0.40)
        case .secondary: return TableTheme.inkCream.opacity(0.30)
        case .dim:       return TableTheme.inkCream.opacity(0.16)
        }
    }
}

extension ButtonStyle where Self == FeltButtonStyle {
    public static var feltPrimary: FeltButtonStyle { FeltButtonStyle(emphasis: .primary) }
    public static var feltSecondary: FeltButtonStyle { FeltButtonStyle(emphasis: .secondary) }
    public static var feltDim: FeltButtonStyle { FeltButtonStyle(emphasis: .dim) }
}

// MARK: - Suit colors

extension Suit {
    /// Color to render this suit's pip / strain glyph against. Two
    /// palettes: cards sit on a white face (deep red on black); the felt
    /// surface is dark, so reds glow warmer and blacks render as cream so
    /// they stay legible.
    public enum Palette { case cardFace, felt }

    public func color(on palette: Palette) -> Color {
        switch (palette, self) {
        case (.cardFace, .hearts), (.cardFace, .diamonds):
            return Color(red: 0.78, green: 0.10, blue: 0.10)
        case (.cardFace, .spades), (.cardFace, .clubs):
            return .black
        case (.felt, .hearts), (.felt, .diamonds):
            return Color(red: 0.95, green: 0.45, blue: 0.42)
        case (.felt, .spades), (.felt, .clubs):
            return TableTheme.inkCream
        }
    }
}
