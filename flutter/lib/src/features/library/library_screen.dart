import 'package:flutter/material.dart';

import '../../core/theme/rozza_theme.dart';
import '../../data/demo_catalog.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/track_row.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int filter = 0;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar.large(
          title: const Text('Your Library'),
          backgroundColor: RozzaColors.ink,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.add_rounded)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.tune_rounded)),
            const SizedBox(width: 8),
          ],
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ChoiceChip(
                label: Text(_filters[index]),
                selected: filter == index,
                onSelected: (_) => setState(() => filter = index),
                selectedColor: RozzaColors.text,
                backgroundColor: RozzaColors.raised,
                labelStyle: TextStyle(
                  color: filter == index ? RozzaColors.ink : RozzaColors.text,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide.none,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _LibrarySummary()),
        SliverList.builder(
          itemCount: DemoCatalog.tracks.length,
          itemBuilder: (context, index) {
            final track = DemoCatalog.tracks.reversed.toList(
              growable: false,
            )[index];
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

const _filters = ['All', 'Playlists', 'Albums', 'Artists', 'Downloaded'];

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Row(
        children: [
          _SummaryTile(
            icon: Icons.favorite_rounded,
            color: RozzaColors.rose,
            title: 'Liked songs',
            detail: '128 tracks',
          ),
          const SizedBox(width: 12),
          _SummaryTile(
            icon: Icons.auto_awesome_rounded,
            color: RozzaColors.violet,
            title: 'Your Flow',
            detail: 'Always evolving',
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 126,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RozzaColors.raised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: RozzaColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 29),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: RozzaColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
