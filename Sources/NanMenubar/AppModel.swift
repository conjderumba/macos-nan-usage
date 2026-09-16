import Foundation
import SwiftUI
import AppKit

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
    // Account data
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var quota: QuotaSnapshot?
    @Published private(set) var account: Account?
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var models: [DashboardModel] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAuthorized = false
    @Published var errorMessage: String?

    // Settings
    @Published var theme: AppTheme = Prefs.raw("theme", .native) {
        didSet { Prefs.set("theme", theme.rawValue) }
    }
    @Published var keyPath: String = Prefs.string("keyPath", NanProviderConfig.defaultKeyPath) {
        didSet {
            Prefs.set("keyPath", keyPath)
            resolveKey()
            Task { await refresh() }
        }
    }
    @Published var pollSeconds: Int = Prefs.int("pollSeconds", 300) {
        didSet {
            Prefs.set("pollSeconds", pollSeconds)
            restartTimer()
        }
    }
    @Published var panelModel: PanelModel = Prefs.raw("panelModel", .worst) {
        didSet { Prefs.set("panelModel", panelModel.rawValue) }
    }
    @Published var panelModelId: String = Prefs.string("panelModelId", "deepseek-v4-flash") {
        didSet { Prefs.set("panelModelId", panelModelId) }
    }
    @Published var panelGauge: PanelGauge = Prefs.raw("panelGauge", .ring) {
        didSet { Prefs.set("panelGauge", panelGauge.rawValue) }
    }
    @Published var showIcon: Bool = Prefs.bool("showIcon", true) {
        didSet { Prefs.set("showIcon", showIcon) }
    }
    @Published var showPercentage: Bool = Prefs.bool("showPercentage", false) {
        didSet { Prefs.set("showPercentage", showPercentage) }
    }
    @Published var showReset: Bool = Prefs.bool("showReset", false) {
        didSet { Prefs.set("showReset", showReset) }
    }
    @Published var showModelName: Bool = Prefs.bool("showModel", false) {
        didSet { Prefs.set("showModel", showModelName) }
    }
    @Published var showTotalTokens: Bool = Prefs.bool("showTotalTokens", false) {
        didSet { Prefs.set("showTotalTokens", showTotalTokens) }
    }
    @Published var showMetrics: Bool = Prefs.bool("showMetrics", true) {
        didSet {
            Prefs.set("showMetrics", showMetrics)
            Task { await refresh() }
        }
    }
    @Published var hideUnused: Bool = Prefs.bool("hideUnused", true) {
        didSet { Prefs.set("hideUnused", hideUnused) }
    }

    private let client = NanClient()
    private var apiKey = ""
    private var timer: Timer?

    init() {
        resolveKey()
    }

    // MARK: Derived

    var allTimeTotal: Int { snapshot?.allTime.totalTokens ?? 0 }
    var last30dTotal: Int { snapshot?.last30d.totalTokens ?? 0 }
    var last24hTotal: Int { snapshot?.last24h.totalTokens ?? 0 }

    var accountLabel: String { account?.email ?? account?.handle ?? "" }

    var visibleModels: [DashboardModel] {
        hideUnused ? models.filter { $0.monthUsed > 0 || $0.allTime > 0 } : models
    }

    /// Model reflected by the menu bar indicator.
    var selectedModel: DashboardModel? {
        let capped = models.filter { $0.cap != nil }
        switch panelModel {
        case .worst: return capped.max { $0.fraction < $1.fraction }
        case .max: return capped.max { $0.monthUsed < $1.monthUsed }
        case .fixed: return models.first { $0.id == panelModelId } ?? capped.first
        }
    }

    var gaugeImage: NSImage? {
        guard let model = selectedModel else { return nil }
        return GaugeRenderer.image(fraction: model.fraction, style: panelGauge)
    }

    var percentageText: String? {
        guard let model = selectedModel, model.cap != nil else { return nil }
        return "\(Int((model.fraction * 100).rounded()))%"
    }

    var resetText: String? {
        guard let date = selectedModel?.resets else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days >= 1 ? "\(days)d" : "<1d"
    }

    var totalText: String { Format.compact(allTimeTotal) }

    // MARK: Lifecycle

    func start() {
        restartTimer()
        if isAuthorized { Task { await refresh() } }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(pollSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func resolveKey() {
        let key = NanAPIKey.normalized(SecretStore.loadAPIKey() ?? NanProviderConfig.apiKey(keyPath: keyPath) ?? "")
        apiKey = key ?? ""
        isAuthorized = key != nil
    }

    // MARK: Actions

    func setAPIKey(_ value: String) {
        guard let key = NanAPIKey.normalized(value) else {
            errorMessage = "Invalid API key format."
            return
        }
        SecretStore.saveAPIKey(key)
        apiKey = key
        isAuthorized = true
        errorMessage = nil
        Task { await refresh() }
    }

    func clearAPIKey() {
        SecretStore.clearAPIKey()
        apiKey = ""
        isAuthorized = false
        snapshot = nil
        quota = nil
        account = nil
        models = []
        availableModels = []
        lastUpdated = nil
        errorMessage = nil
    }

    func refresh() async {
        guard isAuthorized, !apiKey.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let key = apiKey
        do {
            async let accountTask = client.account(apiKey: key)
            async let quotaTask = client.quota(apiKey: key)
            let metrics = showMetrics ? try await client.metrics(apiKey: key) : nil
            let (account, quotaSnapshot) = try await (accountTask, quotaTask)

            self.account = account
            self.quota = quotaSnapshot
            self.snapshot = metrics
            self.availableModels = (try? await client.availableModels(apiKey: key)) ?? []
            self.models = Self.buildModels(snapshot: metrics, quota: quotaSnapshot, available: availableModels)
            self.lastUpdated = Date()
            self.errorMessage = nil
        } catch NanError.unauthorized {
            isAuthorized = false
            errorMessage = NanError.unauthorized.errorDescription
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not reach NaN."
        }
    }

    static func buildModels(snapshot: UsageSnapshot?, quota: QuotaSnapshot, available: [String]) -> [DashboardModel] {
        let all = Dictionary(uniqueKeysWithValues: (snapshot?.allTime.byModel ?? []).map { ($0.model, $0) })
        let month = Dictionary(uniqueKeysWithValues: (snapshot?.monthToDate.byModel ?? []).map { ($0.model, $0) })
        let day = Dictionary(uniqueKeysWithValues: (snapshot?.last24h.byModel ?? []).map { ($0.model, $0) })
        let quotas = Dictionary(uniqueKeysWithValues: quota.models.map { ($0.model, $0) })
        let availableSet = Set(available)

        let ids = Set(all.keys).union(month.keys).union(day.keys).union(quotas.keys).union(availableSet)

        let rows = ids.map { id -> DashboardModel in
            let meta = ModelMetadata.forModel(id)
            let quotaModel = quotas[id]
            return DashboardModel(
                id: id,
                name: meta.name,
                spec: meta.spec,
                available: availableSet.isEmpty || availableSet.contains(id),
                cap: (quotaModel?.cap).flatMap { $0 > 0 ? $0 : nil },
                monthUsed: quotaModel?.tokensUsed ?? month[id]?.totalTokens ?? 0,
                allTime: all[id]?.totalTokens ?? 0,
                last24h: day[id]?.totalTokens ?? 0,
                input: all[id]?.inputTokens ?? 0,
                output: all[id]?.outputTokens ?? 0,
                resets: quotaModel?.periodEnd.flatMap(Format.parseDate)
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

    static func resetLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return "Resets \(formatter.string(from: date))"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

struct ModelMetadata {
    let name: String
    let spec: String

    static func forModel(_ id: String) -> ModelMetadata {
        table[id] ?? ModelMetadata(name: id, spec: "")
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
