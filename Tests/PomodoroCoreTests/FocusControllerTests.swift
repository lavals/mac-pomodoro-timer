import Foundation
import Testing
@testable import PomodoroCore

@Suite struct FocusControllerTests {
    // MARK: availability

    @Test func bothShortcutsPresentIsAvailable() async {
        let runner = FakeShellRunner.listing(["Morning", FocusController.onName, FocusController.offName])

        #expect(await FocusController(runner: runner).availability() == .available)
        #expect(runner.calls == [.init(executable: "/usr/bin/shortcuts", args: ["list"], timeout: 5)])
    }

    @Test func namesAreTrimmedBeforeMatching() async {
        let runner = FakeShellRunner { _, _ in
            ShellResult(status: 0, stdout: "  Pomodoro Focus On \r\n\tPomodoro Focus Off\n", stderr: "")
        }

        #expect(await FocusController(runner: runner).availability() == .available)
    }

    @Test func oneShortcutMissingIsReported() async {
        let runner = FakeShellRunner.listing([FocusController.onName, "Pomodoro Focus Off copy"])

        #expect(await FocusController(runner: runner).availability() == .missing(names: ["Pomodoro Focus Off"]))
    }

    @Test func bothShortcutsMissingAreReportedInOrder() async {
        let runner = FakeShellRunner.listing([])

        #expect(await FocusController(runner: runner).availability()
            == .missing(names: ["Pomodoro Focus On", "Pomodoro Focus Off"]))
    }

    @Test func matchingIsExactNotPrefixOrCaseInsensitive() async {
        let runner = FakeShellRunner.listing(["pomodoro focus on", "Pomodoro Focus Off 2"])

        #expect(await FocusController(runner: runner).availability()
            == .missing(names: ["Pomodoro Focus On", "Pomodoro Focus Off"]))
    }

    @Test func listNonZeroExitIsErrorWithStderr() async {
        let runner = FakeShellRunner { _, _ in ShellResult(status: 1, stdout: "", stderr: "boom\n") }

        #expect(await FocusController(runner: runner).availability() == .error("boom"))
    }

    @Test func listNonZeroExitWithoutStderrMentionsStatus() async {
        let runner = FakeShellRunner { _, _ in ShellResult(status: 3, stdout: "", stderr: "") }

        #expect(await FocusController(runner: runner).availability()
            == .error("shortcuts list exited with status 3"))
    }

    @Test func listTimeoutIsError() async {
        let runner = FakeShellRunner { _, _ in throw ShellError.timeout }

        #expect(await FocusController(runner: runner).availability() == .error("shortcuts list timed out"))
    }

    @Test func listLaunchFailureIsError() async {
        let runner = FakeShellRunner { _, _ in throw ShellError.launchFailed("no such file") }

        #expect(await FocusController(runner: runner).availability()
            == .error("shortcuts could not be started: no such file"))
    }

    // MARK: setFocus

    @Test(arguments: [(true, "Pomodoro Focus On"), (false, "Pomodoro Focus Off")])
    func setFocusRunsTheMatchingShortcut(on: Bool, name: String) async {
        let runner = FakeShellRunner()

        let result = await FocusController(runner: runner).setFocus(on)

        #expect((try? result.get()) != nil)
        #expect(runner.calls == [.init(executable: "/usr/bin/shortcuts", args: ["run", name], timeout: 5)])
    }

    @Test func setFocusPassesCustomTimeout() async {
        let runner = FakeShellRunner()

        _ = await FocusController(runner: runner).setFocus(false, timeout: 2)

        #expect(runner.calls.map(\.timeout) == [2])
    }

    @Test func setFocusNonZeroExitCapturesStatusAndStderr() async {
        let runner = FakeShellRunner { _, _ in
            ShellResult(status: 1, stdout: "", stderr: "Error: shortcut failed\n")
        }

        let result = await FocusController(runner: runner).setFocus(true)

        #expect(result.failure == .failed(status: 1, stderr: "Error: shortcut failed"))
    }

    @Test func setFocusTimeoutMapsToTimeout() async {
        let runner = FakeShellRunner { _, _ in throw ShellError.timeout }

        #expect(await FocusController(runner: runner).setFocus(true).failure == .timeout)
    }

    @Test func setFocusLaunchFailureKeepsTheMessage() async {
        let runner = FakeShellRunner { _, _ in throw ShellError.launchFailed("no such file") }

        #expect(await FocusController(runner: runner).setFocus(false).failure == .launchFailed("no such file"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
