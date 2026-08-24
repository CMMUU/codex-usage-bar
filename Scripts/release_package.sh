#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.3.3}"
DMG_NAME="Codex-Usage-Bar-v$VERSION-universal.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
CHECKSUM_PATH="$ROOT/dist/$DMG_NAME.sha256"

"$ROOT/Scripts/package.sh"
"$ROOT/Scripts/create_dmg.sh"

if [[ -n "${APPLE_NOTARY_KEY_BASE64:-}" ]]; then
  "$ROOT/Scripts/notarize.sh"
fi

(
  cd "$ROOT/dist"
  shasum -a 256 "$DMG_NAME" >"$(basename "$CHECKSUM_PATH")"
)

printf 'Release DMG: %s\n' "$DMG_PATH"
printf 'Checksum: %s\n' "$CHECKSUM_PATH"
