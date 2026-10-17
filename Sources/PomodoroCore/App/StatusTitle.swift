import AppKit

/// Builds the countdown shown next to the menu bar glyph.
public enum StatusTitle {
    public static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    /// - Parameters:
    ///   - time: `mm:ss` from the coordinator.
    ///   - phase: the running or paused phase; nil when nothing is in progress.
    ///   - showCountdown: when false the title is empty and only the glyph shows.
    public static func make(time: String, phase: Phase?, showCountdown: Bool) -> NSAttributedString {
        guard showCountdown else { return NSAttributedString() }
        return NSAttributedString(string: time, attributes: [
            .font: font,
            .foregroundColor: color(for: phase),
        ])
    }

    public static func color(for phase: Phase?) -> NSColor {
        switch phase {
        case .work: return .controlAccentColor
        case .rest: return .systemGreen
        case nil: return .secondaryLabelColor
        }
    }

    /// The phase whose tint the title uses: running or paused phases only.
    public static func phase(for state: TimerState) -> Phase? {
        switch state {
        case .running(let phase, _, _), .paused(let phase, _, _): return phase
        case .idle, .finished: return nil
        }
    }
}
