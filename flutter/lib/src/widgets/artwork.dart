import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../domain/track.dart';

class RozzaArtwork extends StatelessWidget {
  const RozzaArtwork({
    super.key,
    required this.track,
    this.borderRadius = 20,
    this.heroTag,
  });

  final Track track;
  final double borderRadius;
  final Object? heroTag;

  /// Tests disable network-backed decoding so golden captures stay offline and
  /// deterministic. Production keeps the cache-backed high-resolution path.
  static bool networkImagesEnabled = true;

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: Color(track.accent),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ArtworkPlaceholder(accent: Color(track.accent)),
              if (track.artworkUrl.isNotEmpty && networkImagesEnabled)
                CachedNetworkImage(
                  imageUrl: track.artworkUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 900,
                  fadeInDuration: const Duration(milliseconds: 240),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x30000000)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return heroTag == null ? content : Hero(tag: heroTag!, child: content);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, .16)!,
            Color.lerp(accent, Colors.black, .42)!,
          ],
        ),
      ),
      child: Center(
        child: Text(
          'R',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .16),
            fontSize: 90,
            fontWeight: FontWeight.w900,
            letterSpacing: -8,
          ),
        ),
      ),
    );
  }
}
