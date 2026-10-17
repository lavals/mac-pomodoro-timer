import Foundation

/// Exit status and captured output of a finished command.
public struct ShellResult: Equatable, Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Errors a `ShellRunner` throws instead of returning a result.
public enum ShellError: Error, Equatable, Sendable {
    /// The command did not finish within its timeout and was terminated.
    case timeout
    /// The executable could not be started (missing, not executable, ...).
    case launchFailed(String)
}

/// Runs an external command. A protocol so tests can replace the real process with a fake.
public protocol ShellRunner: Sendable {
    func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> ShellResult
}

/// Runs commands with `Foundation.Process`.
///
/// stdout and stderr are drained on background queues while the process runs, so a child that
/// writes more than a pipe buffer never blocks. When the timeout fires first the process is
/// terminated and the call throws `ShellError.timeout` without waiting for the pipes to close.
public struct ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let context = RunContext(continuation: continuation)
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let readers = DispatchGroup()
            process.terminationHandler = { finished in
                readers.notify(queue: .global()) {
                    context.finish(.success(ShellResult(
                        status: finished.terminationStatus,
                        stdout: String(decoding: context.stdout, as: UTF8.self),
                        stderr: String(decoding: context.stderr, as: UTF8.self)
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                context.finish(.failure(ShellError.launchFailed(error.localizedDescription)))
                return
            }

            readers.enter()
            DispatchQueue.global().async {
                context.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global().async {
                context.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard context.finish(.failure(ShellError.timeout)) else { return }
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Shared state for one `ProcessShellRunner.run` call. The continuation is resumed exactly once,
/// by whichever of termination, launch failure or timeout gets there first.
private final class RunContext: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ShellResult, Error>?
    // Each buffer is written by one reader before `readers` is notified and read only afterwards.
    var stdout = Data()
    var stderr = Data()

    init(continuation: CheckedContinuation<ShellResult, Error>) {
        self.continuation = continuation
    }

    /// Resumes the continuation if nobody has yet; returns whether this call did it.
    @discardableResult
    func finish(_ result: Result<ShellResult, Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return false }
        pending.resume(with: result)
        return true
    }
}
