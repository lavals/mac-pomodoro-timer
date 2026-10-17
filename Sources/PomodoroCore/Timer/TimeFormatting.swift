import Foundation

/// Largest value `formatRemaining` shows (`999:59`). Far above the longest session
/// (`Preferences.minuteRange`), it only guards the `Int` conversion against absurd values.
private let maxDisplayedSeconds = 999 * 60 + 59

/// Formats seconds as `mm:ss` (minutes grow past two digits, e.g. `120:00`), rounding up to
/// whole seconds so a fresh 25-minute session reads `25:00`. Negative or NaN values show `00:00`.
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
