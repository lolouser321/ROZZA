# Flutter/native playback architecture

Flutter owns product presentation and user interaction. Swift owns Apple playback and system integration. Playback state is emitted; the UI does not poll.

```text
Flutter UI
  -> PlaybackController (Dart projection of native state)
  -> MethodChannel com.rozza.playback/commands
  -> PlaybackChannelPlugin.swift
  -> NativePlaybackController.swift
  -> AVPlayer / AVAudioSession / MPNowPlayingInfoCenter

MPRemoteCommandCenter / AirPods / vehicle / Siri media command
  -> NativePlaybackController.swift
  -> EventChannel com.rozza.playback/events
  -> PlaybackController
  -> selective Flutter repaint
```

## Commands

- `play()`
- `pause()`
- `next()`
- `previous()`
- `seek(positionMs)`
- `loadTrack(track, autoplay)`
- `setQueue(tracks, startIndex)`
- `getPlaybackState()`

## Events

- `playbackStateChanged`
- `currentTrackChanged`
- `queueChanged`
- `interruptionChanged` (reserved for the interruption observer phase)
- `remoteCommandReceived`
- `error`

Every event contains a `state` snapshot. Remote-command events additionally contain source channel, command ID, before/after queue indexes, acceptance, and rejection reason.

`NativePlaybackController` is the future authoritative playback state machine on iOS. Flutter makes requests and reflects events. It does not register `MPRemoteCommandCenter`, infer play state from animations, or auto-resume from lifecycle callbacks.

The current WKWebView app remains separate during migration. Its working YouTube background bridge is not copied into this native service and is not represented as an AVPlayer capability.
