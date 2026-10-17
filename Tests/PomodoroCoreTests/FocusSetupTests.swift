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
        (.error(.failed(status: 1, stderr: "boom")), "Couldn't check Focus shortcuts"),
    ])
    func hintMessagePerAvailability(_ availability: FocusAvailability, _ expected: String?) {
        #expect(FocusHintView.message(for: availability) == expected)
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
        (.error(.timeout), "Couldn't check Focus shortcuts: timed out"),
        (.error(.failed(status: 3, stderr: "")), "Couldn't check Focus shortcuts: exit status 3"),
        (.error(.launchFailed("no such file")), "Couldn't run the shortcuts tool: no such file"),
    ])
    func statusTextPerAvailability(_ availability: FocusAvailability, _ expected: String) {
        #expect(FocusSetupView.statusText(for: availability) == expected)
    }

    @Test func setupWindowIsReusableTitledAndFixedSize() {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }

        let window = HostedWindowController.focusSetup(coordinator: h.coordinator).window

        #expect(window.title == "Set Up Focus")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.contentView is NSHostingView<FocusSetupView>)
        #expect(window.contentView?.frame.width == 420)
        #expect(!window.isVisible)
    }

    @Test func showingTheSetupWindowRechecksTheShortcuts() async throws {
        let h = Harness()
        defer { h.cleanUp() }
        let controller = HostedWindowController.focusSetup(coordinator: h.coordinator)
        #expect(h.runner.calls.isEmpty)

        controller.onShow()

        for _ in 0..<100 where h.coordinator.focusAvailability != .available {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(h.coordinator.focusAvailability == .available)
        #expect(h.runner.calls.map(\.args) == [["list"]])
    }

    @Test func popoverGrowsToShowTheFocusHint() async throws {
        func popoverHeight(shortcuts: [String]) async throws -> CGFloat {
            let h = Harness(shortcuts: shortcuts)
            defer { h.cleanUp() }
            await h.coordinator.refreshFocusAvailability().value
            let popover = StatusItemController.makePopover(coordinator: h.coordinator, openSettings: {}, openFocusSetup: {})
            let hosting = try #require(popover.contentViewController as? NSHostingController<PopoverView>)
            #expect(hosting.view.fittingSize.width == 240)
            return hosting.view.fittingSize.height
        }

        let withoutHint = try await popoverHeight(shortcuts: [FocusController.onName, FocusController.offName])
        let withHint = try await popoverHeight(shortcuts: [])

        #expect(withHint > withoutHint)
    }
}
