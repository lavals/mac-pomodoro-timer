# Pomodoro Menu Bar App

## Overview
- native macOS menu bar pomodoro timer: configurable work and rest durations, a hideable countdown in the menu bar, and a compact popover with a progress ring
- during a work session the app turns on a macOS Focus (via two user-created Shortcuts) so Slack in the browser and everything else goes quiet; Focus turns off when the session ends or is paused/reset
- distributed as a Homebrew cask from a personal tap so the same app installs on every Mac with `brew install`
- looks native in light and dark mode by using only system materials and semantic colors

## Context (from discovery)
- repo is empty apart from `LICENSE`; public GitHub repo `lavals/mac-pomodoro-timer`
- no git identity configured in this repo or globally; last commit author was `lavals <43458274+lavals@users.noreply.github.com>`
- the public tap repo `lavals/homebrew-tap` already exists and is cloned next to this repo at `../homebrew-tap` (empty)
- **never commit personal data**: no real names, personal or work email addresses, SSH host aliases, or account names other than the public `lavals` handle and its GitHub no-reply address
- toolchain: macOS 27.0.1, Swift 6.4 via Command Line Tools (`xcode-select -p` = `/Library/Developer/CommandLineTools`), **no Xcode**. Verified in scratch packages:
  - **XCTest is unavailable** (module not found). All tests use **Swift Testing** (`import Testing`).
  - ⚠️ `swift test` **fails as soon as the package has an executable target** (`plugin for module 'TestingMacros' not found`), even when tests only import a library target. Verified fix: `swift test -Xswiftc -plugin-path -Xswiftc "$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"`. `make test` adds that flag only when `xcode-select -p` points at the Command Line Tools, so CI (Xcode toolchain) runs plain `swift test`. The flag must not go into `Package.swift`.
  - the default build system is `swiftbuild`; release binaries land under `$(swift build -c release --show-bin-path)`, **not** `.build/release`
  - Command Line Tools build **arm64 only**; universal binaries need Xcode. Decision: ship arm64 only, cask declares `depends_on arch: :arm64`.
- Homebrew 7.0.9 is installed. ⚠️ **`brew install --no-quarantine` no longer exists** and Homebrew always quarantines cask downloads. Since the app is ad-hoc signed and not notarized, Gatekeeper on macOS 15+ would refuse it, so the cask's `postflight` removes `com.apple.quarantine` from the installed app. Ad-hoc signatures also change on every build, so Homebrew prints a "signer changed" warning on upgrade; that is expected.
- `/usr/bin/shortcuts`, `iconutil`, `codesign`, `ditto`, `sips`, `plutil` are all present; system sounds exist at `/System/Library/Sounds` so no audio files need shipping
- headless AppKit (`NSImage`, `NSFont`, `NSAttributedString`) works inside `swift test` (verified by plan review)
- brainstorm design (approved): AppKit `NSStatusItem` + `NSPopover` hosting SwiftUI views; pure-Swift timer engine returning effects; Focus via `shortcuts run`; Swift Package build with a bundle-assembly script; GitHub Actions release to a Homebrew tap

## Development Approach
- **testing approach**: Regular (code first, then tests) — chosen by user
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
  - tests are not optional - they are a required part of the checklist
  - write unit tests for new functions/methods
  - write unit tests for modified functions/methods
  - add new test cases for new code paths
  - update existing test cases if behavior changes
  - tests cover both success and error scenarios
- **CRITICAL: all tests must pass before starting next task** - no exceptions
- **CRITICAL: update this plan file when scope changes during implementation**
- run tests after each change with **`make test`** (never bare `swift test` on this machine, see Context)
- **Swift Testing only** (`import Testing`, `@Test`, `#expect`, `@Suite`). Never `import XCTest`.
- Swift Testing runs tests in parallel and has no teardown: tests that touch `UserDefaults` use a unique suite name per test (`"PomodoroTests.\(UUID())"`) and `defer { defaults.removePersistentDomain(forName:) }`
- keep AppKit/SwiftUI code thin; logic lives in pure types behind small protocols so it is testable without a GUI
- shell scripts, workflows and docs are checked by Makefile/CI steps, **not** by Swift tests

## Testing Strategy
- **unit tests**: required for every task (see Development Approach above). Run with `make test`.
- **no e2e framework**: UI is verified by a smoke launch (`make run`) and the manual scenarios under Post-Completion
- **fakes over mocks**: injected `now: () -> Date`, a `ShellRunner` protocol for the `shortcuts` CLI, an `Alerts` protocol for chime/notification, a `LoginService` protocol for `SMAppService`
- **build artefacts**: `make verify-app` builds the bundle and checks `Info.plist`, version and signature; `make check-cask` renders the cask and checks it with `ruby -c`; both run in CI
- **CI**: `make test` + `make verify-app` + `make check-cask` on every push to `main` and every PR, on a pinned `macos-26` runner; release build only on tags

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope
- keep plan in sync with actual work done

## Solution Overview
- **Swift Package at repo root** with a library target `PomodoroCore` (all code) and a thin executable target `Pomodoro` (only `main.swift`), plus `PomodoroCoreTests`. `swift-tools-version:5.10`, Swift language mode 5 (avoid fighting strict concurrency in AppKit glue), `platforms: [.macOS(.v14)]`. Tests never link `main.swift`.
- **Four layers with one-way dependencies**: `Timer` (pure state machine) ← `Settings` (UserDefaults, login item) ← `Focus` (shortcuts CLI behind a protocol) ← `App` (coordinator, status item, windows) → `Views` (SwiftUI, read-only over the coordinator).
- **Effects, not side effects**: every engine transition returns `[Effect]`; the `TimerCoordinator` performs them through two narrow seams, `FocusController` (over `ShellRunner`) and `Alerts`. Effect **order** is an engine property under test; **execution** is the coordinator's job (chime immediately, focus off awaited, then notification).
- **Persistence is unconditional**: the coordinator saves the engine state after every mutating call. There is no `persist` effect to forget.
- **Absolute end dates**: the engine stores `endDate`, so remaining time is `endDate - now` and survives sleep/wake. The coordinator stores a `now` property updated every second so `@Observable` sees a change even when the engine state does not.
- **Bundle assembly by script**: `scripts/build-app.sh` turns the SwiftPM binary into `Pomodoro.app` with `Info.plist` (`LSUIElement = true`), an `.icns` icon, and an ad-hoc signature. `VERSION` file is the single source of truth for the version; CI refuses a tag that does not match it.
- **Release pipeline**: tag `vX.Y.Z` → GitHub Actions on macOS → test → build → zip with `ditto` → GitHub Release → compute SHA-256 → render `packaging/pomodoro.rb.tmpl` and push `Casks/pomodoro.rb` to `lavals/homebrew-tap` with a PAT. The tap repo holds no hand-maintained content.
- **Out of scope (YAGNI)**: Slack DND, statistics/history, settings sync, long-break cycles, auto-advance, presets, notarization, universal binaries.

## Technical Details

### Timer engine (`Sources/PomodoroCore/Timer/`)
```swift
enum Phase: Codable, Equatable { case work, rest }

enum TimerState: Codable, Equatable {
    case idle                                            // nothing running, next phase is work
    case running(phase: Phase, endDate: Date, total: TimeInterval)
    case paused(phase: Phase, remaining: TimeInterval, total: TimeInterval)
    case finished(phase: Phase)                          // chimed, waiting for user to start the next phase
}

enum Chime: Equatable { case workEnded, restEnded }      // "Glass" and "Tink" system sounds

enum Effect: Equatable {
    case focusOn, focusOff
    case playChime(Chime)
    case postNotification(title: String, body: String)
}

struct Durations: Equatable { var work: TimeInterval; var rest: TimeInterval
    func total(for phase: Phase) -> TimeInterval }

struct TimerEngine {
    private(set) var state: TimerState
    init(state: TimerState = .idle)
    static func restore(_ saved: TimerState?, now: Date) -> (TimerEngine, [Effect])
    mutating func start(now: Date, durations: Durations) -> [Effect]
    mutating func pause(now: Date) -> [Effect]
    mutating func skip(now: Date) -> [Effect]
    mutating func reset() -> [Effect]
    mutating func tick(now: Date) -> [Effect]
    func remaining(now: Date) -> TimeInterval        // 0 when idle/finished
    func progress(now: Date) -> Double               // 0...1 elapsed fraction, clamped
    var nextPhase: Phase                             // what start() would begin
}
```
Transition and effect table (every row is a test):

| from | call | to | effects |
|---|---|---|---|
| idle | start | running(work) | `[.focusOn]` |
| finished(work) | start | running(rest) | `[]` |
| finished(rest) | start | running(work) | `[.focusOn]` |
| paused(work) | start | running(work), endDate = now + remaining | `[.focusOn]` |
| paused(rest) | start | running(rest) | `[]` |
| running(work) | pause | paused(work) | `[.focusOff]` |
| running(rest) | pause | paused(rest) | `[]` |
| running/paused(work) | skip | finished(work) | `[.focusOff]` (no chime) |
| running/paused(rest) | skip | finished(rest) | `[]` |
| running/paused(work) | reset | idle | `[.focusOff]` |
| any other | reset | idle | `[]` |
| running(work), now ≥ endDate | tick | finished(work) | `[.focusOff, .playChime(.workEnded), .postNotification("Focus finished", "Time for a break")]` exactly in this order |
| running(rest), now ≥ endDate | tick | finished(rest) | `[.playChime(.restEnded), .postNotification("Break over", "Ready when you are")]` |
| running, now < endDate | tick | unchanged | `[]` |
| idle / paused / finished | tick, pause, skip (where not listed) | unchanged | `[]` |

- `restore`: `running` with `endDate <= now` → `finished(phase)` + `[.focusOff]` if work (cleanup, no chime); `running(work)` still in the future → `[.focusOn]` (reconcile); `nil`, `idle`, `paused`, `finished` → as saved, `[]`
- display formatting (`mm:ss`, ceil to whole seconds so `25:00` shows at start, caps at `99:59`) lives in `TimeFormatting.swift` as a pure function

### Persistence (`Sources/PomodoroCore/Timer/SessionStore.swift`, `Sources/PomodoroCore/Settings/Preferences.swift`)
- `Preferences` (`@Observable`): `workMinutes` (default 25), `restMinutes` (default 5), `showCountdown` (default true); minutes clamped to 1…120 in `didSet` (verified no recursion); backed by an injected `UserDefaults`; exposes `durations: Durations`
- `SessionStore`: `save(TimerState)` / `load() -> TimerState?` as JSON under one key in the same `UserDefaults`; `clear()`; corrupt data → `nil`

### Focus (`Sources/PomodoroCore/Focus/`)
```swift
struct ShellResult { let status: Int32; let stdout: String; let stderr: String }
protocol ShellRunner: Sendable { func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> ShellResult }

enum FocusAvailability: Equatable { case unknown, available, missing(names: [String]), error(String) }
enum FocusError: Error, Equatable { case notInstalled, failed(status: Int32, stderr: String), timeout }

struct FocusController {
    static let onName = "Pomodoro Focus On", offName = "Pomodoro Focus Off"
    init(runner: ShellRunner)
    func availability() async -> FocusAvailability       // `shortcuts list`, trimmed exact-match on both names
    func setFocus(_ on: Bool) async -> Result<Void, FocusError>   // `shortcuts run <name>`, 5s timeout
}
```
- `ProcessShellRunner` wraps `Foundation.Process` running `/usr/bin/shortcuts`; it **drains stdout and stderr concurrently** (`readabilityHandler` or background reads) before `waitUntilExit`, and enforces the timeout with `terminate()`. Calling `readDataToEndOfFile` after `waitUntilExit` can deadlock on large output.
- runner failures are thrown as `ShellError` (`.timeout`, `.launchFailed(String)`); `setFocus` maps `.timeout` → `FocusError.timeout` and any launch failure → `.notInstalled`. `setFocus` takes an optional `timeout:` (default 5s) so `prepareForTermination` can pass 2s
- all shell calls run **off the main actor**; the coordinator awaits them. The only synchronous shell call is in `prepareForTermination`, with a short timeout.

### App layer (`Sources/PomodoroCore/App/`)
- `main.swift` (in the executable target): creates `NSApplication`, installs `AppDelegate`, calls `NSApp.setActivationPolicy(.accessory)` (works even when launched unbundled), runs
- `AppDelegate`: builds the coordinator, status item and windows; `applicationDidFinishLaunching` requests notification authorization (idempotent, every launch, **guarded by `Bundle.main.bundleIdentifier != nil`** because `UNUserNotificationCenter.current()` crashes unbundled) and sets a `UNUserNotificationCenterDelegate` whose `willPresent` returns `[.banner, .list]` so banners show while the app is active; `applicationWillTerminate` calls `coordinator.prepareForTermination()`
- `TimerCoordinator` (`@MainActor`, `@Observable`):
  - injected: `now: () -> Date`, `Preferences`, `SessionStore`, `FocusController`, `Alerts` (protocol: `playChime(Chime)`, `postNotification(title:body:)`), `ticker` factory (so tests can drive ticks by hand)
  - stored `private(set) var now: Date` updated on every tick; derived `displayTime`, `progress`, `phaseLabel`, `primaryAction` read it. When `idle`/`finished`, `displayTime` shows the **next phase's full duration** (e.g. `25:00`), not `00:00`
  - actions: `start()`, `pause()`, `skip()`, `reset()`, `toggleCountdown()`, `refreshFocusAvailability()`, `prepareForTermination()`
  - after **every** mutating engine call: `sessionStore.save(engine.state)`, then perform effects
  - effect execution: `.playChime` → immediately; `.focusOn/.focusOff` → skipped when `focusAvailability != .available`, otherwise awaited in a `Task`; `.postNotification` → after the focus call completes (so Focus does not swallow it); a failed focus call sets `lastFocusError: String?`, a successful one clears it; the timer never waits on focus
  - 1s `Timer` created only while `running`, added to `RunLoop.main` in `.common` mode (default mode stops firing while the right-click menu is open); holds `ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` while running so App Nap does not delay the chime
  - observes `NSWorkspace.didWakeNotification` on **`NSWorkspace.shared.notificationCenter`** (not `NotificationCenter.default`) → `tick()`
  - `prepareForTermination()`: if work is running or paused-from-running, synchronous `focusOff` with a 2s timeout
- `TimerPresentation.swift`: pure helpers `primaryActionTitle(for:)`, `phaseLabel(for:)`, `ringTint(for:)`, `menuItems(for:)` used by views, status item and menu
- `StatusItemController`:
  - `NSStatusItem` with `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`; in the action, `NSApp.currentEvent?.type == .rightMouseUp` (or left + `.control`) shows the menu, otherwise toggles the popover
  - menu display: assign `statusItem.menu = menu`, `button.performClick(nil)`, and set `statusItem.menu = nil` in `menuDidClose` (a permanently assigned menu disables the left-click action)
  - popover: `NSPopover` with `behavior = .transient`, `contentViewController = NSHostingController(rootView:)` with `sizingOptions = .preferredContentSize`; call `NSApp.activate()` before `show(relativeTo:of:preferredEdge:)` so transient dismissal works in an accessory app; on show, call `coordinator.refreshFocusAvailability()` **after** the popover is visible
  - rendering: `withObservationTracking { read coordinator } onChange: { DispatchQueue.main.async { render(); track() } }` — `onChange` fires once with willSet semantics, so always hop to main, re-read and re-register
  - countdown shown: `StatusTitle.make(...)` → `NSAttributedString` with `NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)`; tint `.controlAccentColor` work, `.systemGreen` rest, `.secondaryLabelColor` idle; plus the glyph image
  - countdown hidden: `StatusGlyph.image(spec:)` renders a `GlyphSpec` (pure value: filled / outlined / dimmed, arc fraction) into an 18×18 template `NSImage`
- `SettingsWindowController` and `FocusSetupWindowController`: one reusable `NSWindow` each (`.titled, .closable`, non-resizable, `isReleasedWhenClosed = false`) hosting a SwiftUI view via `NSHostingView`; shown with `NSApp.activate()` + `makeKeyAndOrderFront`, centered

### Views (`Sources/PomodoroCore/Views/`)
- `PopoverView` (240×280): `ProgressRing` (160pt, 8pt stroke, trailing round cap, subtle track), centered time in `.system(size: 40, weight: .light, design: .rounded).monospacedDigit()`, phase label `Focus`/`Break`/`Ready`, primary capsule `Button` (title from `TimerPresentation`), secondary `Skip`/`Reset` text buttons, a gear button opening Settings, `FocusHintView` only when `focusAvailability` is `.missing`/`.error`, one-line `lastFocusError` in `.caption` secondary when set. Background is the popover's own material; no custom colors.
- `SettingsView`: `Form` with two `Stepper`s (1…120) bound via `@Bindable var preferences`, `Toggle("Show countdown in menu bar")`, `Toggle("Launch at login")` driven by `LaunchAtLoginModel`
- `LaunchAtLoginModel` (`Settings/`): wraps a `LoginService` protocol (`status`, `register()`, `unregister()`) implemented by `SMAppService.mainApp`; `isEnabled` mirrors `status == .enabled`; `.requiresApproval` → message + `SMAppService.openSystemSettingsLoginItems()`; errors become `message: String?`; disabled with an explanatory message when `Bundle.main.bundleIdentifier == nil` (unbundled dev run)
- `FocusSetupView`: step list for both shortcuts (name, single "Set Focus" action, On = turn on until turned off, Off = turn off), "Open Shortcuts" (`NSWorkspace.shared.open(URL(string: "shortcuts://")!)`), "Check again" (`refreshFocusAvailability()`), note that Focus "Share Across Devices" also silences the iPhone, link to `docs/focus-shortcuts.md`

### Build and packaging
- `VERSION` file (e.g. `0.1.0`) — single source of truth; `AppInfo.version` reads `CFBundleShortVersionString` from the bundle with a `"dev"` fallback
- `scripts/build-app.sh` (`set -euo pipefail`): `swift build -c release --product Pomodoro`; `BIN="$(swift build -c release --show-bin-path)/Pomodoro"`; assemble `build/Pomodoro.app/Contents/{MacOS,Resources}`; render `packaging/Info.plist.tmpl` (`__VERSION__`) with keys CFBundleIdentifier `com.lavals.pomodoro`, CFBundleName, CFBundleExecutable, CFBundleShortVersionString, CFBundleVersion, **CFBundlePackageType `APPL`**, CFBundleInfoDictionaryVersion `6.0`, LSUIElement `true`, LSMinimumSystemVersion `14.0`, CFBundleIconFile, NSHumanReadableCopyright; copy `packaging/AppIcon.icns`; `codesign --force --sign - build/Pomodoro.app` (no `--deep`, single binary)
- `scripts/verify-app.sh`: runs `build-app.sh`, then `plutil -extract LSUIElement raw`, compares `CFBundleShortVersionString` to `VERSION`, runs `codesign --verify --strict`, and checks `lipo -archs` reports `arm64`
- `scripts/make-icon.sh` + `scripts/render-icon.swift`: draws a tomato-red rounded circle with a white arc on transparent background into an `.iconset`, runs `iconutil`; output `packaging/AppIcon.icns` is committed
- `scripts/render-cask.sh VERSION SHA256`: renders `packaging/pomodoro.rb.tmpl` to stdout
- `Makefile`: `build`, `test` (adds the plugin-path flag when `xcode-select -p` is the CLT path), `app`, `run` (app + `open`), `install` (`ditto` to `/Applications`), `verify-app`, `check-cask` (render with dummy values, `ruby -c`, fail if `__` remains), `clean`
- `.gitignore`: `.build/`, `build/`, `*.xcodeproj`, `.DS_Store`, `.swiftpm/`

### CI and release
- `.github/workflows/ci.yml`: `on: push: branches: [main]` and `pull_request`; `runs-on: macos-26`; steps `make test`, `make verify-app`, `make check-cask`
- `.github/workflows/release.yml`: `on: push: tags: ['v*']`; `permissions: contents: write`; `runs-on: macos-26`; steps: guard `"v$(cat VERSION)" == "$GITHUB_REF_NAME"` else fail → `make test` → `make verify-app` → `ditto -c -k --keepParent build/Pomodoro.app "Pomodoro-$VERSION.zip"` → `shasum -a 256` → `gh release create "$GITHUB_REF_NAME" "Pomodoro-$VERSION.zip" --generate-notes` with `GH_TOKEN: ${{ github.token }}` → `actions/checkout` with `repository: lavals/homebrew-tap`, `token: ${{ secrets.TAP_GITHUB_TOKEN }}`, `path: tap` → `scripts/render-cask.sh "$VERSION" "$SHA" > tap/Casks/pomodoro.rb` → in `tap/`: `git config user.name "github-actions[bot]"`, `git config user.email "41898282+github-actions[bot]@users.noreply.github.com"`, commit `pomodoro X.Y.Z` **only if `git diff --quiet` fails**, push
- `packaging/pomodoro.rb.tmpl`:
  ```ruby
  cask "pomodoro" do
    version "__VERSION__"
    sha256 "__SHA256__"
    url "https://github.com/lavals/mac-pomodoro-timer/releases/download/v#{version}/Pomodoro-#{version}.zip"
    name "Pomodoro"
    desc "Menu bar pomodoro timer that turns on macOS Focus while you work"
    homepage "https://github.com/lavals/mac-pomodoro-timer"
    depends_on macos: ">= :sonoma"
    depends_on arch: :arm64
    app "Pomodoro.app"
    postflight do
      system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Pomodoro.app"]
    end
    uninstall quit: "com.lavals.pomodoro"
    zap trash: ["~/Library/Preferences/com.lavals.pomodoro.plist"]
  end
  ```

## What Goes Where
- **Implementation Steps** (`[ ]` checkboxes): everything that lives in this repo — Swift code, tests, scripts, workflows, templates, docs
- **Post-Completion** (no checkboxes): GitHub-side setup (PAT secret, first tag), Shortcuts creation, manual UI checks on this and other Macs

## Implementation Steps

### Task 1: Scaffold the Swift package, Makefile and repo hygiene

**Files:**
- Create: `Package.swift`
- Create: `Sources/Pomodoro/main.swift`
- Create: `Sources/PomodoroCore/App/AppInfo.swift`
- Create: `Tests/PomodoroCoreTests/SmokeTests.swift`
- Create: `Makefile`
- Create: `.gitignore`
- Create: `VERSION`

- [x] set local git identity for this repo: `git config user.name lavals` and `git config user.email 43458274+lavals@users.noreply.github.com` (repo-local only, not global)
- [x] create `Package.swift` (tools 5.10, macOS 14, library `PomodoroCore`, executable `Pomodoro` depending on it, test target `PomodoroCoreTests`, `swiftLanguageVersions: [.v5]`)
- [x] create `main.swift` (accessory activation policy, empty `AppDelegate` for now, prints `AppInfo.version`) and `AppInfo.swift` (bundle version with `"dev"` fallback)
- [x] create `Makefile` with `build`, `test` (CLT-aware plugin-path flag), `clean`; `.gitignore`; `VERSION` = `0.1.0`
- [x] write `SmokeTests.swift` with one `@Test` asserting `AppInfo.version` is non-empty
- [x] run `make build` and `make test` - the single test must execute and pass (proves the toolchain workaround) before task 2

### Task 2: Preferences backed by UserDefaults

**Files:**
- Create: `Sources/PomodoroCore/Settings/Preferences.swift`
- Create: `Tests/PomodoroCoreTests/TestDefaults.swift` (helper: unique suite + cleanup)
- Create: `Tests/PomodoroCoreTests/PreferencesTests.swift`
- Create: `Sources/PomodoroCore/Timer/TimerState.swift` (only `Phase` and `Durations`, needed by `Preferences.durations`)

- [x] implement `Preferences` (`@Observable`, injected `UserDefaults`) with `workMinutes`, `restMinutes`, `showCountdown`, defaults 25/5/true
- [x] clamp minute setters to 1…120 in `didSet` and expose `durations: Durations` (define `Durations` here or in Task 3's file; keep one definition); `Phase` and `Durations` live in `Timer/TimerState.swift`, Task 3 adds the rest
- [x] write the `TestDefaults` helper (unique suite name per test, `removePersistentDomain` cleanup)
- [x] write tests for defaults when the suite is empty
- [x] write tests for persistence round-trip and clamping (0 → 1, 500 → 120)
- [x] run `make test` - must pass before task 3

### Task 3: Timer engine state machine

**Files:**
- Modify: `Sources/PomodoroCore/Timer/TimerState.swift` (Phase and Durations exist from Task 2; add TimerState, Effect, Chime)
- Create: `Sources/PomodoroCore/Timer/TimerEngine.swift`
- Create: `Sources/PomodoroCore/Timer/TimeFormatting.swift`
- Create: `Tests/PomodoroCoreTests/TimerEngineTests.swift`
- Create: `Tests/PomodoroCoreTests/TimeFormattingTests.swift`

- [x] implement the types from Technical Details with `Codable` + `Equatable`
- [x] implement `init(state:)`, `start`, `pause`, `skip`, `reset`, `tick`, `remaining(now:)`, `progress(now:)`, `nextPhase`
- [x] implement `formatRemaining(_:) -> String` (`mm:ss`, ceil to seconds, caps at `99:59`)
- [x] write table-driven tests (`@Test(arguments:)`) covering every row of the transition table, including no-op rows and **resume from paused(work) emitting `focusOn`**
- [x] write tests for exact effect ordering at work end and rest end, and that `skip` never chimes
- [x] write tests for sleep/wake: `tick` with `now` far past `endDate` finishes once and the next `tick` returns `[]`; `remaining` never goes negative; `progress` clamps to 1
- [x] write tests for `formatRemaining` (0, 59, 60, 1500, 1499.6 → `25:00`, overflow → `99:59`)
- [x] run `make test` - must pass before task 4

### Task 4: Session persistence and restore

**Files:**
- Create: `Sources/PomodoroCore/Timer/SessionStore.swift`
- Modify: `Sources/PomodoroCore/Timer/TimerEngine.swift` (add `static func restore(_:now:)`)
- Create: `Tests/PomodoroCoreTests/SessionStoreTests.swift`
- Modify: `Tests/PomodoroCoreTests/TimerEngineTests.swift` (restore cases)

- [x] implement `SessionStore` (`save`, `load`, `clear`) as JSON in injected `UserDefaults`
- [x] implement `TimerEngine.restore(_:now:)` per Technical Details
- [x] write tests for save/load round-trip of every `TimerState` case and `load()` returning nil on empty or corrupt data
- [x] write tests for each restore branch (expired work → focusOff, expired rest → none, future work → focusOn, nil/idle/paused/finished → unchanged)
- [x] run `make test` - must pass before task 5

### Task 5: Focus controller over the shortcuts CLI

**Files:**
- Create: `Sources/PomodoroCore/Focus/ShellRunner.swift` (protocol, `ShellResult`, `ProcessShellRunner`)
- Create: `Sources/PomodoroCore/Focus/FocusController.swift`
- Create: `Tests/PomodoroCoreTests/FakeShellRunner.swift`
- Create: `Tests/PomodoroCoreTests/FocusControllerTests.swift`
- Create: `Tests/PomodoroCoreTests/ProcessShellRunnerTests.swift`

- [x] implement `ProcessShellRunner` (async, pipes drained concurrently, timeout → `terminate()`)
- [x] implement `FocusController.availability()` parsing `shortcuts list` output (trim, exact match on both names)
- [x] implement `setFocus(_:)` returning `.failure(.notInstalled / .failed / .timeout)` without throwing
- [x] write tests with `FakeShellRunner`: both names present → `.available`; one missing → `.missing(["Pomodoro Focus Off"])`; list fails → `.error`
- [x] write tests for `setFocus` success, non-zero exit with stderr captured, and timeout mapping
- [x] write tests for `ProcessShellRunner` against `/bin/sh -c` (captures stdout and stderr, non-zero status, large output of 1 MB does not deadlock, `sleep 5` with 0.2s timeout returns `.timeout`)
- [x] run `make test` - must pass before task 6

### Task 6: Timer coordinator with alerts and effect execution

**Files:**
- Create: `Sources/PomodoroCore/App/Alerts.swift` (protocol + `SystemAlerts`: `NSSound(named:)`, `UNUserNotificationCenter` guarded by bundle id)
- Create: `Sources/PomodoroCore/App/TimerCoordinator.swift`
- Create: `Sources/PomodoroCore/App/TimerPresentation.swift`
- Create: `Sources/PomodoroCore/App/AppDelegate.swift` (notification delegate, authorization request, termination hook)
- Modify: `Sources/Pomodoro/main.swift` (use the real `AppDelegate`)
- Create: `Tests/PomodoroCoreTests/FakeAlerts.swift`
- Create: `Tests/PomodoroCoreTests/TimerCoordinatorTests.swift`
- Create: `Tests/PomodoroCoreTests/TimerPresentationTests.swift`

- [x] implement `Alerts` protocol and `SystemAlerts`
- [x] implement `TimerCoordinator` per Technical Details (stored `now`, unconditional save after each mutation, effect execution rules, focus skipping when unavailable, `lastFocusError`, `.common`-mode timer only while running, `beginActivity`, wake observer on `NSWorkspace.shared.notificationCenter`, `prepareForTermination`)
- [x] implement `TimerPresentation` pure helpers (`primaryActionTitle`, `phaseLabel`, `ringTint`, `menuItems`)
- [x] implement `AppDelegate` (delegate `willPresent` → banner + list, `requestAuthorization` every launch behind the bundle-id guard, `applicationWillTerminate` → `prepareForTermination`)
- [x] write coordinator tests with a fake clock, `FakeShellRunner`, `FakeAlerts`, `TestDefaults`: start saves state and calls focus on; advancing the clock and calling `tick()` plays the chime, calls focus off, then posts the notification; pause/skip/reset each persist the new state; `displayTime` changes after the clock advances and an observation registered on it fires; idle and finished show the next phase's full duration
- [x] write tests that focus effects are skipped when availability is `.missing` with no error set; a failed `setFocus` sets `lastFocusError` and the next success clears it; the timer keeps running regardless; `prepareForTermination` calls focus off only when work was running
- [x] write tests for `TimerPresentation` mappings for every state
- [x] run `make test` - must pass before task 7
- ➕ implementation notes: while `focusAvailability` is `.unknown` (no check yet since launch) the first Focus effect runs `shortcuts list` first, so restore effects and the first start work without the popover having been opened; `prepareForTermination` runs only for `running(work)` with availability `.available` (paused work already turned Focus off); the ticker is a `Ticker` protocol + `TickerFactory` (real `SystemTicker` owns the `beginActivity` token); the wake observer `NotificationCenter` is injectable (tests post on a private center); `PrimaryAction`, `RingTint` and `MenuItem` are small enums in `TimerPresentation.swift`

### Task 7: Status item with two display modes and right-click menu

**Files:**
- Create: `Sources/PomodoroCore/App/StatusItemController.swift`
- Create: `Sources/PomodoroCore/App/GlyphSpec.swift` (pure: style filled/outlined/dimmed + arc fraction from state/progress)
- Create: `Sources/PomodoroCore/App/StatusGlyph.swift` (renders `GlyphSpec` into a template `NSImage`)
- Create: `Sources/PomodoroCore/App/StatusTitle.swift` (pure `NSAttributedString` builder)
- Modify: `Sources/PomodoroCore/App/AppDelegate.swift` (create the status item)
- Create: `Tests/PomodoroCoreTests/GlyphSpecTests.swift`
- Create: `Tests/PomodoroCoreTests/StatusTitleTests.swift`

- [x] implement `GlyphSpec.make(state:progress:)` and `StatusGlyph.image(spec:)` (18×18, `isTemplate = true`)
- [x] implement `StatusTitle.make(time:phase:showCountdown:)` (monospaced digits, tint per phase, empty when hidden)
- [x] implement `StatusItemController`: left/right click detection, temporary-menu trick with `menuDidClose`, `withObservationTracking` re-render on main; menu items from `TimerPresentation.menuItems` with "Settings…" disabled until Task 9
- [x] write tests for `GlyphSpec` (idle → dimmed/0, running work → filled/progress, running rest → outlined/progress, paused keeps progress, finished → full arc)
- [x] write tests for `StatusTitle` (hidden → empty, shown → contains `mm:ss`, font has monospaced-digit trait, color per phase) and a non-nil template image of 18×18 from `StatusGlyph`
- [x] run `make test`, then `make build` and launch the binary to confirm the item renders in both modes and the menu works - must pass before task 8 (tests and build pass; binary launched unbundled and stayed up without crashing; visual check deferred to Task 14 manual walkthrough)
- ➕ implementation notes: until the popover lands in Task 8, a left click opens the same menu as a right click; `StatusTitle.make` takes `phase: Phase?` (nil = idle/finished → secondary tint) plus a `StatusTitle.phase(for:)` helper; menu construction is a static `StatusItemController.makeMenu(items:showCountdown:target:action:)` (item tag = index in `TimerPresentation.menuItems`) and is unit-tested; finished glyphs keep their phase style (filled work / outlined rest) with a full arc

### Task 8: Popover with progress ring

**Files:**
- Create: `Sources/PomodoroCore/Views/ProgressRing.swift`
- Create: `Sources/PomodoroCore/Views/PopoverView.swift`
- Modify: `Sources/PomodoroCore/App/StatusItemController.swift` (host `PopoverView`, activate before show, refresh availability after show)
- Modify: `Tests/PomodoroCoreTests/TimerPresentationTests.swift`

- [x] implement `ProgressRing(progress:tint:)` with trailing round cap and a subtle track
- [x] implement `PopoverView` per Technical Details reading from `TimerCoordinator` (gear button and Focus hint are wired in Tasks 9 and 10; leave placeholders disabled)
- [x] host it in the `NSPopover` with `.preferredContentSize` sizing, `NSApp.activate()` before show, `refreshFocusAvailability()` after show
- [x] write tests for any new presentation mapping introduced by the view (secondary button visibility per state: `Skip` while running/paused, `Reset` when finished, none when idle)
- [x] run `make test` and smoke-launch to check layout in light and dark mode - must pass before task 9 (tests pass; binary launched unbundled with an idle saved session and stayed up without crashing; visual check deferred to Task 14 manual walkthrough)
- ➕ implementation notes: new `SecondaryAction` enum + `TimerPresentation.secondaryAction(for:)` (the popover shows only Skip while running/paused; Reset during a phase stays in the right-click menu); `RingTint.nsColor`/`.color` live in `ProgressRing.swift` and match `StatusTitle` colors; popover construction is a static `StatusItemController.makePopover(coordinator:)` and is unit-tested (transient, `.preferredContentSize`, fitting width 240 / height ≥ 280); the disabled Focus hint placeholder is a caption label shown for `.missing`/`.error` (`PopoverView.showsFocusHint`), replaced by `FocusHintView` in Task 10; opening the right-click menu closes an open popover

### Task 9: Settings window with launch-at-login

**Files:**
- Create: `Sources/PomodoroCore/Settings/LaunchAtLoginModel.swift` (`LoginService` protocol, `SMAppServiceLoginService`, model)
- Create: `Sources/PomodoroCore/Views/SettingsView.swift`
- Create: `Sources/PomodoroCore/App/SettingsWindowController.swift`
- Modify: `Sources/PomodoroCore/App/StatusItemController.swift` (enable "Settings…")
- Modify: `Sources/PomodoroCore/Views/PopoverView.swift` (gear button)
- Modify: `Sources/PomodoroCore/App/AppDelegate.swift` (own the window controller)
- Create: `Tests/PomodoroCoreTests/LaunchAtLoginModelTests.swift`

- [x] implement `LaunchAtLoginModel` per Technical Details (status mirroring, requiresApproval branch, error message, unbundled guard)
- [x] implement `SettingsView` (`@Bindable` preferences, two steppers 1…120, countdown toggle, launch-at-login toggle with inline message); note in code that duration changes apply to the next session
- [x] implement `SettingsWindowController` (reusable window, `isReleasedWhenClosed = false`, activate + front, centered) and wire the menu item and gear button
- [x] write tests for `LaunchAtLoginModel` with a fake `LoginService`: enabling calls `register`, disabling calls `unregister`, `.requiresApproval` yields the approval message and opens settings via an injected closure, a throwing service surfaces its message and leaves `isEnabled` unchanged
- [x] run `make test` and smoke-launch - must pass before task 10 (tests pass; binary launched unbundled with an idle saved session and stayed up without crashing; visual check deferred to Task 14 manual walkthrough)
- ➕ implementation notes: `LoginService` exposes `SMAppService.Status` directly so fakes return real status values; `LaunchAtLoginModel` is `@MainActor @Observable` with `setEnabled(_:)` and `refresh()` (called each time the settings window is shown, so changes made in System Settings show up); a `register()` that throws while the status is `.requiresApproval` is treated as the approval branch, not an error; on launch with a pending approval the message shows but System Settings is not opened; `SettingsWindowController.makeWindow(title:rootView:)` is a static helper Task 10 can reuse for the Focus setup window; the popover gear button closes the popover before opening settings

### Task 10: Focus setup window and hint

**Files:**
- Create: `Sources/PomodoroCore/Views/FocusHintView.swift`
- Create: `Sources/PomodoroCore/Views/FocusSetupView.swift`
- Create: `Sources/PomodoroCore/App/FocusSetupWindowController.swift`
- Modify: `Sources/PomodoroCore/Views/PopoverView.swift` (show the hint)
- Modify: `Sources/PomodoroCore/App/AppDelegate.swift` (own the window controller)
- Modify: `Tests/PomodoroCoreTests/TimerCoordinatorTests.swift`
- Create: `Tests/PomodoroCoreTests/FocusSetupTests.swift`
- Modify: `Sources/PomodoroCore/App/StatusItemController.swift` (pass the setup opener to the popover)

- [x] implement `FocusHintView` (shown for `.missing`/`.error`, "Set up…" opens the setup window)
- [x] implement `FocusSetupView` and `FocusSetupWindowController` per Technical Details
- [x] write tests that `refreshFocusAvailability()` updates `focusAvailability` from `FakeShellRunner` (available, missing one name, list error) and that `start()` with `.missing` runs the timer with no shell call and no error
- [x] run `make test` and smoke-launch with the shortcuts temporarily renamed to see the hint and sheet - must pass before task 11 (tests pass; binary launched unbundled with an idle saved session and stayed up without crashing; visual check deferred to Task 14 manual walkthrough; user's shortcuts not modified)
- ➕ implementation notes: `FocusHintView.message(for:)` is the single source for when the hint shows (`PopoverView.showsFocusHint` delegates to it) and names the shortcut when exactly one is missing; `FocusSetupView` shows a status line from `statusText(for:)` that updates live as "Check again" refreshes availability; the guide link points at `https://github.com/lavals/mac-pomodoro-timer/blob/main/docs/focus-shortcuts.md` (the doc itself is written in Task 13); the setup window reuses `SettingsWindowController.makeWindow` and re-checks availability each time it is shown; the popover closes before opening the setup window; view tests live in a new `Tests/PomodoroCoreTests/FocusSetupTests.swift`

### Task 11: App bundle build script, icon and verification

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/verify-app.sh`
- Create: `scripts/make-icon.sh`
- Create: `scripts/render-icon.swift`
- Create: `packaging/Info.plist.tmpl`
- Create: `packaging/AppIcon.icns` (generated, committed)
- Modify: `Makefile` (add `app`, `run`, `install`, `verify-app`)

- [x] write `render-icon.swift` and `make-icon.sh`, generate and commit `AppIcon.icns`
- [x] write `Info.plist.tmpl` (all keys from Technical Details) and `build-app.sh` (`--show-bin-path`, bundle layout, plist rendering from `VERSION`, icon copy, `codesign --force --sign -`)
- [x] write `verify-app.sh` (LSUIElement, version equals `VERSION`, `codesign --verify --strict`, `lipo -archs` = arm64) and add `make app`, `make run`, `make install`, `make verify-app`
- [x] run `make verify-app` as this task's test (shell checks live in the script, not in Swift tests) - must pass
- [x] run `make run` and confirm: no Dock icon, notification permission prompt appears, banner shows at session end while the popover is open - must pass before task 12 (no Dock icon proven by `make verify-app` checking LSUIElement=true; unbundled debug binary launched for 4s with an idle saved session, stayed up, killed; the bundled app was not launched per session constraints; notification prompt and banner check deferred to Task 14 manual walkthrough)
- ➕ implementation notes: `render-icon.swift` draws exact pixel sizes into an `NSBitmapImageRep` (gradient tomato circle, white 3/4 arc with round caps) and is run by `make-icon.sh` with `swift <script>` into a temp `.iconset`; `build-app.sh` lints the rendered plist with `plutil -lint`; `verify-app.sh` additionally checks the bundle id and that `AppIcon.icns` is in Resources; `make install` replaces any existing `/Applications/Pomodoro.app` with `ditto` (targets `run`/`install` are written but were not executed)

### Task 12: GitHub Actions CI, release workflow and cask template

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `packaging/pomodoro.rb.tmpl`
- Create: `scripts/render-cask.sh`
- Modify: `Makefile` (add `check-cask`)

- [x] write `pomodoro.rb.tmpl` (as in Technical Details) and `render-cask.sh`
- [x] add `make check-cask` (render with dummy values, `ruby -c`, fail if `__` remains) and run it
- [x] write `ci.yml` (`main` pushes + PRs, `macos-26`, `make test`, `make verify-app`, `make check-cask`)
- [x] write `release.yml` per Technical Details (tag guard, permissions, release upload, tap checkout with PAT, bot identity, commit only on change, push)
- [x] validate both workflows with `actionlint` (`brew install actionlint` if missing) and `make check-cask` as this task's tests - must pass before task 13
- ➕ implementation notes: `render-cask.sh` rejects a version that is not `X.Y.Z` and a SHA that is not 64 lowercase hex chars; `check-cask` runs under `set -e` so a `ruby -c` syntax error fails the target (verified by breaking the template on purpose); the release tap step runs `mkdir -p tap/Casks` (the tap may be empty) and does `git add` then `git diff --cached --quiet`, since plain `git diff --quiet` does not see a newly created, untracked cask file on the first release; both workflows pin `actions/checkout@v5`, CI has `permissions: contents: read`, and `actionlint` 1.7.12 (with shellcheck) reports no errors

### Task 13: README and Focus shortcut instructions

**Files:**
- Create: `README.md`
- Create: `docs/focus-shortcuts.md`
- Modify: `Sources/PomodoroCore/Views/FocusSetupView.swift` (link to the doc)
- Modify: `Makefile` (add `check-docs`)

- [x] write `README.md`: what it is, screenshot placeholder, install (`brew tap lavals/tap && brew install pomodoro`), why the cask strips quarantine and the expected "signer changed" warning on upgrade, Apple Silicon only, upgrade, build from source (`make run`), release process (bump `VERSION`, tag `vX.Y.Z`, push)
- [x] write `docs/focus-shortcuts.md`: exact steps to create `Pomodoro Focus On` / `Pomodoro Focus Off` with the Set Focus action, choosing Do Not Disturb vs a custom Pomodoro Focus, enabling Share Across Devices, verifying with `shortcuts list`
- [x] link the doc from `FocusSetupView` and README (`FocusSetupView.guideURL` already pointed at `docs/focus-shortcuts.md` since task 10; README links it)
- [x] add `make check-docs` (grep both shortcut names in README and the doc) and add it to `ci.yml`
- [x] run `make check-docs` and `make test` - must pass before task 14

### Task 14: Verify acceptance criteria
- [ ] verify all requirements from Overview are implemented: configurable durations, hideable countdown, Focus on/off around work (including after pause/resume), chime-then-wait, right-click menu, settings window, launch at login, dark mode
- [ ] verify edge cases: sleep/wake overrun, quit during work turns Focus off, relaunch mid-session resumes, relaunch after a pause does not resurrect a running session, missing shortcuts show the hint and never block, corrupt saved session is ignored, countdown keeps updating while the right-click menu is open
- [ ] run full test suite: `make test`
- [ ] run `make verify-app`, `make check-cask`, `make check-docs`
- [ ] run `make run` and walk through a 1-minute work / 1-minute rest cycle end to end on this Mac, checking Slack in the browser goes quiet

### Task 15: [Final] Update documentation
- [ ] update README.md if needed
- [ ] create CLAUDE.md with: `make test` (never bare `swift test` on CLT machines, and why), Swift Testing only, the unbundled `UNUserNotificationCenter` guard, `--show-bin-path`, the release checklist, and the no-personal-data rule
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems - no checkboxes, informational only*

**GitHub setup (lavals account):**
- done: `lavals/mac-pomodoro-timer` is public, `lavals/homebrew-tap` is public and cloned to `../homebrew-tap`
- push an initial commit to the tap: `Casks/.gitkeep` and a one-line README
- create a fine-grained PAT scoped to `lavals/homebrew-tap` with Contents: read/write; add it to this repo as the `TAP_GITHUB_TOKEN` Actions secret; note its expiry date somewhere you will see it, since fine-grained PATs expire
- push `v0.1.0` and confirm the release workflow publishes the zip and the cask commit

**Per-Mac setup:**
- create the two Shortcuts once (they sync via iCloud to other Macs and the iPhone); enable Focus → Share Across Devices if the phone should go quiet too
- `brew tap lavals/tap && brew install pomodoro`
- approve the notification permission prompt on first launch; approve the login item in System Settings if prompted

**Manual verification:**
- light and dark mode appearance of status item, popover, settings
- countdown hidden mode: glyph states for idle/work/rest and the progress arc
- Focus actually silences Slack in the browser during a work session and lifts at the end
- close the lid mid-session, reopen after the end time: session finishes immediately, Focus is off, chime plays
- `brew upgrade pomodoro` after a second tagged release quits the running app, replaces it in `/Applications`, and the app launches without a Gatekeeper block
