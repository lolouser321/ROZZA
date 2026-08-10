# ROZZA 4.1.2 — HD SMART PAUSE · Build 28

ROZZA is an iOS-first music experience built around a persistent native `WKWebView`, native audio/session integration, queue intelligence, discovery, Flow, Radio, Event Mode, and system media controls.

## Build the iOS app

Use the **root project only**:

```bash
brew install xcodegen
chmod +x Scripts/build-unsigned-ipa.sh
./Scripts/build-unsigned-ipa.sh
```

Output:

```text
build/ROZZA-Unsigned.ipa
```

The build script runs `Scripts/qa-source.py` and resource checks before invoking Xcode, then validates that the resulting `.app` contains the expected Build 28 HTML, background bridge, network bridge, persistent-player markers, and native remote-command code.

## Build 28 highlights

- Native vehicle / Bluetooth / AirPods / Lock Screen transport path for Play, Pause, Next, Previous, Stop and seek
- Acknowledged, idempotent remote commands so a retry cannot double-skip
- Short background execution window for remote commands received while the app is inactive
- Background resume pulse after a remote Next / Previous / Play action
- One native system-command owner on iPhone; Web MediaSession is browser-only
- Now Playing artwork, queue index and queue count, with stale metadata cleanup
- Drive Mode with large transport controls and a Coming Up view
- Vehicle diagnostics snapshot for fast troubleshooting
- Continuous Play setting for automatic next-track playback
- Persistent YouTube iframe switching (`loadVideoById`) from Build 25
- Native `URLSession` metadata/search fallback from Build 24

## Canonical source

- `rozza2.html`
- `Sources/`
- `Resources/`
- `project.yml`
- `Scripts/build-unsigned-ipa.sh`

The obsolete duplicate `ios/` project was removed in Build 28 to prevent stale/incorrect builds.

See `ROZZA-IOS-START-HERE.md` and `QA-4.1.2-DRIVE.md`.
