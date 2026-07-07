import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/display_names.dart';

void main() {
  group('DisplayNames', () {
    test('MediaStore <unknown> becomes a friendly label (case-insensitive)', () {
      expect('<unknown>'.artistOrUnknown, 'Unknown artist');
      expect('<UNKNOWN>'.albumOrUnknown, 'Unknown album');
    });

    test('null / empty / whitespace become friendly labels', () {
      const String? nothing = null;
      expect(nothing.artistOrUnknown, 'Unknown artist');
      expect(''.albumOrUnknown, 'Unknown album');
      expect('   '.artistOrUnknown, 'Unknown artist');
    });

    test('real names pass through unchanged', () {
      expect('Radiohead'.artistOrUnknown, 'Radiohead');
      expect('OK Computer'.albumOrUnknown, 'OK Computer');
    });
  });
}
