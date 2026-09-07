import XCTest
@testable import PreferansApp

final class ThemePaletteTests: XCTestCase {
    func testEveryThemeKeepsSmallTextReadableOnAllTableSurfaces() {
        for style in AppTheme.allCases {
            let theme = TableTheme(style)
            for surface in [theme.top, theme.mid, theme.base, theme.panelSwatch] {
                for ink in [theme.primary, theme.secondary, theme.muted,
                            theme.accentSwatch, theme.errorSwatch, theme.warningSwatch, theme.successSwatch] {
                    XCTAssertGreaterThanOrEqual(ink.contrast(against: surface), 4.5,
                        "\(style.rawValue): \(String(ink.hex, radix: 16)) on \(String(surface.hex, radix: 16))")
                }
            }
            XCTAssertGreaterThanOrEqual(theme.onAccentSwatch.contrast(against: theme.accentSwatch), 4.5,
                                        "\(style.rawValue) primary button")
            XCTAssertGreaterThanOrEqual(theme.backInk.contrast(against: theme.back), 4.5,
                                        "\(style.rawValue) card back")
        }
    }

    func testUnknownSavedThemeFallsBackWithoutChangingTheSavedValue() {
        XCTAssertEqual(AppTheme.resolve("a-theme-from-a-future-version"), .default)
        XCTAssertEqual(AppTheme.resolve(nil), .default)
    }
}
