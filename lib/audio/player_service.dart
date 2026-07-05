import 'dart:async';

import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'audio_handler.dart';

/// Playback processing state, expressed as a Viby-domain enum so that UI and
/// state layers can react to it without importing just_audio / audio_service
/// (forbidden by the architecture rules in CLAUDE.md).
enum VibyProcessingState {
  /// No source loaded / nothing to play.
  idle,

  /// Loading the audio source.
  loading,

  /// Rebuffering during playback.
  buffering,

  /// Loaded and able to play (playing or paused).
  ready,

  /// Reached the end of the current source.
  completed,
}

VibyProcessingState _mapProcessingState(ProcessingState state) {
  switch (state) {
    case ProcessingState.idle:
      return VibyProcessingState.idle;
    case ProcessingState.loading:
      return VibyProcessingState.loading;
    case ProcessingState.buffering:
      return VibyProcessingState.buffering;
    case ProcessingState.ready:
      return VibyProcessingState.ready;
    case ProcessingState.completed:
      return VibyProcessingState.completed;
  }
}

/// The single playback entry point for the whole app.
///
/// Per CLAUDE.md this is the ONLY class the UI / state layers may import for
/// playback: it hides just_audio, audio_service and audio_session behind a
/// small surface of methods and streams. It delegates transport to the
/// [VibyAudioHandler] (which owns the OS media session) and shapes the handler's
/// raw streams for consumption (throttling position, mapping to domain types).
class PlayerService {
  PlayerService(this._handler);

  final VibyAudioHandler _handler;

  // --- Transport ---

  Future<void> play() => _handler.play();

  Future<void> pause() => _handler.pause();

  Future<void> seek(Duration position) => _handler.seek(position);

  // --- Streams ---

  /// Current playback position, throttled to at most one event per 200ms so
  /// the UI (slider / position label) rebuilds at a sane cadence.
  Stream<Duration> get position =>
      _throttleTrailing(_handler.positionStream, const Duration(milliseconds: 200));

  /// Duration of the loaded track; null until the source is decoded.
  Stream<Duration?> get duration => _handler.durationStream;

  /// Whether audio is currently playing (as opposed to paused / stopped).
  Stream<bool> get playing => _handler.playingStream;

  /// The processing state, as a Viby-domain enum.
  Stream<VibyProcessingState> get processingState =>
      _handler.processingStateStream.map(_mapProcessingState);

  /// Releases underlying resources. In practice the handler lives for the whole
  /// app session, so this is mainly for symmetry / tests.
  Future<void> dispose() => _handler.dispose();
}

/// Emits the first event immediately, then forwards at most one event per
/// [interval], always carrying the most recent value observed during a window
/// (trailing edge). Unlike a periodic sampler this stays silent when the source
/// is silent, and never drops the final value of a burst.
Stream<T> _throttleTrailing<T>(Stream<T> source, Duration interval) {
  final StreamController<T> controller = StreamController<T>();
  StreamSubscription<T>? subscription;
  Timer? timer;
  late T latest;
  bool hasPending = false;

  void openWindow(T value) {
    controller.add(value);
    timer = Timer(interval, () {
      timer = null;
      if (hasPending) {
        hasPending = false;
        openWindow(latest);
      }
    });
  }

  controller.onListen = () {
    subscription = source.listen(
      (T event) {
        if (timer == null) {
          openWindow(event);
        } else {
          latest = event;
          hasPending = true;
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );
  };
  controller.onCancel = () {
    timer?.cancel();
    timer = null;
    final StreamSubscription<T>? sub = subscription;
    subscription = null;
    return sub?.cancel();
  };

  return controller.stream;
}
