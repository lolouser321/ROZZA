import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatting.dart';
import '../../core/theme/rozza_theme.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/artwork.dart';
import '../queue/queue_sheet.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final state = playback.state;
        final track = state.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final accent = Color(track.accent);
        final maxMs = track.duration.inMilliseconds
            .toDouble()
            .clamp(1, double.infinity)
            .toDouble();
        final positionMs = state.position.inMilliseconds
            .toDouble()
            .clamp(0, maxMs)
            .toDouble();

        return Scaffold(
          backgroundColor: RozzaColors.ink,
          body: Stack(
            fit: StackFit.expand,
            children: [
              RozzaArtwork(track: track, borderRadius: 0),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: .34),
                        const Color(0xF208070B),
                      ],
                      stops: const [0, .72],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artworkSize = (constraints.maxWidth - 48)
                        .clamp(250.0, 430.0)
                        .toDouble();
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 32,
                                ),
                              ),
                              const Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'NOW PLAYING',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.8,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'ROZZA Flow',
                                      style: TextStyle(
                                        color: RozzaColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox.square(
                            dimension: artworkSize,
                            child: RozzaArtwork(
                              track: track,
                              borderRadius: 28,
                              heroTag: 'now-playing-${track.id}',
                            ),
                          ),
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: RozzaColors.muted,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => HapticFeedback.lightImpact(),
                                icon: const Icon(
                                  Icons.favorite_border_rounded,
                                  size: 27,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Slider(
                            value: positionMs,
                            max: maxMs,
                            onChanged: (value) => playback.seek(
                              Duration(milliseconds: value.round()),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatDuration(state.position),
                                  style: const TextStyle(
                                    color: RozzaColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  '-${formatDuration(track.duration - state.position)}',
                                  style: const TextStyle(
                                    color: RozzaColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  color: RozzaColors.muted,
                                ),
                              ),
                              IconButton(
                                onPressed: playback.previous,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 44,
                                ),
                              ),
                              _PlayButton(
                                isPlaying: state.isPlaying,
                                onPressed: playback.toggle,
                              ),
                              IconButton(
                                onPressed: playback.next,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 44,
                                ),
                              ),
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(
                                  Icons.repeat_rounded,
                                  color: RozzaColors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(
                                  Icons.airplay_rounded,
                                  color: RozzaColors.muted,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    showRozzaQueue(context, playback),
                                icon: const Icon(Icons.queue_music_rounded),
                                label: const Text('Up next'),
                              ),
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(
                                  Icons.lyrics_outlined,
                                  color: RozzaColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onPressed});
  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: () {
        HapticFeedback.mediumImpact();
        onPressed();
      },
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: RozzaColors.ink,
        fixedSize: const Size.square(72),
      ),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(isPlaying),
          size: 38,
        ),
      ),
    );
  }
}
