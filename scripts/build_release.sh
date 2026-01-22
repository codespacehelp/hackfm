#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/hackfm/hackfm.xcodeproj"
SCHEME="HackFM"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS_PATH="$ROOT_DIR/hackfm/hackfm/Supporting/HackFM.entitlements"

echo "Building Release..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/HackFM.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build output not found at $APP_PATH" >&2
  exit 1
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "Codesigning with identity: $SIGN_IDENTITY"
  codesign --force --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

if [[ -n "${NOTARIZE_APPLE_ID:-}" && -n "${NOTARIZE_TEAM_ID:-}" && -n "${NOTARIZE_APP_PASSWORD:-}" ]]; then
  echo "Submitting for notarization..."
  xcrun notarytool submit "$APP_PATH" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --team-id "$NOTARIZE_TEAM_ID" \
    --password "$NOTARIZE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
fi

mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/HackFM-Release.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Release artifact: $ZIP_PATH"
