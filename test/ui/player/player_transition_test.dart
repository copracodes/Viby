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

  group('settleOverlay (three-state mini↔full↔queue axis)', () {
    test('from full, a committed drag up settles on queue', () {
      expect(
        settleOverlay(value: 1.5, velocity: 0, origin: 1),
        PlayerOverlayState.queue,
      );
    });

    test('from full, a tiny drag springs back to full', () {
      expect(
        settleOverlay(value: 1.2, velocity: 0, origin: 1),
        PlayerOverlayState.full,
      );
    });

    test('a fling up from full completes to queue', () {
      expect(
        settleOverlay(value: 1.1, velocity: 3.0, origin: 1),
        PlayerOverlayState.queue,
      );
    });

    test('from queue, a short drag down returns to full', () {
      expect(
        settleOverlay(value: 1.4, velocity: 0, origin: 2),
        PlayerOverlayState.full,
      );
    });

    test('from queue, a long drag down passes full and collapses to mini', () {
      expect(
        settleOverlay(value: 0.3, velocity: 0, origin: 2),
        PlayerOverlayState.mini,
      );
    });

    test('from mini, a committed drag up settles on full', () {
      expect(
        settleOverlay(value: 0.6, velocity: 0, origin: 0),
        PlayerOverlayState.full,
      );
    });

    test('mid-flight interruption resolves to the nearest stop', () {
      // Grabbed while animating full→queue and let go near queue.
      expect(
        settleOverlay(value: 1.7, velocity: 0, origin: 1),
        PlayerOverlayState.queue,
      );
      // Grabbed near full.
      expect(
        settleOverlay(value: 1.3, velocity: 0, origin: 2),
        PlayerOverlayState.full,
      );
    });

    test('a fling never overshoots past the ends', () {
      expect(
        settleOverlay(value: 2.0, velocity: 5.0, origin: 2),
        PlayerOverlayState.queue,
      );
      expect(
        settleOverlay(value: 0.0, velocity: -5.0, origin: 0),
        PlayerOverlayState.mini,
      );
    });

    test('PlayerOverlayState.value maps onto the controller axis', () {
      expect(PlayerOverlayState.mini.value, 0.0);
      expect(PlayerOverlayState.full.value, 1.0);
      expect(PlayerOverlayState.queue.value, 2.0);
    });
  });

  group('queueJumpOffset (jump-to-current)', () {
    test('index 0 sits at the top', () {
      expect(
        queueJumpOffset(
          index: 0,
          itemExtent: 64,
          viewportHeight: 600,
          itemCount: 50,
        ),
        0,
      );
    });

    test('a mid-list row lands at the alignment fraction', () {
      // 20 * 64 = 1280; minus 0.35 * 600 = 210 → 1070.
      expect(
        queueJumpOffset(
          index: 20,
          itemExtent: 64,
          viewportHeight: 600,
          itemCount: 50,
        ),
        1070,
      );
    });

    test('clamps to the maximum scroll extent near the end', () {
      // 50 items * 64 = 3200; max = 3200 - 600 = 2600.
      expect(
        queueJumpOffset(
          index: 49,
          itemExtent: 64,
          viewportHeight: 600,
          itemCount: 50,
        ),
        2600,
      );
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
