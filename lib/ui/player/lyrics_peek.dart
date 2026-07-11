import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lyrics/lyrics.dart';
import '../../state/lyrics_providers.dart';
import '../theme/tokens.dart';
import '../widgets/shimmer.dart';

/// The lyrics "peek" under the transport in the expanded Now Playing.
///
/// - Auto-fetch in flight → a subtle shimmer line (never a spinner takeover).
/// - Synced lyrics → the current line + the next (dimmed).
/// - Instrumental → an "Instrumental" affordance.
/// - No lyrics + online enabled → a "Search for lyrics" affordance.
/// - No lyrics + online off → nothing (zero-size, so the block reflows).
///
/// Tapping expands the full lyrics view. Watches only the narrow
/// `lyricsActiveIndexProvider` (an `int`) for the current/next preview, so
/// position ticks that don't cross a line boundary cause no rebuild.
class LyricsPeek extends ConsumerWidget {
  const LyricsPeek({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Lyrics> async = ref.watch(currentLyricsProvider);

    // Auto-fetch (or a track-change reload) in flight → shimmer, not stale text.
    if (async.isLoading) {
      return _PeekShell(
        onExpand: onExpand,
        child: const SizedBox(
          height: 16,
          width: 160,
          child: Shimmer(borderRadius: Radii.full),
        ),
      );
    }

    final Lyrics? lyrics = async.valueOrNull;
    if (lyrics == null) return const SizedBox.shrink();

    if (lyrics.isInstrumental) {
      return _PeekShell(
        onExpand: onExpand,
        icon: Icons.music_note,
        child: const _PeekLabel('Instrumental'),
      );
    }

    if (lyrics.isEmpty) {
      final bool onlineEnabled = ref.watch(onlineLyricsSettingsProvider
          .select((OnlineLyricsState s) => s.enabled));
      if (!onlineEnabled) return const SizedBox.shrink();
      return _PeekShell(
        onExpand: onExpand,
        icon: Icons.search,
        child: const _PeekLabel('Search for lyrics'),
      );
    }

    // Synced: current + next; unsynced: a plain "Lyrics" affordance.
    String currentText = 'Lyrics';
    String? nextText;
    if (lyrics.isSynced) {
      final int active = ref.watch(lyricsActiveIndexProvider);
      currentText = active >= 0 && active < lyrics.lines.length
          ? lyrics.lines[active].text
          : (lyrics.lines.isNotEmpty ? lyrics.lines.first.text : 'Lyrics');
      final int next = active + 1;
      nextText = next >= 0 && next < lyrics.lines.length
          ? lyrics.lines[next].text
          : null;
    }

    return _PeekShell(
      onExpand: onExpand,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AnimatedSwitcher(
            duration: Motion.base,
            child: _PeekLabel(
              currentText.isEmpty ? 'Lyrics' : currentText,
              key: ValueKey<String>(currentText),
            ),
          ),
          if (nextText != null && nextText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              nextText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The shared peek container: a translucent tappable card with an optional
/// leading icon and a trailing up-chevron.
class _PeekShell extends StatelessWidget {
  const _PeekShell({required this.onExpand, required this.child, this.icon});

  final VoidCallback onExpand;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Spacing.sm),
                ],
                Expanded(child: child),
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

class _PeekLabel extends StatelessWidget {
  const _PeekLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
