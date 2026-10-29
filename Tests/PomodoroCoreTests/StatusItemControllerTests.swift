import AppKit
import SwiftUI
import Testing
@testable import PomodoroCore

@MainActor
@Suite(.timeLimit(.minutes(1))) struct StatusItemControllerTests {
    @Test func buildsMenuFromPresentationItems() {
        let items = TimerPresentation.menuItems(for: .running(phase: .work, endDate: t0, total: 1500))
        let menu = StatusItemController.makeMenu(items: items, showCountdown: true, target: nil, action: nil)
        #expect(menu.items.map(\.title) == ["Pause", "Skip", "Reset", "", "Show Countdown in Menu Bar",
                                            "Settings…", "", "Quit Pomodoro"])
        #expect(menu.items[3].isSeparatorItem)
        #expect(menu.items.enumerated().allSatisfy { index, item in item.isSeparatorItem || item.tag == index })
        #expect(menu.items[4].state == .on)
        #expect(menu.items[5].isEnabled)
        #expect(menu.items[0].isEnabled)
        #expect(menu.items[7].keyEquivalent == "q")
    }

    @Test func countdownItemUncheckedWhenHidden() {
        let menu = StatusItemController.makeMenu(
            items: TimerPresentation.menuItems(for: .idle), showCountdown: false, target: nil, action: nil
        )
        #expect(menu.items.map(\.title).first == "Start Focus")
        #expect(menu.items.first { $0.title == "Show Countdown in Menu Bar" }?.state == .off)
    }

    @Test func rightClickOrControlClickOpensTheMenu() {
        #expect(StatusItemController.wantsMenu(eventType: .rightMouseUp, modifierFlags: []))
        #expect(StatusItemController.wantsMenu(eventType: .leftMouseUp, modifierFlags: [.control]))
        #expect(!StatusItemController.wantsMenu(eventType: .leftMouseUp, modifierFlags: []))
        #expect(!StatusItemController.wantsMenu(eventType: .leftMouseUp, modifierFlags: [.option]))
    }

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
