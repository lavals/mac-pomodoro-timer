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
    let tint: RingTint
    let controls: [MenuItem]
    let secondary: SecondaryAction?

    var testDescription: String { "\(state)" }
}

private let presentationTable: [PresentationCase] = [
    .init(state: .idle, action: .startFocus, title: "Start Focus", label: "Ready", tint: .secondary,
          controls: [], secondary: nil),
    .init(state: .running(phase: .work, endDate: end, total: 1500), action: .pause, title: "Pause",
          label: "Focus", tint: .accent, controls: [.skip, .reset], secondary: .skip),
    .init(state: .running(phase: .rest, endDate: end, total: 300), action: .pause, title: "Pause",
          label: "Break", tint: .green, controls: [.skip, .reset], secondary: .skip),
    .init(state: .paused(phase: .work, remaining: 60, total: 1500), action: .resume, title: "Resume",
          label: "Focus", tint: .accent, controls: [.skip, .reset], secondary: .skip),
    .init(state: .paused(phase: .rest, remaining: 60, total: 300), action: .resume, title: "Resume",
          label: "Break", tint: .green, controls: [.skip, .reset], secondary: .skip),
    .init(state: .finished(phase: .work), action: .startBreak, title: "Start Break", label: "Ready",
          tint: .secondary, controls: [.reset], secondary: .reset),
    .init(state: .finished(phase: .rest), action: .startFocus, title: "Start Focus", label: "Ready",
          tint: .secondary, controls: [.reset], secondary: .reset),
]

@Suite struct TimerPresentationTests {
    @Test(arguments: presentationTable)
    func mappings(_ row: PresentationCase) {
        #expect(TimerPresentation.primaryAction(for: row.state) == row.action)
        #expect(TimerPresentation.primaryActionTitle(for: row.state) == row.title)
        #expect(TimerPresentation.phaseLabel(for: row.state) == row.label)
        #expect(TimerPresentation.ringTint(for: row.state) == row.tint)
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

    @Test func secondaryActionTitles() {
        #expect(SecondaryAction.skip.title == "Skip")
        #expect(SecondaryAction.reset.title == "Reset")
    }

    @Test func ringTintColorsMatchTheMenuBarCountdown() {
        #expect(RingTint.accent.nsColor == StatusTitle.color(for: .work))
        #expect(RingTint.green.nsColor == StatusTitle.color(for: .rest))
        #expect(RingTint.secondary.nsColor == StatusTitle.color(for: nil))
    }

    @Test func progressRingClampsProgress() {
        #expect(ProgressRing.clamped(-0.5) == 0)
        #expect(ProgressRing.clamped(0.25) == 0.25)
        #expect(ProgressRing.clamped(1.5) == 1)
        #expect(ProgressRing.clamped(.nan) == 0)
    }

    @Test(arguments: [
        (FocusAvailability.unknown, false),
        (.available, false),
        (.missing(names: [FocusController.onName]), true),
        (.error("boom"), true),
    ])
    func focusHintShowsOnlyWhenShortcutsAreMissingOrFailed(_ availability: FocusAvailability, _ shows: Bool) {
        #expect(PopoverView.showsFocusHint(availability) == shows)
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

    @MainActor
    @Test func popoverIsTransientAndSizedByItsView() throws {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        let popover = StatusItemController.makePopover(coordinator: h.coordinator)

        #expect(popover.behavior == .transient)
        let hosting = try #require(popover.contentViewController as? NSHostingController<PopoverView>)
        #expect(hosting.sizingOptions == .preferredContentSize)
        let size = hosting.view.fittingSize
        #expect(size.width == 240)
        #expect(size.height >= 280)
    }
}
