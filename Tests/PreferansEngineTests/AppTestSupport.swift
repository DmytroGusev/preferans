@testable import PreferansApp
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

@MainActor
enum GameViewModelTestDriver {
    @discardableResult
    static func playOutCurrentDeal(
        _ model: GameViewModel,
        policy: EnginePlayPolicy,
        stepLimit: Int = 64
    ) -> Bool {
        var steps = 0
        while case let .playing(state) = model.engine.state, steps < stepLimit {
            let actor = state.currentPlayer
            guard let card = policy.choose(engine: model.engine, actor: actor) else {
                return false
            }
            model.send(.playCard(player: actor, card: card))
            if model.lastError != nil { return false }
            steps += 1
        }
        if case .playing = model.engine.state, steps >= stepLimit {
            return false
        }
        return true
    }
}
