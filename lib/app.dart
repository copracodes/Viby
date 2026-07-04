import 'package:flutter/material.dart';

import 'core/router.dart';
import 'ui/theme/app_theme.dart';

/// Root application widget.
///
/// Wires the Material 3 theme and go_router together. Deliberately thin — no
/// business logic lives here.
class ResonanceApp extends StatelessWidget {
  const ResonanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Resonance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
