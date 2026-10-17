import Foundation

/// Largest value `formatRemaining` can show (`99:59`).
public let maxDisplayedSeconds = 99 * 60 + 59

/// Formats seconds as `mm:ss`, rounding up to whole seconds so a fresh 25-minute
/// session reads `25:00`. Negative or NaN values show `00:00`; values above `99:59` are capped.
public func formatRemaining(_ seconds: TimeInterval) -> String {
    let whole: Int
    if seconds.isNaN || seconds <= 0 {
        whole = 0
    } else if seconds >= TimeInterval(maxDisplayedSeconds) {
        whole = maxDisplayedSeconds
    } else {
        whole = Int(seconds.rounded(.up))
    }
    return String(format: "%02d:%02d", whole / 60, whole % 60)
}
