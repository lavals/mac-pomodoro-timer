import Foundation

/// Whether the two Pomodoro shortcuts exist on this Mac.
public enum FocusAvailability: Equatable, Sendable {
    case unknown
    case available
    case missing(names: [String])
    /// `shortcuts list` failed, so it is unknown whether the shortcuts exist.
    case error(FocusError)
}

/// Why a `shortcuts` call (listing the shortcuts, or turning Focus on or off) failed.
public enum FocusError: Error, Equatable, Sendable {
    /// The `shortcuts` command line tool could not be started; carries the launch error.
    case launchFailed(String)
    /// The command ran but exited with a non-zero status; carries its trimmed stderr.
    case failed(status: Int32, stderr: String)
    /// The command did not finish in time and was terminated.
    case timeout
}

/// Turns macOS Focus on and off by running two user-created shortcuts through `/usr/bin/shortcuts`.
public struct FocusController: Sendable {
    public static let onName = "Pomodoro Focus On"
    public static let offName = "Pomodoro Focus Off"
    static let executable = "/usr/bin/shortcuts"
    public static let defaultTimeout: Duration = .seconds(5)

    private let runner: ShellRunner

    public init(runner: ShellRunner = ProcessShellRunner()) {
        self.runner = runner
    }

    /// Checks `shortcuts list` for both shortcut names (each line trimmed, exact match).
    public func availability() async -> FocusAvailability {
        let result: ShellResult
        switch await run(["list"], timeout: Self.defaultTimeout) {
        case .success(let output): result = output
        case .failure(let error): return .error(error)
        }

        let installed = Set(result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = [Self.onName, Self.offName].filter { !installed.contains($0) }
        return missing.isEmpty ? .available : .missing(names: missing)
    }

    /// Runs the On or Off shortcut. Never throws: every failure comes back as a `FocusError`.
    public func setFocus(_ on: Bool, timeout: Duration = defaultTimeout) async -> Result<Void, FocusError> {
        await run(["run", on ? Self.onName : Self.offName], timeout: timeout).map { _ in () }
    }

    /// Runs `shortcuts` with `args`; a launch failure, timeout or non-zero exit becomes a `FocusError`.
    private func run(_ args: [String], timeout: Duration) async -> Result<ShellResult, FocusError> {
        let result: ShellResult
        do {
            result = try await runner.run(Self.executable, args, timeout: timeout)
        } catch {
            return .failure(Self.mapShellError(error))
        }
        guard result.status == 0 else {
            return .failure(.failed(
                status: result.status,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return .success(result)
    }

    private static func mapShellError(_ error: Error) -> FocusError {
        switch error {
        case ShellError.timeout: return .timeout
        case ShellError.launchFailed(let message): return .launchFailed(message)
        default: return .launchFailed(error.localizedDescription)
        }
    }
}
