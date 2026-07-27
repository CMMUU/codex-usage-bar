#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  printf '%s\n' \
    "XcodeGen is required to regenerate CodexUsageBar.xcodeproj." \
    "Install it with: brew install xcodegen" \
    >&2
  exit 1
fi

cd "$ROOT"
xcodegen generate --spec project.yml
