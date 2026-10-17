# Pomodoro (macOS menu bar app)

Swift Package: library `PomodoroCore` (all code), thin executable `Pomodoro` (`main.swift` only), tests in `PomodoroCoreTests`. Needs Swift 6.2+ (`swift-tools-version:6.2`; `TimerCoordinator` uses `isolated deinit`), i.e. Command Line Tools for Xcode 26 on macOS 15.6+; the package compiles in Swift 5 language mode (`swiftLanguageModes: [.v5]`). Layers: `Timer` (pure state machine returning effects) <- `Settings` <- `Focus` (shortcuts CLI) <- `App` (coordinator, status item, windows) -> `Views` (SwiftUI). Keep AppKit/SwiftUI glue thin; logic goes in pure types behind small protocols.

## Commands

- `make test` - run tests. Never bare `swift test`: on Command Line Tools-only machines it fails with "plugin for module 'TestingMacros' not found" once the package has an executable target. `make test` adds the `-plugin-path` flag only when `xcode-select -p` is the CLT path, so CI (Xcode toolchain) runs plain `swift test`. Do not put that flag in `Package.swift`.
- `make build` - debug `swift build`; `make app` - assemble `build/Pomodoro.app` (release binary, Info.plist, icon, ad-hoc signature); `make clean` - remove `.build` and `build`
- `make verify-app` - build `build/Pomodoro.app` and check Info.plist, version, signature, arm64
- `make check-cask` - render the cask template with dummy values, `ruby -c` it, and (if `brew` is installed) load it with `HOMEBREW_DEVELOPER=1 brew ruby` so deprecated cask DSL fails the check (read-only: no tap, no install)
- `make check-docs` - both Focus shortcut names appear in README and `docs/focus-shortcuts.md`, and README links `docs/focus-shortcuts.md`
- `scripts/make-icon.sh` - regenerate the committed `packaging/AppIcon.icns` from `scripts/render-icon.swift`; only needed when the icon design changes
- `make run` / `make install` launch or install the real app; only run them when you mean to.

## Testing

- Swift Testing only (`import Testing`, `@Test`, `#expect`). XCTest is not available without Xcode.
- Tests run in parallel with no teardown: `UserDefaults` tests use a unique suite name per test and remove the domain in `defer`. Coordinator tests `await h.settle()` before returning so queued Focus tasks do not outlive the test.
- Exception: `SystemTickerTests` are `.serialized` and spin `RunLoop.main` by hand (`.eventTracking` and `.default` modes) for up to a few seconds, blocking other `@MainActor` tests meanwhile. Do not assert tight wall-clock bounds in main-actor tests; prove bounds with a semaphore instead (see `prepareForTerminationIsBoundedWhenTheShortcutHangs`).
- Never run the real `/usr/bin/shortcuts run ...` in tests; use `FakeShellRunner`. Same for alerts (`FakeAlerts`) and time (inject `now`).
- Shell scripts, workflows and docs are checked by Makefile targets and CI, not Swift tests.

## Gotchas

- Focus Off runs only when the app turned Focus on itself (`SessionStore.focusTurnedOn`, saved next to the session), never gated on `focusAvailability`; availability gates Focus On only and is re-checked whenever it is not `.available`.
- Quitting goes through `applicationShouldTerminate` -> `.terminateLater` so `prepareForTermination()` can await queued Focus calls and run Focus Off (both bounded) before the app exits.

- `UNUserNotificationCenter.current()` crashes in an unbundled process (`swift run`, tests). Guard on `Bundle.main.bundleIdentifier != nil` (see `SystemAlerts.canUseNotifications`).
- The 1s ticker must be added to the run loop in `.common` mode, or the countdown freezes while a menu is open.
- Release binaries land under `$(swift build -c release --show-bin-path)`, not `.build/release`.
- Command Line Tools build arm64 only; the cask declares `depends_on arch: :arm64`.
- Homebrew 7 has no `--no-quarantine`; the app is ad-hoc signed and not notarized, so the cask's `postflight_steps` runs `xattr -dr com.apple.quarantine {{appdir}}/Pomodoro.app` (the legacy `postflight do` block and `depends_on macos: ">= :sym"` are deprecated in Homebrew 7; `postflight_steps` runs in Homebrew's cask sandbox, which allows writes under appdir). Upgrades print a "signer changed" warning; that is expected.

## Release checklist

1. Bump `VERSION` (single source of truth) and commit.
2. `git tag vX.Y.Z` matching `VERSION`, push the tag.
3. `release.yml` refuses a tag that does not match `VERSION`, runs tests, builds and zips the app, checks out `lavals/homebrew-tap` with the `TAP_GITHUB_TOKEN` secret (fine-grained PAT, it expires), creates the GitHub release (or replaces its zip with `--clobber` on a re-run), renders `packaging/pomodoro.rb.tmpl` and pushes `Casks/pomodoro.rb` to the tap.
4. First release: the tap repo must already have at least one commit; `actions/checkout` fails on an empty repo. A failed run can be re-run for the same tag.

## Public repo rules

This repo is public. Commit only as the `lavals` GitHub no-reply identity. Never commit names, email addresses, home-directory paths, host aliases or account details; use repo-relative paths in all committed files.
