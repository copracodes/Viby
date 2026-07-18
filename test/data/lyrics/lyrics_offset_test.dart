import 'package:flutter_test/flutter_test.dart';
import 'package:viby/data/lyrics/lyrics.dart';
import 'package:viby/data/lyrics/lyrics_offset.dart';
import 'package:viby/data/lyrics/lyrics_sync.dart';

void main() {
  group('offsetAdjustedStartMs (tap-to-seek target)', () {
    test('adds the offset to the line start', () {
      expect(offsetAdjustedStartMs(1000, 500), 1500);
      expect(offsetAdjustedStartMs(1000, -400), 600);
    });

    test('clamps at 0', () {
      expect(offsetAdjustedStartMs(200, -1000), 0);
    });

    test('reset (offset 0) is the identity', () {
      expect(offsetAdjustedStartMs(4321, 0), 4321);
    });
  });

  group('offsetAdjustedQueryMs (highlight search)', () {
    test('is the inverse shift of the line start', () {
      // A line at 1000 with +500 offset lights up at position 1500.
      const int lineStart = 1000;
      const int offset = 500;
      const int fireAt = 1500;
      // Just before → not active.
      expect(offsetAdjustedQueryMs(fireAt - 1, offset), lessThan(lineStart));
      // Exactly at → active.
      expect(
        offsetAdjustedQueryMs(fireAt, offset),
        greaterThanOrEqualTo(lineStart),
      );
    });

    test('reset (offset 0) is the identity', () {
      expect(offsetAdjustedQueryMs(4321, 0), 4321);
    });
  });

  group('offset applied through activeLineIndexFor', () {
    final List<LyricLine> lines = <LyricLine>[
      const LyricLine(startMs: 0, text: 'a'),
      const LyricLine(startMs: 2000, text: 'b'),
      const LyricLine(startMs: 4000, text: 'c'),
    ];

    int activeAt(int posMs, int offsetMs) =>
        activeLineIndexFor(lines, offsetAdjustedQueryMs(posMs, offsetMs));

    test('a positive offset delays the highlight', () {
      // Without offset, position 2100 is on line "b" (index 1).
      expect(activeAt(2100, 0), 1);
      // With +500 offset, "b" (at 2000) fires at 2500, so 2100 is still "a".
      expect(activeAt(2100, 500), 0);
      expect(activeAt(2500, 500), 1);
    });

    test('a negative offset advances the highlight', () {
      // With −500 offset, "b" fires at 1500.
      expect(activeAt(1600, -500), 1);
    });
  });
}
