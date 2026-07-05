import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/player_service.dart';

part 'player_providers.g.dart';

/// Holds the app-wide [PlayerService].
///
/// The real instance is created in `main()` after `AudioService.init()` (it
/// needs the initialised audio handler), then injected via an override on the
/// root `ProviderScope`. This body only runs if that override is missing —
/// which would be a wiring bug — so it throws loudly.
@Riverpod(keepAlive: true)
PlayerService playerService(Ref ref) {
  throw UnimplementedError(
    'playerServiceProvider must be overridden in main() with the instance '
    'built from AudioService.init().',
  );
}

/// Whether audio is currently playing. Drives the play/pause button.
@riverpod
Stream<bool> playing(Ref ref) =>
    ref.watch(playerServiceProvider).playing;

/// Current playback position (throttled to 200ms by the service).
@riverpod
Stream<Duration> position(Ref ref) =>
    ref.watch(playerServiceProvider).position;

/// Duration of the loaded track; null until the source is decoded.
@riverpod
Stream<Duration?> trackDuration(Ref ref) =>
    ref.watch(playerServiceProvider).duration;

/// Processing state as a Viby-domain enum (no just_audio types leak to UI).
@riverpod
Stream<VibyProcessingState> processingState(Ref ref) =>
    ref.watch(playerServiceProvider).processingState;
