import '../domain/playback_state.dart';
import '../domain/track.dart';

abstract interface class PlaybackBridge {
  Stream<Map<Object?, Object?>> get events;

  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> loadTrack(Track track, {required bool autoplay});
  Future<void> setQueue(List<Track> tracks, {required int startIndex});
  Future<RozzaPlaybackState?> getPlaybackState(List<Track> fallbackQueue);
}
