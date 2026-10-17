import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import Testing
@testable import PomodoroCore

/// In-memory login service: never touches the real login items.
final class FakeLoginService: LoginService {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    var status: SMAppService.Status
    /// Status after a successful `register()`.
    var statusAfterRegister: SMAppService.Status = .enabled
    var error: Error?
    private(set) var calls: [String] = []

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if let error { throw error }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if let error { throw error }
        status = .notRegistered
    }
}

@MainActor
@Suite struct LaunchAtLoginModelTests {
    @Test func mirrorsStatusOnInit() {
        #expect(LaunchAtLoginModel(service: FakeLoginService(status: .enabled), isBundled: true).isEnabled)
        let off = LaunchAtLoginModel(service: FakeLoginService(status: .notRegistered), isBundled: true)
        #expect(!off.isEnabled)
        #expect(off.message == nil)
        #expect(off.isAvailable)
    }

    @Test func enablingRegisters() {
        let service = FakeLoginService()
        let model = LaunchAtLoginModel(service: service, isBundled: true)
        model.setEnabled(true)
        #expect(service.calls == ["register"])
        #expect(model.isEnabled)
        #expect(model.message == nil)
    }

    @Test func disablingUnregisters() {
        let service = FakeLoginService(status: .enabled)
        let model = LaunchAtLoginModel(service: service, isBundled: true)
        model.setEnabled(false)
        #expect(service.calls == ["unregister"])
        #expect(!model.isEnabled)
        #expect(model.message == nil)
    }

    @Test func requiresApprovalShowsMessageAndOpensSettings() {
        let service = FakeLoginService()
        service.statusAfterRegister = .requiresApproval
        var opened = 0
        let model = LaunchAtLoginModel(service: service, isBundled: true) { opened += 1 }
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.message == LaunchAtLoginModel.approvalMessage)
        #expect(opened == 1)
    }

    @Test func throwingRegisterWhileAwaitingApprovalStillAsksForApproval() {
        let service = FakeLoginService(status: .requiresApproval)
        service.error = FakeLoginService.Failure()
        var opened = 0
        let model = LaunchAtLoginModel(service: service, isBundled: true) { opened += 1 }
        model.setEnabled(true)
        #expect(model.message == LaunchAtLoginModel.approvalMessage)
        #expect(opened == 1)
    }

    @Test func initWithPendingApprovalShowsMessageWithoutOpeningSettings() {
        var opened = 0
        let model = LaunchAtLoginModel(service: FakeLoginService(status: .requiresApproval), isBundled: true) {
            opened += 1
        }
        #expect(!model.isEnabled)
        #expect(model.message == LaunchAtLoginModel.approvalMessage)
        #expect(opened == 0)
    }

    @Test(arguments: [true, false])
    func throwingServiceSurfacesMessageAndKeepsState(enable: Bool) {
        let service = FakeLoginService(status: enable ? .notRegistered : .enabled)
        service.error = FakeLoginService.Failure()
        var opened = 0
        let model = LaunchAtLoginModel(service: service, isBundled: true) { opened += 1 }
        model.setEnabled(enable)
        #expect(model.isEnabled == !enable)
        #expect(model.message == "Operation not permitted")
        #expect(opened == 0)
    }

    @Test func successClearsPreviousError() {
        let service = FakeLoginService()
        service.error = FakeLoginService.Failure()
        let model = LaunchAtLoginModel(service: service, isBundled: true)
        model.setEnabled(true)
        #expect(model.message != nil)
        service.error = nil
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.message == nil)
    }

    @Test func refreshPicksUpExternalChanges() {
        let service = FakeLoginService()
        let model = LaunchAtLoginModel(service: service, isBundled: true)
        service.status = .enabled
        model.refresh()
        #expect(model.isEnabled)
    }

    @Test func unbundledIsUnavailableAndNeverCallsTheService() {
        let service = FakeLoginService(status: .enabled)
        let model = LaunchAtLoginModel(service: service, isBundled: false)
        #expect(!model.isAvailable)
        #expect(!model.isEnabled)
        #expect(model.message == LaunchAtLoginModel.unbundledMessage)
        model.setEnabled(true)
        #expect(service.calls.isEmpty)
        #expect(!model.isEnabled)
    }
}

@MainActor
@Suite struct SettingsWindowTests {
    @Test func windowIsReusableTitledAndFixedSize() {
        let testDefaults = TestDefaults()
        defer { testDefaults.cleanUp() }
        let view = SettingsView(
            preferences: Preferences(defaults: testDefaults.defaults),
            launchAtLogin: LaunchAtLoginModel(service: FakeLoginService(), isBundled: false)
        )
        let window = SettingsWindowController.makeWindow(title: "Pomodoro Settings", rootView: view)
        #expect(window.title == "Pomodoro Settings")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.contentView is NSHostingView<SettingsView>)
        #expect(window.contentView?.frame.width == 360)
        #expect(!window.isVisible)
    }
}
