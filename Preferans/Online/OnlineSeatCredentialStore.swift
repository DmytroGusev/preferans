import Foundation
import Security

/// The v2 account bearer token grants access to every game owned by the
/// account, so it is kept in Keychain rather than UserDefaults. The service and
/// account names are versioned: old trust-based identities can never be loaded
/// accidentally after the clean break.
public enum OnlineAccountSessionStore {
    private static let service = "com.mixandmatch.preferans.online-account.v2"
    private static let account = "active-session"

    public static func token() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    @discardableResult
    public static func store(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8), !data.isEmpty else { return false }
        remove()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func remove() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Main-actor boundary around account-session persistence. The app uses the
/// Keychain-backed implementation, while tests can supply an isolated store
/// without depending on the test runner's Keychain entitlements.
@MainActor
public protocol OnlineAccountSessionStoring {
    func token() -> String?
    @discardableResult func store(_ token: String) -> Bool
    func remove()
}

public struct KeychainOnlineAccountSessionStore: OnlineAccountSessionStoring {
    public init() {}

    public func token() -> String? {
        OnlineAccountSessionStore.token()
    }

    @discardableResult
    public func store(_ token: String) -> Bool {
        OnlineAccountSessionStore.store(token)
    }

    public func remove() {
        OnlineAccountSessionStore.remove()
    }
}

/// Persists the per-seat auth token the worker mints at `/create`/`/join`,
/// keyed by room code, so lobby flows that run without a live transport —
/// abandoning a game from "Your games", fetching the resume snapshot — can
/// still prove seat ownership.
///
/// A seat token is scoped to one short-lived room, unlike the account bearer
/// token above, so UserDefaults remains an appropriate recoverable cache.
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

    public static func removeAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
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
