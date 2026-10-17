import AppKit
import Foundation
import Observation

/// A repeating one-second tick source. Invalidated when the timer stops running.
@MainActor
public protocol Ticker: AnyObject {
    func invalidate()
}

/// Creates a started `Ticker` that calls `fire` every second until invalidated.
public typealias TickerFactory = @MainActor (_ fire: @escaping @MainActor () -> Void) -> Ticker

/// `Foundation.Timer` on the main run loop in `.common` mode, so it keeps firing while the
/// status item's menu is open. Holds a user-initiated activity so App Nap does not delay the chime.
@MainActor
public final class SystemTicker: Ticker {
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    public init(fire: @escaping @MainActor () -> Void) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Pomodoro timer running"
        )
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            // scheduled on RunLoop.main, so the block always runs on the main thread
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func invalidate() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}

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
/// mid-session never leaves Focus on and a Focus the user turned on stays alone.
@MainActor
@Observable
public final class TimerCoordinator {
    /// Clock reading of the last tick or action. Stored so observers see a change every second
    /// even when the engine state does not change.
    public private(set) var now: Date
    public private(set) var engine: TimerEngine
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

    /// Pauses while running, otherwise starts or resumes.
    public func performPrimaryAction() {
        if case .running = engine.state { pause() } else { start() }
    }

    public func toggleCountdown() {
        preferences.showCountdown.toggle()
    }

    /// Performs a timer menu entry or popover button. `.settings`, `.quit` and `.separator` are
    /// app-level entries the caller handles, so they do nothing here.
    public func perform(_ item: MenuItem) {
        switch item {
        case .primary: performPrimaryAction()
        case .skip: skip()
        case .reset: reset()
        case .toggleCountdown: toggleCountdown()
        case .settings, .quit, .separator: break
        }
    }

    /// Re-checks whether both Focus shortcuts exist. Returns the task so callers can await it.
    @discardableResult
    public func refreshFocusAvailability() -> Task<Void, Never> {
        Task { [weak self, focus] in
            let availability = await focus.availability()
            self?.focusAvailability = availability
        }
    }

    /// Called before the app quits: lets queued Focus calls finish (at most `chainBudget`), then
    /// turns Focus off if the app turned it on (at most `offBudget`). Bounded so quitting never
    /// hangs on a stuck `shortcuts` run.
    ///
    /// When the chain is still running (e.g. a slow Focus On), that On may finish after the Off
    /// and switch Focus back on, so the flag stays set. The next launch then turns Focus off,
    /// whatever the saved state, unless a work phase is still running (it turns Focus on instead).
    public func prepareForTermination(
        chainBudget: Duration = .milliseconds(1500),
        offBudget: Duration = .seconds(2)
    ) async {
        var chainFinished = true
        if let pendingEffects {
            chainFinished = await Self.value(of: pendingEffects, within: chainBudget) != nil
        }
        guard sessionStore.focusTurnedOn else { return }
        let focus = self.focus
        let off = Task.detached {
            await focus.setFocus(false, timeout: offBudget / .seconds(1))
        }
        if case .success = await Self.value(of: off, within: offBudget), chainFinished {
            sessionStore.focusTurnedOn = false
        }
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
        case .focusOn: await setFocus(true)
        case .focusOff: await setFocus(false)
        case .postNotification(let title, let body): alerts.postNotification(title: title, body: body)
        case .playChime: break
        }
    }

    private func setFocus(_ on: Bool) async {
        if on { await turnFocusOn() } else { await turnFocusOff() }
    }

    /// Runs Focus On when both shortcuts exist, re-checking unless the last check found them.
    private func turnFocusOn() async {
        if focusAvailability != .available {
            focusAvailability = await focus.availability()
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
