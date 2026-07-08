import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wraps [child] with springy press feedback: scales to [pressedScale] on touch
/// down and springs back to 1.0 on release ([Motion.fast], emphasized curve).
/// Used for the transport controls. Renders nothing interactive itself — pass an
/// [onTap]; a null [onTap] disables the press animation (for dimmed controls).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.pressedScale = 0.9,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: Motion.fast,
        curve: Motion.emphasizedDecelerate,
        child: widget.child,
      ),
    );
  }
}
