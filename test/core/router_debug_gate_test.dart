import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viby/core/router.dart';

/// Walks the whole route tree (shell branches + nested routes) collecting every
/// [GoRoute.path] segment.
List<String> _allPaths(List<RouteBase> routes) {
  final List<String> paths = <String>[];
  for (final RouteBase route in routes) {
    if (route is GoRoute) {
      paths.add(route.path);
      paths.addAll(_allPaths(route.routes));
    } else if (route is ShellRouteBase) {
      if (route is StatefulShellRoute) {
        for (final StatefulShellBranch branch in route.branches) {
          paths.addAll(_allPaths(branch.routes));
        }
      } else {
        paths.addAll(_allPaths(route.routes));
      }
    }
  }
  return paths;
}

void main() {
  test(
      'the debug routes are registered iff kDebugMode — so release/profile '
      'builds (kDebugMode == false) strip them from the route table entirely',
      () {
    final List<String> paths = _allPaths(appRouter.configuration.routes);
    final bool hasDebugRoutes =
        paths.contains('debug-scan') && paths.contains('debug-queue');

    // This single predicate is the gating contract: in this (debug) test run
    // kDebugMode is true and the routes are present; the very same const is
    // false in release/profile, so those builds carry neither route.
    expect(hasDebugRoutes, kDebugMode);

    // The always-on settings sub-routes are unaffected by the gate.
    expect(paths, containsAll(<String>['hidden', 'playback']));
  });
}
