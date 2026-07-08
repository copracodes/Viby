/// Viby design tokens — the single source of truth for spacing, radii, motion,
/// elevation policy and the type scale. Screens compose from these instead of
/// hard-coding magic numbers, so the whole app moves together when a token
/// changes. (CLAUDE.md: "theme, don't hard-code".)
///
/// Dark-first: we prefer Material 3 *surface tint* over drop shadows (see
/// [Elevations]).
library;

import 'package:flutter/material.dart';

/// Spacing on a strict 4pt grid. Use these for padding, gaps and insets.
abstract final class Spacing {
  /// 4 — hairline gaps, icon-to-label.
  static const double xs = 4;

  /// 8 — tight padding, chip gaps.
  static const double sm = 8;

  /// 12 — default gap between related elements.
  static const double md = 12;

  /// 16 — standard screen / list padding.
  static const double lg = 16;

  /// 24 — section spacing, comfortable screen margins.
  static const double xl = 24;

  /// 32 — large blocks, hero spacing.
  static const double xxl = 32;

  /// 48 — oversized separation (empty states).
  static const double xxxl = 48;
}

/// Corner radii. [full] is an effectively-pill radius for stadium shapes.
abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double full = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brFull = BorderRadius.all(Radius.circular(full));
}

/// Motion tokens. Durations pair with curves: entrances decelerate, exits
/// accelerate, in-place changes use [standard].
abstract final class Motion {
  /// 150ms — small, immediate feedback (ripples, toggles).
  static const Duration fast = Duration(milliseconds: 150);

  /// 250ms — the default transition.
  static const Duration base = Duration(milliseconds: 250);

  /// 400ms — large/emphasized moves (hero, sheets).
  static const Duration emphasized = Duration(milliseconds: 400);

  /// 350ms — the dynamic-theme colour morph between tracks.
  static const Duration themeMorph = Duration(milliseconds: 350);

  /// General-purpose easing for in-place changes (M3 "standard").
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// For elements entering the screen (M3 "emphasized decelerate").
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// For elements leaving the screen (M3 "emphasized accelerate").
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
}

/// Elevation policy. Dark-first, so we lean on Material 3 surface *tint*
/// (tonal elevation) and keep real shadows minimal. These are the tonal
/// elevation values (dp) fed to `Material.elevation` / surface containers, not
/// shadow depths.
abstract final class Elevations {
  /// Flat — scaffolds, most content.
  static const double level0 = 0;

  /// Resting cards, the mini-player.
  static const double level1 = 1;

  /// Menus, raised affordances.
  static const double level2 = 3;

  /// Sheets, dialogs.
  static const double level3 = 6;
}

/// The Viby type scale. Sizes/weights live here; [textTheme] materialises them
/// into a [TextTheme] applied by `AppTheme`. Weights lean slightly heavier than
/// the M3 default for a more "premium player" feel on dark surfaces.
abstract final class VibyType {
  static const String? fontFamily = null; // system default (Roboto / SF).

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Builds the app [TextTheme] for a given [brightness]. Colour is left to the
  /// [ColorScheme] (applied downstream); this fixes size / weight / height only.
  static TextTheme textTheme() {
    const double h = 1.2; // display/headline line-height ratio
    const double b = 1.35; // body line-height ratio
    return const TextTheme(
      displayLarge: TextStyle(fontSize: 57, height: h, fontWeight: bold),
      displayMedium: TextStyle(fontSize: 45, height: h, fontWeight: bold),
      displaySmall: TextStyle(fontSize: 36, height: h, fontWeight: semibold),
      headlineLarge: TextStyle(fontSize: 32, height: h, fontWeight: semibold),
      headlineMedium: TextStyle(fontSize: 28, height: h, fontWeight: semibold),
      headlineSmall: TextStyle(fontSize: 24, height: h, fontWeight: semibold),
      titleLarge: TextStyle(fontSize: 22, height: 1.27, fontWeight: semibold),
      titleMedium:
          TextStyle(fontSize: 16, height: 1.5, fontWeight: medium, letterSpacing: 0.15),
      titleSmall:
          TextStyle(fontSize: 14, height: 1.43, fontWeight: medium, letterSpacing: 0.1),
      bodyLarge: TextStyle(fontSize: 16, height: b, fontWeight: regular),
      bodyMedium: TextStyle(fontSize: 14, height: b, fontWeight: regular),
      bodySmall:
          TextStyle(fontSize: 12, height: 1.33, fontWeight: regular, letterSpacing: 0.4),
      labelLarge:
          TextStyle(fontSize: 14, height: 1.43, fontWeight: medium, letterSpacing: 0.1),
      labelMedium:
          TextStyle(fontSize: 12, height: 1.33, fontWeight: medium, letterSpacing: 0.5),
      labelSmall:
          TextStyle(fontSize: 11, height: 1.45, fontWeight: medium, letterSpacing: 0.5),
    );
  }
}
