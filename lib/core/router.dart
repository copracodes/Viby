import 'package:go_router/go_router.dart';

import '../ui/screens/home_screen.dart';

/// Application route table.
///
/// One placeholder route for now. Add new routes here — screens are never
/// pushed with raw [Navigator] calls, always via named go_router routes.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);
