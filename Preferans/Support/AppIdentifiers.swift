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
