# ROZZA 1.9 (Build 10) — Background YouTube Test

This branch keeps the ROZZA 1.8/9 foreground YouTube state machine intact and adds a separate, gated background-only bridge.

## What changed

- Added `Resources/yt_background_bridge.js`.
- The legacy `yt_video_play_messenger.js` remains disabled in the active foreground path.
- The new bridge is injected into YouTube frames at document start but is inert until iOS sends `willResignActive` / background lifecycle events.
- On background preparation it conditionally preserves visible-state behavior for the YouTube frame and performs limited recovery of a lifecycle-induced `<video>` pause.
- No 100 ms polling loop is used.
- Foreground return disables the background bridge and hands control back to the existing ROZZA YT state machine.
- Intentional user Pause sets `shouldPlay=false`, so the bridge must not restart it.
- Version bumped to 1.9 / build 10.

## Physical iPhone test order

1. Confirm a YouTube track still plays normally for 2–3 minutes with ROZZA open.
2. Press Home and leave it for at least 60 seconds.
3. Reopen ROZZA and confirm the same track/state is intact.
4. Repeat using the side button to lock the phone.
5. While playing, intentionally Pause, then Home/lock; it must remain paused.
6. Test a phone/Siri/audio interruption and confirm the bridge does not fight the interruption.

If background audio still stops, capture Xcode logs containing `BackgroundBridge...` plus `window.ROZZADebug.getState()` after reopening ROZZA.
