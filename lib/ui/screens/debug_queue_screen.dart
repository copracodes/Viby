// `material.dart` also exports a `RepeatMode` (animation); hide it so the
// Viby-domain RepeatMode (drift enum) is unambiguous here.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_service.dart';
import '../../data/db/daos/library_dao.dart';
import '../../data/db/tables.dart' show RepeatMode;
import '../../data/models/track.dart';
import '../../state/library_providers.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import '../../state/track_resolver.dart';
import '../widgets/queue_list.dart';

/// THROWAWAY debug screen (route `/debug-queue`) for driving the queue engine:
/// play/shuffle the scanned library, skip, reorder (drag) and remove (swipe).
/// No polish; deleted once the real player/queue UI lands.
class DebugQueueScreen extends ConsumerWidget {
  const DebugQueueScreen({super.key});

  Future<List<Track>> _resolve(WidgetRef ref, List<TrackWithMeta> metas) {
    return resolveTracks(metas, ref.read(artworkServiceProvider));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QueueState queue = ref.watch(queueControllerProvider);
    final AsyncValue<List<TrackWithMeta>> library = ref.watch(allTracksProvider);
    final QueueController controller = ref.read(queueControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug · Queue'),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
      body: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            child: Text(
              '⚠ Throwaway debug tooling — not shipped UI.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          _NowPlaying(queue: queue),
          _LibraryActions(
            library: library,
            onPlayAll: (List<TrackWithMeta> metas) async {
              final List<Track> tracks = await _resolve(ref, metas);
              await controller.setQueue(tracks, autoPlay: true);
            },
            onShuffleAll: (List<TrackWithMeta> metas) async {
              final List<Track> tracks = await _resolve(ref, metas);
              await controller.setQueue(tracks, autoPlay: true, shuffle: true);
            },
          ),
          const Divider(height: 1),
          const Expanded(child: QueueListView()),
        ],
      ),
    );
  }
}

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;
    final Track? current = queue.currentTrack;
    final QueueController controller = ref.read(queueControllerProvider.notifier);
    final PlayerService player = ref.read(playerServiceProvider);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            current == null
                ? 'Nothing playing'
                : '${current.title} · ${current.artistName ?? '—'}',
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'index ${queue.currentIndex + 1}/${queue.length} · '
            'shuffle ${queue.shuffleOn ? 'on' : 'off'} · '
            'repeat ${queue.repeatMode.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              IconButton(
                onPressed: controller.previous,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                iconSize: 40,
                onPressed: () => playing ? player.pause() : player.play(),
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
              ),
              IconButton(
                onPressed: controller.next,
                icon: const Icon(Icons.skip_next),
              ),
              const Spacer(),
              IconButton(
                onPressed: controller.toggleShuffle,
                isSelected: queue.shuffleOn,
                icon: const Icon(Icons.shuffle),
              ),
              IconButton(
                onPressed: controller.cycleRepeat,
                icon: Icon(switch (queue.repeatMode) {
                  RepeatMode.off => Icons.repeat,
                  RepeatMode.all => Icons.repeat_on,
                  RepeatMode.one => Icons.repeat_one_on,
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LibraryActions extends StatelessWidget {
  const _LibraryActions({
    required this.library,
    required this.onPlayAll,
    required this.onShuffleAll,
  });

  final AsyncValue<List<TrackWithMeta>> library;
  final Future<void> Function(List<TrackWithMeta>) onPlayAll;
  final Future<void> Function(List<TrackWithMeta>) onShuffleAll;

  @override
  Widget build(BuildContext context) {
    return library.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object e, _) => Text('Library error: $e'),
      data: (List<TrackWithMeta> metas) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    metas.isEmpty ? null : () => onPlayAll(metas),
                icon: const Icon(Icons.playlist_play),
                label: Text('Play all (${metas.length})'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed:
                    metas.isEmpty ? null : () => onShuffleAll(metas),
                icon: const Icon(Icons.shuffle),
                label: const Text('Shuffle all'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

