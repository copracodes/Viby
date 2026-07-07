import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
// `material.dart` also exports a `RepeatMode`; hide it so the drift enum wins.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/player_service.dart';
import '../../core/display_names.dart';
import '../../data/db/tables.dart' show RepeatMode;
import '../../data/models/track.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import '../widgets/album_art.dart';
import '../widgets/queue_list.dart';

/// Basic Now Playing screen: a functional full-screen layout wired to the queue
/// and player. Phase 2 replaces it with the full gesture/animation treatment,
/// so this is kept intentionally plain and self-contained.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Up next',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const Expanded(child: QueueListView()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QueueState queue = ref.watch(queueControllerProvider);
    final Track? track = queue.currentTrack;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        title: const Text('Now Playing'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Queue',
            onPressed: () => _showQueue(context),
          ),
        ],
      ),
      body: track == null
          ? const Center(child: Text('Nothing playing.'))
          : GestureDetector(
              // Simple swipe-down to dismiss (interactive drag is Phase 2).
              onVerticalDragEnd: (DragEndDetails d) {
                if ((d.primaryVelocity ?? 0) > 300) context.pop();
              },
              child: _NowPlayingBody(track: track, queue: queue),
            ),
    );
  }
}

class _NowPlayingBody extends ConsumerWidget {
  const _NowPlayingBody({required this.track, required this.queue});

  final Track track;
  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: <Widget>[
            // Art flexes to the space above the controls (square, centered) so
            // the layout never overflows on short screens.
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AlbumArt.expand(
                      artworkKey: track.artworkKey,
                      borderRadius: 24,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              track.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              track.artistName.artistOrUnknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // Queue-scope indicator so it's always clear how big the queue is.
            Text(
              '${queue.currentIndex + 1} of ${queue.length}',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const _Scrubber(),
            const SizedBox(height: 8),
            _TransportRow(queue: queue),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Scrubber extends ConsumerWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final Duration buffered =
        ref.watch(bufferedPositionProvider).valueOrNull ?? Duration.zero;
    final Duration total =
        ref.watch(trackDurationProvider).valueOrNull ?? Duration.zero;

    return ProgressBar(
      progress: position,
      buffered: buffered,
      total: total,
      onSeek: (Duration d) => ref.read(playerServiceProvider).seek(d),
      barHeight: 4,
      thumbRadius: 7,
      timeLabelTextStyle: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _TransportRow extends ConsumerWidget {
  const _TransportRow({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final QueueController controller =
        ref.read(queueControllerProvider.notifier);
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;

    final Color repeatColor = queue.repeatMode == RepeatMode.off
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final IconData repeatIcon = queue.repeatMode == RepeatMode.one
        ? Icons.repeat_one
        : Icons.repeat;

    // Previous does something if there's a track to go back to, or if we're far
    // enough in that a press restarts the current track (the 3s rule).
    final bool canPrevious =
        queue.hasPrevious || position > const Duration(seconds: 3);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        IconButton(
          tooltip: 'Shuffle',
          onPressed: controller.toggleShuffle,
          color: queue.shuffleOn ? scheme.primary : scheme.onSurfaceVariant,
          icon: const Icon(Icons.shuffle),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 40,
          onPressed: canPrevious ? controller.previous : null,
          icon: const Icon(Icons.skip_previous),
        ),
        _PlayButton(playing: playing),
        IconButton(
          tooltip: 'Next',
          iconSize: 40,
          onPressed: queue.hasNext ? controller.next : null,
          icon: const Icon(Icons.skip_next),
        ),
        IconButton(
          tooltip: 'Repeat',
          onPressed: controller.cycleRepeat,
          color: repeatColor,
          icon: Icon(repeatIcon),
        ),
      ],
    );
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: IconButton(
        iconSize: 40,
        color: scheme.onPrimary,
        tooltip: playing ? 'Pause' : 'Play',
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        onPressed: () {
          final PlayerService service = ref.read(playerServiceProvider);
          if (playing) {
            service.pause();
          } else {
            service.play();
          }
        },
      ),
    );
  }
}
