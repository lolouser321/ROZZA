# ROZZA Flutter

This is the side-by-side product UI migration. It does not replace or delete the current Swift/WKWebView app.

## Current Phase 1 scope

- Premium dark ROZZA design system
- Responsive, RTL-capable app shell
- Home, Search, Library, Now Playing, Queue, and persistent mini-player
- Lazy lists, bounded network-image decoding, cache-backed artwork, Hero artwork transition, haptics, bottom sheet queue
- Event-driven Flutter playback model
- iOS MethodChannel/EventChannel transport contract
- Swift-owned AVAudioSession, AVPlayer, MPNowPlayingInfoCenter, and MPRemoteCommandCenter scaffold

The demo catalog intentionally has no direct audio URLs. Flutter does not claim to make embedded YouTube background audio native. A licensed/direct/local source can later be assigned an `audioUrl` and handled by the Swift AVPlayer service.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
flutter test --update-goldens test/widget_test.dart
```

See [docs/architecture.md](docs/architecture.md) for the channel contract and [docs/migration-plan.md](docs/migration-plan.md) for phased rollout and performance gates.
