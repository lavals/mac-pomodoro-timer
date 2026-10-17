import AppKit
import UserNotifications

/// Chime and notification output. A protocol so tests never play sounds or post notifications.
@MainActor
public protocol Alerts: AnyObject {
    func playChime(_ chime: Chime)
    func postNotification(title: String, body: String)
}

/// Plays macOS system sounds and posts user notifications.
@MainActor
public final class SystemAlerts: Alerts {
    public init() {}

    /// System sound for each chime; both ship in `/System/Library/Sounds`.
    nonisolated static func soundName(for chime: Chime) -> String {
        switch chime {
        case .workEnded: return "Glass"
        case .restEnded: return "Tink"
        }
    }

    /// `UNUserNotificationCenter.current()` crashes when the process has no bundle identifier
    /// (an unbundled `swift run` or test run), so every notification call checks this first.
    nonisolated static func canUseNotifications(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> Bool {
        bundleIdentifier != nil
    }

    public func playChime(_ chime: Chime) {
        NSSound(named: NSSound.Name(Self.soundName(for: chime)))?.play()
    }

    public func postNotification(title: String, body: String) {
        guard Self.canUseNotifications() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // the chime already played; a notification sound on top would double it
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
