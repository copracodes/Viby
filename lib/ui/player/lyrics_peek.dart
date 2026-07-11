import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lyrics/lyrics.dart';
import '../../state/lyrics_providers.dart';
import '../theme/tokens.dart';

/// The lyrics "peek" under the transport in the expanded Now Playing: the
/// current line + the next (dimmed) for synced lyrics, or a simple "Lyrics"
/// affordance otherwise. Tapping expands the full lyrics view.
///
/// Renders nothing (a zero-size box) when the track has no lyrics, so the
/// control block reflows with no dead space. Watches only the narrow
/// `lyricsActiveIndexProvider` (an `int`) for the current/next preview, so
/// position ticks that don't cross a line boundary cause no rebuild.
class LyricsPeek extends ConsumerWidget {
  const LyricsPeek({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Lyrics? lyrics = ref.watch(currentLyricsProvider).valueOrNull;
    if (lyrics == null || lyrics.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String currentText;
    final String? nextText;
    if (lyrics.isSynced) {
      final int active = ref.watch(lyricsActiveIndexProvider);
      currentText = active >= 0 && active < lyrics.lines.length
          ? lyrics.lines[active].text
          : (lyrics.lines.isNotEmpty ? lyrics.lines.first.text : '');
      final int next = active + 1;
      nextText =
          next >= 0 && next < lyrics.lines.length ? lyrics.lines[next].text : null;
    } else {
      currentText = 'Lyrics';
      nextText = null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: Radii.brLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: Motion.base,
                        child: Text(
                          currentText.isEmpty ? 'Lyrics' : currentText,
                          key: ValueKey<String>(currentText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (nextText != null && nextText.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          nextText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Icon(Icons.keyboard_arrow_up, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
