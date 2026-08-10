# ROZZA 3.1 — CORE ELITE (Build 14)

This release starts implementing the Master Product Roadmap without destabilizing the working YouTube playback architecture.

## Added
- ROZZA Flow foundation with Energy / Discovery / Era / Language controls
- Flow session generation and Smart Queue refill
- Liked Songs / favorites
- Real recently-played history
- Continue Listening with remembered playback position
- Crash/relaunch session continuity
- Playback Watchdog for bounded foreground stall recovery
- Network offline banner and safe reconnect
- Search generation guard so stale searches cannot overwrite newer results
- Performance throttling for visual loops when the app is hidden
- Copy Playback Diagnostics action
- Home discovery sections and Flow entry point
- Library Liked Songs + Recently Played sections

## Protected
- Existing YouTube foreground state machine
- Background bridge and native Home/lock recovery
- AVAudioSession behavior
- Persistent WKWebView
- Native Lock Screen / Control Center bridge

## Physical iPhone tests required
1. YouTube foreground 5+ minutes
2. Home / lock background playback
3. Intentional Pause stays paused
4. Search suggestion one-tap autoplay
5. Relaunch -> Continue Listening -> Resume position
6. Flow starts and Smart Queue adds tracks
7. Wi-Fi off/on while queue remains intact
