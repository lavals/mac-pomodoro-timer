#!/usr/bin/env bash
# Renders packaging/pomodoro.rb.tmpl to stdout.
# usage: scripts/render-cask.sh VERSION SHA256
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 VERSION SHA256" >&2
    exit 2
fi

VERSION="$1"
SHA256="$2"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "invalid version: $VERSION (expected X.Y.Z)" >&2
    exit 1
fi
if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "invalid sha256: $SHA256 (expected 64 lowercase hex chars)" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA256/g" "$ROOT/packaging/pomodoro.rb.tmpl"
