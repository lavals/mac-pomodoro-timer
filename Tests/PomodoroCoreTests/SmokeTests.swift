import Testing
@testable import PomodoroCore

@Suite(.timeLimit(.minutes(1))) struct SmokeTests {
    @Test func versionIsNonEmpty() {
        #expect(!AppInfo.version.isEmpty)
    }

    @Test func versionFallsBackToDev() {
        #expect(AppInfo.version(from: nil) == "dev")
        #expect(AppInfo.version(from: [:]) == "dev")
        #expect(AppInfo.version(from: ["CFBundleShortVersionString": ""]) == "dev")
    }

    @Test func versionReadsBundleValue() {
        #expect(AppInfo.version(from: ["CFBundleShortVersionString": "1.2.3"]) == "1.2.3")
    }
}
