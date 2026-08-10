# ROZZA 4.1.2 — HD SMART PAUSE · Build 28 QA

## Fixed
- Now Playing artwork now prefers max-resolution YouTube artwork, then SD, provider artwork, HQ, and finally the ROZZA fallback.
- Tiny successful YouTube placeholder images are rejected instead of stretched.
- Lock Screen / Control Center artwork uses the same high-resolution fallback chain.
- System/user Pause is a hard intent fence.
- Human Pause cancels pending background transition recovery generations and interruption resume.
- Automatic BackgroundVideoPlaying / BackgroundPulse observations cannot create PLAY intent.
- Automatic lifecycle recovery uses `YT.resume()` and preserves the existing intent instead of setting it.
- Car/AirPods/Control Center toggle resolves from explicit playback intent instead of stale YouTube player state.
- A bounded human-pause fence catches delayed recovery callbacks, but stops immediately if Play is pressed again.

## Verification performed
- Main inline JavaScript: syntax PASS
- Background bridge JavaScript: syntax PASS
- Legacy messenger JavaScript: syntax PASS
- Root Swift files: parse PASS
- Source QA: PASS, 182 IDs, 0 duplicates
- Runtime: explicit Play -> system Pause -> automatic resume attempt remains blocked: PASS
- Runtime: backgroundResumeIfWanted after explicit Pause returns requested=false: PASS
- Runtime: system Toggle from PLAY -> PAUSE, then Toggle -> PLAY: PASS
- Runtime: artwork candidate order starts with maxresdefault.jpg: PASS
- Browser runtime page errors in tested paths: 0
- Build script / resource script shell syntax: PASS

## Physical-device checks still required
Real iOS Home/Lock timing, Bluetooth/AirPods/car hardware, and YouTube/WebKit background lifecycle must still be validated on an actual iPhone.
