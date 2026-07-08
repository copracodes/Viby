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
