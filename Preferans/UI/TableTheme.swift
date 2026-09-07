import SwiftUI
import PreferansEngine

/// A theme is presentation state. It never changes a match, a seat, or a rule.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case clubhouse, midnight, aubergine, graphite, parchment, nordic

    public var id: String { rawValue }
    public static let `default`: AppTheme = .clubhouse

    public var name: String {
        switch self {
        case .clubhouse: String(localized: "Clubhouse")
        case .midnight: String(localized: "Midnight")
        case .aubergine: String(localized: "Aubergine")
        case .graphite: String(localized: "Graphite")
        case .parchment: String(localized: "Parchment")
        case .nordic: String(localized: "Nordic")
        }
    }

    public var subtitle: String {
        switch self {
        case .clubhouse: String(localized: "Green felt · warm brass")
        case .midnight: String(localized: "Deep blue · silver light")
        case .aubergine: String(localized: "Plum velvet · rose gold")
        case .graphite: String(localized: "Charcoal · crisp mint")
        case .parchment: String(localized: "Warm paper · printed ink")
        case .nordic: String(localized: "Soft porcelain · forest green")
        }
    }

    public var colorScheme: ColorScheme {
        switch self {
        case .parchment, .nordic: .light
        default: .dark
        }
    }

    public var titleDesign: Font.Design {
        switch self {
        case .clubhouse, .aubergine, .parchment: .serif
        case .nordic: .rounded
        case .midnight, .graphite: .default
        }
    }

    public var motif: String {
        switch self {
        case .clubhouse: "suit.club.fill"
        case .midnight: "moon.stars.fill"
        case .aubergine: "suit.diamond.fill"
        case .graphite: "square.grid.2x2.fill"
        case .parchment: "suit.spade.fill"
        case .nordic: "leaf.fill"
        }
    }

    public static func resolve(_ rawValue: String?) -> AppTheme {
        rawValue.flatMap(AppTheme.init(rawValue:)) ?? .default
    }
}

/// Opaque sRGB swatches keep contrast independent of whatever lies behind a label.
/// Numeric values also make the shipped palettes auditable without rendering.
public struct ThemeSwatch: Equatable, Sendable {
    public let hex: UInt32
    public init(_ hex: UInt32) { self.hex = hex }
    public var color: Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }

    public var luminance: Double {
        func linear(_ channel: UInt32) -> Double {
            let v = Double(channel) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 255)
            + 0.7152 * linear((hex >> 8) & 255)
            + 0.0722 * linear(hex & 255)
    }

    public func contrast(against other: ThemeSwatch) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct TableTheme: Equatable, Sendable {
    public let style: AppTheme
    public let top: ThemeSwatch
    public let mid: ThemeSwatch
    public let base: ThemeSwatch
    public let panelSwatch: ThemeSwatch
    public let primary: ThemeSwatch
    public let secondary: ThemeSwatch
    public let muted: ThemeSwatch
    public let accentSwatch: ThemeSwatch
    public let onAccentSwatch: ThemeSwatch
    public let errorSwatch: ThemeSwatch
    public let warningSwatch: ThemeSwatch
    public let successSwatch: ThemeSwatch
    public let back: ThemeSwatch
    public let backInk: ThemeSwatch

    public init(_ style: AppTheme) {
        self.style = style
        let colors: [UInt32]
        // top, mid, base, panel, primary, secondary, muted, accent, onAccent,
        // error, warning, success, card back, card-back ink.
        switch style {
        case .clubhouse:
            colors = [0x21453D, 0x17372F, 0x102820, 0x112C25,
                      0xF4EFDF, 0xD0D8CC, 0xB0C1B5, 0xE9CD8B, 0x18291D,
                      0xFFAAA2, 0xF5CC8B, 0xA8DEC2, 0x4B1624, 0xE9CD8B]
        case .midnight:
            colors = [0x202F4C, 0x17243D, 0x101B2E, 0x162238,
                      0xEFF4FF, 0xC8D6EA, 0xADBED8, 0xB9D9FF, 0x122540,
                      0xFFAFB5, 0xF3CF98, 0x9AE1C6, 0x233E66, 0xD0E5FF]
        case .aubergine:
            colors = [0x442C40, 0x342132, 0x251A27, 0x2F2030,
                      0xF9EEF4, 0xDDCAD6, 0xC8AFC0, 0xF1C4AF, 0x3B2332,
                      0xFFAFB9, 0xF4D29E, 0xBBDCBF, 0x5A354D, 0xF2D3B8]
        case .graphite:
            colors = [0x282D30, 0x202528, 0x161B1E, 0x202629,
                      0xF3F7F5, 0xCED9D5, 0xAFBFBA, 0xAFF0D2, 0x17382B,
                      0xFFB4AD, 0xF0D69C, 0xAFF0D2, 0x303D39, 0xBCF5DC]
        case .parchment:
            colors = [0xF6EFDF, 0xEEE5D2, 0xE8DEC8, 0xFFF9ED,
                      0x302A23, 0x575044, 0x645C50, 0x805125, 0xFFF9ED,
                      0xA32633, 0x795219, 0x246348, 0x614738, 0xF4DEB9]
        case .nordic:
            colors = [0xF2F6F2, 0xE8EEEA, 0xDEE7E1, 0xFAFCF9,
                      0x22392F, 0x465C50, 0x53685D, 0x2C6552, 0xF7FFF8,
                      0xA1263D, 0x76520C, 0x246348, 0x35574A, 0xD9F2DA]
        }
        top = ThemeSwatch(colors[0]); mid = ThemeSwatch(colors[1])
        base = ThemeSwatch(colors[2]); panelSwatch = ThemeSwatch(colors[3])
        primary = ThemeSwatch(colors[4]); secondary = ThemeSwatch(colors[5])
        muted = ThemeSwatch(colors[6]); accentSwatch = ThemeSwatch(colors[7])
        onAccentSwatch = ThemeSwatch(colors[8]); errorSwatch = ThemeSwatch(colors[9])
        warningSwatch = ThemeSwatch(colors[10]); successSwatch = ThemeSwatch(colors[11])
        back = ThemeSwatch(colors[12]); backInk = ThemeSwatch(colors[13])
    }

    public var backgroundTop: Color { top.color }
    public var backgroundMid: Color { mid.color }
    public var backgroundBase: Color { base.color }
    public var panel: Color { panelSwatch.color }
    public var textPrimary: Color { primary.color }
    public var textSecondary: Color { secondary.color }
    public var textMuted: Color { muted.color }
    public var accent: Color { accentSwatch.color }
    public var accentStrong: Color { accentSwatch.color }
    public var onAccent: Color { onAccentSwatch.color }
    public var error: Color { errorSwatch.color }
    public var warning: Color { warningSwatch.color }
    public var success: Color { successSwatch.color }
    public var cardBack: Color { back.color }
    public var cardBackInk: Color { backInk.color }
    public var shade: Color { style.colorScheme == .light ? .white : .black }
    public var edge: Color { style.colorScheme == .light ? panel : backgroundBase }
    public var controlRadius: CGFloat {
        switch style {
        case .graphite: 10
        case .midnight, .parchment: 14
        case .clubhouse, .aubergine, .nordic: 22
        }
    }
    public var gradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMid, backgroundBase],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public enum Surface: Equatable { case seat, seatActive, chip, card }
    public func surfaceFill(_ surface: Surface) -> Color {
        switch surface {
        case .seat: panel.opacity(0.72)
        case .seatActive: panel
        case .chip: panel.opacity(0.80)
        case .card: panel
        }
    }
    public func surfaceBorder(_ surface: Surface) -> Color {
        switch surface {
        case .seatActive: accent.opacity(0.65)
        case .card: accent.opacity(0.28)
        case .seat, .chip: textPrimary.opacity(0.12)
        }
    }
    public static func surfaceStroke(_ surface: Surface) -> CGFloat {
        surface == .seatActive ? 1 : 0.5
    }
    public enum Radius {
        public static let pill: CGFloat = 999
        public static let xs: CGFloat = 10
        public static let sm: CGFloat = 14
        public static let md: CGFloat = 20
    }
}

private struct TableThemeKey: EnvironmentKey {
    static let defaultValue = TableTheme(.default)
}

extension EnvironmentValues {
    public var tableTheme: TableTheme {
        get { self[TableThemeKey.self] }
        set { self[TableThemeKey.self] = newValue }
    }
}

/// Keeping identity stable is essential: changing a theme must not recreate the
/// lobby's game model or the online coordinator stored below this modifier.
private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(SettingsKeys.appTheme) private var rawTheme = AppTheme.default.rawValue
    func body(content: Content) -> some View {
        let theme = TableTheme(AppTheme.resolve(rawTheme))
        content
            .environment(\.tableTheme, theme)
            .preferredColorScheme(theme.style.colorScheme)
            .tint(theme.accent)
    }
}

private struct FeltSurfaceModifier: ViewModifier {
    @Environment(\.tableTheme) private var theme
    let surface: TableTheme.Surface
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(theme.surfaceFill(surface), in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.surfaceBorder(surface), lineWidth: TableTheme.surfaceStroke(surface))
            }
    }
}

/// Very quiet linework gives each material its own character. It is decorative,
/// stationary, and never competes with the ranks or suits on the cards.
struct ThemeBackdrop: View {
    @Environment(\.tableTheme) private var theme
    var body: some View {
        theme.gradient.overlay {
            Canvas { context, size in
                var lines = Path()
                let step: CGFloat = theme.style == .graphite ? 48 : 36
                switch theme.style {
                case .clubhouse, .parchment:
                    for y in stride(from: CGFloat(0), to: size.height, by: step) {
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                case .midnight, .graphite:
                    for x in stride(from: CGFloat(0), to: size.width, by: step) {
                        for y in stride(from: CGFloat(0), to: size.height, by: step) {
                            lines.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                        }
                    }
                case .aubergine, .nordic:
                    for inset in stride(from: CGFloat(0), to: max(size.width, size.height), by: step * 2) {
                        lines.addEllipse(in: CGRect(x: -inset, y: -inset,
                                                   width: size.width + 2 * inset,
                                                   height: size.width + 2 * inset))
                    }
                }
                context.stroke(lines, with: .color(theme.accent.opacity(0.045)), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct FeltBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { ThemeBackdrop().ignoresSafeArea() }
    }
}

private struct FeltBandModifier: ViewModifier {
    @Environment(\.tableTheme) private var theme
    func body(content: Content) -> some View {
        content
            .background(theme.panel)
            .overlay(alignment: .top) { Rectangle().fill(theme.accent.opacity(0.18)).frame(height: 0.5) }
    }
}

private struct ThemeNavigationModifier: ViewModifier {
    @Environment(\.tableTheme) private var theme
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.style.colorScheme, for: .navigationBar)
        #else
        content
        #endif
    }
}

extension View {
    public func appAppearance() -> some View { modifier(AppAppearanceModifier()) }
    public func feltSurface(_ surface: TableTheme.Surface, radius: CGFloat = TableTheme.Radius.sm) -> some View {
        modifier(FeltSurfaceModifier(surface: surface, radius: radius))
    }
    public func feltBackground() -> some View { modifier(FeltBackgroundModifier()) }
    public func feltBand() -> some View { modifier(FeltBandModifier()) }
    func themeNavigationChrome() -> some View { modifier(ThemeNavigationModifier()) }
}

public struct FeltButtonStyle: ButtonStyle {
    @Environment(\.tableTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public enum Emphasis { case primary, secondary, dim }
    public var emphasis: Emphasis
    public var tint: Color?
    public init(emphasis: Emphasis = .primary, tint: Color? = nil) {
        self.emphasis = emphasis
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.controlRadius, style: .continuous)
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1), in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 0.75))
            .opacity(isEnabled ? 1 : 0.46)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var background: Color {
        switch emphasis {
        case .primary: tint ?? theme.accentStrong
        case .secondary, .dim: theme.panel
        }
    }
    private var foreground: Color {
        switch emphasis {
        case .primary: theme.onAccent
        case .secondary: tint ?? theme.textPrimary
        case .dim: theme.textSecondary
        }
    }
    private var border: Color {
        switch emphasis {
        case .primary: theme.accent
        case .secondary: theme.textPrimary.opacity(0.28)
        case .dim: theme.textMuted.opacity(0.24)
        }
    }
}

extension ButtonStyle where Self == FeltButtonStyle {
    public static var feltPrimary: FeltButtonStyle { FeltButtonStyle(emphasis: .primary) }
    public static var feltSecondary: FeltButtonStyle { FeltButtonStyle(emphasis: .secondary) }
    public static var feltDim: FeltButtonStyle { FeltButtonStyle(emphasis: .dim) }
}

extension Suit {
    public enum Palette { case cardFace, felt }
    public func color(on palette: Palette, theme: TableTheme = TableTheme(.default)) -> Color {
        switch (palette, self) {
        case (.cardFace, .hearts), (.cardFace, .diamonds): ThemeSwatch(0xBD1722).color
        case (.cardFace, .spades), (.cardFace, .clubs): ThemeSwatch(0x172022).color
        case (.felt, .hearts), (.felt, .diamonds): theme.error
        case (.felt, .spades), (.felt, .clubs): theme.textPrimary
        }
    }
}
