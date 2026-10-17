import AppKit
import SwiftUI

/// Owns the one settings window. Closing it only hides it, so reopening keeps its position.
@MainActor
public final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin: LaunchAtLoginModel

    public init(preferences: Preferences, launchAtLogin: LaunchAtLoginModel) {
        self.launchAtLogin = launchAtLogin
        window = Self.makeWindow(
            title: "Pomodoro Settings",
            rootView: SettingsView(preferences: preferences, launchAtLogin: launchAtLogin)
        )
    }

    /// Brings the window to the front, centered the first time and whenever it was closed.
    public func show() {
        // the login item may have been changed in System Settings since the last look
        launchAtLogin.refresh()
        if !window.isVisible { window.center() }
        // an accessory app has to activate itself for its window to come to the front
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A titled, closable, non-resizable window hosting `rootView`, kept alive after closing.
    static func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
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
