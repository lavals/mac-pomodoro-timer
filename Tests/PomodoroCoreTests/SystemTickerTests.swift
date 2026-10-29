import Foundation
import Testing
@testable import PomodoroCore

/// The real one-second ticker. Runs the main run loop by hand, so it must stay on the main actor.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct SystemTickerTests {
    /// The status item's menu runs the main run loop in event-tracking mode; a timer scheduled
    /// only in the default mode would freeze the countdown while the menu is open.
    @Test func keepsFiringWhileAMenuIsTracking() {
        var fires = 0
        let ticker = SystemTicker { fires += 1 }
        defer { ticker.invalidate() }

        let deadline = Date().addingTimeInterval(5)
        while fires < 2, Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.1))
        }

        #expect(fires >= 2)
    }

    @Test func stopsFiringOnceInvalidated() {
        var fires = 0
        var controlFires = 0
        let ticker = SystemTicker { fires += 1 }
        // proves the run loop below does fire tickers that are not invalidated
        let control = SystemTicker { controlFires += 1 }
        defer { control.invalidate() }

        ticker.invalidate()
        let deadline = Date().addingTimeInterval(1.6)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.1)))
        }

        #expect(controlFires >= 1)
        #expect(fires == 0)
    }
}
