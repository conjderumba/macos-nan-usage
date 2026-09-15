import AppKit

/// Composes the menu bar content into a single image.
/// MenuBarExtra does not reliably render multiple child views, so we draw
/// icon + gauge + text ourselves.
enum MenuBarLabel {
    private enum Item {
        case image(NSImage, CGFloat)
        case text(String)
    }

    private static let spacing: CGFloat = 4
    private static let height: CGFloat = 18

    @MainActor
    static func image(for model: AppModel) -> NSImage? {
        var items: [Item] = []
        if model.showIcon, let icon = NanIcon.menuBar {
            items.append(.image(icon, 16))
        }
        if let gauge = model.gaugeImage {
            items.append(.image(gauge, gauge.size.height))
        }
        if model.showPercentage, let text = model.percentageText {
            items.append(.text(text))
        }
        if model.showReset, let text = model.resetText {
            items.append(.text(text))
        }
        if model.showModelName, let name = model.selectedModel?.name {
            items.append(.text(name))
        }
        if model.showTotalTokens {
            items.append(.text(model.totalText))
        }
        guard !items.isEmpty else { return nil }
        return render(items)
    }

    private static func render(_ items: [Item]) -> NSImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]

        var widths: [CGFloat] = []
        var imageSizes: [NSSize?] = []
        var strings: [NSAttributedString?] = []

        for item in items {
            switch item {
            case .image(let image, let targetHeight):
                let width = image.size.height > 0 ? image.size.width * (targetHeight / image.size.height) : targetHeight
                widths.append(width)
                imageSizes.append(NSSize(width: width, height: targetHeight))
                strings.append(nil)
            case .text(let string):
                let attributed = NSAttributedString(string: string, attributes: attributes)
                widths.append(attributed.size().width)
                imageSizes.append(nil)
                strings.append(attributed)
            }
        }

        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1))
        let size = NSSize(width: ceil(total), height: height)
        let image = NSImage(size: size)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: 2, y: 2)

        var x: CGFloat = 0
        for (index, item) in items.enumerated() {
            switch item {
            case .image(let image, _):
                if let target = imageSizes[index] {
                    image.draw(in: NSRect(x: x, y: (height - target.height) / 2, width: target.width, height: target.height))
                }
            case .text:
                if let attributed = strings[index] {
                    attributed.draw(at: NSPoint(x: x, y: (height - attributed.size().height) / 2))
                }
            }
            x += widths[index] + spacing
        }

        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}
