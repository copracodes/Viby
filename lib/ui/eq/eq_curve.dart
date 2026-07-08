import 'dart:ui';

/// Pure geometry helpers for the equalizer frequency-response visualization.
/// Kept separate from the painter so the spline math is trivially reusable
/// (and, if needed, testable) without a canvas.

/// Maps per-band [gains] to evenly-spaced points inside a [size] rect, given the
/// gain range [minDb]..[maxDb]. Bands are laid out left→right at equal spacing
/// (the conventional EQ display); gain maps to the vertical axis with 0 dB in
/// the middle. Returns one [Offset] per gain.
List<Offset> curvePoints({
  required List<double> gains,
  required double minDb,
  required double maxDb,
  required Size size,
}) {
  if (gains.isEmpty) return const <Offset>[];
  final double span = (maxDb - minDb).abs() < 1e-6 ? 1.0 : (maxDb - minDb);
  final int n = gains.length;
  return <Offset>[
    for (int i = 0; i < n; i++)
      Offset(
        n == 1 ? size.width / 2 : size.width * i / (n - 1),
        size.height * (1 - ((gains[i] - minDb) / span)).clamp(0.0, 1.0),
      ),
  ];
}

/// Builds a smooth Catmull-Rom path through [points] (converted to cubic
/// béziers). With fewer than 3 points it degrades to a straight polyline.
Path smoothPath(List<Offset> points) {
  final Path path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    for (final Offset p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
  for (int i = 0; i < points.length - 1; i++) {
    final Offset p0 = points[i == 0 ? 0 : i - 1];
    final Offset p1 = points[i];
    final Offset p2 = points[i + 1];
    final Offset p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
    final Offset c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final Offset c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// Formats a band center frequency for its axis label: "60", "230", "1k",
/// "3.6k", "14k". Hz below 1000 print as whole numbers; kHz drop a trailing ".0".
String formatFrequency(double hz) {
  if (hz < 1000) return hz.round().toString();
  final double k = hz / 1000;
  final String s = k >= 10 || k == k.roundToDouble()
      ? k.round().toString()
      : k.toStringAsFixed(1);
  return '${s}k';
}
