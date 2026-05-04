import Foundation

public enum PreferansInviteLink {
    public static func inviteURL(baseURL: URL = AppIdentifiers.inviteBaseURL, roomCode: String) -> URL {
        baseURL
            .appendingPathComponent("join")
            .appendingPathComponent(normalizedRoomCode(roomCode) ?? roomCode)
    }

    public static func roomCode(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, components[0].lowercased() == "join" else {
            return nil
        }
        return normalizedRoomCode(components[1])
    }

    public static func normalizedRoomCode(_ raw: String) -> String? {
        let code = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard code.count >= 4, code.count <= 12 else { return nil }
        return code
    }
}
