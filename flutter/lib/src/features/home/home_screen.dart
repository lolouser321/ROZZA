import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/rozza_theme.dart';
import '../../data/demo_catalog.dart';
import '../../domain/track.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_row.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('home-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 118,
          backgroundColor: RozzaColors.ink.withValues(alpha: .92),
          surfaceTintColor: Colors.transparent,
          title: const _Wordmark(),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: InkWell(
                onTap: () {},
                customBorder: const CircleBorder(),
                child: const CircleAvatar(
                  radius: 18,
                  backgroundColor: RozzaColors.raised,
                  child: Text(
                    'R',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
          flexibleSpace: const FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(20, 64, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Good evening',
                  style: TextStyle(color: RozzaColors.muted, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Spotlight(
            playback: playback,
            track: DemoCatalog.tracks.first,
          ),
        ),
        const SliverToBoxAdapter(
          child: SectionHeader(title: 'Made for you', action: 'See all'),
        ),
        SliverToBoxAdapter(child: _MixRail(playback: playback)),
        const SliverToBoxAdapter(child: SectionHeader(title: 'Jump back in')),
        SliverList.builder(
          itemCount: DemoCatalog.tracks.length - 1,
          itemBuilder: (context, index) {
            final track = DemoCatalog.tracks[index + 1];
            return TrackRow(
              track: track,
              onTap: () => playback.playTrack(track),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 180)),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'ROZZA',
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w900,
        letterSpacing: 4.5,
      ),
    );
  }
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.playback, required this.track});

  final PlaybackController playback;
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: AspectRatio(
        aspectRatio: 1.45,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RozzaArtwork(track: track, borderRadius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [.24, 1],
                    colors: [Colors.transparent, Color(0xE608070B)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'ROZZA FLOW',
                      style: TextStyle(
                        color: RozzaColors.rose,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A night drive,\nscored for you.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        playback.playTrack(track);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: RozzaColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play Flow'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixRail extends StatelessWidget {
  const _MixRail({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: DemoCatalog.tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = DemoCatalog.tracks[index];
          return SizedBox(
            width: 146,
            child: InkWell(
              onTap: () => playback.playTrack(track),
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: RozzaArtwork(track: track),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'For your evening',
                    maxLines: 1,
                    style: const TextStyle(
                      color: RozzaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
