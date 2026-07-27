#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:?VERSION is required}"
TAG="${TAG:?TAG is required}"
REPOSITORY="${GITHUB_REPOSITORY:-CMMUU/codex-usage-bar}"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARCHIVE_SHA256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"
DMG_NAME="Codex-Usage-Bar-v$VERSION-universal.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
RELEASE_NOTES="$ROOT/docs/release-notes/$TAG.md"
APPCAST_PATH="$ROOT/dist/appcast.xml"

if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  printf 'Missing SPARKLE_EDDSA_PRIVATE_KEY\n' >&2
  exit 1
fi
if [[ ! -f "$DMG_PATH" ]]; then
  printf 'Missing release DMG: %s\n' "$DMG_PATH" >&2
  exit 1
fi
if [[ ! -f "$RELEASE_NOTES" ]]; then
  printf 'Missing release notes: %s\n' "$RELEASE_NOTES" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

SPARKLE_ARCHIVE="$TEMP_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 3 \
  --show-error \
  --silent \
  --tlsv1.2 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
  --output "$SPARKLE_ARCHIVE"

printf '%s  %s\n' "$SPARKLE_ARCHIVE_SHA256" "$SPARKLE_ARCHIVE" \
  | shasum -a 256 -c -
tar -xf "$SPARKLE_ARCHIVE" -C "$TEMP_DIR"

ARCHIVES_DIR="$TEMP_DIR/archives"
mkdir -p "$ARCHIVES_DIR"
cp "$DMG_PATH" "$ARCHIVES_DIR/$DMG_NAME"
cp \
  "$RELEASE_NOTES" \
  "$ARCHIVES_DIR/${DMG_NAME%.dmg}.md"

printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" \
  | "$TEMP_DIR/bin/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix \
      "https://github.com/$REPOSITORY/releases/download/$TAG/" \
    --embed-release-notes \
    --link "https://codex.cmmuu.com/" \
    --maximum-deltas 0 \
    --maximum-versions 1 \
    -o "$APPCAST_PATH" \
    "$ARCHIVES_DIR"

printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" \
  | "$TEMP_DIR/bin/sign_update" \
    --ed-key-file - \
    "$APPCAST_PATH"
printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" \
  | "$TEMP_DIR/bin/sign_update" \
    --ed-key-file - \
    --verify \
    "$APPCAST_PATH"

xmllint --noout "$APPCAST_PATH"
grep -q 'sparkle:edSignature=' "$APPCAST_PATH"
grep -q 'sparkle-signatures:' "$APPCAST_PATH"
grep -q "releases/download/$TAG/$DMG_NAME" "$APPCAST_PATH"

printf 'Sparkle appcast: %s\n' "$APPCAST_PATH"
