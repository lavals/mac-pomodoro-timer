import Foundation
import Testing
@testable import PomodoroCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000.25)

private let everyState: [TimerState] = [
    .idle,
    .running(phase: .work, endDate: t0.addingTimeInterval(1500), total: 1500),
    .running(phase: .rest, endDate: t0.addingTimeInterval(299.5), total: 300),
    .paused(phase: .work, remaining: 600.75, total: 1500),
    .paused(phase: .rest, remaining: 120, total: 300),
    .finished(phase: .work),
    .finished(phase: .rest),
]

@Suite struct SessionStoreTests {
    @Test(arguments: everyState)
    func saveLoadRoundTrip(_ state: TimerState) {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        SessionStore(defaults: testDefaults.defaults).save(state)

        #expect(SessionStore(defaults: testDefaults.defaults).load() == state)
    }

    @Test func saveReplacesPreviousState() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        let store = SessionStore(defaults: testDefaults.defaults)

        store.save(.idle)
        store.save(.finished(phase: .rest))

        #expect(store.load() == .finished(phase: .rest))
    }

    @Test func loadReturnsNilWhenEmpty() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }

        #expect(SessionStore(defaults: testDefaults.defaults).load() == nil)
    }

    @Test func loadReturnsNilOnCorruptData() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        testDefaults.defaults.set(Data("not json {".utf8), forKey: SessionStore.key)

        #expect(SessionStore(defaults: testDefaults.defaults).load() == nil)
    }

    @Test func loadReturnsNilOnWrongShape() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        testDefaults.defaults.set(Data(#"{"unknownCase":{}}"#.utf8), forKey: SessionStore.key)

        #expect(SessionStore(defaults: testDefaults.defaults).load() == nil)
    }

    @Test func loadReturnsNilWhenValueIsNotData() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        testDefaults.defaults.set("idle", forKey: SessionStore.key)

        #expect(SessionStore(defaults: testDefaults.defaults).load() == nil)
    }

    @Test func focusTurnedOnDefaultsToFalseAndPersists() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        #expect(SessionStore(defaults: testDefaults.defaults).focusTurnedOn == false)

        SessionStore(defaults: testDefaults.defaults).focusTurnedOn = true

        #expect(SessionStore(defaults: testDefaults.defaults).focusTurnedOn)
    }
}
