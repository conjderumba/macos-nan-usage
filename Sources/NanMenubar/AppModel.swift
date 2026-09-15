import Foundation
import SwiftUI

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndTotal
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconAndTotal: return "Icono + total"
        case .iconOnly: return "Solo icono"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case native
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return "Nativo de macOS"
        case .web: return "Estilo web NaN"
        }
    }
}

struct DashboardModel: Identifiable {
    let id: String
    var name: String
    var spec: String
    var available: Bool
    var cap: Int?
    var monthUsed: Int
    var allTime: Int
    var last24h: Int
    var input: Int
    var output: Int
    var resets: Date?

    var fraction: Double {
        guard let cap, cap > 0 else { return 0 }
        return min(1.0, Double(monthUsed) / Double(cap))
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var quota: QuotaSnapshot?
    @Published private(set) var account: Account?
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var models: [DashboardModel] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAuthorized = false
    @Published var errorMessage: String?

    @Published var menuBarStyle: MenuBarStyle = MenuBarStyle(
        rawValue: UserDefaults.standard.string(forKey: AppModel.menuBarStyleKey) ?? ""
    ) ?? .iconAndTotal {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: AppModel.menuBarStyleKey) }
    }

    @Published var theme: AppTheme = AppTheme(
        rawValue: UserDefaults.standard.string(forKey: AppModel.themeKey) ?? ""
    ) ?? .native {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: AppModel.themeKey) }
    }

    private static let menuBarStyleKey = "nan.menuBarStyle"
    private static let themeKey = "nan.theme"

    private let client = NanClient()
    private var apiKey: String
    private var timer: Timer?

    init() {
        let key = SecretStore.loadAPIKey() ?? NanProviderConfig.apiKey() ?? ""
        self.apiKey = key
        self.isAuthorized = !key.isEmpty
    }

    var allTimeTotal: Int { snapshot?.allTime.totalTokens ?? 0 }
    var last30dTotal: Int { snapshot?.last30d.totalTokens ?? 0 }
    var last24hTotal: Int { snapshot?.last24h.totalTokens ?? 0 }

    var menuTitle: String {
        guard snapshot != nil else { return "NaN" }
        return Format.compact(allTimeTotal)
    }

    var accountLabel: String {
        if let email = account?.email { return email }
        if let handle = account?.handle { return "@\(handle)" }
        return ""
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if isAuthorized { Task { await refresh() } }
    }

    func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKey = trimmed
        SecretStore.saveAPIKey(trimmed)
        isAuthorized = true
        errorMessage = nil
        Task { await refresh() }
    }

    func refresh() async {
        guard isAuthorized, !apiKey.isEmpty else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let accountTask = client.account(apiKey: apiKey)
            async let metricsTask = client.metrics(apiKey: apiKey)
            async let quotaTask = client.quota(apiKey: apiKey)
            let (account, metrics, quotaSnapshot) = try await (accountTask, metricsTask, quotaTask)
            self.account = account
            self.snapshot = metrics
            self.quota = quotaSnapshot
            self.lastUpdated = Date()
            self.errorMessage = nil

            if let ids = try? await client.availableModels(apiKey: apiKey) {
                self.availableModels = ids
            }
            self.models = Self.buildModels(snapshot: metrics, quota: quotaSnapshot, available: self.availableModels)
        } catch NanError.unauthorized {
            self.isAuthorized = false
            self.errorMessage = "API key inválida o caducada."
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    static func buildModels(snapshot: UsageSnapshot, quota: QuotaSnapshot, available: [String]) -> [DashboardModel] {
        var ids = Set<String>()
        ids.formUnion(snapshot.allTime.byModel.map(\.model))
        ids.formUnion(snapshot.monthToDate.byModel.map(\.model))
        ids.formUnion(snapshot.last24h.byModel.map(\.model))
        ids.formUnion(quota.models.map(\.model))
        ids.formUnion(available)

        let month = Dictionary(uniqueKeysWithValues: snapshot.monthToDate.byModel.map { ($0.model, $0) })
        let all = Dictionary(uniqueKeysWithValues: snapshot.allTime.byModel.map { ($0.model, $0) })
        let day = Dictionary(uniqueKeysWithValues: snapshot.last24h.byModel.map { ($0.model, $0) })
        let quotas = Dictionary(uniqueKeysWithValues: quota.models.map { ($0.model, $0) })
        let availableSet = Set(available)

        let rows = ids.map { id -> DashboardModel in
            let meta = ModelMetadata.forModel(id)
            let q = quotas[id]
            return DashboardModel(
                id: id,
                name: meta.name,
                spec: meta.spec,
                available: availableSet.isEmpty || availableSet.contains(id),
                cap: (q?.cap).flatMap { $0 > 0 ? $0 : nil },
                monthUsed: q?.tokensUsed ?? month[id]?.totalTokens ?? 0,
                allTime: all[id]?.totalTokens ?? 0,
                last24h: day[id]?.totalTokens ?? 0,
                input: all[id]?.inputTokens ?? 0,
                output: all[id]?.outputTokens ?? 0,
                resets: q?.periodEnd.flatMap(Format.parseDate)
            )
        }

        return rows.sorted { lhs, rhs in
            if (lhs.cap != nil) != (rhs.cap != nil) { return lhs.cap != nil }
            if lhs.monthUsed != rhs.monthUsed { return lhs.monthUsed > rhs.monthUsed }
            return lhs.allTime > rhs.allTime
        }
    }
}

enum Format {
    static func compact(_ value: Int) -> String {
        let d = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", d / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", d / 1_000) }
        return "\(value)"
    }

    static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func resetLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "es_ES")
        return "Resets on \(f.string(from: date))"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "hace \(seconds)s" }
        if seconds < 3600 { return "hace \(seconds / 60)m" }
        return "hace \(seconds / 3600)h"
    }

    static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: value) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: value) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: value)
    }
}

struct ModelMetadata {
    let name: String
    let spec: String

    static func forModel(_ id: String) -> ModelMetadata {
        if let known = table[id] { return known }
        return ModelMetadata(name: id, spec: "")
    }

    private static let table: [String: ModelMetadata] = [
        "qwen3.8-flash": .init(name: "Qwen 3.8 Flash", spec: "125B MoE · 6B active · 262K context · multimodal (vision)"),
        "qwen3.6": .init(name: "Qwen 3.6", spec: "262K context · multimodal · tool calling"),
        "deepseek-v4-flash": .init(name: "DeepSeek V4-Flash", spec: "284B MoE · 1M context · vision · reasoning"),
        "glm5.3-flash": .init(name: "GLM 5.3 Flash", spec: "multimodal · reasoning · 1M context"),
        "glm5.3": .init(name: "GLM 5.3", spec: "premium tier · reasoning · 1M context"),
        "glm5.2": .init(name: "GLM 5.2", spec: "reasoning · 1M context"),
        "gemma4": .init(name: "Gemma 4", spec: "multimodal · 262K context"),
        "mimo-v2.5": .init(name: "Xiaomi MiMo V2.5", spec: "310B-A15B MoE · reasoning · 1M context · external provider"),
        "whisper": .init(name: "Whisper", spec: "audio transcription"),
        "kokoro": .init(name: "Kokoro", spec: "text to speech"),
        "flux-2-klein": .init(name: "FLUX 2 Klein", spec: "image generation"),
        "minimax-h3": .init(name: "MiniMax H3", spec: "video generation"),
        "rerank": .init(name: "Reranker", spec: "document reranking"),
        "qwen3-embedding": .init(name: "Qwen3 Embedding", spec: "embeddings"),
    ]
}
