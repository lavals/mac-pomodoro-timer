import Foundation
import Observation

/// User settings persisted in an injected `UserDefaults`.
///
/// Minute values are clamped to `Preferences.minuteRange` on load and on every write.
@Observable
public final class Preferences {
    public static let minuteRange = 1...120
    public static let defaultWorkMinutes = 25
    public static let defaultRestMinutes = 5
    public static let defaultShowCountdown = true

    enum Key {
        static let workMinutes = "workMinutes"
        static let restMinutes = "restMinutes"
        static let showCountdown = "showCountdown"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Length of a work session in minutes, clamped to 1...120.
    public var workMinutes: Int {
        didSet {
            let clamped = Self.clamp(workMinutes)
            if clamped != workMinutes { workMinutes = clamped; return }
            defaults.set(workMinutes, forKey: Key.workMinutes)
        }
    }

    /// Length of a rest session in minutes, clamped to 1...120.
    public var restMinutes: Int {
        didSet {
            let clamped = Self.clamp(restMinutes)
            if clamped != restMinutes { restMinutes = clamped; return }
            defaults.set(restMinutes, forKey: Key.restMinutes)
        }
    }

    /// Whether the menu bar item shows the `mm:ss` countdown next to the glyph.
    public var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: Key.showCountdown) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workMinutes = Self.clamp(defaults.object(forKey: Key.workMinutes) as? Int ?? Self.defaultWorkMinutes)
        restMinutes = Self.clamp(defaults.object(forKey: Key.restMinutes) as? Int ?? Self.defaultRestMinutes)
        showCountdown = defaults.object(forKey: Key.showCountdown) as? Bool ?? Self.defaultShowCountdown
    }

    /// Current durations in seconds for the timer engine.
    public var durations: Durations {
        Durations(work: TimeInterval(workMinutes * 60), rest: TimeInterval(restMinutes * 60))
    }

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
    }
}
