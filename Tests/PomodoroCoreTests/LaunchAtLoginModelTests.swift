import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import Testing
@testable import PomodoroCore

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

    @Test(arguments: [SMAppService.Status.notFound, .notRegistered])
    func registerThatLeavesTheItemDisabledExplainsIt(_ after: SMAppService.Status) {
        let service = FakeLoginService()
        service.statusAfterRegister = after
        var opened = 0
        let model = LaunchAtLoginModel(service: service, isBundled: true) { opened += 1 }
        model.setEnabled(true)
        #expect(service.calls == ["register"])
        #expect(!model.isEnabled)
        #expect(model.message == LaunchAtLoginModel.notEnabledMessage)
        #expect(opened == 0)
    }

    @Test func refreshClearsAnEarlierError() {
        let service = FakeLoginService()
        service.error = FakeLoginService.Failure()
        let model = LaunchAtLoginModel(service: service, isBundled: true)
        model.setEnabled(true)
        #expect(model.message == "Operation not permitted")

        model.refresh()

        #expect(model.message == nil)
        #expect(!model.isEnabled)
    }

    @Test func refreshNoticesApprovalWithdrawnInSystemSettings() {
        let service = FakeLoginService(status: .enabled)
        var opened = 0
        let model = LaunchAtLoginModel(service: service, isBundled: true) { opened += 1 }
        #expect(model.isEnabled)

        service.status = .requiresApproval
        model.refresh()

        #expect(!model.isEnabled)
        #expect(model.message == LaunchAtLoginModel.approvalMessage)
        #expect(opened == 0)
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
