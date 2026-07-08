import 'dart:convert';
import 'dart:math' as math;

/// A single control point of a preset's frequency-response curve: a target
/// [db] gain at a reference frequency [hz]. Presets are defined as a handful of
/// these points and *normalized* onto whatever bands the device actually
/// reports (see [normalizeCurveToBands]) — we never assume a fixed band count.
class EqControlPoint {
  const EqControlPoint(this.hz, this.db);

  /// Reference frequency in hertz.
  final double hz;

  /// Target gain in decibels at [hz].
  final double db;
}

/// An equalizer preset: a named frequency-response [curve]. Built-in presets
/// (see [kBuiltInPresets]) are code with `builtIn == true`; user-saved presets
/// are drift rows re-hydrated with `builtIn == false`.
///
/// A preset carries a *curve*, not per-band gains, precisely so the same preset
/// maps sensibly onto a 3-, 5-, or 10-band device.
class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.curve,
    this.builtIn = true,
  });

  /// Stable id: a slug for built-ins (`flat`, `rock`, …) or a DAO-minted
  /// `custom:<micros>-<rand>` for user presets.
  final String id;
  final String name;
  final List<EqControlPoint> curve;
  final bool builtIn;

  /// Builds a preset from a frequency→gain map (used to re-hydrate a saved
  /// custom preset). Points are sorted by frequency so interpolation is monotone.
  factory EqPreset.fromGainMap({
    required String id,
    required String name,
    required Map<double, double> gains,
    bool builtIn = false,
  }) {
    final List<EqControlPoint> points = gains.entries
        .map((MapEntry<double, double> e) => EqControlPoint(e.key, e.value))
        .toList()
      ..sort((EqControlPoint a, EqControlPoint b) => a.hz.compareTo(b.hz));
    return EqPreset(id: id, name: name, curve: points, builtIn: builtIn);
  }
}

/// The seven shipped presets. Curves are authored on a canonical ISO-ish set of
/// octave centers (60 Hz … 14 kHz) and interpolated onto the device's bands, so
/// they read the same whether the hardware exposes 3, 5, or 10 bands.
const List<EqPreset> kBuiltInPresets = <EqPreset>[
  EqPreset(id: 'flat', name: 'Flat', curve: <EqControlPoint>[
    EqControlPoint(60, 0),
    EqControlPoint(14000, 0),
  ]),
  EqPreset(id: 'bass_boost', name: 'Bass boost', curve: <EqControlPoint>[
    EqControlPoint(60, 6.0),
    EqControlPoint(150, 4.5),
    EqControlPoint(400, 1.5),
    EqControlPoint(1000, 0),
    EqControlPoint(14000, 0),
  ]),
  EqPreset(id: 'vocal', name: 'Vocal', curve: <EqControlPoint>[
    EqControlPoint(60, -2.0),
    EqControlPoint(200, -1.0),
    EqControlPoint(1000, 2.5),
    EqControlPoint(3000, 4.0),
    EqControlPoint(6000, 2.0),
    EqControlPoint(14000, -1.0),
  ]),
  EqPreset(id: 'rock', name: 'Rock', curve: <EqControlPoint>[
    EqControlPoint(60, 4.0),
    EqControlPoint(230, 2.0),
    EqControlPoint(910, -1.0),
    EqControlPoint(3600, 2.5),
    EqControlPoint(14000, 4.0),
  ]),
  EqPreset(id: 'jazz', name: 'Jazz', curve: <EqControlPoint>[
    EqControlPoint(60, 3.0),
    EqControlPoint(230, 1.5),
    EqControlPoint(910, -1.5),
    EqControlPoint(3600, 1.5),
    EqControlPoint(14000, 2.5),
  ]),
  EqPreset(id: 'electronic', name: 'Electronic', curve: <EqControlPoint>[
    EqControlPoint(60, 5.0),
    EqControlPoint(230, 2.0),
    EqControlPoint(910, 0),
    EqControlPoint(3600, 1.5),
    EqControlPoint(8000, 3.0),
    EqControlPoint(14000, 4.5),
  ]),
  EqPreset(id: 'podcast', name: 'Podcast', curve: <EqControlPoint>[
    EqControlPoint(60, -4.0),
    EqControlPoint(150, -2.0),
    EqControlPoint(500, 1.0),
    EqControlPoint(2000, 3.5),
    EqControlPoint(5000, 2.0),
    EqControlPoint(14000, -2.0),
  ]),
];

/// The default "Flat" preset (id `flat`).
EqPreset get kFlatPreset => kBuiltInPresets.first;

/// Looks up a built-in preset by [id], or null if not a built-in.
EqPreset? builtInPresetById(String id) {
  for (final EqPreset p in kBuiltInPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Interpolates a preset [curve] onto the given band [centerFrequencies],
/// returning one gain (dB) per band, in band order.
///
/// Interpolation is linear in **log-frequency** space (the axis the ear and the
/// bands live on), and clamps flat beyond the first/last control point. This is
/// the single place a preset is mapped to hardware — it makes no assumption
/// about how many bands there are, so 3-, 5-, and 10-band devices all get a
/// faithful rendering of the same curve.
List<double> normalizeCurveToBands(
  List<EqControlPoint> curve,
  List<double> centerFrequencies,
) {
  if (curve.isEmpty) {
    return List<double>.filled(centerFrequencies.length, 0);
  }
  final List<EqControlPoint> points = List<EqControlPoint>.of(curve)
    ..sort((EqControlPoint a, EqControlPoint b) => a.hz.compareTo(b.hz));

  double logHz(double hz) => math.log(math.max(hz, 1.0));

  return centerFrequencies.map((double center) {
    final double x = logHz(center);
    // Below the first / above the last point: hold flat.
    if (x <= logHz(points.first.hz)) return points.first.db;
    if (x >= logHz(points.last.hz)) return points.last.db;
    // Find the bracketing pair and lerp in log-frequency space.
    for (int i = 0; i < points.length - 1; i++) {
      final double x0 = logHz(points[i].hz);
      final double x1 = logHz(points[i + 1].hz);
      if (x >= x0 && x <= x1) {
        final double t = x1 == x0 ? 0.0 : (x - x0) / (x1 - x0);
        return points[i].db + (points[i + 1].db - points[i].db) * t;
      }
    }
    return points.last.db; // unreachable (guarded above)
  }).toList();
}

/// Resolves a stored frequency→gain [gainMap] into a per-band gain list for the
/// given [centerFrequencies]. For each band it takes the gain of the *nearest*
/// stored frequency (in log space); falls back to 0 dB when the map is empty.
///
/// Storing by frequency (not band index) is what lets a curve saved on one
/// device restore correctly on another with a different band layout.
List<double> gainsForBands(
  Map<double, double> gainMap,
  List<double> centerFrequencies,
) {
  if (gainMap.isEmpty) {
    return List<double>.filled(centerFrequencies.length, 0);
  }
  final List<double> freqs = gainMap.keys.toList();
  double logHz(double hz) => math.log(math.max(hz, 1.0));
  return centerFrequencies.map((double center) {
    final double target = logHz(center);
    double best = freqs.first;
    double bestDist = (logHz(best) - target).abs();
    for (final double f in freqs.skip(1)) {
      final double d = (logHz(f) - target).abs();
      if (d < bestDist) {
        bestDist = d;
        best = f;
      }
    }
    return gainMap[best]!;
  }).toList();
}

/// Builds the frequency→gain map to persist from a band layout + gains.
Map<double, double> gainMapFor(
  List<double> centerFrequencies,
  List<double> gains,
) {
  final Map<double, double> map = <double, double>{};
  for (int i = 0; i < centerFrequencies.length && i < gains.length; i++) {
    map[centerFrequencies[i]] = gains[i];
  }
  return map;
}

/// Snaps a gain to the 0 dB center detent when within [detent] dB of it, so the
/// slider "clicks" to flat. Applied on every gain write.
double snapToDetent(double db, {double detent = 0.5}) =>
    db.abs() <= detent ? 0.0 : db;

/// True when two per-band gain lists match within [tol] dB on every band — i.e.
/// the current curve is (still) that of a preset. Used for the modified-state
/// affordance ("Custom (based on Rock)").
bool gainsMatch(List<double> a, List<double> b, {double tol = 0.5}) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > tol) return false;
  }
  return true;
}

/// The label shown for the current EQ state:
/// - no active preset → `Custom`
/// - active preset, unedited → the preset name (e.g. `Rock`)
/// - active preset, edited → `Custom (based on Rock)`
///
/// Pure so the modified-state affordance is unit-testable.
String eqStatusLabel({
  required String? activePresetId,
  required String? activePresetName,
  required bool modified,
}) {
  if (activePresetId == null || activePresetName == null) return 'Custom';
  if (modified) return 'Custom (based on $activePresetName)';
  return activePresetName;
}

// --- Frequency→gain map JSON (shared by EqSettings + EqPresets storage) -------

/// Encodes a frequency→gain map to the JSON string persisted in drift. Keys are
/// stringified frequencies; values are gains in dB.
String encodeGainMap(Map<double, double> gains) {
  return jsonEncode(<String, double>{
    for (final MapEntry<double, double> e in gains.entries)
      _freqKey(e.key): e.value,
  });
}

/// Decodes the JSON produced by [encodeGainMap] back into a frequency→gain map.
/// Tolerant of a null/empty/corrupt payload (returns an empty map).
Map<double, double> decodeGainMap(String? json) {
  if (json == null || json.isEmpty) return <double, double>{};
  try {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map) return <double, double>{};
    final Map<double, double> out = <double, double>{};
    decoded.forEach((Object? k, Object? v) {
      final double? hz = double.tryParse(k.toString());
      final num? db = v is num ? v : num.tryParse(v.toString());
      if (hz != null && db != null) out[hz] = db.toDouble();
    });
    return out;
  } catch (_) {
    return <double, double>{};
  }
}

/// Frequencies are whole hertz for our purposes; key them as trimmed ints when
/// integral so the JSON stays tidy (`"60"` not `"60.0"`).
String _freqKey(double hz) =>
    hz == hz.roundToDouble() ? hz.round().toString() : hz.toString();
