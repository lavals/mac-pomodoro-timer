import Foundation
@testable import PomodoroCore

/// Thread-safe ordered record of side effects, shared between fakes to check cross-fake ordering.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func append(_ event: String) {
        lock.withLock { recorded.append(event) }
    }

    var events: [String] {
        lock.withLock { recorded }
    }
}

/// Set once from an observation callback, which may run on another thread.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// Records chimes and notifications instead of playing sounds or posting real notifications.
@MainActor
final class FakeAlerts: Alerts {
    struct Notification: Equatable {
        let title: String
        let body: String
    }

    private(set) var chimes: [Chime] = []
    private(set) var notifications: [Notification] = []
    private let log: EventLog?

    init(log: EventLog? = nil) {
        self.log = log
    }

    func playChime(_ chime: Chime) {
        chimes.append(chime)
        log?.append("chime \(chime)")
    }

    func postNotification(title: String, body: String) {
        notifications.append(Notification(title: title, body: body))
        log?.append("notify \(title)")
    }
}

/// Ticker driven by hand: `fire()` stands in for one second passing.
@MainActor
final class FakeTicker: Ticker {
    private let onFire: @MainActor () -> Void
    private(set) var isInvalidated = false

    init(fire: @escaping @MainActor () -> Void) {
        onFire = fire
    }

    func fire() {
        onFire()
    }

    func invalidate() {
        isInvalidated = true
    }
}

/// Hands out `FakeTicker`s and remembers them.
@MainActor
final class FakeTickerFactory {
    private(set) var tickers: [FakeTicker] = []

    /// The ticker that is currently running, if any.
    var active: FakeTicker? {
        tickers.last.flatMap { $0.isInvalidated ? nil : $0 }
    }

    var make: TickerFactory {
        { [unowned self] fire in
            let ticker = FakeTicker(fire: fire)
            tickers.append(ticker)
            return ticker
        }
    }
}
