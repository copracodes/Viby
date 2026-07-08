import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/eq_service.dart';
import '../audio/eq_state.dart';
import '../data/db/viby_database.dart' show EqPresetRow;
import 'database_providers.dart';

part 'eq_providers.g.dart';

/// The platform EQ engine (effects + pipeline), built in `main()` before the
/// player and injected via override. This body only runs if the override is
/// missing (a wiring bug), so it throws loudly.
@Riverpod(keepAlive: true)
EqEngine eqEngine(Ref ref) {
  throw UnimplementedError(
    'eqEngineProvider must be overridden in main() with EqEngine.build().',
  );
}

/// The app-wide [EqService]: the real [PlatformEqService] where the engine is
/// capable, else a [NoopEqService]. Restores persisted settings on creation
/// (before first playback) and disposes with the app.
@Riverpod(keepAlive: true)
EqService eqService(Ref ref) {
  final EqEngine engine = ref.watch(eqEngineProvider);
  final EqService service = engine.capable
      ? PlatformEqService(engine, ref.watch(vibyDatabaseProvider).eqDao)
      : NoopEqService();
  unawaited(service.restore());
  ref.onDispose(service.dispose);
  return service;
}

/// The reactive equalizer state for the UI. Yields the service's current
/// snapshot first (so the first frame renders without waiting for the stream),
/// then follows live changes.
@riverpod
Stream<EqRuntimeState> eqState(Ref ref) async* {
  final EqService service = ref.watch(eqServiceProvider);
  yield service.state;
  yield* service.stateStream;
}

/// The user's saved custom presets (newest first), straight from the DAO.
@riverpod
Stream<List<EqPresetRow>> customEqPresets(Ref ref) =>
    ref.watch(vibyDatabaseProvider).eqDao.watchCustomPresets();
