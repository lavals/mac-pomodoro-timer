import AppKit
import SwiftUI

/// Owns one titled window hosting a SwiftUI view. Closing it only hides it, so reopening keeps
/// its position.
@MainActor
public final class HostedWindowController {
    let window: NSWindow
    /// Runs every time the window is shown, before it comes to the front.
    let onShow: () -> Void

    public init<Content: View>(title: String, rootView: Content, onShow: @escaping () -> Void) {
        window = Self.makeWindow(title: title, rootView: rootView)
        self.onShow = onShow
    }

    /// The settings window. Re-reads the login item, which may have been changed in System
    /// Settings since the last look.
    public static func settings(preferences: Preferences, launchAtLogin: LaunchAtLoginModel) -> HostedWindowController {
        HostedWindowController(
            title: "Pomodoro Settings",
            rootView: SettingsView(preferences: preferences, launchAtLogin: launchAtLogin),
            onShow: { launchAtLogin.refresh() }
        )
    }

    /// The Focus setup window. Re-checks the shortcuts, which may have been created since.
    public static func focusSetup(coordinator: TimerCoordinator) -> HostedWindowController {
        HostedWindowController(
            title: "Set Up Focus",
            rootView: FocusSetupView(coordinator: coordinator),
            onShow: { coordinator.refreshFocusAvailability() }
        )
    }

    /// Brings the window to the front, centered the first time and whenever it was closed.
    public func show() {
        onShow()
        if !window.isVisible { window.center() }
        // an accessory app has to activate itself for its window to come to the front
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A titled, closable, non-resizable window hosting `rootView`, kept alive after closing.
    private static func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        return window
    }
}
