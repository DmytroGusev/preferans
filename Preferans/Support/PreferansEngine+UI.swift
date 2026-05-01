import Foundation
import PreferansEngine

extension ScoreSheet {
    func pool(for player: PlayerID) -> Int { pool[player] ?? 0 }
    func mountain(for player: PlayerID) -> Int { mountain[player] ?? 0 }
    func balance(for player: PlayerID) -> Double { normalizedBalances()[player] ?? 0 }
}

extension Card {
    var uiText: String { description }
}

extension GameContract {
    static func declarationOptions(atLeast finalBid: ContractBid) -> [GameContract] {
        guard case .game = finalBid else { return [] }
        return GameContract.allStandard.filter { ContractBid.game($0) >= finalBid }
    }
}
