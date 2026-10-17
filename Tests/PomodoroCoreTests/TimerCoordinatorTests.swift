import AppKit
import Foundation
import Observation
import Testing
@testable import PomodoroCore

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
    ///   - savedData: raw bytes stored under the session key before launch (e.g. corrupt data).
    ///   - focusWasOn: whether the previous run left Focus turned on by the app.
    init(
        shortcuts: [String] = bothShortcuts,
        saved: TimerState? = nil,
        savedData: Data? = nil,
        focusWasOn: Bool = false
    ) {
        runner = FakeShellRunner.listing(shortcuts, log: log)
        alerts = FakeAlerts(log: log)
        preferences = Preferences(defaults: testDefaults.defaults)
        store = SessionStore(defaults: testDefaults.defaults)
        if let saved { store.save(saved) }
        if let savedData { testDefaults.defaults.set(savedData, forKey: SessionStore.Key.state) }
        store.focusTurnedOn = focusWasOn
        let clock = clock
        coordinator = TimerCoordinator(
            now: { clock.now },
            preferences: preferences,
            sessionStore: store,
            focus: FocusController(runner: runner),
            alerts: alerts,
            makeTicker: tickers.make,
            wakeCenter: wakeCenter,
            focusOffRetryDelay: .zero
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

    var primaryAction: PrimaryAction {
        TimerPresentation.primaryAction(for: coordinator.state)
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
        // start, pause; skipping the paused work phase and the rest phase leave Focus alone
        #expect(h.focusRuns == [focusOn, focusOff])
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

    @Test func performingTheShownPrimaryActionTogglesBetweenStartAndPause() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.coordinator.perform(.primary(h.primaryAction))
        #expect(h.primaryAction == .pause)
        h.coordinator.perform(.primary(h.primaryAction))
        #expect(h.primaryAction == .resume)
        h.coordinator.perform(.primary(h.primaryAction))
        #expect(h.primaryAction == .pause)
        await h.settle()
    }

    // MARK: display

    @Test func displayTimeFollowsTheClockAndNotifiesObservers() async {
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
        #expect(TimerPresentation.phaseLabel(for: h.coordinator.state) == "Focus")
        await h.settle()
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

    @Test func startUsesTheCurrentPreferenceDurations() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.preferences.workMinutes = 1
        h.preferences.restMinutes = 2

        h.coordinator.start()
        #expect(h.coordinator.state == .running(phase: .work, endDate: t0.addingTimeInterval(60), total: 60))
        #expect(h.coordinator.displayTime == "01:00")

        h.clock.advance(60)
        h.coordinator.tick()
        #expect(h.coordinator.displayTime == "02:00")
        h.coordinator.start()
        #expect(h.coordinator.state == .running(phase: .rest, endDate: t0.addingTimeInterval(180), total: 120))
        await h.settle()
    }

    @Test func longestAllowedSessionShowsItsFullLength() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.preferences.workMinutes = Preferences.minuteRange.upperBound
        #expect(h.coordinator.displayTime == "120:00")

        h.coordinator.start()
        #expect(h.coordinator.displayTime == "120:00")
        h.clock.advance(1)
        h.coordinator.tick()
        #expect(h.coordinator.displayTime == "119:59")
        await h.settle()
    }

    @Test func toggleCountdownFlipsPreference() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.coordinator.toggleCountdown()

        #expect(h.preferences.showCountdown == false)
    }

    // MARK: ticker

    @Test func tickerRunsOnlyWhileRunning() async {
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
        await h.settle()
    }

    @Test func tickerFiringFinishesThePhaseAndStopsTicking() async {
        let h = Harness()
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
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.alerts.notifications == [.init(title: "Focus finished", body: "Time for a break")])
    }

    @Test func finishedPhaseWaitsForTheUserToStartTheNext() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.coordinator.start()
        h.clock.advance(1500)
        h.coordinator.tick()
        #expect(h.coordinator.state == .finished(phase: .work))

        // more time, ticks and a wake never auto-start the break or chime again
        h.clock.advance(3600)
        h.coordinator.tick()
        h.wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        await h.settle()
        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.alerts.chimes == [.workEnded])
        #expect(h.alerts.notifications.count == 1)
        #expect(h.tickers.active == nil)
        #expect(h.primaryAction == .startBreak)

        h.coordinator.start()
        #expect(h.coordinator.state == .running(phase: .rest, endDate: h.clock.now.addingTimeInterval(300), total: 300))
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
        let h = Harness(saved: .running(phase: .work, endDate: t0.addingTimeInterval(-1), total: 1500), focusWasOn: true)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.store.load() == .finished(phase: .work))
        #expect(h.tickers.active == nil)
        #expect(h.alerts.chimes.isEmpty)
        #expect(h.alerts.notifications.isEmpty)
        #expect(h.focusRuns == [focusOff])
        #expect(h.store.focusTurnedOn == false)
    }

    @Test func restoresExpiredWorkWithoutTouchingAFocusTheAppDidNotTurnOn() async {
        let h = Harness(saved: .running(phase: .work, endDate: t0.addingTimeInterval(-1), total: 1500))
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.runner.calls.isEmpty)
    }

    @Test func restoresRunningWorkWithAStaleFlagTurnsFocusOnWithoutOffFirst() async {
        let running = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(600), total: 1500)
        let h = Harness(saved: running, focusWasOn: true)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.focusRuns == [focusOn])
        #expect(h.store.focusTurnedOn)
    }

    @Test func failedFocusOnAfterACrashKeepsTheFlagSoFocusIsTurnedOffLater() async {
        let running = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(600), total: 1500)
        let h = Harness(saved: running, focusWasOn: true)
        defer { h.cleanUp() }
        let listing = bothShortcuts.joined(separator: "\n")
        // set before the restore chain runs: the check passes, the On run fails
        h.runner.setHandler { _, args in
            args == ["list"]
                ? ShellResult(status: 0, stdout: listing, stderr: "")
                : ShellResult(status: 1, stdout: "", stderr: "busy")
        }
        await h.settle()
        #expect(h.focusRuns == [focusOn])
        #expect(h.store.focusTurnedOn)

        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }
        h.coordinator.skip()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.store.focusTurnedOn == false)
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

    @Test(arguments: [
        TimerState.paused(phase: .work, remaining: 600, total: 1500),
        .idle,
        .finished(phase: .work),
        .finished(phase: .rest),
        .running(phase: .rest, endDate: t0.addingTimeInterval(120), total: 300),
    ])
    func restoreWithAStaleFlagTurnsFocusOff(saved: TimerState) async {
        let h = Harness(saved: saved, focusWasOn: true)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == saved)
        #expect(h.focusRuns == [focusOff])
        #expect(h.store.focusTurnedOn == false)
    }

    @Test func restoreWithAStaleFlagAndExpiredWorkTurnsFocusOffOnce() async {
        let h = Harness(saved: .running(phase: .work, endDate: t0.addingTimeInterval(-1), total: 1500), focusWasOn: true)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.runner.calls.map(\.args) == [focusOff])
    }

    @Test func restoreWithoutAFlagLeavesFocusAlone() async {
        let h = Harness(saved: .idle)
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.runner.calls.isEmpty)
    }

    @Test func corruptSavedSessionIsIgnoredAndOverwritten() async {
        let h = Harness(savedData: Data("not a timer state".utf8))
        defer { h.cleanUp() }
        await h.settle()

        #expect(h.coordinator.state == .idle)
        #expect(h.coordinator.displayTime == "25:00")
        #expect(h.store.load() == .idle)
        #expect(h.tickers.active == nil)
        #expect(h.runner.calls.isEmpty)
        #expect(h.alerts.chimes.isEmpty)
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
        // each start re-checks; the pause has no Focus of the app's to turn off
        #expect(h.runner.calls.map(\.args) == [["list"], ["list"]])
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
        #expect(h.coordinator.lastFocusError == "Couldn't run the Focus shortcut: Focus not allowed")
        #expect(h.coordinator.state.isRunning)
        #expect(h.tickers.active != nil)

        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }
        // the failed On did not turn Focus on, so pausing leaves Focus alone
        h.coordinator.pause()
        await h.settle()
        #expect(h.focusRuns == [focusOn])
        h.coordinator.start()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOn])
        #expect(h.coordinator.lastFocusError == nil)
    }

    @Test func focusTimeoutKeepsTimerRunning() async {
        let h = Harness()
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value
        h.runner.setHandler { _, _ in throw ShellError.timeout }

        h.coordinator.start()
        await h.settle()

        #expect(h.coordinator.lastFocusError == "Couldn't run the Focus shortcut: timed out")
        #expect(h.coordinator.state.isRunning)
    }

    @Test func refreshFocusAvailabilityUpdatesState() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        #expect(h.coordinator.focusAvailability == .unknown)

        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .missing(names: bothShortcuts))
    }

    @Test func refreshFocusAvailabilityFindsBothShortcuts() async {
        let h = Harness()
        defer { h.cleanUp() }

        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .available)
        #expect(h.runner.calls.map(\.args) == [["list"]])
    }

    @Test func refreshFocusAvailabilityReportsTheOneMissingName() async {
        let h = Harness(shortcuts: [FocusController.offName, "Something Else"])
        defer { h.cleanUp() }

        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .missing(names: [FocusController.onName]))
    }

    @Test func refreshFocusAvailabilityReportsListErrors() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.runner.setHandler { _, _ in ShellResult(status: 1, stdout: "", stderr: "list failed") }

        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .error(.failed(status: 1, stderr: "list failed")))
    }

    @Test func refreshFocusAvailabilityPicksUpNewlyCreatedShortcuts() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value
        #expect(h.coordinator.focusAvailability == .missing(names: bothShortcuts))

        let listing = bothShortcuts.joined(separator: "\n")
        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: listing, stderr: "") }
        await h.coordinator.refreshFocusAvailability().value

        #expect(h.coordinator.focusAvailability == .available)
    }

    @Test func startWithMissingShortcutsRunsTheTimerWithoutRunningAShortcut() async {
        let h = Harness(shortcuts: [FocusController.onName])
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value

        h.coordinator.start()
        await h.settle()

        #expect(h.runner.calls.map(\.args) == [["list"], ["list"]])
        #expect(h.coordinator.lastFocusError == nil)
        #expect(h.coordinator.state.isRunning)
        #expect(h.tickers.active != nil)
    }

    // MARK: Focus Off follows what the app turned on

    @Test func focusOffStillRunsAfterAFailedCheckMidSession() async {
        let h = Harness()
        defer { h.cleanUp() }
        let listing = bothShortcuts.joined(separator: "\n")
        h.coordinator.start()
        await h.settle()

        // opening the popover runs a check that times out
        h.runner.setHandler { _, args in
            if args == ["list"] { throw ShellError.timeout }
            return ShellResult(status: 0, stdout: "", stderr: "")
        }
        await h.coordinator.refreshFocusAvailability().value
        #expect(h.coordinator.focusAvailability == .error(.timeout))

        h.coordinator.pause()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff])

        // the next start re-checks instead of trusting the stale error
        h.runner.setHandler { _, args in
            ShellResult(status: 0, stdout: args == ["list"] ? listing : "", stderr: "")
        }
        h.coordinator.start()
        await h.settle()
        #expect(h.coordinator.focusAvailability == .available)
        #expect(h.focusRuns == [focusOn, focusOff, focusOn])
    }

    @Test func startAfterATimedOutCheckRechecksBeforeSkippingFocus() async {
        let h = Harness()
        defer { h.cleanUp() }
        let listing = bothShortcuts.joined(separator: "\n")
        h.runner.setHandler { _, _ in throw ShellError.timeout }
        await h.coordinator.refreshFocusAvailability().value
        #expect(h.coordinator.focusAvailability == .error(.timeout))

        h.runner.setHandler { _, args in
            ShellResult(status: 0, stdout: args == ["list"] ? listing : "", stderr: "")
        }
        h.coordinator.start()
        await h.settle()

        #expect(h.runner.calls.map(\.args).suffix(2) == [["list"], focusOn])
        #expect(h.store.focusTurnedOn)
    }

    @Test func shortcutsAppearingMidSessionLeaveTheUsersFocusAlone() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()

        let listing = bothShortcuts.joined(separator: "\n")
        h.runner.setHandler { _, args in
            ShellResult(status: 0, stdout: args == ["list"] ? listing : "", stderr: "")
        }
        await h.coordinator.refreshFocusAvailability().value
        #expect(h.coordinator.focusAvailability == .available)

        h.coordinator.skip()
        await h.settle()
        #expect(h.focusRuns.isEmpty)
    }

    @Test func failedFocusOffIsRetriedOnce() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()
        let offAttempts = Counter()
        h.runner.setHandler { _, _ in
            offAttempts.increment() == 1
                ? ShellResult(status: 1, stdout: "", stderr: "busy")
                : ShellResult(status: 0, stdout: "", stderr: "")
        }

        h.coordinator.pause()
        await h.settle()

        #expect(h.focusRuns == [focusOn, focusOff, focusOff])
        #expect(h.coordinator.lastFocusError == nil)
        #expect(h.store.focusTurnedOn == false)
    }

    @Test func focusOffThatKeepsFailingIsTriedAgainAtQuit() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()
        h.runner.setHandler { _, _ in ShellResult(status: 1, stdout: "", stderr: "busy") }

        h.coordinator.pause()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff, focusOff])
        #expect(h.coordinator.lastFocusError == "Couldn't run the Focus shortcut: busy")
        #expect(h.store.focusTurnedOn)

        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }
        await h.coordinator.prepareForTermination()
        #expect(h.focusRuns == [focusOn, focusOff, focusOff, focusOff])
        #expect(h.store.focusTurnedOn == false)
    }

    @Test func failedFocusOnKeepsTheFlagAfterAFocusOffThatKeptFailing() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()
        h.runner.setHandler { _, _ in ShellResult(status: 1, stdout: "", stderr: "busy") }

        h.coordinator.pause()
        await h.settle()
        #expect(h.store.focusTurnedOn)

        // the On fails too: Focus is still on from before, so the flag must stay set
        h.coordinator.start()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff, focusOff, focusOn])
        #expect(h.store.focusTurnedOn)

        h.runner.setHandler { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }
        h.coordinator.skip()
        await h.settle()
        #expect(h.focusRuns == [focusOn, focusOff, focusOff, focusOn, focusOff])
        #expect(h.store.focusTurnedOn == false)
    }

    // MARK: dispatch

    @Test func performDispatchesTimerItems() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        h.coordinator.perform(.primary(.startFocus))
        #expect(h.coordinator.state.isRunning)
        h.coordinator.perform(.primary(.pause))
        #expect(h.coordinator.state == .paused(phase: .work, remaining: 1500, total: 1500))
        h.coordinator.perform(.skip)
        #expect(h.coordinator.state == .finished(phase: .work))
        h.coordinator.perform(.reset)
        #expect(h.coordinator.state == .idle)
        h.coordinator.perform(.toggleCountdown)
        #expect(h.preferences.showCountdown == false)

        // app-level entries are the caller's to handle
        for item in [MenuItem.settings, .quit, .separator] {
            h.coordinator.perform(item)
        }
        #expect(h.coordinator.state == .idle)
        #expect(h.preferences.showCountdown == false)
        await h.settle()
    }

    /// The menu is built when it opens and the timer keeps ticking while it is open: a `Pause`
    /// chosen after the phase finished must not start the next one.
    @Test func menuPauseChosenAfterThePhaseFinishedStartsNothing() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        let shown = TimerPresentation.menuItems(for: h.coordinator.state)
        #expect(shown.first == .primary(.pause))

        h.clock.advance(1500)
        h.tickers.active?.fire()
        #expect(h.coordinator.state == .finished(phase: .work))
        h.coordinator.perform(shown[0])
        await h.settle()

        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.focusRuns == [focusOn, focusOff])
    }

    /// A `Start Focus` chosen after the popover already started the phase must not pause it.
    @Test func menuStartChosenAfterThePhaseStartedKeepsItRunning() async {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        let shown = TimerPresentation.menuItems(for: h.coordinator.state)
        #expect(shown.first == .primary(.startFocus))

        h.coordinator.perform(.primary(h.primaryAction))
        h.coordinator.perform(shown[0])
        await h.settle()

        #expect(h.coordinator.state.isRunning)
    }

    /// The popover stays rendered while the timer ticks and captures its actions at render
    /// time: a `Pause` clicked after the phase finished must not start the break (or turn Focus
    /// on again), and a `Skip` clicked then must not change anything either.
    @Test func popoverActionsClickedAfterThePhaseFinishedDoNothing() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        let primary = TimerPresentation.primaryAction(for: h.coordinator.state)
        let secondary = TimerPresentation.secondaryAction(for: h.coordinator.state)
        #expect(primary == .pause)
        #expect(secondary == .skip)

        h.clock.advance(1500)
        h.tickers.active?.fire()
        #expect(h.coordinator.state == .finished(phase: .work))
        h.coordinator.perform(.primary(primary))
        if let secondary { h.coordinator.perform(secondary) }
        await h.settle()

        #expect(h.coordinator.state == .finished(phase: .work))
        #expect(h.store.load() == .finished(phase: .work))
        #expect(h.focusRuns == [focusOn, focusOff])
    }

    // MARK: termination

    @Test func prepareForTerminationTurnsFocusOffWhileWorkRuns() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()

        await h.coordinator.prepareForTermination()

        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.runner.calls.last?.timeout == .seconds(2))
        #expect(h.store.focusTurnedOn == false)
    }

    @Test func quittingRightAfterRestoreWaitsForFocusOnThenTurnsItOff() async {
        let running = TimerState.running(phase: .work, endDate: t0.addingTimeInterval(600), total: 1500)
        let h = Harness(saved: running)
        defer { h.cleanUp() }
        #expect(h.coordinator.focusAvailability == .unknown)

        await h.coordinator.prepareForTermination()

        #expect(h.runner.calls.map(\.args) == [["list"], focusOn, focusOff])
    }

    @Test func quittingRightAfterPauseLetsTheQueuedFocusOffRun() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()

        h.coordinator.pause()
        await h.coordinator.prepareForTermination()

        #expect(h.focusRuns == [focusOn, focusOff])
    }

    @Test func prepareForTerminationIsBoundedWhenTheShortcutHangs() async {
        let h = Harness()
        defer { h.cleanUp() }
        h.coordinator.start()
        await h.settle()
        // the Off run hangs until the test releases it
        let release = DispatchSemaphore(value: 0)
        let finished = Flag()
        h.runner.setHandler { _, _ in
            release.wait()
            finished.set()
            return ShellResult(status: 0, stdout: "", stderr: "")
        }

        await h.coordinator.prepareForTermination(chainBudget: .milliseconds(100), offBudget: .milliseconds(300))

        #expect(!finished.isSet)
        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.store.focusTurnedOn)
        release.signal()
    }

    @Test func quittingWhileFocusOnIsStillRunningKeepsTheFlagForTheNextLaunch() async {
        let h = Harness()
        defer { h.cleanUp() }
        // the On run hangs past the chain budget; the termination Off succeeds first
        let release = DispatchSemaphore(value: 0)
        let listing = bothShortcuts.joined(separator: "\n")
        h.runner.setHandler { _, args in
            if args == focusOn { release.wait() }
            return ShellResult(status: 0, stdout: args == ["list"] ? listing : "", stderr: "")
        }
        h.coordinator.start()

        await h.coordinator.prepareForTermination(chainBudget: .milliseconds(100), offBudget: .seconds(2))

        #expect(h.focusRuns == [focusOn, focusOff])
        #expect(h.store.focusTurnedOn)

        // the orphaned On finishes after the Off and leaves Focus on
        release.signal()
        await h.settle()
        #expect(h.store.focusTurnedOn)

        // next launch after the work phase expired turns Focus off
        let relaunch = TimerCoordinator(
            now: { t0.addingTimeInterval(2000) },
            preferences: h.preferences,
            sessionStore: h.store,
            focus: FocusController(runner: h.runner),
            alerts: h.alerts,
            makeTicker: h.tickers.make,
            wakeCenter: NotificationCenter(),
            focusOffRetryDelay: .zero
        )
        await relaunch.waitForPendingEffects()
        #expect(relaunch.state == .finished(phase: .work))
        #expect(h.focusRuns == [focusOn, focusOff, focusOff])
        #expect(h.store.focusTurnedOn == false)
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

        await h.coordinator.prepareForTermination()

        #expect(h.focusRuns.isEmpty)
    }

    @Test(arguments: [
        [FocusController.onName],
        nil, // `shortcuts list` fails
    ])
    func prepareForTerminationLeavesFocusAloneWhenTheAppNeverTurnedItOn(shortcuts: [String]?) async {
        let h = Harness(shortcuts: shortcuts ?? [])
        defer { h.cleanUp() }
        if shortcuts == nil {
            h.runner.setHandler { _, _ in ShellResult(status: 1, stdout: "", stderr: "list failed") }
        }
        h.coordinator.start()
        await h.settle()
        #expect(h.coordinator.focusAvailability != .available)

        await h.coordinator.prepareForTermination()

        #expect(h.focusRuns.isEmpty)
    }
}

private extension TimerState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
