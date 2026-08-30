import 'package:flutter/foundation.dart';

@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.duration,
    this.audioUrl,
    this.accent = 0xFFFF3D79,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final Duration duration;
  final String? audioUrl;
  final int accent;

  factory Track.fromMap(Map<Object?, Object?> map) => Track(
    id: map['id'] as String? ?? '',
    title: map['title'] as String? ?? 'Untitled',
    artist: map['artist'] as String? ?? 'ROZZA',
    album: map['album'] as String? ?? '',
    artworkUrl: map['artworkUrl'] as String? ?? '',
    duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
    audioUrl: map['audioUrl'] as String?,
    accent: (map['accent'] as num?)?.toInt() ?? 0xFFFF3D79,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'artworkUrl': artworkUrl,
    'durationMs': duration.inMilliseconds,
    'audioUrl': audioUrl,
    'accent': accent,
  };
}
