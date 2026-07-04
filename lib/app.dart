import 'package:flutter/material.dart';

import 'core/router.dart';
import 'ui/theme/app_theme.dart';

/// Root application widget.
///
/// Wires the Material 3 theme and go_router together. Deliberately thin — no
/// business logic lives here.
class VibyApp extends StatelessWidget {
  const VibyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Viby',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
