import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/sleep_timer.dart';
import 'package:viby/ui/player/sleep_timer_sheet.dart' show sleepTimerLabel;

void main() {
  final DateTime now = DateTime(2026, 7, 13, 22, 30);

  group('SleepAfter (wall clock)', () {
    test('counts down to its deadline', () {
      expect(
        sleepRemaining(
          mode: const SleepAfter(Duration(minutes: 30)),
          now: now,
          deadline: now.add(const Duration(minutes: 12)),
        ),
        const Duration(minutes: 12),
      );
    });

    test('an absolute deadline stays correct across a starved background gap',
        () {
      // The app was backgrounded for 20 minutes and ticked nothing; the deadline
      // is absolute, so the answer is still right (and it fires immediately).
      final DateTime deadline = now.add(const Duration(minutes: 5));
      final DateTime muchLater = now.add(const Duration(minutes: 25));
      final Duration? left = sleepRemaining(
        mode: const SleepAfter(Duration(minutes: 5)),
        now: muchLater,
        deadline: deadline,
      );
      expect(left, Duration.zero);
      expect(sleepShouldStop(left), isTrue);
    });

    test('never reports a negative remaining', () {
      expect(
        sleepRemaining(
          mode: const SleepAfter(Duration(minutes: 1)),
          now: now,
          deadline: now.subtract(const Duration(minutes: 3)),
        ),
        Duration.zero,
      );
    });
  });

  group('SleepEndOfTrack', () {
    test('counts down what is left of the current track', () {
      expect(
        sleepRemaining(
          mode: const SleepEndOfTrack(),
          now: now,
          position: const Duration(minutes: 3, seconds: 10),
          trackDuration: const Duration(minutes: 4),
        ),
        const Duration(seconds: 50),
      );
    });

    test('a seek backwards pushes the stop back out (it follows position)', () {
      expect(
        sleepRemaining(
          mode: const SleepEndOfTrack(),
          now: now,
          position: const Duration(seconds: 30),
          trackDuration: const Duration(minutes: 4),
        ),
        const Duration(minutes: 3, seconds: 30),
      );
    });

    test('waits (no countdown) until the duration is known', () {
      expect(
        sleepRemaining(
          mode: const SleepEndOfTrack(),
          now: now,
          position: Duration.zero,
        ),
        isNull,
      );
    });

    test('fires at the end of the track', () {
      final Duration? left = sleepRemaining(
        mode: const SleepEndOfTrack(),
        now: now,
        position: const Duration(minutes: 4),
        trackDuration: const Duration(minutes: 4),
      );
      expect(sleepShouldStop(left), isTrue);
    });
  });

  group('SleepEndOfQueue', () {
    test('does not count down while a next track exists', () {
      final Duration? left = sleepRemaining(
        mode: const SleepEndOfQueue(),
        now: now,
        position: const Duration(minutes: 3, seconds: 55),
        trackDuration: const Duration(minutes: 4),
        hasNext: true,
      );
      expect(left, isNull);
      expect(sleepShouldStop(left), isFalse);
      // ...and crucially does not fade out the second-to-last track.
      expect(sleepFadeLevel(left), 1.0);
    });

    test('counts down the last track once nothing follows it', () {
      expect(
        sleepRemaining(
          mode: const SleepEndOfQueue(),
          now: now,
          position: const Duration(minutes: 3, seconds: 55),
          trackDuration: const Duration(minutes: 4),
        ),
        const Duration(seconds: 5),
      );
    });
  });

  group('the fade envelope', () {
    test('is full until the last 10 seconds', () {
      expect(sleepFadeLevel(const Duration(minutes: 5)), 1.0);
      expect(sleepFadeLevel(const Duration(seconds: 11)), 1.0);
      expect(sleepFadeLevel(kSleepFadeOut), 1.0);
    });

    test('ramps linearly to silence over the window', () {
      expect(sleepFadeLevel(const Duration(seconds: 5)), closeTo(0.5, 1e-9));
      expect(sleepFadeLevel(const Duration(seconds: 1)), closeTo(0.1, 1e-9));
      expect(sleepFadeLevel(Duration.zero), 0.0);
    });

    test('is silent (not negative) past the deadline', () {
      expect(sleepFadeLevel(const Duration(seconds: -5)), 0.0);
    });

    test('leaves the volume alone when nothing is armed', () {
      expect(sleepFadeLevel(null), 1.0);
    });
  });

  group('state + label', () {
    test('isFading only inside the window', () {
      expect(
        const SleepTimerState(
          mode: SleepEndOfTrack(),
          remaining: Duration(seconds: 30),
        ).isFading,
        isFalse,
      );
      expect(
        const SleepTimerState(
          mode: SleepEndOfTrack(),
          remaining: Duration(seconds: 4),
        ).isFading,
        isTrue,
      );
    });

    test('the chip shows a clock while counting, a mode name before that', () {
      expect(
        sleepTimerLabel(
          const SleepTimerState(
            mode: SleepAfter(Duration(minutes: 30)),
            remaining: Duration(minutes: 12, seconds: 5),
          ),
        ),
        '12:05',
      );
      expect(
        sleepTimerLabel(
          const SleepTimerState(
            mode: SleepAfter(Duration(minutes: 30)),
            remaining: Duration(seconds: 9),
          ),
        ),
        '0:09',
      );
      expect(
        sleepTimerLabel(const SleepTimerState(mode: SleepEndOfQueue())),
        'End of queue',
      );
      expect(sleepTimerLabel(const SleepTimerState.idle()), '');
    });
  });
}
