#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/hackfm/hackfm.xcodeproj"
SCHEME="HackFM"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS_PATH="$ROOT_DIR/hackfm/hackfm/Supporting/HackFM.entitlements"

ENV_PATH="$ROOT_DIR/.env"
if [[ -f "$ENV_PATH" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_PATH"
  set +a
fi


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

if [[ -n "${APPLE_SIGN_IDENTITY:-}" ]]; then
  echo "Codesigning with identity: $APPLE_SIGN_IDENTITY"

  sign_item() {
    local item="$1"
    codesign --force --options runtime --sign "$APPLE_SIGN_IDENTITY" "$item"
  }

  # Sign embedded frameworks and libraries first
  for framework in "$APP_PATH"/Contents/Frameworks/*.framework; do
    if [[ -d "$framework" ]]; then
      sign_item "$framework"
    fi
  done

  if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' lib; do
      sign_item "$lib"
    done < <(find "$APP_PATH/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0)
  fi

  # Sign the app bundle last (with entitlements)
  codesign --force --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign "$APPLE_SIGN_IDENTITY" "$APP_PATH"
fi

mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/HackFM-Release.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Submitting for notarization..."
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
fi

echo "Release artifact: $ZIP_PATH"
