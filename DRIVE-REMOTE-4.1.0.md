# ROZZA 4.1.0 — DRIVE REMOTE · Build 26

## Remote-control repair

Build 26 replaces direct one-off `evaluateJavaScript("Coordinator.next/prev")` calls with one acknowledged native-to-JavaScript transport bridge.

- `MPRemoteCommandCenter` is the single system command owner in the iOS shell.
- Vehicle/Lock Screen Previous always changes to the previous queue item; the in-app Previous button keeps the normal restart-current-track behavior after 3 seconds.
- Web `navigator.mediaSession` handlers are disabled in the native shell to avoid duplicate handling.
- Play, Pause, Stop, Toggle, Next, Previous, Seek, Like and Dislike use `ROZZANativeControls.remote(...)`.
- Each native command gets a nonce. If WebKit delays an acknowledgement, native can retry the same nonce without executing Next/Previous twice.
- A short `UIBackgroundTask` gives commands received from a vehicle/Lock Screen a bounded execution window.
- Remote Play/Next/Previous/Dislike received while backgrounded re-arm/pulse the existing background bridge for the newly selected YouTube track.

## Now Playing improvements

Native now-playing metadata now publishes:

- title
- artist
- duration
- elapsed time
- playback rate
- queue index
- queue count
- remote artwork
- stale-artwork cleanup when the track changes
- full Now Playing clear when the queue/current track is cleared

## Added UI

- Drive Mode launcher on Home
- large Previous / Play-Pause / Next buttons
- Like, Radio and Queue shortcuts
- Coming Up preview
- Continuous Play setting
- Vehicle Control diagnostics snapshot in Settings

## Regression boundaries

The background-only bridge file and `ROZZAAudioSession.swift` are unchanged from Build 25. Build 26 changes the command handoff around them rather than rewriting the established background media bridge.
