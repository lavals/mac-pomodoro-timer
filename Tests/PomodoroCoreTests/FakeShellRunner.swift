import Foundation
@testable import PomodoroCore

/// Scripted `ShellRunner` that records every call and never starts a real process.
final class FakeShellRunner: ShellRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
        let timeout: Duration
    }

    /// Async so a handler can hold a call open with `await gate.wait()`. Never block a thread
    /// here: `run` executes on the shared cooperative pool, which has one thread per core.
    typealias Handler = @Sendable (_ executable: String, _ args: [String]) async throws -> ShellResult

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var handler: Handler

    /// By default every command succeeds with empty output.
    init(handler: @escaping Handler = { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }) {
        self.handler = handler
    }

    /// `shortcuts list` prints `names`, one per line; every other command succeeds. Each call is
    /// appended to `log` as `shell <args>`.
    static func listing(_ names: [String], log: EventLog? = nil) -> FakeShellRunner {
        FakeShellRunner { _, args in
            log?.append("shell \(args.joined(separator: " "))")
            let stdout = args == ["list"] ? names.joined(separator: "\n") + "\n" : ""
            return ShellResult(status: 0, stdout: stdout, stderr: "")
        }
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func setHandler(_ newHandler: @escaping Handler) {
        lock.withLock { handler = newHandler }
    }

    func run(_ executable: String, _ args: [String], timeout: Duration) async throws -> ShellResult {
        let current = lock.withLock {
            recorded.append(Call(executable: executable, args: args, timeout: timeout))
            return handler
        }
        return try await current(executable, args)
    }
}
