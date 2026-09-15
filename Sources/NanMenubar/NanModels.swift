import Foundation

struct UsageModelRow: Decodable, Hashable {
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }
}

struct UsageWindow: Decodable {
    let totalTokens: Int
    let byModel: [UsageModelRow]
    let cachedAt: String?
}

struct UsageSnapshot: Decodable {
    let last24h: UsageWindow
    let last30d: UsageWindow
    let monthToDate: UsageWindow
    let allTime: UsageWindow
}

struct QuotaModel: Decodable, Hashable {
    let model: String
    let tokensUsed: Int
    let cap: Int
    let periodEnd: String?
    let windowHours: Int?
}

struct QuotaSnapshot: Decodable {
    let periodStart: String
    let models: [QuotaModel]
}

struct ModelsResponse: Decodable {
    let data: [ModelEntry]

    struct ModelEntry: Decodable { let id: String }
}

struct Account: Decodable {
    let email: String
    let username: String?
    let handle: String?
    let tier: String?
    let namespace: String?
    let region: String?
}

enum NanError: LocalizedError {
    case unauthorized
    case transport
    case decoding

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid or expired API key."
        case .transport: return "Could not reach NaN."
        case .decoding: return "Unexpected server response."
        }
    }
}
