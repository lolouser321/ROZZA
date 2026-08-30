import 'dart:async';

import 'package:rozza/src/domain/playback_state.dart';
import 'package:rozza/src/domain/track.dart';
import 'package:rozza/src/playback/playback_bridge.dart';

class FakePlaybackBridge implements PlaybackBridge {
  final controller = StreamController<Map<Object?, Object?>>.broadcast();
  final calls = <String>[];

  @override
  Stream<Map<Object?, Object?>> get events => controller.stream;

  @override
  Future<RozzaPlaybackState?> getPlaybackState(
    List<Track> fallbackQueue,
  ) async => null;
  @override
  Future<void> loadTrack(Track track, {required bool autoplay}) async =>
      calls.add('loadTrack:${track.id}:$autoplay');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inMilliseconds}');
  @override
  Future<void> setQueue(List<Track> tracks, {required int startIndex}) async =>
      calls.add('setQueue:${tracks.length}:$startIndex');
}
