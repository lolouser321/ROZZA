import '../domain/track.dart';

abstract final class DemoCatalog {
  static const tracks = <Track>[
    Track(
      id: 'midnight-drive',
      title: 'Midnight Drive',
      artist: 'ROZZA Radio',
      album: 'After Dark',
      artworkUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=1200&q=88',
      duration: Duration(minutes: 3, seconds: 42),
      accent: 0xFFFF3D79,
    ),
    Track(
      id: 'desert-light',
      title: 'Desert Light',
      artist: 'Nour',
      album: 'Mirage',
      artworkUrl: 'https://images.unsplash.com/photo-1524368535928-5b5e00ddc76b?auto=format&fit=crop&w=1200&q=88',
      duration: Duration(minutes: 4, seconds: 8),
      accent: 0xFFFF9F43,
    ),
    Track(
      id: 'violet-city',
      title: 'Violet City',
      artist: 'Lina Vale',
      album: 'Neon Hours',
      artworkUrl: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&w=1200&q=88',
      duration: Duration(minutes: 3, seconds: 21),
      accent: 0xFF9C6BFF,
    ),
    Track(
      id: 'blue-room',
      title: 'The Blue Room',
      artist: 'Kairo',
      album: 'Signals',
      artworkUrl: 'https://images.unsplash.com/photo-1524650359799-842906ca1c06?auto=format&fit=crop&w=1200&q=88',
      duration: Duration(minutes: 5, seconds: 4),
      accent: 0xFF55D6E8,
    ),
    Track(
      id: 'slow-bloom',
      title: 'Slow Bloom',
      artist: 'Amaya',
      album: 'Soft Focus',
      artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=1200&q=88',
      duration: Duration(minutes: 2, seconds: 58),
      accent: 0xFF78D79B,
    ),
  ];
}
