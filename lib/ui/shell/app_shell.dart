import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/queue_provider.dart';
import '../../state/theme_providers.dart';
import '../player/player_overlay.dart';
import '../theme/glass_panel.dart';
import '../theme/theme_collection.dart';
import '../theme/viby_theme.dart';

/// The app shell: bottom navigation across Home / Library / Search / Settings
/// with the unified [PlayerOverlay] floating above it.
///
/// The overlay is the mini-player when collapsed and full-screen Now Playing
/// when expanded — one continuous interactive transition. It's a `Positioned.fill`
/// sibling above the nav column; while collapsed it only occupies the mini-bar
/// strip, so the shell stays interactive. The column reserves that strip's
/// height (when something is playing) so content isn't hidden behind it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestination(int index) {
    // Tapping the active tab again pops it back to its root.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasTrack = ref.watch(
      queueControllerProvider.select((QueueState q) => q.currentTrack != null),
    );

    final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
    final VibyTheme theme = resolveActiveTheme(
      selectedId: settings.themeId,
      systemFollow: settings.systemFollow,
      platformBrightness: MediaQuery.platformBrightnessOf(context),
      amoledOverride: settings.amoledOverride,
    );

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(child: navigationShell),
              // Reserve the docked mini-bar strip so list content clears it.
              if (hasTrack) const SizedBox(height: PlayerOverlay.miniHeight),
              _NavSurface(
                surface: theme.surface,
                scheme: Theme.of(context).colorScheme,
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _onDestination,
                  destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                  ],
                ),
              ),
            ],
          ),
          const Positioned.fill(child: PlayerOverlay()),
        ],
      ),
    );
  }
}

/// Renders the nav bar's surface per the active theme's [SurfaceSpec]: a real
/// glass blur (the one budgeted always-on live filter), a translucent tint, or
/// an opaque container.
class _NavSurface extends StatelessWidget {
  const _NavSurface({
    required this.surface,
    required this.scheme,
    required this.child,
  });

  final SurfaceSpec surface;
  final ColorScheme scheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    switch (surface) {
      case GlassSurface(:final double blurSigma, :final double tintAlpha, :final double borderAlpha):
        return GlassPanel(
          blurSigma: blurSigma,
          tint: scheme.surfaceContainer.withValues(alpha: tintAlpha),
          borderColor: scheme.onSurface.withValues(alpha: borderAlpha),
          child: child,
        );
      case TintedSurface(:final double alpha):
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer
                .withValues(alpha: (alpha + 0.05).clamp(0, 1)),
            border: Border(
              top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
            ),
          ),
          child: child,
        );
      case OpaqueSurface():
        return ColoredBox(color: scheme.surfaceContainer, child: child);
    }
  }
}
