import SwiftUI

/// The popover shown on left click: progress ring with the countdown, the primary action and
/// the secondary session control. Reads everything from the coordinator.
public struct PopoverView: View {
    let coordinator: TimerCoordinator
    let openSettings: () -> Void
    let openFocusSetup: () -> Void

    public init(
        coordinator: TimerCoordinator,
        openSettings: @escaping () -> Void = {},
        openFocusSetup: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        self.openFocusSetup = openFocusSetup
    }

    public var body: some View {
        let state = coordinator.state
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(
                    progress: coordinator.progress,
                    tint: TimerPresentation.ringTint(for: state).color
                )
                VStack(spacing: 2) {
                    Text(coordinator.displayTime)
                        .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                    Text(coordinator.phaseLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)

            Button {
                coordinator.performPrimaryAction()
            } label: {
                Text(coordinator.primaryAction.title)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack {
                // keeps the secondary button centered against the gear on the right
                Color.clear.frame(width: 20, height: 1)
                Spacer()
                if let secondary = TimerPresentation.secondaryAction(for: state) {
                    Button(secondary.title) { perform(secondary) }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .frame(width: 20)
            }
            .frame(height: 20)

            if Self.showsFocusHint(coordinator.focusAvailability) {
                FocusHintView(availability: coordinator.focusAvailability, openSetup: openFocusSetup)
            }

            if let error = coordinator.lastFocusError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(16)
        .frame(width: 240)
        .frame(minHeight: 280)
    }

    private func perform(_ action: SecondaryAction) {
        switch action {
        case .skip: coordinator.skip()
        case .reset: coordinator.reset()
        }
    }

    /// The Focus hint shows only once a check found the shortcuts missing or failed.
    static func showsFocusHint(_ availability: FocusAvailability) -> Bool {
        FocusHintView.message(for: availability) != nil
    }
}
