import Foundation

/// Talks to the two NaN origins. Both accept the same API key:
/// - https://cloud-api.nan.builders  (account and usage, Bearer <api-key>)
/// - https://api.nan.builders/v1     (inference surface: models)
struct NanClient {
    private static let dashboard = "https://cloud-api.nan.builders"

    // The delegate blocks redirects so the Bearer never travels to another host.
    private static let redirectGuard = RedirectGuard()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: config, delegate: Self.redirectGuard, delegateQueue: nil)
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
        let data = try await get("https://api.nan.builders/v1/models", apiKey: apiKey)
        let response: ModelsResponse = try decode(data)
        return response.data.map(\.id)
    }

    private func get(_ url: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NanError.transport }
        if http.statusCode == 401 || http.statusCode == 403 { throw NanError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw NanError.transport }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NanError.decoding
        }
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
