import Foundation
import Testing
@testable import PomodoroCore

@Suite(.timeLimit(.minutes(1))) struct TimeFormattingTests {
    @Test(arguments: [
        (0.0, "00:00"),
        (59.0, "00:59"),
        (60.0, "01:00"),
        (1500.0, "25:00"),
        (1499.6, "25:00"),
        (1499.0, "24:59"),
        (0.2, "00:01"),
        (5999.0, "99:59"),
        (6000.0, "100:00"),
        (7199.5, "120:00"),
        (7200.0, "120:00"),
        (1_000_000.0, "999:59"),
        (-5.0, "00:00"),
    ])
    func formats(seconds: TimeInterval, expected: String) {
        #expect(formatRemaining(seconds) == expected)
    }

    @Test func longestAllowedSessionIsNotCapped() {
        let longest = TimeInterval(Preferences.minuteRange.upperBound * 60)
        #expect(formatRemaining(longest) == "\(Preferences.minuteRange.upperBound):00")
        #expect(formatRemaining(longest - 1) == "\(Preferences.minuteRange.upperBound - 1):59")
    }

    @Test func nonFiniteValues() {
        #expect(formatRemaining(.nan) == "00:00")
        #expect(formatRemaining(.infinity) == "999:59")
        #expect(formatRemaining(-.infinity) == "00:00")
    }
}
