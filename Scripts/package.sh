#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Usage Bar"
VERSION="${VERSION:-0.3.2}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.io.cmmuu.codex-usage-bar}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED_DATA="$ROOT/.build/xcode"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
APP_DIR="$ROOT/dist/$APP_NAME.app"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/CodexUsageWidget.appex"
ICON_PATH="$APP_DIR/Contents/Resources/AppIcon.icns"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"

cd "$ROOT"

if ! xcodebuild -version >/dev/null 2>&1; then
  printf '%s\n' \
    "Packaging the app and WidgetKit extension requires a full Xcode installation." \
    "Select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" \
    >&2
  exit 1
fi

"$ROOT/Scripts/generate-project.sh"

rm -rf "$DERIVED_DATA" "$APP_DIR"
mkdir -p "$ROOT/dist"

xcodebuild \
  -project "$ROOT/CodexUsageBar.xcodeproj" \
  -scheme CodexUsageBar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  APP_GROUP_IDENTIFIER="$APP_GROUP_IDENTIFIER" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

ditto "$APP_SOURCE" "$APP_DIR"

if [[ ! -d "$WIDGET_DIR" ]]; then
  printf 'Missing embedded WidgetKit extension: %s\n' "$WIDGET_DIR" >&2
  exit 1
fi
if [[ ! -f "$ICON_PATH" ]]; then
  printf 'Missing application icon: %s\n' "$ICON_PATH" >&2
  exit 1
fi
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  printf 'Missing embedded Sparkle framework: %s\n' "$SPARKLE_FRAMEWORK" >&2
  exit 1
fi

TEMPORARY_ENTITLEMENTS="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY_ENTITLEMENTS"' EXIT

cp \
  "$ROOT/Resources/CodexUsageBar.entitlements" \
  "$TEMPORARY_ENTITLEMENTS/app.entitlements"
cp \
  "$ROOT/Resources/CodexUsageWidget.entitlements" \
  "$TEMPORARY_ENTITLEMENTS/widget.entitlements"

/usr/libexec/PlistBuddy \
  -c "Set :com.apple.security.application-groups:0 $APP_GROUP_IDENTIFIER" \
  "$TEMPORARY_ENTITLEMENTS/app.entitlements"
/usr/libexec/PlistBuddy \
  -c "Set :com.apple.security.application-groups:0 $APP_GROUP_IDENTIFIER" \
  "$TEMPORARY_ENTITLEMENTS/widget.entitlements"

SIGN_ARGUMENTS=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi

SPARKLE_SIGN_ARGUMENTS=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime)
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  SPARKLE_SIGN_ARGUMENTS+=(--timestamp)
fi

codesign \
  "${SPARKLE_SIGN_ARGUMENTS[@]}" \
  "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign \
  "${SPARKLE_SIGN_ARGUMENTS[@]}" \
  --preserve-metadata=entitlements \
  "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign \
  "${SPARKLE_SIGN_ARGUMENTS[@]}" \
  "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign \
  "${SPARKLE_SIGN_ARGUMENTS[@]}" \
  "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign \
  "${SPARKLE_SIGN_ARGUMENTS[@]}" \
  "$SPARKLE_FRAMEWORK"

codesign \
  "${SIGN_ARGUMENTS[@]}" \
  --entitlements "$TEMPORARY_ENTITLEMENTS/widget.entitlements" \
  "$WIDGET_DIR"
codesign \
  "${SIGN_ARGUMENTS[@]}" \
  --entitlements "$TEMPORARY_ENTITLEMENTS/app.entitlements" \
  "$APP_DIR"

plutil -lint "$APP_DIR/Contents/Info.plist"
plutil -lint "$WIDGET_DIR/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

printf 'Packaged: %s\n' "$APP_DIR"
printf 'Version: %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'App Group: %s\n' "$APP_GROUP_IDENTIFIER"
printf 'Sparkle: 2.9.4\n'
