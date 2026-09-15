import SwiftUI
import AppKit

// MARK: - Theme

struct DashboardTheme {
    let kind: AppTheme
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

    static func make(_ kind: AppTheme) -> DashboardTheme {
        switch kind {
        case .native:
            return DashboardTheme(
                kind: .native,
                width: 360,
                radius: 10,
                background: nil,
                card: AnyShapeStyle(.quaternary),
                border: nil,
                accent: Color.accentColor,
                scheme: nil,
                titleFont: .headline,
                subtitleFont: .caption,
                sectionFont: .subheadline.weight(.semibold),
                valueFont: .title2.weight(.semibold),
                numberFont: .caption,
                tinyFont: .caption2,
                primary: .primary,
                secondary: .secondary,
                tertiary: Color(nsColor: .tertiaryLabelColor)
            )
        case .web:
            return DashboardTheme(
                kind: .web,
                width: 392,
                radius: 10,
                background: AnyShapeStyle(Color(red: 0.035, green: 0.035, blue: 0.05)),
                card: AnyShapeStyle(Color(red: 0.085, green: 0.085, blue: 0.115)),
                border: Color.white.opacity(0.06),
                accent: Color(red: 0.55, green: 0.40, blue: 0.98),
                scheme: .dark,
                titleFont: .system(size: 16, weight: .bold, design: .monospaced),
                subtitleFont: .system(size: 9, weight: .medium, design: .monospaced),
                sectionFont: .system(size: 10, weight: .semibold, design: .monospaced),
                valueFont: .system(size: 20, weight: .bold, design: .monospaced),
                numberFont: .system(size: 11, design: .monospaced),
                tinyFont: .system(size: 9, design: .monospaced),
                primary: .white,
                secondary: Color(white: 0.55),
                tertiary: Color(white: 0.45)
            )
        }
    }
}

// MARK: - Root

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyInput = ""
    @State private var showSettings = false

    private var theme: DashboardTheme { DashboardTheme.make(model.theme) }

    var body: some View {
        Group {
            if showSettings {
                SettingsPane(theme: theme, keyInput: $keyInput, onBack: { showSettings = false })
            } else {
                dashboard
            }
        }
        .padding(14)
        .frame(width: theme.width, height: showSettings || model.isAuthorized ? 620 : 320)
        .background {
            if let bg = theme.background {
                Rectangle().fill(bg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .preferredColorScheme(theme.scheme)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isAuthorized {
                stats
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
                Text(model.accountLabel.isEmpty ? (theme.kind == .web ? "USAGE DASHBOARD" : "Uso de la cuenta") : model.accountLabel)
                    .font(theme.subtitleFont)
                    .tracking(theme.kind == .web ? 1.2 : 0)
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
            StatCard(theme: theme, label: theme.kind == .web ? "30 DÍAS" : "30 días", value: model.last30dTotal)
            StatCard(theme: theme, label: theme.kind == .web ? "24 HORAS" : "24 horas", value: model.last24hTotal)
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.kind == .web ? "MODELOS" : "Modelos")
                    .font(theme.sectionFont)
                    .tracking(theme.kind == .web ? 1.2 : 0)
                    .foregroundStyle(theme.kind == .web ? theme.secondary : theme.primary)
                Spacer()
                Text("Actualizado \(Format.relative(model.lastUpdated))")
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.tertiary)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(theme.tinyFont)
                    .foregroundStyle(.orange)
            }

            if model.models.isEmpty {
                Text(model.isRefreshing ? "Cargando…" : "Sin datos de consumo todavía.")
                    .font(theme.numberFont)
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.models) { item in
                            ModelRowView(theme: theme, model: item)
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
            Text("Conecta tu API key de NaN")
                .font(theme.sectionFont)
                .foregroundStyle(theme.primary)
            Text("Se detecta sola si tienes un fichero en ~/.config/nan/api-key o configuras NaN en opencode. Si no, pégala aquí.")
                .font(theme.tinyFont)
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("sk-…", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(theme.kind == .web ? .system(size: 11, design: .monospaced) : .body)
            if let error = model.errorMessage {
                Text(error)
                    .font(theme.tinyFont)
                    .foregroundStyle(.orange)
            }
            Button("Guardar") { model.setAPIKey(keyInput) }
                .buttonStyle(theme.kind == .web ? .borderedProminent : .borderedProminent)
                .tint(theme.accent)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.card))
        .overlay(borderOverlay)
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                if theme.kind == .web {
                    Text("Ajustes")
                } else {
                    Label("Ajustes", systemImage: "gearshape")
                }
            }
            .buttonStyle(.borderless)
            .font(theme.tinyFont)
            .foregroundStyle(theme.secondary)

            Spacer()

            Button("Salir") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(theme.tinyFont)
                .foregroundStyle(theme.secondary)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = theme.border {
            RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(border)
        }
    }
}

// MARK: - Components

private struct StatCard: View {
    let theme: DashboardTheme
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: theme.kind == .web ? 4 : 3) {
            Text(label)
                .font(theme.tinyFont)
                .tracking(theme.kind == .web ? 1 : 0)
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
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.card))
        .overlay {
            if let border = theme.border {
                RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(border)
            }
        }
    }
}

private struct ModelRowView: View {
    let theme: DashboardTheme
    let model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.name)
                    .font(theme.kind == .web ? .system(size: 12, weight: .semibold, design: .monospaced) : .subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if !model.available {
                    Text("n/d")
                        .font(theme.kind == .web ? .system(size: 8, design: .monospaced) : .caption2)
                        .foregroundStyle(theme.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.card))
                }
                Spacer()
                if let cap = model.cap {
                    Text(Format.compact(model.monthUsed)).foregroundStyle(theme.kind == .web ? theme.accent : theme.primary).monospacedDigit()
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.card))
        .overlay {
            if let border = theme.border {
                RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(border)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsPane: View {
    @EnvironmentObject private var model: AppModel
    let theme: DashboardTheme
    @Binding var keyInput: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ajustes")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.primary)
                Spacer()
                Button("Volver", action: onBack)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.secondary)
            }

            section("API key de NaN") {
                TextField("sk-…", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.kind == .web ? .system(size: 11, design: .monospaced) : .body)
                Text("Se detecta sola desde ~/.config/nan/api-key o desde la configuración de NaN en opencode.")
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Guardar") { model.setAPIKey(keyInput) }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Borrar guardada") {
                        SecretStore.clearAPIKey()
                        keyInput = ""
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }

            section("Aspecto") {
                Picker("", selection: $model.theme) {
                    ForEach(AppTheme.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("Barra de menús") {
                Picker("", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            HStack {
                Text(model.accountLabel.isEmpty ? "Sin sesión" : model.accountLabel)
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(theme.tinyFont)
                    .foregroundStyle(theme.secondary)
            }

            Spacer()
        }
        .onAppear {
            if keyInput.isEmpty, let stored = SecretStore.loadAPIKey() { keyInput = stored }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(theme.kind == .web ? .system(size: 9, weight: .semibold, design: .monospaced) : .caption.weight(.semibold))
                .tracking(theme.kind == .web ? 1 : 0)
                .foregroundStyle(theme.secondary)
            content()
        }
    }
}
