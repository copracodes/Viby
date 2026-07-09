import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'viby_theme.dart';

/// Paints a theme's [BackgroundSpec] behind the app's (transparent) scaffolds.
/// Mounted once at the shell root; every screen renders over it.
///
/// Aurora is drawn as a **static** layer — the blobs are composed into a cached
/// `ui.Image` once per theme+size and only redrawn when the theme or size
/// changes (never per frame, never a live `BackdropFilter`). It sits in its own
/// [RepaintBoundary] so scrolling content above it triggers zero background
/// repaints.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.background, required this.child});

  final BackgroundSpec background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Cross-fade the background layer when the theme (hence spec) changes.
        // The layoutBuilder forces StackFit.expand so solid/gradient layers
        // (which have no intrinsic size) fill the screen instead of collapsing
        // to zero under the switcher's default loose constraints.
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedSwitcher(
              duration: Motion.themeMorph,
              layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
                  Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: _BackgroundLayer(
                background,
                key: ValueKey<String>(jsonEncode(background.toJson())),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer(this.spec, {super.key});

  final BackgroundSpec spec;

  @override
  Widget build(BuildContext context) {
    return switch (spec) {
      SolidBackground(:final Color color) => ColoredBox(color: color),
      LinearGradientBackground() => DecoratedBox(
          decoration: BoxDecoration(gradient: _gradientOf(spec as LinearGradientBackground)),
        ),
      AuroraBackground() => _AuroraLayer(spec as AuroraBackground),
    };
  }

  LinearGradient _gradientOf(LinearGradientBackground g) => LinearGradient(
        colors: g.colors,
        stops: g.stops,
        begin: g.begin,
        end: g.end,
      );
}

/// The static aurora layer: composes the base fill + glow blobs into a cached
/// image, regenerated only on theme/size change.
class _AuroraLayer extends StatefulWidget {
  const _AuroraLayer(this.spec);

  final AuroraBackground spec;

  @override
  State<_AuroraLayer> createState() => _AuroraLayerState();
}

class _AuroraLayerState extends State<_AuroraLayer> {
  ui.Image? _image;
  Size _builtSize = Size.zero;
  AuroraBackground? _builtSpec;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _regenerate(Size size) {
    if (size.isEmpty) return;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    _paintAurora(canvas, size, widget.spec);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image next =
        picture.toImageSync(size.width.ceil(), size.height.ceil());
    picture.dispose();
    _image?.dispose();
    _image = next;
    _builtSize = size;
    _builtSpec = widget.spec;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final bool stale = _image == null ||
            size != _builtSize ||
            !identical(_builtSpec, widget.spec);
        if (stale) _regenerate(size);
        return CustomPaint(
          painter: _CachedImagePainter(_image, widget.spec.baseColor),
          size: size,
        );
      },
    );
  }
}

/// Paints [image] 1:1 (already sized to the layer), with [base] as the fill
/// beneath while the first image is being generated.
class _CachedImagePainter extends CustomPainter {
  const _CachedImagePainter(this.image, this.base);

  final ui.Image? image;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final ui.Image? img = image;
    if (img != null) {
      canvas.drawImage(img, Offset.zero, Paint());
    }
  }

  @override
  bool shouldRepaint(_CachedImagePainter old) =>
      old.image != image || old.base != base;
}

/// Draws the base fill and the soft glow blobs. Used once per theme+size to fill
/// the cached image.
void _paintAurora(Canvas canvas, Size size, AuroraBackground spec) {
  canvas.drawRect(Offset.zero & size, Paint()..color = spec.baseColor);
  final double shortest = size.shortestSide;
  for (final GlowBlob blob in spec.blobs) {
    final Offset center = Offset(
      (blob.alignment.x + 1) / 2 * size.width,
      (blob.alignment.y + 1) / 2 * size.height,
    );
    final double radius = blob.radius * shortest;
    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[
          blob.color.withValues(alpha: blob.opacity),
          blob.color.withValues(alpha: 0),
        ],
        <double>[0.0, 1.0],
      );
    canvas.drawCircle(center, radius, paint);
  }
}
