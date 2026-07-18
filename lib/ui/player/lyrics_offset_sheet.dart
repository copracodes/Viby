import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../state/haptics_providers.dart';
import '../../state/lyrics_providers.dart';
import '../theme/tokens.dart';

/// The "Adjust sync" overlay: −0.5s / +0.5s steppers around a live offset
/// readout, plus a reset. Applied while playing (persisted immediately), so a
/// bad sync can be dialled in by ear.
Future<void> showLyricsOffsetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => const _LyricsOffsetSheet(),
  );
}

/// The step size for each nudge (0.5s), in milliseconds.
const int kLyricsOffsetStepMs = 500;

/// "+0.5s" / "−1.2s" / "0.0s" — a signed seconds label for an offset in ms.
String formatLyricsOffset(int offsetMs) {
  if (offsetMs == 0) return '0.0s';
  final String sign = offsetMs > 0 ? '+' : '−';
  final String seconds = (offsetMs.abs() / 1000).toStringAsFixed(1);
  return '$sign${seconds}s';
}

class _LyricsOffsetSheet extends ConsumerWidget {
  const _LyricsOffsetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int offset = ref.watch(currentLyricsOffsetProvider);
    final LyricsController controller =
        ref.read(lyricsControllerProvider.notifier);
    final HapticsService haptics = ref.read(hapticsServiceProvider);

    Future<void> nudge(int deltaMs) async {
      haptics.selection();
      await controller.nudgeOffset(deltaMs);
    }

    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Adjust sync', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                IconButton.filledTonal(
                  iconSize: 28,
                  tooltip: 'Lyrics earlier',
                  icon: const Icon(Icons.remove),
                  onPressed: () => nudge(-kLyricsOffsetStepMs),
                ),
                Text(
                  formatLyricsOffset(offset),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: offset == 0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.primary,
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  tooltip: 'Lyrics later',
                  icon: const Icon(Icons.add),
                  onPressed: () => nudge(kLyricsOffsetStepMs),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Positive delays the lyrics; negative makes them appear sooner.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (offset != 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    haptics.selection();
                    controller.resetOffset();
                  },
                  child: const Text('Reset'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
