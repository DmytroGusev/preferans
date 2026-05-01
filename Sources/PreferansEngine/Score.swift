import Foundation

public struct ScoreDelta: Equatable, Codable, Sendable {
    public private(set) var pool: [PlayerID: Int]
    public private(set) var mountain: [PlayerID: Int]
    public private(set) var whists: [PlayerID: [PlayerID: Int]]

    public init(players: [PlayerID]) {
        self.pool = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        self.mountain = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        self.whists = Dictionary(uniqueKeysWithValues: players.map { ($0, [:]) })
    }

    public mutating func addPool(_ points: Int, to player: PlayerID) {
        guard points != 0 else { return }
        pool[player, default: 0] += points
    }

    public mutating func addMountain(_ points: Int, to player: PlayerID) {
        guard points != 0 else { return }
        mountain[player, default: 0] += points
    }

    public mutating func addWhists(_ points: Int, writer: PlayerID, on target: PlayerID) {
        guard points != 0, writer != target else { return }
        whists[writer, default: [:]][target, default: 0] += points
    }

    public var isZero: Bool {
        pool.values.allSatisfy { $0 == 0 }
            && mountain.values.allSatisfy { $0 == 0 }
            && whists.values.allSatisfy { $0.values.allSatisfy { $0 == 0 } }
    }
}

public struct ScoreSheet: Equatable, Codable, Sendable {
    public let players: [PlayerID]
    public private(set) var pool: [PlayerID: Int]
    public private(set) var mountain: [PlayerID: Int]
    public private(set) var whists: [PlayerID: [PlayerID: Int]]

    public init(players: [PlayerID]) {
        self.players = players
        self.pool = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        self.mountain = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        self.whists = Dictionary(uniqueKeysWithValues: players.map { ($0, [:]) })
    }

    public mutating func apply(_ delta: ScoreDelta) {
        for (player, points) in delta.pool where points != 0 {
            pool[player, default: 0] += points
        }
        for (player, points) in delta.mountain where points != 0 {
            mountain[player, default: 0] += points
        }
        for (writer, entries) in delta.whists {
            for (target, points) in entries where points != 0 {
                whists[writer, default: [:]][target, default: 0] += points
            }
        }
    }

    public func whistsWritten(by writer: PlayerID, on target: PlayerID) -> Int {
        whists[writer]?[target] ?? 0
    }

    public func normalizedBalances(
        poolPointValue: Double = 10,
        mountainPointValue: Double = 10
    ) -> [PlayerID: Double] {
        var balances = Dictionary(uniqueKeysWithValues: players.map { ($0, 0.0) })

        for player in players {
            balances[player, default: 0] += Double(pool[player] ?? 0) * poolPointValue
            balances[player, default: 0] -= Double(mountain[player] ?? 0) * mountainPointValue
        }

        for (writer, entries) in whists {
            for (target, points) in entries {
                balances[writer, default: 0] += Double(points)
                balances[target, default: 0] -= Double(points)
            }
        }

        let average = balances.values.reduce(0, +) / Double(max(1, balances.count))
        return balances.mapValues { $0 - average }
    }
}
