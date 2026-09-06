import Foundation

public enum PreferansGameStatus: String, Codable, Sendable, Equatable {
    case lobby
    case playing
    case finished
    case abandoned
}
