import Foundation
import Testing
@testable import PomodoroCore

/// Exercises the real `Process` plumbing with `/bin/sh -c`, never with `/usr/bin/shortcuts`.
@Suite struct ProcessShellRunnerTests {
    private let runner = ProcessShellRunner()

    private func sh(_ script: String, timeout: TimeInterval = 10) async throws -> ShellResult {
        try await runner.run("/bin/sh", ["-c", script], timeout: timeout)
    }

    @Test func capturesStdoutAndStderrSeparately() async throws {
        let result = try await sh("printf 'out line\\n'; printf 'err line\\n' >&2")

        #expect(result == ShellResult(status: 0, stdout: "out line\n", stderr: "err line\n"))
    }

    @Test func reportsNonZeroStatus() async throws {
        let result = try await sh("echo failing >&2; exit 7")

        #expect(result.status == 7)
        #expect(result.stderr == "failing\n")
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let size = 1_048_576
        let result = try await sh("head -c \(size) /dev/zero | tr '\\0' 'a'; head -c \(size) /dev/zero | tr '\\0' 'b' >&2")

        #expect(result.status == 0)
        #expect(result.stdout.utf8.count == size)
        #expect(result.stderr.utf8.count == size)
    }

    @Test func slowCommandTimesOut() async throws {
        let started = Date()

        await #expect(throws: ShellError.timeout) {
            try await sh("sleep 5", timeout: 0.2)
        }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func missingExecutableFailsToLaunch() async {
        await #expect {
            try await runner.run("/nonexistent/definitely-not-here", [], timeout: 1)
        } throws: { error in
            if case ShellError.launchFailed = error { return true }
            return false
        }
    }
}
