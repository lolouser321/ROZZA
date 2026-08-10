# ROZZA 4.0.1 GOLD — Build 21

This is the QA-hardened build to test on the physical iPhone instead of Build 20.

## Final non-device QA completed
- 165 HTML IDs, 0 duplicates
- main inline JavaScript syntax: PASS
- yt_background_bridge.js syntax: PASS
- yt_video_play_messenger.js syntax: PASS
- all 28 root Swift source files parse: PASS
- shell build/verify scripts parse: PASS
- Info.plist / entitlements parse: PASS
- AppIcon: 1024x1024 RGB/opaque
- required launch assets present
- no horizontal overflow at 320 / 390 / 430 px widths
- representative real-button click-through: PASS, no page errors
- Search + suggestion autoplay state path: PASS under deterministic provider mock
- Favorites + listening history: PASS
- Flow + Smart Queue: PASS
- Radio state behavior: PASS
- Queue Doctor: PASS (72 -> 100 fixture)
- Saved Sets: PASS
- Sleep Timer: PASS
- Event build + Entrance + guest request + Guest Lock: PASS
- Taste DNA + Passport + achievements render: PASS
- Private Session blocks Brain learning: PASS
- natural-language command path: PASS
- Now Playing / Queue / Event sheets: PASS

## Bugs found and fixed during this audit
1. Flow could remain falsely LIVE after search failure -> fixed.
2. Radio could remain falsely LIVE when zero related tracks were added -> fixed.
3. Event emergency backup duplicated a track already in the event queue -> fixed.
4. Expired Sleep Timer state could remain stale in localStorage -> fixed.
5. Native DJ test launcher could overlay the Release app -> now DEBUG-only.
6. Several important iPhone touch targets were too small -> enlarged.
7. XcodeGen test-source path casing corrected to `tests`.
8. Build now runs `Scripts/qa-source.py` before Xcode compilation.

## Playback protection
The files below are byte-identical to Build 20 and were deliberately not modified during GOLD QA:
- Resources/yt_background_bridge.js
- Sources/Playback/DJPlaybackController.swift
- Sources/Web/ROZZAWebAppView.swift
- Sources/Playback/ROZZAAudioSession.swift
- Sources/Web/YouTubeMessengerBridge.swift

## Still must be verified on the physical iPhone
These depend on real iOS/WebKit/hardware and cannot be proven by browser/static QA:
- YouTube automatic continuation after Home / screen lock
- Lock Screen / Control Center commands
- Bluetooth / AirPods route changes
- real YouTube audible autoplay from a suggestion tap
- long-session memory / battery / thermal behavior

## Build
Run from this folder on the Mac:

```bash
chmod +x Scripts/build-unsigned-ipa.sh
./Scripts/build-unsigned-ipa.sh
```

Expected output:
`build/ROZZA-Unsigned.ipa`
