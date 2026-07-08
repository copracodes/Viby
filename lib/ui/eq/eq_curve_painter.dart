import 'package:flutter/material.dart';

import 'eq_curve.dart';

/// Paints the equalizer frequency-response curve: a smooth spline through the
/// band gains, filled beneath with the scheme primary at low alpha. Repaints
/// only when the gains (or theme colours) change, so dragging a slider stays at
/// 60fps. Band dots mark the control points.
class EqCurvePainter extends CustomPainter {
  const EqCurvePainter({
    required this.gains,
    required this.minDb,
    required this.maxDb,
    required this.primary,
    required this.gridColor,
    required this.enabled,
  });

  final List<double> gains;
  final double minDb;
  final double maxDb;
  final Color primary;
  final Color gridColor;

  /// When false (master EQ off), the curve is drawn muted.
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    // Zero-line (0 dB) reference.
    final double span = (maxDb - minDb).abs() < 1e-6 ? 1.0 : (maxDb - minDb);
    final double zeroY = size.height * (1 - ((0 - minDb) / span)).clamp(0.0, 1.0);
    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint);

    final List<Offset> points =
        curvePoints(gains: gains, minDb: minDb, maxDb: maxDb, size: size);
    if (points.isEmpty) return;

    final double opacity = enabled ? 1.0 : 0.35;
    final Path line = smoothPath(points);

    // Fill under the curve.
    final Path fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primary.withValues(alpha: 0.28 * opacity),
          primary.withValues(alpha: 0.02 * opacity),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    // Stroke the curve.
    final Paint stroke = Paint()
      ..color = primary.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, stroke);

    // Control-point dots.
    final Paint dot = Paint()..color = primary.withValues(alpha: opacity);
    final Paint dotHalo = Paint()
      ..color = primary.withValues(alpha: 0.18 * opacity);
    for (final Offset p in points) {
      canvas.drawCircle(p, 5, dotHalo);
      canvas.drawCircle(p, 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(EqCurvePainter old) {
    if (old.enabled != enabled ||
        old.primary != primary ||
        old.gridColor != gridColor ||
        old.minDb != minDb ||
        old.maxDb != maxDb ||
        old.gains.length != gains.length) {
      return true;
    }
    for (int i = 0; i < gains.length; i++) {
      if (old.gains[i] != gains[i]) return true;
    }
    return false;
  }
}
