import Foundation

/// Persists the per-seat auth token the worker mints at `/create`/`/join`,
/// keyed by room code, so lobby flows that run without a live transport —
/// abandoning a game from "Your games", fetching the resume snapshot — can
/// still prove seat ownership.
///
/// UserDefaults (not Keychain) is deliberate: a token authorizes actions only
/// on a single room the account already sits at, has no value once the game
/// ends, and the same store level protects the account identity itself.
public enum OnlineSeatCredentialStore {
    private static let storageKey = "online.seatCredentials"
    /// Entries older than this are pruned on every write. Preferans matches
    /// last hours or days; anything this stale is a finished or abandoned room.
    private static let maxAge: TimeInterval = 90 * 24 * 3600

    private struct Entry: Codable {
        var token: String
        var savedAt: Date
    }

    public static func token(for roomCode: String, defaults: UserDefaults = .standard) -> String? {
        load(defaults)[normalize(roomCode)]?.token
    }

    public static func store(_ token: String?, roomCode: String, defaults: UserDefaults = .standard) {
        guard let token, !token.isEmpty else { return }
        var entries = load(defaults)
        entries[normalize(roomCode)] = Entry(token: token, savedAt: .now)
        save(prune(entries), to: defaults)
    }

    /// Drop a room's credential once the game is gone (abandoned or finished).
    public static func remove(roomCode: String, defaults: UserDefaults = .standard) {
        var entries = load(defaults)
        guard entries.removeValue(forKey: normalize(roomCode)) != nil else { return }
        save(entries, to: defaults)
    }

    private static func normalize(_ roomCode: String) -> String {
        roomCode.uppercased()
    }

    private static func prune(_ entries: [String: Entry]) -> [String: Entry] {
        let cutoff = Date.now.addingTimeInterval(-maxAge)
        return entries.filter { $0.value.savedAt > cutoff }
    }

    private static func load(_ defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func save(_ entries: [String: Entry], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
