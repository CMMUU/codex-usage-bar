#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.3.4}"
DMG_PATH="$ROOT/dist/Codex-Usage-Bar-v$VERSION-universal.dmg"

: "${APPLE_NOTARY_KEY_BASE64:?APPLE_NOTARY_KEY_BASE64 is required}"
: "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
: "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"

if [[ ! -f "$DMG_PATH" ]]; then
  printf 'Missing DMG: %s\n' "$DMG_PATH" >&2
  exit 1
fi

NOTARY_KEY="$(mktemp)"
trap 'rm -f "$NOTARY_KEY"' EXIT
printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode >"$NOTARY_KEY"

xcrun notarytool submit "$DMG_PATH" \
  --key "$NOTARY_KEY" \
  --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
