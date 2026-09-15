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

    var capped: [QuotaModel] { models.filter { $0.cap > 0 } }
    var uncapped: [QuotaModel] { models.filter { $0.cap == 0 } }
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
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Sesión caducada. Vuelve a iniciar sesión."
        case .transport(let m): return "Red: \(m)"
        case .decoding(let m): return "Respuesta inválida: \(m)"
        }
    }
}
