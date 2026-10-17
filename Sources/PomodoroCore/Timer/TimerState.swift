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
