import AppKit
import Foundation
import Testing
@testable import PomodoroCore

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
    .init(state: .running(phase: .work, endDate: t0, total: 1500), action: .pause, title: "Pause",
          label: "Focus", tint: .controlAccentColor, controls: [.skip, .reset], secondary: .skip),
    .init(state: .running(phase: .rest, endDate: t0, total: 300), action: .pause, title: "Pause",
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

@Suite(.timeLimit(.minutes(1))) struct TimerPresentationTests {
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
        #expect(TimerPresentation.focusErrorMessage(.timeout) == "Couldn't run the Focus shortcut: timed out")
        #expect(TimerPresentation.focusErrorMessage(.launchFailed("not found"))
            == "Couldn't run the shortcuts tool: not found")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 1, stderr: "nope"))
            == "Couldn't run the Focus shortcut: nope")
        #expect(TimerPresentation.focusErrorMessage(.failed(status: 2, stderr: ""))
            == "Couldn't run the Focus shortcut: exit status 2")
    }

    @Test func focusCheckErrorMessages() {
        #expect(TimerPresentation.focusCheckErrorMessage(.timeout) == "Couldn't check Focus shortcuts: timed out")
        #expect(TimerPresentation.focusCheckErrorMessage(.launchFailed("not found"))
            == "Couldn't run the shortcuts tool: not found")
        #expect(TimerPresentation.focusCheckErrorMessage(.failed(status: 1, stderr: "nope"))
            == "Couldn't check Focus shortcuts: nope")
        #expect(TimerPresentation.focusCheckErrorMessage(.failed(status: 2, stderr: ""))
            == "Couldn't check Focus shortcuts: exit status 2")
    }
}
