import Foundation
import PreferansEngine

public enum OnlineTableVisibility: String, CaseIterable, Identifiable, Sendable {
    case publicTable = "public"
    case privateTable = "private"
    public var id: String { rawValue }
}

public enum OnlineLobbyIntent: String, CaseIterable, Identifiable {
    case findTable, createTable
    public var id: String { rawValue }
}

public struct OnlineTableSettings: Codable, Sendable, Equatable {
    public var variant: String?
    public var poolTarget: Int
    public var poolClosure: String

    public func displayedPoolTarget(playerCount: Int) -> Int {
        poolClosure == "tableTotal" ? poolTarget : poolTarget / max(1, playerCount)
    }
}

public struct PublicOnlineTable: Decodable, Sendable, Equatable, Identifiable {
    public struct Player: Decodable, Sendable, Equatable {
        public var displayName: String
        public var ready: Bool
        public var connected: Bool
    }
    public var roomCode: String
    public var variant: String
    public var poolTarget: Int
    public var poolClosure: String
    public var maxPlayers: Int
    public var players: [Player]
    public var openSeats: Int
    public var status: PreferansGameStatus
    public var dealNumber: Int?
    public var createdAt: String
    public var id: String { roomCode }
    public var canJoin: Bool { status == .lobby && openSeats > 0 }
    public var settings: OnlineTableSettings {
        OnlineTableSettings(variant: variant, poolTarget: poolTarget, poolClosure: poolClosure)
    }
}

public struct PublicTablePage: Decodable, Sendable {
    public var tables: [PublicOnlineTable]
    public var nextOffset: Int?
}

public protocol PublicTableServing: Sendable {
    func fetchTables(sessionToken: String, offset: Int) async throws -> PublicTablePage
}

public struct CloudflarePublicTableDirectory: PublicTableServing {
    public var baseURL: URL
    public var session: URLSession
    public init(baseURL: URL = AppIdentifiers.roomWorkerBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    public func fetchTables(sessionToken: String, offset: Int = 0) async throws -> PublicTablePage {
        var components = URLComponents(url: baseURL.appendingPathComponent("v2/public-tables"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "offset", value: String(offset))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudflareRoomTransportError.invalidHTTPResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 || http.statusCode == 503 {
                throw CloudflareRoomTransportError.serverError(String(localized: "Public tables are not available on this server yet. You can still invite friends with a room code."))
            }
            let error = try? JSONDecoder().decode(DirectoryError.self, from: data)
            throw CloudflareRoomTransportError.serverError(error?.error ?? "Could not load public tables. Please try again.")
        }
        return try PreferansJSONCoder.decoder.decode(PublicTablePage.self, from: data)
    }
    private struct DirectoryError: Decodable { var error: String }
}

@MainActor
public final class PublicTableLobby: ObservableObject {
    @Published public private(set) var tables: [PublicOnlineTable] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorText: String?
    @Published public private(set) var nextOffset: Int?
    @Published public private(set) var hasLoaded = false
    private let directory: any PublicTableServing
    private var generation = 0
    public init(directory: any PublicTableServing = CloudflarePublicTableDirectory()) { self.directory = directory }

    public func refresh(sessionToken: String?, loadMore: Bool = false) async {
        generation &+= 1
        let current = generation
        guard let sessionToken, !sessionToken.isEmpty else {
            tables = []; nextOffset = nil; isLoading = false; errorText = nil; hasLoaded = false
            return
        }
        let offset = loadMore ? (nextOffset ?? 0) : 0
        isLoading = true
        errorText = nil
        defer { if generation == current { isLoading = false; hasLoaded = true } }
        do {
            let page = try await directory.fetchTables(sessionToken: sessionToken, offset: offset)
            guard generation == current else { return }
            if loadMore {
                let incoming = Set(page.tables.map(\.id))
                tables = tables.filter { !incoming.contains($0.id) } + page.tables
            } else { tables = page.tables }
            nextOffset = page.nextOffset
        } catch {
            guard generation == current else { return }
            if !loadMore { tables = []; nextOffset = nil }
            errorText = error.localizedDescription
        }
    }
}
import PreferansEngine

/// One row in the lobby's "Your games" list — the client mirror of the worker's
/// `GameSummaryEntry`. Decoded straight from `GET /my-games`; never built locally.
/// Carries everything a Continue/History row needs plus the `roomCode` a resume
/// rejoins through.
public struct OnlineGameSummary: Codable, Sendable, Identifiable, Equatable {
    public var roomCode: String
    public var hostPlayerID: PlayerID
    public var status: PreferansGameStatus
    public var maxPlayers: Int
    public var peers: [OnlinePeer]
    /// The seat this device's account holds at the table.
    public var youSeat: PlayerID
    public var variant: String?
    public var phase: String?
    public var dealNumber: Int?
    public var lastSequence: Int
    /// Present once `status == .finished`.
    public var result: OnlineGameResult?
    public var createdAt: String
    public var updatedAt: String

    public var id: String { roomCode }
}

/// Worker-readable match result kept for finished games (mirrors the worker's
/// `GameResultSummary`). Seats are `PlayerID.rawValue` keys.
public struct OnlineGameResult: Codable, Sendable, Equatable {
    public var winner: PlayerID?
    /// Authoritative normalized whist balance per seat. These are the same
    /// zero-sum values used to order the engine's final standings.
    public var finalBalances: [String: Double]?
}

/// Public-safe progress metadata projected by the authoritative engine and
/// fanned out to participant libraries.
public struct OnlineStateSummary: Codable, Sendable, Equatable {
    public var variant: String?
    public var lastSequence: Int
    public var phase: String?
    public var dealNumber: Int?
    public var result: OnlineGameResult?

    public init(
        variant: String? = nil,
        lastSequence: Int,
        phase: String? = nil,
        dealNumber: Int? = nil,
        result: OnlineGameResult? = nil
    ) {
        self.variant = variant
        self.lastSequence = lastSequence
        self.phase = phase
        self.dealNumber = dealNumber
        self.result = result
    }
}

public extension OnlineGameSummary {
    /// Other humans at the table (you excluded), in seat order — for the row's
    /// "with Ann, Bob" line. Bots and still-open seats are dropped.
    var opponents: [OnlinePeer] {
        peers.filter { $0.playerID != youSeat && !$0.isPendingSeat && !$0.isBotSeat }
    }

    /// Count of seats filled by a host-driven bot, for a "+1 bot" hint.
    var botCount: Int { peers.filter(\.isBotSeat).count }

    /// Display name of the winning seat, when a finished game named one.
    var winnerName: String? {
        guard let winner = result?.winner else { return nil }
        return peers.first { $0.playerID == winner }?.displayName
    }

    /// True for games the lobby surfaces under "Continue" (resumable).
    var isInProgress: Bool { status == .lobby || status == .playing }
}

/// Account-scoped read of a player's games. Abstracted so the lobby's
/// `OnlineGameLibrary` can be unit-tested against a stub without a worker.
public protocol OnlineGameDirectory: Sendable {
    func fetchMyGames(sessionToken: String) async throws -> [OnlineGameSummary]
}

/// `OnlineGameDirectory` backed by authenticated `GET /v2/my-games`.
public struct CloudflareGameDirectory: OnlineGameDirectory {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL = AppIdentifiers.roomWorkerBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchMyGames(sessionToken: String) async throws -> [OnlineGameSummary] {
        let url = baseURL.appendingPathComponent("v2").appendingPathComponent("my-games")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let serverError = try? PreferansJSONCoder.decoder.decode(MyGamesError.self, from: data) {
                throw CloudflareRoomTransportError.serverError(serverError.error)
            }
            throw CloudflareRoomTransportError.serverError("Room server returned HTTP \(http.statusCode).")
        }
        return try PreferansJSONCoder.decoder.decode(MyGamesResponse.self, from: data).games
    }

    private struct MyGamesResponse: Decodable {
        var games: [OnlineGameSummary]
    }

    private struct MyGamesError: Decodable {
        var error: String
    }
}

/// Lobby-facing view model for a player's online games. The client counterpart
/// to the worker's per-account `PlayerLibrary`: it reads the directory and
/// splits the result into Continue (in-progress) and History (finished). Resume
/// and abandon are owned by `LobbyViewModel`, which holds the session-creation
/// machinery; this type stays a pure read/refresh surface.
@MainActor
public final class OnlineGameLibrary: ObservableObject {
    @Published public private(set) var inProgress: [OnlineGameSummary] = []
    @Published public private(set) var finished: [OnlineGameSummary] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?
    /// False until the first refresh resolves, so the UI can distinguish
    /// "haven't looked yet" from "looked and found nothing".
    @Published public private(set) var hasLoaded = false

    private let directory: OnlineGameDirectory
    /// Monotonically identifies the refresh whose result is allowed to update
    /// published state. Directory requests are not assumed to support
    /// cancellation, so an older completion must be harmless even when it
    /// arrives after the account or a manual refresh has changed.
    private var refreshGeneration = 0

    public init(directory: OnlineGameDirectory = CloudflareGameDirectory()) {
        self.directory = directory
    }

    public var isEmpty: Bool { inProgress.isEmpty && finished.isEmpty }

    /// Reload the authenticated account's list. A nil/empty session (a fresh
    /// install or signed-out player) clears the list without a network call.
    public func refresh(sessionToken: String?) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        guard let sessionToken, !sessionToken.isEmpty else {
            inProgress = []
            finished = []
            isLoading = false
            loadError = nil
            hasLoaded = true
            return
        }
        isLoading = true
        loadError = nil
        defer {
            if generation == refreshGeneration {
                isLoading = false
                hasLoaded = true
            }
        }
        do {
            let games = try await directory.fetchMyGames(sessionToken: sessionToken)
            guard generation == refreshGeneration else { return }
            // Most-recent-first order arrives from the worker; preserve it.
            inProgress = games.filter(\.isInProgress)
            finished = games.filter { $0.status == .finished }
            // `abandoned` games are intentionally surfaced nowhere.
        } catch {
            guard generation == refreshGeneration else { return }
            loadError = error.localizedDescription
        }
    }

    /// Drop a room from the local lists immediately (optimistic), e.g. right
    /// after the player abandons it, so the row disappears without a round-trip.
    public func removeLocally(roomCode: String) {
        inProgress.removeAll { $0.roomCode == roomCode }
        finished.removeAll { $0.roomCode == roomCode }
    }
}
