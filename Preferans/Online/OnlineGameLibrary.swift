import Foundation
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
    public var finalScores: [String: Int]?
}

/// The host-authored progress summary sent to `POST /rooms/{code}/state`.
/// Mirrors the worker's `GameSummary`; the worker stores it verbatim and fans
/// it out to participant libraries.
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

/// Decoded `GET /rooms/{code}/snapshot` payload. `snapshot` is the opaque blob
/// the worker stored — a pre-encoded `PreferansSnapshot` JSON *string* (opaque to
/// the worker, byte-exact across the round-trip). `decodedSnapshot` rehydrates it
/// here. Nil when the room has no resumable snapshot (still in lobby, or already
/// finished/abandoned).
public struct ResumeSnapshotPayload: Decodable, Sendable {
    public var roomCode: String
    public var status: PreferansGameStatus
    public var lastSnapshotSequence: Int
    public var snapshot: String?

    /// The resumable engine state, decoded from the opaque blob.
    public var decodedSnapshot: PreferansSnapshot? {
        guard let snapshot, let data = snapshot.data(using: .utf8) else { return nil }
        return try? PreferansJSONCoder.decoder.decode(PreferansSnapshot.self, from: data)
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
    func fetchMyGames(accountID: String) async throws -> [OnlineGameSummary]
}

/// `OnlineGameDirectory` backed by the Cloudflare worker's `GET /my-games`.
public struct CloudflareGameDirectory: OnlineGameDirectory {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL = AppIdentifiers.roomWorkerBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchMyGames(accountID: String) async throws -> [OnlineGameSummary] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("my-games"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "accountID", value: accountID)]
        guard let url = components?.url else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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

    public init(directory: OnlineGameDirectory = CloudflareGameDirectory()) {
        self.directory = directory
    }

    public var isEmpty: Bool { inProgress.isEmpty && finished.isEmpty }

    /// Reload the list for `accountID`. A nil/empty account (a fresh install
    /// that never played online) clears the list without a network call.
    public func refresh(accountID: String?) async {
        guard let accountID, !accountID.isEmpty else {
            inProgress = []
            finished = []
            loadError = nil
            hasLoaded = true
            return
        }
        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let games = try await directory.fetchMyGames(accountID: accountID)
            // Most-recent-first order arrives from the worker; preserve it.
            inProgress = games.filter(\.isInProgress)
            finished = games.filter { $0.status == .finished }
            // `abandoned` games are intentionally surfaced nowhere.
        } catch {
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
