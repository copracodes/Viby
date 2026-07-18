/// Pure decision logic for the Now Playing interactive transition and the
/// artwork swipe-to-skip gesture. Kept free of Flutter widgets so the state
/// machine can be unit-tested exhaustively (the "feel" lives in the widgets;
/// the *rules* live here).
library;

/// Where the expand/collapse transition should settle on release.
enum SettleTarget {
  collapsed,
  expanded;

  double get value => this == SettleTarget.expanded ? 1.0 : 0.0;
}

/// Decides where the mini↔full transition settles when the drag is released.
///
/// [value] is the current expansion (0 = mini, 1 = full). [velocity] is its
/// rate of change per second (positive = opening). [origin] is where the drag
/// began (0 or 1). Rules, in order:
///  1. A fling (|velocity| over [flingVelocity]) always completes in its
///     direction — "fling completes".
///  2. Otherwise the drag must travel at least [commitFraction] (40%) away from
///     [origin] to commit; a slower/shorter release springs back to [origin].
SettleTarget settleTarget({
  required double value,
  required double velocity,
  required double origin,
  double flingVelocity = 1.2,
  double commitFraction = 0.4,
}) {
  if (velocity.abs() > flingVelocity) {
    return velocity > 0 ? SettleTarget.expanded : SettleTarget.collapsed;
  }
  final double travelled = (value - origin).abs();
  if (travelled < commitFraction) {
    return origin >= 0.5 ? SettleTarget.expanded : SettleTarget.collapsed;
  }
  // Committed the move: settle to the opposite end from the origin.
  return origin >= 0.5 ? SettleTarget.collapsed : SettleTarget.expanded;
}

/// A tap toggles the transition to the opposite end (mini → full, full → mini),
/// taking the animated path. Pure so the "tap" branch of the controller is
/// testable alongside the drag branch.
SettleTarget targetForTap(double value) =>
    value >= 0.5 ? SettleTarget.collapsed : SettleTarget.expanded;

/// The three resting states of the player overlay, laid out on one continuous
/// axis driven by a single controller (value 0 = [mini], 1 = [full], 2 =
/// [queue]). The queue state is the "shrink-to-mini + queue list" layout; it's
/// entered by tapping Queue and left by dragging down / back / the pill.
enum PlayerOverlayState {
  mini,
  full,
  queue;

  /// The controller value this state rests at.
  double get value => index.toDouble();
}

/// Settles the overlay onto one of the three [PlayerOverlayState]s when a drag is
/// released. Generalises the two-state [settleTarget] rule to a multi-stop axis
/// so mini ↔ full ↔ queue all interpolate on one controller:
///
/// - a fling (|velocity| over [flingVelocity]) carries one stop further in its
///   direction than where the finger let go — "fling completes";
/// - otherwise the release snaps to the nearest stop, **unless** it barely
///   moved from [origin] (under [commitFraction] of a stop), in which case it
///   springs back to the origin stop.
///
/// [value] and [origin] are in stop units (0..2). [velocity] is stop-units/sec,
/// positive = toward queue (dragging up). This makes a single long drag down
/// from queue able to pass through full and settle at mini (and every mid-flight
/// interruption resolves to whichever stop the finger is nearest).
PlayerOverlayState settleOverlay({
  required double value,
  required double velocity,
  required double origin,
  double flingVelocity = 1.2,
  double commitFraction = 0.4,
}) {
  final bool fling = velocity.abs() > flingVelocity;
  if (!fling && (value - origin).abs() < commitFraction) {
    return _stopAt(origin.round());
  }
  final double resolved = fling ? value + (velocity > 0 ? 0.5 : -0.5) : value;
  return _stopAt(resolved.round());
}

PlayerOverlayState _stopAt(int stop) =>
    PlayerOverlayState.values[stop.clamp(0, PlayerOverlayState.values.length - 1)];

/// The scroll offset that brings the current-track row to [alignment] of the
/// viewport in the expanded queue list (0 = top, 0.5 = centre) — the
/// "jump-to-current" affordance and the auto-scroll-on-open. Pure so the target
/// is testable without a live ScrollController. Clamped to the scrollable range.
double queueJumpOffset({
  required int index,
  required double itemExtent,
  required double viewportHeight,
  required int itemCount,
  double alignment = 0.35,
}) {
  if (index <= 0) return 0;
  final double raw = index * itemExtent - alignment * viewportHeight;
  final double maxExtent =
      (itemCount * itemExtent - viewportHeight).clamp(0, double.infinity);
  return raw.clamp(0.0, maxExtent);
}

/// The outcome of an artwork horizontal swipe.
enum SwipeOutcome { none, skipNext, skipPrevious }

/// Resolves an artwork swipe on release.
///
/// [dragFraction] is the horizontal drag as a fraction of width, signed:
/// negative = dragged left (reveals the *next* track), positive = dragged right
/// (reveals the *previous*). [velocity] is px/s (same sign convention). A swipe
/// commits when it passes [commitFraction] (35%) OR is a fling past
/// [flingVelocity] — but only in a direction that actually exists
/// ([hasNext]/[hasPrevious]); otherwise it rubber-bands back ([SwipeOutcome.none]).
SwipeOutcome resolveSwipe({
  required double dragFraction,
  required double velocity,
  required bool hasNext,
  required bool hasPrevious,
  double commitFraction = 0.35,
  double flingVelocity = 600,
}) {
  final bool fling = velocity.abs() > flingVelocity;
  // Direction: prefer the fling's sign, else the drag's sign.
  final double direction = fling ? velocity : dragFraction;
  if (direction == 0) return SwipeOutcome.none;

  final bool towardNext = direction < 0; // left
  final bool committed = dragFraction.abs() >= commitFraction || fling;
  if (!committed) return SwipeOutcome.none;

  if (towardNext) {
    return hasNext ? SwipeOutcome.skipNext : SwipeOutcome.none;
  }
  return hasPrevious ? SwipeOutcome.skipPrevious : SwipeOutcome.none;
}

/// Whether the Previous control does anything: either there's a prior track, or
/// we're far enough into the current one that a press restarts it (the 3s rule
/// from Step 1.4). Pure so the transport's disabled state is testable.
bool canGoPrevious({
  required bool hasPrevious,
  required Duration position,
  Duration restartAfter = const Duration(seconds: 3),
}) {
  return hasPrevious || position > restartAfter;
}
