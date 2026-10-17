import AppKit
import Foundation
import Testing
@testable import PomodoroCore

private let end = Date(timeIntervalSinceReferenceDate: 1_000_000)

@Suite struct StatusTitleTests {
    @Test func hiddenIsEmpty() {
        #expect(StatusTitle.make(time: "25:00", tint: .controlAccentColor, showCountdown: false).length == 0)
    }

    @Test func shownContainsTime() {
        let title = StatusTitle.make(time: "12:34", tint: .controlAccentColor, showCountdown: true)
        #expect(title.string.contains("12:34"))
    }

    @Test func usesMonospacedDigitFont() throws {
        let title = StatusTitle.make(time: "12:34", tint: .secondaryLabelColor, showCountdown: true)
        let font = try #require(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 13)
        let settings = try #require(
            font.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]]
        )
        #expect(settings.contains { setting in
            setting[.typeIdentifier] == kNumberSpacingType
                && setting[.selectorIdentifier] == kMonospacedNumbersSelector
        })
    }

    @Test(arguments: [
        (TimerState.idle, NSColor.secondaryLabelColor),
        (.running(phase: .work, endDate: end, total: 1500), .controlAccentColor),
        (.paused(phase: .rest, remaining: 10, total: 300), .systemGreen),
        (.finished(phase: .work), .secondaryLabelColor),
    ])
    func titleUsesThePresentationTint(_ state: TimerState, _ expected: NSColor) throws {
        let title = StatusTitle.make(time: "05:00", tint: TimerPresentation.tint(for: state), showCountdown: true)
        let color = try #require(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(color == expected)
    }
}

@MainActor
@Suite struct StatusMenuTests {
    @Test func buildsMenuFromPresentationItems() {
        let items = TimerPresentation.menuItems(for: .running(phase: .work, endDate: end, total: 1500))
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
}
