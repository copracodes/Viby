import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A frosted-glass panel: a real `BackdropFilter` blurring whatever is behind
/// it, with a translucent [tint] and an optional top hairline [border].
///
/// This is the ONLY place a live backdrop blur is used for chrome. Per the
/// performance budget (CLAUDE.md), at most two of these are on screen at once
/// (the nav bar + an active sheet); scrolling cards never get one — they fake
/// glass with a tint + border and let the static background show through.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.blurSigma,
    required this.tint,
    required this.child,
    this.borderColor,
  });

  final double blurSigma;
  final Color tint;
  final Color? borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            border: borderColor == null
                ? null
                : Border(top: BorderSide(color: borderColor!)),
          ),
          child: child,
        ),
      ),
    );
  }
}
