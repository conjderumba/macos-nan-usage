import AppKit

/// Draws the level gauge (ring or bar) for the menu bar.
enum GaugeRenderer {
    static func image(fraction: Double, style: PanelGauge, size: CGFloat = 14) -> NSImage? {
        switch style {
        case .none: return nil
        case .ring: return ring(fraction: fraction, size: size)
        case .bar: return bar(fraction: fraction, size: size)
        }
    }

    /// Level by threshold: accent, amber from 75% and red from 90%.
    private static func color(for fraction: Double) -> NSColor {
        if fraction >= 0.9 { return .systemRed }
        if fraction >= 0.75 { return .systemOrange }
        return .controlAccentColor
    }

    private static func ring(fraction: Double, size: CGFloat) -> NSImage {
        let lineWidth: CGFloat = 2.5
        return draw(size: NSSize(width: size, height: size)) { ctx in
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            let rect = CGRect(x: lineWidth / 2, y: lineWidth / 2, width: size - lineWidth, height: size - lineWidth)
            ctx.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
            ctx.strokeEllipse(in: rect)
            guard fraction > 0 else { return }
            ctx.setStrokeColor(color(for: fraction).cgColor)
            ctx.addArc(
                center: CGPoint(x: size / 2, y: size / 2),
                radius: (size - lineWidth) / 2,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi * fraction,
                clockwise: true
            )
            ctx.strokePath()
        }
    }

    private static func bar(fraction: Double, size: CGFloat) -> NSImage {
        let width: CGFloat = 26
        let height: CGFloat = 6
        return draw(size: NSSize(width: width, height: height)) { ctx in
            let radius = height / 2
            let background = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                cornerWidth: radius, cornerHeight: radius, transform: nil
            )
            ctx.addPath(background)
            ctx.setFillColor(NSColor.tertiaryLabelColor.cgColor)
            ctx.fillPath()

            let filled = max(height, width * CGFloat(fraction))
            let foreground = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: filled, height: height),
                cornerWidth: radius, cornerHeight: radius, transform: nil
            )
            ctx.addPath(foreground)
            ctx.setFillColor(color(for: fraction).cgColor)
            ctx.fillPath()
        }
    }

    private static func draw(size: NSSize, _ body: (CGContext) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let image = NSImage(size: size)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: rep) {
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.scaleBy(x: scale, y: scale)
            body(graphics.cgContext)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = false
        return image
    }
}
