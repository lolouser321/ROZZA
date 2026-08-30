import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/playback_state.dart';
import '../domain/track.dart';
import 'playback_bridge.dart';

class PlaybackController extends ChangeNotifier {
  PlaybackController({required this.bridge, required List<Track> initialQueue})
    : _state = RozzaPlaybackState.seed(initialQueue);

  final PlaybackBridge bridge;
  RozzaPlaybackState _state;
  StreamSubscription<Map<Object?, Object?>>? _subscription;

  RozzaPlaybackState get state => _state;

  Future<void> initialize() async {
    await bridge.setQueue(_state.queue, startIndex: _state.queueIndex);
    final nativeState = await bridge.getPlaybackState(_state.queue);
    if (nativeState != null && nativeState.queue.isNotEmpty) {
      _state = nativeState;
    }
    _subscription = bridge.events.listen(_onNativeEvent, onError: (_) {});
  }

  Future<void> toggle() => _state.isPlaying ? pause() : play();

  Future<void> play() async {
    _apply(
      _state.copyWith(status: PlaybackStatus.playing, humanPauseActive: false),
    );
    await bridge.play();
  }

  Future<void> pause() async {
    _apply(
      _state.copyWith(status: PlaybackStatus.paused, humanPauseActive: true),
    );
    await bridge.pause();
  }

  Future<void> next() async {
    if (_state.queue.isEmpty) return;
    final nextIndex = (_state.queueIndex + 1)
        .clamp(0, _state.queue.length - 1)
        .toInt();
    _apply(
      _state.copyWith(
        queueIndex: nextIndex,
        position: Duration.zero,
        status: PlaybackStatus.playing,
        humanPauseActive: false,
      ),
    );
    await bridge.next();
  }

  Future<void> previous() async {
    if (_state.queue.isEmpty) return;
    final previousIndex = (_state.queueIndex - 1)
        .clamp(0, _state.queue.length - 1)
        .toInt();
    _apply(
      _state.copyWith(
        queueIndex: previousIndex,
        position: Duration.zero,
        status: PlaybackStatus.playing,
        humanPauseActive: false,
      ),
    );
    await bridge.previous();
  }

  Future<void> seek(Duration position) async {
    _apply(_state.copyWith(position: position));
    await bridge.seek(position);
  }

  Future<void> playTrack(Track track) async {
    final index = _state.queue.indexWhere((item) => item.id == track.id);
    _apply(
      _state.copyWith(
        queueIndex: index >= 0 ? index : _state.queueIndex,
        position: Duration.zero,
        status: PlaybackStatus.playing,
        humanPauseActive: false,
      ),
    );
    await bridge.loadTrack(track, autoplay: true);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final queue = List<Track>.of(_state.queue);
    final currentID = _state.currentTrack?.id;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    final currentIndex = currentID == null
        ? -1
        : queue.indexWhere((track) => track.id == currentID);
    _apply(
      _state.copyWith(
        queue: List.unmodifiable(queue),
        queueIndex: currentIndex,
      ),
    );
    await bridge.setQueue(queue, startIndex: currentIndex);
  }

  void _onNativeEvent(Map<Object?, Object?> event) {
    final payload = event['state'];
    if (payload is Map) {
      _apply(
        RozzaPlaybackState.fromMap(
          payload.cast<Object?, Object?>(),
          fallbackQueue: _state.queue,
        ),
      );
    }
  }

  void _apply(RozzaPlaybackState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
