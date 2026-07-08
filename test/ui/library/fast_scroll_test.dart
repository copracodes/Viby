import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/library/fast_scroll.dart';

void main() {
  group('bucketLetter', () {
    test('uppercases the first Latin letter', () {
      expect(bucketLetter('Apple'), 'A');
      expect(bucketLetter('apple'), 'A');
      expect(bucketLetter('zoo'), 'Z');
    });

    test('ignores leading whitespace', () {
      expect(bucketLetter('   beta'), 'B');
    });

    test('digits, symbols, empty and non-Latin bucket under #', () {
      expect(bucketLetter('3 Doors Down'), '#');
      expect(bucketLetter('!!!'), '#');
      expect(bucketLetter(''), '#');
      expect(bucketLetter('   '), '#');
      expect(bucketLetter('بحر'), '#');
    });
  });

  group('indexForFraction', () {
    test('maps 0..1 across the list, clamped', () {
      expect(indexForFraction(10, 0.0), 0);
      expect(indexForFraction(10, 1.0), 9);
      expect(indexForFraction(10, 0.5), 5);
      expect(indexForFraction(10, -0.3), 0);
      expect(indexForFraction(10, 2.0), 9);
    });

    test('empty list → 0', () {
      expect(indexForFraction(0, 0.5), 0);
    });
  });

  group('letterForFraction', () {
    test('reads the bucket at the fractional index', () {
      final List<String> names = <String>['Apple', 'Beta', 'Cat', 'Zoo'];
      expect(letterForFraction(names, 0.0), 'A');
      expect(letterForFraction(names, 0.99), 'Z');
    });

    test('empty list → #', () {
      expect(letterForFraction(const <String>[], 0.4), '#');
    });
  });
}
