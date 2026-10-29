import Foundation

/// An isolated `UserDefaults` suite for one test.
///
/// Swift Testing runs tests in parallel and has no teardown, so every test creates its own
/// suite and removes it with `defer { testDefaults.cleanUp() }`.
struct TestDefaults {
    let suiteName = "PomodoroTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
