#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$PROJECT_ROOT/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
INFO_PLIST="$PROJECT_ROOT/Resources/Info.plist"
MESSENGER="$PROJECT_ROOT/Resources/yt_video_play_messenger.js"
BACKGROUND_BRIDGE="$PROJECT_ROOT/Resources/yt_background_bridge.js"

test -s "$ICON"
test -s "$MESSENGER"
test -s "$BACKGROUND_BRIDGE"
plutil -lint "$INFO_PLIST"
python3 -m json.tool "$PROJECT_ROOT/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" >/dev/null
python3 -m json.tool "$PROJECT_ROOT/Resources/Assets.xcassets/LaunchIcon.imageset/Contents.json" >/dev/null
python3 -m json.tool "$PROJECT_ROOT/Resources/Assets.xcassets/LaunchBackground.colorset/Contents.json" >/dev/null

ICON_WIDTH="$(sips -g pixelWidth "$ICON" | awk '/pixelWidth:/ {print $2}')"
ICON_HEIGHT="$(sips -g pixelHeight "$ICON" | awk '/pixelHeight:/ {print $2}')"
ICON_ALPHA="$(sips -g hasAlpha "$ICON" | awk '/hasAlpha:/ {print $2}')"

test "$ICON_WIDTH" = "1024"
test "$ICON_HEIGHT" = "1024"
test "$ICON_ALPHA" = "no"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")" = "ROZZA"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$INFO_PLIST")" = "AppIcon"
test "$(/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$INFO_PLIST")" = "audio"
grep -q 'Resources/yt_video_play_messenger.js' "$PROJECT_ROOT/project.yml"
grep -q 'Resources/yt_background_bridge.js' "$PROJECT_ROOT/project.yml"

if command -v node >/dev/null 2>&1; then
  node --check "$MESSENGER"
  node --check "$BACKGROUND_BRIDGE"
fi

echo "ROZZA resources verified: opaque 1024px AppIcon, launch artwork, YouTube messenger, background-only YouTube bridge, and background audio mode."
