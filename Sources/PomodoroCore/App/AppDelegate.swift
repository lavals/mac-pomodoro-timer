import AppKit
import UserNotifications

/// Application delegate: builds the timer coordinator, sets up notifications and turns Focus
/// off when the app quits mid-session.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Banners must show even while the popover (and so the app) is active.
    nonisolated static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list]

    public private(set) var coordinator: TimerCoordinator?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

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
        let preferences = Preferences()
        let coordinator = TimerCoordinator(
            preferences: preferences,
            sessionStore: SessionStore(),
            focus: FocusController(),
            alerts: SystemAlerts()
        )
        self.coordinator = coordinator
        let settings = SettingsWindowController(preferences: preferences, launchAtLogin: LaunchAtLoginModel())
        settingsWindowController = settings
        statusItemController = StatusItemController(coordinator: coordinator) { settings.show() }
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
