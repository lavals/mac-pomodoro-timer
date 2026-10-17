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
    @ObservationIgnored private let wakeCenter: NotificationCenter?

    /// Restores the saved session, saves the reconciled state and performs the restore effects.
    ///
    /// - Parameter wakeCenter: where `NSWorkspace.didWakeNotification` is observed; nil disables it.
    public init(
        now clock: @escaping () -> Date = Date.init,
        preferences: Preferences,
        sessionStore: SessionStore,
        focus: FocusController,
        alerts: Alerts,
        makeTicker: @escaping TickerFactory = { SystemTicker(fire: $0) },
        wakeCenter: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.clock = clock
        self.preferences = preferences
        self.sessionStore = sessionStore
        self.focus = focus
        self.alerts = alerts
        self.makeTicker = makeTicker
        self.wakeCenter = wakeCenter
        let launchTime = clock()
        now = launchTime
        let (restored, effects) = TimerEngine.restore(sessionStore.load(), now: launchTime)
        engine = restored
        apply(effects)

        wakeObserver = wakeCenter?.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    isolated deinit {
        ticker?.invalidate()
        if let wakeObserver { wakeCenter?.removeObserver(wakeObserver) }
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

    public var phaseLabel: String { TimerPresentation.phaseLabel(for: engine.state) }

    public var primaryAction: PrimaryAction { TimerPresentation.primaryAction(for: engine.state) }

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

    /// Re-checks whether both Focus shortcuts exist. Returns the task so callers can await it.
    @discardableResult
    public func refreshFocusAvailability() -> Task<Void, Never> {
        Task { [weak self, focus] in
            let availability = await focus.availability()
            self?.focusAvailability = availability
        }
    }

    /// Turns Focus off synchronously before the app quits if a work phase is running.
    /// Blocks the caller for at most a couple of seconds.
    public func prepareForTermination() {
        guard case .running(.work, _, _) = engine.state, focusAvailability == .available else { return }
        let done = DispatchSemaphore(value: 0)
        let focus = self.focus
        Task.detached {
            _ = await focus.setFocus(false, timeout: 2)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2.5)
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

    /// Runs a Focus shortcut when both exist. The first call after launch checks availability.
    private func setFocus(_ on: Bool) async {
        if focusAvailability == .unknown {
            focusAvailability = await focus.availability()
        }
        guard focusAvailability == .available else { return }
        switch await focus.setFocus(on) {
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
