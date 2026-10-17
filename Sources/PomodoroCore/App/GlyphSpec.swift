import Foundation

/// What the menu bar glyph shows: a ring whose arc tracks the elapsed fraction of the phase.
/// Pure value so the mapping from timer state is testable without drawing.
public struct GlyphSpec: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Work phase: the elapsed arc is a filled wedge.
        case filled
        /// Rest phase: the elapsed arc is a stroked line.
        case outlined
        /// Nothing in progress: a faint ring.
        case dimmed
    }

    public var style: Style
    /// Elapsed fraction drawn as an arc, 0...1.
    public var arc: Double

    public init(style: Style, arc: Double) {
        self.style = style
        self.arc = arc
    }

    /// Glyph for `state`. `progress` is the coordinator's elapsed fraction and is clamped to 0...1.
    public static func make(state: TimerState, progress: Double) -> GlyphSpec {
        let clamped = min(max(progress, 0), 1)
        switch state {
        case .idle:
            return GlyphSpec(style: .dimmed, arc: 0)
        case .running(let phase, _, _), .paused(let phase, _, _):
            return GlyphSpec(style: style(for: phase), arc: clamped)
        case .finished(let phase):
            return GlyphSpec(style: style(for: phase), arc: 1)
        }
    }

    private static func style(for phase: Phase) -> Style {
        phase == .work ? .filled : .outlined
    }
}
