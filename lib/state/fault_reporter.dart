import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/playback_fault.dart';
import '../core/messenger.dart';
import 'database_providers.dart';
import 'player_providers.dart';

part 'fault_reporter.g.dart';

/// Reacts to playback faults (missing / corrupt files): marks the offending
/// track unplayable in the DB and shows a brief SnackBar. The handler has
/// already skipped past it (or stopped if the whole queue failed).
///
/// keepAlive and read once at app start — it must be listening before the first
/// track plays. Uses [rootMessengerKey] so it needs no BuildContext.
@Riverpod(keepAlive: true)
FaultReporter faultReporter(Ref ref) {
  final FaultReporter reporter = FaultReporter(
    markUnplayable: (String id) => ref
        .read(vibyDatabaseProvider)
        .libraryDao
        .setTrackPlayable(id, false),
  );
  ref.listen<AsyncValue<PlaybackFault>>(
    playbackFaultsProvider,
    (_, AsyncValue<PlaybackFault> next) {
      final PlaybackFault? fault = next.valueOrNull;
      if (fault != null) reporter.onFault(fault);
    },
  );
  return reporter;
}

/// Testable core of the reporter (no Riverpod): [showMessage] and
/// [markUnplayable] are injected so a test can assert both without a real
/// database or messenger.
class FaultReporter {
  FaultReporter({
    required this.markUnplayable,
    void Function(String message)? showMessage,
  }) : _showMessage = showMessage ?? _defaultShowMessage;

  final Future<void> Function(String trackId) markUnplayable;
  final void Function(String message) _showMessage;

  void onFault(PlaybackFault fault) {
    final String id = fault.trackId ?? '';
    if (id.isNotEmpty) markUnplayable(id);
    final String name = (fault.title == null || fault.title!.isEmpty)
        ? 'this track'
        : fault.title!;
    _showMessage(
      fault.allFailed
          ? "Couldn't play $name — nothing else in the queue could play either."
          : "Couldn't play $name — skipped.",
    );
  }

  static void _defaultShowMessage(String message) {
    final ScaffoldMessengerState? messenger = rootMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }
}
