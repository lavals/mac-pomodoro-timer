import Foundation
import Testing
@testable import PomodoroCore

private let durations = Durations(work: 1500, rest: 300)

private let workEndEffects: [Effect] = [
    .focusOff,
    .playChime(.workEnded),
    .postNotification(title: "Focus finished", body: "Time for a break"),
]
private let restEndEffects: [Effect] = [
    .playChime(.restEnded),
    .postNotification(title: "Break over", body: "Ready when you are"),
]

enum EngineCall: String, Sendable, CaseIterable {
    case start, pause, skip, reset, tick

    func apply(to engine: inout TimerEngine, now: Date) -> [Effect] {
        switch self {
        case .start: return engine.start(now: now, durations: durations)
        case .pause: return engine.pause(now: now)
        case .skip: return engine.skip(now: now)
        case .reset: return engine.reset()
        case .tick: return engine.tick(now: now)
        }
    }
}

struct TransitionCase: Sendable, CustomTestStringConvertible {
    let from: TimerState
    let call: EngineCall
    let to: TimerState
    let effects: [Effect]

    var testDescription: String { "\(from) --\(call.rawValue)--> \(to)" }
}

private let runningWork = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(600), total: 1500)
private let runningRest = TimerState.running(phase: .rest, endDate: t0.addingTimeInterval(120), total: 300)
private let pausedWork = TimerState.paused(phase: .work, remaining: 600, total: 1500)
private let pausedRest = TimerState.paused(phase: .rest, remaining: 120, total: 300)
private let expiredWork = TimerState.running(phase: .work, endDate: t0, total: 1500)
private let expiredRest = TimerState.running(phase: .rest, endDate: t0, total: 300)

private let transitionTable: [TransitionCase] = [
    // start
    .init(from: .idle, call: .start,
          to: .running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500), effects: [.focusOn]),
    .init(from: .finished(phase: .work), call: .start,
          to: .running(phase: .rest, endDate: t0.addingTimeInterval(300), total: 300), effects: []),
    .init(from: .finished(phase: .rest), call: .start,
          to: .running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500), effects: [.focusOn]),
    .init(from: pausedWork, call: .start, to: runningWork, effects: [.focusOn]),
    .init(from: pausedRest, call: .start, to: runningRest, effects: []),
    // pause
    .init(from: runningWork, call: .pause, to: pausedWork, effects: [.focusOff]),
    .init(from: runningRest, call: .pause, to: pausedRest, effects: []),
    // skip
    .init(from: runningWork, call: .skip, to: .finished(phase: .work), effects: [.focusOff]),
    .init(from: pausedWork, call: .skip, to: .finished(phase: .work), effects: [.focusOff]),
    .init(from: runningRest, call: .skip, to: .finished(phase: .rest), effects: []),
    .init(from: pausedRest, call: .skip, to: .finished(phase: .rest), effects: []),
    // reset
    .init(from: runningWork, call: .reset, to: .idle, effects: [.focusOff]),
    .init(from: pausedWork, call: .reset, to: .idle, effects: [.focusOff]),
    .init(from: runningRest, call: .reset, to: .idle, effects: []),
    .init(from: pausedRest, call: .reset, to: .idle, effects: []),
    .init(from: .idle, call: .reset, to: .idle, effects: []),
    .init(from: .finished(phase: .work), call: .reset, to: .idle, effects: []),
    .init(from: .finished(phase: .rest), call: .reset, to: .idle, effects: []),
    // tick
    .init(from: expiredWork, call: .tick, to: .finished(phase: .work), effects: workEndEffects),
    .init(from: expiredRest, call: .tick, to: .finished(phase: .rest), effects: restEndEffects),
    .init(from: runningWork, call: .tick, to: runningWork, effects: []),
    .init(from: runningRest, call: .tick, to: runningRest, effects: []),
    // no-ops
    .init(from: .idle, call: .tick, to: .idle, effects: []),
    .init(from: .idle, call: .pause, to: .idle, effects: []),
    .init(from: .idle, call: .skip, to: .idle, effects: []),
    .init(from: pausedWork, call: .tick, to: pausedWork, effects: []),
    .init(from: pausedWork, call: .pause, to: pausedWork, effects: []),
    .init(from: pausedRest, call: .tick, to: pausedRest, effects: []),
    .init(from: pausedRest, call: .pause, to: pausedRest, effects: []),
    .init(from: .finished(phase: .work), call: .tick, to: .finished(phase: .work), effects: []),
    .init(from: .finished(phase: .work), call: .pause, to: .finished(phase: .work), effects: []),
    .init(from: .finished(phase: .work), call: .skip, to: .finished(phase: .work), effects: []),
    .init(from: .finished(phase: .rest), call: .tick, to: .finished(phase: .rest), effects: []),
    .init(from: .finished(phase: .rest), call: .pause, to: .finished(phase: .rest), effects: []),
    .init(from: .finished(phase: .rest), call: .skip, to: .finished(phase: .rest), effects: []),
    .init(from: runningWork, call: .start, to: runningWork, effects: []),
    .init(from: runningRest, call: .start, to: runningRest, effects: []),
]

struct RestoreCase: Sendable, CustomTestStringConvertible {
    let saved: TimerState?
    let state: TimerState
    let effects: [Effect]

    var testDescription: String { "restore \(saved.map { "\($0)" } ?? "nil") -> \(state)" }
}

private let restoreTable: [RestoreCase] = [
    // expired while the app was not running: finish silently, clean up Focus after work
    .init(saved: expiredWork, state: .finished(phase: .work), effects: [.focusOff]),
    .init(saved: expiredRest, state: .finished(phase: .rest), effects: []),
    .init(saved: .running(phase: .work, endDate: t0.addingTimeInterval(-3600), total: 1500),
          state: .finished(phase: .work), effects: [.focusOff]),
    // still running: reconcile Focus for work, nothing for rest
    .init(saved: runningWork, state: runningWork, effects: [.focusOn]),
    .init(saved: runningRest, state: runningRest, effects: []),
    // end date more than a phase ahead (clock moved backwards): pulled in to a full phase
    .init(saved: .running(phase: .work, endDate: t0.addingTimeInterval(10_000), total: 1500),
          state: .running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500), effects: [.focusOn]),
    .init(saved: .running(phase: .rest, endDate: t0.addingTimeInterval(900), total: 300),
          state: .running(phase: .rest, endDate: t0.addingTimeInterval(300), total: 300), effects: []),
    // everything else restores as saved
    .init(saved: nil, state: .idle, effects: []),
    .init(saved: .idle, state: .idle, effects: []),
    .init(saved: pausedWork, state: pausedWork, effects: []),
    .init(saved: pausedRest, state: pausedRest, effects: []),
    .init(saved: .finished(phase: .work), state: .finished(phase: .work), effects: []),
    .init(saved: .finished(phase: .rest), state: .finished(phase: .rest), effects: []),
]

@Suite(.timeLimit(.minutes(1))) struct TimerEngineTests {
    @Test(arguments: transitionTable)
    func transition(_ row: TransitionCase) {
        var engine = TimerEngine(state: row.from)
        let effects = row.call.apply(to: &engine, now: t0)
        #expect(engine.state == row.to)
        #expect(effects == row.effects)
    }

    @Test(arguments: restoreTable)
    func restore(_ row: RestoreCase) {
        let (engine, effects) = TimerEngine.restore(row.saved, now: t0)
        #expect(engine.state == row.state)
        #expect(effects == row.effects)
    }

    @Test func restoredRunningWorkKeepsCountingDown() {
        let (engine, _) = TimerEngine.restore(runningWork, now: t0)
        #expect(engine.remaining(now: t0.addingTimeInterval(100)) == 500)
    }

    @Test func defaultInitIsIdle() {
        #expect(TimerEngine().state == .idle)
    }

    @Test func resumeFromPausedWorkTurnsFocusBackOn() {
        var engine = TimerEngine()
        #expect(engine.start(now: t0, durations: durations) == [.focusOn])
        #expect(engine.pause(now: t0.addingTimeInterval(100)) == [.focusOff])
        #expect(engine.state == .paused(phase: .work, remaining: 1400, total: 1500))

        let resumeAt = t0.addingTimeInterval(1000)
        #expect(engine.start(now: resumeAt, durations: durations) == [.focusOn])
        #expect(engine.state == .running(phase: .work, endDate: resumeAt.addingTimeInterval(1400), total: 1500))
    }

    @Test func resumeIgnoresChangedDurations() {
        var engine = TimerEngine(state: pausedWork)
        _ = engine.start(now: t0, durations: Durations(work: 60, rest: 60))
        #expect(engine.state == runningWork)
    }

    @Test func workEndEffectsAreOrderedFocusOffChimeNotification() {
        var engine = TimerEngine()
        _ = engine.start(now: t0, durations: durations)
        let effects = engine.tick(now: t0.addingTimeInterval(1500))
        #expect(effects == workEndEffects)
        #expect(effects.first == .focusOff)
        #expect(effects.last == .postNotification(title: "Focus finished", body: "Time for a break"))
    }

    @Test func restEndEffectsAreOrderedChimeThenNotification() {
        var engine = TimerEngine(state: .finished(phase: .work))
        #expect(engine.start(now: t0, durations: durations) == [])
        let effects = engine.tick(now: t0.addingTimeInterval(300))
        #expect(effects == restEndEffects)
    }

    @Test(arguments: [runningWork, runningRest, pausedWork, pausedRest, expiredWork, expiredRest])
    func skipNeverChimesOrNotifies(_ state: TimerState) {
        var engine = TimerEngine(state: state)
        let effects = engine.skip(now: t0.addingTimeInterval(10_000))
        for effect in effects {
            if case .playChime = effect { Issue.record("skip played a chime") }
            if case .postNotification = effect { Issue.record("skip posted a notification") }
        }
        #expect(effects.allSatisfy { $0 == .focusOff })
    }

    // MARK: clock moved backwards while the app runs (now earlier than endDate - total)

    @Test func pauseAfterClockMovedBackStoresAtMostTotal() {
        var engine = TimerEngine(state: runningWork)  // ends at t0 + 600
        let effects = engine.pause(now: t0.addingTimeInterval(-3600))
        #expect(effects == [.focusOff])
        #expect(engine.state == .paused(phase: .work, remaining: 1500, total: 1500))
    }

    @Test func resumeOfPausedSessionWithMoreThanTotalLeftRunsAtMostTotal() {
        var engine = TimerEngine(state: .paused(phase: .work, remaining: 5000, total: 1500))
        _ = engine.start(now: t0, durations: durations)
        #expect(engine.state == .running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500))
    }

    @Test func remainingAndProgressStayWithinThePhaseAfterClockMovedBack() {
        let earlier = t0.addingTimeInterval(-3600)
        let running = TimerEngine(state: runningWork)
        #expect(running.remaining(now: earlier) == 1500)
        #expect(running.progress(now: earlier) == 0)

        let paused = TimerEngine(state: .paused(phase: .rest, remaining: 900, total: 300))
        #expect(paused.remaining(now: t0) == 300)
        #expect(paused.progress(now: t0) == 0)
    }

    @Test func tickAfterClockMovedBackPullsTheEndDateInToAFullPhase() {
        var engine = TimerEngine(state: runningWork)
        let earlier = t0.addingTimeInterval(-3600)
        #expect(engine.tick(now: earlier) == [])
        #expect(engine.state == .running(phase: .work, endDate: earlier.addingTimeInterval(1500), total: 1500))

        // the phase then ends a full phase after the rollback, not at the original end date
        #expect(engine.tick(now: earlier.addingTimeInterval(1500)) == workEndEffects)
        #expect(engine.state == .finished(phase: .work))
    }

    @Test func pauseAfterEndDateFinishesLikeTick() {
        var engine = TimerEngine(state: expiredWork)
        let effects = engine.pause(now: t0.addingTimeInterval(5))
        #expect(engine.state == .finished(phase: .work))
        #expect(effects == workEndEffects)
    }

    @Test func tickFarPastEndDateFinishesOnce() {
        var engine = TimerEngine()
        _ = engine.start(now: t0, durations: durations)
        let wake = t0.addingTimeInterval(8 * 3600)

        #expect(engine.remaining(now: wake) == 0)
        #expect(engine.progress(now: wake) == 1)
        #expect(engine.tick(now: wake) == workEndEffects)
        #expect(engine.state == .finished(phase: .work))
        #expect(engine.tick(now: wake) == [])
        #expect(engine.tick(now: wake.addingTimeInterval(60)) == [])
        #expect(engine.state == .finished(phase: .work))
    }

    @Test func tickExactlyAtEndDateFinishes() {
        var engine = TimerEngine()
        _ = engine.start(now: t0, durations: durations)
        #expect(engine.tick(now: t0.addingTimeInterval(1499.999)) == [])
        #expect(engine.tick(now: t0.addingTimeInterval(1500)) == workEndEffects)
    }

    @Test func remainingPerState() {
        #expect(TimerEngine().remaining(now: t0) == 0)
        #expect(TimerEngine(state: .finished(phase: .work)).remaining(now: t0) == 0)
        #expect(TimerEngine(state: runningWork).remaining(now: t0) == 600)
        #expect(TimerEngine(state: runningWork).remaining(now: t0.addingTimeInterval(100)) == 500)
        #expect(TimerEngine(state: runningWork).remaining(now: t0.addingTimeInterval(10_000)) == 0)
        #expect(TimerEngine(state: pausedWork).remaining(now: t0.addingTimeInterval(10_000)) == 600)
    }

    @Test func progressPerState() {
        #expect(TimerEngine().progress(now: t0) == 0)
        #expect(TimerEngine(state: .finished(phase: .rest)).progress(now: t0) == 1)
        #expect(TimerEngine(state: runningWork).progress(now: t0) == 0.6)
        #expect(TimerEngine(state: pausedRest).progress(now: t0) == 0.6)
        #expect(TimerEngine(state: runningWork).progress(now: t0.addingTimeInterval(-10_000)) == 0)
        #expect(TimerEngine(state: runningWork).progress(now: t0.addingTimeInterval(10_000)) == 1)
        #expect(TimerEngine(state: .running(phase: .work, endDate: t0, total: 0)).progress(now: t0) == 1)
    }

    @Test func nextPhasePerState() {
        #expect(TimerEngine().nextPhase == .work)
        #expect(TimerEngine(state: .finished(phase: .work)).nextPhase == .rest)
        #expect(TimerEngine(state: .finished(phase: .rest)).nextPhase == .work)
        #expect(TimerEngine(state: runningRest).nextPhase == .rest)
        #expect(TimerEngine(state: pausedWork).nextPhase == .work)
    }

    @Test func fullCycleAlternatesPhases() {
        var engine = TimerEngine()
        var now = t0
        #expect(engine.start(now: now, durations: durations) == [.focusOn])
        now += 1500
        #expect(engine.tick(now: now) == workEndEffects)
        #expect(engine.start(now: now, durations: durations) == [])
        now += 300
        #expect(engine.tick(now: now) == restEndEffects)
        #expect(engine.nextPhase == .work)
        #expect(engine.start(now: now, durations: durations) == [.focusOn])
    }
}
