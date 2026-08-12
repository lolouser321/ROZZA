# ROZZA 4.2.0 — CORE STABLE · Build 30 QA

## Diagnostic root cause from Build 29
The reported state had a valid queue/current track but no active engine:
- playback.source = none
- playback.status = idle
- YT.mounted = false
- YT.videoId = null
- YT.wantPlay = false

That meant the UI restored the current song but the YouTube engine did not. Background and remote commands therefore had no live player to control.

## Build 30 corrections
- Restore/mount the current engine shortly after boot.
- Auto-resume only when the saved session was genuinely playing.
- Persist explicit human Pause immediately, preventing unwanted relaunch autoplay.
- Remote Play rebuilds a missing/mismatched YouTube engine automatically.
- One explicit intent authority: playbackIntent + native remote commands.
- Now Playing metadata is transport-only and cannot change user intent.
- Iframe background observations are transport-only and cannot change user intent.
- Track-start and watchdog recovery use YT.resume(), not repeated explicit YT.play().
- Previous no longer sends a redundant second Play after switching tracks.
- Native remote targets are cleared before registration; legacy PlaybackManager no longer registers competing handlers.
- Added accessory skip-forward/backward commands.
- Reduced YouTube polling/visualizer/native position-update overhead.
- Watchdog can rebuild a vanished YouTube engine while intended playback is active.

## Static verification
- Source QA PASS: 182 IDs, zero duplicates.
- Main JavaScript syntax PASS.
- Background bridge JavaScript syntax PASS.
- Legacy messenger JavaScript syntax PASS.
- Every root Swift file parses PASS.
- Build/resource shell scripts syntax PASS.
- Single-intent-authority assertions PASS.
- Canonical @main remains DJPlaybackController + persistent ROZZAWebAppView.
- Legacy PlaybackManager remote registration disabled.

## Physical device validation
The final four hardware tests must be done on an iPhone because Linux cannot reproduce iOS WebKit/AVAudioSession suspension timing or real Bluetooth/vehicle events:
1. Start a song, press Home: continues automatically.
2. Lock screen: continues automatically.
3. Pause from Control Center/AirPods/car: remains paused.
4. Next/Previous from AirPods/car: changes one track exactly once and starts it automatically.
