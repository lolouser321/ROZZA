import 'package:flutter_test/flutter_test.dart';
import 'package:rozza_flutter/src/track.dart';

void main() {
  test('accepts only HTTPS background-capable sources', () {
    final track = Track.fromJson({
      'id': 'one',
      'title': 'Song',
      'artist': 'Artist',
      'sources': [
        {
          'provider': 'youtube',
          'providerID': 'video',
          'canPlayInBackground': false,
        },
        {
          'provider': 'licensed',
          'providerID': 'audio',
          'url': 'https://cdn.example.com/song.mp3',
          'canPlayInBackground': true,
        },
      ],
    });
    expect(track.isBackgroundPlayable, isTrue);
    expect(track.backgroundSource?.providerId, 'audio');
  });

  test('never marks YouTube metadata as background playable', () {
    final track = Track.fromJson({
      'id': 'two',
      'title': 'Video',
      'artist': 'Artist',
      'sources': [
        {
          'provider': 'youtube',
          'providerID': 'video',
          'canPlayInBackground': false,
        },
      ],
    });
    expect(track.isBackgroundPlayable, isFalse);
  });
}
