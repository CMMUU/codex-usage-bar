#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/docs/images/usage-popover.png"

cd "$ROOT"

swift build
BIN_DIR="$(swift build --show-bin-path)"

CODEX_USAGE_BAR_DOCUMENTATION_SNAPSHOT="$OUTPUT" \
  "$BIN_DIR/CodexUsageBar"

test -s "$OUTPUT"
file "$OUTPUT"
printf 'Documentation snapshot: %s\n' "$OUTPUT"
