import Foundation

public enum PreferansInviteLink {
    public static func inviteURL(baseURL: URL = AppIdentifiers.inviteBaseURL, roomCode: String) -> URL {
        baseURL
            .appendingPathComponent("join")
            .appendingPathComponent(normalizedRoomCode(roomCode) ?? roomCode)
    }

    public static func roomCode(from url: URL) -> String? {
        guard url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        let isWebInvite = url.scheme == "https" && url.host == AppIdentifiers.inviteBaseURL.host
        let isAppInvite = url.scheme == "com.mixandmatch.preferans" && url.host == "table"
        guard isWebInvite || isAppInvite else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0].lowercased() == "join" else {
            return nil
        }
        return normalizedRoomCode(components[1])
    }

    public static func roomCode(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return roomCode(from: url)
        }

        if trimmed.range(of: "join/", options: [.anchored, .caseInsensitive]) != nil {
            return roomCodeAfterJoinPrefix(in: trimmed, prefix: "join/")
        }
        if trimmed.hasPrefix("/join/") {
            return roomCode(from: AppIdentifiers.inviteBaseURL.appendingPathComponent(trimmed))
        }
        if let host = AppIdentifiers.inviteBaseURL.host, trimmed.hasPrefix(host + "/join/") {
            return URL(string: "https://" + trimmed).flatMap { roomCode(from: $0) }
        }

        return normalizedRoomCode(trimmed)
    }

    public static func normalizedRoomCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { return nil }
        let code = trimmed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard code.count >= 4, code.count <= 12 else { return nil }
        return code
    }

    private static func roomCodeAfterJoinPrefix(in value: String, prefix: String) -> String? {
        guard let range = value.range(of: prefix, options: .caseInsensitive) else { return nil }
        return roomCodeAfterJoinPrefix(in: value, prefixEnd: range.upperBound)
    }

    private static func roomCodeAfterJoinPrefix(in value: String, prefixEnd: String.Index) -> String? {
        let tail = value[prefixEnd...]
        let token = tail.prefix { character in
            character != "/" && character != "?" && character != "#"
        }
        return normalizedRoomCode(String(token))
    }
}
