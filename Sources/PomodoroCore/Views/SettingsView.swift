import SwiftUI

/// The settings window content: session lengths, countdown visibility and launch at login.
public struct SettingsView: View {
    @Bindable var preferences: Preferences
    let launchAtLogin: LaunchAtLoginModel

    public init(preferences: Preferences, launchAtLogin: LaunchAtLoginModel) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
    }

    public var body: some View {
        Form {
            Section {
                // the coordinator reads `preferences.durations` only in `start()`, so a running
                // session keeps its length and the new value applies to the next session
                Stepper(value: $preferences.workMinutes, in: Preferences.minuteRange) {
                    Text("Focus: \(preferences.workMinutes) min")
                }
                Stepper(value: $preferences.restMinutes, in: Preferences.minuteRange) {
                    Text("Break: \(preferences.restMinutes) min")
                }
            } footer: {
                Text("Changes apply to the next session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show countdown in menu bar", isOn: $preferences.showCountdown)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(!launchAtLogin.isAvailable)
                if let message = launchAtLogin.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
