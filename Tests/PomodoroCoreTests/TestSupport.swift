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

/// One-shot gate for holding a fake shell call open: `wait()` suspends until `open()`.
///
/// Use this, never `DispatchSemaphore.wait()`, in async code. A blocked thread is lost to the
/// cooperative pool (one thread per core, 3 on GitHub's macOS runners); a few blocked at once
/// starve every task in the test process, including `Task.sleep` wake-ups, and the run hangs.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let openAlready = lock.withLock {
                if !isOpen { waiters.append(continuation) }
                return isOpen
            }
            if openAlready { continuation.resume() }
        }
    }

    /// Releases every current and future waiter.
    func open() {
        let released = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in released { waiter.resume() }
    }
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
