import Foundation

/// Typed access to the app settings (UserDefaults). The API key is NOT stored here.
enum Prefs {
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }

    static func string(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    static func stringArray(_ key: String, _ fallback: [String]) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? fallback
    }

    static func raw<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        T(rawValue: string(key, fallback.rawValue)) ?? fallback
    }

    static func set(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case native
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return "macOS native"
        case .web: return "NaN web"
        }
    }
}

/// Which model the menu bar indicator reflects.
enum PanelModel: String, CaseIterable, Identifiable {
    case worst
    case max
    case fixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worst: return "Near cap"
        case .max: return "Highest"
        case .fixed: return "Fixed"
        }
    }
}

/// How the selected model's level is drawn in the menu bar.
enum PanelGauge: String, CaseIterable, Identifiable {
    case ring
    case bar
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .bar: return "Bar"
        case .none: return "None"
        }
    }
}
