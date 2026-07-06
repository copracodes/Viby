import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
