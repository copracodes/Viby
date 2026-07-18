import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/display_names.dart';
import '../../data/lyrics/lyrics.dart';
import '../../data/models/track.dart';
import '../../state/lyrics_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import 'lyrics_follow.dart';
import 'lyrics_how_to.dart';
import 'lyrics_offset_sheet.dart';
import 'lyrics_search_sheet.dart';
import 'player_progress.dart';
import 'player_transport.dart';

/// The full-screen lyrics experience — cross-faded in over the artwork Now
/// Playing (see `PlayerOverlay`). Synced lyrics scroll and highlight with
/// tap-to-seek; unsynced lyrics render as static scrollable text; a missing set
/// shows a tasteful empty state + "How to add lyrics".
///
/// Auto-scroll keeps the active line at ~35% of the viewport. A manual scroll
/// pauses auto-follow (a resume pill appears; it also auto-resumes 4s later) via
/// the pure [LyricsFollow] state machine. Playback ticks only ever change the
/// narrow `lyricsActiveIndexProvider` (an `int`), so a tick that doesn't cross a
/// line boundary causes no rebuild here.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, required this.onCollapse});

  /// Collapses the lyrics view back to the artwork Now Playing.
  final VoidCallback onCollapse;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _lineKeys = const <GlobalKey>[];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureKeys(int count) {
    if (_lineKeys.length != count) {
      _lineKeys = List<GlobalKey>.generate(count, (_) => GlobalKey());
    }
  }

  void _scrollToLine(int index, {bool animate = true}) {
    if (index < 0 || index >= _lineKeys.length) return;
    final BuildContext? ctx = _lineKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35, // keep the active line ~35% down the viewport
        duration: animate ? Motion.emphasized : Duration.zero,
        curve: Motion.emphasizedDecelerate,
      );
      return;
    }
    // The target line isn't built (a far seek): jump proportionally. Once it
    // lays out, the next active-index change re-runs this and ensureVisible
    // lands it precisely.
    if (_scroll.hasClients) {
      final double max = _scroll.position.maxScrollExtent;
      final double target =
          (_lineKeys.isEmpty ? 0.0 : index / _lineKeys.length) * max;
      _scroll.animateTo(
        target.clamp(0.0, max),
        duration: Motion.emphasized,
        curve: Motion.emphasizedDecelerate,
      );
    }
  }

  bool _onScroll(ScrollNotification n) {
    final LyricsFollowController follow =
        ref.read(lyricsFollowControllerProvider.notifier);
    // Only user drags pause auto-follow; programmatic auto-scroll (dragDetails
    // null while `following`) settles as a no-op (see shouldArmResumeTimer).
    if (n is ScrollStartNotification && n.dragDetails != null) {
      follow.dispatch(LyricsFollowEvent.userScrolled);
    } else if (n is ScrollEndNotification) {
      follow.dispatch(LyricsFollowEvent.scrollSettled);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Reset follow + scroll on track change.
    ref.listen<String?>(
      queueControllerProvider.select((QueueState q) => q.currentTrack?.id),
      (String? _, String? __) {
        ref
            .read(lyricsFollowControllerProvider.notifier)
            .dispatch(LyricsFollowEvent.trackChanged);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      },
    );
    // Auto-scroll as the active line advances (only while following).
    ref.listen<int>(lyricsActiveIndexProvider, (int? _, int next) {
      if (ref.read(lyricsFollowControllerProvider).isFollowing) {
        _scrollToLine(next);
      }
    });
    // When following resumes, snap back to the active line.
    ref.listen<LyricsFollowState>(lyricsFollowControllerProvider,
        (LyricsFollowState? prev, LyricsFollowState next) {
      if ((prev == null || !prev.isFollowing) && next.isFollowing) {
        _scrollToLine(ref.read(lyricsActiveIndexProvider));
      }
    });

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final Track? track =
        ref.watch(queueControllerProvider.select((QueueState q) => q.currentTrack));
    final AsyncValue<Lyrics> lyricsAsync = ref.watch(currentLyricsProvider);

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
        child: Column(
          children: <Widget>[
            _Header(track: track, onCollapse: widget.onCollapse),
            Expanded(
              child: lyricsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const _Empty(),
                data: (Lyrics lyrics) => _body(context, lyrics, scheme),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Spacing.xl, vertical: Spacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[PlayerProgress(), PlayerTransport()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Lyrics lyrics, ColorScheme scheme) {
    if (lyrics.isInstrumental) return _Instrumental(scheme: scheme);
    if (lyrics.isEmpty) return const _Empty();
    _ensureKeys(lyrics.lines.length);
    final int active = ref.watch(lyricsActiveIndexProvider);
    final bool paused =
        ref.watch(lyricsFollowControllerProvider.select((s) => s.showResumePill));

    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _scroll,
            // Generous cache so the next active line is usually already built,
            // letting ensureVisible target it precisely.
            cacheExtent: 800,
            padding: EdgeInsets.fromLTRB(
              Spacing.xl,
              Spacing.xl,
              Spacing.xl,
              MediaQuery.sizeOf(context).height * 0.4,
            ),
            itemCount: lyrics.lines.length + (lyrics.isSynced ? 0 : 1),
            itemBuilder: (BuildContext context, int i) {
              if (!lyrics.isSynced && i == 0) {
                return _UnsyncedCaption(scheme: scheme);
              }
              final int lineIndex = lyrics.isSynced ? i : i - 1;
              final LyricLine line = lyrics.lines[lineIndex];
              return _LyricLineTile(
                key: _lineKeys[lineIndex],
                line: line,
                isActive: lyrics.isSynced && lineIndex == active,
                distance: active < 0 ? 0 : (lineIndex - active).abs(),
                synced: lyrics.isSynced,
                scheme: scheme,
                onTap: lyrics.isSynced
                    ? () {
                        ref
                            .read(lyricsControllerProvider.notifier)
                            .seekToLine(line.startMs);
                        ref
                            .read(lyricsFollowControllerProvider.notifier)
                            .dispatch(LyricsFollowEvent.resumeTapped);
                      }
                    : null,
              );
            },
          ),
        ),
        // A manual sync offset is in effect → a subtle caption at the top.
        if (lyrics.isSynced)
          Positioned(
            top: Spacing.xs,
            left: 0,
            right: 0,
            child: Center(child: _OffsetCaption(scheme: scheme)),
          ),
        if (paused)
          Positioned(
            bottom: Spacing.xxl,
            left: 0,
            right: 0,
            child: Center(child: _ResumePill(onTap: _resume)),
          ),
        // Attribution for online-sourced lyrics — tappable to re-search when the
        // auto-match is wrong.
        if (lyrics.isOnline)
          Positioned(
            bottom: Spacing.xs,
            left: 0,
            right: 0,
            child: Center(
              child: _Attribution(
                onTap: () => showLyricsSearchSheet(context),
              ),
            ),
          ),
      ],
    );
  }

  void _resume() {
    ref
        .read(lyricsFollowControllerProvider.notifier)
        .dispatch(LyricsFollowEvent.resumeTapped);
  }
}

/// Header: collapse chevron, the artwork "corner thumb" + title/artist, and an
/// overflow (Refresh lyrics / How to add lyrics).
class _Header extends ConsumerWidget {
  const _Header({required this.track, required this.onCollapse});

  final Track? track;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.xs, Spacing.xs, Spacing.xs, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Close lyrics',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: onCollapse,
          ),
          AlbumArt(
            artworkKey: track?.artworkKey,
            size: 40,
            borderRadius: Radii.sm,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  track?.title ?? 'Lyrics',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                if (track != null)
                  Text(
                    track!.artistName.artistOrUnknown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String v) {
              switch (v) {
                case 'refresh':
                  ref.read(lyricsControllerProvider.notifier).refresh();
                case 'adjust':
                  showLyricsOffsetSheet(context);
                case 'search':
                  showLyricsSearchSheet(context);
                case 'howto':
                  showHowToAddLyricsSheet(context);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'refresh',
                child: Text('Refresh lyrics'),
              ),
              // Only offer sync adjustment for time-synced lyrics (it does
              // nothing for a static/unsynced sheet).
              if (ref.watch(currentLyricsProvider).valueOrNull?.isSynced ??
                  false)
                const PopupMenuItem<String>(
                  value: 'adjust',
                  child: Text('Adjust sync'),
                ),
              if (ref.watch(onlineLyricsSettingsProvider
                  .select((OnlineLyricsState s) => s.enabled)))
                const PopupMenuItem<String>(
                  value: 'search',
                  child: Text('Search online'),
                ),
              const PopupMenuItem<String>(
                value: 'howto',
                child: Text('How to add lyrics'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single lyric line. Active line: full opacity, scheme primary, w600, scaled
/// 1.04. Neighbours fade progressively by [distance]. Transitions are animated
/// so the highlight glides as the active line advances.
class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    super.key,
    required this.line,
    required this.isActive,
    required this.distance,
    required this.synced,
    required this.scheme,
    this.onTap,
  });

  final LyricLine line;
  final bool isActive;
  final int distance;
  final bool synced;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (line.text.isEmpty) {
      // A musical-gap line: a small breathing space, never highlighted.
      return const SizedBox(height: Spacing.lg);
    }
    final double opacity = isActive
        ? 1.0
        : synced
            ? (1.0 - 0.16 * distance).clamp(0.32, 0.8)
            : 0.85;
    final Color color = isActive ? scheme.primary : scheme.onSurface;
    final TextStyle base = Theme.of(context).textTheme.titleLarge!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: AnimatedScale(
          scale: isActive ? 1.04 : 1.0,
          alignment: Alignment.centerLeft,
          duration: Motion.base,
          curve: Motion.standard,
          child: AnimatedDefaultTextStyle(
            duration: Motion.base,
            curve: Motion.standard,
            style: base.copyWith(
              color: color.withValues(alpha: opacity),
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              height: 1.3,
            ),
            child: Text(line.text),
          ),
        ),
      ),
    );
  }
}

/// A small tappable caption shown while a manual sync offset is in effect
/// ("Synced offset +0.5s"), hidden at 0. Tapping reopens the adjuster.
class _OffsetCaption extends ConsumerWidget {
  const _OffsetCaption({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int offset = ref.watch(currentLyricsOffsetProvider);
    if (offset == 0) return const SizedBox.shrink();
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: Radii.brFull,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showLyricsOffsetSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.av_timer, size: 14, color: scheme.primary),
              const SizedBox(width: Spacing.xs),
              Text(
                'Synced offset ${formatLyricsOffset(offset)}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnsyncedCaption extends StatelessWidget {
  const _UnsyncedCaption({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.schedule_outlined,
              size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.xs),
          Text(
            'Not time-synced',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResumePill extends StatelessWidget {
  const _ResumePill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: Radii.brFull,
      elevation: Elevations.level2,
      child: InkWell(
        borderRadius: Radii.brFull,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.vertical_align_center,
                  size: 18, color: scheme.onPrimary),
              const SizedBox(width: Spacing.xs),
              Text(
                'Resume',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty state, online-aware: when online lyrics are on it offers "Search
/// online"; when off it offers to enable them. Always offers "How to add lyrics".
class _Empty extends ConsumerWidget {
  const _Empty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool onlineEnabled = ref.watch(onlineLyricsSettingsProvider
        .select((OnlineLyricsState s) => s.enabled));

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lyrics_outlined, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: Spacing.md),
          Text(
            'No lyrics for this song',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.sm),
          if (onlineEnabled)
            FilledButton.tonalIcon(
              onPressed: () => showLyricsSearchSheet(context),
              icon: const Icon(Icons.search),
              label: const Text('Search online'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => ref
                  .read(onlineLyricsSettingsProvider.notifier)
                  .setEnabled(true),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Enable online lyrics'),
            ),
          const SizedBox(height: Spacing.xs),
          TextButton.icon(
            onPressed: () => showHowToAddLyricsSheet(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('How to add lyrics'),
          ),
        ],
      ),
    );
  }
}

/// The confirmed-instrumental state (LRCLIB flag).
class _Instrumental extends StatelessWidget {
  const _Instrumental({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.music_note, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: Spacing.md),
          Text(
            'Instrumental',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// "Lyrics from LRCLIB" attribution, tappable to re-search on a mismatch.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: Theme.of(context).textTheme.labelMedium,
      ),
      child: const Text('Lyrics from LRCLIB · Wrong? Tap to search'),
    );
  }
}
