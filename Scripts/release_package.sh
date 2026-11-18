#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.4.8}"
export SIGNING_MODE=developer-id
: "${APPLE_TEAM_ID:?Official releases require APPLE_TEAM_ID}"
: "${CODE_SIGN_IDENTITY:?Official releases require Developer ID signing}"
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
  printf 'Official releases cannot use ad-hoc signing.\n' >&2
  exit 1
fi
DMG_NAME="Codex-Usage-Bar-v$VERSION-universal.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
CHECKSUM_PATH="$ROOT/dist/$DMG_NAME.sha256"

"$ROOT/Scripts/package.sh"
"$ROOT/Scripts/notarize.sh" "$ROOT/dist/Codex Usage Bar.app"
"$ROOT/Scripts/create_dmg.sh"
"$ROOT/Scripts/notarize.sh" "$DMG_PATH"
python3 "$ROOT/Scripts/verify_signing.py" --app "$ROOT/dist/Codex Usage Bar.app" --team "$APPLE_TEAM_ID" --version "$VERSION" --notarized

(
  cd "$ROOT/dist"
  shasum -a 256 "$DMG_NAME" >"$(basename "$CHECKSUM_PATH")"
)

printf 'Release DMG: %s\n' "$DMG_PATH"
printf 'Checksum: %s\n' "$CHECKSUM_PATH"
