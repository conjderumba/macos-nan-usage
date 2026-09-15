import Foundation

/// Resolves the NaN API key.
/// Priority: NAN_API_KEY -> configurable file (default ~/.config/nan/api-key)
/// -> opencode config -> opencode auth store.
enum NanProviderConfig {
    static let defaultKeyPath = "~/.config/nan/api-key"

    static func apiKey(keyPath: String = defaultKeyPath) -> String? {
        if let env = ProcessInfo.processInfo.environment["NAN_API_KEY"], !env.isEmpty {
            return env
        }
        if let key = fromFile(keyPath) { return key }
        if let key = fromOpencodeConfig() { return key }
        if let key = fromOpencodeAuth() { return key }
        return nil
    }

    private static func fromFile(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: expanded, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private static func fromOpencodeConfig() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".config/opencode/opencode.jsonc"),
            home.appendingPathComponent(".config/opencode/opencode.json"),
        ]
        for url in candidates {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let key = firstMatch(in: text, pattern: "\"apiKey\"\\s*:\\s*\"(sk-[^\"]+)\"") {
                return key
            }
        }
        return nil
    }

    private static func fromOpencodeAuth() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".local/share/opencode/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nan = root["nan"] as? [String: Any],
              let key = nan["key"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[resultRange])
    }
}
