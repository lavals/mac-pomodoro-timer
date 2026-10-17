import Foundation

/// What the main button does in the current state.
public enum PrimaryAction: Equatable, Sendable {
    case startFocus, startBreak, resume, pause

    public var title: String {
        switch self {
        case .startFocus: return "Start Focus"
        case .startBreak: return "Start Break"
        case .resume: return "Resume"
        case .pause: return "Pause"
        }
    }
}

/// The popover's text button under the primary one.
public enum SecondaryAction: Equatable, Sendable {
    case skip, reset

    public var title: String {
        switch self {
        case .skip: return "Skip"
        case .reset: return "Reset"
        }
    }
}

/// Semantic tint for the progress ring and menu bar title; views map it to a system color.
public enum RingTint: Equatable, Sendable {
    /// `controlAccentColor`: a work phase.
    case accent
    /// `systemGreen`: a rest phase.
    case green
    /// `secondaryLabelColor`: nothing in progress.
    case secondary
}

/// One entry of the status item's right-click menu.
public enum MenuItem: Equatable, Sendable {
    case primary(PrimaryAction)
    case skip
    case reset
    case toggleCountdown
    case settings
    case quit
    case separator

    public var title: String {
        switch self {
        case .primary(let action): return action.title
        case .skip: return "Skip"
        case .reset: return "Reset"
        case .toggleCountdown: return "Show Countdown in Menu Bar"
        case .settings: return "Settings…"
        case .quit: return "Quit Pomodoro"
        case .separator: return ""
        }
    }
}

/// Pure mappings from timer state to what the UI shows. Shared by the popover, status item and menu.
public enum TimerPresentation {
    public static func primaryAction(for state: TimerState) -> PrimaryAction {
        switch state {
        case .idle, .finished(.rest): return .startFocus
        case .finished(.work): return .startBreak
        case .running: return .pause
        case .paused: return .resume
        }
    }

    public static func primaryActionTitle(for state: TimerState) -> String {
        primaryAction(for: state).title
    }

    /// The popover's secondary button: `Skip` while a phase is running or paused, `Reset` once it
    /// finished, none when idle. (The right-click menu offers both while in progress.)
    public static func secondaryAction(for state: TimerState) -> SecondaryAction? {
        switch state {
        case .running, .paused: return .skip
        case .finished: return .reset
        case .idle: return nil
        }
    }

    /// `Focus` / `Break` while a phase is running or paused, `Ready` otherwise.
    public static func phaseLabel(for state: TimerState) -> String {
        switch state {
        case .running(.work, _, _), .paused(.work, _, _): return "Focus"
        case .running(.rest, _, _), .paused(.rest, _, _): return "Break"
        case .idle, .finished: return "Ready"
        }
    }

    public static func ringTint(for state: TimerState) -> RingTint {
        switch state {
        case .running(.work, _, _), .paused(.work, _, _): return .accent
        case .running(.rest, _, _), .paused(.rest, _, _): return .green
        case .idle, .finished: return .secondary
        }
    }

    /// Menu entries for the state: primary action, the session controls that apply, then app items.
    public static func menuItems(for state: TimerState) -> [MenuItem] {
        let controls: [MenuItem]
        switch state {
        case .running, .paused: controls = [.skip, .reset]
        case .finished: controls = [.reset]
        case .idle: controls = []
        }
        return [.primary(primaryAction(for: state))] + controls
            + [.separator, .toggleCountdown, .settings, .separator, .quit]
    }

    /// One-line explanation of a failed Focus call for the popover.
    public static func focusErrorMessage(_ error: FocusError) -> String {
        switch error {
        case .notInstalled:
            return "Couldn't run the shortcuts tool"
        case .timeout:
            return "Focus shortcut timed out"
        case .failed(let status, let stderr):
            return stderr.isEmpty ? "Focus shortcut failed (exit \(status))" : "Focus shortcut failed: \(stderr)"
        }
    }
}
