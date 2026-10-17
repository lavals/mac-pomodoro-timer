import AppKit
import PomodoroCore

/// Placeholder delegate; replaced by `PomodoroCore.AppDelegate` in a later task.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Pomodoro \(AppInfo.version)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// menu bar only: no Dock icon, works even when launched unbundled
app.setActivationPolicy(.accessory)
app.run()
