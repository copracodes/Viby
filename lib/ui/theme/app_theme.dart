import 'package:flutter/material.dart';

import 'dynamic_theme.dart';
import 'tokens.dart';

/// Central Material 3 theme for Viby.
///
/// Colour comes from a [ColorScheme] (brand seed by default, or an album-art
/// seed via the dynamic theme); typography / shape / motion come from the
/// design [tokens]. Screens read `Theme.of(context)` and never hard-code.
class AppTheme {
  const AppTheme._();

  /// Brand seed colour — the static purple.
  static const Color seed = kBrandSeed;

  static ThemeData light() =>
      fromScheme(schemeFromSeed(seed, brightness: Brightness.light));

  static ThemeData dark() =>
      fromScheme(schemeFromSeed(seed, brightness: Brightness.dark));

  /// Pure-black dark variant for OLED screens.
  static ThemeData amoled() => fromScheme(
        schemeFromSeed(seed, brightness: Brightness.dark, amoled: true),
      );

  /// Builds the full [ThemeData] for a [scheme]. This is the one place theme
  /// shape is assembled, so the brand theme and the dynamic album-art theme are
  /// always structurally identical — only the colours differ.
  static ThemeData fromScheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: VibyType.textTheme(),
      // Dark-first elevation policy: lean on M3 surface tint, keep shadows off.
      cardTheme: const CardThemeData(
        elevation: Elevations.level1,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.brMd),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: Radii.brLg),
      ),
      // Use the classic ink ripple rather than Material 3's default InkSparkle:
      // InkSparkle needs a runtime shader (`ink_sparkle.frag`) that fails to load
      // on this device's Vulkan driver and in widget tests. InkRipple looks
      // nearly identical and is shader-free.
      splashFactory: InkRipple.splashFactory,
    );
  }
}
