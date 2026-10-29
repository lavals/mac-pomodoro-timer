import AppKit
import Testing
import UserNotifications
@testable import PomodoroCore

@Suite(.timeLimit(.minutes(1))) struct AlertsTests {
    @Test(arguments: [Chime.workEnded, .restEnded])
    func systemAlertsSoundsExist(_ chime: Chime) {
        // loads the system sound without playing it
        #expect(NSSound(named: NSSound.Name(SystemAlerts.soundName(for: chime))) != nil)
    }

    @Test func systemAlertsSoundNamesAndBundleGuard() {
        #expect(SystemAlerts.soundName(for: .workEnded) == "Glass")
        #expect(SystemAlerts.soundName(for: .restEnded) == "Tink")
        #expect(SystemAlerts.canUseNotifications(bundleIdentifier: nil) == false)
        #expect(SystemAlerts.canUseNotifications(bundleIdentifier: "com.lavals.pomodoro") == true)
    }

    @Test func notificationsShowAsBannerWhileActive() {
        #expect(AppDelegate.presentationOptions == [.banner, .list])
    }
}
