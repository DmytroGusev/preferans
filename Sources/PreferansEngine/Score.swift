import Foundation

public struct ScoreDelta: Equatable, Codable, Sendable {
    public private(set) var pool: [PlayerID: Int]
    public private(set) var mountain: [PlayerID: Int]
    public private(set) var whists: [PlayerID: [PlayerID: Int]]

    public init(players: [PlayerID]) {
        self.pool = players.dictionary(filledWith: 0)
        self.mountain = players.dictionary(filledWith: 0)
        self.whists = players.dictionary(filledWith: [:])
    }

    init(uncheckedPlayers _: [PlayerID], pool: [PlayerID: Int], mountain: [PlayerID: Int], whists: [PlayerID: [PlayerID: Int]]) {
        self.pool = pool
        self.mountain = mountain
        self.whists = whists
    }

    public mutating func addPool(_ points: Int, to player: PlayerID) {
        precondition(hasKnownPlayer(player), "ScoreDelta pool target \(player) is not in the score player set.")
        guard points != 0 else { return }
        pool[player]! += points
    }

    public mutating func addMountain(_ points: Int, to player: PlayerID) {
        precondition(hasKnownPlayer(player), "ScoreDelta mountain target \(player) is not in the score player set.")
        guard points != 0 else { return }
        mountain[player]! += points
    }

    public mutating func addWhists(_ points: Int, writer: PlayerID, on target: PlayerID) {
        precondition(hasKnownPlayer(writer), "ScoreDelta whist writer \(writer) is not in the score player set.")
        precondition(hasKnownPlayer(target), "ScoreDelta whist target \(target) is not in the score player set.")
        guard points != 0, writer != target else { return }
        whists[writer, default: [:]][target, default: 0] += points
    }

    public var isZero: Bool {
        pool.values.allSatisfy { $0 == 0 }
            && mountain.values.allSatisfy { $0 == 0 }
            && whists.values.allSatisfy { $0.values.allSatisfy { $0 == 0 } }
    }

    public func validate(players expectedPlayers: [PlayerID]) throws {
        try Self.require(Set(expectedPlayers).count == expectedPlayers.count, "scoreDelta players must be unique")
        let expected = Set(expectedPlayers)
        try Self.require(Set(pool.keys) == expected, "scoreDelta pool keys must match players")
        try Self.require(Set(mountain.keys) == expected, "scoreDelta mountain keys must match players")
        try Self.require(Set(whists.keys) == expected, "scoreDelta whist writer keys must match players")
        for (writer, entries) in whists {
            try Self.require(expected.contains(writer), "scoreDelta whist writer \(writer) is not in players")
            try Self.require(Set(entries.keys).isSubset(of: expected), "scoreDelta whist targets for \(writer) contain unknown players")
            try Self.require(entries[writer] == nil || entries[writer] == 0, "scoreDelta cannot write whists against self")
        }
    }

    private func hasKnownPlayer(_ player: PlayerID) -> Bool {
        pool.keys.contains(player)
            && mountain.keys.contains(player)
            && whists.keys.contains(player)
    }

    private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw InvariantViolation(message: message())
        }
    }
}

public struct ScoreSheet: Equatable, Codable, Sendable {
    public let players: [PlayerID]
    public private(set) var pool: [PlayerID: Int]
    public private(set) var mountain: [PlayerID: Int]
    public private(set) var whists: [PlayerID: [PlayerID: Int]]

    public init(players: [PlayerID]) {
        self.players = players
        self.pool = players.dictionary(filledWith: 0)
        self.mountain = players.dictionary(filledWith: 0)
        self.whists = players.dictionary(filledWith: [:])
    }

    init(uncheckedPlayers players: [PlayerID], pool: [PlayerID: Int], mountain: [PlayerID: Int], whists: [PlayerID: [PlayerID: Int]]) {
        self.players = players
        self.pool = pool
        self.mountain = mountain
        self.whists = whists
    }

    public mutating func apply(_ delta: ScoreDelta) {
        do {
            try delta.validate(players: players)
        } catch let violation as InvariantViolation {
            preconditionFailure(violation.message)
        } catch {
            preconditionFailure("unexpected score delta validation error: \(error)")
        }
        for (player, points) in delta.pool where points != 0 {
            pool[player]! += points
        }
        for (player, points) in delta.mountain where points != 0 {
            mountain[player]! += points
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
        var balances = players.dictionary(filledWith: 0.0)

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

    public func validate(players expectedPlayers: [PlayerID]) throws {
        try Self.require(players == expectedPlayers, "score players must match engine players")
        try Self.require(Set(players).count == players.count, "score players must be unique")
        let expected = Set(expectedPlayers)
        try Self.require(Set(pool.keys) == expected, "score pool keys must match players")
        try Self.require(Set(mountain.keys) == expected, "score mountain keys must match players")
        try Self.require(Set(whists.keys) == expected, "score whist writer keys must match players")
        for (writer, entries) in whists {
            try Self.require(expected.contains(writer), "score whist writer \(writer) is not in players")
            try Self.require(Set(entries.keys).isSubset(of: expected), "score whist targets for \(writer) contain unknown players")
            try Self.require(entries[writer] == nil || entries[writer] == 0, "score cannot write whists against self")
        }
    }

    private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw InvariantViolation(message: message())
        }
    }
}
