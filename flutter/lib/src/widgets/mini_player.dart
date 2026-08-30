import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/rozza_theme.dart';
import '../playback/playback_controller.dart';
import '../features/now_playing/now_playing_screen.dart';
import 'artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final state = playback.state;
        final track = state.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final progress = track.duration.inMilliseconds == 0
            ? 0.0
            : (state.position.inMilliseconds / track.duration.inMilliseconds)
                  .clamp(0.0, 1.0)
                  .toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Material(
                color: RozzaColors.raised.withValues(alpha: .90),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        transitionDuration: const Duration(milliseconds: 420),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 320,
                        ),
                        pageBuilder: (_, animation, _) => FadeTransition(
                          opacity: animation,
                          child: NowPlayingScreen(playback: playback),
                        ),
                      ),
                    );
                  },
                  child: SizedBox(
                    height: 72,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: SizedBox.square(
                                dimension: 56,
                                child: RozzaArtwork(
                                  track: track,
                                  borderRadius: 14,
                                  heroTag: 'now-playing-${track.id}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: RozzaColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: playback.toggle,
                              icon: Icon(
                                state.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                              ),
                            ),
                            IconButton(
                              onPressed: playback.next,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        PositionedDirectional(
                          start: 72,
                          end: 12,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            color: Color(track.accent),
                            backgroundColor: Colors.white.withValues(
                              alpha: .10,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
