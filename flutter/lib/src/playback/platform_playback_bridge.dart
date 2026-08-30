import 'package:flutter/services.dart';

import '../domain/playback_state.dart';
import '../domain/track.dart';
import 'playback_bridge.dart';

class PlatformPlaybackBridge implements PlaybackBridge {
  static const _commands = MethodChannel('com.rozza.playback/commands');
  static const _events = EventChannel('com.rozza.playback/events');

  @override
  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => (event as Map).cast<Object?, Object?>());

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> next() => _invoke('next');

  @override
  Future<void> previous() => _invoke('previous');

  @override
  Future<void> seek(Duration position) =>
      _invoke('seek', {'positionMs': position.inMilliseconds});

  @override
  Future<void> loadTrack(Track track, {required bool autoplay}) =>
      _invoke('loadTrack', {'track': track.toMap(), 'autoplay': autoplay});

  @override
  Future<void> setQueue(List<Track> tracks, {required int startIndex}) =>
      _invoke('setQueue', {
        'tracks': tracks.map((track) => track.toMap()).toList(growable: false),
        'startIndex': startIndex,
      });

  @override
  Future<RozzaPlaybackState?> getPlaybackState(
    List<Track> fallbackQueue,
  ) async {
    try {
      final raw = await _commands.invokeMapMethod<Object?, Object?>(
        'getPlaybackState',
      );
      return raw == null
          ? null
          : RozzaPlaybackState.fromMap(raw, fallbackQueue: fallbackQueue);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _commands.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Android's media-service implementation lands in migration phase 5.
    }
  }
}
