import AppKit
import SwiftUI

extension RingTint {
    /// The system color behind the tint; matches the menu bar countdown.
    public var nsColor: NSColor {
        switch self {
        case .accent: return .controlAccentColor
        case .green: return .systemGreen
        case .secondary: return .secondaryLabelColor
        }
    }

    public var color: Color { Color(nsColor: nsColor) }
}

/// A circular progress indicator: a subtle full-circle track with the elapsed fraction drawn
/// clockwise from 12 o'clock, ending in a round cap.
public struct ProgressRing: View {
    /// Elapsed fraction in 0...1; values outside are clamped.
    public let progress: Double
    public let tint: Color
    public var lineWidth: CGFloat = 8

    public init(progress: Double, tint: Color, lineWidth: CGFloat = 8) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Self.clamped(progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // a zero-length trim with a round cap would still draw a dot
                .opacity(Self.clamped(progress) > 0 ? 1 : 0)
                .animation(.linear(duration: 0.3), value: progress)
        }
        // the stroke is centered on the path, so inset it to stay inside the frame
        .padding(lineWidth / 2)
    }

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
