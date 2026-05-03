import Foundation

public enum AppIdentifiers {
    /// Replace this with the iCloud container you create in Signing & Capabilities.
    public static let cloudKitContainer = "iCloud.com.example.preferans"

    /// Add this ID in a .gamekit bundle / App Store Connect if you use Game Center Activities.
    public static let gameCenterActivityID = "com.example.preferans.activity.table"

    public static let cloudSchemaVersion = 1
    public static let gameWireSchemaVersion = 1
}

/// UserDefaults keys for settings persisted across launches. Centralised
/// so a typo can't silently bind a toggle to a key nothing reads.
public enum SettingsKeys {
    /// Admin/debug toggle — when on, every seat's hand is rendered face-up
    /// in the projection (handy for hot-seat review or screenshot recipes,
    /// not appropriate for online play).
    public static let revealAllHands = "settings.revealAllHands"

    /// Preferred UI language code (BCP-47). When set, written into
    /// `AppleLanguages` at app start so Foundation/SwiftUI pick the matching
    /// strings catalog. Defaults to `ru` per product requirement.
    public static let appLanguage = "settings.appLanguage"
}

/// Catalog-localized languages the user can pick from in Settings. The
/// raw value is the BCP-47 code that lands in `AppleLanguages`; the
/// `displayName` is rendered in the same language so a user who lands on
/// the wrong default still recognizes their own language.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en
    case uk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        case .uk: return "Українська"
        }
    }

    public static let `default`: AppLanguage = .ru

    /// Resolve the persisted choice (or default) for the current process.
    public static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: SettingsKeys.appLanguage),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return .default
    }

    /// Apply `lang` to `AppleLanguages` so the next bundle lookup picks
    /// the matching catalog. Call this before any view loads (i.e. in
    /// `App.init`). Persistence lives in the `appLanguage` key.
    public static func apply(_ lang: AppLanguage) {
        UserDefaults.standard.set(lang.rawValue, forKey: SettingsKeys.appLanguage)
        UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
    }
}


/// Shared JSON encoder/decoder for every persistence and wire path
/// (CloudKit blobs, GameKit messages). Both use ISO-8601 dates so a record
/// written by one can be read by the other. Each call site treats the
/// instance as immutable after construction; concurrent encode/decode is
/// fine, mutating the strategies after init is not.
public enum PreferansJSONCoder {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
