import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A shimmering skeleton placeholder (a sweeping highlight over a muted box).
/// Used while artwork loads — a skeleton reads as "content coming", where a
/// spinner reads as "something's wrong".
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.borderRadius = Radii.md});

  final double borderRadius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color base = scheme.surfaceContainerHighest;
    final Color highlight = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.06),
      base,
    );
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            final double x = _controller.value * 3 - 1.5;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(x - 1, 0),
                  end: Alignment(x + 1, 0),
                  colors: <Color>[base, highlight, base],
                  stops: const <double>[0.35, 0.5, 0.65],
                ),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}
