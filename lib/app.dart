import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/messenger.dart';
import 'core/router.dart';
import 'state/fault_reporter.dart';
import 'state/history_recorder.dart';
import 'state/queue_persistence.dart';
import 'ui/theme/app_theme.dart';

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
    return MaterialApp.router(
      title: 'Viby',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
