import Foundation

/// The two kinds of session the timer alternates between.
public enum Phase: Codable, Equatable, Sendable {
    case work, rest
}

/// Session lengths in seconds, derived from `Preferences`.
public struct Durations: Equatable, Sendable {
    public var work: TimeInterval
    public var rest: TimeInterval

    public init(work: TimeInterval, rest: TimeInterval) {
        self.work = work
        self.rest = rest
    }

    /// Full length of the given phase.
    public func total(for phase: Phase) -> TimeInterval {
        switch phase {
        case .work: return work
        case .rest: return rest
        }
    }
}

/// Where the timer is. `running` stores an absolute end date so remaining time survives sleep.
public enum TimerState: Codable, Equatable, Sendable {
    /// Nothing running; the next phase is work.
    case idle
    case running(phase: Phase, endDate: Date, total: TimeInterval)
    case paused(phase: Phase, remaining: TimeInterval, total: TimeInterval)
    /// The phase ended (chimed or skipped); waiting for the user to start the next one.
    case finished(phase: Phase)
}

/// Sound played when a phase ends naturally.
public enum Chime: Equatable, Sendable {
    case workEnded, restEnded
}

/// Side effects requested by the engine. The coordinator performs them in order.
public enum Effect: Equatable, Sendable {
    case focusOn, focusOff
    case playChime(Chime)
    case postNotification(title: String, body: String)
}
