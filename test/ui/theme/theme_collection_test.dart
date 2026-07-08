import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/ui/theme/dynamic_theme.dart';
import 'package:viby/ui/theme/theme_collection.dart';
import 'package:viby/ui/theme/viby_theme.dart';

void main() {
  group('BackgroundSpec serialization round-trip', () {
    void roundTrips(BackgroundSpec spec) {
      final BackgroundSpec back = BackgroundSpec.fromJson(spec.toJson());
      expect(back.toJson(), spec.toJson());
      expect(back.runtimeType, spec.runtimeType);
    }

    test('solid', () => roundTrips(const SolidBackground(Color(0xFF112233))));

    test('linearGradient', () {
      roundTrips(const LinearGradientBackground(
        colors: <Color>[Color(0xFF2E1145), Color(0xFF241033), Color(0xFF3A1440)],
        stops: <double>[0, 0.5, 1],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ));
    });

    test('aurora', () {
      roundTrips(const AuroraBackground(
        baseColor: Color(0xFF0A0A0F),
        blobs: <GlowBlob>[
          GlowBlob(
            color: Color(0xFF6A2CE0),
            alignment: Alignment(-0.9, -0.9),
            radius: 0.9,
            opacity: 0.45,
          ),
          GlowBlob(
            color: Color(0xFFD81E9B),
            alignment: Alignment(0.1, 1.1),
            radius: 0.95,
            opacity: 0.34,
          ),
        ],
      ));
    });

    test('every shipped theme background round-trips', () {
      for (final VibyTheme t in kThemeCollection) {
        final BackgroundSpec back = BackgroundSpec.fromJson(t.background.toJson());
        expect(back.toJson(), t.background.toJson(), reason: t.id);
      }
    });
  });

  group('blob contrast guard', () {
    test('brightestRegion picks the most luminous composited blob', () {
      const AuroraBackground bg = AuroraBackground(
        baseColor: Color(0xFF000000),
        blobs: <GlowBlob>[
          GlowBlob(
            color: Color(0xFF222222),
            alignment: Alignment.topLeft,
            radius: 1,
            opacity: 1,
          ),
          GlowBlob(
            color: Color(0xFFDDDDDD),
            alignment: Alignment.bottomRight,
            radius: 1,
            opacity: 1,
          ),
        ],
      );
      // The bright blob dominates.
      expect(brightestRegion(bg).computeLuminance(),
          greaterThan(const Color(0xFF888888).computeLuminance()));
    });

    test('ensureBlobsReadable darkens blobs until text clears the guard', () {
      // A bright blob over black with white text would fail; the guard scales
      // opacity down until white-on-brightest ≥ 4.5:1.
      const AuroraBackground bg = AuroraBackground(
        baseColor: Color(0xFF000000),
        blobs: <GlowBlob>[
          GlowBlob(
            color: Color(0xFFFFFFFF),
            alignment: Alignment.center,
            radius: 1,
            opacity: 0.9,
          ),
        ],
      );
      const Color white = Color(0xFFFFFFFF);
      expect(contrastRatio(white, brightestRegion(bg)), lessThan(kMinContrast));
      final AuroraBackground safe = ensureBlobsReadable(bg, white);
      expect(contrastRatio(white, brightestRegion(safe)),
          greaterThanOrEqualTo(kMinContrast));
      expect(safe.blobs.single.opacity, lessThan(0.9));
    });

    test('leaves already-safe blobs untouched', () {
      const AuroraBackground bg = AuroraBackground(
        baseColor: Color(0xFF0A0A0F),
        blobs: <GlowBlob>[
          GlowBlob(
            color: Color(0xFF6A2CE0),
            alignment: Alignment.topLeft,
            radius: 0.9,
            opacity: 0.3,
          ),
        ],
      );
      final AuroraBackground safe = ensureBlobsReadable(bg, const Color(0xFFFFFFFF));
      expect(safe.blobs.single.opacity, 0.3);
    });
  });

  group('every theme is coherent (contrast guards hold)', () {
    test('primary reads on surface at ≥ 4.5:1', () {
      for (final VibyTheme t in kThemeCollection) {
        expect(
          contrastRatio(t.scheme.primary, t.scheme.surface),
          greaterThanOrEqualTo(kMinContrast),
          reason: '${t.id} primary-on-surface',
        );
      }
    });

    test('aurora text reads over the brightest blob region', () {
      for (final VibyTheme t in kThemeCollection) {
        final BackgroundSpec bg = t.background;
        if (bg is AuroraBackground) {
          expect(
            contrastRatio(t.scheme.onSurface, brightestRegion(bg)),
            greaterThanOrEqualTo(kMinContrast),
            reason: '${t.id} onSurface over brightest blob',
          );
        }
      }
    });
  });

  group('resolveActiveTheme', () {
    test('system-follow maps to the Classic pair by platform brightness', () {
      expect(
        resolveActiveTheme(
          selectedId: 'nebula',
          systemFollow: true,
          platformBrightness: Brightness.light,
          amoledOverride: false,
        ).id,
        'classic_light',
      );
      expect(
        resolveActiveTheme(
          selectedId: 'nebula',
          systemFollow: true,
          platformBrightness: Brightness.dark,
          amoledOverride: false,
        ).id,
        'classic_dark',
      );
    });

    test('specific selection wins when not following system', () {
      expect(
        resolveActiveTheme(
          selectedId: 'nebula',
          systemFollow: false,
          platformBrightness: Brightness.light,
          amoledOverride: false,
        ).id,
        'nebula',
      );
    });

    test('unknown id falls back to Classic Dark', () {
      expect(
        resolveActiveTheme(
          selectedId: 'nope',
          systemFollow: false,
          platformBrightness: Brightness.light,
          amoledOverride: false,
        ).id,
        'classic_dark',
      );
    });

    test('amoled override forces pure-black surfaces on dark themes only', () {
      final VibyTheme dark = resolveActiveTheme(
        selectedId: 'midnight_aurora',
        systemFollow: false,
        platformBrightness: Brightness.dark,
        amoledOverride: true,
      );
      expect(dark.scheme.surface, const Color(0xFF000000));
      // Aurora blobs survive on black.
      expect(dark.background, isA<AuroraBackground>());

      final VibyTheme light = resolveActiveTheme(
        selectedId: 'frost',
        systemFollow: false,
        platformBrightness: Brightness.light,
        amoledOverride: true,
      );
      expect(light.scheme.surface, isNot(const Color(0xFF000000)));
    });
  });

  group('effectiveScheme (dynamic-seed gating)', () {
    const Color seed = Color(0xFF00E5FF); // cyan

    test('accepting theme swaps primary from the seed', () {
      final ColorScheme s =
          effectiveScheme(onyx, seed: seed, dynamicColor: true);
      expect(s.primary, isNot(onyx.scheme.primary));
      // Surface identity is preserved.
      expect(s.surface, onyx.scheme.surface);
    });

    test('non-accepting theme ignores the seed (locked identity)', () {
      final ColorScheme s =
          effectiveScheme(nebula, seed: seed, dynamicColor: true);
      expect(s.primary, nebula.scheme.primary);
    });

    test('dynamic off, or null seed, keeps the theme scheme', () {
      expect(effectiveScheme(onyx, seed: seed, dynamicColor: false).primary,
          onyx.scheme.primary);
      expect(effectiveScheme(onyx, seed: null, dynamicColor: true).primary,
          onyx.scheme.primary);
    });
  });
}
