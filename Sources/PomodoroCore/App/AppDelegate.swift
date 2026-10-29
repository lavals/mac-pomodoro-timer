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
    private var settingsWindowController: HostedWindowController?
    private var focusSetupWindowController: HostedWindowController?

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
        let settings = HostedWindowController.settings(preferences: preferences, launchAtLogin: LaunchAtLoginModel())
        settingsWindowController = settings
        let focusSetup = HostedWindowController.focusSetup(coordinator: coordinator)
        focusSetupWindowController = focusSetup
        statusItemController = StatusItemController(
            coordinator: coordinator,
            openSettings: { settings.show() },
            openFocusSetup: { focusSetup.show() }
        )
    }

    /// Opening the app again from Finder or Spotlight while it runs shows the settings window:
    /// the app has no Dock icon and the status item may be hidden behind the notch.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { settingsWindowController?.show() }
        return false
    }

    /// Defers quitting until queued Focus calls finished and Focus is off again (bounded, see
    /// `TimerCoordinator.prepareForTermination`).
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        Task {
            await coordinator.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions)
    }
}
