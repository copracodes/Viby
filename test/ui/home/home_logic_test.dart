import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/home/home_logic.dart';

void main() {
  group('shouldShowTopTracks', () {
    test('hidden until 5 distinct plays', () {
      expect(shouldShowTopTracks(0), isFalse);
      expect(shouldShowTopTracks(4), isFalse);
      expect(shouldShowTopTracks(5), isTrue);
      expect(shouldShowTopTracks(20), isTrue);
    });
  });

  group('greetingForHour', () {
    test('buckets the day', () {
      expect(greetingForHour(5), 'Good morning');
      expect(greetingForHour(8), 'Good morning');
      expect(greetingForHour(11), 'Good morning');
      expect(greetingForHour(12), 'Good afternoon');
      expect(greetingForHour(16), 'Good afternoon');
      expect(greetingForHour(17), 'Good evening');
      expect(greetingForHour(21), 'Good evening');
      expect(greetingForHour(22), 'Late night');
      expect(greetingForHour(0), 'Late night');
      expect(greetingForHour(4), 'Late night');
    });
  });
}
