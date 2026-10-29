import AppKit
import PomodoroCore

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // menu bar only: no Dock icon, works even when launched unbundled
    app.setActivationPolicy(.accessory)
    print("Pomodoro \(AppInfo.version)")
    app.run()
}
