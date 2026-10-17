import AppKit

/// Builds the countdown shown next to the menu bar glyph.
public enum StatusTitle {
    public static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    /// - Parameters:
    ///   - time: `mm:ss` from the coordinator.
    ///   - tint: `TimerPresentation.tint(for:)` of the current state.
    ///   - showCountdown: when false the title is empty and only the glyph shows.
    public static func make(time: String, tint: NSColor, showCountdown: Bool) -> NSAttributedString {
        guard showCountdown else { return NSAttributedString() }
        return NSAttributedString(string: time, attributes: [
            .font: font,
            .foregroundColor: tint,
        ])
    }
}
