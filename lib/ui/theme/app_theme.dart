import 'package:flutter/material.dart';

/// Central Material 3 theme for Viby.
///
/// Keep all colour / typography decisions here — screens and widgets should
/// read from `Theme.of(context)`, never hard-code colours.
class AppTheme {
  const AppTheme._();

  /// Seed colour the Material 3 [ColorScheme] is derived from.
  static const Color _seed = Color(0xFF7C4DFF);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // Use the classic ink ripple rather than Material 3's default InkSparkle:
      // InkSparkle needs a runtime shader (`ink_sparkle.frag`) that fails to load
      // on this device's Vulkan driver and in widget tests. InkRipple looks
      // nearly identical and is shader-free.
      splashFactory: InkRipple.splashFactory,
    );
  }
}
