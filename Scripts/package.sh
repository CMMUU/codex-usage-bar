#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Usage Bar"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_DIR/CodexUsageBar" "$MACOS_DIR/CodexUsageBar"
cp "$ROOT/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf 'Packaged: %s\n' "$APP_DIR"
