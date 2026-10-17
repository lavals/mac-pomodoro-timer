import AppKit
import Foundation
import Observation
import Testing
@testable import PomodoroCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let bothShortcuts = [FocusController.onName, FocusController.offName]

/// Manually advanced clock.
@MainActor
final class TestClock {
    var now = t0

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// A coordinator wired to fakes only: no real shortcuts, sounds, notifications or timers.
@MainActor
struct Harness {
    let testDefaults = TestDefaults()
    let clock = TestClock()
    let log = EventLog()
    let runner: FakeShellRunner
    let alerts: FakeAlerts
    let tickers = FakeTickerFactory()
    let wakeCenter = NotificationCenter()
    let preferences: Preferences
    let store: SessionStore
    let coordinator: TimerCoordinator

    /// - Parameters:
    ///   - shortcuts: names `shortcuts list` reports.
    ///   - saved: session state saved before launch.
    init(shortcuts: [String] = bothShortcuts, saved: TimerState? = nil) {
        let log = log
        runner = FakeShellRunner { _, args in
            log.append("shell \(args.joined(separator: " "))")
            let stdout = args == ["list"] ? shortcuts.joined(separator: "\n") + "\n" : ""
            return ShellResult(status: 0, stdout: stdout, stderr: "")
        }
        alerts = FakeAlerts(log: log)
        preferences = Preferences(defaults: testDefaults.defaults)
        store = SessionStore(defaults: testDefaults.defaults)
        if let saved { store.save(saved) }
        let clock = clock
        coordinator = TimerCoordinator(
            now: { clock.now },
            preferences: preferences,
            sessionStore: store,
            focus: FocusController(runner: runner),
            alerts: alerts,
            makeTicker: tickers.make,
            wakeCenter: wakeCenter
        )
    }

    func cleanUp() {
        testDefaults.cleanUp()
    }

    /// `shortcuts run` calls only, without the availability check.
    var focusRuns: [[String]] {
        runner.calls.map(\.args).filter { $0.first == "run" }
    }

    func settle() async {
        await coordinator.waitForPendingEffects()
    }
}

private let focusOn = ["run", FocusController.onName]
private let focusOff = ["run", FocusController.offName]

@MainActor
@Suite struct TimerCoordinatorTests {
    // MARK: persistence and focus around actions

    @Test func startSavesStateAndTurnsFocusOn() async {
        let h = Harness()
        defer { h.cleanUp() }

        h.coordinator.start()

        let expected = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500)
        #expect(h.coordinator.state == expected)
        #expect(h.store.load() == expected)
        await h.settle()
        #expect(h.runner.calls.map(\.args) == [["list"], focusOn])
        #expect(h.coordinator.focusAvailability == .available)
        #expect(h.coordinator.lastFocusError == nil)
    }

    @Test func workEndPlaysChimeThenFocusOffThenNotification() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()

        h.clock.advance(1500)
        h.coordinator.tick()

        // the chime is immediate, before any Focus call finished
        #expect(h.alerts.chimes == [.workEnded])
        await h.settle()
        #expect(h.log.events.suffix(3) == [
            "chime workEnded",
            "shell run Pomodoro Focus Off",
            "notify Focus finished",
        ])
        #expect(h.alerts.notifications == [.init(title: "Focus finished", body: "Time for a break")])
        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.store.load() == .finished(phase: .work))
    }

    @Test func restEndChimesAndNotifiesWithoutFocus() async {
        let h = Harness(saved: .finished(phase: .work))
        defer { h.cleanUp() }

        h.coordinator.start()
        h.clock.advance(300)
        h.coordinator.tick()
        await h.settle()

        #expect(h.alerts.chimes == [.restEnded])
        #expect(h.alerts.notifications == [.init(title: "Break over", body: "Ready when you are")])
        #expect(h.focusRuns.isEmpty)
        #expect(h.coordinator.state == .finished(phase: .rest))
    }

    @Test func pauseSkipResetEachPersist() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()

        h.clock.advance(100)
        h.coordinator.pause()
        #expect(h.store.load() == .paused(phase: .work, remaining: 1400, total: 1500))

        h.coordinator.skip()
        #expect(h.store.load() == .finished(phase: .work))

        h.coordinator.start()
        #expect(h.store.load() == .running(phase: .rest, endDate: t0.addingTimeInterval(400), total: 300))

        h.coordinator.reset()
        #expect(h.store.load() == .idle)

        await h.settle()
        // start, pause, skip of a paused work phase, then a rest phase (no Focus)
        #expect(h.focusRuns == [focusOn, focusOff, focusOff])
    }

    @Test func pauseThenResumeTurnsFocusBackOn() async {
        let h = Harness()
        defer { h.cleanUp() }

        h.coordinator.start()
        h.coordinator.pause()
        h.coordinator.start()
        await h.settle()

        #expect(h.focusRuns == [focusOn, focusOff, focusOn])
    }

    @Test func performPrimaryActionTogglesBetweenStartAndPause() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.coordinator.performPrimaryAction()
        #expect(h.coordinator.primaryAction == .pause)
        h.coordinator.performPrimaryAction()
        #expect(h.coordinator.primaryAction == .resume)
        h.coordinator.performPrimaryAction()
        #expect(h.coordinator.primaryAction == .pause)
    }

    // MARK: display

    @Test func displayTimeFollowsTheClockAndNotifiesObservers() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.coordinator.start()
        #expect(h.coordinator.displayTime == "25:00")
        #expect(h.coordinator.progress == 0)

        let changed = Flag()
        withObservationTracking {
            _ = h.coordinator.displayTime
        } onChange: {
            changed.set()
        }
        h.clock.advance(61)
        h.coordinator.tick()

        #expect(changed.isSet)
        #expect(h.coordinator.displayTime == "23:59")
        #expect(abs(h.coordinator.progress - 61.0 / 1500) < 1e-9)
        #expect(h.coordinator.phaseLabel == "Focus")
    }

    @Test(arguments: [
        (TimerState.idle, "25:00"),
        (.finished(phase: .work), "05:00"),
        (.finished(phase: .rest), "25:00"),
    ])
    func idleAndFinishedShowNextPhaseFullDuration(state: TimerState, expected: String) {
        let h = Harness(shortcuts: [], saved: state)
        defer { h.cleanUp() }

        #expect(h.coordinator.displayTime == expected)
    }

    @Test func idleDisplayFollowsPreferences() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.preferences.workMinutes = 50

        #expect(h.coordinator.displayTime == "50:00")
    }

    @Test func toggleCountdownFlipsPreference() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.coordinator.toggleCountdown()

        #expect(h.preferences.showCountdown == false)
    }

    // MARK: ticker

    @Test func tickerRunsOnlyWhileRunning() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        #expect(h.tickers.tickers.isEmpty)

        h.coordinator.start()
        #expect(h.tickers.active != nil)
        h.coordinator.pause()
        #expect(h.tickers.active == nil)
        h.coordinator.start()
        #expect(h.tickers.tickers.count == 2)
        #expect(h.tickers.active != nil)
        h.coordinator.start() // no-op while running: no second ticker
        #expect(h.tickers.tickers.count == 2)
    }

    @Test func tickerFiringFinishesThePhaseAndStopsTicking() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.coordinator.start()
        let ticker = h.tickers.active

        h.clock.advance(10)
        ticker?.fire()
        #expect(h.coordinator.displayTime == "24:50")

        h.clock.advance(1490)
        ticker?.fire()
        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.tickers.active == nil)
        #expect(h.alerts.chimes == [.workEnded])
    }

    @Test func wakeNotificationTicks() async throws {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.coordinator.start()
        h.clock.advance(3600)

        h.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        for _ in 0..<100 where h.coordinator.state != .finished(phase: .work) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.alerts.chimes == [.workEnded])
    }

    // MARK: restore at launch

    @Test func restoresRunningWorkAndReconcilesFocus() async {
        let running = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(600), total: 1500)
        let h = Harness(saved: running)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == running)
        #expect(h.coordinator.displayTime == "10:00")
        #expect(h.tickers.active != nil)
        #expect(h.focusRuns == [focusOn])
    }

    @Test func restoresExpiredWorkSilentlyAndTurnsFocusOff() async {
        let h = Harness(saved: .running(phase: .work, endDate: t0.addingTimeInterval(-1), total: 1500))
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.store.load() == .finished(phase: .work))
        #expect(h.tickers.active == nil)
        #expect(h.alerts.chimes.isEmpty)
        #expect(h.alerts.notifications.isEmpty)
        #expect(h.focusRuns == [focusOff])
    }

    @Test func restoresPausedWithoutResurrectingASession() async {
        let paused = TimerState.paused(phase: .work, remaining: 600, total: 1500)
        let h = Harness(saved: paused)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == paused)
        #expect(h.tickers.active == nil)
        #expect(h.runner.calls.isEmpty)
    }

    // MARK: focus failures and availability

    @Test func focusEffectsAreSkippedWhenShortcutsAreMissing() async {
        let h = Harness(shortcuts: [FocusController.onName])
        defer { h.cleanUp() }

        h.coordinator.start()
        h.coordinator.pause()
        h.coordinator.start()
        await h.settle()

        #expect(h.coordinator.focusAvailability == .missing(names: [FocusController.offName]))
        #expect(h.runner.calls.map(\.args) == [["list"]])
        #expect(h.coordinator.lastFocusError == nil)
        #expect(h.coordinator.state.isRunning)
    }

    @Test func failedFocusSetsErrorAndNextSuccessClearsIt() async {
        let h = Harness()
        defer { h.cleanUp() }
        let listing = bothShortcuts.joined(separator: "\n")
        h.runner.setHandler { _, args in
            args == ["list"]
                ? ShellResult(status: 0, stdout: listing, stderr: "")
                : ShellResult(status: 1, stdout: "", stderr: "Focus not allowed")
        }

        h.coordinator.start()
        await h.settle()
        #expect(h.coordinator.lastFocusError == "Focus shortcut failed: Focus not allowed")
        #expect(h.coordinator.state.isRunning)
        #expect(h.tickers.active != nil)

        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }
        h.coordinator.pause()
        await h.settle()
        #expect(h.coordinator.lastFocusError == nil)
    }

    @Test func focusTimeoutKeepsTimerRunning() async {
        let h = Harness()
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value
        h.runner.setHandler { _, _ in throw ShellError.timeout }

        h.coordinator.start()
        await h.settle()

        #expect(h.coordinator.lastFocusError == "Focus shortcut timed out")
        #expect(h.coordinator.state.isRunning)
    }

    @Test func refreshFocusAvailabilityUpdatesState() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        #expect(h.coordinator.focusAvailability == .unknown)

        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .missing(names: bothShortcuts))
    }

    // MARK: termination

    @Test func prepareForTerminationTurnsFocusOffWhileWorkRuns() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()

        h.coordinator.prepareForTermination()

        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.runner.calls.last?.timeout == 2)
    }

    @Test(arguments: [
        TimerState.idle,
        .paused(phase: .work, remaining: 600, total: 1500),
        .running(phase: .rest, endDate: t0.addingTimeInterval(60), total: 300),
        .finished(phase: .work),
    ])
    func prepareForTerminationDoesNothingOtherwise(state: TimerState) async {
        let h = Harness(saved: state)
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value

        h.coordinator.prepareForTermination()

        #expect(h.focusRuns.isEmpty)
    }
}

/// Set once from an observation callback.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

private extension TimerState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
