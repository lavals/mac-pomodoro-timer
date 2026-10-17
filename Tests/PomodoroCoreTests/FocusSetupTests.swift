import AppKit
import SwiftUI
import Testing
@testable import PomodoroCore

@Suite struct FocusHintTests {
    @Test(arguments: [
        (FocusAvailability.unknown, String?.none),
        (.available, nil),
        (.missing(names: [FocusController.offName]), "Shortcut “Pomodoro Focus Off” not found"),
        (.missing(names: [FocusController.onName, FocusController.offName]), "Focus shortcuts not set up"),
        (.error("boom"), "Couldn't check Focus shortcuts"),
    ])
    func hintMessagePerAvailability(_ availability: FocusAvailability, _ expected: String?) {
        #expect(FocusHintView.message(for: availability) == expected)
        #expect(PopoverView.showsFocusHint(availability) == (expected != nil))
    }
}

@MainActor
@Suite struct FocusSetupTests {
    @Test func stepsNameBothShortcutsExactly() {
        let text = FocusSetupView.steps.joined(separator: "\n")
        #expect(text.contains("“\(FocusController.onName)”"))
        #expect(text.contains("“\(FocusController.offName)”"))
        #expect(text.contains("Set Focus"))
    }

    @Test func linksOpenShortcutsAndTheGuide() {
        #expect(FocusSetupView.shortcutsURL.absoluteString == "shortcuts://")
        #expect(FocusSetupView.guideURL.absoluteString.hasSuffix("docs/focus-shortcuts.md"))
    }

    @Test(arguments: [
        (FocusAvailability.unknown, "Not checked yet."),
        (.available, "Both shortcuts found. Focus turns on during work sessions."),
        (.missing(names: [FocusController.onName]), "Missing: “Pomodoro Focus On”"),
        (.missing(names: [FocusController.onName, FocusController.offName]),
         "Missing: “Pomodoro Focus On”, “Pomodoro Focus Off”"),
        (.error("timed out"), "Couldn't check shortcuts: timed out"),
    ])
    func statusTextPerAvailability(_ availability: FocusAvailability, _ expected: String) {
        #expect(FocusSetupView.statusText(for: availability) == expected)
    }

    @Test func setupWindowIsReusableTitledAndFixedSize() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        let window = SettingsWindowController.makeWindow(
            title: "Set Up Focus",
            rootView: FocusSetupView(coordinator: h.coordinator)
        )

        #expect(window.title == "Set Up Focus")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.contentView is NSHostingView<FocusSetupView>)
        #expect(window.contentView?.frame.width == 420)
        #expect(!window.isVisible)
    }

    @Test func popoverWithFocusHintKeepsItsWidth() async throws {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        await h.coordinator.refreshFocusAvailability().value

        let popover = StatusItemController.makePopover(coordinator: h.coordinator)

        let hosting = try #require(popover.contentViewController as? NSHostingController<PopoverView>)
        #expect(hosting.view.fittingSize.width == 240)
    }
}
