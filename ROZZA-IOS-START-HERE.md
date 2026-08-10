# ROZZA iOS — START HERE

**Canonical iOS project: repository root.**

Do not build an `ios/` subfolder. ROZZA 4.1.0 Build 26 intentionally removed the old duplicate iOS project so there is only one playback stack and one source of truth.

## Build on macOS

```bash
brew install xcodegen
chmod +x Scripts/build-unsigned-ipa.sh
./Scripts/build-unsigned-ipa.sh
```

The script performs source QA first, generates the root Xcode project, builds the Release iPhone app, validates the packaged HTML/background bridge/native remote-control markers, and writes:

```text
build/ROZZA-Unsigned.ipa
```

## Active playback files

- `rozza2.html` — UI, queue, YouTube player, autoplay, Flow/Brain/Event/Drive features
- `Sources/Playback/DJPlaybackController.swift` — native audio lifecycle, Lock Screen / vehicle / Bluetooth remote commands, Now Playing metadata
- `Sources/Web/ROZZAWebAppView.swift` — persistent WKWebView + native network bridge
- `Resources/yt_background_bridge.js` — background-only iframe media bridge
- `Resources/ROZZA.entitlements` and `Resources/Info.plist` — iOS capabilities/configuration

## Important

The root `Scripts/build-unsigned-ipa.sh` is the supported build route. Physical-iPhone testing is still required for Home/Lock, Bluetooth head units, steering-wheel controls, interruptions, and long background sessions because those lifecycle paths cannot be fully validated by static source tests.
