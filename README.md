# Pomodoro

A small, native macOS menu bar pomodoro timer. Set your work and rest lengths, start a session from the menu bar, and the app turns on a macOS Focus while you work, so notifications from Slack in the browser and everything else stay quiet until the break.

<!-- Screenshot: add a picture of the menu bar countdown and the popover here. -->

## Features

- Configurable work and rest durations (1 to 120 minutes each; 25 and 5 by default)
- Countdown in the menu bar, or a compact glyph with a progress arc when you hide it
- A popover with a progress ring, one main button (Start Focus, Start Break, Pause or Resume) and a Skip button while a phase runs or is paused, or Reset once it finished
- Turns a Focus on while a work session runs and off when it ends, is paused, skipped or reset, or when you quit Pomodoro mid-session; resuming a paused work session turns it back on
- Survives a relaunch: reopening Pomodoro during a work session resumes the countdown and turns Focus back on
- Plays a chime and posts a notification at the end of each phase, then waits for you to start the next one
- Right-click (or Control-click) menu with the main action, Skip and Reset, the countdown toggle, Settings and Quit
- Settings window with Focus and Break lengths (1 to 120 minutes each), the menu bar countdown switch and an optional Launch at login switch. New lengths apply from the next session; turning on Launch at login may ask you to allow Pomodoro in System Settings › General › Login Items
- Follows light and dark mode using system materials and colors

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon (arm64). Intel Macs are not supported.
- Building from source needs more: see [Build from source](#build-from-source).

## Install

```sh
brew tap lavals/tap
brew install pomodoro
```

Then open Pomodoro from `/Applications`. It lives in the menu bar and has no Dock icon. On first launch, allow notifications so you get an alert when a phase ends.

### Why the cask removes the quarantine flag

The app is signed ad hoc and is not notarized by Apple. Homebrew marks every downloaded cask with the `com.apple.quarantine` attribute, and Gatekeeper refuses to open an un-notarized app that carries it. The cask's `postflight_steps` stanza runs `xattr` to remove that attribute from `/Applications/Pomodoro.app` so the app opens normally. If you prefer not to rely on that, build the app from source instead (see below; building needs macOS 15.6 or later).

## Set up Focus

Pomodoro switches Focus by running two shortcuts that you create once in the Shortcuts app:

- `Pomodoro Focus On`
- `Pomodoro Focus Off`

Follow the step-by-step guide in [docs/focus-shortcuts.md](docs/focus-shortcuts.md). While the shortcuts are missing, the popover shows a hint whose **Set up…** link opens the same steps in the app. Without them the timer still works; it just leaves Focus alone.

## Upgrade

```sh
brew upgrade pomodoro
```

Homebrew quits the running app, replaces it and reopens it. A work session that was running picks up where it left off and turns Focus back on. Because each release is signed ad hoc, the signature changes from one build to the next, so Homebrew prints a warning that the signer changed. That is expected for this app.

## Uninstall

```sh
brew uninstall --zap pomodoro
```

This quits the app, removes it and deletes its settings. If you no longer need them, delete the `Pomodoro Focus On` and `Pomodoro Focus Off` shortcuts in the Shortcuts app.

## Build from source

Requires Swift 6.2 or later: the Command Line Tools for Xcode 26 (`xcode-select --install`), which need macOS 15.6 or later. Full Xcode is not required. On macOS 14, install with Homebrew instead.

```sh
git clone https://github.com/lavals/mac-pomodoro-timer.git
cd mac-pomodoro-timer
make run
```

`make run` builds `build/Pomodoro.app` and opens it. Other targets:

| Target            | What it does                                                   |
| ----------------- | -------------------------------------------------------------- |
| `make test`       | Runs the test suite (use this rather than plain `swift test`)  |
| `make app`        | Builds the app bundle into `build/Pomodoro.app`                |
| `make install`    | Builds the app and copies it to `/Applications`                |
| `make verify-app` | Builds the bundle and checks its Info.plist, version and signature |
| `make check-cask` | Renders the Homebrew cask template, checks its syntax and loads it with Homebrew to catch deprecated cask syntax |
| `make check-docs` | Checks that the README and the Focus guide name both shortcuts and that the README links the guide |

## Release process

1. Bump the version in `VERSION` (for example `0.2.0`) and commit it.
2. Tag the commit with the same version and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The release workflow checks that the tag matches `VERSION`, runs the tests, builds and zips the app, checks out the tap, publishes the GitHub release, and updates the cask in the `lavals/homebrew-tap` repository.

First-time setup:

- The `lavals/homebrew-tap` repository must exist and have at least one commit (for example a README); the workflow cannot check out an empty repository.
- Add a `TAP_GITHUB_TOKEN` Actions secret: a fine-grained token with read and write access to the contents of the tap repository. Fine-grained tokens expire; when a release fails at "Check out tap", renew the token and update the secret.

If a release run fails, fix the cause and re-run the workflow for the same tag. It is safe to re-run: an existing GitHub release gets its zip replaced instead of failing, and the cask is rendered from that zip.

## License

See [LICENSE](LICENSE).
