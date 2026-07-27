#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Usage Bar"
VERSION="${VERSION:-0.2.1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_DIR="$ROOT/dist/$APP_NAME.app"
DMG_PATH="$ROOT/dist/Codex-Usage-Bar-v$VERSION-universal.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  printf 'Missing app bundle: %s\n' "$APP_DIR" >&2
  exit 1
fi

STAGING_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

ditto "$APP_DIR" "$STAGING_DIRECTORY/$APP_NAME.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIRECTORY" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  codesign \
    --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --timestamp \
    "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

printf 'Created: %s\n' "$DMG_PATH"
