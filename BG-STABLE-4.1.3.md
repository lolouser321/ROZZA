# ROZZA 4.1.3 — BG STABLE · Build 29

This release fixes the Build 28 regression where Home/Lock background recovery
could be killed by the native Smart Pause guard before the main-frame intent
mirror reached Swift.

## Playback contract
1. Explicit user/app intent is sent directly from the main ROZZA page through
   the `playbackIntent` WKScriptMessage handler.
2. Iframe `playing`/`pause` messages are transport observations only.
3. A human/system Pause creates a hard pause fence.
4. Automatic background recovery can never clear a hard pause.
5. During Home/Lock, a playing transport observation is accepted unless a hard
   pause fence is active; it no longer depends on a potentially stale native
   `youtubeWantsPlayback` mirror.
6. `backgroundPrepare()` returns the authoritative JS `YT.wantPlay`; Swift
   promotes that value only when the background transition generation is still
   current and no hard user pause is active.

This keeps all three invariants together:
- Home/Lock playback may recover automatically when the user wanted playback.
- Human Pause always wins and remains paused.
- Automatic Next preserves play intent without requiring another tap.
