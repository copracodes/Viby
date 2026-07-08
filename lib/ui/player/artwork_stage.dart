import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/track.dart';
import '../../state/haptics_providers.dart';
import '../../state/queue_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import 'player_transition.dart';

/// Fixed decode resolution (logical px) for the shared-element artwork. Chosen
/// to look crisp at full-screen while giving one stable cache key across the
/// whole mini↔full size range, so a drag never re-decodes.
const double _sharedArtDecodeSize = 720;

/// The Now Playing artwork: a rounded card that scales subtly with play/pause
/// state and — when [enabled] (fully expanded) — can be swiped horizontally to
/// skip tracks. The neighbour's art peeks in from the edge as you drag; the
/// queue is only touched on *commit* (never mid-drag), and a swipe toward an
/// unavailable edge rubber-bands.
class ArtworkStage extends ConsumerStatefulWidget {
  const ArtworkStage({
    super.key,
    required this.size,
    required this.borderRadius,
    required this.enabled,
    required this.playing,
  });

  final double size;
  final double borderRadius;
  final bool enabled;
  final bool playing;

  @override
  ConsumerState<ArtworkStage> createState() => _ArtworkStageState();
}

class _ArtworkStageState extends ConsumerState<ArtworkStage>
    with SingleTickerProviderStateMixin {
  // Eager (not lazy `late final`): the stage can be disposed without ever
  // swiping — creating the Ticker lazily inside dispose() would be illegal.
  late final AnimationController _settle;
  Animation<double>? _settleAnim;

  /// Live horizontal drag offset in px (negative = dragging left → next).
  double _dx = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: Motion.base);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _animateDxTo(double target, {VoidCallback? onArrived}) {
    _settleAnim = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _settle, curve: Motion.emphasizedDecelerate),
    )..addListener(() {
        setState(() => _dx = _settleAnim!.value);
      });
    _settle
      ..reset()
      ..forward().whenComplete(() {
        if (onArrived != null) onArrived();
      });
  }

  void _onDragUpdate(DragUpdateDetails d, QueueState queue) {
    final double raw = _dx + d.delta.dx;
    // Rubber-band toward an unavailable edge.
    final bool towardNext = raw < 0;
    final bool available = towardNext ? queue.hasNext : queue.hasPrevious;
    setState(() => _dx = available ? raw : raw * 0.2);
  }

  void _onDragEnd(DragEndDetails d, QueueState queue) {
    final double velocity = d.primaryVelocity ?? 0;
    final SwipeOutcome outcome = resolveSwipe(
      dragFraction: _dx / widget.size,
      velocity: velocity,
      hasNext: queue.hasNext,
      hasPrevious: queue.hasPrevious,
    );
    final QueueController controller =
        ref.read(queueControllerProvider.notifier);
    switch (outcome) {
      case SwipeOutcome.skipNext:
        ref.read(hapticsServiceProvider).light();
        _animateDxTo(-widget.size, onArrived: () {
          controller.next();
          setState(() => _dx = 0); // new current rebuilds centred
        });
      case SwipeOutcome.skipPrevious:
        ref.read(hapticsServiceProvider).light();
        _animateDxTo(widget.size, onArrived: () {
          controller.previous();
          setState(() => _dx = 0);
        });
      case SwipeOutcome.none:
        _animateDxTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final QueueState queue = ref.watch(queueControllerProvider);
    final int index = queue.currentIndex;
    final Track? current = queue.currentTrack;
    final Track? next =
        index + 1 < queue.length ? queue.tracks[index + 1] : null;
    final Track? previous = index > 0 ? queue.tracks[index - 1] : null;

    final double size = widget.size;
    const double gap = Spacing.md;

    Widget art(Track? track, double dx) => Transform.translate(
          offset: Offset(dx, 0),
          child: SizedBox(
            width: size,
            height: size,
            child: track == null
                ? const SizedBox.shrink()
                : AlbumArt.expand(
                    artworkKey: track.artworkKey,
                    borderRadius: widget.borderRadius,
                    // Decode once at a fixed resolution (not the live animated
                    // size), so growing the art during a mini→full drag reuses
                    // one cached bitmap — no per-frame re-decode / shimmer flash.
                    decodeSize: _sharedArtDecodeSize,
                  ),
          ),
        );

    final Widget stack = SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: <Widget>[
              // Neighbours peek from the edges as the current art slides.
              if (previous != null) art(previous, _dx - size - gap),
              if (next != null) art(next, _dx + size + gap),
              art(current, _dx),
            ],
          ),
        ),
      ),
    );

    final Widget scaled = AnimatedScale(
      scale: widget.playing ? 1.0 : 0.94,
      duration: Motion.emphasized,
      curve: Motion.standard,
      child: stack,
    );

    if (!widget.enabled) return scaled;

    return GestureDetector(
      onHorizontalDragUpdate: (DragUpdateDetails d) => _onDragUpdate(d, queue),
      onHorizontalDragEnd: (DragEndDetails d) => _onDragEnd(d, queue),
      child: scaled,
    );
  }
}
