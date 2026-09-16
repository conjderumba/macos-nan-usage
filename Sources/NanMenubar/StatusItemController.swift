import AppKit
import SwiftUI
import Combine

/// Owns the NSStatusItem and a fixed-position panel.
/// A custom panel (instead of NSPopover) so the panel never moves when the
/// status item resizes, while the bar keeps updating live.
@MainActor
final class StatusItemController: NSObject {
    private enum Segment {
        case icon(NSImage)
        case gauge(NSImage)
        case text(String)
        case separator
    }

    private static let panelSize = NSSize(width: 392, height: 620)

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let panel: PopoverPanel
    private let stack = PassThroughStackView()
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = PopoverPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        setupPanel()
        setupStatusItem()

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        refresh()
    }

    // MARK: Panel

    private func setupPanel() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: DashboardView().environmentObject(model))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect
    }

    private func setupStatusItem() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(togglePanel)
            button.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            stack.setContentHuggingPriority(.required, for: .horizontal)
            stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size

        var origin = NSPoint(x: buttonFrame.maxX - size.width, y: buttonFrame.minY - size.height - 6)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)
            origin.y = max(origin.y, visible.minY + 6)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    private func closePanel() {
        panel.orderOut(nil)
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.closePanel()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Ignore clicks on the status item: the button action toggles the panel.
                if let button = self.statusItem.button, let window = button.window {
                    let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
                    if frame.contains(NSEvent.mouseLocation) { return }
                }
                self.closePanel()
            }
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    // MARK: Status bar content

    private func refresh() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for segment in segments() {
            stack.addArrangedSubview(view(for: segment))
        }
        resizeToContent()
    }

    /// The status bar button does not derive its width from constrained subviews,
    /// so we set the item length from the content ourselves (otherwise it never shrinks).
    private func resizeToContent() {
        stack.layoutSubtreeIfNeeded()
        guard !stack.arrangedSubviews.isEmpty else {
            statusItem.length = 0
            return
        }
        statusItem.length = max(24, ceil(stack.fittingSize.width))
    }

    private func segments() -> [Segment] {
        var groups: [[Segment]] = []

        var visual: [Segment] = []
        if model.showIcon, let icon = NanIcon.menuBar { visual.append(.icon(icon)) }
        if let gauge = model.gaugeImage { visual.append(.gauge(gauge)) }
        if !visual.isEmpty { groups.append(visual) }

        var level: [Segment] = []
        if model.showPercentage, let text = model.percentageText { level.append(.text(text)) }
        if model.showReset, let text = model.resetText { level.append(.text(text)) }
        if !level.isEmpty { groups.append(level) }

        if model.showModelName, let name = model.selectedModel?.name { groups.append([.text(name)]) }
        if model.showTotalTokens { groups.append([.text(model.totalText)]) }

        var result: [Segment] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { result.append(.separator) }
            result.append(contentsOf: group)
        }
        return result
    }

    private func view(for segment: Segment) -> NSView {
        switch segment {
        case .icon(let image):
            return imageView(image, height: 16, tooltip: model.tooltip)
        case .gauge(let image):
            return imageView(image, height: image.size.height, tooltip: model.percentageTooltip)
        case .text(let string):
            return label(string, tooltip: tooltip(for: string))
        case .separator:
            return SeparatorView()
        }
    }

    private func tooltip(for text: String) -> String? {
        if text == model.percentageText { return model.percentageTooltip }
        if text == model.resetText { return model.resetTooltip }
        if text == model.totalText { return "All-time total: \(Format.compact(model.allTimeTotal)) tokens" }
        if text == model.selectedModel?.name { return model.tooltip }
        return nil
    }

    private func label(_ string: String, tooltip: String?) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        field.textColor = .labelColor
        field.toolTip = tooltip
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    private func imageView(_ image: NSImage, height: CGFloat, tooltip: String?) -> NSImageView {
        let view = NSImageView(image: image)
        view.toolTip = tooltip
        view.translatesAutoresizingMaskIntoConstraints = false
        let width = image.size.height > 0 ? image.size.width * (height / image.size.height) : height
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: height),
            view.widthAnchor.constraint(equalToConstant: width),
        ])
        return view
    }
}

/// Borderless panel that can still take keyboard focus (for the text fields).
private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        NSRect(x: bounds.midX, y: bounds.midY - 6, width: 1, height: 12).fill()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 14) }
}

/// Lets clicks fall through to the status item button while its subviews keep their tooltips.
private final class PassThroughStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
