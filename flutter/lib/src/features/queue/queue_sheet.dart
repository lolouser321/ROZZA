import 'package:flutter/material.dart';

import '../../core/theme/rozza_theme.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/artwork.dart';

Future<void> showRozzaQueue(BuildContext context, PlaybackController playback) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => QueueSheet(playback: playback),
  );
}

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .82,
      minChildSize: .48,
      maxChildSize: .96,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: const BoxDecoration(
          color: RozzaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: AnimatedBuilder(
          animation: playback,
          builder: (context, _) {
            final state = playback.state;
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RozzaColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Up next',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Save as playlist'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    buildDefaultDragHandles: false,
                    itemCount: state.queue.length,
                    onReorderItem: playback.reorderQueue,
                    itemBuilder: (context, index) {
                      final track = state.queue[index];
                      final active = index == state.queueIndex;
                      return ListTile(
                        key: ValueKey(track.id),
                        onTap: () => playback.playTrack(track),
                        contentPadding: const EdgeInsetsDirectional.fromSTEB(
                          20,
                          4,
                          12,
                          4,
                        ),
                        leading: SizedBox.square(
                          dimension: 50,
                          child: RozzaArtwork(track: track, borderRadius: 12),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? RozzaColors.rose : RozzaColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          style: const TextStyle(color: RozzaColors.muted),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: RozzaColors.muted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
