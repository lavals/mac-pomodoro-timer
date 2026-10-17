import Foundation

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
