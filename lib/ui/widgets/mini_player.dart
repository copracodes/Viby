import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/player_service.dart';
import '../../core/display_names.dart';
import '../../data/models/track.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import 'album_art.dart';

/// Persistent mini-player docked above the nav bar. Renders nothing when the
/// queue is empty. Tapping opens Now Playing (Session B); the play/pause button
/// controls transport without leaving the current screen.
///
/// Note: the marquee title/artist is a Phase 2 polish item — for now it
/// ellipsizes.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? track =
        ref.watch(queueControllerProvider.select((QueueState q) => q.currentTrack));
    if (track == null) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;
    final bool hasNext =
        ref.watch(queueControllerProvider.select((QueueState q) => q.hasNext));
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final Duration? duration = ref.watch(trackDurationProvider).valueOrNull;
    final int totalMs = duration?.inMilliseconds ?? track.durationMs;
    final double progress = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push('/now-playing'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: <Widget>[
                  AlbumArt(
                    artworkKey: track.artworkKey,
                    size: 44,
                    borderRadius: 6,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          track.artistName.artistOrUnknown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 32,
                    onPressed: () {
                      final PlayerService service =
                          ref.read(playerServiceProvider);
                      if (playing) {
                        service.pause();
                      } else {
                        service.play();
                      }
                    },
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    iconSize: 32,
                    // Dimmed + inert at the end of the queue (repeat off).
                    onPressed: hasNext
                        ? () => ref.read(queueControllerProvider.notifier).next()
                        : null,
                    icon: const Icon(Icons.skip_next),
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
