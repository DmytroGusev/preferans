import SwiftUI

/// Visual language for the card table. Everything that lives on the felt —
/// status bars, opponent seats, action buttons — pulls its colors from here
/// so the table reads as one continuous environment rather than a green
/// rectangle floating on a system-grey background.
public enum TableTheme {
    // Felt
    public static let feltDeep = Color(red: 0.04, green: 0.16, blue: 0.10)
    public static let feltMid  = Color(red: 0.07, green: 0.24, blue: 0.16)
    public static let feltHigh = Color(red: 0.12, green: 0.36, blue: 0.24)
    public static let feltEdge = Color(red: 0.02, green: 0.09, blue: 0.06)

    // Inks on felt — cream, never pure white, so cards stay the brightest thing
    public static let inkCream     = Color(red: 0.95, green: 0.92, blue: 0.83)
    public static let inkCreamSoft = Color(red: 0.95, green: 0.92, blue: 0.83).opacity(0.65)
    public static let inkCreamDim  = Color(red: 0.95, green: 0.92, blue: 0.83).opacity(0.42)

    // Accents
    public static let gold       = Color(red: 0.83, green: 0.67, blue: 0.34)
    public static let goldBright = Color(red: 0.96, green: 0.82, blue: 0.46)
    public static let wine       = Color(red: 0.62, green: 0.13, blue: 0.16)

    public static let feltGradient = LinearGradient(
        colors: [feltHigh, feltMid, feltDeep],
        startPoint: .topLeading,
        endPoint: .bottom
    )
}

extension View {
    /// Full-screen felt + soft vignette. Use as the screen background so the
    /// felt extends behind every UI layer including the safe areas.
    public func feltBackground() -> some View {
        self.background {
            ZStack {
                TableTheme.feltGradient
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.40)],
                    center: .center,
                    startRadius: 120,
                    endRadius: 700
                )
            }
            .ignoresSafeArea()
        }
    }

    /// Translucent darker-felt band — used for the phase bar and action bar
    /// so they read as embroidered onto the felt rather than as system chrome.
    public func feltBand() -> some View {
        self.background(
            LinearGradient(
                colors: [Color.black.opacity(0.28), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.18))
                .frame(height: 0.5)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.18))
                .frame(height: 0.5)
        }
    }
}

/// Pill button style for actions on the felt. Three emphases:
/// - `.primary`   — gold pill, used for the single CTA per phase
/// - `.secondary` — cream-outline dark-felt pill, used for choice rows
/// - `.dim`       — muted secondary, used for "pass" and disabled-feeling actions
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
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(background(pressed: configuration.isPressed))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(border, lineWidth: 1)
            )
            .foregroundStyle(foreground)
            .shadow(color: .black.opacity(emphasis == .primary ? 0.30 : 0.18),
                    radius: emphasis == .primary ? 4 : 2, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch emphasis {
        case .primary:
            LinearGradient(
                colors: [
                    (tint ?? TableTheme.goldBright).opacity(pressed ? 0.85 : 1),
                    (tint ?? TableTheme.gold).opacity(pressed ? 0.80 : 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .secondary:
            Color.black.opacity(pressed ? 0.42 : 0.30)
        case .dim:
            Color.black.opacity(pressed ? 0.30 : 0.18)
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
        case .primary:   return TableTheme.feltDeep.opacity(0.55)
        case .secondary: return TableTheme.inkCream.opacity(0.45)
        case .dim:       return TableTheme.inkCream.opacity(0.22)
        }
    }
}

extension ButtonStyle where Self == FeltButtonStyle {
    public static var feltPrimary: FeltButtonStyle { FeltButtonStyle(emphasis: .primary) }
    public static var feltSecondary: FeltButtonStyle { FeltButtonStyle(emphasis: .secondary) }
    public static var feltDim: FeltButtonStyle { FeltButtonStyle(emphasis: .dim) }
}
