import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A tiny animated 3-bar equalizer marking the currently-playing row. The bars
/// bounce while [playing] and freeze mid-motion when paused (so a paused row
/// still reads as "this is the one, just paused").
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color,
    this.size = 18,
  });

  final bool playing;
  final Color? color;
  final double size;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Per-bar phase offsets so they don't move in lockstep.
  static const List<double> _phases = <double>[0.0, 0.5, 0.25];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop(); // freeze mid-motion
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;
    final double barWidth = widget.size / 6;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final double phase in _phases)
                  _bar(color, barWidth, _height(phase)),
              ],
            );
          },
        ),
      ),
    );
  }

  double _height(double phase) {
    final double v = math.sin((_controller.value + phase) * 2 * math.pi);
    return (0.35 + 0.65 * (0.5 + 0.5 * v)) * widget.size;
  }

  Widget _bar(Color color, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
