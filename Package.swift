// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pomodoro", targets: ["Pomodoro"]),
        .library(name: "PomodoroCore", targets: ["PomodoroCore"]),
    ],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(name: "Pomodoro", dependencies: ["PomodoroCore"]),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"]),
    ],
    // Swift 5 language mode on a Swift 6.2+ toolchain (isolated deinit needs the 6.2 compiler)
    swiftLanguageModes: [.v5]
)
