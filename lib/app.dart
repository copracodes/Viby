import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/messenger.dart';
import 'core/perf.dart';
import 'core/router.dart';
import 'state/fault_reporter.dart';
import 'state/history_recorder.dart';
import 'state/queue_persistence.dart';
import 'state/theme_providers.dart';
import 'ui/theme/app_background.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/dynamic_theme.dart';
import 'ui/theme/theme_collection.dart';
import 'ui/theme/viby_theme.dart';

/// Root application widget.
///
/// Wires the Material 3 theme and go_router together, and kicks off a one-time
/// queue restore on launch. Deliberately thin — no business logic lives here.
class VibyApp extends ConsumerStatefulWidget {
  const VibyApp({super.key});

  @override
  ConsumerState<VibyApp> createState() => _VibyAppState();
}

class _VibyAppState extends ConsumerState<VibyApp> {
  @override
  void initState() {
    super.initState();
    // Start logging plays (feeds Home's "recently played").
    ref.read(historyRecorderProvider);
    // Start listening for playback faults (missing / corrupt files) so a bad
    // file is skipped-with-a-message and marked, not a stall.
    ref.read(faultReporterProvider);
    unawaited(_restoreQueue());
    // Log time-to-first-frame (profile/debug only).
    WidgetsBinding.instance.addPostFrameCallback((_) => reportColdStart());
  }

  /// Cold-start: rebuild the last queue (paused, seeked to the saved position)
  /// and start checkpointing. Guarded — a restore failure (corrupt state, a
  /// wiring gap in tests) must never block the app from booting.
  Future<void> _restoreQueue() async {
    try {
      await ref.read(queuePersistenceProvider).restore();
    } catch (e, st) {
      developer.log('queue restore failed', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeSettingsState settings = ref.watch(themeSettingsProvider);
    final VibyThemeMode mode = settings.mode;
    final bool amoled = mode == VibyThemeMode.amoled;

    final ThemeData lightData;
    final ThemeData darkData;
    final ThemeMode themeMode;
    if (mode == VibyThemeMode.system) {
      lightData = AppTheme.fromVibyTheme(classicLight);
      darkData = AppTheme.fromVibyTheme(classicDark);
      themeMode = ThemeMode.system;
    } else {
      final VibyTheme t = themeForMode(mode, Brightness.dark, amoled: amoled);
      lightData = darkData = AppTheme.fromVibyTheme(t);
      themeMode = t.isDark ? ThemeMode.dark : ThemeMode.light;
    }

    return MaterialApp.router(
      title: 'Viby',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: lightData,
      darkTheme: darkData,
      themeMode: themeMode,
      routerConfig: appRouter,
      // The AppBackground is mounted here (above the Navigator, below all
      // routes), so every transparent-scaffold screen renders over the theme's
      // painted background. Platform brightness is resolved here where a
      // MediaQuery exists.
      builder: (BuildContext context, Widget? child) {
        final Brightness platform = MediaQuery.platformBrightnessOf(context);
        final VibyTheme active = themeForMode(mode, platform, amoled: amoled);
        return AppBackground(
          background: active.background,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
