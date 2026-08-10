# ROZZA 4.1.2 — HD SMART PAUSE · Build 28

- Now Playing artwork prefers max-resolution YouTube art, validates actual pixel size, and falls back through SD/HQ/original instead of stretching a small search thumbnail.
- Native Lock Screen artwork receives the same candidate chain and rejects undersized images.
- Human/system Pause is now a hard playback-intent fence. It cancels pending Home/lock recovery generations and interruption resume.
- Automatic background bridge Playing/Pulse events can report transport state but can no longer create PLAY intent.
- Background recovery uses YT.resume(), which preserves existing intent instead of setting it.
- Car/AirPods/Control Center toggle commands resolve against explicit intent rather than stale YouTube playerState.
- A short bounded pause fence catches delayed lifecycle recovery callbacks after a human Pause, and aborts immediately if the user presses Play again.
