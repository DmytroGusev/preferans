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

    private enum CodingKeys: String, CodingKey {
        case pool
        case mountain
        case whists
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = ScoreDelta(
            uncheckedPlayers: [],
            pool: try values.decode([PlayerID: Int].self, forKey: .pool),
            mountain: try values.decode([PlayerID: Int].self, forKey: .mountain),
            whists: try values.decode([PlayerID: [PlayerID: Int]].self, forKey: .whists)
        )
        do {
            try decoded.validate(players: Array(decoded.pool.keys))
        } catch let violation as InvariantViolation {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: violation.message
            ))
        }
        self = decoded
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
        try ScoreStorageValidator.validate(
            label: "scoreDelta",
            expectedPlayers: expectedPlayers,
            pool: pool,
            mountain: mountain,
            whists: whists
        )
    }

    private func hasKnownPlayer(_ player: PlayerID) -> Bool {
        pool.keys.contains(player)
            && mountain.keys.contains(player)
            && whists.keys.contains(player)
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

    private enum CodingKeys: String, CodingKey {
        case players
        case pool
        case mountain
        case whists
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPlayers = try values.decode([PlayerID].self, forKey: .players)
        let decoded = ScoreSheet(
            uncheckedPlayers: decodedPlayers,
            pool: try values.decode([PlayerID: Int].self, forKey: .pool),
            mountain: try values.decode([PlayerID: Int].self, forKey: .mountain),
            whists: try values.decode([PlayerID: [PlayerID: Int]].self, forKey: .whists)
        )
        do {
            try decoded.validate(players: decodedPlayers)
        } catch let violation as InvariantViolation {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: violation.message
            ))
        }
        self = decoded
    }

    /// Adds `delta` to the sheet verbatim, with **no pulka-closing
    /// redistribution**. Safe only as the fallback for matches whose pool
    /// target doesn't imply a per-player limit (see
    /// ``apply(_:closingAtPoolTarget:poolClosure:)``, the public entry point,
    /// which delegates here for unbounded and table-total matches). Applying
    /// a delta through this method in an individually closing match would let
    /// pool points overshoot the per-player target and skip the American-aid
    /// write-back — hence `private`.
    private mutating func applyRaw(_ delta: ScoreDelta) {
        validateForApply(delta)
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

    /// Applies a deal delta under the match's pulka-closing convention.
    /// Individual closure first fills the earner, then aids the highest open
    /// opponent and writes equivalent whists back to the earner. Once everyone
    /// is closed, leftover value reduces the earner's mountain so final equal
    /// pool totals can be ignored. Table-total closure applies entries verbatim:
    /// Leningrad does not close or aid individual pools.
    ///
    /// This is the **only public mutator** for deal deltas: it owns pulka
    /// closing, so external callers can't accidentally bypass it. Returns the
    /// delta as actually applied (post-closing).
    @discardableResult
    public mutating func apply(
        _ delta: ScoreDelta,
        closingAtPoolTarget totalPoolTarget: Int,
        poolClosure: PoolClosurePolicy = .individualWithAmericanAid,
        poolPointWhistValue: Int = 10
    ) -> ScoreDelta {
        precondition(poolPointWhistValue > 0, "poolPointWhistValue must be positive.")
        if totalPoolTarget == .max || poolClosure == .tableTotal {
            applyRaw(delta)
            return delta
        }
        guard let perPlayerTarget = individualPoolTarget(totalPoolTarget: totalPoolTarget) else {
            preconditionFailure(
                "Individual pool target \(totalPoolTarget) must be positive and divisible by \(players.count)."
            )
        }

        validateForApply(delta)
        var applied = ScoreDelta(players: players)

        for player in players {
            let points = delta.mountain[player] ?? 0
            guard points != 0 else { continue }
            mountain[player]! += points
            applied.addMountain(points, to: player)
        }

        for writer in players {
            for (target, points) in delta.whists[writer] ?? [:] where points != 0 {
                whists[writer, default: [:]][target, default: 0] += points
                applied.addWhists(points, writer: writer, on: target)
            }
        }

        for player in players {
            let points = delta.pool[player] ?? 0
            guard points != 0 else { continue }
            applyPool(
                points,
                earnedBy: player,
                perPlayerTarget: perPlayerTarget,
                poolPointWhistValue: poolPointWhistValue,
                appliedDelta: &applied
            )
        }

        return applied
    }

    public func whistsWritten(by writer: PlayerID, on target: PlayerID) -> Int {
        whists[writer]?[target] ?? 0
    }

    public func normalizedBalances(
        poolPointValue: Double = 10,
        mountainPointValue: Double = 10
    ) -> [PlayerID: Double] {
        precondition(poolPointValue > 0, "poolPointValue must be positive.")
        precondition(mountainPointValue > 0, "mountainPointValue must be positive.")
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
        try ScoreStorageValidator.validate(
            label: "score",
            expectedPlayers: expectedPlayers,
            pool: pool,
            mountain: mountain,
            whists: whists
        )
    }

    private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw InvariantViolation(message: message())
        }
    }

    private mutating func applyPool(
        _ points: Int,
        earnedBy earner: PlayerID,
        perPlayerTarget: Int,
        poolPointWhistValue: Int,
        appliedDelta: inout ScoreDelta
    ) {
        guard points > 0 else {
            pool[earner]! += points
            appliedDelta.addPool(points, to: earner)
            return
        }

        var remaining = points
        let ownRoom = max(0, perPlayerTarget - (pool[earner] ?? 0))
        let ownCredit = min(remaining, ownRoom)
        if ownCredit > 0 {
            pool[earner]! += ownCredit
            appliedDelta.addPool(ownCredit, to: earner)
            remaining -= ownCredit
        }

        while remaining > 0, let recipient = americanAidRecipient(excluding: earner, perPlayerTarget: perPlayerTarget) {
            let room = max(0, perPlayerTarget - (pool[recipient] ?? 0))
            let aid = min(remaining, room)
            guard aid > 0 else { break }
            pool[recipient]! += aid
            whists[earner, default: [:]][recipient, default: 0] += aid * poolPointWhistValue
            appliedDelta.addPool(aid, to: recipient)
            appliedDelta.addWhists(
                aid * poolPointWhistValue,
                writer: earner,
                on: recipient
            )
            remaining -= aid
        }

        if remaining > 0 {
            mountain[earner]! -= remaining
            appliedDelta.addMountain(-remaining, to: earner)
        }
    }

    private func americanAidRecipient(excluding earner: PlayerID, perPlayerTarget: Int) -> PlayerID? {
        var best: PlayerID?
        for candidate in players where candidate != earner && (pool[candidate] ?? 0) < perPlayerTarget {
            guard let currentBest = best else {
                best = candidate
                continue
            }
            if (pool[candidate] ?? 0) > (pool[currentBest] ?? 0) {
                best = candidate
            }
        }
        return best
    }

    private func individualPoolTarget(totalPoolTarget: Int) -> Int? {
        guard totalPoolTarget != .max,
              totalPoolTarget > 0,
              !players.isEmpty,
              totalPoolTarget.isMultiple(of: players.count)
        else {
            return nil
        }
        let target = totalPoolTarget / players.count
        return target > 0 ? target : nil
    }

    private func validateForApply(_ delta: ScoreDelta) {
        do {
            try delta.validate(players: players)
        } catch let violation as InvariantViolation {
            preconditionFailure(violation.message)
        } catch {
            preconditionFailure("unexpected score delta validation error: \(error)")
        }
    }
}

private enum ScoreStorageValidator {
    static func validate(
        label: String,
        expectedPlayers: [PlayerID],
        pool: [PlayerID: Int],
        mountain: [PlayerID: Int],
        whists: [PlayerID: [PlayerID: Int]]
    ) throws {
        try require(
            Set(expectedPlayers).count == expectedPlayers.count,
            "\(label) players must be unique"
        )
        let expected = Set(expectedPlayers)
        try require(Set(pool.keys) == expected, "\(label) pool keys must match players")
        try require(Set(mountain.keys) == expected, "\(label) mountain keys must match players")
        try require(Set(whists.keys) == expected, "\(label) whist writer keys must match players")
        try require(pool.values.allSatisfy { $0 >= 0 }, "\(label) pool entries cannot be negative")
        for (writer, entries) in whists {
            try require(expected.contains(writer), "\(label) whist writer \(writer) is not in players")
            try require(
                Set(entries.keys).isSubset(of: expected),
                "\(label) whist targets for \(writer) contain unknown players"
            )
            try require(
                entries.values.allSatisfy { $0 >= 0 },
                "\(label) direct whist entries cannot be negative"
            )
            try require(entries[writer] == nil || entries[writer] == 0, "\(label) cannot write whists against self")
        }
    }

    private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw InvariantViolation(message: message())
        }
    }
}
