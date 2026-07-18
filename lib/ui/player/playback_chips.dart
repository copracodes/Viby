import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/loop_region.dart';
import '../../audio/sleep_timer.dart';
import '../../state/ab_loop_provider.dart';
import '../../state/playback_providers.dart';
import '../theme/tokens.dart';
import 'sleep_timer_sheet.dart';
import 'speed_sheet.dart';

/// The "something is not at its default" strip under the title in Now Playing:
/// a live sleep-timer countdown and a speed chip. Both are absent when nothing
/// is armed / speed is 1x, so the layout is unchanged in the normal case — and
/// both are tappable, because a chip you can't act on is just a label.
class PlaybackChips extends ConsumerWidget {
  const PlaybackChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SleepTimerState timer = ref.watch(sleepTimerProvider).valueOrNull ??
        const SleepTimerState.idle();
    final double speed = ref.watch(playbackSpeedProvider).valueOrNull ?? 1.0;
    final AbLoopState ab = ref.watch(abLoopControllerProvider);

    final bool showSpeed = (speed - 1.0).abs() > 0.001;
    final bool showAb = ab is! AbLoopInactive;
    if (!timer.isArmed && !showSpeed && !showAb) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Spacing.sm,
        children: <Widget>[
          if (showAb)
            _Chip(
              // Pending A (waiting for B) reads as "A ✓"; armed reads "A-B" and
              // is filled. Tapping advances the same state machine as the
              // overflow entry (set B → clear).
              icon: Icons.repeat_on_outlined,
              label: ab is AbLoopArmed ? 'A-B' : 'A ✓',
              active: ab is AbLoopArmed,
              onTap: () => ref.read(abLoopControllerProvider.notifier).tap(),
            ),
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
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Filled (rather than outlined) — the loop is armed, not merely pending.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = active ? scheme.onPrimary : scheme.primary;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: fg),
      label: Text(label),
      labelStyle:
          Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      side: BorderSide(
        color: active
            ? Colors.transparent
            : scheme.primary.withValues(alpha: 0.4),
      ),
      backgroundColor: active ? scheme.primary : Colors.transparent,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
