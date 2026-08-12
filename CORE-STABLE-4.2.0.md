# ROZZA 4.2.0 — CORE STABLE · Build 30

Stability release focused on one playback engine and one explicit intent authority.

- Restores/mounts the current playback engine automatically after launch.
- Auto-resumes only when the saved session was actually playing.
- Human Pause is persisted immediately and remains authoritative.
- Now Playing metadata and iframe observations can no longer mutate user intent.
- Remote Play rebuilds an unmounted YouTube player automatically.
- Car/AirPods common remote targets are owned by DJPlaybackController only.
- Added skip-forward/backward accessory commands.
- Automatic track-start/watchdog recovery uses intent-preserving resume, not explicit Play.
- Reduced visualizer and native metadata update overhead.
- Existing HD artwork, Smart Pause, background bridge, persistent YouTube iframe, Smart Queue and Continuous Play remain.
