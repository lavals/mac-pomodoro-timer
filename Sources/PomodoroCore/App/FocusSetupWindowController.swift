import AppKit
import SwiftUI

/// Owns the one Focus setup window. Closing it only hides it, so reopening keeps its position.
@MainActor
public final class FocusSetupWindowController {
    private let window: NSWindow
    private let coordinator: TimerCoordinator

    public init(coordinator: TimerCoordinator) {
        self.coordinator = coordinator
        window = SettingsWindowController.makeWindow(
            title: "Set Up Focus",
            rootView: FocusSetupView(coordinator: coordinator)
        )
    }

    /// Brings the window to the front, centered the first time and whenever it was closed.
    public func show() {
        // the shortcuts may have been created since the last check
        coordinator.refreshFocusAvailability()
        if !window.isVisible { window.center() }
        // an accessory app has to activate itself for its window to come to the front
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
