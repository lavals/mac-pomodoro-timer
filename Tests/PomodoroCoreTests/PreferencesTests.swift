import Foundation
import Testing
@testable import PomodoroCore

@Suite(.timeLimit(.minutes(1))) struct PreferencesTests {
    @Test func defaultsWhenSuiteIsEmpty() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let prefs = Preferences(defaults: testDefaults.defaults)

        #expect(prefs.workMinutes == 25)
        #expect(prefs.restMinutes == 5)
        #expect(prefs.showCountdown == true)
        #expect(prefs.durations == Durations(work: 1500, rest: 300))
    }

    @Test func valuesPersistAcrossInstances() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let prefs = Preferences(defaults: testDefaults.defaults)
        prefs.workMinutes = 50
        prefs.restMinutes = 10
        prefs.showCountdown = false

        let reloaded = Preferences(defaults: testDefaults.defaults)
        #expect(reloaded.workMinutes == 50)
        #expect(reloaded.restMinutes == 10)
        #expect(reloaded.showCountdown == false)
        #expect(reloaded.durations == Durations(work: 3000, rest: 600))
    }

    @Test(arguments: [(0, 1), (-5, 1), (1, 1), (120, 120), (500, 120)])
    func minuteSettersClamp(input: Int, expected: Int) {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let prefs = Preferences(defaults: testDefaults.defaults)
        prefs.workMinutes = input
        prefs.restMinutes = input

        #expect(prefs.workMinutes == expected)
        #expect(prefs.restMinutes == expected)

        let reloaded = Preferences(defaults: testDefaults.defaults)
        #expect(reloaded.workMinutes == expected)
        #expect(reloaded.restMinutes == expected)
    }

    @Test func outOfRangeStoredValuesAreClampedOnLoad() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        testDefaults.defaults.set(0, forKey: Preferences.Key.workMinutes)
        testDefaults.defaults.set(999, forKey: Preferences.Key.restMinutes)

        let prefs = Preferences(defaults: testDefaults.defaults)
        #expect(prefs.workMinutes == 1)
        #expect(prefs.restMinutes == 120)
    }

    @Test func changesAreObservable() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        let prefs = Preferences(defaults: testDefaults.defaults)
        let fired = Flag()
        withObservationTracking {
            _ = prefs.workMinutes
        } onChange: {
            fired.set()
        }
        prefs.workMinutes = 30
        #expect(fired.isSet)
    }

    @Test func durationsTotalPerPhase() {
        let durations = Durations(work: 1500, rest: 300)
        #expect(durations.total(for: .work) == 1500)
        #expect(durations.total(for: .rest) == 300)
    }
}
