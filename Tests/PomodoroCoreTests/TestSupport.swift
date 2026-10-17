import Foundation

/// Shared fixed instant for timer tests.
let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

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

/// Thread-safe call counter for scripted shell handlers.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Increments and returns the new value.
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
