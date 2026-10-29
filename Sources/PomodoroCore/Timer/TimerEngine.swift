import Foundation

/// Pure pomodoro state machine. Every transition returns the effects the caller must perform.
///
/// The engine never reads the clock; callers pass `now` so tests control time. If the clock
/// moves backwards, time left is never more than the phase's `total`: `restore` and `tick` pull
/// a running end date in to `now + total`, and `pause` and resuming use at most `total`.
public struct TimerEngine: Equatable, Sendable {
    public private(set) var state: TimerState

    public init(state: TimerState = .idle) {
        self.state = state
    }

    /// Rebuilds the engine from a saved state at launch.
    ///
    /// A running phase whose end date passed while the app was not running finishes silently
    /// (no chime or notification), turning Focus off if it was a work phase. A work phase still
    /// in the future turns Focus back on so the system matches the timer; if its end date lies
    /// more than a full phase ahead (the clock moved backwards), it is pulled in to `now + total`.
    /// Everything else is restored as saved; nil restores idle.
    public static func restore(_ saved: TimerState?, now: Date) -> (TimerEngine, [Effect]) {
        guard let saved else { return (TimerEngine(), []) }
        switch saved {
        case .running(let phase, let endDate, _) where endDate <= now:
            return (TimerEngine(state: .finished(phase: phase)), phase == .work ? [.focusOff] : [])
        case .running(let phase, let endDate, let total):
            let clamped = TimerState.running(
                phase: phase, endDate: clampedEndDate(endDate, now: now, total: total), total: total
            )
            return (TimerEngine(state: clamped), phase == .work ? [.focusOn] : [])
        default:
            return (TimerEngine(state: saved), [])
        }
    }

    /// The phase `start(now:durations:)` would begin or resume.
    public var nextPhase: Phase {
        switch state {
        case .idle, .finished(.rest): return .work
        case .finished(.work): return .rest
        case .running(let phase, _, _), .paused(let phase, _, _): return phase
        }
    }

    /// Starts the next phase, or resumes a paused one. No-op while running.
    public mutating func start(now: Date, durations: Durations) -> [Effect] {
        let phase: Phase
        switch state {
        case .running:
            return []
        case .paused(let pausedPhase, let remaining, let total):
            phase = pausedPhase
            // bounded so a paused session saved with more than `total` left still ends on time
            let left = Self.clampedRemaining(remaining, total: total)
            state = .running(phase: phase, endDate: now.addingTimeInterval(left), total: total)
        case .idle, .finished:
            phase = nextPhase
            let total = durations.total(for: phase)
            state = .running(phase: phase, endDate: now.addingTimeInterval(total), total: total)
        }
        return phase == .work ? [.focusOn] : []
    }

    /// Pauses a running phase. If the phase already ran out, it finishes instead (same as `tick`).
    /// The stored time left is at most `total`, even if the clock moved backwards.
    public mutating func pause(now: Date) -> [Effect] {
        guard case .running(let phase, let endDate, let total) = state else { return [] }
        if now >= endDate { return tick(now: now) }
        let remaining = Self.clampedRemaining(endDate.timeIntervalSince(now), total: total)
        state = .paused(phase: phase, remaining: remaining, total: total)
        return phase == .work ? [.focusOff] : []
    }

    /// Ends a running or paused phase early without a chime.
    public mutating func skip(now: Date) -> [Effect] {
        switch state {
        case .running(let phase, _, _), .paused(let phase, _, _):
            state = .finished(phase: phase)
            return phase == .work ? [.focusOff] : []
        case .idle, .finished:
            return []
        }
    }

    /// Returns to idle from any state.
    public mutating func reset() -> [Effect] {
        let effects: [Effect]
        switch state {
        case .running(.work, _, _), .paused(.work, _, _): effects = [.focusOff]
        default: effects = []
        }
        state = .idle
        return effects
    }

    /// Finishes the running phase once `now` reaches its end date. An end date more than a full
    /// phase ahead (the clock moved backwards) is pulled in to `now + total` instead.
    public mutating func tick(now: Date) -> [Effect] {
        guard case .running(let phase, let endDate, let total) = state else { return [] }
        guard now >= endDate else {
            let clamped = Self.clampedEndDate(endDate, now: now, total: total)
            if clamped != endDate { state = .running(phase: phase, endDate: clamped, total: total) }
            return []
        }
        state = .finished(phase: phase)
        switch phase {
        case .work:
            return [
                .focusOff,
                .playChime(.workEnded),
                .postNotification(title: "Focus finished", body: "Time for a break"),
            ]
        case .rest:
            return [
                .playChime(.restEnded),
                .postNotification(title: "Break over", body: "Ready when you are"),
            ]
        }
    }

    /// Seconds left in the current phase in `0...total`; 0 when idle or finished.
    public func remaining(now: Date) -> TimeInterval {
        switch state {
        case .idle, .finished: return 0
        case .running(_, let endDate, let total):
            return Self.clampedRemaining(endDate.timeIntervalSince(now), total: total)
        case .paused(_, let remaining, let total): return Self.clampedRemaining(remaining, total: total)
        }
    }

    /// Elapsed fraction of the current phase in 0...1; 0 when idle, 1 when finished.
    public func progress(now: Date) -> Double {
        let total: TimeInterval
        switch state {
        case .idle: return 0
        case .finished: return 1
        case .running(_, _, let phaseTotal), .paused(_, _, let phaseTotal): total = phaseTotal
        }
        guard total > 0 else { return 1 }
        return min(max((total - remaining(now: now)) / total, 0), 1)
    }

    private static func clampedRemaining(_ remaining: TimeInterval, total: TimeInterval) -> TimeInterval {
        min(max(0, remaining), max(0, total))
    }

    /// `endDate`, but no later than a full phase from `now`.
    private static func clampedEndDate(_ endDate: Date, now: Date, total: TimeInterval) -> Date {
        min(endDate, now.addingTimeInterval(total))
    }
}
