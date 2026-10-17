# Pomodoro

A small, native macOS menu bar pomodoro timer. Set your work and rest lengths, start a session from the menu bar, and the app turns on a macOS Focus while you work, so notifications from Slack in the browser and everything else stay quiet until the break.

<!-- Screenshot: add a picture of the menu bar countdown and the popover here. -->

## Features

- Configurable work and rest durations (1 to 120 minutes each; 25 and 5 by default)
- Countdown in the menu bar, or a compact glyph with a progress arc when you hide it
- A popover with a progress ring and Start, Pause, Skip and Reset buttons
- Turns a Focus on while a work session runs and off when it ends, is paused, skipped or reset
- Plays a chime and posts a notification at the end of each phase, then waits for you to start the next one
- Right-click menu with the same actions, the countdown toggle, Settings and Quit
- Settings window with an optional Launch at login switch
- Follows light and dark mode using system materials and colors

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon (arm64). Intel Macs are not supported.

## Install

```sh
brew tap lavals/tap
brew install pomodoro
```

Then open Pomodoro from `/Applications`. It lives in the menu bar and has no Dock icon. On first launch, allow notifications so you get an alert when a phase ends.

### Why the cask removes the quarantine flag

The app is signed ad hoc and is not notarized by Apple. Homebrew marks every downloaded cask with the `com.apple.quarantine` attribute, and Gatekeeper refuses to open an un-notarized app that carries it. The cask's `postflight` step removes that attribute from `/Applications/Pomodoro.app` so the app opens normally. If you prefer not to rely on that, build the app from source instead (see below).

## Set up Focus

Pomodoro switches Focus by running two shortcuts that you create once in the Shortcuts app:

- `Pomodoro Focus On`
- `Pomodoro Focus Off`

Follow the step-by-step guide in [docs/focus-shortcuts.md](docs/focus-shortcuts.md). While the shortcuts are missing, the popover shows a hint whose **Set up…** link opens the same steps in the app. Without them the timer still works; it just leaves Focus alone.

## Upgrade

```sh
brew upgrade pomodoro
```

Homebrew quits the running app, replaces it and you can open it again. Because each release is signed ad hoc, the signature changes from one build to the next, so Homebrew prints a warning that the signer changed. That is expected for this app.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`); full Xcode is not required.

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
| `make check-cask` | Renders the Homebrew cask template and checks its syntax       |
| `make check-docs` | Checks that the docs name both Focus shortcuts                 |

## Release process

1. Bump the version in `VERSION` (for example `0.2.0`) and commit it.
2. Tag the commit with the same version and push the tag:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The release workflow checks that the tag matches `VERSION`, runs the tests, builds and zips the app, publishes a GitHub release, and updates the cask in the `lavals/homebrew-tap` repository.

The workflow needs a `TAP_GITHUB_TOKEN` Actions secret: a fine-grained token with read and write access to the contents of the tap repository.

## License

See [LICENSE](LICENSE).
