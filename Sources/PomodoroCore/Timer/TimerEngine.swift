import Foundation

/// Pure pomodoro state machine. Every transition returns the effects the caller must perform.
///
/// The engine never reads the clock; callers pass `now` so tests control time.
public struct TimerEngine: Equatable, Sendable {
    public private(set) var state: TimerState

    public init(state: TimerState = .idle) {
        self.state = state
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
            state = .running(phase: phase, endDate: now.addingTimeInterval(remaining), total: total)
        case .idle, .finished:
            phase = nextPhase
            let total = durations.total(for: phase)
            state = .running(phase: phase, endDate: now.addingTimeInterval(total), total: total)
        }
        return phase == .work ? [.focusOn] : []
    }

    /// Pauses a running phase. If the phase already ran out, it finishes instead (same as `tick`).
    public mutating func pause(now: Date) -> [Effect] {
        guard case .running(let phase, let endDate, let total) = state else { return [] }
        if now >= endDate { return tick(now: now) }
        state = .paused(phase: phase, remaining: endDate.timeIntervalSince(now), total: total)
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

    /// Finishes the running phase once `now` reaches its end date.
    public mutating func tick(now: Date) -> [Effect] {
        guard case .running(let phase, let endDate, _) = state, now >= endDate else { return [] }
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

    /// Seconds left in the current phase; 0 when idle or finished, never negative.
    public func remaining(now: Date) -> TimeInterval {
        switch state {
        case .idle, .finished: return 0
        case .running(_, let endDate, _): return max(0, endDate.timeIntervalSince(now))
        case .paused(_, let remaining, _): return max(0, remaining)
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
}
