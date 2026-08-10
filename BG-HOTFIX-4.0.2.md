# ROZZA 4.0.2 — Background State Handoff Hotfix (Build 22)

## Root cause found from the user-installed 4.0.1 / Build 21 IPA

The IPA contained the correct background bridge, `UIBackgroundModes=audio`, and the bounded native resume-kick code. The bug was the foreground -> native state handoff:

- `DJPlaybackController.willResignActive` decided whether to schedule automatic resume using `isYouTubePlaying`.
- The legacy foreground iframe messenger had correctly been disabled.
- The replacement background bridge is intentionally inert in foreground.
- Therefore `isYouTubePlaying` could remain false while YouTube was audibly playing.
- `postNowPlayingToNative()` did report `isPlaying`, but native `updateNowPlaying(info:)` only used it for Lock Screen metadata and did not update the controller playback flag.
- Result: Home/lock captured `resume=false`, so the bounded auto-resume sequence often never ran. Manual Control Center Play worked because it called the explicit Play path directly.

## Fix

1. `rozza2.html` now sends `source` and authoritative `wantsPlayback` with every now-playing update.
2. `DJPlaybackController.updateNowPlaying(info:)` mirrors YouTube foreground `isPlaying` and Play/Pause intent into native state.
3. Home/lock capture uses `youtubeWantsPlayback || isYouTubePlaying`, so a lifecycle pause cannot erase the user's Play intent before resume scheduling.
4. Background `BackgroundIntent` events also update the native intent mirror.
5. Lock Screen explicit Play/Pause commands update native intent immediately.

The background bridge itself was not changed.
