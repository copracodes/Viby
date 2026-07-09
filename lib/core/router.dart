import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/screens/album_detail_screen.dart';
import '../ui/screens/artist_detail_screen.dart';
import '../ui/screens/debug_queue_screen.dart';
import '../ui/screens/debug_scan_screen.dart';
import '../ui/screens/eq_screen.dart';
import '../ui/screens/hidden_songs_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/liked_songs_screen.dart';
import '../ui/screens/library_screen.dart';
import '../ui/screens/playlist_detail_screen.dart';
import '../ui/screens/search_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/shell/app_shell.dart';

/// Application route table.
///
/// A [StatefulShellRoute] gives each bottom-nav tab its own navigation stack
/// (so deep links within Library survive tab switches). Album/artist detail
/// nest under Library, keeping the nav bar + mini-player. Now Playing is a
/// root route so it covers the shell full-screen. Debug tools live under
/// Settings › Developer.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/home';
  static const String library = '/library';
  static const String search = '/search';
  static const String settings = '/settings';

  /// Equalizer — a root route so it covers the shell full-screen. Opened from
  /// Settings › Audio and the Now Playing overflow.
  static const String eq = '/eq';

  /// Hidden songs manager (Settings › Library).
  static const String hidden = '/settings/hidden';

  /// The virtual Liked Songs collection (under the Library tab).
  static const String liked = '/library/liked';

  /// THROWAWAY debug routes (Phase 1.2 / 1.3), now under Settings › Developer.
  static const String debugScan = '/settings/debug-scan';
  static const String debugQueue = '/settings/debug-queue';

  static String album(String id) => '/library/album/$id';
  static String artist(String id) => '/library/artist/$id';
  static String playlist(String id) => '/library/playlist/$id';
}

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.eq,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) => const EqScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (
        BuildContext context,
        GoRouterState state,
        StatefulNavigationShell navigationShell,
      ) =>
          AppShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (BuildContext context, GoRouterState state) =>
                  const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.library,
              builder: (BuildContext context, GoRouterState state) =>
                  const LibraryScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'album/:id',
                  builder: (BuildContext context, GoRouterState state) =>
                      AlbumDetailScreen(albumId: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'artist/:id',
                  builder: (BuildContext context, GoRouterState state) =>
                      ArtistDetailScreen(
                        artistId: state.pathParameters['id']!,
                      ),
                ),
                GoRoute(
                  path: 'playlist/:id',
                  builder: (BuildContext context, GoRouterState state) =>
                      PlaylistDetailScreen(
                        playlistId: state.pathParameters['id']!,
                      ),
                ),
                GoRoute(
                  path: 'liked',
                  builder: (BuildContext context, GoRouterState state) =>
                      const LikedSongsScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.search,
              builder: (BuildContext context, GoRouterState state) =>
                  const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.settings,
              builder: (BuildContext context, GoRouterState state) =>
                  const SettingsScreen(),
              // Throwaway debug tools — registered in non-release builds only
              // (debug + profile, so the profile perf pass can reach them), so
              // they (and their screens) are tree-shaken out of release.
              routes: <RouteBase>[
                GoRoute(
                  path: 'hidden',
                  builder: (BuildContext context, GoRouterState state) =>
                      const HiddenSongsScreen(),
                ),
                if (!kReleaseMode)
                  GoRoute(
                    path: 'debug-scan',
                    builder: (BuildContext context, GoRouterState state) =>
                        const DebugScanScreen(),
                  ),
                if (!kReleaseMode)
                  GoRoute(
                    path: 'debug-queue',
                    builder: (BuildContext context, GoRouterState state) =>
                        const DebugQueueScreen(),
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
