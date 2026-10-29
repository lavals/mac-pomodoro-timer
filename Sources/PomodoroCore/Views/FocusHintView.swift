import SwiftUI

/// One line in the popover saying the Focus shortcuts are missing or could not be checked,
/// with a "Set up…" button that opens the setup window. The timer works either way.
public struct FocusHintView: View {
    let availability: FocusAvailability
    let openSetup: () -> Void

    public init(availability: FocusAvailability, openSetup: @escaping () -> Void) {
        self.availability = availability
        self.openSetup = openSetup
    }

    public var body: some View {
        if let message = Self.message(for: availability) {
            HStack(spacing: 6) {
                Image(systemName: "moon")
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button("Set up…", action: openSetup)
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    /// The hint text, or nil when no hint should show (not checked yet, or both shortcuts exist).
    static func message(for availability: FocusAvailability) -> String? {
        switch availability {
        case .unknown, .available:
            return nil
        case .missing(let names) where names.count == 1:
            return "Shortcut “\(names[0])” not found"
        case .missing:
            return "Focus shortcuts not set up"
        case .error:
            return TimerPresentation.focusCheckFailed
        }
    }
}
