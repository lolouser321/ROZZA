# QA — ROZZA 4.1.0 DRIVE REMOTE · Build 26

## Automated/static coverage

- main inline JavaScript parses
- both bundled bridge scripts parse
- all root Swift files parse
- source QA script passes
- build shell scripts parse
- no duplicate HTML IDs
- Drive Mode DOM anchors exist
- Continuous Play default/UI exists
- native remote dispatcher exists
- Next / Previous native handlers exist
- queue index/count metadata exists
- artwork publishing path exists
- browser/native MediaSession ownership is separated
- remote command nonce deduplication exercised in runtime test
- vehicle Previous tested to change tracks even when current playback is >3 seconds
- vehicle diagnostics state exercised in runtime test
- stale Now Playing / artwork cleanup has source/build guards
- Drive Mode runtime rendering exercised at iPhone widths
- Continuous Play on/off runtime behavior exercised

## Physical-device checks still required

1. Start a song, press steering-wheel / head-unit Next once: exactly one next track starts.
2. Press Previous: the previous-track action reaches ROZZA and playback resumes.
3. Lock iPhone and repeat Next / Previous from the vehicle.
4. Play/Pause from vehicle and Control Center.
5. Let a track end naturally: next track starts when Continuous Play is enabled.
6. Check artwork/title/artist and queue position on the system/vehicle Now Playing surface where supported.
7. Receive/end a phone call or Siri interruption and confirm playback intent is respected.
8. Run a 20–30 minute drive/background session for lifecycle/network soak testing.

Real vehicle hardware, Bluetooth firmware, CarPlay behavior, and iOS/WebKit background scheduling cannot be fully emulated by the Linux source-QA environment.
