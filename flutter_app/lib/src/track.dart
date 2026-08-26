class TrackSource {
  const TrackSource({
    required this.provider,
    required this.providerId,
    required this.canPlayInBackground,
    this.url,
  });

  factory TrackSource.fromJson(Map<String, dynamic> json) => TrackSource(
    provider: json['provider'] as String? ?? 'unknown',
    providerId: json['providerID'] as String? ?? '',
    url: json['url'] as String?,
    canPlayInBackground: json['canPlayInBackground'] as bool? ?? false,
  );

  final String provider;
  final String providerId;
  final String? url;
  final bool canPlayInBackground;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.sources,
    this.album,
    this.artworkUrl,
    this.duration,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Unknown title',
    artist: json['artist'] as String? ?? 'Unknown artist',
    album: json['album'] as String?,
    artworkUrl: json['artworkURL'] as String?,
    duration: (json['duration'] as num?)?.toDouble(),
    sources: (json['sources'] as List<dynamic>? ?? const [])
        .map((value) => TrackSource.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final double? duration;
  final List<TrackSource> sources;

  TrackSource? get backgroundSource {
    for (final source in sources) {
      final uri = Uri.tryParse(source.url ?? '');
      if (source.canPlayInBackground && uri != null && uri.scheme == 'https') {
        return source;
      }
    }
    return null;
  }

  bool get isBackgroundPlayable => backgroundSource != null;
}
