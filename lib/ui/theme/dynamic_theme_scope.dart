import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/theme_providers.dart';
import 'app_theme.dart';
import 'dynamic_theme.dart';
import 'tokens.dart';

/// Wraps [child] in a theme seeded by the currently-playing track's artwork,
/// animating between schemes as the track changes.
///
/// This is scoped, not global: only the now-playing surfaces (Now Playing +
/// mini-player) opt in, so Library/Home stay on the calm base theme rather than
/// strobing colour with every track (see CLAUDE.md). Colour lerps over
/// [Motion.themeMorph] via [AnimatedTheme] (which uses `ThemeData.lerp` →
/// `ColorScheme.lerp`, the correct per-channel interpolation).
class DynamicThemeScope extends ConsumerWidget {
  const DynamicThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
    final Color? seed = ref.watch(currentSeedProvider).valueOrNull;
    final Color effectiveSeed = seed ?? kBrandSeed;

    final Brightness brightness = _brightnessFor(context, settings.mode);
    final ColorScheme scheme = schemeFromSeed(
      effectiveSeed,
      brightness: brightness,
      amoled: settings.mode == VibyThemeMode.amoled,
    );

    return AnimatedTheme(
      data: AppTheme.fromScheme(scheme),
      duration: Motion.themeMorph,
      curve: Motion.standard,
      child: child,
    );
  }

  Brightness _brightnessFor(BuildContext context, VibyThemeMode mode) {
    switch (mode) {
      case VibyThemeMode.system:
        return MediaQuery.platformBrightnessOf(context);
      case VibyThemeMode.light:
        return Brightness.light;
      case VibyThemeMode.dark:
      case VibyThemeMode.amoled:
        return Brightness.dark;
    }
  }
}
