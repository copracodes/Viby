import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/loop_region.dart';
import '../../core/router.dart';
import '../../data/db/tables.dart' show RepeatMode;
import '../../state/ab_loop_provider.dart';
import '../../state/haptics_providers.dart';
import '../../state/lyrics_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/tokens.dart';
import '../widgets/like_button.dart';
import 'lyrics_offset_sheet.dart';
import 'sleep_timer_sheet.dart';
import 'speed_sheet.dart';

/// The secondary action row beneath the transport (Step 2.2 restructure):
/// icon-only, evenly spaced, active states in scheme primary. Holds Like,
/// Repeat (cycles off→all→one, "1" badge on one), Queue, Lyrics, A-B repeat, and
/// an overflow (Sleep timer, Equalizer, Playback speed, Adjust sync).
///
/// Sleep/Speed/A-B also surface their *live* active state in the [PlaybackChips]
/// row above the transport, so parking Sleep/Speed in the overflow loses no
/// visibility. Capped at six slots (five actions + overflow) per the spec.
class SecondaryToolbar extends ConsumerWidget {
  const SecondaryToolbar({
    super.key,
    required this.trackId,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final String trackId;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RepeatMode repeat = ref.watch(
        queueControllerProvider.select((QueueState q) => q.repeatMode));
    final bool queueEmpty =
        ref.watch(queueControllerProvider.select((QueueState q) => q.isEmpty));
    final AbLoopState ab = ref.watch(abLoopControllerProvider);

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          LikeButton(trackId: trackId),
          _RepeatAction(
            mode: repeat,
            onTap: queueEmpty
                ? null
                : () {
                    ref.read(hapticsServiceProvider).selection();
                    ref.read(queueControllerProvider.notifier).cycleRepeat();
                  },
          ),
          _ToolbarIcon(
            icon: Icons.queue_music,
            tooltip: 'Queue',
            onTap: onOpenQueue,
          ),
          _ToolbarIcon(
            icon: Icons.lyrics_outlined,
            tooltip: 'Lyrics',
            onTap: onOpenLyrics,
          ),
          _ToolbarIcon(
            icon: Icons.repeat_on_outlined,
            tooltip: 'A-B repeat',
            active: ab is! AbLoopInactive,
            onTap: () => ref.read(abLoopControllerProvider.notifier).tap(),
          ),
          _OverflowAction(scheme: scheme),
        ],
      ),
    );
  }
}

/// Repeat control: dimmed off, primary on all/one, with a "1" badge for one.
class _RepeatAction extends StatelessWidget {
  const _RepeatAction({required this.mode, required this.onTap});

  final RepeatMode mode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = mode != RepeatMode.off;
    final Color color = (active ? scheme.primary : scheme.onSurfaceVariant)
        .withValues(alpha: onTap == null ? 0.35 : 1.0);
    return _ToolbarIcon(
      icon: mode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
      tooltip: 'Repeat',
      color: color,
      onTap: onTap,
    );
  }
}

/// The overflow menu: Sleep timer, Equalizer, Playback speed, Adjust sync
/// (the last only when the current track has time-synced lyrics).
class _OverflowAction extends ConsumerWidget {
  const _OverflowAction({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool synced =
        ref.watch(currentLyricsProvider).valueOrNull?.isSynced ?? false;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: scheme.onSurface),
      onSelected: (String value) {
        switch (value) {
          case 'sleep':
            showSleepTimerSheet(context, ref);
          case 'eq':
            context.push(AppRoutes.eq);
          case 'speed':
            showSpeedSheet(context, ref);
          case 'adjust':
            showLyricsOffsetSheet(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'sleep',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bedtime_outlined),
            title: Text('Sleep timer'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'eq',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.graphic_eq),
            title: Text('Equalizer'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'speed',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.speed),
            title: Text('Playback speed'),
          ),
        ),
        if (synced)
          const PopupMenuItem<String>(
            value: 'adjust',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.av_timer),
              title: Text('Adjust sync'),
            ),
          ),
      ],
    );
  }
}

/// A single icon-only toolbar action with an active (primary) state.
class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color resolved = color ??
        (active ? scheme.primary : scheme.onSurface)
            .withValues(alpha: onTap == null ? 0.35 : 1.0);
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, color: resolved),
    );
  }
}
