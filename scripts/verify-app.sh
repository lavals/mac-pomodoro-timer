#!/usr/bin/env bash
# Builds the app bundle and checks it: menu-bar-only (LSUIElement), version matches
# VERSION, valid signature, arm64 binary. Exits non-zero on the first failed check.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/build-app.sh

APP="build/Pomodoro.app"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/Pomodoro"
EXPECTED_VERSION="$(tr -d '[:space:]' < VERSION)"

fail() {
    echo "verify-app: FAIL: $*" >&2
    exit 1
}

ui_element="$(plutil -extract LSUIElement raw "$PLIST")"
[[ "$ui_element" == "true" ]] || fail "LSUIElement is '$ui_element', expected 'true'"

version="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
[[ "$version" == "$EXPECTED_VERSION" ]] || fail "CFBundleShortVersionString is '$version', expected '$EXPECTED_VERSION'"

bundle_id="$(plutil -extract CFBundleIdentifier raw "$PLIST")"
[[ "$bundle_id" == "com.lavals.pomodoro" ]] || fail "CFBundleIdentifier is '$bundle_id'"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon.icns missing from Resources"

codesign --verify --strict "$APP" || fail "codesign --verify --strict failed"

archs="$(lipo -archs "$BIN")"
[[ "$archs" == "arm64" ]] || fail "binary architectures are '$archs', expected 'arm64'"

echo "verify-app: OK ($APP, version $version, $archs, LSUIElement=$ui_element)"
