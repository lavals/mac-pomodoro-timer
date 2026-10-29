import AppKit
import Foundation
import Observation

/// Owns the timer engine and performs its effects: chimes, Focus shortcuts and notifications.
///
/// Every mutating call saves the engine state first, then performs the returned effects.
/// Chimes play immediately. Focus calls and notifications run in order on a serial chain of
/// tasks, so a notification is posted only after the preceding Focus Off finished (Focus would
/// otherwise swallow it). The timer itself never waits on Focus.
///
/// Focus On runs only when both shortcuts exist (re-checked whenever the last check did not
/// find them). Focus Off runs only when the app turned Focus on itself
/// (`SessionStore.focusTurnedOn`), whatever the last availability check said, so a failed check
/// mid-session never leaves Focus on. A Focus the user turns on while no work phase runs stays
/// alone; one that was already on when work started is turned off with the app's own (the
/// current Focus state cannot be read, so the app cannot tell the two apart).
///
/// Availability checks may overlap (popover, setup window, Focus On); results apply in start
/// order, so an older check that finishes late never overwrites a newer one. Once
/// `prepareForTermination` starts, timer actions and ticks do nothing, so no Focus call is
/// queued behind the termination Off.
@MainActor
@Observable
public final class TimerCoordinator {
    /// Clock reading of the last tick or action. Stored so observers see a change every second
    /// even when the engine state does not change.
    private var now: Date
    private var engine: TimerEngine
    /// Whether both Focus shortcuts exist. `.unknown` until the first check.
    public private(set) var focusAvailability: FocusAvailability = .unknown
    /// Message of the last failed Focus call; cleared by the next successful one.
    public private(set) var lastFocusError: String?

    public let preferences: Preferences

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sessionStore: SessionStore
    @ObservationIgnored private let focus: FocusController
    @ObservationIgnored private let alerts: Alerts
    @ObservationIgnored private let makeTicker: TickerFactory
    @ObservationIgnored private var ticker: Ticker?
    @ObservationIgnored private var pendingEffects: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let wakeCenter: NotificationCenter
    @ObservationIgnored private let focusOffRetryDelay: Duration
    /// Number of the last availability check started / applied (see `applyAvailability`).
    @ObservationIgnored private var availabilityChecksStarted = 0
    @ObservationIgnored private var availabilityCheckApplied = 0
    /// Set when `prepareForTermination` starts; timer actions and ticks are ignored from then on.
    @ObservationIgnored private(set) var isTerminating = false

    /// Restores the saved session, saves the reconciled state and performs the restore effects.
    /// If the last run left `SessionStore.focusTurnedOn` set and no work phase is still running,
    /// Focus is turned off.
    ///
    /// - Parameters:
    ///   - wakeCenter: where `NSWorkspace.didWakeNotification` is observed.
    ///   - focusOffRetryDelay: pause before the one retry of a failed Focus Off.
    public init(
        now clock: @escaping () -> Date = Date.init,
        preferences: Preferences,
        sessionStore: SessionStore,
        focus: FocusController,
        alerts: Alerts,
        makeTicker: @escaping TickerFactory = { SystemTicker(fire: $0) },
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        focusOffRetryDelay: Duration = .seconds(2)
    ) {
        self.clock = clock
        self.preferences = preferences
        self.sessionStore = sessionStore
        self.focus = focus
        self.alerts = alerts
        self.makeTicker = makeTicker
        self.wakeCenter = wakeCenter
        self.focusOffRetryDelay = focusOffRetryDelay
        let launchTime = clock()
        now = launchTime
        var (restored, effects) = TimerEngine.restore(sessionStore.load(), now: launchTime)
        // a flag left set by the last run (quit race, crash before a queued Off) means Focus may
        // still be on; turn it off unless a work phase is still running or restore already does
        if sessionStore.focusTurnedOn, !effects.contains(.focusOn), !effects.contains(.focusOff) {
            effects.append(.focusOff)
        }
        engine = restored
        apply(effects)

        wakeObserver = wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    isolated deinit {
        ticker?.invalidate()
        if let wakeObserver { wakeCenter.removeObserver(wakeObserver) }
    }

    // MARK: derived state

    public var state: TimerState { engine.state }

    /// `mm:ss` left in the current phase. When idle or finished it shows the full length of the
    /// phase `start()` would begin (e.g. `25:00`), not `00:00`.
    public var displayTime: String {
        switch engine.state {
        case .idle, .finished:
            return formatRemaining(preferences.durations.total(for: engine.nextPhase))
        case .running, .paused:
            return formatRemaining(engine.remaining(now: now))
        }
    }

    /// Elapsed fraction of the current phase in 0...1.
    public var progress: Double { engine.progress(now: now) }

    // MARK: actions

    /// Starts the next phase with the current preferences, or resumes a paused one.
    public func start() {
        mutate { $0.start(now: $1, durations: preferences.durations) }
    }

    public func pause() {
        mutate { $0.pause(now: $1) }
    }

    public func skip() {
        mutate { $0.skip(now: $1) }
    }

    public func reset() {
        mutate { engine, _ in engine.reset() }
    }

    /// Advances the clock and finishes the running phase if its end date passed.
    public func tick() {
        mutate { $0.tick(now: $1) }
    }

    public func toggleCountdown() {
        preferences.showCountdown.toggle()
    }

    /// Performs a timer menu entry or popover button. `.settings`, `.quit` and `.separator` are
    /// app-level entries the caller handles, so they do nothing here.
    ///
    /// Callers pass the item they showed, not one derived again at click time: a primary entry
    /// does what its title said when it was shown, even if the state changed since (a menu stays
    /// open and a popover stays rendered while the timer ticks): `Pause` on a phase that already
    /// finished does nothing instead of starting the next one.
    public func perform(_ item: MenuItem) {
        switch item {
        case .primary(.startFocus), .primary(.startBreak), .primary(.resume): start()
        case .primary(.pause): pause()
        case .skip: skip()
        case .reset: reset()
        case .toggleCountdown: toggleCountdown()
        case .settings, .quit, .separator: break
        }
    }

    /// Re-checks whether both Focus shortcuts exist. Returns the task so callers can await it.
    /// The result is dropped if a check started later has already been applied.
    @discardableResult
    public func refreshFocusAvailability() -> Task<Void, Never> {
        let check = startAvailabilityCheck()
        return Task { [weak self, focus] in
            let availability = await focus.availability()
            self?.applyAvailability(availability, check: check)
        }
    }

    /// Numbers a new availability check in start order.
    private func startAvailabilityCheck() -> Int {
        availabilityChecksStarted += 1
        return availabilityChecksStarted
    }

    /// Applies a check's result unless a check started after it was applied already.
    private func applyAvailability(_ availability: FocusAvailability, check: Int) {
        guard check > availabilityCheckApplied else { return }
        availabilityCheckApplied = check
        focusAvailability = availability
    }

    /// Called before the app quits: from here on timer actions and ticks do nothing (so nothing
    /// new is queued behind the Off), then lets queued Focus calls finish (at most `chainBudget`),
    /// then turns Focus off if the app turned it on (at most `offBudget`). An Off that failed (not
    /// one that timed out: a stuck `shortcuts` run will not recover in time) is retried once
    /// after `retryDelay`, again within `offBudget`. Bounded so quitting never hangs on a stuck
    /// `shortcuts` run: with the defaults at most 1.5 + 2 + 0.5 + 2 = 6s, under the 10s
    /// Homebrew waits for the app to quit.
    ///
    /// When the chain is still running (e.g. a slow Focus On), that On may finish after the Off
    /// and switch Focus back on, so the flag stays set. The next launch then turns Focus off,
    /// whatever the saved state, unless a work phase is still running (it turns Focus on instead).
    public func prepareForTermination(
        chainBudget: Duration = .milliseconds(1500),
        offBudget: Duration = .seconds(2),
        retryDelay: Duration = .milliseconds(500)
    ) async {
        isTerminating = true
        var chainFinished = true
        if let pendingEffects {
            chainFinished = await Self.value(of: pendingEffects, within: chainBudget) != nil
        }
        guard sessionStore.focusTurnedOn else { return }
        var result = await focusOff(within: offBudget)
        if case .failure(let error)? = result, error != .timeout {
            try? await Task.sleep(for: retryDelay)
            result = await focusOff(within: offBudget)
        }
        if case .success? = result, chainFinished {
            sessionStore.focusTurnedOn = false
        }
    }

    /// Runs Focus Off detached; nil if it did not finish within `budget` (the run keeps going).
    private func focusOff(within budget: Duration) async -> Result<Void, FocusError>? {
        let focus = self.focus
        let off = Task.detached {
            await focus.setFocus(false, timeout: budget)
        }
        return await Self.value(of: off, within: budget)
    }

    /// The task's value, or nil if it did not finish within `budget`. The task keeps running.
    private static func value<T: Sendable>(of task: Task<T, Never>, within budget: Duration) async -> T? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: budget)
                once.resume(nil)
            }
            Task {
                let value = await task.value
                timer.cancel()
                once.resume(value)
            }
        }
    }

    /// Waits until every queued Focus call and notification has been performed.
    func waitForPendingEffects() async {
        await pendingEffects?.value
    }

    // MARK: effects

    private func mutate(_ transition: (inout TimerEngine, Date) -> [Effect]) {
        guard !isTerminating else { return }
        now = clock()
        let effects = transition(&engine, now)
        apply(effects)
    }

    /// Saves the state, (re)starts or stops the ticker, then performs `effects`.
    private func apply(_ effects: [Effect]) {
        sessionStore.save(engine.state)
        syncTicker()

        var queued: [Effect] = []
        for effect in effects {
            if case .playChime(let chime) = effect {
                alerts.playChime(chime)
            } else {
                queued.append(effect)
            }
        }
        guard !queued.isEmpty else { return }
        let previous = pendingEffects
        pendingEffects = Task { [weak self] in
            await previous?.value
            for effect in queued {
                await self?.performQueued(effect)
            }
        }
    }

    private func performQueued(_ effect: Effect) async {
        switch effect {
        case .focusOn: await turnFocusOn()
        case .focusOff: await turnFocusOff()
        case .postNotification(let title, let body): alerts.postNotification(title: title, body: body)
        case .playChime: break
        }
    }

    /// Runs Focus On when both shortcuts exist, re-checking unless the last check found them.
    private func turnFocusOn() async {
        if focusAvailability != .available {
            let check = startAvailabilityCheck()
            let availability = await focus.availability()
            applyAvailability(availability, check: check)
        }
        guard focusAvailability == .available else { return }
        // marked before the run so a quit while it is in flight still turns Focus off
        let wasOn = sessionStore.focusTurnedOn
        sessionStore.focusTurnedOn = true
        let result = await focus.setFocus(true)
        // a timed-out run may still have switched Focus on; any other failure did not, so the
        // flag goes back to what it was (Focus may still be on from an earlier failed Off)
        if case .failure(let error) = result, error != .timeout {
            sessionStore.focusTurnedOn = wasOn
        }
        record(result)
    }

    /// Runs Focus Off if the app turned Focus on, retrying once after a failure.
    private func turnFocusOff() async {
        guard sessionStore.focusTurnedOn else { return }
        var result = await focus.setFocus(false)
        if case .failure = result {
            try? await Task.sleep(for: focusOffRetryDelay)
            result = await focus.setFocus(false)
        }
        if case .success = result {
            sessionStore.focusTurnedOn = false
        }
        record(result)
    }

    private func record(_ result: Result<Void, FocusError>) {
        switch result {
        case .success: lastFocusError = nil
        case .failure(let error): lastFocusError = TimerPresentation.focusErrorMessage(error)
        }
    }

    private func syncTicker() {
        if case .running = engine.state {
            guard ticker == nil else { return }
            ticker = makeTicker { [weak self] in self?.tick() }
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }
}

/// Resumes a continuation once; later calls are ignored.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
