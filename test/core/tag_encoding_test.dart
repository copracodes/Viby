import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/tag_encoding.dart';

void main() {
  // Arabic "بحر" (sea) is CP1256 bytes [0xC8, 0xCD, 0xD1]. When those bytes are
  // (mis)decoded as Latin-1 — exactly what MediaStore does — they become the
  // string "ÈÍÑ" (U+00C8, U+00CD, U+00D1). That mojibake is our repair target.
  const String arabic = 'بحر';
  const String mojibake = 'ÈÍÑ';

  group('decodeCp1256', () {
    test('maps CP1256 bytes to the right Arabic code points', () {
      expect(decodeCp1256(<int>[0xC8, 0xCD, 0xD1]), arabic);
    });

    test('leaves ASCII bytes untouched', () {
      expect(decodeCp1256('Hello'.codeUnits), 'Hello');
    });
  });

  group('bestDecoding', () {
    test('repairs a CP1256-as-Latin1 title', () {
      expect(bestDecoding(mojibake), arabic);
    });

    test('leaves a proper UTF-8 Arabic title untouched', () {
      expect(bestDecoding(arabic), arabic);
    });

    test('leaves a plain ASCII title untouched', () {
      expect(bestDecoding('Bohemian Rhapsody'), 'Bohemian Rhapsody');
    });

    test('does not mangle a mostly-ASCII title with one stray accent', () {
      expect(bestDecoding('Café'), 'Café');
    });

    test('does not mangle an ordinary accented Latin name (Björk)', () {
      // ö would reinterpret to a CP1256 diacritic — the suspicion guard blocks
      // this false positive (only one high char, no replacement/`?`).
      expect(bestDecoding('Björk'), 'Björk');
    });
  });

  group('looksSuspicious', () {
    test('flags mojibake and replacement chars', () {
      expect(looksSuspicious(mojibake), isTrue);
      expect(looksSuspicious('Sng ��'), isTrue);
    });

    test('does not flag clean ASCII or clean Arabic', () {
      expect(looksSuspicious('Bohemian Rhapsody'), isFalse);
      expect(looksSuspicious(arabic), isFalse);
      expect(looksSuspicious(''), isFalse);
    });
  });
}
