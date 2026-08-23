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
# Negative source-text checks (confirm a string is absent) go through this
# helper rather than through check(), since passing a literal "!" as a
# check() argument tries to run a command named "!" instead of negating.
check_absent() {
  local desc="$1" pattern="$2" file="$3"
  if grep -q "$pattern" "$file"; then
    echo "  [FAIL] $desc"
    exit 1
  else
    echo "  [OK]   $desc"
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
check "CFBundleShortVersionString == 4.2.3" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")" = "4.2.3"
check "CFBundleVersion == 34" test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")" = "34"

# Build 34 remote/background stability guard: make sure Xcode packaged the
# boot-time engine restore, Drive Mode, HD artwork, hard human-pause fence,
# plus the real phone/Siri interruption state machine instead of a stale HTML
# or Swift build.
check_cmp "packaged rozza2.html matches source" "$PROJECT_ROOT/rozza2.html" "$APP_PATH/rozza2.html"
check_cmp "packaged yt_background_bridge.js matches source" "$PROJECT_ROOT/Resources/yt_background_bridge.js" "$APP_PATH/yt_background_bridge.js"
check "boot-time engine restore function" grep -q "function restorePlaybackEngineAfterBoot" "$APP_PATH/rozza2.html"
check "boot-time engine restore call" grep -q "Coordinator.restoreCurrent(shouldResume)" "$APP_PATH/rozza2.html"
check "remote play rebuilds missing engine" grep -q "remote-play-rebuild" "$APP_PATH/rozza2.html"
check "watchdog uses intent-preserving resume" grep -q "YT.resume('watchdog-stall')" "$APP_PATH/rozza2.html"
check "background handoff wantsPlayback line" grep -q "wantsPlayback: st.source==='youtube' ? !!YT.wantPlay : isPlaying" "$APP_PATH/rozza2.html"
check "native network fallback wired" grep -q "window.ROZZANativeNetwork=ROZZANativeNetwork" "$APP_PATH/rozza2.html"
check "persistent YouTube player switch" grep -q "cmd(autoplay ? 'loadVideoById' : 'cueVideoById', \[id\])" "$APP_PATH/rozza2.html"
check "background pulse event (HTML)" grep -q "ROZZA_BACKGROUND_PULSE" "$APP_PATH/rozza2.html"
check "background pulse receiver (bridge JS)" grep -q "ROZZA_BACKGROUND_PULSE" "$APP_PATH/yt_background_bridge.js"
check "mirror pool version 4" grep -q "const MIRROR_POOL_VERSION = 4;" "$APP_PATH/rozza2.html"
check "current Piped seed present" grep -q "pipedapi.orangenet.cc" "$APP_PATH/rozza2.html"
check "unified remote command dispatcher" grep -q "window.ROZZANativeControls.remote" "$APP_PATH/rozza2.html"
check "vehicle previous-track semantics" grep -q "Coordinator.previousTrack()" "$APP_PATH/rozza2.html"
check "vehicle command diagnostics" grep -q "window.ROZZARemoteDiagnostics=RemoteDiagnostics" "$APP_PATH/rozza2.html"
check "native Now Playing clear handoff" grep -q "postMessage({ clear:true" "$APP_PATH/rozza2.html"
check "native queue-index metadata" grep -q "queueIndex: Math.max(0,Q.idx)" "$APP_PATH/rozza2.html"
check "Drive Mode sheet present" grep -q 'id="driveSheet"' "$APP_PATH/rozza2.html"
check "artwork cover element present" grep -q 'id="ytArtworkCover"' "$APP_PATH/rozza2.html"
check "ROZZA signature present" grep -q 'rozza-signature' "$APP_PATH/rozza2.html"
check "HD artwork candidate chain" grep -q "maxresdefault.jpg" "$APP_PATH/rozza2.html"
check "HD artwork loader wired" grep -q "loadBestArtworkImage" "$APP_PATH/rozza2.html"
check "intent-preserving resume path" grep -q "YT.resume(reason)" "$APP_PATH/rozza2.html"
check "main-frame playbackIntent dispatch" grep -q "postPlaybackIntentToNative(true, reason)" "$APP_PATH/rozza2.html"
check_absent "legacy embed-error copy removed" "This video can’t be embedded right now." "$APP_PATH/rozza2.html"
check "continuous playback default" grep -q "continuousPlayback:true" "$APP_PATH/rozza2.html"
check "transport-only interruption suspend command" grep -q "CMD SUSPEND reason=" "$APP_PATH/rozza2.html"
check "native interruption suspend/resume bridge" grep -q "suspendForInterruption" "$APP_PATH/rozza2.html"
check "automatic player self-heal wired" grep -q "automatic-start-self-heal" "$APP_PATH/rozza2.html"
check "player rebuild log line present" grep -q "REBUILD PLAYER id=" "$APP_PATH/rozza2.html"
check_absent "manual second-Play fallback removed" "Tap Play once to start this YouTube session." "$APP_PATH/rozza2.html"
# `strings | grep -q` is unsafe under pipefail: grep -q exits as soon as it
# finds a match, which can SIGPIPE `strings` mid-write ("failed to flush
# output") and abort the whole script even though the match was found.
# Capture to a file once so grep's exit status is the only one that matters.
#
# Only genuine runtime string literals long enough (>~15 bytes) to survive
# Swift's small-string optimization are checked against the compiled binary.
# Still dropped, same reasons as previous rounds: "networkProxy"/
# "remote-native-"/"playbackIntent" (short-literal SSO risk),
# "hardUserPauseActive"/"ROZZA.RemoteCommand"/"skipForwardCommand"/
# "activateForNativePlaybackIfNeeded"/"beginReceivingRemoteControlEvents"
# (Swift/SDK identifiers, never string literals), "Metadata is transport
# observation only" (a // comment, stripped by the compiler entirely), and
# the two negative checks for Swift call-site syntax that was never
# compiled as contiguous string data in the first place. All of this is
# already covered reliably by qa-source.py's source-level greps.
#
# The main-player intent log line was also dropped from here: since the
# per-call-site print() was consolidated into registerExplicitPlaybackIntent(),
# the only distinguishing literal left at the main-player call site is
# "main-player-" (12 bytes) — short-literal SSO risk like the others above.
# Covered by qa-source.py instead.
strings "$APP_PATH/ROZZA" > "$WORK_DIR/rozza-binary-strings.txt" || true
check "compiled binary contains background-capture log line" grep -q "Background capture wantsPlayback=" "$WORK_DIR/rozza-binary-strings.txt"
check "compiled binary contains native pause-fence reason string" grep -q "native-human-pause-fence" "$WORK_DIR/rozza-binary-strings.txt"
check "compiled binary contains genuine-interruption log line" grep -q "Genuine interruption began" "$WORK_DIR/rozza-binary-strings.txt"
check_absent "compiled binary does not ignore every YouTube interruption" "Ignored AVAudioSession interruption for WebKit-owned YouTube" "$WORK_DIR/rozza-binary-strings.txt"

ditto "$APP_PATH" "$WORK_DIR/Payload/ROZZA.app"
ditto -c -k --sequesterRsrc --keepParent "$WORK_DIR/Payload" "$OUTPUT_IPA"

test -s "$OUTPUT_IPA"
echo "Unsigned IPA created at: $OUTPUT_IPA"
