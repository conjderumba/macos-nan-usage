import Foundation

/// Persists a manually entered NaN API key so it survives launches.
/// Falls back to the opencode config when nothing is stored here.
enum SecretStore {
    private static let key = "nan.apiKey"

    static func loadAPIKey() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func saveAPIKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
