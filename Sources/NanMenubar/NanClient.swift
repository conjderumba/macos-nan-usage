import Foundation

/// Talks to the two NaN origins that matter. Both accept the same API key:
/// - https://cloud-api.nan.builders  (account + consumption, Bearer <api-key>)
/// - https://api.nan.builders/v1     (inference surface: available models)
struct NanClient {
    private static let dashboard = "https://cloud-api.nan.builders"
    static let modelsURL = URL(string: "https://api.nan.builders/v1/models")!

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config)
    }

    func account(apiKey: String) async throws -> Account {
        let data = try await get("\(Self.dashboard)/api/auth/me", apiKey: apiKey)
        return try decode(data)
    }

    func metrics(apiKey: String) async throws -> UsageSnapshot {
        let data = try await get("\(Self.dashboard)/api/metrics/usage", apiKey: apiKey)
        return try decode(data)
    }

    func quota(apiKey: String) async throws -> QuotaSnapshot {
        let data = try await get("\(Self.dashboard)/api/usage/quota", apiKey: apiKey)
        return try decode(data)
    }

    func availableModels(apiKey: String) async throws -> [String] {
        let data = try await get(Self.modelsURL.absoluteString, apiKey: apiKey)
        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
        } catch {
            throw NanError.decoding(String(describing: error))
        }
    }

    private func get(_ url: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NanError.transport("sin respuesta") }
        if http.statusCode == 401 || http.statusCode == 403 { throw NanError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw NanError.transport("HTTP \(http.statusCode)")
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NanError.decoding(String(describing: error))
        }
    }
}
