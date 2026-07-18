import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_service.dart';
import '../../core/display_names.dart';
import '../../data/models/track.dart';
import '../../state/haptics_providers.dart';
import '../../state/player_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/dynamic_theme_scope.dart';
import '../theme/tokens.dart';
import '../widgets/equalizer_bars.dart';
import 'playback_chips.dart';
import 'secondary_toolbar.dart';
import '../widgets/queue_list.dart';
import 'artwork_stage.dart';
import 'lyrics_peek.dart';
import 'lyrics_view.dart';
import 'now_playing_backdrop.dart';
import 'player_progress.dart';
import 'player_transport.dart';
import 'player_transition.dart';

/// The unified player surface: a single overlay that is the docked mini-player
/// at expansion 0 and the full-screen Now Playing at expansion 1, with one
/// [AnimationController] driven by drags and taps. Replaces the old modal route
/// so mini → full is one continuous, interruptible, interactive transition.
///
/// It lives above the nav shell (hosted by `AppShell`) and only occupies the
/// mini-bar rect while collapsed, so the shell beneath stays interactive.
class PlayerOverlay extends ConsumerStatefulWidget {
  const PlayerOverlay({super.key});

  /// Docked mini-bar height.
  static const double miniHeight = 64;

  /// Our `NavigationBar`'s height (label + icon), before the bottom safe area.
  static const double navBarHeight = 80;

  @override
  ConsumerState<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends ConsumerState<PlayerOverlay>
    with TickerProviderStateMixin {
  // Created eagerly in initState (not a lazy `late final`): the overlay may be
  // disposed while collapsed-and-empty having never accessed the controller in
  // build, and lazily creating a Ticker inside dispose() is illegal.
  late final AnimationController _c;

  // Lyrics sub-state: 0 = artwork Now Playing, 1 = full-screen lyrics. Only
  // meaningful while fully expanded (_c.value == 1); the two cross-fade.
  late final AnimationController _lyricsC;

  double _dragOrigin = 0;
  double _expandDistance = 1;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Motion.emphasized,
      value: 0,
    );
    _lyricsC = AnimationController(
      vsync: this,
      duration: Motion.emphasized,
      value: 0,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    _lyricsC.dispose();
    super.dispose();
  }

  void _expandLyrics() => _lyricsC.animateTo(1,
      duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  void _collapseLyrics() => _lyricsC.animateTo(0,
      duration: Motion.emphasized, curve: Motion.emphasizedAccelerate);

  void _expand() =>
      _c.animateTo(1, duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  void _collapse() {
    // Reset the lyrics sub-state so re-opening the player shows the artwork.
    _lyricsC.value = 0;
    _c.animateTo(0,
        duration: Motion.emphasized, curve: Motion.emphasizedAccelerate);
  }

  void _onDragStart(DragStartDetails _) => _dragOrigin = _c.value;

  void _onDragUpdate(DragUpdateDetails d) {
    // Drag up (negative dy) opens.
    _c.value = (_c.value - d.delta.dy / _expandDistance).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final double velocityFraction =
        -(d.primaryVelocity ?? 0) / _expandDistance;
    final SettleTarget target = settleTarget(
      value: _c.value,
      velocity: velocityFraction,
      origin: _dragOrigin,
    );
    target == SettleTarget.expanded ? _expand() : _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = ref.watch(
      queueControllerProvider.select((QueueState q) => q.currentTrack),
    );
    if (track == null) return const SizedBox.shrink();

    return DynamicThemeScope(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double h = constraints.maxHeight;
          final double w = constraints.maxWidth;
          final EdgeInsets pad = MediaQuery.paddingOf(context);
          final double navBar = PlayerOverlay.navBarHeight + pad.bottom;
          final double collapsedTop = h - navBar - PlayerOverlay.miniHeight;
          _expandDistance = collapsedTop <= 0 ? 1 : collapsedTop;

          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_c, _lyricsC]),
            builder: (BuildContext context, _) => _buildFrame(
              context,
              track: track,
              h: h,
              w: w,
              pad: pad,
              navBar: navBar,
              collapsedTop: collapsedTop,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrame(
    BuildContext context, {
    required Track track,
    required double h,
    required double w,
    required EdgeInsets pad,
    required double navBar,
    required double collapsedTop,
  }) {
    final double t = _c.value;
    final double ct = Motion.standard.transform(t.clamp(0.0, 1.0));

    // Panel rect (screen coords): mini-bar strip → full screen.
    final double panelTop = _lerp(collapsedTop, 0, ct);
    final double panelBottom = _lerp(navBar, 0, ct); // inset from bottom

    // Artwork shared-element rect (screen coords).
    const double miniArt = 48;
    final double fullArt = (w - 2 * Spacing.xl).clamp(0.0, h * 0.5);
    final Rect miniRect = Rect.fromLTWH(
      Spacing.md,
      collapsedTop + (PlayerOverlay.miniHeight - miniArt) / 2,
      miniArt,
      miniArt,
    );
    final double fullArtTop = pad.top + Spacing.xxxl + Spacing.lg;
    final Rect fullRect =
        Rect.fromLTWH((w - fullArt) / 2, fullArtTop, fullArt, fullArt);
    final Rect artScreen = Rect.lerp(miniRect, fullRect, ct)!;
    final double artRadius = _lerp(Radii.sm, Radii.lg, ct);

    final double fadeMini = (1 - t / 0.28).clamp(0.0, 1.0);
    // Lyrics take over as `lv` rises; the artwork Now Playing fades out under it.
    final double lv = Motion.standard.transform(_lyricsC.value.clamp(0.0, 1.0));
    final double fadeFull = ((t - 0.35) / 0.65).clamp(0.0, 1.0) * (1 - lv);
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;

    return Stack(
      children: <Widget>[
        // Backdrop — never hit-tests; opacity follows the transition.
        if (t > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: t,
                child: NowPlayingBackdrop(artworkKey: track.artworkKey),
              ),
            ),
          ),

        // The interactive panel (mini strip → full). Only this captures touch,
        // so while collapsed the shell above the strip stays usable.
        Positioned(
          top: panelTop,
          left: 0,
          right: 0,
          bottom: panelBottom,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: t < 0.5 ? _expand : null,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: _PanelContents(
              t: t,
              track: track,
              fadeMini: fadeMini,
              fadeFull: fadeFull,
              artFade: 1 - lv,
              playing: playing,
              // Artwork rect translated into panel-local coordinates.
              artLocalRect: artScreen.translate(0, -panelTop),
              artRadius: artRadius,
              topInset: pad.top,
              onCollapse: _collapse,
              onOpenQueue: () => _openQueue(context),
              onExpandLyrics: _expandLyrics,
            ),
          ),
        ),

        // Full-screen lyrics, cross-faded above the artwork Now Playing.
        if (lv > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: lv < 0.5,
              child: Opacity(
                opacity: lv,
                child: LyricsView(onCollapse: _collapseLyrics),
              ),
            ),
          ),
      ],
    );
  }

  void _openQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _QueueSheet(
        onClear: () => _confirmClear(sheetContext),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext sheetContext) async {
    final bool ok = await showDialog<bool>(
          context: sheetContext,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Clear queue?'),
            content: const Text('This stops playback and empties the queue.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await ref.read(queueControllerProvider.notifier).clear();
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// The panel's stacked contents: mini row (fades out), full layout (fades in),
/// and the shared-element artwork positioned in panel-local coordinates.
class _PanelContents extends StatelessWidget {
  const _PanelContents({
    required this.t,
    required this.track,
    required this.fadeMini,
    required this.fadeFull,
    required this.artFade,
    required this.playing,
    required this.artLocalRect,
    required this.artRadius,
    required this.topInset,
    required this.onCollapse,
    required this.onOpenQueue,
    required this.onExpandLyrics,
  });

  final double t;
  final Track track;
  final double fadeMini;
  final double fadeFull;

  /// Shared-element artwork opacity (1 → visible, 0 → lyrics have taken over).
  final double artFade;
  final bool playing;
  final Rect artLocalRect;
  final double artRadius;
  final double topInset;
  final VoidCallback onCollapse;
  final VoidCallback onOpenQueue;
  final VoidCallback onExpandLyrics;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // Mini-bar surface + progress hairline (collapsed look).
        if (fadeMini > 0.001)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: PlayerOverlay.miniHeight,
            child: IgnorePointer(
              ignoring: t > 0.05,
              child: Opacity(
                opacity: fadeMini,
                child: _MiniRow(track: track, playing: playing),
              ),
            ),
          ),

        // Full layout: top bar + bottom controls (artwork floats between).
        if (fadeFull > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: t < 0.9,
              child: Opacity(
                opacity: fadeFull,
                child: _FullLayout(
                  track: track,
                  topInset: topInset,
                  onCollapse: onCollapse,
                  onOpenQueue: onOpenQueue,
                  onExpandLyrics: onExpandLyrics,
                ),
              ),
            ),
          ),

        // Shared-element artwork (fades out as lyrics take over).
        if (artFade > 0.001)
          Positioned.fromRect(
            rect: artLocalRect,
            child: IgnorePointer(
              ignoring: artFade < 0.5,
              child: Opacity(
                opacity: artFade,
                child: ArtworkStage(
                  size: artLocalRect.width,
                  borderRadius: artRadius,
                  enabled: t > 0.98 && artFade > 0.98,
                  playing: playing,
                ),
              ),
            ),
          ),

        // Mini play/next controls sit to the right of the thumb (tap targets
        // above the shared artwork + panel gesture).
        if (fadeMini > 0.001)
          Positioned(
            top: 0,
            right: Spacing.xs,
            height: PlayerOverlay.miniHeight,
            child: IgnorePointer(
              ignoring: t > 0.05,
              child: Opacity(
                opacity: fadeMini,
                child: _MiniControls(playing: playing, scheme: scheme),
              ),
            ),
          ),
      ],
    );
  }
}

/// The collapsed mini row: progress hairline + title/artist (leaves room on the
/// left for the shared artwork thumb and on the right for the mini controls).
class _MiniRow extends ConsumerWidget {
  const _MiniRow({required this.track, required this.playing});

  final Track track;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Duration position =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final Duration? duration = ref.watch(trackDurationProvider).valueOrNull;
    final int totalMs = duration?.inMilliseconds ?? track.durationMs;
    final double progress =
        totalMs > 0 ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          Expanded(
            child: Padding(
              // Left inset clears the shared artwork thumb; right clears controls.
              padding: const EdgeInsets.only(left: 68, right: 96),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (playing) ...<Widget>[
                          const SizedBox(width: Spacing.sm),
                          const EqualizerBars(playing: true, size: 12),
                        ],
                      ],
                    ),
                    Text(
                      track.artistName.artistOrUnknown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniControls extends ConsumerWidget {
  const _MiniControls({required this.playing, required this.scheme});

  final bool playing;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasNext = ref.watch(
      queueControllerProvider.select((QueueState q) => q.hasNext),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          iconSize: 30,
          onPressed: () {
            ref.read(hapticsServiceProvider).light();
            final PlayerService service = ref.read(playerServiceProvider);
            playing ? service.pause() : service.play();
          },
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          iconSize: 30,
          onPressed: hasNext
              ? () {
                  ref.read(hapticsServiceProvider).light();
                  ref.read(queueControllerProvider.notifier).next();
                }
              : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}

/// The expanded Now Playing layout, minus the (floating) artwork: a top bar and
/// the bottom control block (title/artist/chip/progress/transport).
class _FullLayout extends ConsumerWidget {
  const _FullLayout({
    required this.track,
    required this.topInset,
    required this.onCollapse,
    required this.onOpenQueue,
    required this.onExpandLyrics,
  });

  final Track track;
  final double topInset;
  final VoidCallback onCollapse;
  final VoidCallback onOpenQueue;
  final VoidCallback onExpandLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final QueueState queue = ref.watch(queueControllerProvider);

    return Stack(
      children: <Widget>[
        // Top bar — just the collapse chevron now; all actions moved to the
        // secondary toolbar beneath the transport.
        Positioned(
          top: topInset,
          left: Spacing.xs,
          right: Spacing.xs,
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Collapse',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: onCollapse,
              ),
              const Spacer(),
            ],
          ),
        ),

        // Bottom control block.
        Positioned(
          left: Spacing.xl,
          right: Spacing.xl,
          bottom: Spacing.xxl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                track.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                track.artistName.artistOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              _QueueChip(queue: queue),
              const PlaybackChips(),
              const SizedBox(height: Spacing.lg),
              const PlayerProgress(),
              const SizedBox(height: Spacing.sm),
              const PlayerTransport(),
              SecondaryToolbar(
                trackId: track.id,
                onOpenQueue: onOpenQueue,
                onOpenLyrics: onExpandLyrics,
              ),
              // Lyrics peek — hidden entirely when the track has no lyrics, so
              // the block reflows with no dead space.
              LyricsPeek(onExpand: onExpandLyrics),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueChip extends StatelessWidget {
  const _QueueChip({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: Radii.brFull,
      ),
      child: Text(
        '${queue.currentIndex + 1} of ${queue.length}',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// The draggable queue sheet: "Up next" header, the shared reorder/remove list,
/// and a clear-queue action (with confirm).
class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, 0, Spacing.sm, Spacing.sm),
            child: Row(
              children: <Widget>[
                Text('Up next', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
          const Expanded(child: QueueListView()),
        ],
      ),
    );
  }
}
