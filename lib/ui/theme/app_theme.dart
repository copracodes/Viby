import 'package:flutter/material.dart';

import 'dynamic_theme.dart';
import 'theme_collection.dart';
import 'tokens.dart';
import 'viby_theme.dart';

/// Central Material 3 theme for Viby.
///
/// Colour comes from a [ColorScheme] (a [VibyTheme]'s scheme, or an album-art
/// seed via the dynamic theme); typography / shape / motion come from the design
/// [tokens]. Screens read `Theme.of(context)` and never hard-code.
///
/// Since Step 3.2 the theme is *transparent over an [AppBackground]*: the
/// scaffold, app bar and (glass/gradient themes') surfaces let the painted
/// background show through. Surface rendering is driven by the theme's
/// [SurfaceSpec].
class AppTheme {
  const AppTheme._();

  /// Brand seed colour — the static purple.
  static const Color seed = kBrandSeed;

  // Classic wrappers (used by app wiring + tests). Route through the collection
  // so there is one definition of the Classic themes.
  static ThemeData light() => fromVibyTheme(classicLight);
  static ThemeData dark() => fromVibyTheme(classicDark);
  static ThemeData amoled() => fromVibyTheme(applyAmoled(classicDark));

  /// Builds [ThemeData] for a [theme], optionally overriding its [scheme] (the
  /// dynamic-colour path passes an artwork-seeded scheme). This is the one place
  /// theme shape is assembled, so every theme is structurally identical — only
  /// colours + surface rendering differ.
  static ThemeData fromVibyTheme(VibyTheme theme, {ColorScheme? scheme}) =>
      _build(scheme ?? theme.scheme, theme.surface);

  /// Legacy entry: build from a bare scheme with opaque surfaces (kept for the
  /// dynamic-theme scope, which supplies its own surface spec via
  /// [fromVibyTheme]). Retained for backward compatibility.
  static ThemeData fromScheme(ColorScheme scheme) =>
      _build(scheme, const OpaqueSurface());

  static ThemeData _build(ColorScheme scheme, SurfaceSpec surface) {
    final Color cardColor = _surfaceColor(scheme, surface);
    final BorderSide cardBorder = _surfaceBorder(scheme, surface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Transparent so the AppBackground shows through (Step 3.2).
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: VibyType.textTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      // Dark-first elevation policy: lean on M3 surface tint, keep shadows off.
      cardTheme: CardThemeData(
        elevation: Elevations.level1,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.brMd,
          side: cardBorder,
        ),
      ),
      // Nav bar is transparent here; the shell wraps it in the theme's surface
      // (glass panel or a tinted container) so at most one live blur is on
      // screen for the nav.
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _sheetColor(scheme, surface),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _sheetColor(scheme, surface),
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        // Dialogs sit over a scrim and must stay crisply readable — keep them
        // opaque even under glass themes.
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.brLg),
      ),
      // Classic ink ripple (InkSparkle's runtime shader fails on this device /
      // in tests).
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// The fill for cards, derived from the [SurfaceSpec]. Glass cards *fake* the
  /// frosted look with a translucent tint (no per-card blur — see the perf
  /// budget in CLAUDE.md); real blur is reserved for the nav + active sheet.
  static Color _surfaceColor(ColorScheme scheme, SurfaceSpec surface) {
    return switch (surface) {
      OpaqueSurface() => scheme.surfaceContainer,
      TintedSurface(:final double alpha) =>
        scheme.surfaceContainerHigh.withValues(alpha: alpha),
      GlassSurface(:final double tintAlpha) =>
        scheme.surfaceContainerHigh.withValues(alpha: tintAlpha),
    };
  }

  static Color _sheetColor(ColorScheme scheme, SurfaceSpec surface) {
    return switch (surface) {
      OpaqueSurface() => scheme.surfaceContainer,
      TintedSurface(:final double alpha) =>
        scheme.surfaceContainer.withValues(alpha: (alpha + 0.15).clamp(0, 1)),
      GlassSurface(:final double tintAlpha) =>
        scheme.surfaceContainer.withValues(alpha: (tintAlpha + 0.2).clamp(0, 1)),
    };
  }

  /// The hairline border that sells "glass"/tinted surfaces (a 1px light edge).
  static BorderSide _surfaceBorder(ColorScheme scheme, SurfaceSpec surface) {
    return switch (surface) {
      OpaqueSurface() => BorderSide.none,
      TintedSurface() =>
        BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      GlassSurface(:final double borderAlpha) =>
        BorderSide(color: scheme.onSurface.withValues(alpha: borderAlpha)),
    };
  }
}
