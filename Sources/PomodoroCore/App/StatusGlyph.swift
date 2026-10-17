import AppKit

/// Draws a `GlyphSpec` into an 18×18 template image, so the menu bar tints it for light and dark mode.
public enum StatusGlyph {
    public static let size = NSSize(width: 18, height: 18)

    public static func image(spec: GlyphSpec) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(spec, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pomodoro"
        return image
    }

    private static func draw(_ spec: GlyphSpec, in rect: NSRect) {
        let lineWidth: CGFloat = 1.5
        let ringRect = rect.insetBy(dx: 2 + lineWidth / 2, dy: 2 + lineWidth / 2)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2

        // template images only use alpha, so the dimmed ring is just more transparent
        let trackAlpha: CGFloat = spec.style == .dimmed ? 0.35 : 0.5
        NSColor.black.withAlphaComponent(trackAlpha).setStroke()
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = lineWidth
        ring.stroke()

        guard spec.arc > 0 else { return }
        NSColor.black.set()
        // clockwise from 12 o'clock
        let start: CGFloat = 90
        let end = start - CGFloat(spec.arc) * 360
        switch spec.style {
        case .filled, .dimmed:
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            wedge.close()
            wedge.fill()
            ring.stroke()
        case .outlined:
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            arc.lineWidth = lineWidth + 0.5
            arc.lineCapStyle = .round
            arc.stroke()
        }
    }
}
