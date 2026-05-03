import Foundation

public enum ScoreFormatting {
    public static func balance(_ value: Double) -> String {
        let rounded = abs(value) < 0.05 ? 0 : value
        let formatted = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return rounded > 0 ? "+\(formatted)" : formatted
    }
}
