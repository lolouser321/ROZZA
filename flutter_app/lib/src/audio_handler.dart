import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'track.dart';

class RozzaAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  RozzaAudioHandler() {
    _listenToPlayer();
    unawaited(_configureSession());
  }

  final AudioPlayer _player = AudioPlayer();

  Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  void _listenToPlayer() {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );
    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
      }
    });
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null && item.duration != duration) {
        final updated = item.copyWith(duration: duration);
        mediaItem.add(updated);
        final items = [...queue.value];
        final index = _player.currentIndex;
        if (index != null && index < items.length) {
          items[index] = updated;
          queue.add(items);
        }
      }
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  Future<void> loadAndPlay(List<Track> tracks, int index) async {
    final playable = tracks
        .where((track) => track.isBackgroundPlayable)
        .toList();
    if (playable.isEmpty) return;
    final selected = tracks[index];
    final initialIndex = playable.indexWhere(
      (track) => track.id == selected.id,
    );
    if (initialIndex < 0) return;

    final items = playable.map(_toMediaItem).toList(growable: false);
    queue.add(items);
    mediaItem.add(items[initialIndex]);
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: items
            .map(
              (item) => AudioSource.uri(
                Uri.parse(item.extras!['url'] as String),
                tag: item,
              ),
            )
            .toList(growable: false),
      ),
      initialIndex: initialIndex,
    );
    await play();
  }

  MediaItem _toMediaItem(Track track) {
    final source = track.backgroundSource!;
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      artUri: Uri.tryParse(track.artworkUrl ?? ''),
      duration: track.duration == null
          ? null
          : Duration(milliseconds: (track.duration! * 1000).round()),
      extras: {'url': source.url, 'provider': source.provider},
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
