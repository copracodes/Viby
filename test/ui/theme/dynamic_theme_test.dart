import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:viby/ui/theme/dynamic_theme.dart';

void main() {
  group('contrast guard', () {
    test('contrastRatio is symmetric and spans black↔white = 21', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(
        contrastRatio(Colors.white, Colors.black),
        closeTo(contrastRatio(Colors.black, Colors.white), 0.001),
      );
    });

    test('a low-contrast colour is adjusted until it clears 4.5:1', () {
      const Color background = Color(0xFF000000);
      const Color tooDark = Color(0xFF222222); // ~1.5:1 on black — unreadable
      expect(contrastRatio(tooDark, background), lessThan(4.5));

      final Color fixed = ensureContrast(tooDark, background);
      expect(contrastRatio(fixed, background), greaterThanOrEqualTo(4.5));
    });

    test('an already-legible colour is returned unchanged', () {
      const Color background = Color(0xFF000000);
      const Color bright = Color(0xFFEEEEEE);
      expect(ensureContrast(bright, background), bright);
    });
  });

  group('monochrome fallback', () {
    test('near-monochrome art yields no seed (→ brand fallback)', () {
      final PaletteGenerator grey = PaletteGenerator.fromColors(<PaletteColor>[
        PaletteColor(const Color(0xFF3A3A3A), 300),
        PaletteColor(const Color(0xFF6E6E6E), 120),
      ]);
      expect(seedFromPalette(grey), isNull);
    });

    test('a vibrant swatch is picked as the seed', () {
      final PaletteGenerator vivid = PaletteGenerator.fromColors(<PaletteColor>[
        PaletteColor(const Color(0xFFE91E63), 300), // saturated pink
        PaletteColor(const Color(0xFF202020), 50),
      ]);
      final Color? seed = seedFromPalette(vivid);
      expect(seed, isNotNull);
      expect(isNearMonochrome(seed!), isFalse);
    });

    test('isNearMonochrome flags greys but not saturated colours', () {
      expect(isNearMonochrome(const Color(0xFF808080)), isTrue);
      expect(isNearMonochrome(const Color(0xFFE91E63)), isFalse);
    });
  });

  group('LruCache', () {
    test('evicts the least-recently-used entry past capacity', () {
      final LruCache<String, int> cache = LruCache<String, int>(2);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // 'a' is now most-recently-used, so 'b' is the LRU
      cache.put('c', 3); // evicts 'b'

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.length, 2);
    });

    test('capacity of 50 holds 50 and drops the oldest on the 51st', () {
      final LruCache<int, int> cache = LruCache<int, int>(50);
      for (int i = 0; i < 51; i++) {
        cache.put(i, i);
      }
      expect(cache.length, 50);
      expect(cache.containsKey(0), isFalse); // oldest evicted
      expect(cache.containsKey(50), isTrue);
    });
  });

  group('schemeFromSeed', () {
    test('amoled dark uses pure-black surface', () {
      final ColorScheme scheme = schemeFromSeed(
        kBrandSeed,
        brightness: Brightness.dark,
        amoled: true,
      );
      expect(scheme.surface, const Color(0xFF000000));
      expect(scheme.brightness, Brightness.dark);
    });

    test('non-amoled dark keeps its tonal (non-black) surface', () {
      final ColorScheme scheme =
          schemeFromSeed(kBrandSeed, brightness: Brightness.dark);
      expect(scheme.surface, isNot(const Color(0xFF000000)));
    });

    test('primary always clears the contrast guard on surface', () {
      for (final Brightness b in Brightness.values) {
        final ColorScheme scheme = schemeFromSeed(kBrandSeed, brightness: b);
        expect(
          contrastRatio(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });
}
