import AppKit
import Testing
@testable import PomodoroCore

/// The status item's button rendering, on a plain `NSButton` instead of a real status item.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct StatusButtonRendererTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func followsConsecutiveTicksAndTheCountdownToggle() async throws {
        let h = Harness(shortcuts: [])
        defer { h.cleanUp() }
        let button = NSButton()
        let renderer = StatusButtonRenderer(button: button, coordinator: h.coordinator)
        renderer.start()
        #expect(button.attributedTitle.string == "25:00")
        #expect(button.imagePosition == .imageLeading)
        #expect(button.image != nil)

        h.coordinator.start()
        h.clock.advance(1)
        h.coordinator.tick()
        try await waitUntil { button.attributedTitle.string == "24:59" }
        #expect(button.attributedTitle.string == "24:59")

        // a second change must still be observed: tracking re-registers after each one
        h.clock.advance(1)
        h.coordinator.tick()
        try await waitUntil { button.attributedTitle.string == "24:58" }
        #expect(button.attributedTitle.string == "24:58")

        h.coordinator.toggleCountdown()
        try await waitUntil { button.imagePosition == .imageOnly }
        #expect(button.imagePosition == .imageOnly)
        #expect(button.attributedTitle.string.isEmpty)

        h.coordinator.toggleCountdown()
        try await waitUntil { button.imagePosition == .imageLeading }
        #expect(button.imagePosition == .imageLeading)
        #expect(button.attributedTitle.string == "24:58")
        await h.settle()
    }
}
