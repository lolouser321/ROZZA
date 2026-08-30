# ROZZA migration plan

## Phase 1 — product shell (implemented here)

Ship the Flutter design system, navigation, Home, Search, Library, Now Playing, Queue, mini-player, RTL layout, cached artwork, haptics, and visual regressions against mock/current ROZZA data. Keep the current app untouched and releasable.

Exit gates: clean analyzer, widget/state tests, phone captures reviewed, profile-mode startup/frame baseline recorded on target iPhone hardware.

## Phase 2 — data and product logic

Move the existing search, queue persistence, library, recommendations, Flow, Radio, playlists, AI, and Event Mode behind typed repositories. Preserve backend contracts first; port algorithms only when tests capture their current behavior. Add request coalescing, cache policy, cancellation, and search-latency traces.

Exit gates: parity fixtures for queue/search/recommendations, no duplicate network calls, offline/error/loading states, p95 search target agreed from device baseline.

## Phase 3 — native playback contract

Connect the Dart `PlaybackController` to `PlaybackChannelPlugin.swift` and the Swift `NativePlaybackController`. Add licensed/direct/local providers to AVPlayer. Complete interruption/route observers and emit all reserved events. Flutter remains a projection of native state.

Exit gates: one state machine; method/event contract tests; track-switch latency trace; real-device Play/Pause/Next/Previous matrix across Lock Screen, Control Center, AirPods, car, and Siri.

## Phase 4 — iOS media service ownership

Move all supported iOS background playback, MPNowPlayingInfoCenter, MPRemoteCommandCenter, interruptions, route changes, and recovery behind the Swift service. Retire the current WebView UI screen-by-screen only after parity. Do not describe embedded YouTube as native AVPlayer playback.

Exit gates: 30-minute background soak, interruption recovery tests, zero restart after human Pause, memory/CPU/frame/startup baselines within agreed budgets.

## Phase 5 — Android service

Implement the same contract with Media3/MediaSessionService, audio focus, Bluetooth/car controls, notification controls, and foreground-service policy. Keep the Dart UI and domain projection unchanged.

Exit gates: the shared contract suite passes on both platforms; Android Auto is a later product decision, not implied by the base service.

## Performance capture

Use `flutter run --profile` and DevTools on representative low/high devices. Record cold/warm first frame, frame build/raster percentiles, jank count, memory after 15/30 minutes, idle/playing CPU, p50/p95 search latency, and tap-to-audible track-switch latency. Store signed-off measurements per build; widget-test wall time is not a device-performance measurement.
