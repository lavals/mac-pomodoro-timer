#!/usr/bin/env bash
# Regenerates packaging/AppIcon.icns from scripts/render-icon.swift.
# The output is committed, so this only needs to run when the icon design changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
swift "$ROOT/scripts/render-icon.swift" "$ICONSET"
iconutil --convert icns --output "$ROOT/packaging/AppIcon.icns" "$ICONSET"
echo "wrote packaging/AppIcon.icns"
