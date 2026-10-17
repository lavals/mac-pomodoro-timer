import Foundation
import Observation
import ServiceManagement

/// The login item registration the app needs: the subset of `SMAppService` used by
/// `LaunchAtLoginModel`, so tests can use a fake and never touch the real login items.
public protocol LoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

/// `LoginService` over `SMAppService.mainApp`.
public struct SMAppServiceLoginService: LoginService {
    public init() {}

    public var status: SMAppService.Status { SMAppService.mainApp.status }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Drives the "Launch at login" toggle: mirrors the login item status, registers or
/// unregisters it, and explains why it is off when the user must approve it or the app runs
/// unbundled (`swift run`), where there is no app to register.
@MainActor
@Observable
public final class LaunchAtLoginModel {
    static let approvalMessage = "Allow Pomodoro in System Settings > General > Login Items."
    static let unbundledMessage = "Launch at login works only in the installed app."
    static let notEnabledMessage = "macOS did not enable launch at login. Check System Settings > General > Login Items."

    /// Whether the app is registered and allowed to launch at login.
    public private(set) var isEnabled = false
    /// One line shown under the toggle: approval hint, error or unbundled explanation.
    public private(set) var message: String?
    /// False when running without a bundle: the toggle is shown disabled.
    public let isAvailable: Bool

    @ObservationIgnored private let service: LoginService
    @ObservationIgnored private let openLoginItemsSettings: () -> Void

    /// - Parameters:
    ///   - isBundled: whether the app runs from an `.app` bundle; the login service is never
    ///     called otherwise.
    ///   - openLoginItemsSettings: opens System Settings > Login Items when approval is needed.
    public init(
        service: LoginService = SMAppServiceLoginService(),
        isBundled: Bool = Bundle.main.bundleIdentifier != nil,
        openLoginItemsSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.service = service
        self.openLoginItemsSettings = openLoginItemsSettings
        isAvailable = isBundled
        refresh()
    }

    /// Re-reads the status, e.g. when the settings window opens after the user changed the
    /// login item in System Settings.
    public func refresh() {
        guard isAvailable else {
            isEnabled = false
            message = Self.unbundledMessage
            return
        }
        let status = service.status
        isEnabled = status == .enabled
        message = status == .requiresApproval ? Self.approvalMessage : nil
    }

    /// Registers (`true`) or unregisters (`false`) the login item. On failure the error is shown
    /// in `message` and `isEnabled` keeps its previous value.
    public func setEnabled(_ enabled: Bool) {
        guard isAvailable else {
            message = Self.unbundledMessage
            return
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // registering may throw while still leaving the item waiting for approval
            if enabled, service.status == .requiresApproval {
                requestApproval()
            } else {
                message = error.localizedDescription
            }
            return
        }
        let status = service.status
        isEnabled = status == .enabled
        if enabled, status == .requiresApproval {
            requestApproval()
        } else if enabled, status != .enabled {
            // registering "succeeded" but the item is not there (e.g. `.notFound`)
            message = Self.notEnabledMessage
        } else {
            message = nil
        }
    }

    private func requestApproval() {
        isEnabled = false
        message = Self.approvalMessage
        openLoginItemsSettings()
    }
}
