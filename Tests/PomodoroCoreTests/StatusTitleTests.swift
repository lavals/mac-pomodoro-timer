import AppKit
import Foundation
import Testing
@testable import PomodoroCore

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
        (.running(phase: .work, endDate: t0, total: 1500), .controlAccentColor),
        (.paused(phase: .rest, remaining: 10, total: 300), .systemGreen),
        (.finished(phase: .work), .secondaryLabelColor),
    ])
    func titleUsesThePresentationTint(_ state: TimerState, _ expected: NSColor) throws {
        let title = StatusTitle.make(time: "05:00", tint: TimerPresentation.tint(for: state), showCountdown: true)
        let color = try #require(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(color == expected)
    }
}
