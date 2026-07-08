import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/player/player_transition.dart';

void main() {
  group('settleTarget (expand/collapse state machine)', () {
    test('fling up completes to expanded regardless of position', () {
      expect(
        settleTarget(value: 0.1, velocity: 3.0, origin: 0.0),
        SettleTarget.expanded,
      );
    });

    test('fling down completes to collapsed regardless of position', () {
      expect(
        settleTarget(value: 0.9, velocity: -3.0, origin: 1.0),
        SettleTarget.collapsed,
      );
    });

    test('slow release under 40% travel springs back to origin', () {
      // Opened only 30% from collapsed, released slowly → back to collapsed.
      expect(
        settleTarget(value: 0.3, velocity: 0.1, origin: 0.0),
        SettleTarget.collapsed,
      );
      // Collapsed only 30% from expanded (value 0.7) → springs back to expanded.
      expect(
        settleTarget(value: 0.7, velocity: -0.1, origin: 1.0),
        SettleTarget.expanded,
      );
    });

    test('slow release past 40% travel commits the move', () {
      expect(
        settleTarget(value: 0.5, velocity: 0.0, origin: 0.0),
        SettleTarget.expanded,
      );
      expect(
        settleTarget(value: 0.5, velocity: 0.0, origin: 1.0),
        SettleTarget.collapsed,
      );
    });

    test('tap toggles to the opposite end', () {
      expect(targetForTap(0.0), SettleTarget.expanded);
      expect(targetForTap(1.0), SettleTarget.collapsed);
    });
  });

  group('resolveSwipe (artwork skip)', () {
    test('drag left past threshold with a next track skips next', () {
      expect(
        resolveSwipe(
          dragFraction: -0.4,
          velocity: 0,
          hasNext: true,
          hasPrevious: true,
        ),
        SwipeOutcome.skipNext,
      );
    });

    test('drag right past threshold with a previous track skips previous', () {
      expect(
        resolveSwipe(
          dragFraction: 0.4,
          velocity: 0,
          hasNext: true,
          hasPrevious: true,
        ),
        SwipeOutcome.skipPrevious,
      );
    });

    test('short drag under 35% rubber-bands (no skip)', () {
      expect(
        resolveSwipe(
          dragFraction: -0.2,
          velocity: 0,
          hasNext: true,
          hasPrevious: true,
        ),
        SwipeOutcome.none,
      );
    });

    test('a fling commits even below the distance threshold', () {
      expect(
        resolveSwipe(
          dragFraction: -0.1,
          velocity: -1200,
          hasNext: true,
          hasPrevious: true,
        ),
        SwipeOutcome.skipNext,
      );
    });

    test('never skips in an unavailable direction (rubber-band)', () {
      expect(
        resolveSwipe(
          dragFraction: -0.6,
          velocity: -2000,
          hasNext: false,
          hasPrevious: true,
        ),
        SwipeOutcome.none,
      );
      expect(
        resolveSwipe(
          dragFraction: 0.6,
          velocity: 2000,
          hasNext: true,
          hasPrevious: false,
        ),
        SwipeOutcome.none,
      );
    });
  });

  group('canGoPrevious', () {
    test('true when a previous track exists', () {
      expect(
        canGoPrevious(hasPrevious: true, position: Duration.zero),
        isTrue,
      );
    });

    test('true past 3s even with no previous track (restart rule)', () {
      expect(
        canGoPrevious(hasPrevious: false, position: const Duration(seconds: 5)),
        isTrue,
      );
    });

    test('false at the first track within the first 3s', () {
      expect(
        canGoPrevious(hasPrevious: false, position: const Duration(seconds: 1)),
        isFalse,
      );
    });
  });
}
