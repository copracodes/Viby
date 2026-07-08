import 'package:flutter/material.dart';

import 'dynamic_theme.dart' show contrastRatio, kMinContrast;

/// A named, hand-crafted Viby theme: a [ColorScheme] plus how the app's
/// *background* and *surfaces* render on top of it. This extends the 2.1 token +
/// dynamic-colour system (it does not replace it) — the token scale, motion and
/// the contrast guard still apply; a [VibyTheme] only adds art direction.
///
/// [acceptsDynamicSeed] declares whether album-art dynamic colour may swap this
/// theme's primary (Classic + Onyx accept; gradient/aurora themes lock their
/// identity so dynamic colour doesn't fight the art direction). Now Playing's
/// palette-tinted backdrop is contextual and applies regardless (per CLAUDE.md).
class VibyTheme {
  const VibyTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.scheme,
    required this.background,
    required this.surface,
    required this.acceptsDynamicSeed,
    this.isPro = false,
  });

  /// Stable id, persisted in settings (never reuse across themes).
  final String id;
  final String name;
  final Brightness brightness;
  final ColorScheme scheme;
  final BackgroundSpec background;
  final SurfaceSpec surface;
  final bool acceptsDynamicSeed;

  /// Marks a Pro theme (badge shown). Gating is a separate concern — see
  /// `kProThemesUnlocked`.
  final bool isPro;

  bool get isDark => brightness == Brightness.dark;

  VibyTheme copyWith({ColorScheme? scheme, BackgroundSpec? background}) =>
      VibyTheme(
        id: id,
        name: name,
        brightness: brightness,
        scheme: scheme ?? this.scheme,
        background: background ?? this.background,
        surface: surface,
        acceptsDynamicSeed: acceptsDynamicSeed,
        isPro: isPro,
      );
}

// --- BackgroundSpec --------------------------------------------------------

/// How the app background is painted behind the (transparent) scaffolds.
///
/// [AuroraBackground] is rendered as a **static** pre-composed layer (painted
/// once per theme+size, cached as an image) — never a live `BackdropFilter`, so
/// scrolling causes zero background repaints. See `app_background.dart`.
sealed class BackgroundSpec {
  const BackgroundSpec();

  Map<String, Object?> toJson();

  static BackgroundSpec fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'solid':
        return SolidBackground(_color(json['color']));
      case 'linearGradient':
        return LinearGradientBackground(
          colors: (json['colors']! as List<Object?>)
              .map((Object? c) => _color(c))
              .toList(),
          stops: (json['stops'] as List<Object?>?)
              ?.map((Object? s) => (s! as num).toDouble())
              .toList(),
          begin: _align(json['begin']),
          end: _align(json['end']),
        );
      case 'aurora':
        return AuroraBackground(
          baseColor: _color(json['baseColor']),
          blobs: (json['blobs']! as List<Object?>)
              .map((Object? b) => GlowBlob.fromJson(b! as Map<String, Object?>))
              .toList(),
        );
      default:
        throw ArgumentError('unknown BackgroundSpec type: ${json['type']}');
    }
  }
}

/// A flat fill (the Classic themes).
class SolidBackground extends BackgroundSpec {
  const SolidBackground(this.color);
  final Color color;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'type': 'solid', 'color': color.toARGB32()};
}

/// A linear gradient wash (Nebula, Frost's top tint).
class LinearGradientBackground extends BackgroundSpec {
  const LinearGradientBackground({
    required this.colors,
    this.stops,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
  });

  final List<Color> colors;
  final List<double>? stops;
  final Alignment begin;
  final Alignment end;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'linearGradient',
        'colors': colors.map((Color c) => c.toARGB32()).toList(),
        if (stops != null) 'stops': stops,
        'begin': <double>[begin.x, begin.y],
        'end': <double>[end.x, end.y],
      };
}

/// A base fill with soft glow blobs composited on top (the aurora look). Painted
/// statically — see [BackgroundSpec] doc.
class AuroraBackground extends BackgroundSpec {
  const AuroraBackground({required this.baseColor, required this.blobs});

  final Color baseColor;
  final List<GlowBlob> blobs;

  /// Returns a copy with every blob's opacity scaled by [factor] (used by the
  /// contrast guard to auto-darken blobs that fail a readability check).
  AuroraBackground scaleOpacity(double factor) => AuroraBackground(
        baseColor: baseColor,
        blobs: blobs
            .map((GlowBlob b) => b.copyWith(opacity: b.opacity * factor))
            .toList(),
      );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'aurora',
        'baseColor': baseColor.toARGB32(),
        'blobs': blobs.map((GlowBlob b) => b.toJson()).toList(),
      };
}

/// A single soft radial glow in an [AuroraBackground]. [radius] is a fraction of
/// the layer's shortest side; [alignment] positions the blob centre.
class GlowBlob {
  const GlowBlob({
    required this.color,
    required this.alignment,
    required this.radius,
    required this.opacity,
  });

  final Color color;
  final Alignment alignment;
  final double radius;
  final double opacity;

  GlowBlob copyWith({double? opacity}) => GlowBlob(
        color: color,
        alignment: alignment,
        radius: radius,
        opacity: opacity ?? this.opacity,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'color': color.toARGB32(),
        'alignment': <double>[alignment.x, alignment.y],
        'radius': radius,
        'opacity': opacity,
      };

  static GlowBlob fromJson(Map<String, Object?> json) => GlowBlob(
        color: _color(json['color']),
        alignment: _align(json['alignment']),
        radius: (json['radius']! as num).toDouble(),
        opacity: (json['opacity']! as num).toDouble(),
      );
}

// --- SurfaceSpec -----------------------------------------------------------

/// How cards / sheets / nav render on top of the background.
///
/// [GlassSurface] uses a real `BackdropFilter` ONLY where it earns it (nav bar +
/// the active sheet — at most two live filters on screen). Cards in scrolling
/// content fake glass with a semi-transparent tint + hairline border and let the
/// static background show through (see the performance budget in CLAUDE.md).
sealed class SurfaceSpec {
  const SurfaceSpec();
}

/// Fully opaque surfaces (Classic).
class OpaqueSurface extends SurfaceSpec {
  const OpaqueSurface();
}

/// Scheme surface painted at [alpha] so the background shows through — no blur.
class TintedSurface extends SurfaceSpec {
  const TintedSurface({this.alpha = 0.72});
  final double alpha;
}

/// Frosted glass: [blurSigma] backdrop blur (real, budgeted surfaces only),
/// surface tint at [tintAlpha], hairline border at [borderAlpha].
class GlassSurface extends SurfaceSpec {
  const GlassSurface({
    this.blurSigma = 24,
    this.tintAlpha = 0.5,
    this.borderAlpha = 0.12,
  });
  final double blurSigma;
  final double tintAlpha;
  final double borderAlpha;
}

// --- Blob contrast guard ---------------------------------------------------

/// The effective colour a viewer sees where [blob] is brightest — the blob
/// colour composited (src-over) onto [base] at the blob's peak opacity. Used to
/// test whether text will read over the brightest region of an aurora.
Color compositeBlob(Color base, GlowBlob blob) =>
    Color.alphaBlend(blob.color.withValues(alpha: blob.opacity), base);

/// The brightest composited region across all blobs of [bg] (by luminance).
Color brightestRegion(AuroraBackground bg) {
  Color brightest = bg.baseColor;
  for (final GlowBlob blob in bg.blobs) {
    final Color c = compositeBlob(bg.baseColor, blob);
    if (c.computeLuminance() > brightest.computeLuminance()) brightest = c;
  }
  return brightest;
}

/// Ensures body text ([onColor]) stays legible over the brightest blob region of
/// an [AuroraBackground]: if contrast there falls below [minRatio], blob opacity
/// is scaled down (up to a floor) until it clears. Returns the safe background.
AuroraBackground ensureBlobsReadable(
  AuroraBackground bg,
  Color onColor, {
  double minRatio = kMinContrast,
}) {
  AuroraBackground current = bg;
  for (int i = 0; i < 8; i++) {
    if (contrastRatio(onColor, brightestRegion(current)) >= minRatio) {
      return current;
    }
    current = current.scaleOpacity(0.85);
  }
  return current;
}

// --- JSON helpers ----------------------------------------------------------

Color _color(Object? v) => Color((v! as num).toInt());

Alignment _align(Object? v) {
  if (v == null) return Alignment.center;
  final List<Object?> l = v as List<Object?>;
  return Alignment((l[0]! as num).toDouble(), (l[1]! as num).toDouble());
}
