import SwiftUI

/// A circular progress indicator: a subtle full-circle track with the elapsed fraction drawn
/// clockwise from 12 o'clock, ending in a round cap.
public struct ProgressRing: View {
    /// Elapsed fraction in 0...1, as `TimerEngine.progress(now:)` returns it.
    public let progress: Double
    public let tint: Color
    private let lineWidth: CGFloat = 8

    public init(progress: Double, tint: Color) {
        self.progress = progress
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // a zero-length trim with a round cap would still draw a dot
                .opacity(progress > 0 ? 1 : 0)
                .animation(.linear(duration: 0.3), value: progress)
        }
        // the stroke is centered on the path, so inset it to stay inside the frame
        .padding(lineWidth / 2)
    }
}
