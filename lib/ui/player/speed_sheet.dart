import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_service.dart';
import '../../core/haptics.dart';
import '../../state/haptics_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/player_providers.dart';
import '../theme/tokens.dart';

/// The playback-speed stepper: −/+ in 0.05 steps around a big readout, with the
/// common speeds one tap away and a Reset back to 1.0x.
Future<void> showSpeedSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => const _SpeedSheet(),
  );
}

/// Rounds to the nearest step and clamps to the supported range. Pure.
double stepSpeed(double current, double delta, {double step = 0.05}) {
  final double raw = current + delta;
  final double snapped = (raw / step).roundToDouble() * step;
  return double.parse(
    snapped.clamp(kSpeedMin, kSpeedMax).toStringAsFixed(2),
  );
}

/// "1.5x" / "1x" — trailing zeros are noise on a chip.
String formatSpeed(double speed) {
  final String s = speed.toStringAsFixed(2);
  return '${s.replaceFirst(RegExp(r'\.?0+$'), '')}x';
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double speed = ref.watch(playbackSpeedProvider).valueOrNull ?? 1.0;
    final PlayerService player = ref.read(playerServiceProvider);
    final HapticsService haptics = ref.read(hapticsServiceProvider);

    Future<void> set(double value) async {
      haptics.selection();
      await player.setSpeed(value);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Playback speed', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                IconButton.filledTonal(
                  iconSize: 28,
                  icon: const Icon(Icons.remove),
                  onPressed: speed <= kSpeedMin
                      ? null
                      : () => set(stepSpeed(speed, -0.05)),
                ),
                Text(
                  formatSpeed(speed),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: speed == 1.0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.primary,
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  icon: const Icon(Icons.add),
                  onPressed: speed >= kSpeedMax
                      ? null
                      : () => set(stepSpeed(speed, 0.05)),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: <Widget>[
                for (final double preset in kSpeedPresets)
                  ChoiceChip(
                    label: Text(formatSpeed(preset)),
                    selected: (speed - preset).abs() < 0.001,
                    onSelected: (_) => set(preset),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Pitch stays natural at every speed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (speed != 1.0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => set(1),
                  child: const Text('Reset to 1x'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
