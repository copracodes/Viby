import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/loop_region.dart';

void main() {
  group('loopShouldSeekBack (trigger)', () {
    const LoopRegion region = LoopRegion(aMs: 2000, bMs: 5000);

    test('false before B, true at/after B', () {
      expect(loopShouldSeekBack(positionMs: 1999, region: region), isFalse);
      expect(loopShouldSeekBack(positionMs: 4999, region: region), isFalse);
      expect(loopShouldSeekBack(positionMs: 5000, region: region), isTrue);
      expect(loopShouldSeekBack(positionMs: 8000, region: region), isTrue);
    });
  });

  group('nextAbState (arming state machine)', () {
    test('set A → set B → clear', () {
      // Tap 1 at 2.0s: A is pending.
      AbLoopState s = nextAbState(const AbLoopInactive(), 2000);
      expect(s, const AbLoopPendingA(2000));

      // Tap 2 at 6.0s (> A + 1s): armed.
      s = nextAbState(s, 6000);
      expect(s, const AbLoopArmed(LoopRegion(aMs: 2000, bMs: 6000)));

      // Tap 3: cleared.
      s = nextAbState(s, 9000);
      expect(s, const AbLoopInactive());
    });

    test('B ≤ A + 1s is rejected (state unchanged)', () {
      const AbLoopState pending = AbLoopPendingA(2000);
      // Exactly 1s later — not strictly more than the minimum span → rejected.
      expect(nextAbState(pending, 3000), pending);
      // Earlier than A → rejected.
      expect(nextAbState(pending, 1500), pending);
      // Just over 1s → accepted.
      expect(
        nextAbState(pending, 3001),
        const AbLoopArmed(LoopRegion(aMs: 2000, bMs: 3001)),
      );
    });

    test('kMinLoopSpanMs guards the span', () {
      expect(kMinLoopSpanMs, 1000);
      final AbLoopState armed =
          nextAbState(const AbLoopPendingA(0), kMinLoopSpanMs + 1);
      expect(armed, isA<AbLoopArmed>());
    });
  });
}
