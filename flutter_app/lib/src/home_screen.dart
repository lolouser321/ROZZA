import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'audio_handler.dart';
import 'rozza_api.dart';
import 'track.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.handler});
  final RozzaAudioHandler handler;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _api = RozzaApi();
  List<Track> _tracks = const [];
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await _api.search(query);
      if (mounted) setState(() => _tracks = tracks);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Track track) async {
    if (!track.isBackgroundPlayable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'YouTube is foreground-only. Choose a Native audio result for Lock Screen, AirPods, and background controls.',
          ),
        ),
      );
      return;
    }
    try {
      await widget.handler.loadAndPlay(_tracks, _tracks.indexOf(track));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Playback failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ROZZA',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 4),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_api.isConfigured)
              const MaterialBanner(
                content: Text(
                  'Direct Audius mode: real native audio is enabled. Connect the ROZZA backend later for Jamendo and the full catalog.',
                ),
                actions: [SizedBox.shrink()],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _controller,
                hintText: 'Search music',
                leading: const Icon(Icons.search),
                trailing: [
                  IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
                onSubmitted: (_) => _search(),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: _tracks.isEmpty && !_loading
                  ? const _EmptyState()
                  : ListView.builder(
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        return ListTile(
                          onTap: () => _select(track),
                          leading: _Artwork(url: track.artworkUrl),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Chip(
                            avatar: Icon(
                              track.isBackgroundPlayable
                                  ? Icons.headphones
                                  : Icons.ondemand_video,
                              size: 16,
                            ),
                            label: Text(
                              track.isBackgroundPlayable
                                  ? 'Native'
                                  : 'Foreground',
                            ),
                          ),
                        );
                      },
                    ),
            ),
            _NowPlaying(handler: widget.handler),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.handler});
  final RozzaAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        if (item == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF211A2D),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: handler.skipToPrevious,
                  icon: const Icon(Icons.skip_previous),
                ),
                StreamBuilder<PlaybackState>(
                  stream: handler.playbackState,
                  builder: (context, stateSnapshot) {
                    final playing = stateSnapshot.data?.playing ?? false;
                    return IconButton.filled(
                      onPressed: playing ? handler.pause : handler.play,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    );
                  },
                ),
                IconButton(
                  onPressed: handler.skipToNext,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: uri == null
          ? const ColoredBox(
              color: Color(0xFF342744),
              child: SizedBox.square(
                dimension: 48,
                child: Icon(Icons.music_note),
              ),
            )
          : Image.network(
              uri.toString(),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.square(
                dimension: 48,
                child: Icon(Icons.music_note),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones, size: 72, color: Color(0xFF9D5CFF)),
            SizedBox(height: 16),
            Text(
              'Real background audio',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Native streams keep playing when ROZZA is closed or locked and respond to AirPods, Control Center, and Lock Screen controls.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
