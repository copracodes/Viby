import 'package:flutter/widgets.dart';

/// A minimal, hand-drawn **A–B repeat** glyph: two endpoint markers (A on the
/// left, B on the right) joined by a loop arc that returns to A with a small
/// arrowhead. Material ships no A–B mark, and the stock `repeat_on` icon carries
/// a filled rounded-square background that breaks the plain-glyph corner-action
/// family — so this is drawn to the same ~2dp round-cap stroke weight as the
/// Material set and coloured by the caller (secondary → primary when active).
class AbRepeatIcon extends StatelessWidget {
  const AbRepeatIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AbRepeatPainter(color)),
    );
  }
}

class _AbRepeatPainter extends CustomPainter {
  const _AbRepeatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is authored on a 24-unit grid and scaled to the real size, so
    // the stroke weight and proportions hold at any icon size.
    double u(double v) => size.width * v / 24;

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double baseY = u(16.5);
    final double ax = u(4.8);
    final double bx = u(19.2);
    final double r = u(1.9);

    // The loop: a semicircle bulging up from A to B (clockwise in screen
    // coordinates = up and over the top).
    final Path loop = Path()
      ..moveTo(ax, baseY)
      ..arcToPoint(
        Offset(bx, baseY),
        radius: Radius.circular((bx - ax) / 2),
        clockwise: true,
      );
    canvas.drawPath(loop, stroke);

    // The two endpoint markers.
    canvas.drawCircle(Offset(ax, baseY), r, fill);
    canvas.drawCircle(Offset(bx, baseY), r, fill);

    // A downward chevron arrowhead at A — the loop "returns" to the start.
    final double d = u(2.7);
    final double e = u(2.9);
    final Path arrow = Path()
      ..moveTo(ax - d, baseY - e)
      ..lineTo(ax, baseY)
      ..lineTo(ax + d, baseY - e);
    canvas.drawPath(arrow, stroke);
  }

  @override
  bool shouldRepaint(_AbRepeatPainter oldDelegate) =>
      oldDelegate.color != color;
}
