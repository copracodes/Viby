import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/models/track.dart';
import '../../state/haptics_providers.dart';
import '../../state/queue_provider.dart';
import 'album_art.dart';

/// The live play queue as a reorderable, swipe-to-remove list with the current
/// track highlighted. Shared by the Now Playing queue sheet and the debug
/// queue screen — every row action drives `QueueController`.
class QueueListView extends ConsumerWidget {
  const QueueListView({super.key, this.padding});

  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QueueState queue = ref.watch(queueControllerProvider);
    final QueueController controller =
        ref.read(queueControllerProvider.notifier);

    if (queue.isEmpty) {
      return const Center(child: Text('The queue is empty.'));
    }

    return ReorderableListView.builder(
      padding: padding,
      itemCount: queue.length,
      onReorder: (int oldIndex, int newIndex) {
        // ReorderableListView gives an insert-before index; normalise to the
        // post-removal index the engine expects.
        final int to = newIndex > oldIndex ? newIndex - 1 : newIndex;
        ref.read(hapticsServiceProvider).light();
        controller.reorder(oldIndex, to);
      },
      itemBuilder: (BuildContext context, int index) {
        final Track track = queue.tracks[index];
        final bool isCurrent = index == queue.currentIndex;
        final ColorScheme scheme = Theme.of(context).colorScheme;

        return Dismissible(
          key: ValueKey<String>('${track.id}@$index'),
          direction: DismissDirection.endToStart,
          background: ColoredBox(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.delete_outline,
                    color: scheme.onErrorContainer),
              ),
            ),
          ),
          onDismissed: (_) => controller.removeAt(index),
          child: ListTile(
            selected: isCurrent,
            leading: isCurrent
                ? Icon(Icons.equalizer, color: scheme.primary)
                : AlbumArt(artworkKey: track.artworkKey, size: 40),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artistName.artistOrUnknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Overflow (Play next / Remove) + the drag handle. Long-press
            // anywhere on the row still initiates a drag reorder.
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _QueueRowMenu(
                  isCurrent: isCurrent,
                  onPlayNext: () {
                    ref.read(hapticsServiceProvider).light();
                    controller.playNextInQueue(index);
                  },
                  onRemove: () {
                    ref.read(hapticsServiceProvider).light();
                    controller.removeAt(index);
                  },
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
            onTap: () => controller.skipTo(index),
          ),
        );
      },
    );
  }
}

/// Per-row overflow: "Play next" (hidden on the current row, where it's a no-op)
/// and "Remove from queue".
class _QueueRowMenu extends StatelessWidget {
  const _QueueRowMenu({
    required this.isCurrent,
    required this.onPlayNext,
    required this.onRemove,
  });

  final bool isCurrent;
  final VoidCallback onPlayNext;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Track options',
      icon: const Icon(Icons.more_vert),
      onSelected: (String value) {
        switch (value) {
          case 'playNext':
            onPlayNext();
          case 'remove':
            onRemove();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (!isCurrent)
          const PopupMenuItem<String>(
            value: 'playNext',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.playlist_play),
              title: Text('Play next'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'remove',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.remove_circle_outline),
            title: Text('Remove from queue'),
          ),
        ),
      ],
    );
  }
}
