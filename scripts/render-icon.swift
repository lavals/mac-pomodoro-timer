// Renders the app icon into an .iconset directory.
// Usage: swift scripts/render-icon.swift <output.iconset>
// Draws a tomato-red circle with a white progress arc on a transparent background.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: render-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Draws the icon into a square bitmap of `pixels` × `pixels`.
func renderIcon(pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let side = CGFloat(pixels)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    // tomato body: a circle inset to leave room for the standard icon margin
    let inset = side * 0.1
    let bodyRect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let tomato = NSColor(srgbRed: 0.89, green: 0.27, blue: 0.20, alpha: 1)
    let highlight = NSColor(srgbRed: 0.96, green: 0.42, blue: 0.33, alpha: 1)
    let gradient = NSGradient(starting: highlight, ending: tomato)
    gradient?.draw(in: NSBezierPath(ovalIn: bodyRect), angle: -90)

    // white arc: about three quarters of a ring, starting at 12 o'clock and running clockwise
    let center = NSPoint(x: side / 2, y: side / 2)
    let radius = bodyRect.width * 0.30
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -180, clockwise: true)
    arc.lineWidth = max(1, side * 0.075)
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    context.flushGraphics()
    return bitmap.representation(using: .png, properties: [:])
}

// iconutil expects these names; @2x variants are double the pixel size.
let baseSizes = [16, 32, 128, 256, 512]
for size in baseSizes {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        guard let png = renderIcon(pixels: size * scale) else {
            FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
            exit(1)
        }
        try png.write(to: outputDirectory.appendingPathComponent(name))
    }
}
