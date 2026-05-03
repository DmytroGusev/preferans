import Foundation

/// Single source of truth for the bot-move pacing constants used by
/// `GameViewModel.botMoveDelay`. Three named values, one place to look:
///
/// - ``interactive``: the production default applied when no UI test
///   flag is set. Slow enough that an observer can read each move on
///   the felt. The lobby's user-chosen Bot speed picker overrides this
///   with values from `BotMoveSpeed` for live `bin/sim` and App Store
///   builds.
///
/// - ``testFast``: the test-flag value applied only when
///   ``UITestFlags.fastBotDelay`` is present. **Never** applied to a
///   manually launched simulator session — `bin/sim` and shipped builds
///   keep the picker speed. Set to a small non-zero duration so SwiftUI
///   gets a render cycle between consecutive bot moves; the centered
///   action banner and the auction-trail pills need at least one tick
///   to land before the next event re-keys them. A literal `.zero`
///   collapses multi-action bot stretches into a single SwiftUI tick
///   and the user-visible UI never updates between them.
///
/// - ``instant``: zero — only used by `BotMoveSpeed.instant`, the
///   "Watch bots" demo path, where the user explicitly opts into having
///   the engine race ahead with no pacing at all.
public enum BotPacing {
    /// Production default — applied when no test flag forces an override.
    public static let interactive: Duration = .milliseconds(500)

    /// Applied **only** when the `-uiTestFastBotDelay` launch flag is
    /// present. Not used by manual sim runs.
    public static let testFast: Duration = .milliseconds(10)

    /// Used by the `Watch bots` demo and the `Instant` picker option.
    public static let instant: Duration = .zero
}
