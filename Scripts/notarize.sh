#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.4.6}"
TARGET="${1:-$ROOT/dist/Codex-Usage-Bar-v$VERSION-universal.dmg}"
if [[ ! -e "$TARGET" ]]; then
  printf 'Missing notarization target: %s\n' "$TARGET" >&2
  exit 1
fi
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
if [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_ARGUMENTS=(--keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${APPLE_NOTARY_KEY_PATH:-}" ]]; then
  : "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
  : "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"
  AUTH_ARGUMENTS=(--key "$APPLE_NOTARY_KEY_PATH" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")
else
  : "${APPLE_NOTARY_KEY_BASE64:?Notarization requires a keychain profile or Apple API key}"
  : "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
  : "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"
  NOTARY_KEY="$TEMP_DIR/notary.p8"
  printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode >"$NOTARY_KEY"
  chmod 600 "$NOTARY_KEY"
  AUTH_ARGUMENTS=(--key "$NOTARY_KEY" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID")
fi
UPLOAD="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  UPLOAD="$TEMP_DIR/application.zip"
  ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$UPLOAD"
fi
xcrun notarytool submit "$UPLOAD" "${AUTH_ARGUMENTS[@]}" --wait --timeout 20m
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
