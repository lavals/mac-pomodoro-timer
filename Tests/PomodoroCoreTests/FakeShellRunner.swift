import Foundation
@testable import PomodoroCore

/// Scripted `ShellRunner` that records every call and never starts a real process.
final class FakeShellRunner: ShellRunner, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let args: [String]
        let timeout: TimeInterval
    }

    typealias Handler = @Sendable (_ executable: String, _ args: [String]) throws -> ShellResult

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var handler: Handler

    /// By default every command succeeds with empty output.
    init(handler: @escaping Handler = { _, _ in ShellResult(status: 0, stdout: "", stderr: "") }) {
        self.handler = handler
    }

    /// `shortcuts list` prints `names`, one per line; every other command succeeds.
    static func listing(_ names: [String]) -> FakeShellRunner {
        FakeShellRunner { _, args in
            let stdout = args == ["list"] ? names.joined(separator: "\n") + "\n" : ""
            return ShellResult(status: 0, stdout: stdout, stderr: "")
        }
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> ShellResult {
        let current = lock.withLock {
            recorded.append(Call(executable: executable, args: args, timeout: timeout))
            return handler
        }
        return try current(executable, args)
    }
}
