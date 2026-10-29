import AppKit
import SwiftUI
import Testing
@testable import PomodoroCore

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SettingsWindowTests {
    @Test func windowIsReusableTitledAndFixedSize() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        let controller = HostedWindowController.settings(
            preferences: Preferences(defaults: testDefaults.defaults),
            launchAtLogin: LaunchAtLoginModel(service: FakeLoginService(), isBundled: false)
        )
        let window = controller.window
        #expect(window.title == "Pomodoro Settings")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.contentView is NSHostingView<SettingsView>)
        #expect(window.contentView?.frame.width == 360)
        #expect(!window.isVisible)
    }

    @Test func showingTheSettingsWindowRereadsTheLoginItem() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        let service = FakeLoginService()
        let launchAtLogin = LaunchAtLoginModel(service: service, isBundled: true)
        let controller = HostedWindowController.settings(
            preferences: Preferences(defaults: testDefaults.defaults),
            launchAtLogin: launchAtLogin
        )
        service.status = .enabled

        controller.onShow()

        #expect(launchAtLogin.isEnabled)
    }
}
