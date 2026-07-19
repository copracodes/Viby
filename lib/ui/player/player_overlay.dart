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
import 'player_progress_row.dart';
import '../widgets/queue_list.dart';
import 'artwork_stage.dart';
import 'lyrics_peek.dart';
import 'lyrics_view.dart';
import 'now_playing_backdrop.dart';
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

  // Queue sub-state: 0 = full Now Playing, 1 = shrink-to-mini + queue list. Only
  // meaningful while fully expanded. Together with [_c] it forms one continuous
  // mini(0) ↔ full(1) ↔ queue(2) axis (see [_axis]); the pure `settleOverlay`
  // decides where a release lands so all three interpolate without jumps.
  late final AnimationController _queueC;

  double _expandDistance = 1;

  /// Pixel distance the full↔queue drag spans (shorter than the mini↔full
  /// expand, so pulling the queue closed feels snappy). Set in build.
  double _queueDragDistance = 300;

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
    _queueC = AnimationController(
      vsync: this,
      duration: Motion.emphasized,
      value: 0,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    _lyricsC.dispose();
    _queueC.dispose();
    super.dispose();
  }

  /// The combined mini↔full↔queue position in stop units (0..2).
  double get _axis => _c.value + _queueC.value;

  void _expandLyrics() => _lyricsC.animateTo(1,
      duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  void _collapseLyrics() => _lyricsC.animateTo(0,
      duration: Motion.emphasized, curve: Motion.emphasizedAccelerate);

  void _openQueueState() => _queueC.animateTo(1,
      duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  void _closeQueueState() => _queueC.animateTo(0,
      duration: Motion.emphasized, curve: Motion.emphasizedAccelerate);

  void _expand() =>
      _c.animateTo(1, duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  void _collapse() {
    // Reset the sub-states so re-opening the player shows the artwork.
    _lyricsC.value = 0;
    _queueC.value = 0;
    _c.animateTo(0,
        duration: Motion.emphasized, curve: Motion.emphasizedAccelerate);
  }

  /// Animates to a settled [PlayerOverlayState] (used after a drag release).
  void _settleTo(PlayerOverlayState target) {
    switch (target) {
      case PlayerOverlayState.queue:
        _queueC.animateTo(1,
            duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
      case PlayerOverlayState.full:
        _queueC.animateTo(0,
            duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
        if (_c.value < 1) _expand();
      case PlayerOverlayState.mini:
        _collapse();
    }
  }

  // --- Mini ↔ full drag (the panel while no queue is open) ------------------

  /// Which stop the current mini↔full drag *began* at (0 = mini, 1 = full),
  /// captured at drag start. The settle rule keys off where the drag started,
  /// not where it happens to be at release: deriving the origin from `_c.value`
  /// at release flipped it once a full→mini drag crossed the midpoint, so the
  /// "commit to the opposite end" branch sent the panel back *up* to full — the
  /// two-swipes-to-minimize regression.
  double _dragOrigin = 0;

  void _onDragStart(DragStartDetails _) {
    _dragOrigin = _c.value >= 0.5 ? 1 : 0;
  }

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

  // --- Queue drag (from the pill: full↔queue, continuing to mini) ------------

  void _onQueueDragUpdate(DragUpdateDetails d) {
    final double dy = d.delta.dy;
    if (_queueC.value > 0 || dy < 0) {
      // In the queue segment: a shorter drag distance.
      final double next =
          (_queueC.value - dy / _queueDragDistance).clamp(0.0, 1.0);
      final double overflow = _queueC.value - dy / _queueDragDistance - next;
      _queueC.value = next;
      // Dragging further down once the queue is closed carries into collapsing
      // the whole panel (queue → full → mini, no jump).
      if (next == 0 && overflow < 0) {
        _c.value = (_c.value + overflow * _queueDragDistance / _expandDistance)
            .clamp(0.0, 1.0);
      }
    } else {
      _c.value = (_c.value - dy / _expandDistance).clamp(0.0, 1.0);
    }
  }

  void _onQueueDragEnd(DragEndDetails d) {
    final double velocity =
        -(d.primaryVelocity ?? 0) / _queueDragDistance;
    _settleTo(settleOverlay(value: _axis, velocity: velocity, origin: 2));
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
          _queueDragDistance = (h * 0.4).clamp(1.0, double.infinity);

          return AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_c, _lyricsC, _queueC]),
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
    // Lyrics take over as `lv` rises; the queue state as `qv` rises.
    final double lv = Motion.standard.transform(_lyricsC.value.clamp(0.0, 1.0));
    final double qv = Motion.standard.transform(_queueC.value.clamp(0.0, 1.0));

    // Panel rect (screen coords): mini-bar strip → full screen.
    final double panelTop = _lerp(collapsedTop, 0, ct);
    final double panelBottom = _lerp(navBar, 0, ct); // inset from bottom

    // Shared-element artwork rect (screen coords), interpolated across ALL three
    // states: mini thumb → full hero → pill thumb. Driving the artwork's size +
    // position off `qv` (not just its opacity) is what makes the queue→full drag
    // read as the pill *growing* back into Now Playing rather than a cross-fade.
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
    // Where the pill's thumbnail sits (matches _PlayerPill's card margin/padding).
    const double pillArt = 44;
    final Rect pillRect = Rect.fromLTWH(
      2 * Spacing.md,
      pad.top + Spacing.sm + Spacing.xs,
      pillArt,
      pillArt,
    );
    final Rect artScreen =
        Rect.lerp(Rect.lerp(miniRect, fullRect, ct)!, pillRect, qv)!;
    final double artRadius =
        _lerp(_lerp(Radii.sm, Radii.lg, ct), Radii.sm, qv);

    final double fadeMini = (1 - t / 0.28).clamp(0.0, 1.0);
    final double fadeFull =
        ((t - 0.35) / 0.65).clamp(0.0, 1.0) * (1 - lv) * (1 - qv);
    // The artwork stays visible through the queue morph (it MOVES, doesn't fade);
    // only lyrics take it away.
    final double artFade = 1 - lv;
    // Swipe-to-skip + drag-to-collapse are live only at rest in full Now Playing.
    final bool artInteractive = t > 0.98 && qv < 0.02 && lv < 0.02;
    final bool playing = ref.watch(playingProvider).valueOrNull ?? false;

    return Stack(
      children: <Widget>[
        // Backdrop — never hit-tests; opacity follows the transition. Stays up
        // in the queue state so the dynamic theme keeps driving it.
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
              playing: playing,
              topInset: pad.top,
              onCollapse: _collapse,
              onOpenQueue: _openQueueState,
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

        // The queue state: a top player pill + the expanded queue list,
        // cross-faded above Now Playing as `qv` rises.
        if (qv > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: qv < 0.5,
              child: Opacity(
                opacity: qv,
                child: _QueueOverlayState(
                  track: track,
                  playing: playing,
                  topInset: pad.top,
                  bottomInset: pad.bottom,
                  onCollapseToFull: _closeQueueState,
                  onPillDragUpdate: _onQueueDragUpdate,
                  onPillDragEnd: _onQueueDragEnd,
                  onClear: () => _confirmClear(context),
                ),
              ),
            ),
          ),

        // The ONE shared-element artwork, above every layer so it reads as a
        // single element that grows/shrinks between the mini thumb, the full
        // hero and the pill thumb. Interactive only at rest in full Now Playing:
        // horizontal = swipe-to-skip (ArtworkStage), vertical = drag-to-collapse.
        if (artFade > 0.001)
          Positioned.fromRect(
            rect: artScreen,
            child: IgnorePointer(
              ignoring: !artInteractive,
              child: Opacity(
                opacity: artFade,
                // The vertical-drag callbacks are attached unconditionally, NOT
                // gated on `artInteractive`. A collapse drag begun on the artwork
                // pushes `t` below the 0.98 interactive threshold within a few
                // pixels; nulling the callbacks there would dispose the active
                // drag recognizer mid-gesture and strand the panel near full —
                // the other half of the two-swipe regression. The IgnorePointer
                // above still blocks a *new* drag from starting here once we're
                // no longer at rest; an in-flight one keeps its pointer.
                child: GestureDetector(
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: ArtworkStage(
                    size: artScreen.width,
                    borderRadius: artRadius,
                    enabled: artInteractive,
                    playing: playing,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool ok = await showDialog<bool>(
          context: context,
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
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// The panel's stacked contents: the mini row (fades out) and the full layout
/// (fades in). The shared-element artwork is a sibling layer above the panel
/// (see `_buildFrame`), so it can span all three states without being clipped.
class _PanelContents extends StatelessWidget {
  const _PanelContents({
    required this.t,
    required this.track,
    required this.fadeMini,
    required this.fadeFull,
    required this.playing,
    required this.topInset,
    required this.onCollapse,
    required this.onOpenQueue,
    required this.onExpandLyrics,
  });

  final double t;
  final Track track;
  final double fadeMini;
  final double fadeFull;
  final bool playing;
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
              // Scrubber flanked by the quiet corner actions (Love/A-B · Queue/More).
              ProgressWithActions(trackId: track.id, onOpenQueue: onOpenQueue),
              const SizedBox(height: Spacing.sm),
              const PlayerTransport(),
              // Lyrics peek — hidden entirely when the track has no lyrics, so
              // the block reflows with no dead space (and is the lyrics entry).
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

/// Nominal height of a queue row (a two-line [ListTile]) — used to compute the
/// jump-to-current scroll offset (see [queueJumpOffset]).
const double _kQueueRowExtent = 64;

/// The queue "third state": a compact player pill docked at the top (drag it
/// down / tap it to return to Now Playing) and the expanded reorder/remove queue
/// list below, headered "Queue" with jump-to-current and clear-with-confirm.
/// Auto-scrolls to the current track on open.
class _QueueOverlayState extends ConsumerStatefulWidget {
  const _QueueOverlayState({
    required this.track,
    required this.playing,
    required this.topInset,
    required this.bottomInset,
    required this.onCollapseToFull,
    required this.onPillDragUpdate,
    required this.onPillDragEnd,
    required this.onClear,
  });

  final Track track;
  final bool playing;
  final double topInset;
  final double bottomInset;
  final VoidCallback onCollapseToFull;
  final ValueChanged<DragUpdateDetails> onPillDragUpdate;
  final ValueChanged<DragEndDetails> onPillDragEnd;
  final VoidCallback onClear;

  @override
  ConsumerState<_QueueOverlayState> createState() => _QueueOverlayStateState();
}

class _QueueOverlayStateState extends ConsumerState<_QueueOverlayState> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll to the current track once the list is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToCurrent() {
    if (!_scroll.hasClients) return;
    final QueueState queue = ref.read(queueControllerProvider);
    final double offset = queueJumpOffset(
      index: queue.currentIndex,
      itemExtent: _kQueueRowExtent,
      viewportHeight: _scroll.position.viewportDimension,
      itemCount: queue.length,
    );
    _scroll.animateTo(offset,
        duration: Motion.emphasized, curve: Motion.emphasizedDecelerate);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      // Transparent so the queue state shares the ONE themed backdrop (behind
      // the whole overlay) — the blurred artwork + scheme scrim morph on a track
      // change exactly as they do in full Now Playing. An opaque surface here
      // would hide that per-track tint (only the accent would appear to change).
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
        child: Column(
          children: <Widget>[
            // The floating player pill + the grabber below it form one draggable
            // header (drag down / tap → back to Now Playing; drag further →
            // collapse). The grabber marks where the sheet content begins.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onCollapseToFull,
              onVerticalDragUpdate: widget.onPillDragUpdate,
              onVerticalDragEnd: widget.onPillDragEnd,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PlayerPill(track: widget.track, playing: widget.playing),
                  _Grabber(scheme: scheme),
                ],
              ),
            ),
            // "Queue" header + jump-to-current + clear.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.xs, Spacing.sm, Spacing.xs),
              child: Row(
                children: <Widget>[
                  Text('Queue', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Jump to current',
                    icon: const Icon(Icons.my_location),
                    onPressed: _jumpToCurrent,
                  ),
                  TextButton.icon(
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(child: QueueListView(scrollController: _scroll)),
          ],
        ),
      ),
    );
  }
}

/// The drag-handle "grabber" — sits directly below the pill, marking where the
/// draggable sheet content begins.
class _Grabber extends StatelessWidget {
  const _Grabber({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: Radii.brFull,
      ),
    );
  }
}

/// The compact floating player pill docked atop the queue state: artwork thumb,
/// title + artist, play/pause and next, on a translucent card so it reads as a
/// pill over the (now visible) themed backdrop.
class _PlayerPill extends ConsumerWidget {
  const _PlayerPill({required this.track, required this.playing});

  final Track track;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasNext = ref.watch(
      queueControllerProvider.select((QueueState q) => q.hasNext),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: Radii.brLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.xs, Spacing.xs, Spacing.sm),
            child: Row(
            children: <Widget>[
              // The shared-element artwork docks here (it's a sibling layer
              // above the queue state), so the pill reserves its footprint.
              const SizedBox(width: 44, height: 44),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
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
          ),
        ),
      ],
      ),
    );
  }
}
