import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/theme_providers.dart';
import 'app_theme.dart';
import 'theme_collection.dart';
import 'tokens.dart';
import 'viby_theme.dart';

/// Wraps [child] in a theme seeded by the currently-playing track's artwork,
/// animating between schemes as the track changes.
///
/// This is scoped, not global: only the now-playing surfaces (Now Playing +
/// mini-player) opt in, so Library/Home stay on the calm base theme (see
/// CLAUDE.md). The seed only swaps the accent when the *active theme*
/// [VibyTheme.acceptsDynamicSeed] (Classic + Onyx) — gradient/aurora themes keep
/// their locked identity — via [effectiveScheme]. Colour lerps over
/// [Motion.themeMorph].
class DynamicThemeScope extends ConsumerWidget {
  const DynamicThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
    final Color? seed = ref.watch(currentSeedProvider).valueOrNull;

    final VibyTheme theme = resolveActiveTheme(
      selectedId: settings.themeId,
      systemFollow: settings.systemFollow,
      platformBrightness: MediaQuery.platformBrightnessOf(context),
      amoledOverride: settings.amoledOverride,
    );
    final ColorScheme scheme = effectiveScheme(
      theme,
      seed: seed,
      dynamicColor: settings.dynamicColor,
    );

    return AnimatedTheme(
      data: AppTheme.fromVibyTheme(theme, scheme: scheme),
      duration: Motion.themeMorph,
      curve: Motion.standard,
      child: child,
    );
  }
}
