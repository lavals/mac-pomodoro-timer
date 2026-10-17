import Foundation
@testable import PomodoroCore

/// Records chimes and notifications instead of playing sounds or posting real notifications.
@MainActor
final class FakeAlerts: Alerts {
    struct Notification: Equatable {
        let title: String
        let body: String
    }

    private(set) var chimes: [Chime] = []
    private(set) var notifications: [Notification] = []
    private let log: EventLog?

    init(log: EventLog? = nil) {
        self.log = log
    }

    func playChime(_ chime: Chime) {
        chimes.append(chime)
        log?.append("chime \(chime)")
    }

    func postNotification(title: String, body: String) {
        notifications.append(Notification(title: title, body: body))
        log?.append("notify \(title)")
    }
}
