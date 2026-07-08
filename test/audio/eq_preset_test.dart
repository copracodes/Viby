import 'package:flutter_test/flutter_test.dart';
import 'package:viby/audio/eq_preset.dart';

void main() {
  group('normalizeCurveToBands', () {
    // A representative 3-, 5-, and 10-band device layout (octave-ish centers).
    const List<double> bands3 = <double>[120, 1000, 8000];
    const List<double> bands5 = <double>[60, 230, 910, 3600, 14000];
    const List<double> bands10 = <double>[
      31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
    ];

    test('produces one gain per band, for any band count', () {
      final EqPreset rock = builtInPresetById('rock')!;
      expect(normalizeCurveToBands(rock.curve, bands3), hasLength(3));
      expect(normalizeCurveToBands(rock.curve, bands5), hasLength(5));
      expect(normalizeCurveToBands(rock.curve, bands10), hasLength(10));
    });

    test('flat preset maps to all zeros on every layout', () {
      final EqPreset flat = builtInPresetById('flat')!;
      for (final List<double> bands in <List<double>>[bands3, bands5, bands10]) {
        for (final double g in normalizeCurveToBands(flat.curve, bands)) {
          expect(g, closeTo(0, 1e-9));
        }
      }
    });

    test('reproduces control-point gains exactly at their frequencies', () {
      // Rock has an explicit +4 dB point at 60 Hz and a -1 dB point at 910 Hz.
      final EqPreset rock = builtInPresetById('rock')!;
      final List<double> g = normalizeCurveToBands(rock.curve, bands5);
      expect(g[0], closeTo(4.0, 1e-6)); // 60 Hz
      expect(g[2], closeTo(-1.0, 1e-6)); // 910 Hz
      expect(g[4], closeTo(4.0, 1e-6)); // 14 kHz
    });

    test('clamps flat below the first / above the last control point', () {
      const List<EqControlPoint> curve = <EqControlPoint>[
        EqControlPoint(100, 6),
        EqControlPoint(1000, -6),
      ];
      // 20 Hz is below the first point → holds 6; 16 kHz above the last → -6.
      final List<double> g =
          normalizeCurveToBands(curve, <double>[20, 100, 1000, 16000]);
      expect(g[0], closeTo(6, 1e-9));
      expect(g[1], closeTo(6, 1e-9));
      expect(g[2], closeTo(-6, 1e-9));
      expect(g[3], closeTo(-6, 1e-9));
    });

    test('interpolates in log-frequency space (midpoint of a decade)', () {
      // Two points a decade apart; the geometric mid-frequency should land at
      // the arithmetic midpoint gain.
      const List<EqControlPoint> curve = <EqControlPoint>[
        EqControlPoint(100, 0),
        EqControlPoint(1000, 10),
      ];
      final List<double> g = normalizeCurveToBands(curve, <double>[316.2278]);
      expect(g.single, closeTo(5.0, 0.05));
    });

    test('empty curve yields zeros', () {
      expect(
        normalizeCurveToBands(const <EqControlPoint>[], bands5),
        everyElement(0.0),
      );
    });
  });

  group('gainsForBands / gainMapFor (frequency-keyed restore)', () {
    test('round-trips gains through a frequency map onto the same layout', () {
      const List<double> freqs = <double>[60, 230, 910, 3600, 14000];
      const List<double> gains = <double>[3, -2, 0, 4.5, -1];
      final Map<double, double> map = gainMapFor(freqs, gains);
      expect(gainsForBands(map, freqs), gains);
    });

    test('restores onto a different band layout by nearest frequency', () {
      // Saved on a 3-band device, restored on a 5-band one: each new band takes
      // the nearest saved frequency's gain.
      final Map<double, double> saved =
          gainMapFor(<double>[120, 1000, 8000], <double>[6, 0, -6]);
      final List<double> restored =
          gainsForBands(saved, <double>[60, 230, 910, 3600, 14000]);
      expect(restored[0], 6); // 60 Hz → nearest 120
      expect(restored[4], -6); // 14 kHz → nearest 8000
      expect(restored, hasLength(5));
    });

    test('empty map yields zeros', () {
      expect(gainsForBands(<double, double>{}, <double>[60, 1000]), <double>[0, 0]);
    });
  });

  group('snapToDetent', () {
    test('snaps to 0 within the detent band, passes through otherwise', () {
      expect(snapToDetent(0.4), 0.0);
      expect(snapToDetent(-0.5), 0.0);
      expect(snapToDetent(0.51), 0.51);
      expect(snapToDetent(-3.2), -3.2);
    });
  });

  group('gainsMatch (modified detection)', () {
    test('true within tolerance, false beyond it or on length mismatch', () {
      expect(gainsMatch(<double>[1, 2, 3], <double>[1.3, 2.0, 2.7]), isTrue);
      expect(gainsMatch(<double>[1, 2, 3], <double>[1, 2, 4]), isFalse);
      expect(gainsMatch(<double>[1, 2], <double>[1, 2, 3]), isFalse);
    });
  });

  group('eqStatusLabel (modified-state affordance)', () {
    test('no active preset → Custom', () {
      expect(
        eqStatusLabel(
            activePresetId: null, activePresetName: null, modified: false),
        'Custom',
      );
    });

    test('active + unedited → the preset name', () {
      expect(
        eqStatusLabel(
            activePresetId: 'rock', activePresetName: 'Rock', modified: false),
        'Rock',
      );
    });

    test('active + edited → Custom (based on X)', () {
      expect(
        eqStatusLabel(
            activePresetId: 'rock', activePresetName: 'Rock', modified: true),
        'Custom (based on Rock)',
      );
    });
  });

  group('gain-map JSON', () {
    test('encode/decode round-trips (integer keys stay tidy)', () {
      final Map<double, double> gains = <double, double>{
        60: 3.5,
        230: -1.0,
        14000: 2.0,
      };
      final String json = encodeGainMap(gains);
      expect(json.contains('"60"'), isTrue);
      expect(decodeGainMap(json), gains);
    });

    test('tolerates null / empty / garbage', () {
      expect(decodeGainMap(null), isEmpty);
      expect(decodeGainMap(''), isEmpty);
      expect(decodeGainMap('not json'), isEmpty);
      expect(decodeGainMap('[1,2,3]'), isEmpty);
    });
  });
}
