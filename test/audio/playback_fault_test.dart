import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/playback_fault.dart';
import 'package:viby/data/db/tables.dart' show RepeatMode;

void main() {
  group('decidePlaybackFault', () {
    test('skips to the next track when one is available', () {
      final FaultDecision d = decidePlaybackFault(
        failedIndex: 1,
        queueLength: 5,
        consecutiveFailures: 1,
        repeat: RepeatMode.off,
      );
      expect(d.outcome, FaultOutcome.skip);
      expect(d.skipIndex, 2);
    });

    test('stops at the end of the queue with repeat off', () {
      final FaultDecision d = decidePlaybackFault(
        failedIndex: 4,
        queueLength: 5,
        consecutiveFailures: 1,
        repeat: RepeatMode.off,
      );
      expect(d.outcome, FaultOutcome.stopEnd);
    });

    test('wraps to the top at the end under repeat-all', () {
      final FaultDecision d = decidePlaybackFault(
        failedIndex: 4,
        queueLength: 5,
        consecutiveFailures: 1,
        repeat: RepeatMode.all,
      );
      expect(d.outcome, FaultOutcome.skip);
      expect(d.skipIndex, 0);
    });

    test('stops (all failed) once every track has failed in a row', () {
      final FaultDecision d = decidePlaybackFault(
        failedIndex: 2,
        queueLength: 5,
        consecutiveFailures: 5,
        repeat: RepeatMode.all, // even repeat-all must give up
      );
      expect(d.outcome, FaultOutcome.stopAllFailed);
    });

    test('empty queue stops', () {
      final FaultDecision d = decidePlaybackFault(
        failedIndex: 0,
        queueLength: 0,
        consecutiveFailures: 0,
        repeat: RepeatMode.off,
      );
      expect(d.outcome, FaultOutcome.stopEnd);
    });
  });
}
