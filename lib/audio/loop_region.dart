/// A–B repeat: an armed region of the current track that loops [aMs]..[bMs].
///
/// Both the audio-layer trigger ([loopShouldSeekBack]) and the UI arming state
/// machine ([nextAbState]) are pure and unit-tested here, so the handler and the
/// controller stay thin.
library;

/// An A–B loop over the current track, in milliseconds. Invariant: [bMs] is
/// always more than [aMs] + [kMinLoopSpanMs] (guaranteed by [nextAbState]).
class LoopRegion {
  const LoopRegion({required this.aMs, required this.bMs});

  final int aMs;
  final int bMs;

  @override
  bool operator ==(Object other) =>
      other is LoopRegion && other.aMs == aMs && other.bMs == bMs;

  @override
  int get hashCode => Object.hash(aMs, bMs);

  @override
  String toString() => 'LoopRegion($aMs..$bMs)';
}

/// The minimum span between A and B for a valid loop, so a mis-tap can't create
/// a machine-gun micro-loop.
const int kMinLoopSpanMs = 1000;

/// Whether playback has reached (or passed) the loop's end and should seek back
/// to A. Pure so the handler's fine sampler is testable without a player.
bool loopShouldSeekBack({required int positionMs, required LoopRegion region}) =>
    positionMs >= region.bMs;

/// The A–B arming state, cycled by [nextAbState] on each user tap.
sealed class AbLoopState {
  const AbLoopState();
}

/// Nothing armed (no chip).
class AbLoopInactive extends AbLoopState {
  const AbLoopInactive();

  @override
  bool operator ==(Object other) => other is AbLoopInactive;

  @override
  int get hashCode => 0;
}

/// A has been set at [aMs]; waiting for the second tap to place B.
class AbLoopPendingA extends AbLoopState {
  const AbLoopPendingA(this.aMs);

  final int aMs;

  @override
  bool operator ==(Object other) =>
      other is AbLoopPendingA && other.aMs == aMs;

  @override
  int get hashCode => aMs.hashCode;
}

/// A and B are both set; the loop is armed on [region].
class AbLoopArmed extends AbLoopState {
  const AbLoopArmed(this.region);

  final LoopRegion region;

  @override
  bool operator ==(Object other) =>
      other is AbLoopArmed && other.region == region;

  @override
  int get hashCode => region.hashCode;
}

/// Advances the A–B state machine for a tap at [positionMs]:
///
/// - inactive → set A at the current position;
/// - pendingA(a) → arm a..position, **iff** position > a + [kMinLoopSpanMs];
///   otherwise the same state is returned (the tap is rejected — the caller
///   plays a denial haptic);
/// - armed → clear.
AbLoopState nextAbState(AbLoopState state, int positionMs) {
  switch (state) {
    case AbLoopInactive():
      return AbLoopPendingA(positionMs);
    case AbLoopPendingA(:final int aMs):
      if (positionMs > aMs + kMinLoopSpanMs) {
        return AbLoopArmed(LoopRegion(aMs: aMs, bMs: positionMs));
      }
      return state; // rejected: B must be more than 1s past A
    case AbLoopArmed():
      return const AbLoopInactive();
  }
}
