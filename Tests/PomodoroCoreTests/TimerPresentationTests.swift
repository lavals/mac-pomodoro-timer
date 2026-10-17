import Foundation
import Testing
import UserNotifications
@testable import PomodoroCore

private let end = Date(timeIntervalSinceReferenceDate: 1_000_000)

struct PresentationCase: Sendable, CustomTestStringConvertible {
    let state: TimerState
    let action: PrimaryAction
    let title: String
    let label: String
    let tint: RingTint
    let controls: [MenuItem]

    var testDescription: String { "\(state)" }
}

private let presentationTable: [PresentationCase] = [
    .init(state: .idle, action: .startFocus, title: "Start Focus", label: "Ready", tint: .secondary,
          controls: []),
    .init(state: .running(phase: .work, endDate: end, total: 1500), action: .pause, title: "Pause",
          label: "Focus", tint: .accent, controls: [.skip, .reset]),
    .init(state: .running(phase: .rest, endDate: end, total: 300), action: .pause, title: "Pause",
          label: "Break", tint: .green, controls: [.skip, .reset]),
    .init(state: .paused(phase: .work, remaining: 60, total: 1500), action: .resume, title: "Resume",
          label: "Focus", tint: .accent, controls: [.skip, .reset]),
    .init(state: .paused(phase: .rest, remaining: 60, total: 300), action: .resume, title: "Resume",
          label: "Break", tint: .green, controls: [.skip, .reset]),
    .init(state: .finished(phase: .work), action: .startBreak, title: "Start Break", label: "Ready",
          tint: .secondary, controls: [.reset]),
    .init(state: .finished(phase: .rest), action: .startFocus, title: "Start Focus", label: "Ready",
          tint: .secondary, controls: [.reset]),
]

@Suite struct TimerPresentationTests {
    @Test(arguments: presentationTable)
    func mappings(_ row: PresentationCase) {
        #expect(TimerPresentation.primaryAction(for: row.state) == row.action)
        #expect(TimerPresentation.primaryActionTitle(for: row.state) == row.title)
        #expect(TimerPresentation.phaseLabel(for: row.state) == row.label)
        #expect(TimerPresentation.ringTint(for: row.state) == row.tint)
        #expect(TimerPresentation.menuItems(for: row.state)
            == [.primary(row.action)] + row.controls + [.separator, .toggleCountdown, .settings, .separator, .quit])
    }

    @Test func menuItemTitles() {
        #expect(MenuItem.primary(.startBreak).title == "Start Break")
        #expect(MenuItem.skip.title == "Skip")
        #expect(MenuItem.reset.title == "Reset")
        #expect(MenuItem.settings.title == "Settings…")
        #expect(MenuItem.quit.title == "Quit Pomodoro")
    }

    @Test func focusErrorMessages() {
        #expect(TimerPresentation.focusErrorMessage(.timeout) == "Focus shortcut timed out")
        #expect(TimerPresentation.focusErrorMessage(.notInstalled) == "Couldn't run the shortcuts tool")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 1, stderr: "nope"))
            == "Focus shortcut failed: nope")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 2, stderr: ""))
            == "Focus shortcut failed (exit 2)")
    }

    @Test func systemAlertsSoundNamesAndBundleGuard() {
        #expect(SystemAlerts.soundName(for: .workEnded) == "Glass")
        #expect(SystemAlerts.soundName(for: .restEnded) == "Tink")
        #expect(SystemAlerts.canUseNotifications(bundleIdentifier: nil) == false)
        #expect(SystemAlerts.canUseNotifications(bundleIdentifier: "com.lavals.pomodoro") == true)
    }

    @Test func notificationsShowAsBannerWhileActive() {
        #expect(AppDelegate.presentationOptions == [.banner, .list])
    }
}
