import Foundation
import PreferansEngine

@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var engine: PreferansEngine
    @Published public private(set) var lastError: String?
    @Published public private(set) var eventLog: [String] = []
    @Published public var selectedViewer: PlayerID
    public let tableID: UUID = UUID()

    public init(players: [PlayerID], rules: PreferansRules = .sochi, firstDealer: PlayerID? = nil) throws {
        self.engine = try PreferansEngine(players: players, rules: rules, firstDealer: firstDealer)
        self.selectedViewer = players.first ?? PlayerID("player")
    }

    public func send(_ action: PreferansAction) {
        do {
            let authoritativeAction = makeAuthoritative(action)
            let events = try engine.apply(authoritativeAction)
            eventLog.append(contentsOf: events.map { String(describing: $0) })
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func startDeal() {
        send(.startDeal(dealer: engine.nextDealer, deck: Deck.standard32.shuffled()))
    }

    public func projection(revealAll: Bool = true) -> PlayerGameProjection {
        PlayerProjectionBuilder.projection(
            for: selectedViewer,
            tableID: tableID,
            sequence: eventLog.count,
            engine: engine,
            identities: engine.players.map { PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue) },
            policy: revealAll ? .localDebug : .online
        )
    }

    private func makeAuthoritative(_ action: PreferansAction) -> PreferansAction {
        switch action {
        case .startDeal:
            return .startDeal(dealer: engine.nextDealer, deck: Deck.standard32.shuffled())
        default:
            return action
        }
    }
}
