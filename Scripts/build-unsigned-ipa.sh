#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$PROJECT_ROOT/build/unsigned-ipa-work"
OUTPUT_IPA="$PROJECT_ROOT/build/ROZZA-Unsigned.ipa"

command -v xcodegen >/dev/null 2>&1 || {
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

"$PROJECT_ROOT/Scripts/verify-ios-resources.sh"

rm -rf "$WORK_DIR"
rm -f "$OUTPUT_IPA"
mkdir -p "$WORK_DIR/Payload" "$(dirname "$OUTPUT_IPA")"

cd "$PROJECT_ROOT"
xcodegen generate
xcodebuild \
  -project ROZZA.xcodeproj \
  -scheme ROZZA \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

APP_PATH="$(find "$WORK_DIR/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit)"
test -n "$APP_PATH"
test -f "$APP_PATH/Info.plist"
test -s "$APP_PATH/Assets.car"
test -s "$APP_PATH/rozza2.html"
test -s "$APP_PATH/yt_video_play_messenger.js"
test -s "$APP_PATH/yt_background_bridge.js"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Info.plist")" = "ROZZA"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_PATH/Info.plist")" = "AppIcon"
test "$(/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$APP_PATH/Info.plist")" = "audio"

ditto "$APP_PATH" "$WORK_DIR/Payload/ROZZA.app"
ditto -c -k --sequesterRsrc --keepParent "$WORK_DIR/Payload" "$OUTPUT_IPA"

test -s "$OUTPUT_IPA"
echo "Unsigned IPA created at: $OUTPUT_IPA"
