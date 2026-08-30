import 'package:flutter/foundation.dart';

import 'track.dart';

enum PlaybackStatus { idle, loading, playing, paused, interrupted, error }

@immutable
class RozzaPlaybackState {
  const RozzaPlaybackState({
    required this.status,
    required this.queue,
    required this.queueIndex,
    required this.position,
    required this.humanPauseActive,
    this.error,
  });

  factory RozzaPlaybackState.seed(List<Track> tracks) => RozzaPlaybackState(
    status: PlaybackStatus.paused,
    queue: List.unmodifiable(tracks),
    queueIndex: tracks.isEmpty ? -1 : 0,
    position: const Duration(seconds: 73),
    humanPauseActive: true,
  );

  final PlaybackStatus status;
  final List<Track> queue;
  final int queueIndex;
  final Duration position;
  final bool humanPauseActive;
  final String? error;

  Track? get currentTrack =>
      queueIndex >= 0 && queueIndex < queue.length ? queue[queueIndex] : null;
  bool get isPlaying =>
      status == PlaybackStatus.playing || status == PlaybackStatus.loading;

  RozzaPlaybackState copyWith({
    PlaybackStatus? status,
    List<Track>? queue,
    int? queueIndex,
    Duration? position,
    bool? humanPauseActive,
    String? error,
  }) => RozzaPlaybackState(
    status: status ?? this.status,
    queue: queue ?? this.queue,
    queueIndex: queueIndex ?? this.queueIndex,
    position: position ?? this.position,
    humanPauseActive: humanPauseActive ?? this.humanPauseActive,
    error: error,
  );

  factory RozzaPlaybackState.fromMap(
    Map<Object?, Object?> map, {
    required List<Track> fallbackQueue,
  }) {
    final rawQueue = map['queue'];
    final queue = rawQueue is List
        ? rawQueue
              .whereType<Map>()
              .map((item) => Track.fromMap(item.cast<Object?, Object?>()))
              .toList(growable: false)
        : fallbackQueue;
    final statusName = map['status'] as String? ?? 'paused';
    return RozzaPlaybackState(
      status: PlaybackStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => PlaybackStatus.paused,
      ),
      queue: List.unmodifiable(queue),
      queueIndex:
          (map['queueIndex'] as num?)?.toInt() ?? (queue.isEmpty ? -1 : 0),
      position: Duration(
        milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0,
      ),
      humanPauseActive: map['humanPauseActive'] as bool? ?? true,
      error: map['error'] as String?,
    );
  }
}
