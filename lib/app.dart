import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/messenger.dart';
import 'core/perf.dart';
import 'core/router.dart';
import 'state/fault_reporter.dart';
import 'state/history_recorder.dart';
import 'state/library_providers.dart';
import 'state/queue_persistence.dart';
import 'state/scan_triggers.dart';
import 'state/theme_providers.dart';
import 'ui/theme/app_background.dart';
import 'ui/theme/app_theme.dart';
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

class _VibyAppState extends ConsumerState<VibyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start logging plays (feeds Home's "recently played").
    ref.read(historyRecorderProvider);
    // Start listening for playback faults (missing / corrupt files) so a bad
    // file is skipped-with-a-message and marked, not a stall.
    ref.read(faultReporterProvider);
    // Start listening for auto-detected new songs (subtle snackbar on Library).
    ref.read(newSongsReporterProvider);
    unawaited(_restoreQueue());
    // Catch music added since the last session (cheap; gated by >5min).
    unawaited(ref.read(libraryScanProvider.notifier).maybeResumeScan());
    // Log time-to-first-frame (profile/debug only).
    WidgetsBinding.instance.addPostFrameCallback((_) => reportColdStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume, pick up any music added while backgrounded (an incremental
    // rescan, skipped if the library was scanned in the last few minutes).
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(libraryScanProvider.notifier).maybeResumeScan());
    }
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

    final ThemeData lightData;
    final ThemeData darkData;
    final ThemeMode themeMode;
    if (settings.systemFollow) {
      lightData = AppTheme.fromVibyTheme(classicLight);
      darkData = AppTheme.fromVibyTheme(
        settings.amoledOverride ? applyAmoled(classicDark) : classicDark,
      );
      themeMode = ThemeMode.system;
    } else {
      final VibyTheme t = resolveActiveTheme(
        selectedId: settings.themeId,
        systemFollow: false,
        platformBrightness: Brightness.dark, // unused when not following
        amoledOverride: settings.amoledOverride,
      );
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
      // No global per-frame theme lerp: a whole-app AnimatedTheme rebuilds Theme
      // every frame, which collides with the Library TabBar's internal
      // AnimatedBuilder (setState-during-build on _TabStyle) when the startup
      // hydration morph lands while Library is mounting. The visible transition
      // is carried by the AppBackground cross-fade (350ms) plus Now Playing's own
      // scoped AnimatedTheme; the app chrome swaps instantly.
      themeAnimationDuration: Duration.zero,
      routerConfig: appRouter,
      // The AppBackground is mounted here (above the Navigator, below all
      // routes), so every transparent-scaffold screen renders over the theme's
      // painted background. Platform brightness is resolved here where a
      // MediaQuery exists.
      builder: (BuildContext context, Widget? child) {
        final VibyTheme active = resolveActiveTheme(
          selectedId: settings.themeId,
          systemFollow: settings.systemFollow,
          platformBrightness: MediaQuery.platformBrightnessOf(context),
          amoledOverride: settings.amoledOverride,
        );
        return AppBackground(
          background: active.background,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
