import Foundation

/// Whether the two Pomodoro shortcuts exist on this Mac.
public enum FocusAvailability: Equatable, Sendable {
    case unknown
    case available
    case missing(names: [String])
    case error(String)
}

/// Why turning Focus on or off failed.
public enum FocusError: Error, Equatable, Sendable {
    /// The `shortcuts` command line tool could not be started; carries the launch error.
    case launchFailed(String)
    /// The shortcut ran but exited with a non-zero status.
    case failed(status: Int32, stderr: String)
    /// The shortcut did not finish in time and was terminated.
    case timeout
}

/// Turns macOS Focus on and off by running two user-created shortcuts through `/usr/bin/shortcuts`.
public struct FocusController: Sendable {
    public static let onName = "Pomodoro Focus On"
    public static let offName = "Pomodoro Focus Off"
    static let executable = "/usr/bin/shortcuts"
    public static let defaultTimeout: TimeInterval = 5

    private let runner: ShellRunner

    public init(runner: ShellRunner = ProcessShellRunner()) {
        self.runner = runner
    }

    /// Checks `shortcuts list` for both shortcut names (each line trimmed, exact match).
    public func availability() async -> FocusAvailability {
        let result: ShellResult
        do {
            result = try await runner.run(Self.executable, ["list"], timeout: Self.defaultTimeout)
        } catch ShellError.timeout {
            return .error("shortcuts list timed out")
        } catch ShellError.launchFailed(let message) {
            return .error("shortcuts could not be started: \(message)")
        } catch {
            return .error(error.localizedDescription)
        }

        guard result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .error(detail.isEmpty ? "shortcuts list exited with status \(result.status)" : detail)
        }

        let installed = Set(result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = [Self.onName, Self.offName].filter { !installed.contains($0) }
        return missing.isEmpty ? .available : .missing(names: missing)
    }

    /// Runs the On or Off shortcut. Never throws: every failure comes back as a `FocusError`.
    public func setFocus(_ on: Bool, timeout: TimeInterval = defaultTimeout) async -> Result<Void, FocusError> {
        let name = on ? Self.onName : Self.offName
        do {
            let result = try await runner.run(Self.executable, ["run", name], timeout: timeout)
            guard result.status == 0 else {
                return .failure(.failed(
                    status: result.status,
                    stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            return .success(())
        } catch ShellError.timeout {
            return .failure(.timeout)
        } catch ShellError.launchFailed(let message) {
            return .failure(.launchFailed(message))
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}
