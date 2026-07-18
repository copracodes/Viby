import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/sleep_timer.dart';
import '../../state/playback_providers.dart';
import '../theme/tokens.dart';
import 'sleep_timer_sheet.dart';
import 'speed_sheet.dart';

/// The "something is not at its default" strip under the title in Now Playing:
/// a live sleep-timer countdown and a speed chip. Both are absent when nothing
/// is armed / speed is 1x, so the layout is unchanged in the normal case — and
/// both are tappable, because a chip you can't act on is just a label. (A-B has
/// moved to a progress-bar corner action; its state shows there and on the bar.)
class PlaybackChips extends ConsumerWidget {
  const PlaybackChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SleepTimerState timer = ref.watch(sleepTimerProvider).valueOrNull ??
        const SleepTimerState.idle();
    final double speed = ref.watch(playbackSpeedProvider).valueOrNull ?? 1.0;

    final bool showSpeed = (speed - 1.0).abs() > 0.001;
    if (!timer.isArmed && !showSpeed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Spacing.sm,
        children: <Widget>[
          if (timer.isArmed)
            _Chip(
              // The icon changes while fading, so the last 10s are legible at a
              // glance rather than only in the numbers.
              icon: timer.isFading
                  ? Icons.volume_down_outlined
                  : Icons.bedtime_outlined,
              label: sleepTimerLabel(timer),
              onTap: () => showSleepTimerSheet(context, ref),
            ),
          if (showSpeed)
            _Chip(
              icon: Icons.speed,
              label: formatSpeed(speed),
              onTap: () => showSpeedSheet(context, ref),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: scheme.primary),
      label: Text(label),
      labelStyle: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: scheme.primary),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      backgroundColor: Colors.transparent,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
