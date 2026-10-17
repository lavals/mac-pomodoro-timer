import AppKit
import SwiftUI

/// Explains how to create the two Focus shortcuts, opens the Shortcuts app and re-checks.
public struct FocusSetupView: View {
    let coordinator: TimerCoordinator

    static let shortcutsURL = URL(string: "shortcuts://")!
    static let guideURL = URL(string: "https://github.com/lavals/mac-pomodoro-timer/blob/main/docs/focus-shortcuts.md")!

    public init(coordinator: TimerCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        let availability = coordinator.focusAvailability
        let found = availability == .available
        VStack(alignment: .leading, spacing: 14) {
            Text("Pomodoro turns on a Focus while you work by running two shortcuts. Create them once in the Shortcuts app:")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("If Share Across Devices is on in System Settings › Focus, your iPhone goes quiet too.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link("Step-by-step guide", destination: Self.guideURL)
                .font(.caption)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: found ? "checkmark.circle.fill" : "moon")
                    .foregroundStyle(found ? Color.green : Color.secondary)
                Text(Self.statusText(for: availability))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }

            HStack {
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(Self.shortcutsURL)
                }
                Spacer()
                Button("Check again") {
                    coordinator.refreshFocusAvailability()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The numbered instructions, naming both shortcuts exactly as `FocusController` runs them.
    static let steps: [String] = [
        "Create a shortcut named “\(FocusController.onName)” with one action, Set Focus: turn Do Not Disturb (or your own Focus) On until Turned Off.",
        "Create a shortcut named “\(FocusController.offName)” with one action, Set Focus: turn the same Focus Off.",
        "Come back here and click Check again.",
    ]

    /// What the last availability check found.
    static func statusText(for availability: FocusAvailability) -> String {
        switch availability {
        case .unknown:
            return "Not checked yet."
        case .available:
            return "Both shortcuts found. Focus turns on during work sessions."
        case .missing(let names):
            return "Missing: " + names.map { "“\($0)”" }.joined(separator: ", ")
        case .error(let error):
            return TimerPresentation.focusCheckErrorMessage(error)
        }
    }
}
