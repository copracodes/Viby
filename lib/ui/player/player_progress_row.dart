import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../audio/loop_region.dart';
import '../../core/router.dart';
import '../../state/ab_loop_provider.dart';
import '../../state/lyrics_providers.dart';
import '../widgets/like_button.dart';
import 'ab_repeat_icon.dart';
import 'lyrics_offset_sheet.dart';
import 'player_progress.dart';
import 'sleep_timer_sheet.dart';
import 'speed_sheet.dart';

/// The scrubber flanked by four small, quiet corner actions (Step 2.2 iteration):
/// Love + A-B on the left, Queue + More on the right. All four are one visual
/// family — plain 24dp glyphs with no background container — in a 44dp touch box,
/// secondary-coloured until active (then a color+fill change only); the bar
/// shortens to fit.
///
/// More holds Sleep timer, Equalizer, Playback speed and Adjust sync — the
/// sleep/speed *state* still shows via the chips row by the title. Lyrics has no
/// icon: the peek zone under the transport is its entry point.
class ProgressWithActions extends ConsumerWidget {
  const ProgressWithActions({
    super.key,
    required this.trackId,
    required this.onOpenQueue,
  });

  final String trackId;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AbLoopState ab = ref.watch(abLoopControllerProvider);

    // Icons sit on their own row above the scrubber so neither is cramped:
    // Love + A-B pinned left, Queue + More pinned right.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            LikeButton(trackId: trackId, size: 24),
            _CornerAction(
              // A custom minimal A-B glyph (two markers + a loop arc). Material
              // has no A-B mark, and `repeat_on_outlined` carries a rounded-square
              // background that breaks the plain-glyph family; a bare `repeat`
              // wouldn't read as *A-B* either. Active = primary fill only.
              iconBuilder: (Color c) => AbRepeatIcon(color: c),
              tooltip: 'A-B repeat',
              active: ab is! AbLoopInactive,
              onTap: () => ref.read(abLoopControllerProvider.notifier).tap(),
            ),
            const Spacer(),
            _CornerAction(
              iconBuilder: (Color c) => Icon(Icons.queue_music, color: c),
              tooltip: 'Queue',
              onTap: onOpenQueue,
            ),
            const _MoreAction(),
          ],
        ),
        const PlayerProgress(),
      ],
    );
  }
}

/// A small, quiet corner action: a 24dp glyph, 44dp minimum touch box, secondary
/// colour until [active] (then scheme primary). [iconBuilder] receives the
/// resolved colour so both Material icons and the custom A-B glyph theme alike.
class _CornerAction extends StatelessWidget {
  const _CornerAction({
    required this.iconBuilder,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final Widget Function(Color color) iconBuilder;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = active ? scheme.primary : scheme.onSurfaceVariant;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 24,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: iconBuilder(color),
    );
  }
}

/// The "More" (⋮) corner action: Sleep timer, Equalizer, Playback speed, and
/// Adjust sync (only with time-synced lyrics).
class _MoreAction extends ConsumerWidget {
  const _MoreAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool synced =
        ref.watch(currentLyricsProvider).valueOrNull?.isSynced ?? false;
    return PopupMenuButton<String>(
      tooltip: 'More',
      iconSize: 24,
      icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
      constraints: const BoxConstraints(minWidth: 44),
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
