import 'package:go_router/go_router.dart';

import '../ui/screens/debug_queue_screen.dart';
import '../ui/screens/debug_scan_screen.dart';
import '../ui/screens/home_screen.dart';

/// Application route table.
///
/// Add new routes here — screens are never pushed with raw [Navigator] calls,
/// always via named go_router routes.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';

  /// THROWAWAY debug route for the library scanner (Phase 1.2).
  static const String debugScan = '/debug-scan';

  /// THROWAWAY debug route for the queue engine (Phase 1.3).
  static const String debugQueue = '/debug-queue';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.debugScan,
      name: 'debug-scan',
      builder: (context, state) => const DebugScanScreen(),
    ),
    GoRoute(
      path: AppRoutes.debugQueue,
      name: 'debug-queue',
      builder: (context, state) => const DebugQueueScreen(),
    ),
  ],
);
