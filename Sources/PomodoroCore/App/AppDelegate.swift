import AppKit
import UserNotifications

/// Application delegate: builds the timer coordinator, sets up notifications and turns Focus
/// off when the app quits mid-session.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Banners must show even while the popover (and so the app) is active.
    nonisolated static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list]

    public private(set) var coordinator: TimerCoordinator?

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // requesting again on every launch is a no-op once the user has answered
        if SystemAlerts.canUseNotifications() {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
        coordinator = TimerCoordinator(
            preferences: Preferences(),
            sessionStore: SessionStore(),
            focus: FocusController(),
            alerts: SystemAlerts()
        )
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions)
    }
}
