import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_service.dart';
import '../../audio/sleep_timer.dart';
import '../../core/haptics.dart';
import '../../state/haptics_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/player_providers.dart';
import '../theme/tokens.dart';

/// "Stop playing in…" — the presets, the two conditional modes, and (when armed)
/// extend / cancel.
Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SleepTimerState timer =
        ref.watch(sleepTimerProvider).valueOrNull ?? const SleepTimerState.idle();
    final PlayerService player = ref.read(playerServiceProvider);
    final HapticsService haptics = ref.read(hapticsServiceProvider);

    Future<void> arm(SleepMode mode) async {
      haptics.selection();
      await player.armSleepTimer(mode);
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Text('Sleep timer', style: theme.textTheme.titleLarge),
            ),
            if (timer.isArmed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Text(
                  sleepTimerLabel(timer, long: true),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: <Widget>[
                  for (final Duration d in kSleepPresets)
                    ChoiceChip(
                      label: Text('${d.inMinutes} min'),
                      selected: timer.mode == SleepAfter(d),
                      onSelected: (_) => arm(SleepAfter(d)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('End of track'),
              selected: timer.mode is SleepEndOfTrack,
              onTap: () => arm(const SleepEndOfTrack()),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_outlined),
              title: const Text('End of queue'),
              selected: timer.mode is SleepEndOfQueue,
              onTap: () => arm(const SleepEndOfQueue()),
            ),
            if (timer.isArmed) ...<Widget>[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('15 min'),
                        onPressed: () async {
                          haptics.selection();
                          await player
                              .extendSleepTimer(const Duration(minutes: 15));
                        },
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel timer'),
                        onPressed: () async {
                          haptics.selection();
                          await player.cancelSleepTimer();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              const SizedBox(height: Spacing.md),
            // The fade is the point of the feature: say so once, here.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.lg),
              child: Text(
                'Music fades out over the last '
                '${kSleepFadeOut.inSeconds} seconds instead of cutting off.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chip / sheet label for a timer state. Pure so it can be unit-tested.
String sleepTimerLabel(SleepTimerState timer, {bool long = false}) {
  final SleepMode? mode = timer.mode;
  if (mode == null) return '';
  final Duration? left = timer.remaining;
  if (left != null) {
    final int minutes = left.inMinutes;
    final int seconds = left.inSeconds % 60;
    final String clock = minutes > 0
        ? '$minutes:${seconds.toString().padLeft(2, '0')}'
        : '0:${seconds.toString().padLeft(2, '0')}';
    return long ? 'Stopping in $clock' : clock;
  }
  return switch (mode) {
    SleepEndOfTrack() => long ? 'Stopping at the end of this track' : 'End of track',
    SleepEndOfQueue() => long ? 'Stopping at the end of the queue' : 'End of queue',
    SleepAfter() => long ? 'Timer armed' : 'On',
  };
}
