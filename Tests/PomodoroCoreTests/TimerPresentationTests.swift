import AppKit
import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import PomodoroCore

private let end = Date(timeIntervalSinceReferenceDate: 1_000_000)

struct PresentationCase: Sendable, CustomTestStringConvertible {
    let state: TimerState
    let action: PrimaryAction
    let title: String
    let label: String
    let tint: NSColor
    let controls: [MenuItem]
    let secondary: MenuItem?

    var testDescription: String { "\(state)" }
}

private let presentationTable: [PresentationCase] = [
    .init(state: .idle, action: .startFocus, title: "Start Focus", label: "Ready", tint: .secondaryLabelColor,
          controls: [], secondary: nil),
    .init(state: .running(phase: .work, endDate: end, total: 1500), action: .pause, title: "Pause",
          label: "Focus", tint: .controlAccentColor, controls: [.skip, .reset], secondary: .skip),
    .init(state: .running(phase: .rest, endDate: end, total: 300), action: .pause, title: "Pause",
          label: "Break", tint: .systemGreen, controls: [.skip, .reset], secondary: .skip),
    .init(state: .paused(phase: .work, remaining: 60, total: 1500), action: .resume, title: "Resume",
          label: "Focus", tint: .controlAccentColor, controls: [.skip, .reset], secondary: .skip),
    .init(state: .paused(phase: .rest, remaining: 60, total: 300), action: .resume, title: "Resume",
          label: "Break", tint: .systemGreen, controls: [.skip, .reset], secondary: .skip),
    .init(state: .finished(phase: .work), action: .startBreak, title: "Start Break", label: "Ready",
          tint: .secondaryLabelColor, controls: [.reset], secondary: .reset),
    .init(state: .finished(phase: .rest), action: .startFocus, title: "Start Focus", label: "Ready",
          tint: .secondaryLabelColor, controls: [.reset], secondary: .reset),
]

@Suite struct TimerPresentationTests {
    @Test(arguments: presentationTable)
    func mappings(_ row: PresentationCase) {
        #expect(TimerPresentation.primaryAction(for: row.state) == row.action)
        #expect(TimerPresentation.primaryAction(for: row.state).title == row.title)
        #expect(TimerPresentation.phaseLabel(for: row.state) == row.label)
        #expect(TimerPresentation.tint(for: row.state) == row.tint)
        #expect(TimerPresentation.secondaryAction(for: row.state) == row.secondary)
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
        #expect(TimerPresentation.focusErrorMessage(.launchFailed("not found"))
            == "Couldn't run the shortcuts tool: not found")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 1, stderr: "nope"))
            == "Focus shortcut failed: nope")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 2, stderr: ""))
            == "Focus shortcut failed (exit 2)")
    }

    @Test(arguments: [Chime.workEnded, .restEnded])
    func systemAlertsSoundsExist(_ chime: Chime) {
        // loads the system sound without playing it
        #expect(NSSound(named: NSSound.Name(SystemAlerts.soundName(for: chime))) != nil)
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

    @MainActor
    @Test func popoverIsTransientAndSizedByItsView() throws {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        let popover = StatusItemController.makePopover(coordinator: h.coordinator, openSettings: {}, openFocusSetup: {})

        #expect(popover.behavior == .transient)
        let hosting = try #require(popover.contentViewController as? NSHostingController<PopoverView>)
        #expect(hosting.sizingOptions == .preferredContentSize)
        let size = hosting.view.fittingSize
        #expect(size.width == 240)
        #expect(size.height >= 280)
    }
}
