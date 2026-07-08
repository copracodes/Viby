import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/queue_provider.dart';
import '../player/player_overlay.dart';

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

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(child: navigationShell),
              // Reserve the docked mini-bar strip so list content clears it.
              if (hasTrack) const SizedBox(height: PlayerOverlay.miniHeight),
              NavigationBar(
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
            ],
          ),
          const Positioned.fill(child: PlayerOverlay()),
        ],
      ),
    );
  }
}
