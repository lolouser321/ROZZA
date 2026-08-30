import 'package:flutter/material.dart';

import '../../core/theme/rozza_theme.dart';
import '../../data/demo_catalog.dart';
import '../../domain/track.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/track_row.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String query = '';

  List<Track> get results {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return DemoCatalog.tracks
        .where(
          (track) => '${track.title} ${track.artist} ${track.album}'
              .toLowerCase()
              .contains(needle),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('search-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverAppBar.large(
          title: Text('Search'),
          backgroundColor: RozzaColors.ink,
          surfaceTintColor: Colors.transparent,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Artists, songs, lyrics and moods',
                hintStyle: const TextStyle(color: RozzaColors.muted),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: const Icon(Icons.mic_none_rounded),
                filled: true,
                fillColor: RozzaColors.raised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (query.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Text(
                'Browse by feeling',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              itemCount: _moods.length,
              itemBuilder: (context, index) => _MoodCard(data: _moods[index]),
            ),
          ),
        ] else if (results.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No match yet. Try an artist or mood.',
                style: TextStyle(color: RozzaColors.muted),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final track = results[index];
              return TrackRow(
                track: track,
                onTap: () => widget.playback.playTrack(track),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 180)),
      ],
    );
  }
}

class _MoodData {
  const _MoodData(this.title, this.subtitle, this.colors, this.icon);
  final String title;
  final String subtitle;
  final List<Color> colors;
  final IconData icon;
}

const _moods = [
  _MoodData('After dark', 'Deep & cinematic', [
    Color(0xFF671B4B),
    Color(0xFF1D102B),
  ], Icons.dark_mode_rounded),
  _MoodData('Energy', 'Move without stopping', [
    Color(0xFFFF5B35),
    Color(0xFF712418),
  ], Icons.bolt_rounded),
  _MoodData('Arabic soul', 'Roots, reimagined', [
    Color(0xFFD29342),
    Color(0xFF4B2B20),
  ], Icons.auto_awesome_rounded),
  _MoodData('Focus', 'Quietly in the zone', [
    Color(0xFF287F8A),
    Color(0xFF152E43),
  ], Icons.blur_on_rounded),
  _MoodData('New wave', 'Fresh this week', [
    Color(0xFF6B55D9),
    Color(0xFF27244D),
  ], Icons.waves_rounded),
  _MoodData('Slow down', 'Soft around the edges', [
    Color(0xFF4D8267),
    Color(0xFF1A3932),
  ], Icons.spa_rounded),
];

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.data});
  final _MoodData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: data.colors),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              end: 10,
              bottom: 5,
              child: Icon(
                data.icon,
                size: 58,
                color: Colors.white.withValues(alpha: .16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    data.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: .68),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
