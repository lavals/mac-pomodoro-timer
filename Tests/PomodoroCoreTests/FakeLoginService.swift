import Foundation
import ServiceManagement
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
