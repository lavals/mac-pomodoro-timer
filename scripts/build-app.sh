#!/usr/bin/env bash
# Builds build/Pomodoro.app from the SwiftPM release binary:
# bundle layout, Info.plist rendered from VERSION, icon, ad-hoc signature.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ -z "$VERSION" ]]; then
    echo "VERSION file is empty" >&2
    exit 1
fi

swift build -c release --product Pomodoro
# the swiftbuild build system does not put binaries under .build/release, so ask SwiftPM
BIN="$(swift build -c release --show-bin-path)/Pomodoro"
if [[ ! -x "$BIN" ]]; then
    echo "release binary not found at $BIN" >&2
    exit 1
fi

APP="build/Pomodoro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Pomodoro"
sed "s/__VERSION__/$VERSION/g" packaging/Info.plist.tmpl > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# single binary, so no --deep; ad-hoc identity because the app is not notarized
codesign --force --sign - "$APP"

echo "built $APP ($VERSION)"
