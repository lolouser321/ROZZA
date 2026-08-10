#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$PROJECT_ROOT/build/unsigned-ipa-work"
OUTPUT_IPA="$PROJECT_ROOT/build/ROZZA-Unsigned.ipa"

command -v xcodegen >/dev/null 2>&1 || {
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
}

python3 "$PROJECT_ROOT/Scripts/qa-source.py"
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

# Every check below is silent-on-pass/silent-on-fail by design (test/cmp -s/
# grep -q), which previously meant a failure produced zero diagnostic output
# before set -e killed the script. Wrap each one so a failure always names
# itself in the log instead of leaving a bare "exit code 1".
check() {
  local desc="$1"; shift
  if "$@"; then
    echo "  [OK]   $desc"
  else
    echo "  [FAIL] $desc"
    exit 1
  fi
}
check_cmp() {
  local desc="$1" a="$2" b="$3"
  if cmp -s "$a" "$b"; then
    echo "  [OK]   $desc"
  else
    echo "  [FAIL] $desc"
    echo "         $a: $(wc -c < "$a" 2>/dev/null || echo '?') bytes"
    echo "         $b: $(wc -c < "$b" 2>/dev/null || echo '?') bytes"
    cmp "$a" "$b" || true
    exit 1
  fi
}

APP_PATH="$(find "$WORK_DIR/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit)"
check "app bundle found" test -n "$APP_PATH"
check "Info.plist present" test -f "$APP_PATH/Info.plist"
check "Assets.car present" test -s "$APP_PATH/Assets.car"
check "rozza2.html present" test -s "$APP_PATH/rozza2.html"
check "yt_video_play_messenger.js present" test -s "$APP_PATH/yt_video_play_messenger.js"
check "yt_background_bridge.js present" test -s "$APP_PATH/yt_background_bridge.js"
check "CFBundleDisplayName" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_PATH/Info.plist")" = "ROZZA"
check "CFBundleIconName" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_PATH/Info.plist")" = "AppIcon"
check "UIBackgroundModes[0]" test "$(/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$APP_PATH/Info.plist")" = "audio"
check "CFBundleShortVersionString == 4.0.5" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")" = "4.0.5"
check "CFBundleVersion == 25" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")" = "25"

# Build 25 regression guard: make sure Xcode packaged the new foreground ->
# native playback-intent handoff instead of a stale HTML or Swift build.
check_cmp "packaged rozza2.html matches source" "$PROJECT_ROOT/rozza2.html" "$APP_PATH/rozza2.html"
check_cmp "packaged yt_background_bridge.js matches source" "$PROJECT_ROOT/Resources/yt_background_bridge.js" "$APP_PATH/yt_background_bridge.js"
check "background handoff wantsPlayback line" grep -q "wantsPlayback: st.source==='youtube' ? !!YT.wantPlay : isPlaying" "$APP_PATH/rozza2.html"
check "native network fallback wired" grep -q "window.ROZZANativeNetwork=ROZZANativeNetwork" "$APP_PATH/rozza2.html"
check "persistent YouTube player switch" grep -q "cmd(autoplay ? 'loadVideoById' : 'cueVideoById', \[id\])" "$APP_PATH/rozza2.html"
check "background pulse event (HTML)" grep -q "ROZZA_BACKGROUND_PULSE" "$APP_PATH/rozza2.html"
check "background pulse receiver (bridge JS)" grep -q "ROZZA_BACKGROUND_PULSE" "$APP_PATH/yt_background_bridge.js"
check "mirror pool version 4" grep -q "const MIRROR_POOL_VERSION = 4;" "$APP_PATH/rozza2.html"
check "current Piped seed present" grep -q "pipedapi.orangenet.cc" "$APP_PATH/rozza2.html"
# `strings | grep -q` is unsafe under pipefail: grep -q exits as soon as it
# finds a match, which can SIGPIPE `strings` mid-write ("failed to flush
# output") and abort the whole script even though the match was found.
# Capture to a file once so grep's exit status is the only one that matters.
strings "$APP_PATH/ROZZA" > "$WORK_DIR/rozza-binary-strings.txt" || true
# No check here for the "networkProxy" message-handler name: at 12 bytes it
# is short enough for Swift's small-string optimization to encode it as a
# packed inline value instead of a plain byte run, so it legitimately does
# not appear in `strings` output even when the code is compiled in and
# working correctly (confirmed: this check failed on a build where the
# handler registration and proxyJSONRequest were both present and correct).
# qa-source.py already verifies the handler exists at the Swift source level,
# which is the reliable version of this check.
check "compiled binary contains background-capture log line" grep -q "Background capture wantsPlayback=" "$WORK_DIR/rozza-binary-strings.txt"

ditto "$APP_PATH" "$WORK_DIR/Payload/ROZZA.app"
ditto -c -k --sequesterRsrc --keepParent "$WORK_DIR/Payload" "$OUTPUT_IPA"

test -s "$OUTPUT_IPA"
echo "Unsigned IPA created at: $OUTPUT_IPA"
