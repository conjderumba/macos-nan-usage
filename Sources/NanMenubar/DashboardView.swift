import SwiftUI
import AppKit

// MARK: - Theme

struct DashboardTheme {
    let isWeb: Bool
    let width: CGFloat
    let radius: CGFloat
    let background: AnyShapeStyle?
    let card: AnyShapeStyle
    let border: Color?
    let accent: Color
    let scheme: ColorScheme?
    let titleFont: Font
    let subtitleFont: Font
    let sectionFont: Font
    let valueFont: Font
    let numberFont: Font
    let tinyFont: Font
    let primary: Color
    let secondary: Color
    let tertiary: Color

    static func make(_ theme: AppTheme) -> DashboardTheme {
        switch theme {
        case .native:
            return DashboardTheme(
                isWeb: false, width: 360, radius: 10,
                background: nil,
                card: AnyShapeStyle(.quaternary), border: nil,
                accent: .accentColor, scheme: nil,
                titleFont: .headline, subtitleFont: .caption,
                sectionFont: .subheadline.weight(.semibold), valueFont: .title2.weight(.semibold),
                numberFont: .caption, tinyFont: .caption2,
                primary: .primary, secondary: .secondary, tertiary: Color(nsColor: .tertiaryLabelColor)
            )
        case .web:
            return DashboardTheme(
                isWeb: true, width: 392, radius: 10,
                background: AnyShapeStyle(Color(red: 0.035, green: 0.035, blue: 0.05)),
                card: AnyShapeStyle(Color(red: 0.085, green: 0.085, blue: 0.115)),
                border: Color.white.opacity(0.06),
                accent: Color(red: 0.55, green: 0.40, blue: 0.98), scheme: .dark,
                titleFont: .system(size: 16, weight: .bold, design: .monospaced),
                subtitleFont: .system(size: 9, weight: .medium, design: .monospaced),
                sectionFont: .system(size: 10, weight: .semibold, design: .monospaced),
                valueFont: .system(size: 20, weight: .bold, design: .monospaced),
                numberFont: .system(size: 11, design: .monospaced),
                tinyFont: .system(size: 9, design: .monospaced),
                primary: .white, secondary: Color(white: 0.55), tertiary: Color(white: 0.45)
            )
        }
    }
}

private extension View {
    /// Card background and border from the theme, to avoid repeating the modifier.
    func card(_ theme: DashboardTheme) -> some View {
        background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.card))
            .overlay {
                if let border = theme.border {
                    RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(border)
                }
            }
    }
}

// MARK: - Root

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyInput = ""
    @State private var hasStoredKey = false
    @State private var showSettings = false
    @State private var draggedModel: DashboardModel?
    @State private var dragWatchdog: Timer?

    private var theme: DashboardTheme { DashboardTheme.make(model.theme) }

    /// Reads the dragging pasteboard, which carries the payload of the drag in flight.
    /// A payload that is not one of our cards is ignored, which is what stops text
    /// dragged in from another app from reordering the list.
    private var draggedCardId: String? {
        NSPasteboard(name: .drag).string(forType: .string)
    }

    /// The card being dragged, for the reorder. Falls back to the state set by `onDrag`
    /// only when the pasteboard cannot be read at all.
    private func draggedCard() -> DashboardModel? {
        guard let id = draggedCardId else { return draggedModel }
        return model.models.first { $0.id == id }
    }

    /// Starts tracking a card drag. The drag preview follows the cursor on its own, so
    /// the card has to be faded out of the list or it ends up drawn twice.
    private func beginDrag(_ card: DashboardModel) {
        draggedModel = card
        dragWatchdog?.invalidate()
        // `.onDrag` has no "drag ended" callback, and a card released outside the list
        // never reaches `performDrop`, so watch the mouse button instead: once it is up
        // the drag is over, whatever ended it, and the card comes back.
            let timer = Timer(timeInterval: 0.15, repeats: true) { timer in
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                timer.invalidate()
                draggedModel = nil
            }
        RunLoop.main.add(timer, forMode: .common)
        dragWatchdog = timer
    }

    /// Whether `card` is the one under the pointer.
    private func isBeingDragged(_ card: DashboardModel) -> Bool {
        draggedModel?.id == card.id
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsPane(theme: theme, keyInput: $keyInput, hasStoredKey: $hasStoredKey, onBack: { showSettings = false })
            } else {
                dashboard.padding(14)
            }
        }
        .frame(width: 392, height: 620)
        .background {
            if !showSettings, let background = theme.background {
                Rectangle().fill(background)
            }
        }
        .preferredColorScheme(theme.scheme)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isAuthorized {
                if model.showMetrics, model.snapshot != nil {
                    stats
                }
                modelsSection
            } else {
                keyPrompt
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = NanIcon.menuBar {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("NaN")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primary)
                Text(model.accountLabel.isEmpty ? (theme.isWeb ? "USAGE DASHBOARD" : "Account usage") : model.accountLabel)
                    .font(theme.subtitleFont)
                    .tracking(theme.isWeb ? 1.2 : 0)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.secondary)
            .help("Actualizar")
            .disabled(!model.isAuthorized)
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            StatCard(theme: theme, label: "Total", value: model.allTimeTotal)
            StatCard(theme: theme, label: theme.isWeb ? "30 DÍAS" : "30 days", value: model.last30dTotal)
            StatCard(theme: theme, label: theme.isWeb ? "24 HORAS" : "24 hours", value: model.last24hTotal)
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.isWeb ? "MODELS" : "Models")
                    .font(theme.sectionFont)
                    .tracking(theme.isWeb ? 1.2 : 0)
                    .foregroundStyle(theme.isWeb ? theme.secondary : theme.primary)
                Spacer()
                Text("Updated \(Format.relative(model.lastUpdated))")
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.tertiary)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(theme.tinyFont)
                    .foregroundStyle(.orange)
            }

            if model.visibleModels.isEmpty {
                Text(model.isRefreshing ? "Loading…" : "No usage data yet.")
                    .font(theme.numberFont)
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.visibleModels) { item in
                            ModelRowView(theme: theme, model: item, showBreakdown: model.showMetrics)
                                .opacity(isBeingDragged(item) ? 0.2 : 1)
                                .onDrag {
                                    beginDrag(item)
                                    return NSItemProvider(object: item.id as NSString)
                                }
                                .onDrop(
                                    of: [.text],
                                    delegate: ModelReorderDelegate(
                                        target: item,
                                        source: { draggedCard() },
                                        onEnter: { source, target in model.moveModel(source, onto: target) },
                                        onDrop: { draggedModel = nil }
                                    )
                                )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var keyPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your NaN API key")
                .font(theme.sectionFont)
                .foregroundStyle(theme.primary)
            Text("Auto-detected from ~/.config/nan/api-key or from opencode. Otherwise paste it here.")
                .font(theme.tinyFont)
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("sk-…", text: $keyInput)
                .textFieldStyle(.roundedBorder)
            if let error = model.errorMessage {
                Text(error)
                    .font(theme.tinyFont)
                    .foregroundStyle(.orange)
            }
            Button("Save") { model.setAPIKey(keyInput) }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .font(theme.tinyFont)
            .foregroundStyle(theme.isWeb ? theme.accent : theme.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(theme.tinyFont)
                .foregroundStyle(theme.secondary)
        }
    }
}

// MARK: - Components

private struct StatCard: View {
    let theme: DashboardTheme
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(theme.tinyFont)
                .tracking(theme.isWeb ? 1 : 0)
                .foregroundStyle(theme.secondary)
            Text(Format.compact(value))
                .font(theme.valueFont)
                .monospacedDigit()
                .foregroundStyle(theme.primary)
            Text("tokens")
                .font(theme.tinyFont)
                .foregroundStyle(theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .card(theme)
    }
}

private struct ModelRowView: View {
    let theme: DashboardTheme
    let model: DashboardModel
    let showBreakdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                    .help("Drag to reorder")
                Text(model.name)
                    .font(theme.isWeb ? .system(size: 12, weight: .semibold, design: .monospaced) : .subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if !model.available {
                    Text("n/a")
                        .font(theme.isWeb ? .system(size: 8, design: .monospaced) : .caption2)
                        .foregroundStyle(theme.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.card))
                }
                Spacer()
                if let cap = model.cap {
                    Text(Format.compact(model.monthUsed)).foregroundStyle(theme.isWeb ? theme.accent : theme.primary).monospacedDigit()
                    + Text(" / \(Format.compact(cap))").foregroundStyle(theme.secondary).monospacedDigit()
                } else {
                    Text("\(Format.compact(model.allTime)) total").foregroundStyle(theme.secondary).monospacedDigit()
                }
            }
            .font(theme.numberFont)

            if !model.spec.isEmpty {
                Text(model.spec)
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }

            if model.cap != nil {
                ProgressView(value: model.fraction)
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
            }

            if showBreakdown {
                HStack {
                    Text("in \(Format.compact(model.input)) · out \(Format.compact(model.output))")
                        .monospacedDigit()
                    Spacer()
                    if let reset = Format.resetLabel(model.resets) {
                        Text(reset)
                    }
                }
                .font(theme.tinyFont)
                .foregroundStyle(theme.tertiary)
            }
        }
        .padding(10)
        .card(theme)
    }
}

// MARK: - Reordering

/// Live reordering while a card is being dragged: hovering another card drops the
/// dragged one into its place, so the list follows the pointer instead of waiting for
/// the mouse to be released.
private struct ModelReorderDelegate: DropDelegate {
    let target: DashboardModel
    let source: () -> DashboardModel?
    let onEnter: (DashboardModel, DashboardModel) -> Void
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard let source = source(), source.id != target.id else { return }
        withAnimation(.easeInOut(duration: 0.15)) { onEnter(source, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDrop()
        return true
    }
}

// MARK: - Settings

private struct SettingsPane: View {
    @EnvironmentObject private var model: AppModel
    let theme: DashboardTheme
    @Binding var keyInput: String
    @Binding var hasStoredKey: Bool
    let onBack: () -> Void

    @State private var pollText = ""
    @FocusState private var pollFocused: Bool

    private func commitPoll() {
        let value = Int(pollText.trimmingCharacters(in: .whitespaces)) ?? model.pollSeconds
        let clamped = min(1800, max(60, value))
        model.pollSeconds = clamped
        pollText = String(clamped)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.secondary)
                Spacer()
                Text("Settings")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primary)
                Spacer()
                Label("Back", systemImage: "chevron.left").hidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Form {
                Section("NaN API key") {
                    SecureField("API key", text: $keyInput)
                    TextField("Key file", text: $model.keyPath)
                    HStack(spacing: 8) {
                        Button("Save") {
                            model.setAPIKey(keyInput)
                            if NanAPIKey.normalized(keyInput) != nil {
                                keyInput = ""
                                hasStoredKey = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        if hasStoredKey {
                            Button("Remove", role: .destructive) {
                                model.clearAPIKey()
                                keyInput = ""
                                hasStoredKey = false
                            }
                        }
                        Spacer()
                        if hasStoredKey {
                            Label("Stored in Keychain", systemImage: "checkmark.seal.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $model.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Menu bar") {
                    Picker("Indicator follows", selection: $model.panelModel) {
                        ForEach(PanelModel.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if model.panelModel == .fixed {
                        TextField("Model id", text: $model.panelModelId)
                    }

                    Text("Near cap: closest to its cap · Highest: most tokens · Fixed: the model id above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Gauge", selection: $model.panelGauge) {
                        ForEach(PanelGauge.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show icon", isOn: $model.showIcon)
                    Toggle("Show percentage", isOn: $model.showPercentage)
                    Toggle("Show reset", isOn: $model.showReset)
                    Toggle("Show model name", isOn: $model.showModelName)
                    Toggle("Show total tokens", isOn: $model.showTotalTokens)
                }

                Section("Data") {
                    LabeledContent("Poll every") {
                        HStack(spacing: 6) {
                            TextField(text: $pollText, prompt: Text("300")) { EmptyView() }
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                                .focused($pollFocused)
                                .onSubmit(commitPoll)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Aggregate usage (24h / 30d)", isOn: $model.showMetrics)
                    Toggle("Hide unused models", isOn: $model.hideUnused)
                    if !model.modelOrder.isEmpty {
                        Button("Reset model order") { model.resetModelOrder() }
                    }
                }

                Section {
                    HStack {
                        Text(model.accountLabel.isEmpty ? "Not signed in" : model.accountLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Quit") { NSApp.terminate(nil) }
                    }
                }
            }
            .formStyle(.grouped)
            .font(theme.isWeb ? .system(size: 11, design: .monospaced) : .body)
            .tint(theme.accent)
            .scrollContentBackground(theme.isWeb ? .hidden : .automatic)
            .background {
                if let background = theme.background {
                    Rectangle().fill(background)
                }
            }
        }
        .onAppear {
            hasStoredKey = SecretStore.loadAPIKey() != nil
            pollText = String(model.pollSeconds)
        }
        .onChange(of: pollFocused) { _, focused in
            if !focused { commitPoll() }
        }
    }
}
