import 'package:flutter_test/flutter_test.dart';
import 'package:viby/state/scan_triggers.dart';

void main() {
  group('shouldResumeScan', () {
    final DateTime now = DateTime(2026, 7, 9, 12, 0, 0);

    test('runs when there is no prior scan', () {
      expect(shouldResumeScan(null, now), isTrue);
    });

    test('skips when the last scan was recent (< 5 min)', () {
      expect(
        shouldResumeScan(now.subtract(const Duration(minutes: 2)), now),
        isFalse,
      );
    });

    test('runs when the last scan was long ago (> 5 min)', () {
      expect(
        shouldResumeScan(now.subtract(const Duration(minutes: 10)), now),
        isTrue,
      );
    });

    test('is exclusive at exactly the gap boundary', () {
      expect(shouldResumeScan(now.subtract(kResumeScanGap), now), isFalse);
      expect(
        shouldResumeScan(
          now.subtract(kResumeScanGap + const Duration(seconds: 1)),
          now,
        ),
        isTrue,
      );
    });
  });

  group('shouldAnnounceAdded', () {
    test('announces only when tracks were added AND on the Library tab', () {
      expect(shouldAnnounceAdded(3, true), isTrue);
      expect(shouldAnnounceAdded(3, false), isFalse);
      expect(shouldAnnounceAdded(0, true), isFalse);
      expect(shouldAnnounceAdded(0, false), isFalse);
    });
  });
}
